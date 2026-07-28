# V1 Device Validation Report

## Validation Context

| Item | Confirmed value |
| --- | --- |
| Validation date | 2026-07-28 |
| Fixed original Candidate | `2e31e8a753005f8bb40bce348820529775aa2e9d` |
| Tested commit | `a0d423331c512986a4c731175045ac7f5e93adb3` |
| Branch | `test/v1-device-validation-round1` |
| Xcode | 26.6 (`17F113`) |
| Shared scheme | `PersonalGrowthOS` |
| Configuration | Debug |
| Bundle identifier | `com.yocruzer.PersonalGrowthOS` |

## Device

| Item | Confirmed value |
| --- | --- |
| Device name | 蔡先生的iPhone |
| Model | iPhone 16 (`iPhone17,3`) |
| iOS | 26.5.2 (`23F84`) |
| Xcode destination UDID | `00008140-00096D1E21D0801C` |
| CoreDevice identifier | `1602D9E0-4D13-59BA-93AD-1BEBAEB1C7D3` |
| Connection | Connected over USB; paired; CoreDevice tunnel connected |
| Developer Mode | Enabled |

## Signing and Provisioning

- App Target Debug and Release use `CODE_SIGN_STYLE = Automatic`.
- App Target Debug and Release use `DEVELOPMENT_TEAM = 83SKX2PM7B`.
- No project capability, entitlement file, Bundle Identifier or test-target signing change was added for this validation.
- Xcode selected an Apple Development identity and the Xcode-managed `iOS Team Provisioning Profile: *` profile.
- The embedded profile Team Identifier is `83SKX2PM7B`.
- The embedded profile includes device UDID `00008140-00096D1E21D0801C`; device registration is therefore confirmed for the profile used by this build.
- The signed application identifier is `83SKX2PM7B.com.yocruzer.PersonalGrowthOS`.

## Build

Command:

```sh
xcodebuild \
  -project PersonalGrowthOS.xcodeproj \
  -scheme PersonalGrowthOS \
  -configuration Debug \
  -destination 'platform=iOS,id=00008140-00096D1E21D0801C' \
  -destination-timeout 60 \
  -derivedDataPath /tmp/PersonalGrowthOS-Device-DerivedData-a0d4233 \
  -resultBundlePath /tmp/PersonalGrowthOS-DeviceBuild-a0d4233.xcresult \
  -allowProvisioningUpdates \
  -allowProvisioningDeviceRegistration \
  -showBuildTimingSummary \
  build
```

Result: PASS — `** BUILD SUCCEEDED **`. The dependency graph contained only the `PersonalGrowthOS` App Target. Asset Catalog compilation, arm64 compilation, provisioning, code signing and bundle validation completed successfully.

Application artifact:

```text
/tmp/PersonalGrowthOS-Device-DerivedData-a0d4233/Build/Products/Debug-iphoneos/PersonalGrowthOS.app
```

Build result bundle:

```text
/tmp/PersonalGrowthOS-DeviceBuild-a0d4233.xcresult
```

## Install

Result: PASS — `devicectl device install app` installed `com.yocruzer.PersonalGrowthOS` without first uninstalling the existing app.

Device installation path:

```text
/private/var/containers/Bundle/Application/15EA4293-D4F0-4804-8426-5D2EA314D5A5/PersonalGrowthOS.app
```

## Launch

Result: PASS for process launch — `devicectl device process launch` successfully launched `com.yocruzer.PersonalGrowthOS` in the foreground.

A console-attached launch remained running for more than 40 seconds without crash output. After ending that diagnostic attachment, a final ordinary foreground launch succeeded, and a subsequent device process query confirmed the app still running as PID 1329.

The following visual check remains Owner-confirmed only:

- [ ] Today, Timeline, Growth and Library are all visible and reachable on the physical iPhone.

## Uncompleted Physical-device Validation

The following items remain untested or unconfirmed and must not be treated as passed:

- [ ] Owner confirmation of the four primary navigation entrances.
- [ ] Camera capture and Camera permission behavior.
- [ ] Photos Picker behavior, selection, ordering and Photos permission recovery.
- [ ] Representative physical-device responsiveness, memory, heat and storage behavior.
- [ ] Accessibility and Dynamic Type review on the physical device.
- [ ] Offline workflow checks.
- [ ] Export, Import and disposable restore rehearsal.
- [ ] Full Owner Manual Validation Checklist.
- [ ] Candidate acceptance, Dogfooding and the continuous 30-day observation.

No TestFlight upload, App Store Connect configuration, release, merge, device-app deletion or destructive Export/Import rehearsal was performed.
