#!/usr/bin/env python3
"""Exercises the actual build script using synthetic, disposable checkouts."""
import os
import pathlib
import plistlib
import subprocess
import tempfile

script = pathlib.Path(__file__).resolve().with_name('generate-build-provenance.sh')
with tempfile.TemporaryDirectory(prefix='pgos-provenance-') as directory:
    root = pathlib.Path(directory)
    checkout = root / 'repo'
    checkout.mkdir()
    def git(*args):
        return subprocess.check_output(['git', '-C', str(checkout), *args], text=True).strip()
    git('init', '-q')
    git('-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '--allow-empty', '-qm', 'fixture')
    head = git('rev-parse', 'HEAD')
    clean = {k: v for k, v in os.environ.items() if not k.startswith('CI_')}
    output = root / 'BuildProvenance.plist'
    def run(source=checkout, env=None, succeeds=True):
        result = subprocess.run([str(script), str(source), str(output)], env=clean | (env or {}), capture_output=True, text=True)
        assert (result.returncode == 0) == succeeds, result.stderr
        return plistlib.loads(output.read_bytes()) if succeeds else result.stderr
    value = run()
    assert value == {'Commit': head, 'Source': 'localGit', 'Dirty': False, 'Tag': ''}
    (checkout / 'source.txt').write_text('dirty')
    assert run()['Dirty'] is True
    value = run(env={'CI_COMMIT': head, 'CI_TAG': 'release/1.0'})
    assert value == {'Commit': head, 'Source': 'xcodeCloud', 'Dirty': False, 'Tag': 'release/1.0'}
    assert run(env={'CI_COMMIT': head})['Tag'] == ''
    run(env={'CI_COMMIT': 'invalid'}, succeeds=False)
    run(env={'CI_COMMIT': 'f' * 40}, succeeds=False)
    run(env={'CI_COMMIT': head, 'CI_TAG': 'bad<&tag'}, succeeds=False)
    missing = root / 'no-git'
    missing.mkdir()
    assert run(source=missing)['Commit'] == ''
    assert run(source=missing)['Source'] == 'unknown'
    assert run(source=missing, env={'CI_COMMIT': head, 'CI_TAG': 'release'})['Commit'] == head
print('PASS: local clean/dirty, CI tagged/untagged, missing Git, invalid/stale SHA and unsafe tag')
