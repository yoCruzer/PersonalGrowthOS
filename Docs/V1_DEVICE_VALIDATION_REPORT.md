# V1 Device Validation Report

## Validation Context

| Item | Confirmed value |
| --- | --- |
| Validation date | 2026-07-28 |
| Fixed original Candidate | `2e31e8a753005f8bb40bce348820529775aa2e9d` |
| First physical-device build commit | `a0d423331c512986a4c731175045ac7f5e93adb3` |
| Round 1 starting commit | `a3e64cb1624e2d83cdd4081aa3d30a5ecb1cd4e0` |
| Round 1 repair commit | `1ba25cf6cdb217696cb7bea1883ec5767b3748b4` |
| Round 1 branch | `fix/v1-device-smoke-round1` |
| Xcode | 26.6 (`17F113`) |
| Shared scheme | `PersonalGrowthOS` |
| Configuration | Debug |
| Bundle identifier | `com.yocruzer.PersonalGrowthOS` |

## Device

| Item | First installation | Round 1 repair attempt |
| --- | --- | --- |
| Device name | 蔡先生的iPhone | 蔡先生的iPhone |
| Model | iPhone 16 (`iPhone17,3`) | iPhone 16 (`iPhone17,3`) |
| iOS | 26.5.2 (`23F84`) | 26.6 (`23G71`) |
| Xcode destination UDID | `00008140-00096D1E21D0801C` | `00008140-00096D1E21D0801C` |
| CoreDevice identifier | `1602D9E0-4D13-59BA-93AD-1BEBAEB1C7D3` | `1602D9E0-4D13-59BA-93AD-1BEBAEB1C7D3` |
| Connection | USB; paired; tunnel connected | Local network; paired; tunnel connected during diagnosis |
| Developer Mode | Enabled | Enabled |
| DDI services | Available | Unavailable: Xcode 26.6 supports physical devices through iOS 26.5 |

## Signing and Provisioning

- App Target Debug and Release use `CODE_SIGN_STYLE = Automatic`.
- App Target Debug and Release use `DEVELOPMENT_TEAM = 83SKX2PM7B`.
- No project capability, entitlement file, Bundle Identifier or test-target signing change was added.
- A Round 1 generic iOS Debug build succeeded with Apple Development identity `Guangzong Cai (BKDNAV2N47)`.
- The Xcode-managed profile is `iOS Team Provisioning Profile: *`, Team Identifier `83SKX2PM7B`.
- The profile includes device UDID `00008140-00096D1E21D0801C`, so device registration remains confirmed.
- The signed bundle identifier is `com.yocruzer.PersonalGrowthOS`.
- Only standard development entitlements were present: application identifier, Team identifier, debug allowance and keychain access group.

## First iPhone Smoke Test

The Owner manually confirmed the following on the first installed build:

- [x] App icon appears normally.
- [x] App launches.
- [x] Today, Timeline, Growth and Library are reachable.
- [x] A text-only entry can be created.
- [x] Data remains after force-quitting and reopening the App.
- [x] Photos Picker works.
- [x] Camera capture works.
- [x] No launch crash or P0 data issue was observed.

The first Smoke Test found these Round 1 issues:

- The interface did not follow a Simplified Chinese system language.
- Habit Check-in lacked clear feedback, flexible once/multiple-per-day semantics, debounce and undo.
- Habit names and recording settings could not be edited.
- Timeline image thumbnails used a destructive center crop.
- Goal and Flag cards were not actionable or editable.
- Today, Growth add actions and empty Tag flows needed clearer guidance.

## Round 1 Repair Scope

- Added English and Simplified Chinese String Catalog coverage for the V1 interface.
- Added once-per-day and multiple-per-day Habit recording modes, optional daily count target, duplicate-tap protection, haptics, immediate UI state and latest-record undo.
- Added non-destructive Habit editing while preserving stable IDs, history and relationships.
- Added Goal/Flag navigation and minimal editing while preserving stable IDs and persisted list updates.
- Changed Timeline image presentation to aspect-fit with bounded height and no original-media modification.
- Added Today first-use guidance, stronger Add Goal/Flag actions, and Tag creation/selection guidance.

## Automated Validation

| Check | Result |
| --- | --- |
| Unit Tests | PASS — 116 passed, 0 failed, 0 skipped |
| UI Tests | PASS — 21 passed, 0 failed, 0 skipped |
| Total | PASS — 137 passed, 0 failed, 0 skipped |
| Baseline comparison | 124 to 137 tests; 13 focused tests added, none deleted or skipped |
| Simulator Debug build | PASS on iPhone 17 Pro simulator, iOS 26.5 |
| String Catalog | PASS — 263 keys have explicit English and Simplified Chinese values; catalog compilation succeeded |
| Asset Catalog | PASS as part of Unit/UI and simulator builds |
| `git diff --check` | PASS |

Automated coverage includes critical English/Chinese resources and launch languages; Habit legacy compatibility, recording modes, local-natural-day limits, debounce, undo, editing and restart persistence; Goal/Flag editing and restart persistence; Timeline fit sizing for landscape, portrait, square and long images; and Today/Tag empty-state flows.

These automated results do not constitute Owner confirmation of physical-device interaction or visual quality.

## Round 1 Builds

Simulator command:

```sh
xcodebuild -quiet \
  -project PersonalGrowthOS.xcodeproj \
  -scheme PersonalGrowthOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,id=4C8C76D9-41F0-4EB1-9881-836515666D9F' \
  -derivedDataPath /tmp/PersonalGrowthOS-SmokeFix-SimulatorFinal \
  -resultBundlePath /tmp/PersonalGrowthOS-SmokeFix-SimulatorFinal.xcresult \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Result: PASS.

Generic signed iOS command:

```sh
xcodebuild -quiet \
  -project PersonalGrowthOS.xcodeproj \
  -scheme PersonalGrowthOS \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/PersonalGrowthOS-SmokeFix-GenericDevice \
  -resultBundlePath /tmp/PersonalGrowthOS-SmokeFix-GenericDevice.xcresult \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build
```

Result: PASS. Signing and provisioning completed successfully.

Signed application artifact:

```text
/tmp/PersonalGrowthOS-SmokeFix-GenericDevice/Build/Products/Debug-iphoneos/PersonalGrowthOS.app
```

Physical-device destination command:

```sh
xcodebuild -quiet \
  -project PersonalGrowthOS.xcodeproj \
  -scheme PersonalGrowthOS \
  -configuration Debug \
  -destination 'platform=iOS,id=00008140-00096D1E21D0801C' \
  -derivedDataPath /tmp/PersonalGrowthOS-SmokeFix-Device \
  -resultBundlePath /tmp/PersonalGrowthOS-SmokeFix-Device.xcresult \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  build
```

Result: BLOCKED before target compilation because Xcode could not mount the Developer Disk Image:

```text
The developer disk image could not be mounted on this device.
kAMDMobileImageMounterNetworkUnauthorizedError
AMAuthInstallRequestSendSync failed: 3501 (kAMAuthInstallErrorHTTPUnauthorized)
```

The device is now on iOS 26.6, while Xcode 26.6 lists physical-device support through iOS 26.5. Resolving this requires an Xcode version with iOS 26.6 device support (or a newer supported Xcode), then retrying the same UDID without uninstalling the App.

## Round 1 Install and Launch

- Actual Round 1 installed commit: none.
- Install result: NOT RUN because the physical-device build was blocked by DDI compatibility.
- Launch result: NOT RUN because no Round 1 build was installed.
- The existing App was not uninstalled and its data was not cleared or rebuilt.
- No TestFlight upload, App Store Connect configuration, release or `main` merge was performed.

## Owner Physical-device Retest Required

- [ ] Simplified Chinese interface coverage.
- [ ] English interface regression.
- [ ] Once-per-day Habit behavior.
- [ ] Multiple-per-day Habit behavior and optional target count.
- [ ] Rapid repeated Habit Check-in protection.
- [ ] Habit Check-in haptic feedback.
- [ ] Latest Habit Check-in undo.
- [ ] Habit rename with existing history.
- [ ] Habit recording-mode switch with existing history.
- [ ] Timeline landscape, portrait, long and edge-subject images.
- [ ] Goal card navigation and editing.
- [ ] Flag card navigation and editing.
- [ ] Today initial empty-state guidance.
- [ ] Add Goal/Flag button prominence.
- [ ] Library Tag creation and no-Tag selection guidance.
- [ ] Existing test data remains after overlay installation.

## Still Unverified

- [ ] Round 1 physical-device build, overlay install and launch after installing compatible Xcode device support.
- [ ] Round 1 launch-crash observation on the physical iPhone.
- [ ] Representative physical-device responsiveness, memory, heat and storage behavior.
- [ ] Accessibility and Dynamic Type review on the physical device.
- [ ] Offline workflow checks.
- [ ] Export, Import and disposable restore rehearsal.
- [ ] Full Owner Manual Validation Checklist.
- [ ] Candidate acceptance, Dogfooding and the continuous 30-day observation.

## Known V1 Limits

- Language follows iOS; there is no in-App language switch or first-launch language picker.
- Multiple-per-day Habits track counts only; there is no unit, volume, duration, weekly target or custom interval system.
- Existing Habits without configuration read as multiple-per-day with no target; no Habit, ID or Check-in is recreated.
- Changing a Habit to once-per-day constrains future Check-ins only and does not rewrite historical same-day records.
- Goal and Flag editing remains intentionally limited to existing core fields; no reminder or project-management state machine was added.
- Timeline uses bounded aspect-fit thumbnails; full original viewing remains in entry detail.
