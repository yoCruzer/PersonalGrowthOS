#!/bin/sh
# Build only; install into a chosen simulator with simctl. No user data reset.
set -eu
repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture_app=${1:-/tmp/PGOSCaptureFixtureHost.app}
mkdir -p "$fixture_app"
cat > "$fixture_app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CaptureFixtureHost</string>
<key>CFBundleIdentifier</key><string>com.yocruzer.CaptureFixtureHost</string>
<key>CFBundleName</key><string>Capture Fixture Host</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>LSRequiresIPhoneOS</key><true/>
<key>UIDeviceFamily</key><array><integer>1</integer></array>
<key>UIApplicationSceneManifest</key><dict>
<key>UIApplicationSupportsMultipleScenes</key><false/>
<key>UISceneConfigurations</key><dict><key>UIWindowSceneSessionRoleApplication</key><array><dict>
<key>UISceneConfigurationName</key><string>Fixture</string>
<key>UISceneDelegateClassName</key><string>CaptureFixtureHost.CaptureHostScene</string>
</dict></array></dict></dict>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
fixture_arch=$(uname -m)
xcrun --sdk iphonesimulator swiftc -module-cache-path /tmp/PGOSCaptureFixtureModuleCache -parse-as-library -target "$fixture_arch-apple-ios17.0-simulator" -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -module-name CaptureFixtureHost -o "$fixture_app/CaptureFixtureHost" "$repository/PersonalGrowthOSUITests/Fixtures/CaptureHost/CaptureHost.swift"
codesign --force --sign - "$fixture_app"
