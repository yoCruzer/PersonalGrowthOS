# Build 8 Habit Analytics — In-progress Implementation Record

| Item | Value |
| --- | --- |
| Baseline | `95076bf5c2a86122fbd327903d80bccdfb8c768d` |
| Branch | `feature/build8-habit-analytics-dashboard` |
| State | In progress — not a review candidate |

## Implemented foundation

- SwiftData V8 adds `HabitLogDayMetadata`, `HabitPlanRevision` and `HabitLifecycleEvent`. The exact V7 `HabitLog` shape remains unchanged; immutable Local Day, time-zone and provenance live in the additive metadata entity keyed uniquely by HabitLog ID.
- New check-ins atomically persist their Gregorian civil day metadata with the HabitLog. The weekly calculation shares the existing Monday-first, four-day-first-week policy.
- On first V8 launch, legacy logs are frozen using that migration device's local civil calendar and time-zone identifier. Legacy plans and lifecycle truth begin at the migration boundary, so earlier activity stays visible but does not receive fabricated strict adherence.
- Habit creation creates an effective plan/lifecycle record. Status changes append lifecycle events in the same save operation. Plans are effective-dated; replacing a pending boundary replaces that pending revision.
- Plan revisions persist `recordingMode` independently from schedule. Once/day caps credit at one per Local Day for day/week/month targets; multiple/day preserves every positive completion. Tracking Only also retains its explicit recording mode, and backup v4 requires and round-trips it.
- Runtime settings come from the Plan effective on the relevant Local Day across Today, Overview, Detail and check-in validation. Legacy configuration is only a no-effective-Plan fallback, so a contradictory mutable configuration cannot change V8 behavior.
- Name-only edits do not create or replace Plan revisions. The editor loads an existing pending Plan and shows its effective date; a real Plan change removes the never-effective pending revision before writing one replacement.
- Current adherence, consistency and streaks are limited to the current contiguous Plan/lifecycle segment. Returning from week/month/Tracking Only or from pause/completion/archive cannot join metrics to an earlier same-period region.
- Local Day parsing is Gregorian-valid; backdated positives recompute historical outcomes. Legacy Plan/lifecycle truth begins at a conservative migration boundary using a hidden `migrationBaseline` plus known current status. Resume, Restart and Restore are distinct, same-day events are deterministic, and Journey merges visible Plan/lifecycle facts chronologically.
- The pure `HabitAnalyticsEngine` derives grouped credit, period progress, outcomes, strict adherence, consistency, streaks and activity cells from value snapshots.
- Once-per-day credit is capped at one positive completion per immutable Local Day; multiple-per-day credit retains each positive completion. A plan change inside an open week/month leaves that whole strict period neutral rather than fabricating a miss.
- Plan edits use next-day/next-Monday/next-month boundaries; cross-period edits choose the coarser boundary. Journey filters out not-yet-effective revisions and Context uses existing Entry/Habit/Goal links.
- Backup package v4 carries Local Day metadata, plan revisions and lifecycle events while decoding v1–v3 payloads without these fields.
- v4 export/import preserves plan revision and lifecycle IDs plus HabitLog Local Day/time-zone provenance; old-package imports are bootstrapped during the same atomic publication transaction.
- Older package schemas reject v4-only Plan/lifecycle payloads instead of silently materializing them. The Dashboard, streak units and Journey strings compile for English and Simplified Chinese and are exercised through localized UI flows.

## Current UI integration

- Habits are grouped as Today, This Week, This Month or Tracking Only using plan data, never the Habit name. Overview rows consume the same authoritative current-segment snapshot as Detail and report actual/target/remaining for day, week and month or honest record counts for Tracking Only; active rows retain direct check-in or +/- controls without turning the row itself into the control.
- The editor exposes No Goal, Every Day, Selected Days, Times per Week and Times per Month, and restores the current effective plan when editing.
- Habit Detail starts with a Now section containing current-period progress, lifecycle status, the primary structured check-in, Insight/Details routes, adherence and streaks. The dashboard follows rather than displacing the action surface.
- Daily Progress is a full current civil-month calendar that distinguishes achieved, missed, open, rest, lifecycle-neutral, pre-coverage and future dates while retaining factual rest-day activity. Weekly/monthly/tracking-only Progress remains scoped to the current evaluation; Year Activity is a separate 365-day view.
- Recent Activity is bounded to five facts and links to full history. The remaining dashboard includes Consistency, Trend, effective Journey and linked Context. Daily weekday pattern values are achieved/eligible success rates over strict scheduled outcomes; rest/open/neutral days are excluded. Weekly/monthly/tracking-only values are explicitly labeled factual activity distributions.

## Stage 0 recovery checkpoint

- Sunday is selectable using the documented `1 = Sunday ... 7 = Saturday` identity, independent of the device's first weekday.
- Selected-day schedules define expectation only: a rest-day activity fact can be stored while analytics keeps that day `notScheduled`.
- Once/day duplicate detection, Today completion and repeatable decrement use persisted Local Day; only positive completed logs contribute to completion/count/decrement.
- A false log does not mark Today complete and does not block an immediate true completion on the same Local Day.

## Stage 1 real V7 migration checkpoint

- `PersonalGrowthOSTests/Fixtures/Build7V7Fixture` was generated by the exact `95076bf5c2a86122fbd327903d80bccdfb8c768d` source and contains representative V7 SQLite and media facts.
- The first real overlay rejected direct Local Day columns on `HabitLog` because that design changed the historical V7 model checksum (`Cannot use staged migration with an unknown model version`). No destructive fallback was used.
- The corrected additive metadata design opens that V7 store, preserves Entry/Image/Habit/HabitLog/Goal/ObjectLink/Weight/WeeklyReview IDs and facts, bootstraps Local Day metadata/plans/lifecycle exactly once, and reopens with the same additions and civil days under a different time zone.

## Known gaps before Build 8 can be reviewed

- The complete acceptance matrix has not yet been exercised end-to-end. Real V7→V8 migration/bootstrap, Local Day credit/validation, historical `recordingMode`, runtime/pending Plan correctness, contiguous segments, lifecycle history, period-aware P0/P1 dashboard, backup schema boundaries and Dashboard localization are covered; final visual/a11y polish and all-package regression remain.
- Remote head is `bdb17449af6db016b70fd404712b2342e27e8504`; recovered staged checkpoints remain local until the final Build 8 gate. No Draft PR, archive, TestFlight action or merge has occurred.
- Physical-device validation is entirely outstanding.

## Verification so far

- Simulator Debug build: PASS after the V8 model/backup/dashboard integration.
- Focused V8 Local Day/bootstrap, daily-credit, lifecycle-boundary and future-occurrence tests: 4/4 PASS on iPhone 16 Simulator, iOS 26.5 (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-07-04-+0800.xcresult`).
- v4 full import/export round-trip: PASS on iPhone 16 Simulator, iOS 26.5 (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-12-27-+0800.xcresult`).
- Cross-period plan-boundary test: PASS on iPhone 16 Simulator, iOS 26.5 (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-16-21-+0800.xcresult`).
- Habit Foundation suite: 38/38 PASS on iPhone 17 Pro Simulator, iOS 26.5, including V7→V8 bootstrap and week-credit/transition cases (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-26-56-+0800.xcresult`).
- Recovered Stage 0 Habit Foundation suite: 45/45 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-Stage0-HabitFoundation.xcresult`). The complete Build 8 gate has not run.
- Exact-`95076bf` fixture generation: 1/1 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build7-V7Fixture-Generate.xcresult`).
- Stage 1 migration/Habit/transfer regression: 48/48 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-Stage1-Targeted2.xcresult`). The complete Build 8 gate has not run.
- Stage 2 Habit/recording-mode/transfer regression: 50/50 PASS (`/tmp/PersonalGrowthOS-Build8-Stage2-RecordingMode.xcresult`) plus focused real-migration and v4 proof 5/5 PASS (`/tmp/PersonalGrowthOS-Build8-Stage2-RecordingMode-2.xcresult`) on iPhone 17 Pro Simulator, iOS 26.5.
- Stage 3 effective-Plan runtime regression: Habit Foundation 49/49 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-Stage3-RuntimeTruth.xcresult`).
- Stage 4 pending-Plan regression: Habit Foundation 50/50 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-Stage4-PendingPlan.xcresult`).
- Stage 5 contiguous-analytics regression: Habit Foundation 54/54 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-Stage5-ContiguousAnalytics.xcresult`).
- Stage 6/7 Local Day/lifecycle/v4 regression: 58/58 PASS (`/tmp/PersonalGrowthOS-Build8-Stage67-LocalDayLifecycle.xcresult`), focused validation 2/2 PASS (`/tmp/PersonalGrowthOS-Build8-Stage67-Focused.xcresult`), and conservative real-migration boundary 2/2 PASS (`/tmp/PersonalGrowthOS-Build8-Stage67-MigrationBoundary.xcresult`) on iPhone 17 Pro Simulator, iOS 26.5.
- Stage 8 P0 dashboard regression: Habit Foundation 60/60 PASS (`/tmp/PersonalGrowthOS-Build8-Stage8-P0Dashboard-Final.xcresult`) on iPhone 17 Pro Simulator, plus focused create/check-in/detail UI 1/1 PASS (`/tmp/PersonalGrowthOS-Build8-Stage8-P0UI.xcresult`) and visual inspection of the Now/month-calendar hierarchy on a clean iPhone 16 Simulator, iOS 26.5.
- Stage 9 weekday-pattern regression: Habit Foundation 62/62 PASS (`/tmp/PersonalGrowthOS-Build8-Stage9-WeekdayPattern.xcresult`) on iPhone 17 Pro Simulator, iOS 26.5, including daily scheduled-denominator exclusions and weekly/monthly/tracking-only activity distribution.
- Stage 10 backup/localization regression: Habit Foundation plus Import/Export Recovery 88/88 PASS (`/tmp/PersonalGrowthOS-Build8-Stage10-BackupLocalizationFinal.xcresult`) on iPhone 16 Simulator, iOS 26.5. Focused English/system-language UI 2/2 PASS (`/tmp/PersonalGrowthOS-Build8-Stage10-EnDashboardUI.xcresult`) and Simplified Chinese Dashboard UI 1/1 PASS (`/tmp/PersonalGrowthOS-Build8-Stage10-ZhDashboardUI2.xcresult`). The 423-entry catalog parses with complete English and Simplified Chinese values; all 85 explicit `HabitViews` localization keys resolve, and both language catalogs compile independently.
