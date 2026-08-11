# Known Limitations

## V1 Product Boundaries

- Weight uses kilograms only. It intentionally provides no diet, exercise, calorie, BMI judgement, diagnosis, HealthKit sync, target plan, reminder, advice or multidimensional health analysis.
- Review remains manual and lightweight. There are no automatic reports, templates or advanced analytics.
- Search remains a local in-memory normalized scan. OCR, semantic search and a separate full-text index are out of scope.
- CloudKit and multi-device sync remain disabled.

## Data Transfer

- Backup ZIP files are unencrypted and contain sensitive personal records, Entry text and original photos.
- Import is full restore into an empty database only. Merge import and erase-and-restore are intentionally unavailable.
- Current exports use package schema v3 to include Weight and Weekly Review records. The current app imports v1, v2 and v3; older app builds are expected to reject newer schemas rather than silently discard data they do not understand.
- The importer targets the stored ZIP/ZIP64 subset emitted by this app, not arbitrary third-party compression variants.

## Persistence and Device Validation

- Automated V5→V6 and V6→V7 fixtures preserve representative existing identities and fields; the V6→V7 migration adds Weekly Review without changing existing Entry, Habit or Weight data. The exact Owner TestFlight store still requires an overlay migration test.
- Weight and Weekly Review persistence, backup and relaunch are simulator-verified only on this branch.
- Build 3 has not been installed on a physical device. The V5→V6/V6→V7 overlay, Weight behavior, Weekly Review behavior and backup flow remain Owner physical validation.
- Actual iCloud multi-device validation was not performed because CloudKit is intentionally disabled in V1.

## Distribution Blocker

- The Version 1.0 (Build 3) Archive exists at `/tmp/PersonalGrowthOS-V1Final-Build3.xcarchive`.
- App Store Connect export, server validation and upload are blocked because Xcode has no signed-in Apple account and the keychain has no iOS Distribution certificate.
- This blocks Build 3 TestFlight availability, but does not block local implementation, automated validation or Archive completeness.

## Existing Technical Debt

- Entry, Tag, Habit, Goal, Weight and Weekly Review mutation services use the shared main `ModelContext`; rollback can discard unrelated unsaved UI changes. Import publication and persistence recovery also use that context-level rollback pattern. This is accepted non-blocking debt.
- Image presentation debts UX-01 and UX-02 are tracked in `Docs/UX_DEBT.md`.
