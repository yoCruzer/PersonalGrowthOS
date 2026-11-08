#!/usr/bin/env python3
"""Offline black-box validation of an already packaged locked host and packaging rejects."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys


def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package-output', required=True)
    parser.add_argument('--probe-binary', required=True)
    parser.add_argument('--evidence-output', required=True)
    args = parser.parse_args()
    output = Path(args.package_output); evidence = Path(args.evidence_output)
    evidence.mkdir(mode=0o700, parents=False, exist_ok=False)
    script = Path(os.path.abspath(__file__)).with_name('package_locked_host.py')
    app = output / 'FormalSyncProbe.app'; binary = app / 'Contents/MacOS/FormalDevelopmentHost'
    cases = []
    def check(label, condition):
        cases.append({'case': label, 'passed': bool(condition)})
        if not condition: raise AssertionError(label)
    def command(label, argv, expected):
        result = subprocess.run([str(x) for x in argv], capture_output=True, text=True)
        cases.append({'case': label, 'command': [str(x) for x in argv], 'exitCode': result.returncode,
                      'expectedExitCode': expected, 'stdout': result.stdout, 'stderr': result.stderr,
                      'passed': result.returncode == expected})
        if result.returncode != expected: raise AssertionError(label)
        return result
    try:
        receipt = json.loads((output / 'packaging.json').read_text())
        info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
        entitlements = plistlib.loads((output / 'candidate.entitlements').read_bytes())
        check('actual-binary-hash', sha(binary) == receipt['binarySHA256'])
        check('info-hash', sha(app / 'Contents/Info.plist') == receipt['infoSHA256'])
        check('entitlements-hash', sha(output / 'candidate.entitlements') == receipt['candidateEntitlementsSHA256'])
        check('independent-mac-identity', info['CFBundleIdentifier'] == 'com.yocruzer.PersonalGrowthOS.FormalSyncProbe'
              and info['CFBundleExecutable'] == binary.name and info['CFBundleSupportedPlatforms'] == ['MacOSX']
              and info['CFBundlePackageType'] == 'APPL' and info['LSMinimumSystemVersion'] == '14.0')
        check('candidate-only-no-profile-signature-resource', not (app / 'Contents/embedded.provisionprofile').exists()
              and not (app / 'Contents/_CodeSignature').exists() and not (app / 'Contents/candidate.entitlements').exists())
        check('no-appgroups-production-push', 'com.apple.security.application-groups' not in entitlements
              and 'aps-environment' not in entitlements and entitlements['com.apple.developer.icloud-container-environment'] == 'Development')
        check('source-snapshot-hashes', all(sha(output / 'source-snapshot' / path) == value for path, value in receipt['sourceSHA256'].items()))
        plan = evidence / 'plan'
        command('make-fixed-synthetic-plan', [args.probe_binary, 'plan', plan], 0)
        plan_hash = (plan / 'plan.sha256').read_text().strip()
        command('actual-app-executable-locked', [binary, 'inspect', plan, plan_hash, evidence / 'inspect'], 2)
        inspect = json.loads((evidence / 'inspect/report.json').read_text())
        check('inspect-never-authorizes', inspect['status'] == 'NOT_READY' and inspect['networkOperations'] == 0 and not inspect['networkAuthorized'] and not inspect['p0Passed'])
        command('actual-app-preflight-rejects', [args.probe_binary, 'preflight', plan, plan_hash, app, evidence / 'preflight'], 2)
        preflight = json.loads((evidence / 'preflight/report.json').read_text())
        check('preflight-real-unprovisioned-rejection', preflight['status'] == 'NOT_READY' and 'PROFILE_MISSING' in preflight['rejectionCodes']
              and 'CODE_IDENTITY_MISMATCH' in preflight['rejectionCodes'] and not preflight['networkAuthorized'] and not preflight['p0Passed'])
        self_check = command('internal-fixture-locked', [binary, 'inspect-fixture'], 2)
        self_report = json.loads(self_check.stdout)
        command('runtime-invalid-base64-rejected', [binary, 'inspect-runtime', '%%%'], 64)
        rejected_runtime = command('runtime-unqualified-input-rejected', [binary, 'inspect-runtime', base64.b64encode(b'{}').decode()], 2)
        runtime_report = json.loads(rejected_runtime.stdout)
        check('runtime-rejection-never-authorizes', runtime_report['status'] == 'NOT_READY'
              and runtime_report['mode'] == 'OFFLINE_ONLY' and runtime_report['networkOperations'] == 0
              and not runtime_report['networkAuthorized'] and not runtime_report['ownerApprovalVerified']
              and not runtime_report['signatureProfileDeviceVerified'] and not runtime_report['p0Passed']
              and runtime_report['accountQualification'] == 'NOT_RUN' and runtime_report['actualServiceAccess'] == 'NOT_RUN')
        command('guarded-cli-requires-complete-input', [binary, 'run-approved', 'unused'], 64)
        for verb in ('enroll-guard', 'run-approved'):
            command(verb + '-rejects-missing-approval', [binary, verb, base64.b64encode(b'{}').decode(), hashlib.sha256(b'{}').hexdigest()], 1)
        check('internal-fixture-report-redacted-locked', self_report['mode'] == 'OFFLINE_ONLY'
              and self_report['status'] == 'NOT_READY' and self_report['failure'] == 'EXTERNAL_GATE_NOT_COMPLETE'
              and self_report['networkOperations'] == 0 and not self_report['networkAuthorized'] and not self_report['p0Passed']
              and self_report['environment'] == 'Development' and '/' not in self_check.stdout)
        command('internal-fixture-extra-path-rejected', [binary, 'inspect-fixture', evidence / 'forbidden-path'], 64)
        check('internal-fixture-cannot-create-caller-output', not (evidence / 'forbidden-path').exists())
        command('live-option-rejected', [binary, 'live', plan, plan_hash, evidence / 'live'], 64)
        command('wrong-plan-hash-rejected', [binary, 'inspect', plan, '0' * 64, evidence / 'wrong-hash'], 1)
        before = sha(output / 'packaging.json')
        command('existing-output-rejected', [sys.executable, script, '--output', output], 1)
        check('existing-output-preserved', sha(output / 'packaging.json') == before)
        link = evidence / 'output-link'; link.symlink_to(output, target_is_directory=True)
        command('output-symlink-rejected', [sys.executable, script, '--output', link], 1)
        parent_link = evidence / 'parent-link'; parent_link.symlink_to(evidence, target_is_directory=True)
        command('parent-symlink-rejected', [sys.executable, script, '--output', parent_link / 'new'], 1)
        command('dotdot-rejected', [sys.executable, script, '--output', str(evidence) + '/../escaped'], 1)
        check('symlinks-did-not-create-output', not (evidence / 'new').exists())
        # Test rejected input copies, never modifying the actual package source.
        fixture = evidence / 'repo-fixture'; (fixture / 'Scripts/FormalDevelopmentHost').mkdir(parents=True)
        fixture_script = fixture / 'Scripts/FormalDevelopmentHost/package_locked_host.py'
        shutil.copyfile(script, fixture_script)
        shutil.copyfile(script.with_name('trusted-source-sha256.json'), fixture_script.with_name('trusted-source-sha256.json'))
        fixture_package = fixture / 'Packages/SyncFoundation'
        shutil.copytree(output / 'source-snapshot', fixture_package)
        source = fixture_package / 'Sources/FormalDevelopmentHost/main.swift'
        source.unlink(); source.symlink_to(output / 'source-snapshot/Sources/FormalDevelopmentHost/main.swift')
        command('source-symlink-rejected', [sys.executable, fixture_script, '--output', evidence / 'source-link-output'], 1)
        check('source-rejected-before-output', not (evidence / 'source-link-output').exists())
        source.unlink(); shutil.copyfile(output / 'source-snapshot/Sources/FormalDevelopmentHost/main.swift', source)
        source.write_text(source.read_text() + '\n// unreviewed source\n')
        command('unreviewed-swift-rejected', [sys.executable, fixture_script, '--output', evidence / 'changed-source-output'], 1)
        check('swift-rejected-before-output', not (evidence / 'changed-source-output').exists())
        shutil.copyfile(output / 'source-snapshot/Sources/FormalDevelopmentHost/main.swift', source)
        command('output-inside-package-rejected', [sys.executable, fixture_script, '--output', fixture_package / 'new-output'], 1)
        check('no-source-self-mutation', not (fixture_package / 'new-output').exists())
        manifest = fixture_package / 'Package.swift'; manifest.write_text(manifest.read_text() + '\n// changed manifest\n')
        command('unreviewed-manifest-rejected', [sys.executable, fixture_script, '--output', evidence / 'changed-manifest-output'], 1)
        check('manifest-rejected-before-output', not (evidence / 'changed-manifest-output').exists())
        # Read-only ad-hoc metadata, no sign command, no raw profile or private identifiers.
        verification = subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True)
        details = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', str(app)], capture_output=True)
        technical = {}
        for line in details.stderr.decode(errors='replace').splitlines():
            if line.startswith(('Identifier=', 'Signature=', 'TeamIdentifier=', 'CDHash=')):
                key, value = line.split('=', 1); technical[key] = value
        (evidence / 'actual-code-signature.json').write_text(json.dumps({'verifyExitCode': verification.returncode, 'detailsExitCode': details.returncode,
             'technicalFields': technical, 'developerSigningPerformed': False}, indent=2) + '\n')
    finally:
        (evidence / 'checks.json').write_text(json.dumps(cases, indent=2) + '\n')
    print(f'{len(cases)} checks passed; actual app remains NOT_READY; no developer signing/network')

if __name__ == '__main__': main()
