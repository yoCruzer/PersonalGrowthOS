# Usability S2 — Weekly Review and Action Loop

| Item | Value |
| --- | --- |
| Status | Review fixes validated; [Draft PR #2](https://github.com/yoCruzer/PersonalGrowthOS/pull/2) open |
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
- `git diff --check` passed. No String Catalog changed in this review-fix.

## Follow-up Boundary

Backup validation intentionally does not recompute a review's identifier from its stored period: package v3 does not retain the exporting device's time zone, so receiver-side recomputation could reject an otherwise valid local-week review. The existing non-empty identifier, unique identifier and ordered-period checks remain in place; timezone-aware package metadata would be a separate non-blocking follow-up.

The next work is review of the S2 Draft PR and, if accepted, focused physical-device interaction validation. Build 3 TestFlight export remains a separate Owner-owned activity on `feature/v1-completion-push` and is not evidence for this S2 candidate.
