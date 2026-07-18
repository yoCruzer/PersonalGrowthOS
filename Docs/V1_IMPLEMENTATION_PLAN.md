# V1 Implementation Plan

| Item | Value |
| --- | --- |
| Project | Personal Growth OS |
| Document | V1_IMPLEMENTATION_PLAN.md |
| Version | v0.4 |
| Status | Owner Accepted Implementation Planning Baseline — Governance Revision Draft |
| Foundation Baseline | Owner-accepted Foundation v0.2 implementation baseline at ce18ed36ce4a4866e36ab15d4b55eab4a0d410dd |
| Last Updated | 2026-07-18 |

---

# Purpose

本文档把 Owner-accepted Foundation v0.2 implementation baseline 转化为可逐步执行、验证和退出的 V1 实施计划。

本文档只定义实施边界、架构选择、阶段顺序和验收标准。它不批准任何实现工作，也不修改 Foundation Documents 中的产品范围。

---

# Planning Principles

1. Done is better than perfect.
2. Good enough to build.
3. 先打通 Capture → Persist → Timeline 的最小闭环。
4. S0–S10 是 Macro Stages；默认模式下，每个 Macro Stage 必须先拆成经 Owner 独立批准的可执行子 Stage。Owner 也可以通过明确的 Autonomous Execution Program 一次性批准多个 Macro Stages。
5. 复杂度必须由当前 V1 场景证明合理。
6. 不为 AI、跨平台、iCloud 同步或未知未来需求提前建设架构。
7. Export / Import 是 V1 的真实能力，但 V1 不建设复杂备份系统。
8. 本计划被接受为实施规划基线不等于批准实施；Autonomous Execution Program 只有在 `Docs/CURRENT_TASK.md` 明确记录 Owner startup authorization 后才能开始。

---

# Foundation Baseline

本计划服从以下文档，并按其规定顺序理解：

1. INDEX.md
2. VISION.md
3. DESIGN_PRINCIPLES.md
4. CORE_MODEL.md
5. INFORMATION_ARCHITECTURE.md
6. V1_SCOPE.md

这些 Foundation Documents 的文档生命周期状态仍为 Foundation Draft v0.2。本计划仅记录它们已被 Owner 接受为当前实施基线（Owner Accepted）；这不把 Foundation Documents 的状态改为 Approved。

规划时未发现 Prompt 与 Foundation Documents 的产品范围冲突。Prompt 对持久化、图片和导入导出提出了实现级问题；本计划在不改变 Foundation 决策的前提下给出推荐。

---

# Implementation Goal

V1 实施阶段的目标是：

> 做出一个可在 iPhone 上运行、可真实记录、可离线使用、可手动备份与恢复，并可长期迭代的 Daily Driver 基础版本。

V1 不是 Release Candidate，也不以 App Store Ready 为目标。它首先要成为目标用户自然、可靠的人生记录入口。

---

# Platform Boundary

| Boundary | V1 Decision |
| --- | --- |
| Platform | iPhone |
| Minimum OS | iOS 17+ |
| UI | SwiftUI |
| Architecture | Local First |
| Core workflow network dependency | None |
| Data transfer | Basic Data Export and Data Import are required |
| Not in V1 | iPad, Mac, Web, cross-platform abstractions |
| Not in V1 | iCloud multi-device sync and real-time sync |

Local First does not mean Local Only。网络、同步和云端都不是核心工作流的运行前提，但用户必须能通过导出包迁移和恢复数据。

---

# Architecture Recommendation

| Area | Recommendation |
| --- | --- |
| Project skeleton | 单一原生 iOS App 工程，按职责分目录；V1 不创建独立 Swift Package |
| Production targets | 一个 iPhone App target |
| Test targets | 一个 Unit Test target；一个只承载关键流程 smoke test 的 UI Test target |
| Persistence | SwiftData，显式 VersionedSchema、应用级 UUID 和 repository/service 边界 |
| Images | App 私有容器中的文件；SwiftData 只保存元数据、所有权和相对路径 |
| Export / Import | 标准 ZIP；manifest.json + data.json + media/；全量导出与恢复模式 |
| Search | 本地基础包含搜索；V1 不建立独立全文索引 |
| Review | EntryKind.review，不建立独立 Review 生命周期或模块 |

该方案优先使用 iOS 17 原生能力，保持 SwiftUI 集成和测试便利，同时避免把 V1 拆成多个 package、重复 Domain/Persistence model 或通用知识图谱。

---

# Project Skeleton

## Decision

Macro Stage S0 获得实施批准并开始时，应立即创建一个 iOS App target、一个 Unit Test target 和一个轻量 UI Test target。

V1 不同时建立 Swift Package。当前代码规模、单平台边界和单一 App 交付物不足以证明 package 级模块化的成本合理。模块边界先通过目录、访问控制和小型协议表达；只有真实编译时间、复用或团队边界证明必要时，才评估拆包。

UI 不直接操作文件系统或编码导出包。ViewModel / feature logic 通过窄接口调用 EntryStore、MediaStore、SearchService 和 ImportExportService。V1 采用唯一 canonical persisted model 策略，不建立字段重复的完整 Domain Model 与 SwiftData Model 映射层；只有 Export / Import 使用独立 Codable transfer DTO。

## Recommended Directory Structure

~~~text
PersonalGrowthOS/
├── App/
│   ├── PersonalGrowthOSApp
│   ├── AppContainer
│   └── AppShell
├── Domain/
│   ├── Entry/
│   ├── Habit/
│   ├── Goal/
│   ├── Tag/
│   ├── Link/
│   └── Validation/
├── Persistence/
│   ├── Models/
│   ├── Schema/
│   ├── Repositories/
│   └── Migration/
├── Media/
│   ├── MediaStore
│   ├── ImageIngestion
│   ├── ImageLoading
│   └── MediaConsistency
├── ImportExport/
│   ├── TransferModels/
│   ├── Export/
│   ├── Import/
│   └── Integrity/
├── Features/
│   ├── Today/
│   ├── Timeline/
│   ├── Capture/
│   ├── Growth/
│   ├── Library/
│   ├── Search/
│   ├── Review/
│   └── Settings/
└── Support/
    ├── Logging/
    └── FileLocations/

PersonalGrowthOSTests/
├── Domain/
├── Persistence/
├── Media/
├── ImportExport/
└── Features/

PersonalGrowthOSUITests/
└── CriticalFlows/
~~~

## Responsibility Boundaries

| Area | Responsibility | V1 Boundary |
| --- | --- | --- |
| App | Dependency composition, lifecycle, root navigation | No service locator framework |
| Domain | Enums, value objects, validation rules and business behavior | No duplicate persisted entity model or generic domain framework |
| Persistence | Canonical SwiftData models, Schema, Container, Repository and Migration | No second field-equivalent model and no CloudKit |
| Media | Image copy, metadata, thumbnails, cleanup | No video, Live Photo, OCR |
| ImportExport | Versioned transfer DTO, package validation, restore | No merge import |
| Features | Screen-level state and user flows | No reusable design system project |
| Support | File locations and focused diagnostics | No generalized infrastructure layer |

---

# V1 Domain Model

All persisted objects use an explicit app-owned UUID. SwiftData PersistentIdentifier is an implementation detail and must not be the exported identity.

## Canonical Model Strategy

V1 has one canonical persisted model for each persisted concept.

- Macro Stage S1 defines Entry's stable semantics, enums, value rules, validation and business behavior. It does not create a second field-complete Entry entity.
- Macro Stage S2 creates the V1 canonical SwiftData Entry model. That model is the primary V1 Entry implementation used through repositories.
- Domain/ contains enums, value objects, validation rules and business behavior that do not duplicate the complete persisted field set.
- Persistence/ contains canonical SwiftData Models, VersionedSchema, ModelContainer configuration, repositories and migrations.
- Features consume the canonical model through focused repository/service interfaces rather than mapping every field into a parallel entity.
- ImportExport/ may define versioned transfer DTOs because the portable package contract must be independent of SwiftData internals.
- Names or structures equivalent to DomainEntry plus PersistentEntry, with substantially the same fields and lifecycle, are prohibited in V1.

## Required Objects and Concepts

| Object / Concept | Conceptual Fields and Rules | Delivery |
| --- | --- | --- |
| Entry | id, kind, status, optional title/body, createdAt, occurredAt, updatedAt, optional periodStart/periodEnd | Minimal semantics in Macro S1; canonical persistence in Macro S2; complete in Macro S4 |
| EntryKind | quickNote, review | Macro S1; review behavior in Macro S8 |
| EntryStatus | inbox, organized, archived | Macro S1; full flows in Macro S5 |
| Habit | id, name, lifecycle status, timestamps | Macro S6 |
| HabitLog | id, habitID, occurredAt, completion/result, optional quantity/unit, optional linkedEntryID | Macro S6 |
| Goal | id, kind, title, lifecycle status, timestamps, optional completion boundary | Macro S7 |
| GoalKind | standard, flag | Macro S7 |
| Tag | id, display name, normalized name, timestamps | Macro S5 |
| Link | id, typed source/target IDs, link kind, createdAt | Macro S5 onward |
| ImageMetadata | id, entryID, relative path, original filename/type, byte count, pixel size, checksum, sort order, timestamps | Minimal in Macro S2; complete in Macro S4 |
| GoalLifecycleEvent | id, goalID, event kind, occurredAt | Macro S7 |
| ExportManifest | package/schema/app versions, export ID/time, counts, file hashes and sizes | Transfer DTO in Macro S9 |

All listed concepts are required for V1, but they do not all belong in the first runnable slice. No AI, sync, Journey, Place, People, Project or analytics entity is reserved in the persisted schema.

## Entry Rules

- A saved Entry must contain non-empty body text or at least one image.
- An Entry supports text only, image only, or mixed text and images.
- An Entry owns zero to nine ImageMetadata records.
- createdAt records when the Entry entered the system.
- occurredAt records when the experience happened and may be years before createdAt.
- updatedAt records the last user edit.
- User edits are allowed; V1 does not store full edit history.
- New quick captures default to EntryKind.quickNote and EntryStatus.inbox.
- Archive changes Entry status; it is not the same operation as permanent deletion.

## Link Rules

Link is a small persisted implementation record, not a new user-visible core entity and not a general knowledge graph.

Allowed link kinds are limited to:

- Entry relates to Goal.
- Entry relates to Habit.
- Entry uses Tag.
- Habit supports Goal.
- Review Entry reviews Entry.
- Review Entry reviews Habit.
- Review Entry reviews Goal.

Each link validates the allowed source/target kinds, preserves app-owned UUIDs for export, and prevents an identical duplicate link. HabitLog uses an explicit optional linkedEntryID rather than owning media or rich text.

## Link and Deletion Invariants

- The active database must never contain a Link whose source or target object does not exist.
- Archive preserves the object and all of its Links.
- Permanent delete is a coordinated operation that removes or safely updates every related Link before the result becomes visible.
- Entry permanent delete removes Links where that Entry is source or target. If it is linked from a HabitLog, the HabitLog remains only when its structured fact remains valid and its linkedEntryID is cleared in the same operation.
- Review Entry deletion follows the Entry rule and removes all reviewsEntry, reviewsHabit and reviewsGoal Links owned by that Review Entry.
- Habit permanent delete removes its HabitLogs and all Entry/Habit, Habit/Goal and Review/Habit Links; linked Entries remain.
- Goal permanent delete removes its lifecycle events and all Entry/Goal, Habit/Goal and Review/Goal Links; Entries, Habits and Review Entries remain.
- Tag permanent delete removes every Entry/Tag Link; Entries remain.
- A failed delete must roll back both object and Link changes, including any media Trash movement.
- Import, schema migration, recovery and launch integrity checks validate that no dangling Link is published.

Deletion behavior is implemented and tested with each object family rather than deferred to final integration.

## Deferred and Reserved Items

| Classification | Items |
| --- | --- |
| Later V1 Stage | Habit, HabitLog, Goal, GoalKind.flag, Review behavior, full Link set, ExportManifest |
| Architecture-only reservation | Versioned schema/migration entry points and transfer schema version |
| Not reserved in V1 schema | AI, OCR, audio, video, Journey, Place, People, Project, iCloud sync |

---

# Review Boundary

V1 Review is a manually created Entry with EntryKind.review.

It may contain:

- Optional periodStart.
- Optional periodEnd.
- Links to zero or more Entries.
- Links to a Habit.
- Links to a Goal.

It participates in Timeline, Library and Search using the same Entry storage and presentation foundation. A specialized creation flow may expose the optional period and links, but V1 does not create an independent Review database entity, tab or lifecycle.

V1 explicitly excludes:

- Automatic weekly, monthly or annual reports.
- AI Review or AI analysis.
- Statistical charts and mood analysis.
- Complex templates.
- Automatic selection of important records.
- Automatically generated growth conclusions.
- An independent Review lifecycle.

---

# Persistence Strategy

## Recommendation: SwiftData

SwiftData is the V1 primary persistence solution.

Reasons:

- The deployment floor is iOS 17+, so SwiftData does not add a compatibility penalty.
- It integrates directly with SwiftUI while still permitting repository/service boundaries.
- ModelContainer supports explicit schema, configuration and migration plans.
- ModelConfiguration supports an in-memory store for fast isolated persistence tests.
- Relationships and typed fetches are sufficient for the bounded V1 model.
- It avoids a third-party database dependency before the product proves it needs lower-level SQL control.

Apple documents ModelContainer configuration and SchemaMigrationPlan in the official [ModelContainer documentation](https://developer.apple.com/documentation/swiftdata/modelcontainer), and documents in-memory configurations in [ModelConfiguration](https://developer.apple.com/documentation/swiftdata/modelconfiguration).

## Alternatives Considered

| Option | Strength | V1 Cost / Risk | Decision |
| --- | --- | --- | --- |
| SwiftData | Native iOS 17 integration, concise model layer, in-memory tests | Younger migration/query surface; model changes require discipline | Recommended |
| Core Data | Mature migrations and tooling | More boilerplate and cognitive cost for this small single-platform V1 | Do not choose initially |
| SQLite / GRDB | Explicit SQL, strong migration/query control | Third-party dependency and more infrastructure before product validation | Defer unless SwiftData fails a measured requirement |

## Risk Controls

- Define VersionedSchema from the first persisted build instead of adding versioning after data exists.
- Use explicit UUID identity and export DTOs; never rely on SwiftData internal identifiers for backup compatibility.
- Keep SwiftData access behind focused repositories so features do not scatter queries and saves.
- Exercise every schema migration against a fixture store before release.
- Keep a real on-disk persistence test in addition to in-memory unit tests.
- Do not enable CloudKit entitlements in V1.

## Database Boundary

The SwiftData store contains structured objects, links and image metadata only.

It does not contain:

- Original image binary data.
- Thumbnail binary data.
- Export ZIP content.
- Temporary import or camera files.

The database stores a relative media path, never an absolute sandbox path or temporary URL.

## Database and File Consistency

Cross-store operations use a coordinator with explicit staging:

1. Ingest: copy to a temporary staging file, validate type/size, compute checksum, then atomically move to the final media path.
2. Save: insert ImageMetadata and Entry, then explicitly save the model context.
3. Save failure: remove only files created by that failed operation.
4. Delete: move owned media to a recoverable trash directory, save database deletion, then purge trash; restore files if the save fails.
5. Launch/maintenance: detect unreferenced final files and missing referenced files, report them, and never silently delete before validation.
6. Import: build a temporary data set and media tree; publish it only after full preflight and successful persistence.

Permanent file sharing between Entries is not supported in V1. Each image file has one owning Entry, preventing deletion of one Entry from removing another Entry's content.

---

# Image Storage Boundary

## Sources and Ownership

- V1 supports Photos Library selection and camera capture.
- The App copies selected/captured image bytes into its private container.
- It does not depend long-term on a Photos Library asset identifier.
- A temporary picker/camera URL is never stored as permanent state.
- Each Entry owns at most nine images.
- Images are core Entry content, not attachments.
- HabitLog never owns an image; a HabitLog with text or image insight links to an Entry.

## Original, Display and Thumbnail Policy

- Preserve the original imported/captured bytes as the source of truth.
- Do not automatically overwrite the original with a resized or reformatted file.
- Decode/downsample on demand for display to avoid full-resolution memory spikes.
- Generate a small thumbnail only as a reproducible cache.
- Do not persist a second full-size processed copy in V1 unless profiling proves it necessary.
- Export originals only; thumbnails are recreated after import.

## Directory and Naming Policy

~~~text
Application Support/
└── PersonalGrowthOS/
    ├── Store/
    ├── Media/
    │   └── Originals/
    │       └── ab/
    │           └── image-uuid.extension
    ├── Staging/
    └── Trash/

Caches/
└── PersonalGrowthOS/
    └── Thumbnails/
~~~

- File names use image UUIDs, not user-provided names.
- A short UUID prefix may shard directories.
- The database stores paths relative to the PersonalGrowthOS root.
- Original filename and content type are metadata, not path components.
- File extension is derived from validated content type.

## Resource Budget

Provisional implementation guardrails:

- Maximum nine images per Entry.
- Accept common still-image formats supported by iOS decoding; no RAW workflow, Live Photo or video.
- Initial per-original admission limit: 25 MiB.
- Initial decoded pixel-count limit: 80 megapixels.
- Thumbnail target: at most 512 pixels on the longest edge.
- Display decoding uses target-size downsampling and avoids holding multiple originals in memory.

The 25 MiB and 80-megapixel values are provisional implementation guardrails, not Foundation decisions or long-term product contracts. Macro Stage S4 must exercise repeatable boundary fixtures and simulator-based technical checks and may adjust these values without a schema migration. Physical-device tuning remains Owner-deferred validation and does not block technical continuation. Silently recompressing the original remains prohibited.

## Capture Draft and Atomic Save

- Cancelling Photos selection leaves the existing text draft unchanged.
- Photos permission denial, picker interruption and system interruption leave the draft recoverable in the active capture flow.
- Before copying media, the App checks that available capacity can cover staged originals, final originals and a safety reserve.
- A multi-image save uses all-or-nothing semantics in V1: either the Entry, all ImageMetadata and all originals commit, or none becomes active.
- Disk exhaustion, any file-copy failure or database-save failure must not publish a partial Entry or leave orphaned originals.
- Failure cleanup removes only files created by the failed operation and never discards the user's existing text draft.
- Settings provides a basic media-storage usage value; disk-related errors also state that storage capacity is the blocking condition.

## Deletion and Recovery

- Archiving an Entry does not delete media.
- Permanent Entry deletion moves only that Entry's owned originals into Trash.
- Database deletion and trash movement follow the staged coordinator flow.
- Trash is purged only after the database save succeeds.
- Failed or interrupted operations are recoverable on next launch.
- A maintenance scan may flag orphaned files, but cleanup requires a verified ownership decision.

---

# Export / Import Format

## Recommended Package

Use a standard ZIP file for portability and manual device transfer.

~~~text
PersonalGrowthOS-export-YYYYMMDD-HHMMSS.zip
├── manifest.json
├── data.json
└── media/
    ├── image-uuid-1.heic
    └── image-uuid-2.jpg
~~~

The package contract is independent of the ZIP implementation. Macro Stage S9 must first confirm an Apple-platform implementation that emits standard ZIP. If the system API is insufficient, one narrowly scoped, maintained ZIP dependency may be proposed for separate Owner approval; no dependency is added by this planning Stage.

## Export Privacy and Temporary Files

- The V1 ZIP is not encrypted.
- Before export or share, the App warns that the package may contain private Entry text and original images and should be handled as sensitive data.
- Export is assembled in an App-private temporary directory.
- After the share/export flow completes, is cancelled or fails, the App removes temporary package and assembly files.
- Cleanup is retried on the next launch after interruption.
- Ordinary logs never record Entry body text, original image bytes, full sensitive paths or transfer DTO payloads.
- Diagnostics may record redacted object IDs, counts, sizes, schema versions and error categories.

## manifest.json

The manifest contains:

- Format identifier.
- Package schema version.
- App version/build.
- Export UUID.
- Export timestamp in an unambiguous UTC representation.
- Object counts by type.
- Data file path, byte count and SHA-256 checksum.
- Each media file's relative path, byte count and SHA-256 checksum.

The manifest contains integrity metadata, not encryption, account or cloud-sync state.

## data.json

Use one UTF-8 JSON document with arrays of versioned transfer DTOs.

Why JSON rather than JSONL in V1:

- A full restore package is bounded to one user's local data.
- Whole-package preflight and relationship validation are simpler.
- Human inspection during early development is easier.
- Streaming scale has not been demonstrated as a V1 requirement.

If measured exports become too large for bounded-memory encoding, JSONL may be introduced in a future transfer schema version without changing domain identity.

data.json preserves:

- Explicit UUIDs for all objects and links.
- Entry kinds, states and three time semantics.
- Review period and links.
- HabitLog-to-Entry relation.
- GoalKind.flag.
- Relative image references and metadata.
- Relationship endpoints and link kinds.

SwiftData internal IDs and absolute sandbox paths are never exported.

## V1 Import Mode

V1 supports:

> Full export + import into an empty database.

Empty-database import is the minimum required V1 restore capability.

Erase-and-restore may be exposed only if the old active data set is retained, the new data set is validated before publication, and every failure path can roll back to the old data. If those conditions are not proven, V1 ships empty-database import only.

V1 does not support merge import.

Consequences:

- A non-empty target is rejected unless a proven-safe erase-and-restore mode is available and the user explicitly confirms it.
- IDs are preserved exactly.
- ID collision is impossible in an accepted empty target; any duplicate ID inside the package fails preflight.
- Duplicate import into an existing data set is rejected instead of silently duplicating records.
- Complex conflict resolution is deferred.

## Import Resource Limits

Initial V1 safety limits are configuration values, not Foundation contracts:

| Resource | Initial hard limit |
| --- | --- |
| Compressed ZIP size | 8 GiB |
| Total expanded size | 24 GiB and no more than available capacity minus a 1 GiB safety reserve |
| Archive file count | 100,000 |
| Decoded object count | 500,000 |
| Compression ratio | 100:1 for the whole package or any individual archive member |

Preflight rejects a package before extraction or object insertion when a limit is exceeded. Limits may be tuned from measured V1 data without changing the persistence schema or transfer identity.

Archive handling also rejects:

- Absolute paths, parent traversal, symbolic links and paths outside the staging root.
- Duplicate normalized paths or case-colliding paths.
- Unexpected executable/special file types.
- Declared sizes, checksums or counts that do not match extracted content.
- A media file that exceeds the current supported image guardrails.

## Import Flow

1. Copy the selected ZIP to an App-owned staging location.
2. Enforce package size, expanded size, file count, object count, compression-ratio and safe-path limits before publishing any data.
3. Decode manifest and data into transfer DTOs without mutating active data.
4. Validate checksums, object IDs, relationship endpoints, Entry content rules, image ownership and absence of dangling Links.
5. Treat a missing or corrupt referenced original image as a blocking package error.
6. Build an isolated temporary SwiftData store and temporary media tree.
7. Save and re-read the temporary data set; verify counts, IDs, links and image checksums.
8. For empty restore, publish the temporary data set.
9. Expose replace/restore only when the old data set remains recoverable until the new one passes relaunch validation; otherwise do not offer this mode.
10. On any failure, delete staging output and leave the active data set unchanged.

An unsupported newer schema is rejected with a clear error. Older schema import is supported only when an explicit transfer-schema migrator exists and is covered by fixtures.

---

# Search Boundary

V1 search targets:

- Entry, including Review Entry.
- Habit.
- Goal.
- Tag.

Recommendation:

- Start with local basic contains search over Entry title/body and object names.
- Normalize Unicode width/case for comparison while preserving original text.
- Chinese text is supported as literal substring matching.
- Review Entry uses the same Entry search path.
- Do not create a separate FTS/search index until measured data volume or latency fails acceptance.
- If SwiftData's supported predicates cannot express a normalization step, fetch a bounded candidate set and normalize in the search service; measure before adding an index.

V1 does not include:

- OCR or image-content search.
- Semantic search.
- AI Search.
- Pinyin expansion, synonym search or language segmentation.
- Cloud search.

Initial technical acceptance: a concrete, representative personal-data fixture returns useful local results without visible blocking in the available iPhone Simulator. Macro Stage S5 must define and measure that fixture before accepting performance. Oldest-supported physical-device confirmation remains Owner-deferred validation.

## Search Delivery Ownership

| Macro Stage | Search responsibility |
| --- | --- |
| S5 | Implement global search for Entry and Tag; Review Entry is already compatible through the Entry path |
| S6 | Add Habit to global Search when Habit is implemented |
| S7 | Add Goal, including GoalKind.flag, to global Search when Goal is implemented |
| S8 | Verify Review Entry continues to reuse the Entry search path; do not add a separate Review index |
| S10 | Run full search regression only; do not use integration as a late stage to add missing Habit or Goal search |

---

# Navigation Skeleton

The final V1 App Shell follows the Foundation information architecture:

~~~text
App Shell
├── Today (default)
├── Timeline
├── Growth
│   ├── Habits
│   └── Goals / Flags
└── Library
    ├── Inbox
    ├── All Entries
    ├── Tags
    └── Archived

Global
├── Quick Capture
├── Search
└── Settings
    ├── Data Export
    └── Data Import
~~~

The shell is activated incrementally. The first runnable slice only needs Today, global Quick Capture and Timeline. Library, Growth, Search and Settings become functional in later Stages.

Goal responsibilities remain distinct:

| Surface | Goal / Flag responsibility |
| --- | --- |
| Today | Lightweight visibility for Active Goals / Flags that are useful today |
| Growth | Create, inspect and manage Goal / Flag lifecycle and relationships |
| Timeline | Show bounded Goal lifecycle events as history |

Today is not a ToDo list. It does not require daily Goal updates or turn Goal status into daily tasks.

This plan does not define colors, animation, typography, high-fidelity layouts or a reusable visual design system.

---

# First Runnable Vertical Slice

## Goal

Deliver the earliest real, restart-safe Capture → Persist → Timeline loop:

~~~text
Launch App
↓
Open Today
↓
Open Quick Capture
↓
Create text-only or one-image-only Entry
↓
Persist locally
↓
See Entry in Timeline
↓
Relaunch and see the same Entry
~~~

One image is included early because image-only Entry is a Foundation invariant and the database/file-system consistency boundary is a major architectural risk. The slice limits the source to Photos Library and one image; camera and up to nine images are completed in Macro Stage S4.

## In Scope

- Launchable iPhone App on iOS 17+.
- Today as the default route.
- Global Quick Capture entry point.
- Optional body text.
- One Photos Library image or text; at least one is required.
- EntryKind.quickNote and EntryStatus.inbox.
- createdAt, occurredAt and updatedAt.
- Minimal ImageMetadata and private-container copy.
- SwiftData save and fetch.
- Timeline ordered by occurredAt with a stable tie-breaker.
- Relaunch persistence.
- Clear save failure without losing the capture draft.
- Photos picker cancellation, permission denial and system interruption preserve existing text.
- Available-capacity preflight before copying the selected original.

## Out of Scope

- Habit and HabitLog.
- Goal and Flag.
- Review.
- Tags and links.
- Entry editing, archive and permanent deletion.
- Camera capture and multiple images.
- Full Library, Search or four-tab App Shell.
- Export and Import.
- iCloud, AI, OCR, analytics and visual polish.

## Minimum Domain, Persistence, Media and UI

- Domain: Entry, EntryKind.quickNote, EntryStatus.inbox, three timestamps and content validation only.
- Persistence: one versioned SwiftData schema, Entry repository and explicit save/fetch; no generic repository framework.
- Media: minimal ImageMetadata plus staged copy of one Photos Library original into the private container.
- UI: a Today screen with capture action, a capture sheet with body/photo/save controls, and a Timeline list with text or thumbnail preview.
- App: AppContainer and only the routing needed for Today, Quick Capture and Timeline.
- Tests: domain, persistence, media and one critical-flow UI smoke test.

## Validation

- Unit: reject empty capture; accept text only; accept image only; set three time values correctly.
- Persistence: save, fetch and re-open an on-disk store.
- Media: copy an image, persist a relative path, re-open and load it.
- Failure: simulated database save failure removes only newly staged media and preserves the draft.
- Failure: picker cancellation, permission denial, system interruption, insufficient disk and file-copy failure preserve text and publish no partial Entry.
- UI smoke on an available iPhone Simulator: launch → capture text → save → Timeline; relaunch → Entry remains.
- Owner-deferred physical-device validation: repeat with one image-only Entry on a real iPhone and verify real Photos Picker / permission behavior.

## Exit Criteria

- Text-only and one-image-only captures both complete in a small number of deliberate actions.
- Both appear in Timeline immediately after a successful save.
- Both survive process termination and relaunch.
- No permanent image reference uses a temporary URL or Photos asset identifier.
- The slice's Autonomous Candidate Technical Gate passes through automated tests, temporary data/media fixtures and an available iPhone Simulator.
- No Habit, Goal, Review, Search or Export / Import scope has leaked into the slice.
- Owner-deferred physical-device validation is retained for final Owner Manual Validation and does not block S3 → S4.

---

# Dogfooding and Formal V1 Observation

- After Macro Stage S3 satisfies its Autonomous Candidate Technical Gate, Codex continues to S4 when the applicable Program authorization covers it; real-iPhone validation is not an S3 continuation gate.
- Owner may separately perform informal real-life Dogfooding during S3–S9, but it is optional feedback and does not block autonomous engineering progress or count toward formal V1 exit.
- Findings may refine later approved work, fix Daily Driver blockers and tune implementation guardrails without expanding Foundation scope.
- Formal Dogfooding and the Foundation-defined continuous 30-day V1 Exit Observation are Owner-deferred physical-device validation after S10 technical completion and Owner acceptance of the Candidate.
- Codex must not claim that real-life Dogfooding or any day of the formal 30-day observation has been completed.

---

# Validation Responsibility in an Autonomous Execution Program

## Autonomous Candidate Technical Gate

Codex must complete the applicable technical evidence for each Stage using an available iPhone Simulator, Unit Tests, UI Tests, in-memory or temporary on-disk SwiftData, temporary media directories, synthetic fixtures, database reopen/restart checks, isolated Export / Import, failure injection, data/media consistency tests, static checks, full diff review and a clean working tree.

Passing this technical gate allows Codex to continue to the next authorized Stage. It does not require a Development Team, physical-device signing, Owner data or a real iPhone.

## Owner-deferred Physical-device Validation

Real-iPhone installation and launch, real Photos Picker and permission behavior, physical-device image experience, performance, memory, disk and interaction review, Owner real-life content, real-iPhone Daily Driver blocker review, formal Dogfooding and the continuous 30-day observation remain required Owner validation. They are retained for the final `Owner Manual Validation Checklist` and must not be claimed by Codex.

These checks are gates before Owner acceptance of the V1 Candidate, formal Dogfooding or the 30-day Exit Observation. They do not block S3 → S4, S9 → S10 or V1 Candidate Technical Completion. Lack of a persisted Development Team or physical-device signing does not itself require an intermediate escalation.

If concrete evidence shows that continuing without a physical-device result would endanger user-data integrity, depend on unresolved Apple platform behavior or commit the project to an irreversible design, the applicable mandatory escalation still applies.

---

# Macro Stage Governance

S0–S10 are Macro Stages / Implementation Phases. They describe sequencing and responsibility, not one-shot Codex implementation tasks.

默认采用逐子 Stage 独立批准模式。在此模式下，任何 Macro Stage 开始前：

1. Create one or more small executable sub Stage documents or task definitions.
2. Give each sub Stage an independent Goal, In Scope, Out of Scope, Validation and Exit Criteria.
3. Obtain explicit Owner approval for that sub Stage.
4. Execute only the approved sub Stage and stop at its Exit Criteria.

Macro Stages S4, S5, S6, S7 and S9 should normally be split into multiple small sub Stages because they cross several persistence, UI or failure boundaries.

Passing one sub Stage never approves the next sub Stage or the rest of its Macro Stage unless the Owner has separately approved an Autonomous Execution Program that explicitly covers them.

Owner 可以通过明确的 Autonomous Execution Program 一次性批准多个 Macro Stages。该批准必须定义授权范围、执行分支、验证要求、升级条件、Git 规则和最终 Owner Review 边界。在该 Program 的批准范围内：

1. 内部 Stage 继续作为工程、验证、提交、状态记录、故障定位和回滚边界。
2. Codex 完成一个内部 Stage 后可以自主进入下一个已授权 Stage，不再逐个等待 Owner 批准。
3. 自主执行必须服从 Foundation Documents、`DEVELOPMENT_CONTRACT.md`、获批的 Autonomous Execution Program、明确升级条件和最终 Owner Review。
4. 一次性执行授权不构成自动接受、自动合并到 `main`、自动发布或未来范围授权。

Autonomous Execution Program 只有在 `Docs/CURRENT_TASK.md` 明确记录 Owner startup authorization 后生效。Governance Baseline 被接受或进入 `main` 本身不启动 Program。

---

# Macro Stage Breakdown

## Macro Stage S0 — Project Skeleton and Test Harness

| Item | Plan |
| --- | --- |
| Macro Stage ID | S0 |
| Stage Name | Project Skeleton and Test Harness |
| Goal | Establish a launchable iPhone project and test harness without product features |
| Dependencies | Explicit Owner approval of a small executable S0 sub Stage after this plan is accepted |
| Files / Modules likely involved | App, Support, PersonalGrowthOSTests, PersonalGrowthOSUITests |
| Risk Notes | Early package/module abstraction could slow the first slice |

In Scope:

- Create the iOS 17+ SwiftUI App target.
- Create unit and UI test targets.
- Establish responsibility-based folders and dependency composition.
- Add a launch smoke test and test-only in-memory configuration seam.

Out of Scope:

- Product domain models, real persistence schema, feature UI and third-party dependencies.

Validation:

- Build for an available iPhone simulator.
- Run empty test suites and launch smoke test.
- Confirm no network or CloudKit capability.

Exit Criteria:

- App launches to a minimal placeholder.
- Both test targets run.
- Project structure matches this plan without Swift Package extraction.

## Macro Stage S1 — Entry Domain Foundation

| Item | Plan |
| --- | --- |
| Macro Stage ID | S1 |
| Stage Name | Entry Domain Foundation |
| Goal | Define the minimum stable Entry concepts and validation |
| Dependencies | S0 |
| Files / Modules likely involved | Domain/Entry, Domain/Validation, Domain tests |
| Risk Notes | Encoding UI or SwiftData concerns into domain rules too early |

In Scope:

- EntryKind.quickNote and EntryKind.review.
- EntryStatus.inbox, organized and archived.
- Explicit UUID identity.
- createdAt, occurredAt and updatedAt semantics.
- Optional review period fields.
- Text/image presence and nine-image maximum validation.
- Entry enums, value objects, stable value rules, validation and business behavior.

Out of Scope:

- The canonical SwiftData Entry model, Review UI, links, image I/O and feature screens.
- Any field-complete DomainEntry or other entity that would duplicate the S2 persisted model.

Validation:

- Unit tests for time semantics, status transitions, EntryKind.review and content validation.

Exit Criteria:

- Domain rules express every Foundation Entry invariant without implementation-only UI assumptions.
- S1 has not created a second complete Entry model or persistence field mirror.

## Macro Stage S2 — Local Persistence and Media Foundations

| Item | Plan |
| --- | --- |
| Macro Stage ID | S2 |
| Stage Name | Local Persistence and Media Foundations |
| Goal | Establish SwiftData, repository seams and safe one-image media storage |
| Dependencies | S1 |
| Files / Modules likely involved | Persistence/Models, Schema, Repositories, Migration, Media |
| Risk Notes | SwiftData migration behavior and cross-store consistency |

In Scope:

- Initial VersionedSchema and ModelContainer configuration.
- The single canonical SwiftData Entry model as V1's primary Entry implementation.
- Minimal ImageMetadata persistence.
- Explicit app UUID uniqueness rules.
- In-memory and temporary on-disk test configurations.
- Media staging, atomic move, checksum and relative paths.
- Repository save/fetch and failure cleanup.

Out of Scope:

- UI, camera, multiple images, delete workflow and import/export.
- A parallel DomainEntry/PersistentEntry mapping layer with duplicate fields.

Validation:

- Save/read/update persistence tests.
- Re-open an on-disk store.
- Simulate save and file failures.
- Verify the database contains no image binary.

Exit Criteria:

- Entry and one owned image can be persisted and reloaded through service boundaries.
- Failure leaves no newly orphaned final file.
- Features and repositories share the canonical SwiftData Entry model while Domain supplies enums, value rules and behavior.

## Macro Stage S3 — First Runnable Capture → Timeline Slice

| Item | Plan |
| --- | --- |
| Macro Stage ID | S3 |
| Stage Name | First Runnable Capture → Timeline Slice |
| Goal | Deliver the first real restart-safe vertical slice |
| Dependencies | S2 |
| Files / Modules likely involved | App, Features/Today, Capture, Timeline, Entry repository, Media |
| Risk Notes | Capture friction and image picker lifecycle |

In Scope:

- Everything defined in First Runnable Vertical Slice.
- Explicit draft preservation for picker cancellation, permission denial and system interruption.
- Disk-capacity preflight and failure paths that publish neither a half Entry nor an orphan original.

Out of Scope:

- Everything listed in that slice's Out of Scope section.

Validation:

- Autonomous Candidate Technical Gate: Unit, persistence, media and iPhone Simulator UI smoke checks defined above.
- Inject picker, permission, interruption, low-disk, copy and database-save failures.
- Owner-deferred physical-device validation: real-iPhone image-only capture, Photos Picker, permissions and interaction checks are retained for the final Owner Manual Validation Checklist.

Exit Criteria:

- All automated and simulator-based First Runnable Vertical Slice technical Exit Criteria pass.
- Missing Development Team, physical-device signing or real-iPhone evidence does not block S3 → S4.
- Physical-device validation and formal Dogfooding remain Owner-deferred and are not claimed complete by Codex.

## Macro Stage S4 — Rich Entry Media and Editing

| Item | Plan |
| --- | --- |
| Macro Stage ID | S4 |
| Stage Name | Rich Entry Media and Editing |
| Goal | Complete V1 Rich Entry creation, editing and image lifecycle |
| Dependencies | S3 |
| Files / Modules likely involved | Domain/Entry, Media, Features/Capture, Entry detail/editor |
| Risk Notes | Large-image memory peaks, disk growth and accidental media deletion |

In Scope:

- Text-only, image-only and mixed Entries.
- Photos selection and camera capture.
- Zero to nine images with ordering.
- Thumbnail cache and downsampled display.
- Edit text, occurredAt and image selection.
- Archive and confirmed permanent delete with Trash recovery.
- Resource-budget validation with repeatable boundary fixtures and an available iPhone Simulator; oldest-supported physical-device measurement is Owner-deferred.
- Multi-image save with all-or-nothing transaction semantics.
- Capacity preflight for staging and final originals.
- Basic media-storage usage visibility in Settings and actionable low-disk errors.
- Adjustment of the provisional 25 MiB / 80-megapixel guardrails from measured evidence without schema migration.

Out of Scope:

- OCR, video, Live Photo, advanced editing filters and shared image files.

Validation:

- Unit tests for image metadata and nine-image limit.
- Memory/disk tests with boundary-size fixtures.
- Delete interruption and recovery tests.
- Multi-image partial-copy, low-disk and database-save failure tests.
- Picker cancellation, permission denial and system interruption draft-preservation tests.
- Manual text, image and mixed Entry flows, including backdated occurredAt.

Exit Criteria:

- All three Rich Entry forms survive relaunch.
- Original images remain unchanged and exportable.
- Delete cannot remove another Entry's media.
- Resource thresholds are documented from measurements.
- No failed multi-image save leaves a partial Entry or orphaned original.
- The measured guardrails remain implementation configuration, not persistence schema or Foundation contract.

## Macro Stage S5 — Library, Inbox, Tags and Search

| Item | Plan |
| --- | --- |
| Macro Stage ID | S5 |
| Stage Name | Library, Inbox, Tags and Search |
| Goal | Make Entries organizable and findable without adding management pressure |
| Dependencies | S4 |
| Files / Modules likely involved | Features/Library, Search, Domain/Tag, Link, repositories |
| Risk Notes | Search latency and turning Inbox into a task list |

In Scope:

- Inbox, All Entries and Archived views.
- organized and archived transitions.
- Lightweight Tags and Entry-Tag links.
- Global basic local search across Entry, Review Entry through the Entry path, and Tag.
- Review Entry compatibility in shared Entry search queries without a separate index.
- Search performance fixture and measurement.
- Entry and Tag permanent-delete Link cleanup.

Out of Scope:

- FTS engine, semantic/AI search, OCR, folders and complex taxonomy.

Validation:

- State transition and archive tests.
- Tag/link uniqueness tests.
- Entry/Tag relation deletion, rollback and dangling-Link tests.
- Chinese literal substring and normalized Latin search tests.
- Manual organize-without-required-tag flow.

Exit Criteria:

- Users can leave content in Inbox, organize it, archive it and find it again.
- Search meets the measured fixture threshold without a separate index.
- Entry and Tag deletion cannot publish dangling Links.

## Macro Stage S6 — Habit and HabitLog

| Item | Plan |
| --- | --- |
| Macro Stage ID | S6 |
| Stage Name | Habit and HabitLog |
| Goal | Add structured habit tracking without duplicating Entry media |
| Dependencies | S5 |
| Files / Modules likely involved | Domain/Habit, Persistence, Features/Growth, Today, Timeline |
| Risk Notes | HabitLog noise overwhelming Timeline |

In Scope:

- Habit lifecycle required for V1.
- Structured HabitLog facts: completion, occurredAt, quantity, unit and simple result.
- Simple check-in creates HabitLog only.
- Optional linked Entry for text or image insight.
- Today habit check-in and habit history.
- Timeline rule that keeps ordinary logs aggregated or filtered.
- Habit integration into global Search.
- Habit permanent-delete cleanup for HabitLogs and related Links while preserving linked Entries.

Out of Scope:

- Streak shame mechanics, advanced statistics, charts and HabitLog-owned media.

Validation:

- Habit/HabitLog lifecycle tests.
- HabitLog-to-Entry relationship tests.
- Assert HabitLog schema has no image ownership.
- Habit search result tests.
- Habit relation deletion, rollback and dangling-Link tests.
- Manual simple and rich check-in flows.

Exit Criteria:

- Habit check-in is fast.
- Rich insight uses an Entry.
- Timeline remains useful with dense HabitLog fixtures.
- Habit is searchable before S6 exits.
- Habit deletion leaves no dangling Links.

## Macro Stage S7 — Goal, Flag and Core Relationships

| Item | Plan |
| --- | --- |
| Macro Stage ID | S7 |
| Stage Name | Goal, Flag and Core Relationships |
| Goal | Complete Growth with Goal, GoalKind.flag and bounded relationships |
| Dependencies | S6 |
| Files / Modules likely involved | Domain/Goal, Link, Persistence, Features/Growth, Timeline |
| Risk Notes | Modeling Flag separately or growing Link into a knowledge graph |

In Scope:

- Goal lifecycle: active, paused, completed, abandoned and archived.
- GoalKind.standard and GoalKind.flag.
- Habit supports Goal.
- Entry relates to Goal and Habit.
- Goal lifecycle events in Timeline.
- Duplicate and invalid-link prevention.
- Goal and GoalKind.flag integration into global Search.
- Lightweight Today display of Active Goals / Flags that are useful for daily context.
- Today does not turn Goals into ToDo items or require daily Goal updates.
- Clear responsibility split: Today shows lightweight active context, Growth manages lifecycle/relationships, and Timeline shows lifecycle history.
- Goal permanent-delete cleanup for lifecycle events and related Links.

Out of Scope:

- Projects, tasks, team collaboration and separate Flag entity.

Validation:

- GoalKind.flag unit tests.
- Lifecycle and GoalLifecycleEvent tests.
- Link direction, endpoint and restoration-ready ID tests.
- Goal/Flag global search tests.
- Goal relation deletion, rollback and dangling-Link tests.
- Today/Goal responsibility and no-required-daily-update UI tests.
- Manual Goal and Flag flows.

Exit Criteria:

- Flag is only a Goal kind.
- Habit → Goal direction is consistent in storage and UI.
- Timeline shows bounded Goal lifecycle events.
- Goal and Flag are searchable before S7 exits.
- Today shows lightweight Active Goals / Flags without becoming a ToDo list.
- Goal deletion leaves no dangling Links.

## Macro Stage S8 — Lightweight Manual Review

| Item | Plan |
| --- | --- |
| Macro Stage ID | S8 |
| Stage Name | Lightweight Manual Review |
| Goal | Enable manual reflection using EntryKind.review |
| Dependencies | S7 |
| Files / Modules likely involved | Domain/Entry and Link, Features/Review, Timeline, Library, Search |
| Risk Notes | Review scope drifting toward reports, templates or analytics |

In Scope:

- Manual Review Entry creation.
- Optional periodStart and periodEnd.
- Links to Entry, Habit and Goal.
- Participation in Timeline, Library and Search.
- Explicit verification that Review Entry continues to reuse the Entry search path.
- Review Entry permanent-delete cleanup for all review Links.

Out of Scope:

- Automatic reports, AI, charts, mood analysis, complex templates and independent lifecycle.

Validation:

- EntryKind.review and period validation tests.
- Link tests for all three target kinds.
- Review deletion, rollback and dangling-Link tests.
- Manual daily/weekly and Goal/Habit review examples.
- Search and Timeline integration tests.

Exit Criteria:

- Review reuses Entry storage and lifecycle.
- Review reuses Entry search and does not introduce a separate search index.
- Review deletion leaves no dangling Links.
- No automatic or analytics capability is present.

## Macro Stage S9 — Export / Import Recovery

| Item | Plan |
| --- | --- |
| Macro Stage ID | S9 |
| Stage Name | Export / Import Recovery |
| Goal | Deliver real manual backup, transfer and full restore |
| Dependencies | S8 and stable V1 schema |
| Files / Modules likely involved | ImportExport, Integrity, Persistence/Migration, Media, Settings |
| Risk Notes | Duplicate data, ID collision, corrupt packages and partial restore |

In Scope:

- Standard ZIP package.
- Versioned manifest.json and data.json.
- Original media files and SHA-256 integrity metadata.
- Full export.
- Preflighted import into empty database.
- Explicit erase-and-restore only if retained-old-data rollback is proven.
- Isolated staging, rollback, ID and relationship preservation.
- Unencrypted-export privacy warning and temporary export cleanup.
- Import size/count/compression/path resource limits.
- Redacted logging and post-import dangling-Link validation.

Out of Scope:

- Merge import, incremental backup, scheduled backup, encryption container and cloud destinations.

Validation:

- Full export/import round trip.
- Image, ID and relationship restoration.
- Missing image, corrupt manifest, duplicate ID and incompatible schema fixtures.
- Interrupted import leaves active data unchanged.
- Oversized ZIP, expansion limit, file/object count, compression-ratio and unsafe-path fixtures.
- Export completion/cancellation/failure temporary-file cleanup tests.
- Assert ordinary logs contain no Entry body, image bytes or sensitive full paths.
- Post-import/recovery dangling-Link validation.
- Autonomous technical gate: delete the isolated simulator/test data set and restore it from the export package.
- Owner-deferred physical-device validation: repeat the delete/restore rehearsal on a real iPhone.

Exit Criteria:

- A complete V1 data set can be exported, removed and restored with IDs, links and originals intact.
- Empty-database import is complete and usable.
- Erase-and-restore is exposed only if old-data retention and rollback tests pass.
- Failure never publishes a partial data set.
- Import, recovery and re-open publish no dangling Links.

## Macro Stage S10 — V1 Integration and Daily Driver Readiness

| Item | Plan |
| --- | --- |
| Macro Stage ID | S10 |
| Stage Name | V1 Integration and Daily Driver Readiness |
| Goal | Integrate the complete V1 scope and begin evidence-based Daily Driver validation |
| Dependencies | S9 |
| Files / Modules likely involved | App Shell, all Features, diagnostics, test suites |
| Risk Notes | Late scope expansion and polishing instead of real use |

In Scope:

- Final Today, Timeline, Growth and Library shell.
- Global Quick Capture, Search and Settings access.
- End-to-end regression suite.
- Full Search regression for Entry/Review Entry/Tag/Habit/Goal; S10 does not add a missing S6/S7 search implementation.
- Performance, disk, accessibility and failure-message pass for core workflows.
- Generate the final `Owner Manual Validation Checklist`.
- Prepare, but do not start or claim, the Foundation-defined formal Dogfooding and 30-day real-use observation.

Out of Scope:

- App Store launch work, AI, iCloud sync, maps, widgets, cross-platform and V2 features.

Validation:

- Autonomous Candidate Technical Gate: all automated suites, iPhone Simulator critical paths, isolated Export / Import delete-and-restore rehearsal, failure injection, static checks and complete diff review.
- Owner-deferred physical-device validation: the full manual matrix, real-iPhone install/launch, Photos Picker and permissions, physical-device performance/memory/disk/interaction, real-life content and Daily Driver blocker review.

Exit Criteria:

- Every Foundation V1 capability is present and no explicit out-of-scope capability was added.
- Core workflows work offline.
- No known technical issue blocks the simulator- and fixture-validated core workflows.
- The Autonomous Candidate Technical Gate passes and a V1 Candidate Technical Completion is produced.
- Missing Development Team, physical-device signing or real-iPhone evidence does not block S9 → S10 or S10 technical completion.
- Product is ready for Owner Manual Validation, not declared accepted or a Release Candidate.
- Formal Dogfooding and the 30-day observation begin only after Owner completes the applicable physical-device review and explicitly decides to start them; Codex does not start or claim that clock.

---

# Test and Validation Strategy

## Unit Tests

At minimum:

- Entry createdAt, occurredAt and updatedAt semantics.
- EntryStatus inbox, organized and archived.
- EntryKind.review.
- GoalKind.flag.
- HabitLog structured facts and optional Entry relation.
- Habit supports Goal direction.
- Link endpoint validation and duplicate prevention.
- Link deletion policy for Entry, Review Entry, Habit, Goal and Tag.
- Archive preserving Links.
- ImageMetadata ownership, ordering, path and checksum.
- Export / Import DTO encoding and decoding.
- Relationship reconstruction from explicit UUIDs.

## Persistence Tests

At minimum:

- Insert and save.
- Fetch after a new context/store open.
- Update and explicit save.
- Archive without media deletion.
- Permanent delete with owned-media cleanup.
- Permanent object delete with related-Link cleanup or safe reference update.
- Relationship rollback after an injected delete failure.
- App/process restart recovery through on-disk store reopen.
- Initial and subsequent schema migration fixtures.
- Database/file consistency after injected failure.
- Missing referenced file and orphaned file detection.
- Dangling-Link detection after migration, recovery and re-open.

Use in-memory stores for fast isolated behavior tests and temporary on-disk stores for migration, restart and file consistency.

## Import / Export Tests

At minimum:

- Complete full export.
- Complete empty-store import.
- Original image restoration.
- Object ID preservation.
- Link and HabitLog-to-Entry preservation.
- Missing media file.
- Corrupt manifest or data checksum.
- Unsupported schema version.
- Duplicate object ID in a package.
- Interrupted/failing import.
- Maximum compressed/expanded size, file count, object count and compression-ratio enforcement.
- Unsafe path, symlink and normalized-path collision rejection.
- Temporary export cleanup after completion, cancellation and failure.
- Log-redaction assertions for Entry body, image content and sensitive paths.
- No dangling Links after import or rollback.
- Re-export after restore produces an equivalent logical data set.

## Owner-deferred Physical-device Validation

Codex must generate these items as the final `Owner Manual Validation Checklist`. They are retained requirements for Owner acceptance and real-life validation, but they do not block autonomous Stage continuation or V1 Candidate Technical Completion.

At minimum:

- Create and reopen a text-only Entry.
- Create and reopen an image-only Entry.
- Create and reopen a mixed Entry.
- Backdate occurredAt while createdAt remains current.
- Perform a simple HabitLog check-in.
- Add Habit insight through a linked Entry.
- Create Goal and GoalKind.flag.
- Create a lightweight Review and link Entry/Habit/Goal.
- Search Entry, Review Entry, Habit, Goal and Tag.
- Export manually.
- Confirm the unencrypted-package privacy warning before sharing.
- Remove the active data set and restore it by import.
- Repeat the first slice and restore flow on a real iPhone without network.
- Verify real Photos Picker and permission behavior.
- Review physical-device performance, memory, disk use and interaction quality.
- Perform a real-iPhone Daily Driver blocker review before formal Dogfooding.

---

# Risk Register

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Image storage growth | Device storage exhaustion | Nine-image cap, admission budget, visible sizes, original-only source plus rebuildable thumbnails |
| Large-image memory peak | Crash during capture or Timeline scrolling | Metadata-first ingestion, target-size downsampling, no multi-original decode |
| Database/file inconsistency | Missing memories or orphaned files | Staging coordinator, atomic moves, Trash recovery, integrity scan and failure injection tests |
| Dangling Links | Broken navigation, search or restore | Transactional relationship cleanup plus post-delete/import/migration integrity validation |
| Multi-image partial save | Half Entry or orphan originals | Capacity preflight and all-or-nothing Entry/media commit |
| SwiftData migration failure | Existing data becomes unreadable | VersionedSchema from day one, fixture migrations, pre-release backup rehearsal |
| Import duplicate data | Repeated objects and images | Empty-store import by default, explicit UUID validation, and replace only after proven rollback |
| ID collision | Broken relationships | Preserve app UUIDs, reject duplicate package IDs, no merge import |
| Delete and restore failure | Irrecoverable loss | Archive distinct from delete, recoverable Trash, isolated restore and retained old data set |
| Foundation scope expansion | V1 never becomes usable | Stage-level Out of Scope, Owner gates, move unrelated requests to V2 |
| Quick Capture becomes heavy | User abandons capture | Text/image minimum only before save; tags, links and organization remain optional |
| HabitLog floods Timeline | Review value decreases | Aggregate/filter ordinary logs; show meaningful linked Entry independently |
| Review becomes a subsystem | Templates, analytics and automation delay V1 | Keep EntryKind.review and explicit exclusions; no Review lifecycle |
| iCloud, AI or maps distract V1 | Core offline loop delayed | No capabilities, entities or abstractions for them in V1 |
| ZIP implementation choice | Non-portable export or dependency sprawl | Contract standard ZIP first; separately approve one focused implementation if platform API is insufficient |
| Unencrypted export exposure | Private text or originals shared unintentionally | Explicit warning, private staging, prompt cleanup and redacted logs |
| Malicious or extreme import | Disk/memory exhaustion or unsafe extraction | Hard size/count/ratio limits, safe-path validation and isolated staging |
| Search performance | Slow Library with long history | Measure bounded fixture; add index only after failure is observed |

---

# Macro Stage Gates and Change Control

- Each Macro Stage is a planning phase and must retain clear engineering, validation, commit and rollback boundaries during implementation.
- By default, each executable sub Stage requires an explicit Owner-approved task with Goal, In Scope, Out of Scope, Validation and Exit Criteria.
- An explicit Autonomous Execution Program may approve multiple Macro Stages at once; within that approved range, passing one internal Stage permits autonomous continuation without a new Owner approval.
- The Autonomous Execution Program is active only when `Docs/CURRENT_TASK.md` explicitly records Owner startup authorization; governance acceptance alone does not activate it.
- Autonomous continuation remains subject to the Foundation Documents, the Development Contract, the approved Program's escalation conditions and final Owner Review.
- Autonomous Stage continuation is governed by the Autonomous Candidate Technical Gate; Owner-deferred physical-device validation is retained for final Owner review and does not block S3 → S4, S9 → S10 or Candidate Technical Completion.
- A sub Stage may refine implementation details but may not expand V1 Scope.
- A Foundation contradiction stops implementation and returns to Owner Review.
- Schema changes after real data exists require a migration fixture and export/import compatibility review.
- Media and import destructive paths require failure injection before manual acceptance.
- New third-party dependencies require separate justification and Owner approval.

---

# Owner Review Decision

Decision: APPROVED AS IMPLEMENTATION PLANNING BASELINE.

All previously stated Owner Conditions have been addressed in document version v0.2.

The following architecture choices are Owner Accepted for this implementation baseline:

1. SwiftData as the V1 persistence choice, with VersionedSchema from the first persisted build.
2. No Swift Package or multi-module project at V1 start.
3. Including one Photos Library image in the first runnable slice to validate cross-store consistency early.
4. Original-file preservation plus provisional, adjustable 25 MiB / 80-megapixel implementation guardrails.
5. Standard ZIP with manifest.json, data.json and media/.
6. Empty-database import as a required V1 capability.
7. Erase-and-restore only when retained-old-data rollback is proven.
8. Merge import deferred and Out of Scope for V1.

---

# Planning Status

Macro Stage S0 is complete on `main`. Product implementation has not started.

S1–S10 remain unstarted and have no startup authorization.

The underlying product implementation planning baseline remains Owner accepted. The v0.4 governance and validation-boundary revision is an Owner Re-review Draft on `docs/v1-autonomous-governance` and has not entered `main`.

Implementation remains unapproved.

---

# Change History

| Version | Date | Change |
| --- | --- | --- |
| v0.1 | 2026-07-16 | Initial implementation planning baseline draft. |
| v0.2 | 2026-07-16 | Addressed all Owner Conditions and retained implementation approval gates. |
| v0.3 | 2026-07-16 | Recorded final Owner acceptance of the implementation planning baseline; implementation stages remain unapproved. |
| v0.4 | 2026-07-18 | Added the Autonomous Execution Program mechanism and Current Task startup-authorization requirement; distinguished the Autonomous Candidate Technical Gate from Owner-deferred physical-device validation without changing S1–S10 product scope. |
