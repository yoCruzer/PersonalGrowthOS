# Product regression: 47df1f3

GitHub Actions run [42438147022](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42438147022) completed successfully on its first automatic PR-triggered attempt. Source head: `47df1f3cad80270bded407078fab86d26be6f46b`; tested merge checkout: `55aef2cf3152843079971ff82024c114e2f0542e`.

- Release: unsigned iOS build passed; app, ShareExtension and ImportantDaysWidget bundles verified. No Archive, TestFlight or publication.
- Unit: **599 total, 598 passed, 0 failed, 1 skipped**. `TodoFoundationTests.testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure` requires an isolated 32 MB HFS+ test image; the runner must not fill its primary volume. This remains unverified by this run.
- Smoke: **5 passed, 0 failed, 0 skipped**, including narrow-screen and accessibility text checks. Both test lanes used iPhone 13 mini / iOS 27.2 (24B8117), Xcode 27.0 (27A266a), ARM64.
- Optional extended UI: skipped because this was a PR event, not a manually selected extended suite. Those suites were not exercised here.
- Build warnings retained: AppIntents metadata extraction has no framework dependency; four existing `ImportExportRecoveryTests` asynchronous-context `wait` call sites warn about future Swift 6 language mode. Both xcresult summaries have empty `runtimeWarnings` arrays. This run does not claim warning-free builds.

`test-summary.json` and `test-tests.json` are unmodified original artifact members. Environment files select public fields; warning excerpts replace only the hosted checkout prefix. The three original ZIPs and their extracted members remain outside the repository. Each exact ZIP SHA256 matches its GitHub artifact digest, and each extracted member was byte-verified against the ZIP. `source-files-sha256.json` binds all extracted bytes. Public metadata contains no temporary signed download URL.

Only synthetic hosted CI evidence is included. No Owner schema originals, screenshots, provisioning profiles, certificates or daily business data were read or copied. Product source identity equality against d508ae4 is supporting context only; these new actual results were independently collected. No workflow rerun was requested.
