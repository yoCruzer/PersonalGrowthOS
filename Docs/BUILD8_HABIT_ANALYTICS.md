# Build 8 Habit Analytics — Draft Review Handoff

| Item | Value |
| --- | --- |
| Baseline | `95076bf5c2a86122fbd327903d80bccdfb8c768d` |
| Branch | `feature/build8-habit-analytics-dashboard` |
| State | Draft review candidate — automated gate passed; Owner device validation outstanding |
| Draft PR | [#5](https://github.com/yoCruzer/PersonalGrowthOS/pull/5), base `fix/build7-owner-feedback-round2` |

## Implemented foundation

- SwiftData V8 adds `HabitLogDayMetadata`, `HabitPlanRevision` and `HabitLifecycleEvent`. The exact V7 `HabitLog` shape remains unchanged; immutable Local Day, time-zone and provenance live in the additive metadata entity keyed uniquely by HabitLog ID.
- New check-ins atomically persist their Gregorian civil day metadata with the HabitLog. The weekly calculation shares the existing Monday-first, four-day-first-week policy.
- On first V8 launch, legacy logs are frozen using that migration device's local civil calendar and time-zone identifier. Legacy plans and lifecycle truth begin at the migration boundary, so earlier activity stays visible but does not receive fabricated strict adherence.
- Habit creation creates an effective plan/lifecycle record. Status changes append lifecycle events in the same save operation. Plans are effective-dated; replacing a pending boundary replaces that pending revision.
- Plan revisions persist `recordingMode` independently from schedule plus an origin that distinguishes migration bootstrap from user-authored changes. Once/day caps credit at one per Local Day and is validated to exactly 1/day, 1–7/week or 1–28/month; multiple/day requires a positive integer target for goal plans. Tracking Only retains its explicit recording mode, and backup v4 requires and round-trips the plan data.
- Runtime settings come from the Plan effective on the relevant Local Day across Today, Overview, Detail and check-in validation. Legacy configuration is only a no-effective-Plan fallback, so a contradictory mutable configuration cannot change V8 behavior.
- Name-only edits do not create or replace Plan revisions. The editor loads an existing pending Plan and shows its effective date; a real Plan change removes the never-effective pending revision before writing one replacement.
- Current adherence, consistency and Current Streak are limited to the current contiguous compatible period/lifecycle segment. Same-period target or selected-weekday changes preserve continuity while each historical period is judged by its then-effective Plan. Best Streak retains the maximum from historical same-unit segments without joining across lifecycle, period-kind or Tracking Only boundaries.
- Local Day parsing is Gregorian-valid; backdated positives recompute historical outcomes. Legacy Plan/lifecycle truth begins at a conservative migration boundary using a hidden `migrationBaseline` plus known current status. Resume, Restart and Restore are distinct, same-day events are deterministic, and Journey merges visible Plan/lifecycle facts chronologically.
- The pure `HabitAnalyticsEngine` derives grouped credit, period progress, outcomes, strict adherence, consistency, streaks and activity cells from value snapshots.
- Once-per-day credit is capped at one positive completion per immutable Local Day; multiple-per-day credit retains each positive completion. A plan change inside an open week/month leaves that whole strict period neutral rather than fabricating a miss.
- Plan edits use next-day/next-Monday/next-month boundaries; cross-period edits choose the coarser boundary. Journey filters out not-yet-effective revisions and migration-bootstrap Plans, while Context uses existing Entry/Habit/Goal links.
- Backup package v4 carries Local Day metadata, plan revisions and lifecycle events while decoding v1–v3 payloads only when every v4-only array and HabitLog LocalDay/time-zone/provenance field is absent. Imports reject duplicate Habit+effective-day revisions and impossible Plan targets; runtime Plan resolution remains deterministic by effective day, creation time and ID.
- v4 export/import preserves plan revision and lifecycle IDs plus HabitLog Local Day/time-zone provenance; old-package imports are bootstrapped during the same atomic publication transaction.
- Older package schemas reject v4-only Plan/lifecycle payloads instead of silently materializing them. The Dashboard, streak units and Journey strings compile for English and Simplified Chinese and are exercised through localized UI flows.

## Current UI integration

- Only active Habits enter Today, This Week, This Month or Tracking Only. Paused and Completed Habits remain available in lower-priority status sections without current due/remaining controls or semantics; Archived retains its Build 7 destination. Overview rows consume the same authoritative current-segment snapshot as Detail, and check-in/increment/decrement failures now surface a visible alert.
- The editor exposes No Goal, Every Day, Selected Days, Times per Week and Times per Month, and restores the current effective plan when editing. Once/day Every Day and Selected Days hide the ignored target field; weekly/monthly fields expose clear labels and enforce 7/28 maxima.
- Habit Detail starts with a Now section containing current-period progress, lifecycle status, the primary structured check-in, Insight/Details routes, adherence and streaks. The dashboard follows rather than displacing the action surface.
- Daily Progress is a Monday-first full current civil-month calendar that distinguishes achieved, missed, open, rest, lifecycle-neutral, pre-coverage and future dates while retaining factual rest-day activity. Its header and leading offset share the Weekly Review calendar policy. Weekly/monthly/tracking-only Progress remains scoped to the current evaluation; Year Activity is a separate 365-day view.
- Recent Activity is bounded to five facts and links to full history. The remaining dashboard includes Consistency, Trend, effective Journey and linked Context. Daily weekday pattern values are achieved/eligible success rates over strict scheduled outcomes; rest/open/neutral days are excluded. Weekly/monthly/tracking-only values are explicitly labeled factual activity distributions.
- Overview repeatable controls have unique Habit-scoped accessibility identities. At accessibility Dynamic Type sizes, the action moves below full-width name/progress content; normal sizes retain the compact aligned row. Target and Tracking Only counters share rhythm without inventing a denominator.

## Stage 0 recovery checkpoint

- Sunday is selectable using the documented `1 = Sunday ... 7 = Saturday` identity, independent of the device's first weekday.
- Selected-day schedules define expectation only: a rest-day activity fact can be stored while analytics keeps that day `notScheduled`.
- Once/day duplicate detection, Today completion and repeatable decrement use persisted Local Day; only positive completed logs contribute to completion/count/decrement.
- A false log does not mark Today complete and does not block an immediate true completion on the same Local Day.

## Stage 1 real V7 migration checkpoint

- `PersonalGrowthOSTests/Fixtures/Build7V7Fixture` was generated by the exact `95076bf5c2a86122fbd327903d80bccdfb8c768d` source and contains representative V7 SQLite and media facts.
- The first real overlay rejected direct Local Day columns on `HabitLog` because that design changed the historical V7 model checksum (`Cannot use staged migration with an unknown model version`). No destructive fallback was used.
- The corrected additive metadata design opens that V7 store, preserves Entry/Image/Habit/HabitLog/Goal/ObjectLink/Weight/WeeklyReview IDs and facts, bootstraps Local Day metadata/plans/lifecycle exactly once, and reopens with the same additions and civil days under a different time zone.

## Review boundary

- The complete automated acceptance matrix passed after the bounded PR #5 review closure. Real V7→V8 migration/bootstrap, Local Day credit/validation, historical Plan semantics, lifecycle-segmented Best/Current streaks, Plan constraints/provenance/determinism, inactive-section semantics, backup schema boundaries, Monday-first calendar, visible Overview failures, localization and frozen visual/a11y carryover are covered.
- Review-closure implementation commit `41194b8` follows reviewed head `9bb435c` on `feature/build8-habit-analytics-dashboard`; Draft PR [#5](https://github.com/yoCruzer/PersonalGrowthOS/pull/5) continues to target the exact Build 7 handoff branch.
- Physical-device validation is entirely outstanding.
- No merge, archive or TestFlight action has occurred or is authorized by this handoff.

## Verification so far

- PR #5 review-closure targeted Habit Foundation plus Import/Export Recovery suite: 98/98 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-PR5-ReviewClosure-TargetedUnit2.xcresult`).
- Review-closure Habit UI coverage: the focused eight-case batch passed seven unchanged cases, then the editor validation case passed after its explicit target accessibility label was added (`/tmp/PersonalGrowthOS-Build8-PR5-ReviewClosure-TargetedUI.xcresult`, `/tmp/PersonalGrowthOS-Build8-PR5-ReviewClosure-EditorUI2.xcresult`). The pre-existing Weekly Review save/relaunch case also passed 1/1 after replacing an immediate post-keyboard `.exists` assertion with a bounded wait (`/tmp/PersonalGrowthOS-Build8-PR5-ReviewClosure-WeeklyReviewUI.xcresult`).
- Review-closure complete Unit suite: 196/196 PASS, 0 failed, 0 skipped on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-PR5-ReviewClosure-FinalUnit.xcresult`).
- The first complete UI attempt exposed only the pre-existing immediate Weekly Review assertion (30/31). After the targeted synchronization fix, the post-fix complete UI suite passed 31/31, 0 failed, 0 skipped on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-PR5-ReviewClosure-FinalUI2.xcresult`).
- Post-closure Simulator Debug build: PASS. The 429-entry String Catalog parses with complete English and Simplified Chinese values; `git diff --check` passes.

- Simulator Debug build: PASS after the V8 model/backup/dashboard integration.
- Focused V8 Local Day/bootstrap, daily-credit, lifecycle-boundary and future-occurrence tests: 4/4 PASS on iPhone 16 Simulator, iOS 26.5 (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-07-04-+0800.xcresult`).
- v4 full import/export round-trip: PASS on iPhone 16 Simulator, iOS 26.5 (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-12-27-+0800.xcresult`).
- Cross-period plan-boundary test: PASS on iPhone 16 Simulator, iOS 26.5 (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-16-21-+0800.xcresult`).
- Habit Foundation suite: 38/38 PASS on iPhone 17 Pro Simulator, iOS 26.5, including V7→V8 bootstrap and week-credit/transition cases (`/Users/hanghang/Library/Developer/Xcode/DerivedData/PersonalGrowthOS-emotcgnahyqoknbhmwfzpcczyvfw/Logs/Test/Test-PersonalGrowthOS-2026.09.05_15-26-56-+0800.xcresult`).
- Recovered Stage 0 Habit Foundation suite: 45/45 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-Stage0-HabitFoundation.xcresult`).
- Exact-`95076bf` fixture generation: 1/1 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build7-V7Fixture-Generate.xcresult`).
- Stage 1 migration/Habit/transfer regression: 48/48 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-Stage1-Targeted2.xcresult`).
- Stage 2 Habit/recording-mode/transfer regression: 50/50 PASS (`/tmp/PersonalGrowthOS-Build8-Stage2-RecordingMode.xcresult`) plus focused real-migration and v4 proof 5/5 PASS (`/tmp/PersonalGrowthOS-Build8-Stage2-RecordingMode-2.xcresult`) on iPhone 17 Pro Simulator, iOS 26.5.
- Stage 3 effective-Plan runtime regression: Habit Foundation 49/49 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-Stage3-RuntimeTruth.xcresult`).
- Stage 4 pending-Plan regression: Habit Foundation 50/50 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-Stage4-PendingPlan.xcresult`).
- Stage 5 contiguous-analytics regression: Habit Foundation 54/54 PASS on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-Stage5-ContiguousAnalytics.xcresult`).
- Stage 6/7 Local Day/lifecycle/v4 regression: 58/58 PASS (`/tmp/PersonalGrowthOS-Build8-Stage67-LocalDayLifecycle.xcresult`), focused validation 2/2 PASS (`/tmp/PersonalGrowthOS-Build8-Stage67-Focused.xcresult`), and conservative real-migration boundary 2/2 PASS (`/tmp/PersonalGrowthOS-Build8-Stage67-MigrationBoundary.xcresult`) on iPhone 17 Pro Simulator, iOS 26.5.
- Stage 8 P0 dashboard regression: Habit Foundation 60/60 PASS (`/tmp/PersonalGrowthOS-Build8-Stage8-P0Dashboard-Final.xcresult`) on iPhone 17 Pro Simulator, plus focused create/check-in/detail UI 1/1 PASS (`/tmp/PersonalGrowthOS-Build8-Stage8-P0UI.xcresult`) and visual inspection of the Now/month-calendar hierarchy on a clean iPhone 16 Simulator, iOS 26.5.
- Stage 9 weekday-pattern regression: Habit Foundation 62/62 PASS (`/tmp/PersonalGrowthOS-Build8-Stage9-WeekdayPattern.xcresult`) on iPhone 17 Pro Simulator, iOS 26.5, including daily scheduled-denominator exclusions and weekly/monthly/tracking-only activity distribution.
- Stage 10 backup/localization regression: Habit Foundation plus Import/Export Recovery 88/88 PASS (`/tmp/PersonalGrowthOS-Build8-Stage10-BackupLocalizationFinal.xcresult`) on iPhone 16 Simulator, iOS 26.5. Focused English/system-language UI 2/2 PASS (`/tmp/PersonalGrowthOS-Build8-Stage10-EnDashboardUI.xcresult`) and Simplified Chinese Dashboard UI 1/1 PASS (`/tmp/PersonalGrowthOS-Build8-Stage10-ZhDashboardUI2.xcresult`). The 423-entry catalog parses with complete English and Simplified Chinese values; all 85 explicit `HabitViews` localization keys resolve, and both language catalogs compile independently.
- Stage 11 visual/accessibility closure: mixed once/day, adjacent multiple/day, over-target, Tracking Only and long-name rows pass enabled semantic accessibility audits with measured >=44-point +/- targets and non-intersecting adjacent controls in both Light/default text (`/tmp/PersonalGrowthOS-Build8-Stage11-LightFinal.xcresult`) and Dark/system accessibility-extra-large (`/tmp/PersonalGrowthOS-Build8-Stage11-DarkLargeFinal.xcresult`). Exported screenshots were visually inspected; accessibility-size actions retain full-width text above compact controls.
- Final complete Unit suite: 186/186 PASS, 0 failed, 0 skipped on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-FinalUnit-Rerun.xcresult`).
- Final complete UI suite: 29/29 PASS, 0 failed, 0 skipped on iPhone 17 Pro Simulator, iOS 26.5 (`/tmp/PersonalGrowthOS-Build8-FinalUI-Rerun.xcresult`). The enabled semantic audit includes useful-description coverage for the Quick Capture editor; Habit Insight, Weekly Review and Tag Search use only visible navigation and scrolling.
- Final exact-V7 overlay/bootstrap/reopen and v4 full backup round-trip proof: 2/2 PASS (`/tmp/PersonalGrowthOS-Build8-FinalDataProofs.xcresult`).
- Final Simulator Debug build and independent English/Simplified Chinese `build-for-testing` runs: PASS. The 423-entry String Catalog has complete values in both languages.
- Final project parse, JSON/catalog structure, conflict-marker, `git diff --check` and recovery-patch SHA-256 checks: PASS. The preserved pre-recovery patch remains `/tmp/PersonalGrowthOS-Build8-pre-recovery-bdb1744.patch` with SHA-256 `812464f2da6e52129972caf7f49ab321cabf37d2c4a72ebc9fa2bb3bf51e8618`.
