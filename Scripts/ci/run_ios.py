#!/usr/bin/env python3
"""Hosted macOS gates. All products stay in RUNNER_TEMP; native tests are serial."""
import json
import os
from pathlib import Path
import subprocess
import sys

lane = sys.argv[1]
assert lane in ('release', 'unit', 'smoke')
root = Path(os.environ['RUNNER_TEMP']) / ('pgos-' + lane)
root.mkdir(parents=True, exist_ok=True)
os.environ['DEVELOPER_DIR'] = '/Applications/Xcode_27.app/Contents/Developer'


def run(args, name):
    print('+', ' '.join(args), flush=True)
    with (root / (name + '.log')).open('w') as log:
        proc = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in proc.stdout:
            print(line, end='', flush=True)
            log.write(line)
    code = proc.wait()
    if code:
        raise subprocess.CalledProcessError(code, args)


def output(args):
    return subprocess.check_output(args, text=True)


run(['sw_vers'], 'os')
run(['xcodebuild', '-version'], 'xcode')
assert output(['xcodebuild', '-version']).startswith('Xcode 27.')
run(['xcodebuild', '-showsdks'], 'sdks')
run(['xcrun', 'simctl', 'list', 'runtimes'], 'runtimes')
run(['xcodebuild', '-list', '-project', 'PersonalGrowthOS.xcodeproj'], 'schemes')
manifest = dict(lane=lane, checkoutSHA=output(['git', 'rev-parse', 'HEAD']).strip(),
                event=os.environ.get('GITHUB_EVENT_NAME'), githubSHA=os.environ.get('GITHUB_SHA'),
                headSHA=os.environ.get('PGOS_PR_HEAD_SHA'), runner=os.environ.get('RUNNER_NAME'),
                image=os.environ.get('ImageVersion'), arch=os.environ.get('RUNNER_ARCH'),
                xcode=output(['xcodebuild', '-version']), developerDir=os.environ['DEVELOPER_DIR'])
(root / 'environment.json').write_text(json.dumps(manifest, indent=2) + '\n')
common = ['xcodebuild', '-project', 'PersonalGrowthOS.xcodeproj', '-scheme', 'PersonalGrowthOS',
          '-jobs', '2', '-derivedDataPath', str(root / 'DerivedData'), 'CODE_SIGNING_ALLOWED=NO']
if lane == 'release':
    run(common + ['build', '-configuration', 'Release', '-destination', 'generic/platform=iOS'], 'release')
    products = root / 'DerivedData/Build/Products/Release-iphoneos'
    bundles = [products / 'PersonalGrowthOS.app',
               products / 'PersonalGrowthOS.app/PlugIns/ShareExtension.appex',
               products / 'PersonalGrowthOS.app/PlugIns/ImportantDaysWidget.appex']
    for bundle in bundles:
        assert bundle.is_dir(), bundle
        assert not (bundle / '_CodeSignature').exists(), bundle
    (root / 'bundles.json').write_text(json.dumps([str(x.relative_to(products)) for x in bundles], indent=2))
else:
    runtimes = json.loads(output(['xcrun', 'simctl', 'list', 'runtimes', '-j']))['runtimes']
    available = [x for x in runtimes if x.get('isAvailable') and x['identifier'].split('.')[-1].startswith('iOS-27')]
    assert available, 'No available iOS 27 simulator runtime'
    runtime = sorted(available, key=lambda x: tuple(map(int, x['version'].split('.'))))[-1]
    types = json.loads(output(['xcrun', 'simctl', 'list', 'devicetypes', '-j']))['devicetypes']
    phones = [x for x in types if x['name'].startswith('iPhone')]
    device_type = next((x for x in phones if x['name'] == 'iPhone 13 mini'), phones[0])
    udid = output(['xcrun', 'simctl', 'create', 'PGOS-CI-' + lane, device_type['identifier'], runtime['identifier']]).strip()
    manifest.update(runtime=runtime, deviceType=device_type, simulatorUDID=udid)
    (root / 'environment.json').write_text(json.dumps(manifest, indent=2) + '\n')
    run(['xcrun', 'simctl', 'boot', udid], 'boot')
    run(['xcrun', 'simctl', 'bootstatus', udid, '-b'], 'bootstatus')
    run(['xcrun', 'simctl', 'ui', udid, 'appearance', 'light'], 'appearance')
    args = common + ['test', '-destination', 'platform=iOS Simulator,id=' + udid,
                     '-parallel-testing-enabled', 'NO', '-maximum-concurrent-test-simulator-destinations', '1',
                     '-collect-test-diagnostics', 'never', '-resultBundlePath', str(root / 'tests.xcresult')]
    if lane == 'unit':
        args += ['-only-testing:PersonalGrowthOSTests']  # Entire hosted iOS Unit target, no method filter.
    else:
        args += ['-only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/' + name for name in [
            'testUITestingLaunchShowsAppShell', 'testCoreShellRemainsOperableAtLargestAccessibilityTextSize',
            'testUIReadabilityChineseDefaultAndLargerText', 'testUIReadabilityEnglishDefault',
            'testRepeatableHabitCounterIncrementsDecrementsAndPersists']]
    try:
        run(args, 'tests')
    finally:
        result = root / 'tests.xcresult'
        if result.exists():
            for kind in ['summary', 'tests']:
                proc = subprocess.run(['xcrun', 'xcresulttool', 'get', 'test-results', kind, '--path', str(result)],
                                      capture_output=True, text=True)
                (root / ('test-' + kind + '.json')).write_text(proc.stdout or proc.stderr)
        subprocess.run(['xcrun', 'simctl', 'shutdown', udid], check=False)
