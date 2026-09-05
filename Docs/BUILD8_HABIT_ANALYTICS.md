# Build 8 Habit Analytics — In-progress Implementation Record

| Item | Value |
| --- | --- |
| Baseline | `95076bf5c2a86122fbd327903d80bccdfb8c768d` |
| Branch | `feature/build8-habit-analytics-dashboard` |
| State | In progress — not a review candidate |

## Implemented foundation

- SwiftData V8 adds `HabitPlanRevision` and `HabitLifecycleEvent`; `HabitLog` now stores an optional immutable Local Day and time-zone provenance.
- New check-ins persist their Gregorian civil day. The weekly calculation shares the existing Monday-first, four-day-first-week policy.
- On first V8 launch, legacy logs are frozen using that migration device's local civil calendar and time-zone identifier. Legacy plans and lifecycle truth begin at the migration boundary, so earlier activity stays visible but does not receive fabricated strict adherence.
- Habit creation creates an effective plan/lifecycle record. Status changes append lifecycle events in the same save operation. Plans are effective-dated; replacing a pending boundary replaces that pending revision.
- The pure `HabitAnalyticsEngine` derives grouped credit, period progress, outcomes, strict adherence, consistency, streaks and activity cells from value snapshots.
- Once-per-day credit is capped at one positive completion per immutable Local Day; multiple-per-day credit retains each positive completion. A plan change inside an open week/month leaves that whole strict period neutral rather than fabricating a miss.
- Plan edits use next-day/next-Monday/next-month boundaries; cross-period edits choose the coarser boundary. Journey filters out not-yet-effective revisions and Context uses existing Entry/Habit/Goal links.
- Backup package v4 carries Local Day metadata, plan revisions and lifecycle events while decoding v1–v3 payloads without these fields.
- v4 export/import preserves plan revision and lifecycle IDs plus HabitLog Local Day/time-zone provenance; old-package imports are bootstrapped during the same atomic publication transaction.

## Current UI integration

- Habits are grouped as Today, This Week, This Month or Tracking Only using plan data, never the Habit name; active rows provide direct check-in or +/- controls without turning the row itself into the control.
- The editor exposes No Goal, Every Day, Selected Days, Times per Week and Times per Month, and restores the current effective plan when editing.
- Habit Detail has current-period day/week/month activity grids, Adherence, Consistency, streaks, trend, weekday pattern, effective Journey, linked Context and a 365-day heatmap.

## Stage 0 recovery checkpoint

- Sunday is selectable using the documented `1 = Sunday ... 7 = Saturday` identity, independent of the device's first weekday.
- Selected-day schedules define expectation only: a rest-day activity fact can be stored while analytics keeps that day `notScheduled`.
- Once/day duplicate detection, Today completion and repeatable decrement use persisted Local Day; only positive completed logs contribute to completion/count/decrement.
- A false log does not mark Today complete and does not block an immediate true completion on the same Local Day.

## Known gaps before Build 8 can be reviewed

- The complete acceptance matrix has not yet been implemented or exercised. V7→V8 migration/bootstrap, day-credit and plan-transition cases are covered, but calendar/DST variants, selected-weekday UI, all lifecycle/schedule combinations, visual row-polish, full backup compatibility and all-package regression remain.
- Remote head is `bdb17449af6db016b70fd404712b2342e27e8504`; the recovered Stage 0 checkpoint has not been pushed. No Draft PR, archive, TestFlight action or merge has occurred.
- Physical-device validation is entirely outstanding.

## Verification so far

- Simulator Debug build: PASS after the V8 model/backup/dashboard integration.
- Focused V8 Local Day/bootstrap, daily-credit, lifecycle-boundary and future-occurrence tests: 4/4 PASS on iPhone 16 Simulator, iOS 26.5 (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-07-04-+0800.xcresult`).
- v4 full import/export round-trip: PASS on iPhone 16 Simulator, iOS 26.5 (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-12-27-+0800.xcresult`).
- Cross-period plan-boundary test: PASS on iPhone 16 Simulator, iOS 26.5 (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-16-21-+0800.xcresult`).
- Habit Foundation suite: 38/38 PASS on iPhone 17 Pro Simulator, iOS 26.5, including V7→V8 bootstrap and week-credit/transition cases (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-26-56-+0800.xcresult`).
- Recovered Stage 0 Habit Foundation suite: 45/45 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-Stage0-HabitFoundation.xcresult`). The complete Build 8 gate has not run.
