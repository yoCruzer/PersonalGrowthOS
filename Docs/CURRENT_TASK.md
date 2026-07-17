# Current Task

| Item | Value |
| --- | --- |
| Next batch | Batch 1 |
| Stage | S0B — Composition and Test Harness Foundation |
| Status | Defined, not started |
| Dependency | Completed S0A bootstrap on `main` |
| Execution gate | Separate Owner approval remains required by `Docs/S0_EXECUTION_PLAN.md` |

## Objective

Establish the smallest explicit App composition root, controllable launch configuration, and deterministic Unit/UI smoke-test seam while keeping the App a static placeholder with no product functionality.

Batch 0 does not authorize execution of this batch.

## Scope

- Add `AppConfiguration` with only standard and UI-testing startup modes.
- Centralize launch argument and environment interpretation at one boundary.
- Add `AppContainer` as the minimal composition root containing only the startup configuration.
- Construct the container once in `PersonalGrowthOSApp` and pass it explicitly to `RootPlaceholderView`.
- Give the placeholder one stable accessibility identifier for UI launch verification.
- Add focused Unit Tests for configuration selection and composition creation.
- Replace or refine the current UI launch proof with one deterministic smoke test that launches the App and observes the identified placeholder.
- Keep repeated test launches independent of network, accounts, permissions, and persisted data.

Expected changes should remain limited to the App entry, placeholder, minimal files under `PersonalGrowthOS/App/`, focused composition tests, focused launch smoke tests, and Xcode target membership if the project format requires it.

## Constraints

- Read the Foundation Documents, Development Contract, current state, current task, `Docs/V1_IMPLEMENTATION_PLAN.md`, and `Docs/S0_EXECUTION_PLAN.md` before implementation.
- Obtain the separate S0B execution approval required by the accepted S0 plan.
- Preserve the existing project name, targets, scheme, iOS 17.0 deployment target, iPhone-only device family, bundle identifiers, automatic signing, and absence of a shared Development Team.
- Keep `AppContainer` concrete and minimal; do not create a dependency-injection framework, service locator, protocol graph, or speculative service placeholders.
- Limit test-only behavior to side-effect-free startup configuration and stable placeholder identification.
- Make one coherent Batch 1 commit, update current-state/current-task handoff documents, leave the repository clean, and stop before S1.

## Success Criteria

- The App builds for an available iPhone Simulator in both standard and UI-testing launch modes.
- `AppConfiguration` deterministically selects the standard and UI-testing modes from centralized launch inputs.
- One explicit `AppContainer` is created at the App entry point and contains no product services.
- Focused Unit Tests for configuration and composition execute and pass.
- The UI smoke test repeatedly launches the App and observes the stable placeholder identifier.
- A standard launch still displays the same static placeholder.
- All existing tests pass.
- No product model, persistence, feature UI, package dependency, capability, entitlement, signing change, or deployment change appears in the diff.
- The Batch 1 diff is limited to the approved S0B boundary, documentation reflects the new verified state, and the repository is clean after one commit.

## Out of Scope

- Any Entry, Habit, HabitLog, Goal, Flag, Review, Tag, Link, or media domain behavior.
- SwiftData, `VersionedSchema`, `ModelContainer`, repositories, stores, persistence fixtures, or sample user data.
- Product navigation, tabs, Today, Timeline, Growth, Library, Capture, Search, Settings, or import/export.
- Fake product services, generalized dependency injection, reusable mocking infrastructure, or third-party dependencies.
- Snapshot, performance, broad UI automation, visual design, branding, localization, or accessibility work beyond the single smoke-test identifier.
- S1 or any later product implementation.
