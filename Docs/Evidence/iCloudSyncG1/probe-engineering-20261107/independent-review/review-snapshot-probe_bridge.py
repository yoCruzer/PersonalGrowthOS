#!/usr/bin/env python3
"""Temporary loopback-only transport for synthetic SyncLab commands.

No shell execution, device control, credentials, product paths, or cloud APIs.
The signed app separately validates commands and owns its sandboxed test store.
"""
import argparse
import hmac
import hashlib
import http.server
import json
import os
from pathlib import Path
import re
import secrets
import threading

LIMIT = 32_000_000


def valid_id(value):
    return isinstance(value, str) and re.fullmatch(r'probe-[A-Za-z0-9_-]{1,74}', value) is not None


class Bridge(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, root, dataset, run_id):
        if not re.fullmatch(r'synthetic-g1-[A-Za-z0-9_-]{1,67}', dataset) or not valid_id(run_id):
            raise ValueError('invalid synthetic run identity')
        self.dataset = dataset
        self.run_id = run_id
        self.root = Path(root)
        self.root.mkdir(mode=0o700, parents=True, exist_ok=True)
        for name in ('requests', 'results'):
            (self.root / name).mkdir(mode=0o700, exist_ok=True)
        self.token = secrets.token_hex(32)
        self.lock = threading.Lock()
        super().__init__(('127.0.0.1', 0), Handler)

    def pending(self):
        for path in sorted((self.root / 'requests').glob('probe-*.json')):
            if path.is_symlink() or not valid_id(path.stem):
                continue
            if not (self.root / 'results' / path.name).exists():
                data = path.read_bytes()
                if len(data) > 65_536:
                    raise ValueError('command too large')
                command = json.loads(data)
                if command.get('id') != path.stem:
                    raise ValueError('command identity mismatch')
                return data
        return b''


class Handler(http.server.BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(15)

    def log_message(self, *args):
        pass  # Never print authorization headers or private result fingerprints.

    def reply(self, status, data=b''):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def authorized(self):
        return hmac.compare_digest(self.headers.get('Authorization', ''), 'Bearer ' + self.server.token)

    def do_GET(self):
        if not self.authorized():
            self.reply(403); return
        if self.path != '/next':
            self.reply(404); return
        try:
            with self.server.lock:
                data = self.server.pending()
            self.reply(200, data)
        except (ValueError, OSError):
            self.reply(409)

    def do_POST(self):
        if not self.authorized():
            self.reply(403); return
        if self.path != '/result':
            self.reply(404); return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= LIMIT:
                self.reply(413); return
            data = self.rfile.read(length)
            result = json.loads(data)
            if not isinstance(result, dict) or not valid_id(result.get('id')) or result.get('status') not in ('PASS', 'FAIL'):
                self.reply(400); return
            with self.server.lock:
                name = result['id'] + '.json'
                if not (self.server.root / 'requests' / name).is_file():
                    self.reply(409); return
                command = (self.server.root / 'requests' / name).read_bytes()
                if (result.get('dataset') != self.server.dataset or result.get('runID') != self.server.run_id
                        or result.get('commandDigest') != hashlib.sha256(command).hexdigest()):
                    self.reply(409); return
                target = self.server.root / 'results' / name
                if target.exists():
                    # A lost HTTP response can cause a retry, never overwrite evidence.
                    self.reply(200 if target.read_bytes() == data else 409); return
                temporary = target.with_suffix('.' + secrets.token_hex(8) + '.tmp')
                try:
                    with temporary.open('xb') as output:
                        output.write(data); output.flush(); os.fsync(output.fileno())
                    os.link(temporary, target)  # Atomic publish; never replace prior evidence.
                finally:
                    temporary.unlink(missing_ok=True)
            self.reply(200)
        except (ValueError, OSError):
            self.reply(400)


def enqueue(root, source):
    data = Path(source).read_bytes()
    command = json.loads(data)
    if len(data) > 65_536 or not isinstance(command, dict) or not valid_id(command.get('id')):
        raise ValueError('invalid command identity/size')
    if command.get('action') not in ('connect', 'save', 'sync', 'snapshot', 'reopen', 'stop'):
        raise ValueError('unsupported action')
    target = Path(root) / 'requests' / (command['id'] + '.json')
    with target.open('xb') as output:
        output.write(data)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['serve', 'enqueue'])
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--command', type=Path)
    parser.add_argument('--dataset')
    parser.add_argument('--run-id')
    args = parser.parse_args()
    os.umask(0o077)
    if args.action == 'enqueue':
        enqueue(args.root, args.command); return
    server = Bridge(args.root, args.dataset, args.run_id)
    config = {'address': 'http://127.0.0.1:' + str(server.server_port), 'token': server.token,
              'dataset': server.dataset, 'runID': server.run_id}
    (args.root / 'connection-private.json').write_text(json.dumps(config))
    print('Loopback synthetic bridge ready', flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()


if __name__ == '__main__':
    main()
