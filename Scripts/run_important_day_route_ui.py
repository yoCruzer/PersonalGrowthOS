#!/usr/bin/env python3
"""Drive real warm/cold URL delivery without XCUIApplication.openURL's process relaunch.

Run from the repo with --simulator UUID --result /tmp/name.xcresult --log /tmp/name.log.
Remaining arguments are xcodebuild selectors/options. Only synthetic route IDs are emitted.
"""
import argparse
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument('--simulator', required=True)
parser.add_argument('--result', required=True)
parser.add_argument('--log', required=True)
args, extra = parser.parse_known_args()
command = ['xcodebuild', '-project', 'PersonalGrowthOS.xcodeproj', '-scheme', 'PersonalGrowthOS',
           '-destination', f'platform=iOS Simulator,id={args.simulator}',
           '-derivedDataPath', '/private/tmp/pgos-important-days-data-build',
           '-resultBundlePath', args.result, '-collect-test-diagnostics', 'never',
           '-parallel-testing-enabled', 'NO', *extra, 'test', 'CODE_SIGNING_ALLOWED=NO']
routes = {
    'PGOS_ROUTE_UI_READY_1': 'suixinlog://important-day/11111111-2222-4333-8444-555555555555',
    'PGOS_ROUTE_UI_READY_2': 'suixinlog://important-day/00000000-0000-4000-8000-000000000099',
}
seen = set()
with open(args.log, 'w') as log:
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    for line in process.stdout:
        log.write(line)
        log.flush()
        for marker, url in routes.items():
            if marker in line and marker not in seen:
                seen.add(marker)
                delivered = subprocess.run(['xcrun', 'simctl', 'openurl', args.simulator, url], capture_output=True, text=True, timeout=15)
                log.write(f'ExternalRouteDriver {marker} exit={delivered.returncode}\n')
                log.flush()
                if delivered.returncode:
                    print(f'ExternalRouteDriver failed: {marker}', flush=True)
    code = process.wait()
print(f'xcodebuild exit={code}; delivered={len(seen)}', flush=True)
sys.exit(code)
