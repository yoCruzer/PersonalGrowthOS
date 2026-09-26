# Known Limitations

2026-09-26 当前入口：[CURRENT_STATE](CURRENT_STATE.md) / [统一收口计划](EXTERNAL_CAPTURE_EXECUTION_PLAN.md#统一收口审计-2026-09-26)。当前 External Capture 候选仍在统一门禁前；以下历史 Build 3/4/5 记录不代表当前发布阻塞。真机事项统一到 [当前候选清单](OWNER_MANUAL_VALIDATION_CHECKLIST.md)，不逐代重复。

## V1 Product Boundaries

- Weight uses kilograms only. It intentionally provides no diet, exercise, calorie, BMI judgement, diagnosis, HealthKit sync, target plan, reminder, advice or multidimensional health analysis.
- Review remains manual and lightweight. There are no automatic reports, templates or advanced analytics.
- Search remains a local in-memory normalized scan. OCR, semantic search and a separate full-text index are out of scope.
- CloudKit and multi-device sync remain disabled.

## Data Transfer

- Backup ZIP files are unencrypted and contain sensitive personal records, Entry text and original photos.
- Import is full restore into an empty database only. Merge import and erase-and-restore are intentionally unavailable.
- Current exports use package schema v6, including source metadata, pins and follow-ups as well as existing records. The current app imports valid v1–v6 packages; older app builds are expected to reject newer schemas rather than silently discard data they do not understand.
- The importer targets the stored ZIP/ZIP64 subset emitted by this app, not arbitrary third-party compression variants.

## Current Capture and Device Boundaries

- Share-sheet capture uses public APIs; no full article extraction, site adaptation, AI/OCR or invented source-app identity. Real Photos/WeChat provider variations, signed App Group access, actual network/offline behavior and Owner store overlay remain OWNER_REQUIRED.
- Pending Shares are retained separately from ordinary backups until imported. Export drains consumable shares and discloses the count still excluded; unknown schema is retained, and discard requires per-item confirmation.
- Current schema is V10. The historical default simulator main file has a V8 identifier and a HabitPlanRevision hash different from the frozen V8 fixture; WAL was not replayed during read-only inspection. Its origin and relevance to Owner data remain unverified; no erase/rebuild fallback is provided.
- Build 9 tag/Archive success and project 1.0(7) are separate identity facts. Actual cloud build and TestFlight availability are UNKNOWN/OWNER_REQUIRED; see the execution plan. Existing Xcode Cloud remains the sole configured release workflow.

## Historical Persistence and Device Validation (superseded)

- Automated V5→V6 and V6→V7 fixtures preserve representative existing identities and fields; the V6→V7 migration adds Weekly Review without changing existing Entry, Habit or Weight data. Build 4 Owner iPhone validation also passed the V5→V6→V7 overlay and restart recovery of the existing store.
- Build 4 Owner validation passed Weight persistence and V7 export. Weekly Review's explicit-only creation passed, but its Chinese keyboard/save/relaunch closure failed; the current Build 5 candidate fixes that flow and still requires Owner physical revalidation before merge/release.
- Build 3 remains a separate historical distribution handoff and has not been installed on a physical device in this S2 validation stream.
- Actual iCloud multi-device validation was not performed because CloudKit is intentionally disabled in V1.

## Historical Build 3 Distribution Blocker (superseded)

- The Version 1.0 (Build 3) Archive exists at `/tmp/PersonalGrowthOS-V1Final-Build3.xcarchive`.
- App Store Connect export, server validation and upload are blocked because Xcode has no signed-in Apple account and the keychain has no iOS Distribution certificate.
- This blocks Build 3 TestFlight availability, but does not block local implementation, automated validation or Archive completeness.

## Existing Technical Debt

- Entry, Tag, Habit, Goal, Weight and Weekly Review mutation services use the shared main `ModelContext`; rollback can discard unrelated unsaved UI changes. This remains bounded pre-existing debt. External Capture and backup restore now publish through private worker contexts with a shared store lease; their failure paths do not rollback the main editing context.
- No open image-presentation debt remains from UX-01/UX-02; their bounded Build 5 candidate resolutions are recorded in `Docs/UX_DEBT.md` and need normal Owner interaction verification.
