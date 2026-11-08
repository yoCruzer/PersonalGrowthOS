# Product regression: d508ae4

GitHub Actions run [42435822140](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42435822140) completed successfully on its first automatic PR-triggered attempt. Source head: `d508ae41f8f87adff790c65cc090f217206e0e18`; tested merge checkout: `ead8f0c1e1850740a2aa43138075b04357796e73`.

- Release: unsigned iOS build passed; app, ShareExtension and ImportantDaysWidget bundles verified. No Archive, TestFlight or publication.
- Unit: **599 total, 598 passed, 0 failed, 1 skipped**. The skipped `TodoFoundationTests.testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure` requires an isolated 32 MB HFS+ test image; the CI runner must not fill its primary volume. This remains unverified by this run.
- Smoke: **5 passed, 0 failed, 0 skipped**, including narrow-screen and accessibility text checks. Both test lanes used iPhone 13 mini / iOS 27.2 (24B8117), Xcode 27.0 (27A266a), ARM64.
- Optional extended UI: skipped because this was a PR event, not a manually selected extended suite. Those suites were not exercised here.
- Build warnings retained: AppIntents metadata extraction has no framework dependency; four existing `ImportExportRecoveryTests` asynchronous-context `wait` call sites warn about future Swift 6 language mode. No runtime warnings were reported in either xcresult summary. This run does not claim warning-free builds.

`test-summary.json` and `test-tests.json` are unmodified extracted CI artifact members. Environment files select public fields; warning excerpts replace only the hosted checkout prefix. Original compact artifact members remain in the local temporary download directory, and `source-files-sha256.json` binds their bytes. All three original ZIPs are retained outside the repository; their exact SHA256 values match GitHub artifact digests, and all extracted members were byte-compared with those ZIPs. Artifact metadata records original ZIP digests. No Owner CKDB, screenshots, exports, or daily business data are included.

The product source identity comparison is supporting context only; these are new actual results, not a substitution of an earlier run. The GitHub connector supplied run/job/artifact metadata. A sandbox network restriction on the first CLI download was resolved with authorized network access; the same existing artifacts were downloaded, with no workflow rerun.
