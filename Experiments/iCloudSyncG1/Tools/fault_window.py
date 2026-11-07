#!/usr/bin/env python3
"""Fixed-plan Mac runner, invoked by Owner in the dedicated GUI test user.

No account/network setting changes. Does not control iPhone, log in, erase,
re-sign, download, or execute commands supplied by JSON. Plan files authorize
nothing until this launcher is explicitly run in the designated user.
"""
import argparse
import hashlib
import json
import os
import re
import stat
from pathlib import Path
import subprocess
import time
import uuid


def sha(data):
    return hashlib.sha256(data).hexdigest()


def read_regular(path, limit=32000000):
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
            raise ValueError('Expected bounded regular file')
        with os.fdopen(fd, 'rb', closefd=False) as f:
            data = f.read(limit + 1)
        if len(data) > limit:
            raise ValueError('File exceeds bound')
        return data
    finally:
        os.close(fd)


def safe_stage(name):
    if not isinstance(name, str) or not re.fullmatch(r'[0-9]{2}-[A-Za-z-]{1,64}', name):
        raise ValueError('Invalid fixed stage name')


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()


def publish(bytes_, target):
    temporary = target.parent / (str(uuid.uuid4()) + '.tmp')
    try:
        with temporary.open('xb') as stream:
            stream.write(bytes_); stream.flush(); os.fsync(stream.fileno())
        os.link(temporary, target)  # Atomic final name; never replaces evidence.
        fd = os.open(target.parent, os.O_RDONLY | os.O_NOFOLLOW)
        try: os.fsync(fd)
        finally: os.close(fd)
    finally:
        if temporary.exists(): temporary.unlink()


def load_stage(root, name):
    config = json.loads(read_regular(root / 'window.json',4096))
    safe_stage(name)
    manifest_bytes = read_regular(root / 'plans/manifest.json', 4000000)
    if sha(manifest_bytes) != config['manifestSHA256']:
        raise ValueError('Manifest changed; refusing launch')
    stages = json.loads(manifest_bytes)
    stage = next(s for s in stages if s['name'] == name and s['device'] == 'macOS')
    if (root / 'plans' / name).is_symlink():
        raise ValueError('Symlink stage directory')
    plan_bytes = read_regular(root / 'plans' / name / 'SyncLab-Probe-Plan.json',262144)
    if json.loads(plan_bytes) != stage['plan'] or len(plan_bytes) > 262144:
        raise ValueError('Plan differs from prepared manifest')
    return config, stage, plan_bytes


def run(root, name):
    config, stage, plan_bytes = load_stage(root, name)
    if os.getuid() != config['testUID']:
        raise ValueError('请在专用测试用户 haha 中启动；当前用户不符。')
    output = root / 'results' / name
    output.mkdir()  # Claim before launching; interrupted attempts are never replayed.
    app = root / 'SyncLab.app'
    binary = app / 'Contents/MacOS/SyncLab'
    if sha(binary.read_bytes()) != config['executableSHA256']:
        raise ValueError('Executable changed')
    subprocess.run(['/usr/bin/codesign', '--verify', '--strict', str(app)], check=True)
    # Bundle sandbox locations are fixed, never taken from a plan.
    container = Path.home() / 'Library/Containers/com.yocruzer.PersonalGrowthOS.SyncLab/Data'
    documents = container / 'Documents'
    documents.mkdir(parents=True, exist_ok=True)
    imported = documents / 'SyncLab-Probe-Plan.json'
    if imported.exists() or imported.is_symlink():
        old = read_regular(imported,262144)
        retained = documents / ('SyncLab-Imported-' + sha(old) + '.json')
        if not retained.exists():
            with retained.open('xb') as f:
                f.write(old)
    plan = stage['plan']
    for key, prefix in [('id','probe-'),('runID','probe-'),('dataset','synthetic-g1-')]:
        value = plan[key]
        if not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', value) or not value.startswith(prefix):
            raise ValueError('Invalid plan identity')
    for command in plan['commands']:
        if not re.fullmatch(r'probe-[A-Za-z0-9_-]{1,122}', command['id']):
            raise ValueError('Invalid command identity')
    base = container / 'Library/Application Support/PersonalGrowthOS-SyncLab'
    claimed = base / 'manual-plan-journals/SyncLab-Manual-Results' / plan['runID'] / plan['dataset'] / (plan['id'] + '.request.json')
    report = documents / ('SyncLab-Manual-' + plan['id'] + '.json')
    if claimed.exists() or claimed.is_symlink() or report.exists() or report.is_symlink():
        raise ValueError('Previously claimed plan; preserve and use a fresh recovery plan')
    if stage.get('expectedExit') is not None:
        previous = base / 'fault-journals' / plan['runID'] / plan['dataset'] / plan['id'] / plan['commands'][-1]['id']
        if previous.exists() or previous.is_symlink():
            raise ValueError('Existing fault evidence; refusing to attribute it to a new launch')
    temporary = documents / 'SyncLab-Probe-Plan.next'
    with temporary.open('xb') as f:
        f.write(plan_bytes); f.flush(); os.fsync(f.fileno())
    temporary.replace(imported)
    plan = stage['plan']
    # Explicit launcher opt-in; no permission comes from imported bytes.
    env = {**os.environ, 'SYNCLAB_ENABLE_DEVELOPMENT': 'YES',
           'SYNCLAB_DATASET': plan['dataset'], 'SYNCLAB_PROBE_RUN': plan['runID'],
           'SYNCLAB_PROBE_IMPORTED_PLAN': 'YES'}
    for key in ['SYNCLAB_PROBE_BRIDGE', 'SYNCLAB_PROBE_TOKEN', 'SYNCLAB_PROBE_COMMAND']:
        env.pop(key, None)
    subprocess.run(['/usr/bin/open', '-n', '-W', '-a', str(app)], env=env, check=True, timeout=720)
    report = documents / ('SyncLab-Manual-' + plan['id'] + '.json')
    if report.exists():
        data = read_regular(report); value = json.loads(data)
        if value['planID'] != plan['id'] or value['planDigest'] != sha(plan_bytes):
            raise ValueError('Wrong report identity')
        if value.get('dataset') != plan['dataset'] or value.get('runID') != plan['runID']:
            raise ValueError('Wrong report context')
        if len({r.get('processNonce') for r in value['results']}) != 1:
            raise ValueError('Mixed process lifetimes')
        for command, result in zip(plan['commands'], value['results']):
            if result.get('planID') != plan['id'] or result.get('dataset') != plan['dataset'] or result.get('runID') != plan['runID']:
                raise ValueError('Wrong nested command context')
            if result['id'] != command['id'] or result['commandDigest'] != sha(canonical(command)) or not result.get('processNonce') or result.get('platform') != 'macOS':
                raise ValueError('Wrong command provenance')
        publish(data, output / 'report.json')
        if stage.get('expectedExit') is not None or value['completedAllCommands'] is not True or len(value['results']) != len(plan['commands']) or any(r['status'] != 'PASS' or r['halted'] or r.get('errorCode') for r in value['results']):
            raise ValueError('Expected boundary not reached or command failed; report retained')
        print(name + ': command report collected; cross-device acceptance still pending')
    else:
        if stage.get('expectedExit') is None:
            raise ValueError('No report; unplanned interruption')
        last = plan['commands'][-1]
        faults = container / 'Library/Application Support/PersonalGrowthOS-SyncLab/fault-journals' / plan['runID'] / plan['dataset'] / plan['id'] / last['id']
        points = {73:'beforeSaveCommit', 74:'afterSaveCommit', 75:'afterFetchedInstall', 76:'afterFetchedState', 77:'assetLeaseBeforeACK'}
        marker = faults / (points[stage['expectedExit']] + '.json')
        data = read_regular(marker); value = json.loads(data)
        if value['commandID'] != last['id'] or value['planID'] != plan['id'] or value['dataset'] != plan['dataset'] or value['runID'] != plan['runID']:
            raise ValueError('Wrong fault marker identity')
        if value.get('commandDigest') != sha(canonical(last)) or not value.get('processNonce') or value.get('point') != points[stage['expectedExit']]:
            raise ValueError('Wrong boundary provenance')
        if stage['expectedExit'] in (75,76,77) and value.get('provenance') != 'actualCloudKitCallback':
            raise ValueError('Local seam cannot substitute a cloud callback')
        publish(data, output / 'boundary.json')
        print(name + ': boundary retained; open -W does not expose app exit code; NEW process recovery must verify nonce')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('stage', nargs='?')
    parser.add_argument('--listen', action='store_true')
    args = parser.parse_args()
    root = args.package.resolve()
    if not args.listen:
        run(root, args.stage); return
    config = json.loads(read_regular(root / 'window.json',4096))
    if os.getuid() != config['testUID']:
        raise ValueError('Dedicated test user required')
    deadline = time.monotonic() + 7200
    seen = set()
    print('固定合成测试窗口已就绪；可切回原用户。两小时后自动停止等待。', flush=True)
    while time.monotonic() < deadline:
        request = root / 'requested-stage.json'
        if request.exists():
            data = read_regular(request,1024)
            if len(data) > 1024:
                raise ValueError('Request too large')
            name = json.loads(data)['stage']
            if name == 'STOP':
                return
            if name not in seen:
                seen.add(name)
                try:
                    run(root, name)
                except Exception as error:
                    # Do not print account IDs, paths from CK errors, or credentials.
                    print('测试停止：' + type(error).__name__ + '；原证据保留。', flush=True)
                    raise
        time.sleep(0.5)


if __name__ == '__main__':
    main()
