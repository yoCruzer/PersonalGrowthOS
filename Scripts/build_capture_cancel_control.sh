#!/bin/sh
# Build an independent standard Share Extension for cancellation comparison. No data reset.
set -eu
repository=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture_app=/tmp/PGOSCancelControlApp.app
extension_app="$fixture_app/PlugIns/CancelControl.appex"
sh "$repository/Scripts/build_capture_fixture_host.sh"
mkdir -p "$extension_app"
cp /tmp/PGOSCaptureFixtureHost.app/CaptureFixtureHost "$fixture_app/CaptureFixtureHost"
cp /tmp/PGOSCaptureFixtureHost.app/Info.plist "$fixture_app/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.yocruzer.CancelControlApp' "$fixture_app/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName Cancel Control App' "$fixture_app/Info.plist"
cat > "$extension_app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>CancelControl</string>
<key>CFBundleIdentifier</key><string>com.yocruzer.CancelControlApp.ShareExtension</string>
<key>CFBundleName</key><string>Cancel Control</string>
<key>CFBundleDisplayName</key><string>Cancel Control</string>
<key>CFBundlePackageType</key><string>XPC!</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>NSExtension</key><dict>
<key>NSExtensionPointIdentifier</key><string>com.apple.share-services</string>
<key>NSExtensionPrincipalClass</key><string>CancelControl.CancelControl</string>
<key>NSExtensionAttributes</key><dict><key>NSExtensionActivationRule</key><dict>
<key>NSExtensionActivationDictionaryVersion</key><integer>2</integer>
<key>NSExtensionActivationSupportsText</key><true/>
<key>NSExtensionActivationSupportsWebURLWithMaxCount</key><integer>1</integer>
</dict></dict></dict>
</dict></plist>
PLIST
fixture_arch=$(uname -m)
xcrun --sdk iphonesimulator swiftc -module-cache-path /tmp/PGOSCaptureFixtureModuleCache -parse-as-library -application-extension -target "$fixture_arch-apple-ios17.0-simulator" -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" -module-name CancelControl -Xlinker -e -Xlinker _NSExtensionMain -o "$extension_app/CancelControl" "$repository/PersonalGrowthOSUITests/Fixtures/CaptureHost/CancelControl.swift"
codesign --force --sign - "$extension_app"
codesign --force --sign - "$fixture_app"
