#!/usr/bin/env python3
"""Prepare signed fixed-plan Mac window; no launch or cloud operations."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import pwd
import shutil
import subprocess
from fault_window import safe_stage, read_regular


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--app', type=Path, required=True)
    p.add_argument('--plans', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--test-user', required=True)
    a = p.parse_args()
    uid = pwd.getpwnam(a.test_user).pw_uid
    if uid == os.getuid():
        raise SystemExit('Dedicated test user required')
    tools = Path(__file__).resolve().parent
    subprocess.run(['/usr/bin/python3', str(tools/'verify_signing.py'), str(a.app)], check=True)
    manifest = read_regular(a.plans/'manifest.json',4000000)
    stages = json.loads(manifest)
    if len(stages) != 27 or len({s['name'] for s in stages}) != 27:
        raise SystemExit('Expected complete fixed dependency and fault suite')
    for stage in stages:
        safe_stage(stage["name"])
    if a.plans.is_symlink() or any(path.is_symlink() for path in a.plans.rglob("*")):
        raise SystemExit("Symlink plan source refused")
    a.output.mkdir(mode=0o755)
    a.output.chmod(0o755)
    subprocess.run(['/usr/bin/ditto', str(a.app), str(a.output/'SyncLab.app')], check=True)
    prepared = a.output/'plans'; prepared.mkdir()
    (prepared/'manifest.json').write_bytes(manifest)
    (prepared/'SyncLab-Probe-Batch.json').write_bytes(read_regular(a.plans/'SyncLab-Probe-Batch.json',524288))
    for stage in stages:
        name=stage['name']; source=read_regular(a.plans/name/'SyncLab-Probe-Plan.json',262144)
        if json.loads(source)!=stage['plan']:
            raise SystemExit('Plan differs from fixed manifest')
        destination=prepared/name; destination.mkdir()
        (destination/'SyncLab-Probe-Plan.json').write_bytes(source)
    shutil.copyfile(tools/'fault_window.py', a.output/'fault_window.py')
    shutil.copyfile(tools/'window_transport.py', a.output/'window_transport.py')
    (a.output/'window_transport.py').chmod(0o644)
    config = {'transport':'loopback-v1', 'testUID': uid, 'manifestSHA256': hashlib.sha256(manifest).hexdigest(),
              'executableSHA256': hashlib.sha256((a.output/'SyncLab.app/Contents/MacOS/SyncLab').read_bytes()).hexdigest()}
    (a.output/'window.json').write_text(json.dumps(config, indent=2)+'\n')
    (a.output/'window.json').chmod(0o644)
    (a.output/'fault_window.py').chmod(0o644)
    results = a.output/'results'; results.mkdir(mode=0o700)
    subprocess.run(['/bin/chmod','+a',f'user:{a.test_user} allow read,write,execute,add_file,add_subdirectory,delete_child,file_inherit,directory_inherit',str(results)],check=True)
    controller = pwd.getpwuid(os.getuid()).pw_name
    subprocess.run(['/bin/chmod','+a',f'user:{controller} allow read,execute,file_inherit,directory_inherit',str(results)],check=True)
    for path in (a.output/'plans').rglob('*'):
        path.chmod(0o755 if path.is_dir() else 0o644)
    (a.output/'plans').chmod(0o755)
    launcher = a.output/'Start-Fault-Window.command'
    launcher.write_text('#!/bin/zsh\nset -eu\nsynclab_dir="${0:A:h}"\n/usr/bin/python3 "$synclab_dir/fault_window.py" "$synclab_dir" --listen\n')
    launcher.chmod(0o755)
    print('Prepared; Owner starts once in dedicated user. No app launched.')


if __name__ == '__main__':
    main()
