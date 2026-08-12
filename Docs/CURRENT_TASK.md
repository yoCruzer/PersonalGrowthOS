# Current Task

| Item | Value |
| --- | --- |
| Current checkpoint | Post-V1 Usability S2 — Build 5 candidate ready for independent review |
| Status | BUILD 4 OWNER FEEDBACK FIXED LOCALLY — DRAFT PR #2 OPEN |
| Execution branch | `feature/usability-s2-review-loop` |
| Base | `c45c666` (`design: refresh app icon for Suixin Log`) |
| Prior committed UX work | `53f2326` add-action consistency; `06cc913` reversible repeatable Habit check-ins |
| Automated gate | PASS — 142 Unit tests, 3 focused UI smokes, 25 full UI tests and Simulator Debug build |
| External V1 release status | Separate Owner-only Build 3 archive/export/upload work remains on `feature/v1-completion-push` |

## Objective

Resolve the Build 4 Owner feedback without widening S2: restore the Weekly Review save/keyboard closure, compact the repeatable-Habit card, make the global floating controls input-aware and draggable, and close the two bounded Entry-media UX debts. The resulting code is a Build 5 candidate for independent review only; do not consume Build 5, archive, upload, publish or merge it in this batch.

The user starts a weekly review explicitly from Today. The screen shows only local facts from the natural current week (Entries, entry days/photos, completed HabitLogs, a representative Habit, Weight change, Tags and recent Entries). The user may write what to remember, what to improve, a next step and one focus, then save and later reopen the same week’s review. Nothing is generated automatically.

## Completed Boundary

- Schema V7 adds `WeeklyReview` with one stable natural-week identifier; V6 stores migrate without changing existing Entry, Habit or Weight data.
- Weekly Review identity uses centralized ISO-style Gregorian Monday-week rules with local time-zone semantics, independent of Locale, Region and non-Gregorian system calendar selection.
- The local summary has empty-state semantics and excludes Review Entries from Entry activity totals.
- Weekly Review is available from Today and remains voluntary; opening the screen creates no record.
- A record is created only from the explicit Start action; optional text is trimmed and restart persistence is covered.
- Full backups use package schema v3 and preserve WeeklyReview identity and fields. Import remains compatible with schema v1/v2 packages that contain no WeeklyReview data.
- Once-per-day Habit Undo remains unchanged. Multiple-per-day detail and Insight check-ins rely solely on immediate +/- counter reversal; decrement retains linked Entry content and its Habit relation.
- English and Simplified Chinese strings are supplied for the new flow.
- Targeted validation passed: Habit + Weekly Review Unit 37/37, schema-v3/Weekly Review import-export 3/3 and focused mixed-path UI smoke 1/1.
- Full Unit validation passed: 141/141.
- Version 1.0 (Build 4) Release Archive was prepared from `bacb504afb30c582c869ae68f8558831c5067437` at `/tmp/PersonalGrowthOS-S2-Build4.xcarchive`; local Archive metadata and formal AppIcon inspection passed.
- Build 4 Owner iPhone validation passed V5→V6→V7 overlay migration, retention/relaunch of existing data, Weight persistence, repeatable-Habit `+++--`, Insight→`+`→`-` linked-Entry retention, explicit-only Weekly Review creation, and V7 export.
- Build 4 failed the Weekly Review save/Chinese keyboard closure; the current candidate adds explicit focus/keyboard dismissal, visible save success/failure feedback, and a stable save refetch. Build 5 Owner revalidation remains required.
- The Archive has not been exported or uploaded to App Store Connect, and Draft PR #2 remains open.

## Explicit Non-Goals

- No automatic weekly/monthly/yearly report or prompt.
- No AI summary, mood analysis, advanced statistics, templates, reminders or generated conclusions.
- No new task, Goal, HealthKit, diet, medical or health-advice behavior.
- No change to the existing lightweight manual `EntryKind.review` model.
- No App Store export, upload, Archive, build-number bump, merge to `main`, signing/account configuration change, or Build 5 physical-device claim in this batch.

## Next Action

Have the incremental Build 4 feedback diff independently reviewed. If accepted, then raise the build number and prepare a new Build 5 Archive for Owner iPhone revalidation of Weekly Review Chinese input/save/relaunch, floating-control interaction, Habit compact layout and Entry media preview. Keep [Draft PR #2](https://github.com/yoCruzer/PersonalGrowthOS/pull/2), this branch and the separate Build 3 distribution handoff unmerged.
