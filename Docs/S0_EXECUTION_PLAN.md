# S0 Execution Plan

| Item | Value |
| --- | --- |
| Project | Personal Growth OS |
| Document | S0_EXECUTION_PLAN.md |
| Version | v0.3 |
| Status | Owner Accepted S0 Execution Planning Baseline |
| Baseline Commit | c8d82d27e546f9fa3297d70c10efaef94fca990e |
| Last Updated | 2026-07-16 |

---

# Purpose

本文档把 Macro Stage S0 — Project Skeleton and Test Harness 拆分为两个小型、可独立审批、执行、验证和停止的子 Stage。

本文档只定义未来 S0 实施任务的边界。创建本文档不批准创建 Xcode Project，不批准编写 Swift 或测试代码，也不批准开始 S0A、S0B、S1 或任何后续实现。

---

# Baseline Documents and Reading Order

任何 S0 子 Stage 在编写可执行任务前，必须按以下顺序读取当前基线：

1. Docs/INDEX.md
2. Docs/VISION.md
3. Docs/DESIGN_PRINCIPLES.md
4. Docs/CORE_MODEL.md
5. Docs/INFORMATION_ARCHITECTURE.md
6. Docs/V1_SCOPE.md
7. Docs/V1_IMPLEMENTATION_PLAN.md
8. Docs/S0_EXECUTION_PLAN.md

Baseline facts:

- main baseline commit: c8d82d27e546f9fa3297d70c10efaef94fca990e.
- Foundation document lifecycle: Foundation Draft v0.2.
- V1_IMPLEMENTATION_PLAN.md: v0.3, Owner Accepted Implementation Planning Baseline.
- Product implementation: not started.
- S0 and all executable sub Stages: unapproved.

If this plan conflicts with a Foundation Document or V1_IMPLEMENTATION_PLAN.md, the higher-level baseline wins and execution stops for Owner Review.

---

# S0 Macro Stage Boundary

Macro Stage S0 exists only to establish:

- One native iPhone SwiftUI application project.
- One App target.
- One Unit Test target.
- One lightweight UI Test target.
- A minimal launchable placeholder.
- A minimal dependency-composition entry point.
- A small configuration seam for later tests.
- A launch smoke test.

S0 must not establish:

- Product domain models or business rules.
- SwiftData models, VersionedSchema, ModelContainer or repositories.
- Entry, Media, Capture, Timeline, Today, Growth, Library, Search or Review behavior.
- Product navigation beyond what is strictly required to show the placeholder.
- Third-party dependencies or Swift Package modules.
- Cloud, sync, account, notification or sharing capabilities.
- Product visual design, branding or production assets.

S0 ends after the bootstrap, composition seam and smoke harness are independently validated. It does not produce a vertical product slice; that work remains in later approved Macro Stages.

---

# Recommended Sub Stage Split

The proposed split is accepted as the smallest practical dependency chain:

| Order | Sub Stage | Purpose | Stop Point |
| --- | --- | --- | --- |
| 1 | S0A — Native Xcode Project Bootstrap | Create and validate the native project, targets and placeholder launch | Stop after project build/launch evidence |
| 2 | S0B — Composition and Test Harness Foundation | Add the minimal composition/configuration seam and smoke coverage | Stop after unit/UI harness evidence |

Why this split is appropriate:

- S0B cannot compile or run until S0A creates the project and targets.
- S0A has useful independent evidence: the project builds and the placeholder launches.
- Composition and test behavior can be reviewed without mixing them into project-generation noise.
- S0A can be reverted as one bootstrap change; S0B can be reverted while leaving a valid native project.
- Passing S0A does not approve S0B.
- Passing S0B does not approve S1 or any product feature.

Each sub Stage requires a separate executable task and explicit Owner approval immediately before execution.

---

# Xcode Project Creation Decisions

| Decision | Recommendation |
| --- | --- |
| Project name | PersonalGrowthOS |
| App target | PersonalGrowthOS |
| Unit Test target | PersonalGrowthOSTests |
| UI Test target | PersonalGrowthOSUITests |
| Platform | iPhone only |
| Deployment target | iOS 17.0 |
| UI lifecycle | SwiftUI App lifecycle using an @main App entry point |
| Storyboard | None |
| Project format | Native Xcode project; no XcodeGen, Tuist or other generator |
| Unit test framework | XCTest |
| UI test framework | XCUITest |
| Bundle identifier strategy | Stable V1 App Bundle Identifier: com.yocruzer.PersonalGrowthOS |
| Test bundle identifiers | Derived from App identifier with Tests and UITests suffixes |
| Signing | Automatic Signing; shared project must not persist DEVELOPMENT_TEAM; S0A acceptance is Simulator-only |
| Capabilities | None |
| Entitlements file | Do not create unless a future separately approved capability requires it |
| Project directory | Repository root: PersonalGrowthOS.xcodeproj |
| Source directory | Repository root/PersonalGrowthOS |
| Unit test directory | Repository root/PersonalGrowthOSTests |
| UI test directory | Repository root/PersonalGrowthOSUITests |
| Shared scheme | PersonalGrowthOS scheme committed as a shared scheme |
| Build configurations | Xcode-standard Debug and Release only |
| Device family | iPhone only; do not enable iPad support in S0 |

Bundle and signing notes:

- com.yocruzer.PersonalGrowthOS is the current stable V1 App Bundle Identifier, not a temporary placeholder.
- Changing this identifier later requires separate Owner Review.
- This identifier decision does not approve physical-device signing, Apple Developer Team configuration, App Store Connect setup or release work.
- Use Automatic Signing, but the shared project must not hard-code or persist DEVELOPMENT_TEAM.
- S0A acceptance uses an available iPhone Simulator only. Simulator build and tests must pass when no Development Team is configured.
- Physical-device signing and Development Team selection are outside S0A and S0B.
- S0 does not add CloudKit, iCloud, Push Notifications, App Groups, Sign in with Apple, Background Modes or associated domains.

Asset notes:

- S0A may retain the minimal empty asset catalog created by the native Xcode template when required by the target.
- It must not add a designed App icon, brand palette, production imagery or other product assets.

---

# S0A — Native Xcode Project Bootstrap

| Item | Plan |
| --- | --- |
| Stage ID | S0A |
| Stage Name | Native Xcode Project Bootstrap |
| Goal | Create a native iOS 17+ SwiftUI project with three correctly configured targets and a minimal placeholder that launches in an iPhone Simulator |
| Dependencies | Baseline commit c8d82d27e546f9fa3297d70c10efaef94fca990e; explicit Owner approval of S0A |

## In Scope

- Create PersonalGrowthOS.xcodeproj at the repository root using native Xcode project structure.
- Create the PersonalGrowthOS iPhone App target.
- Create PersonalGrowthOSTests as a Unit Test target.
- Create PersonalGrowthOSUITests as a UI Test target.
- Set iOS 17.0 as the deployment target for all three targets.
- Use SwiftUI App lifecycle and no storyboard.
- Create the minimum App entry and placeholder view required to launch.
- Configure one shared PersonalGrowthOS scheme containing the App and test targets.
- Keep Debug and Release as the only build configurations.
- Keep targets iPhone-only.
- Create only the minimal empty asset catalog required by the target, if the native template produces one.
- Create the minimum XCTest file needed to prove the Unit Test target runs.
- Create one minimum XCUITest file that launches the App and proves the UI Test target executes.
- Permit only the Xcode project metadata necessary to define, build and run the three targets and shared scheme.

## Out of Scope

- AppContainer, AppConfiguration or dependency composition behavior.
- Product domain folders, types, enums, models or validation.
- SwiftData imports, schema, models, container or persistence configuration.
- Real feature UI, navigation, data display or user interaction.
- Entry, Media, Capture, Today, Timeline, Growth, Library, Search, Settings or Review.
- Unit or UI test behavior beyond minimum target execution and App launch proof.
- Branding, product icons, colors, localization or accessibility design.
- Physical-device distribution, provisioning profile setup or release signing.
- App Store Connect setup or publishing work.
- Future service interfaces, generic architecture scaffolding or nonessential placeholder directories/files.
- A four-Tab product shell or any approximation of product navigation.

## Expected Files / Artifacts

Expected bootstrap artifacts, subject to native Xcode internal layout:

~~~text
PersonalGrowthOS.xcodeproj/
├── project.pbxproj
└── xcshareddata/
    └── xcschemes/
        └── PersonalGrowthOS.xcscheme

PersonalGrowthOS/
├── PersonalGrowthOSApp.swift
├── RootPlaceholderView.swift
└── Assets.xcassets/        (necessary minimal catalog only)

PersonalGrowthOSTests/
└── PersonalGrowthOSTests.swift       (minimum target execution test)

PersonalGrowthOSUITests/
└── PersonalGrowthOSUITests.swift     (minimum App launch smoke test)
~~~

Xcode may create only the project metadata necessary for these artifacts. Exact internal metadata files may vary with the selected Xcode version.

S0A must not create Domain models, a SwiftData Schema, Entry, Media, Capture, Timeline, a four-Tab product shell, future service interfaces, third-party dependencies, or nonessential architecture directories and placeholder files. It must not create Product Domain, Persistence, ImportExport or Feature implementations.

## Validation

These commands and checks are future S0A execution steps only; they are not run by this planning task:

1. Run xcodebuild -list and confirm it discovers PersonalGrowthOS.xcodeproj, the shared PersonalGrowthOS scheme, and exactly one App, one Unit Test and one UI Test target with the expected names.
2. Select an iPhone Simulator that is actually available on the execution host; do not hard-code a particular iPhone model.
3. Build the PersonalGrowthOS App target successfully for that Simulator.
4. Run the PersonalGrowthOSTests target and confirm its minimum test executes successfully.
5. Run the PersonalGrowthOSUITests target and confirm its minimum launch smoke test starts the App successfully.
6. Confirm the placeholder becomes visible and the process remains running without crash.
7. Repeat build and test validation with no DEVELOPMENT_TEAM configured; no physical-device signing may be required.
8. Confirm all validation succeeds without network access, remote services or account login.
9. Inspect build settings for iOS 17.0 and iPhone-only targeting.
10. Confirm there is no storyboard reference.
11. Confirm no capabilities or entitlements are configured.
12. Confirm no package dependency or third-party binary is linked.
13. Confirm the diff contains only S0A-approved bootstrap artifacts.

The executable S0A task must record the exact simulator/runtime used; this plan intentionally does not hard-code a device model that may be unavailable on the host.

## Exit Criteria

- The project opens without repair or migration prompts in the selected Xcode toolchain.
- All three target names and the shared scheme match this document.
- The App builds, installs and launches to a static placeholder on an iPhone Simulator.
- Unit Test target runs its minimum test and UI Test target executes its minimum App launch smoke test.
- Deployment target, lifecycle, device family, signing and capability decisions match this document.
- No product model, persistence, feature implementation or third-party dependency exists.
- Working tree contains only S0A-approved artifacts.
- Evidence is reported to Owner and execution stops.
- S0B remains unapproved.

## Risk Notes

- Xcode template output can add unwanted files, capabilities or target settings.
- Local signing/team values can leak into the shared project.
- Automatically generated test templates can blur the S0A/S0B boundary.
- A fixed simulator name can make validation non-portable.
- Modern Xcode project-format changes can create noisy diffs.

Mitigation:

- Inspect every generated file and build setting.
- Remove template sample behavior not required for launch.
- Keep signing account values local.
- Select an available simulator at execution time.
- Do not normalize or hand-edit unrelated project metadata.

## Explicitly Forbidden

- Starting S0A without explicit Owner approval.
- Creating S0B composition or smoke-test behavior.
- Creating any S1 Entry semantics or product model.
- Importing or configuring SwiftData.
- Adding a Swift Package or third-party dependency.
- Adding any capability or entitlements file.
- Creating a storyboard.
- Adding product branding or high-fidelity UI.
- Adding a four-Tab product shell.
- Adding future service interfaces or speculative architecture directories/placeholders.
- Creating a feature branch unless separately requested by Owner.
- Continuing to S0B after S0A passes.

---

# S0B — Composition and Test Harness Foundation

| Item | Plan |
| --- | --- |
| Stage ID | S0B |
| Stage Name | Composition and Test Harness Foundation |
| Goal | Establish a minimal explicit App composition root, a controllable launch configuration seam and basic unit/UI smoke evidence without product dependencies |
| Dependencies | S0A completed and accepted; repository at the accepted S0A commit; separate explicit Owner approval of S0B |

## In Scope

- Add a small AppConfiguration value describing only the minimum App startup mode: standard or UI testing.
- Add an AppContainer solely as the composition root for that minimum startup configuration.
- Keep AppContainer free of product services until a later approved Stage introduces a real dependency.
- Construct AppContainer once in the SwiftUI App entry point and pass it to the placeholder root explicitly.
- Centralize lightweight launch-argument/environment interpretation in one factory rather than scattering ProcessInfo access.
- Add a deterministic placeholder accessibility identifier for UI launch verification.
- Add a unit test that verifies standard/test configuration selection and composition creation.
- Add one XCUITest launch smoke test that starts the App and observes the placeholder.
- Ensure repeated UI test launches do not require network, account, permissions or persisted data.

AppConfiguration and AppContainer may support only minimum App startup configuration, the composition root, UI Test launch configuration and minimum dependency-assembly verification. The configuration seam is a small value plus factory. It is not a service locator, dependency-injection framework, protocol graph or persistence abstraction.

The UI Test seam must prefer lightweight launch arguments and environment values. It may only provide a stable, side-effect-free startup state for UI testing; it must not become a separate test business architecture, feature-flag system or alternate product runtime.

## Out of Scope

- SwiftData, in-memory ModelContainer or any real persistence configuration.
- EntryStore, MediaStore, SearchService, repositories, fake repositories or any other future service placeholder or implementation.
- Product navigation, app tabs, capture flow or timeline.
- Product domain types, model fixtures or sample user data.
- Snapshot testing, performance testing or broad UI automation.
- General-purpose dependency-injection framework, service locator, generic mocking framework or reusable test architecture.
- Protocol or mock proliferation without an approved real dependency.
- Test-only production behavior beyond launch configuration and deterministic placeholder identification.

## Expected Files / Artifacts

Expected S0B changes:

~~~text
PersonalGrowthOS/
├── PersonalGrowthOSApp.swift          (modify composition entry)
├── RootPlaceholderView.swift          (inject minimal container/configuration)
└── App/
    ├── AppConfiguration.swift
    └── AppContainer.swift

PersonalGrowthOSTests/
└── AppCompositionTests.swift

PersonalGrowthOSUITests/
└── AppLaunchSmokeTests.swift

PersonalGrowthOS.xcodeproj/
└── project.pbxproj                    (target membership only when required)
~~~

Exact files must remain limited to the separately approved executable S0B task.

## Validation

These checks are future S0B execution steps only:

1. Build the App scheme for an available iPhone Simulator.
2. Run PersonalGrowthOSTests and confirm composition/configuration checks pass.
3. Run PersonalGrowthOSUITests and confirm the launch smoke test observes the placeholder.
4. Run the smoke test repeatedly and confirm deterministic launch without network or permission prompts.
5. Confirm standard launch still shows the same placeholder.
6. Search the diff for SwiftData, @Model, ModelContainer, Entry, MediaStore and other product implementation symbols; none may be introduced as dependencies.
7. Confirm no capabilities, package dependencies, signing changes or deployment-target changes.
8. Confirm only S0B-approved files changed from the accepted S0A baseline.

## Exit Criteria

- The App has one visible, explicit composition root.
- AppConfiguration can select standard and UI-testing launch modes without global scattered checks.
- AppContainer contains no invented product services.
- Unit composition/configuration tests pass.
- The UI launch smoke test passes on an available iPhone Simulator.
- The App remains a static placeholder with no product behavior.
- No SwiftData schema, product model, feature or third-party dependency exists.
- Evidence is reported to Owner and execution stops.
- S1 and every later implementation Stage remain unapproved.

## Risk Notes

- An empty AppContainer can become speculative architecture.
- Test launch flags can leak into product behavior.
- A smoke test can become brittle if it depends on visual layout.
- S0B can accidentally introduce persistence seams before S2.

Mitigation:

- AppContainer stores only actual launch configuration until a real dependency is approved.
- Keep launch-mode parsing in one boundary and expose no feature flags.
- Assert one stable accessibility identifier rather than layout details.
- Forbid SwiftData and repository abstractions in S0B.

## Explicitly Forbidden

- Starting S0B without separate explicit Owner approval.
- Treating S0A acceptance as S0B approval.
- Adding SwiftData or any persistence model/configuration.
- Adding Entry, Media, Capture, Timeline or other feature code.
- Adding fake product repositories or sample records.
- Adding EntryStore, MediaStore, SearchService or any future service placeholder.
- Adding a general-purpose DI framework, service locator, or speculative protocols/mocks.
- Adding a third-party testing, mocking or dependency-injection library.
- Adding capabilities, entitlements or account requirements.
- Expanding the placeholder into product UI.
- Continuing to S1 after S0B passes.

---

# S0A / S0B Boundary

| Concern | S0A Owner | S0B Owner |
| --- | --- | --- |
| Xcode project and target creation | Yes | No |
| Target names, deployment and iPhone-only settings | Yes | Verify only |
| Shared scheme | Create | Use |
| SwiftUI App entry and static placeholder | Minimal creation | Inject configuration/container only |
| Unit/UI test targets | Create and run minimum target/launch proof | Add focused configuration/composition evidence |
| Composition root | No | Yes, minimal |
| Test launch configuration seam | No | Yes |
| Basic App launch smoke | Yes, template-level only | Retain and make deterministic through the approved seam |
| Stable placeholder assertion | No | Yes |
| Product model/persistence/features | No | No |

Boundary rules:

- S0A changes project structure; S0B changes only minimal composition and smoke-harness files.
- S0B must not revisit naming, deployment, signing or capability decisions unless execution discovers a blocker and returns to Owner Review.
- Each sub Stage should be reviewed as a separate diff and can be reverted without requiring the other to be redesigned.
- S0A completion produces no authority to execute S0B.
- S0B completion produces no authority to execute S1.

---

# Owner Review Decisions

Decision: APPROVED AS S0 EXECUTION PLANNING BASELINE.

The S0A / S0B split and all listed project, signing, artifact, validation and abstraction boundaries are Owner Accepted.

This planning approval does not approve execution of S0A or S0B.

Owner must approve or revise before S0A:

1. The two-sub-Stage split and the stop point between S0A and S0B.
2. Project and three target names.
3. iOS 17.0, iPhone-only and SwiftUI/no-storyboard decisions.
4. Stable V1 App Bundle Identifier: com.yocruzer.PersonalGrowthOS; any later change requires separate Owner Review.
5. Automatic-signing strategy with no shared Development Team.
6. No capabilities and no entitlements file.
7. Native Xcode project with no generator or Swift Package.
8. XCTest/XCUITest as the initial harness.
9. Whether a template-generated empty asset catalog is acceptable.

Owner must separately approve or revise before S0B:

1. AppConfiguration limited to standard and UI-testing launch modes.
2. AppContainer as a minimal explicit composition root with no product services.
3. One unit composition/configuration test.
4. One accessibility-identifier-based UI launch smoke test.

No Owner decision in this section constitutes implementation approval until the corresponding executable sub Stage is explicitly approved.

---

# Planning Status

Implementation has not started.

S0A remains unapproved.

S0B remains unapproved.

Creating this document does not approve Xcode Project creation.

S1 and every later implementation Stage remain unapproved.

This document is approved for merge into main as the current S0 execution planning baseline.

---

# Change History

| Version | Date | Change |
| --- | --- | --- |
| v0.3 | 2026-07-16 | Recorded final Owner acceptance of the S0 execution planning baseline; S0A and S0B execution remain unapproved. |
| v0.2 | 2026-07-16 | Addressed Owner conditions for bundle identity, signing, exact S0A artifacts and validation, and the S0B abstraction and UI Test seam boundaries. |
| v0.1 | 2026-07-16 | Initial S0 execution planning draft for Owner Review. |
