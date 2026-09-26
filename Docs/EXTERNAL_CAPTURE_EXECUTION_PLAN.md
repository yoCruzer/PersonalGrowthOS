# External Capture v1

## Authority and boundary

2026-09-22 Owner request authorizes text, images, URL and Safari selected content through public iOS Share Sheet APIs. Owner explicitly selected Build 9 `ae14f10` as the baseline despite PR #6 remaining Draft. Starting branch: `feature/build9-today-entry-followups`; execution branch: `codex/external-capture-v1`. Draft PR base is the Build 9 branch. No merge, release tag, build-number increment, Archive or TestFlight. Stop at independent review; full article capture is excluded.

## Implementation plan / acceptance

1. Versioned shared payload + atomic file inbox: test validation, corruption, unsupported version and original attachment checksums.
2. Ordinary Entry import with optional related source and durable receipt: test attachment rollback, post-commit retry, duplicate scan, deletion/replay, V9 migration/reopen and source backup round trip.
3. Lightweight extension, Safari preprocessing, metadata fallback and source link: build both targets and exercise representative public Share Sheet behavior where available.
4. Run final Unit and existing UI smoke/regression gates once, inspect localized UI/configuration, document actual evidence, commit/push and create Draft PR. Device-only checks remain explicitly unverified.

## Architecture

`ShareExtension → group.com.yocruzer.PersonalGrowthOS / ExternalCapture → main app → ordinary Entry`.

Both targets compile `SharedCapture/ShareInbox.swift`; the extension has no SwiftData dependency. The main private database stays in its existing Application Support location. App Group entitlements are in both targets; a device provisioning profile must authorize this group and the new extension bundle ID `com.yocruzer.PersonalGrowthOS.ShareExtension`.

Payload v1 contains stable UUID, creation time, editable text, optional source and image descriptors. Images remain files (up to 9, each 25 MB / 80 million pixels, matching existing media limits), never UserDefaults. A private staging directory receives copies, verifies sizes/checksums and serializes JSON; a same-volume directory rename publishes the complete Pending package. Cancellation removes extension working files; termination before publication leaves an unconsumed staging directory, never a partial Entry. No automatic expiration of pending user content.

The app scans at initial view appearance and foreground activation. A serialized importer uses its own ModelContext, preserving editor drafts. It validates the payload and attachments, copies media via the existing MediaStore, and commits Entry, optional EntryExternalSource and CaptureImportReceipt together. Only after commit is the inbox package deleted. A committed receipt converts subsequent scans into cleanup-only; receipts survive permanent Entry deletion to avoid resurrection. Pre-commit failures retain the original package and remove copies. Process death leaves unreferenced copies handled by the existing startup recovery machinery; the intact inbox remains retryable. Corrupt/unsupported packages are retained and reported rather than silently deleted.

## Data compatibility

Schema V10 adds EntryExternalSource and CaptureImportReceipt, with a V9→V10 lightweight migration. No historical Entry/Image/Habit schema fields change. Optional source is linked by stable Entry ID, following the existing pin/follow-up pattern. Permanent deletion removes source in the same transaction; archive/edit/pin/follow-up retain source.

Backup v6 includes entrySources; importer accepts v1–v5 without them and rejects nonempty source data falsely labeled as older formats. Source identity, endpoint, URLs and size bounds are validated. Import receipts are local delivery bookkeeping, not user content, and are not backed up. Do not open an upgraded V10 store with an older app: rollback requires an appropriate pre-upgrade backup, never destructive fallback.

## Capture and metadata

Safari preprocessing reads only document URL/title, selected text, canonical link and site name. No DOM article extraction, login reuse, source app identification or private API. Source URL opens through the standard system Link UI and only accepts HTTP(S). Original URL is retained independently of canonical URL.

LPMetadataProvider has a three-second timeout with subresources disabled; Save is immediately enabled once core content is loaded and never waits for metadata. Available title/final URL are cached in the payload/source. Metadata failure leaves the core URL intact. The source card deliberately uses text; no remote preview image/icon loading or repeated display-time request.

Apple references: [Safari preprocessing](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html), [LP timeout](https://developer.apple.com/documentation/linkpresentation/lpmetadataprovider/timeout), [subresources](https://developer.apple.com/documentation/linkpresentation/lpmetadataprovider/shouldfetchsubresources).

## Privacy and diagnostics

OSLog category ExternalCapture records provider UTTypes/selection, IDs, byte/count statistics, serialization/publication, discovery/import/receipt, media copy and metadata states. It never logs text, titles, image contents or URLs; errors log fixed reason or error type only. No source-app bundle-ID discovery. The extension performs a metadata network request only for the URL explicitly shared by the user; core saving is local.

## Known boundaries / future

WeChat works only when its UI invokes the system Share Sheet and provides supported content. Its private forwarding/favorites menus cannot be intercepted. Selected text plus page metadata depends on the host supplying Safari preprocessing results. Future full-article capture can extend the versioned payload and capture mode, but v1 implements only metadataOnly/selectedContent.

## Verification checkpoint

Historical implementation checkpoint: first sandboxed build could not access CoreSimulator (exit 70); retried using the authorized simulator build permission. First real compile caught one argument-order error, corrected before focused tests. The final passing evidence is recorded below.

Owner Device Verification: actual signed App Group access; Safari URL and selected text; Photos image; supported WeChat share; extension termination/background/main app restart; offline metadata; inaccessible source link. All test writes use isolated synthetic stores; the physical Owner database is not accessed.

### Observed targeted results

- `/tmp/PGOS-Capture-Targeted.xcresult`: 5/5 focused Unit PASS, exit 0. Payload/atomic publication, commit interruption and deduplication, image rollback/fallback, corrupt/future payload retention, V9 migration/reopen.
- `/tmp/PGOS-Capture-ShareUI.xcresult`: source backup round trip 1/1 PASS; Safari UI failed before opening the extension because the system is Chinese and its share action is in More. Whole run exit 65, not a pass.
- `ShareUI2` and `ShareUI3`: failed only on actual system accessibility lookup (ShareButton label is 共享; app targets are shareCell cells). The test uses the observed identifiers/cell labels; no product rule or assertion was weakened.
- `/tmp/PGOS-Capture-ShareUI4.xcresult`: actual Safari → system Share Sheet → 随心log Extension → shared inbox → isolated main-app Entry → source link → relaunch PASS, exit 0. Screenshot `/tmp/PGOS-Capture-ShareUI4-Shots/04FDF515-BA0C-4787-BC3B-1A0D2C2DFFE1.png` visually verified: selected quote, title and original URL, Chinese Save/Cancel and import-on-next-open notice. Final gate adds explicit quote-equality assertions.
- `/tmp/PGOS-Capture-Release.log`: unsigned generic iOS arm64 Release build of app plus embedded extension PASS, exit 0; no Archive or distribution action. Simulator signed products use the expected simulated App Group entitlement; actual device provisioning remains external.
- Catalog: 468 keys, all en/zh-Hans. Plists parse and `git diff --check` pass.
- Remote baseline checked again: `ae14f107f7eebb89a1549e00de3d941e6a996281`; GitHub Actions workflow count 0.

The UI fixture is a loopback HTML page served by the test's NWListener. Safari is exercised through actual XCUI system controls. The DEBUG-only app test hook consumes only that exact fixture URL into the existing separate UITesting store; normal UI tests never consume shared user content. The final gate includes strengthened pre-save rollback, two-image partial-copy rollback, image-only import and deletion/source cleanup assertions.

The historical default simulator store's unknown-model-version startup warning remains present, as documented before this branch. It is not erased or rebuilt. Migration tests open isolated stores and the checked-in exact older fixtures. Device-data preservation is not inferred from the simulator warning or an empty-store fallback.

### Final automated gate and bounded closure

- `/tmp/PGOS-Capture-FinalGate.xcresult`: full Unit **218/218 PASS** and 3 selected existing/new UI smoke/regression tests **3/3 PASS**, exit 0. UI covers the semantic accessibility audit, normal Entry creation/edit/relaunch, and Safari selected text → extension → Entry/source → relaunch. Unit includes historical migrations/exact stored fixtures, all existing import/export/recovery suites and the six new capture tests.
- Review found a post-commit cleanup edge: an interrupted directory deletion could leave no JSON, so parsing before checking the receipt prevented cleanup. The importer now checks the directory UUID's durable receipt first. A test removes JSON after successful commit and verifies cleanup-only retry, no duplicate and no resurrection after actual permanent deletion/source cleanup.
- Publication also rejects JSON that expands beyond the reader's 2 MB bound (for example escaped control text); optional canonical URLs and provider metadata are bounded so enrichment cannot invalidate otherwise valid core content.
- `/tmp/PGOS-Capture-Closure.xcresult`: all 6 capture Unit tests plus the strengthened Safari UI **7/7 PASS**, exit 0. UI asserts exact selected text, title, original-source link, actually opens Safari via that link, and verifies restart persistence. This is the final product code; the broader gate is not redundantly rerun after these narrowly tested fixes.
- `/tmp/PGOS-Capture-ReleaseFinal.log`: final incremental unsigned Release app/extension build **PASS**, exit 0. Bundle inspection confirms both targets remain 1.0 (7), the extension is embedded and its Safari script is bundled.

Actual gate commands (same iPhone 16 / iOS 26.5 destination; no erase, clean, Archive or release upload):

```sh
xcodebuild test -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=5F04DE28-8329-4774-9488-076D6DDC5230' -derivedDataPath /tmp/PGOS-Capture-Derived -parallel-testing-enabled NO -only-testing:PersonalGrowthOSTests -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testExternalCaptureSafariShareAndImport -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTextCaptureAppearsInTimelineAndSurvivesRelaunch -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testCoreShellPassesAccessibilityAudit -resultBundlePath /tmp/PGOS-Capture-FinalGate.xcresult
xcodebuild test -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=5F04DE28-8329-4774-9488-076D6DDC5230' -derivedDataPath /tmp/PGOS-Capture-Derived -parallel-testing-enabled NO -only-testing:PersonalGrowthOSTests/ExternalCaptureTests -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testExternalCaptureSafariShareAndImport -resultBundlePath /tmp/PGOS-Capture-Closure.xcresult
xcodebuild build -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/PGOS-Capture-Release CODE_SIGNING_ALLOWED=NO
```

### Validation limits

The simulator's real host-provider integration covers Safari selected content and URL/title/source reopen. Text-only, image-only, image+URL, multi-image rollback, metadata-absent fallback and corrupt/future payload handling are validated at the payload/import boundary. Photos/WeChat provider variations, real network timeout/offline interaction, physical App Group provisioning, and system termination of a live extension remain Owner Device Verification. No simulator result is labeled a physical-device pass. The new schema's synthetic V9 fixture and the existing exact older fixtures prove automated compatibility; an overlay against the Owner's actual Build 9 database is still a device gate.

Unsupported images (e.g. GIF/WebP), video, full webpage bodies and source-app identity are outside this v1 implementation. Pending packages never expire automatically; uncommitted shared staging left by abrupt termination is not imported and may remain on disk. No saved share is silently deleted to reclaim space.


## Final delivery

**COMPLETE — READY_FOR_INDEPENDENT_REVIEW.** Tested product implementation: `068a27a`. Ordinary push succeeded; [Draft PR #7](https://github.com/yoCruzer/PersonalGrowthOS/pull/7) targets `feature/build9-today-entry-followups` from `codex/external-capture-v1`. Following documentation-only commit records the handoff; it does not change tested product code. Both current-context documents are updated. No merge, Ready-for-review conversion, tag, build-number change, Archive or TestFlight occurred. Stop here; independent review and Owner device checks are the next boundary.


## 统一收口审计 2026-09-26

授权输入：Owner 上传包的 `02_CODEX_CLOSURE_GOAL.md`、`01_AUDIT_REPORT.md`（已按顺序完整阅读），覆盖 R1–R9/L1–L2，替代上方历史 COMPLETE 边界。终点仍为 READY_FOR_INDEPENDENT_REVIEW；本轮尚未完成。

计划：先 R4 确定性交错及 R2 单消费者/发布互斥，再 provider/metadata/失败 Inbox/所有权/搜索/诊断，最后统一 final gate 与 L2 交付。定向测试优先，不先跑全量 baseline。

| ID | 当前结论 | 证据 / 下一验证 |
| --- | --- | --- |
| R4 | CONFIRMED → 修复定向验证中 | restore worker 安装 Originals 后，catch 删除整个目录；MainActor importer 无共享互斥。新增 `testRestoreFailurePreservesInterleavedCommittedShareImage` 用 beforeSave checkpoint + semaphore 控制交错，断言已提交分享图片保持可读。 |
| R2 | CONFIRMED（静态） | importer.scan/consume 同步 MainActor；将与 R4 共同修改并验证。 |
| R1 | CONFIRMED（静态/官方规则） | Apple 激活字典 version 2 对混合 asset 匹配成立；实际 provider/系统面板补验待做。 |
| R3 | CONFIRMED（静态） | 前台仅 Retry/Cancel，无持久稍后或按条处理入口；待修复。 |
| R5 | CONFIRMED（静态） | loadItem/loadFileRepresentation continuation 无超时/取消管理；待修复。 |
| R6 | 修复验证中 | 外部可选 metadata 统一按 UTF-8 预算截断完整 Character，严格 payload/backup 验证不放宽；2 项定向测试通过，结合后续 UI 继续验证。 |
| R7 | CONFIRMED（静态/生命周期待验） | App Group staging 无独立回收；导出 Pending 告知与 owned recovery 补偿待做。 |
| R8 | 修复验证中 | source 字段合并去重与真实提交后刷新已实现，来源仅字段 Unit 通过；Safari 空结果刷新和 follow-up UI 均通过（R8 运行 exit 0）；final gate 待做。 |
| R9 | CONFIRMED（静态） | startup 丢弃 Error，缺可复制脱敏报告与非破坏重试；待修复。 |
| L1 | 待核实 | 显式 SwiftData import / Release warning。 |
| L2 | 进行中 | 起始本地/远端 ab79c734f1f53a60484ba4bc5f6247cbe9b14b3b；PR #7 OPEN Draft，base 未变。当前上下文已标旧 handoff superseded。 |

首次沙箱内 R4 测试无法访问 CoreSimulator，日志 `/tmp/PGOS-Closure-R4-Repro.log`；不属于产品失败。获准访问模拟器后的同一定向测试运行使用 `/tmp/PGOS-Closure-R4-Repro2.log` 与 `.xcresult`，复现退出码 65：Entry/receipt 已提交且 Pending 已清理，但读取分享图片抛出文件不存在（NSCocoaErrorDomain 260）。所有测试使用合成隔离库。


### R4/R2 第一组证据

- 原缺陷运行复现：`/tmp/PGOS-Closure-R4-Repro2.xcresult`，exit 65，`testRestoreFailurePreservesInterleavedCommittedShareImage` 图片可读断言失败；不是 Owner 真机事故。
- 修复：同一标准化媒体根目录的 `StorePublication` 锁覆盖完整同步 worker 操作，无 await 重入；导入的私有 ModelContext 在 worker 创建/使用，扫描、hash、拷图离开 MainActor。恢复与导出快照/媒体读取共用该发布边界。恢复失败只清理此次安装的图片路径；成功不 rollback 主 context。
- `/tmp/PGOS-Closure-R4-Fix.xcresult`，exit 0，8/8：上述交错回归、恢复中断及 6 项现有 ExternalCaptureTests。分享请求在恢复 beforeSave 暂停期间已调度，receipt 仍为 0、Pending 保留；释放恢复失败后分享提交且图片可读。receipt/reopen/永久删除不复活、图片失败回滚、V9 迁移、source 备份往返均通过。
- 安装后取消及成功恢复期间编辑草稿验证：首次 `Cancellation` 因 fixture 缺少 createdAt 编译失败（exit 65）；修正后 `/tmp/PGOS-Closure-R4-Cancellation2.xcresult` exit 0，2/2 PASS。取消后排队分享完成；成功与取消均保留主 context 未保存草稿。
- R4 其余检查点、导出一致边界验证与 R2 extension 重 I/O 仍待完成；不得将本组通过写成全部收口完成。

命令公共前缀：`xcodebuild test -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=5F04DE28-8329-4774-9488-076D6DDC5230' -derivedDataPath /tmp/PGOS-Capture-Derived -parallel-testing-enabled NO`。

各运行附加参数（日志为同名前缀 `.log`）：

```text
Repro2: -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests/testRestoreFailurePreservesInterleavedCommittedShareImage -resultBundlePath /tmp/PGOS-Closure-R4-Repro2.xcresult
Fix: -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests/testRestoreFailurePreservesInterleavedCommittedShareImage -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests/testInterruptedPublicationLeavesEmptyTargetAndNoOriginals -only-testing:PersonalGrowthOSTests/ExternalCaptureTests -resultBundlePath /tmp/PGOS-Closure-R4-Fix.xcresult
Cancellation2: -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests/testRestoreCancellationAfterInstallReleasesShareAndPreservesDraft -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests/testSuccessfulRestoreDoesNotRollbackDraftCreatedDuringPublication -resultBundlePath /tmp/PGOS-Closure-R4-Cancellation2.xcresult
```

2026-09-26 实时 PR 列表：#1–#7 仍全部 OPEN Draft，#2→#3→#4→#5→#6→#7 base 链与审计相同；#1/#2 重叠及云端 release identity 尚待核实。未更改远端 PR 状态。


### 当前发布与集成证据（L2，2026-09-26）

- 实时 GitHub main：`dd09975d3a3736b24f8646fa4f197cc883ab1796`。
- 已推送本轮第一组代码：`b25c59d00726395622923cab9a9c11d0d1555ef5`，API 核实 PR 分支远端一致。SSH push 因 publickey 失败；使用既有 gh 登录凭据的 HTTPS 普通 push 成功，无凭据或远端配置改动。
- `git merge-base --is-ancestor 19475fe0830d9a2c8ceff4f27adc63ed4ecab7a7 1a1f6bb6d4b95470a7add37d15c5cfdbc5edd0ed` exit 0：PR #1 远端 head 完整包含于 PR #2。PR #1 无独有代码需要重复合并。需保留其中 Weight/persistence/backup/review 修复提交 `6c5ec6c`、`17d3607`、`77d98a5`、`f8a1298` 及其历史；#2 另外包含图标提交 `c45c666` 与 S2 后续。
- 未来经 Owner 授权可先集成 #2（保留 #1 已包含历史），再依序 #3→#4→#5→#6→#7；#1 如何关闭或合并及各 PR base 调整由 Owner 决定。本轮未执行任何 merge/close/retarget。

| 发布身份维度 | 当前可见证据 |
| --- | --- |
| 开发阶段 | Build 9 / External Capture v1，不是安装构建号 |
| 工程 App/Extension | 1.0 (7)，本轮不改号 |
| Build 9 git tag | `testflight-1.0.0-build9` → `ae14f107f7eebb89a1549e00de3d941e6a996281` |
| 云端 Archive | `PersonalGrowthOS / TestFlight-workflow / Archive - iOS`：2026-09-16T15:15:17Z completed/success，0 errors / 1 warning |
| 云端实际 CFBundleVersion | UNKNOWN，check API 未提供 |
| TestFlight 上传/处理/可安装性 | UNKNOWN / OWNER_REQUIRED，tag 和 Archive success 不替代这项证据 |
| External Capture 起始 HEAD checks | ab79c73：0 check runs |
| 当前 Owner 真机验收 | OWNER_REQUIRED，尚无本轮签名/App Group、provider、升级数据门禁证据 |

本轮继续沿用 Xcode Cloud，没有建立额外 CI 或触发发布工作流。


### R6/R8/L1 第二组（定向验证通过，final gate 待做）

- R6：Safari JS、attributedTitle、LP callback 均走 `CaptureSource.normalizeMetadata`。完整 Character 的 UTF-8 预算为 title 32768 / siteName 4096；无效或过长 canonical 丢弃，可选 metadata 不改变原始 URL/正文。ASCII、中文、组合 emoji、附加符、空值/超长字段和严格非法 payload 拒绝通过。当前保存为同步 immutable 发布；R2 extension 异步化后仍需复验晚到 callback 与快照边界。
- `/tmp/PGOS-Closure-R6.xcresult` exit 0，2/2：`testOptionalMetadataUsesUTF8BudgetWithoutChangingCoreContent` 与 `testSourceBackupRoundTrip`。该测试不是 LP 实际超时证据。
- R8：搜索将 source URL/canonical/host/siteName/title 的 Entry ID 与既有结果合并去重，保持原排序与 follow-up 片段定位。worker 在数据库 save 成功后发送 scoped commit 通知，搜索在 MainActor 刷新保留 query，包括空结果页；清理失败不撤销 commit 通知。
- L1：`SearchView.swift` 已显式 import SwiftData；最终 Release warning 门禁仍待统一执行。
- `/tmp/PGOS-Closure-R8.xcresult`：metadata/来源字段 Unit 2/2 已通过；真实 Safari 系统分享→extension→异步导入→保留的 `127.0.0.1` 空搜索自动命中、来源打开、重启持久化 UI 已通过。既有 follow-up 删除返回刷新 UI 通过；整次 2 Unit + 2 UI，exit 0。

公共 xcodebuild 前缀同上，具体参数：

```text
R6: -only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testOptionalMetadataUsesUTF8BudgetWithoutChangingCoreContent -only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testSourceBackupRoundTrip -resultBundlePath /tmp/PGOS-Closure-R6.xcresult
R8: -only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testSourceOnlySearchMatchesAfterEntryRenameWithoutDuplicates -only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testOptionalMetadataUsesUTF8BudgetWithoutChangingCoreContent -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testExternalCaptureSafariShareAndImport -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPR6SearchRefreshesAfterDeletingMatchedFollowUps -resultBundlePath /tmp/PGOS-Closure-R8.xcresult
```
