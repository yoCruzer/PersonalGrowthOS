#!/usr/bin/env python3
"""Stage an already signed Mac lab app for an Owner-created local test user.

No passwords/private keys, no account changes, no launch or cloud operations.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--connection', type=Path, required=True)
parser.add_argument('--test-user', required=True)
parser.add_argument('--dataset', required=True)
parser.add_argument('--run-id', required=True)
args = parser.parse_args()
tools = Path(__file__).resolve().parent
test_uid = pwd.getpwnam(args.test_user).pw_uid
if test_uid == os.getuid():
    raise SystemExit('Refusing to stage for the current daily user')
subprocess.run(['/usr/bin/python3', str(tools / 'verify_signing.py'), str(args.app)], check=True)
args.output.mkdir(mode=0o755)  # Never overwrite an earlier signed package/evidence.
args.output.chmod(0o755)
subprocess.run(['/usr/bin/ditto', str(args.app), str(args.output / 'SyncLab.app')], check=True)
for name in ['verify_signing.py', 'profile_entitlements.py']:
    shutil.copyfile(tools / name, args.output / name)
    (args.output / name).chmod(0o644)
config = json.loads(args.connection.read_text())
if config.get('dataset') != args.dataset or config.get('runID') != args.run_id:
    raise SystemExit('Bridge and package run identities must match')
config.update(testUID=test_uid, dataset=args.dataset, runID=args.run_id)
configuration = args.output / 'connection-private.json'
configuration.write_text(json.dumps(config))
configuration.chmod(0o600)
subprocess.run(['/bin/chmod', '+a', 'user:' + args.test_user + ' allow read', str(configuration)], check=True)
(args.output / 'launch_probe.py').write_text('''import json, os, pathlib, subprocess
root = pathlib.Path(__file__).resolve().parent
config = json.loads((root / 'connection-private.json').read_text())
if os.getuid() != config['testUID']:
    raise SystemExit('请在专用测试用户中启动，当前用户不符。')
subprocess.run(['/usr/bin/python3', str(root / 'verify_signing.py'), str(root / 'SyncLab.app')], check=True)
env = {'SYNCLAB_ENABLE_DEVELOPMENT': 'YES', 'SYNCLAB_DATASET': config['dataset'],
       'SYNCLAB_PROBE_RUN': config['runID'], 'SYNCLAB_PROBE_BRIDGE': config['address'],
       'SYNCLAB_PROBE_TOKEN': config['token']}
command = ['/usr/bin/open', '-n', '-a', str(root / 'SyncLab.app')]
subprocess.run(command, env={**os.environ, **env}, check=True)
print('SyncLab已启动。请保持应用和测试用户登录，切回原用户继续。')
''')
(args.output / 'launch_probe.py').chmod(0o644)
launcher = args.output / 'Start-SyncLab.command'
launcher.write_text('#!/bin/zsh\nset -eu\nsynclab_dir="${0:A:h}"\n/usr/bin/python3 "$synclab_dir/launch_probe.py"\n')
launcher.chmod(0o755)
manifest = {'dataset': args.dataset, 'runID': args.run_id,
            'scope': 'Debug synthetic-only loopback probe; no private keys',
            'sourceHashes': {name: hashlib.sha256((tools / name).read_bytes()).hexdigest()
                             for name in ['verify_signing.py', 'profile_entitlements.py']},
            'executableSHA256': hashlib.sha256((args.output / 'SyncLab.app/Contents/MacOS/SyncLab').read_bytes()).hexdigest()}
(args.output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
(args.output / 'manifest.json').chmod(0o644)
print('Staged verified test package; connection token is restricted to original and designated test users.')
