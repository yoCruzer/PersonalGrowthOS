# Known Limitations

## V1 Product Boundaries

- Weight uses kilograms only. It intentionally provides no diet, exercise, calorie, BMI judgement, diagnosis, HealthKit sync, target plan, reminder, advice or multidimensional health analysis.
- Review remains manual and lightweight. There are no automatic reports, templates or advanced analytics.
- Search remains a local in-memory normalized scan. OCR, semantic search and a separate full-text index are out of scope.
- CloudKit and multi-device sync remain disabled.

## Data Transfer

- Backup ZIP files are unencrypted and contain sensitive personal records, Entry text and original photos.
- Import is full restore into an empty database only. Merge import and erase-and-restore are intentionally unavailable.
- Current exports use package schema v2 to include Weight. The current app imports v1 and v2; older app builds are expected to reject v2 rather than silently discard Weight.
- The importer targets the stored ZIP/ZIP64 subset emitted by this app, not arbitrary third-party compression variants.

## Persistence and Device Validation

- Automated V5→V6 fixtures preserve existing Entry, Habit and Goal data, but the exact Owner TestFlight store still requires an overlay migration test.
- Weight persistence, backup and relaunch are simulator-verified only in this push.
- No new physical-device, TestFlight-build or actual iCloud multi-device validation was performed.

## Existing Technical Debt

- Entry, Tag and Habit mutations use the shared main `ModelContext`; rollback can discard unrelated unsaved UI changes. This is accepted non-blocking debt.
- Image presentation debts UX-01 and UX-02 are tracked in `Docs/UX_DEBT.md`.
