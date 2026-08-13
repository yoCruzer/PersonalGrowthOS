# Usability S2 — Weekly Review and Action Loop

| Item | Value |
| --- | --- |
| Status | Build 5 candidate ready for independent review; [Draft PR #2](https://github.com/yoCruzer/PersonalGrowthOS/pull/2) remains Draft |
| Branch | `feature/usability-s2-review-loop` |
| Base | `c45c666` |
| Scope | Manual weekly reflection from Today with a bounded local summary and one next step/focus |

## Product Boundary

S2 is a small, user-initiated review loop. It supports reflection, not automated evaluation: the app never creates a review, sends a prompt, derives a conclusion or turns text into a task.

The flow is:

```text
Today → Weekly Review → Start explicitly → See this week’s local facts → Write reflection / next step / focus → Save → Reopen
```

`WeeklyReview` is separate from the existing manual `EntryKind.review`. This preserves the established V1 Review entry lifecycle while keeping S2’s one-per-week draft compact and locally owned.

## Data and Compatibility

- SwiftData schema V7 adds `WeeklyReview`; V6→V7 is lightweight and leaves existing objects unchanged.
- Weekly Review uses one centralized ISO-style Gregorian policy: Monday is the first day of week, four days are required in the first week, and the local device time zone supplies local-day semantics. Locale, Region and a user-selected non-Gregorian system calendar do not alter the identifier or period boundaries.
- Backup package schema v3 serializes weekly reviews. Package schemas v1 and v2 remain valid when they contain no weekly review data; schema v1 continues to reject Weight and schema v2 continues to reject weekly reviews.
- Validation rejects duplicate weekly-review IDs or week identifiers, reversed periods, invalid timestamps and blank non-nil text values.

## Validation Evidence

Executed on iPhone 16 Simulator, iOS 26.5 (`5F04DE28-8329-4774-9488-076D6DDC5230`):

- Habit and Weekly Review focused Unit tests: 37/37 passed — `/tmp/PersonalGrowthOS-S2-reviewfix-Habit-Weekly-2.xcresult`.
- Import/export schema-v3 and Weekly Review focused tests: 3/3 passed — `/tmp/PersonalGrowthOS-S2-reviewfix-Transfer.xcresult`.
- Focused multiple-per-day Insight/counter UI smoke: 1/1 passed — `/tmp/PersonalGrowthOS-S2-reviewfix-Habit-UI-4.xcresult`.
- Simulator Debug build: passed.
- Full Unit suite: 141/141 passed — `/tmp/PersonalGrowthOS-S2-reviewfix-Full-Unit.xcresult`.
- `git diff --check` passed. The Build 5 candidate adds bilingual success, preview and accessibility strings; String Catalog JSON and bilingual-value validation passed.

## Build 4 Owner Feedback and Build 5 Candidate

Build 4 was distributed through TestFlight before the Owner's real-iPhone overlay validation. That validation passed V5→V6→V7 migration, existing Entry/image/Habit/Goal/Review retention and restart recovery, Weight persistence, repeatable-Habit `+++--`, Insight→`+`→`-` linked-Entry retention, explicit-only Weekly Review creation, and V7 export. The resulting evidence supersedes the earlier simulator-only wording for those flows.

It also found a merge-blocking Weekly Review closure failure: after Chinese text input, keyboard dismissal was unreliable and Save showed no observable completion or restart-persistence proof. The current candidate gives each field an explicit `FocusState`, supplies a keyboard Done action, yields after ending focus before saving, refetches the stable current-week review by period, and reports either a visible Saved state or the existing error alert. A final independent-review closure also clears any stale Saved state when an editable field (including completion) changes or when a new save begins. The current simulator evidence includes 40 focused Unit tests, four focused UI smokes (Weekly Review save/relaunch including completion state, Insight/counter and Quick Capture), Simulator Debug build, a 142-test full Unit gate and a 25-test full UI gate. Chinese IME composition itself requires Build 5 Owner revalidation.

The same candidate keeps the existing Habit semantics but compacts the repeatable-Habit card with 28pt visual controls inside 44×44pt button hit areas and a `ViewThatFits` fallback. The global Search/Capture cluster hides for keyboard and presentation input states, moves only after long press, stores normalized `@AppStorage` coordinates, and clamps them to the current safe operating area. Entry media now fits its actual aspect ratio with a maximum height instead of a forced gray container; Entry-detail thumbnails open a single-image, aspect-fit full-screen preview with a close control and safe thumbnail fallback. No media-browser, data-model or export behavior was added.

## Follow-up Boundary

Backup validation intentionally does not recompute a review's identifier from its stored period: package v3 does not retain the exporting device's time zone, so receiver-side recomputation could reject an otherwise valid local-week review. The existing non-empty identifier, unique identifier and ordered-period checks remain in place; timezone-aware package metadata would be a separate non-blocking follow-up.

The next work is independent incremental review of the S2 Draft PR. The post-`2084207` candidate has not consumed Build 5, become a Build 5 Archive, or received Owner device validation. If accepted, prepare a new Build 5 Archive and perform focused Owner physical-device validation of Chinese Weekly Review input/save/relaunch plus the bounded new interaction work. Build 3 TestFlight export remains a separate Owner-owned activity on `feature/v1-completion-push` and is not evidence for this S2 candidate.
