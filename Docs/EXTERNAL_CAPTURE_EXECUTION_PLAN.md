> 当前入口为下方“统一收口审计 2026-09-26”及其逐组证据，状态 IN_PROGRESS。其前的 2026-09-22 COMPLETE/Stop 指令属于历史 handoff（superseded），不指挥当前 Goal。Owner-only 验收统一使用 [当前候选清单](OWNER_MANUAL_VALIDATION_CHECKLIST.md)。

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
| R4 | FIXED（final gate 待做） | 原图片丢失已确定性复现；共享发布锁/私有 context/拥有路径清理后，失败、安装后取消、二次空库检查、成功恢复排队分享、导出 cutoff 与草稿保护均定向通过，详见第一及第七组。 |
| R2 | 修复实现 / 继续验证 | 主 App importer 与 Extension 发布/图片校验/hash/缩略图移至 worker；同包并发消费幂等通过。九张总量 >180 MiB PNG 导入九次 MainActor 响应及草稿保护已通过；最终门禁与真机性能仍待做。 |
| R1 | 修复实现 / 公共 host 验证通过 | version 2 默认匹配；真实独立混合 host 与 Safari 均出现并完整导入。语义化选择、caption、替代表现、部分失败及多来源提示已实现；部分保存确认 UI 已通过；真机及统一门禁待做。 |
| R3 | FIXED（final gate 待做） | 失败状态持久化、同故障仅首次提醒、设置页逐条重试/稍后/确认丢弃已实现；版本变化重新尝试，receipt 优先区分已提交副本。3 Unit + 1 UI 定向通过。 |
| R5 | FIXED（final gate 待做） | once-only bridge、30 秒边界、Task/Progress/generation 的 Unit 与部分保存 UI 通过；取消返回系统选择器后可实际重开，旧 provider 回调后无污染/无幽灵 Entry。直接回 host 的旧断言由标准 SLCompose 对照证伪，实际选择器截图可见，详见第八组。 |
| R6 | 修复验证中 | 外部可选 metadata 统一按 UTF-8 预算截断完整 Character，严格 payload/backup 验证不放宽；2 项定向测试通过，结合后续 UI 继续验证。 |
| R7 | FIXED（final gate 待做） | staging 活跃租约/终止回收、写前副本日志/逐文件补偿、实际测试进程终止恢复、低容量注入及导出 Pending 告知已定向通过；未知 Recovery 保留。 |
| R8 | 修复验证中 | source 字段合并去重与真实提交后刷新已实现，来源仅字段 Unit 通过；Safari 空结果刷新和 follow-up UI 均通过（R8 运行 exit 0）；final gate 待做。 |
| R9 | FIXED（final gate 待做；历史库根因未验证） | 白名单阶段/类别/角色/版本/schema/opID/domain-code 报告可复制，启动安全重试保留 Entry，导入诊断持久化后成功消退；2 Unit + 1 UI 通过。历史主文件 V8 hash 差异只读记录，不等同 Owner 根因。 |
| L1 | FIXED（Release gate 待做） | 显式 SwiftData import 已补，最终 Release warning 核查尚待统一门禁。 |
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


### R1/R2/R5 与 R7 staging 第三组

当前实现：

- `ShareProviderReader` 使用公开 NSItemProvider API。一个 provider 的表示按语义择优/失败回退；独立 caption 保留。Safari JS 返回的 title 与同一 item 的同值 caption 仅去除重复表示，不覆盖选中文字。未知辅助 provider 跳过并记录类型；已知图片缺失、数量超限、多个来源须显示问题并由用户重试或明确确认仅保存显示内容，其他 URL 保留为文字。文件 URL 不成为网页来源。
- 真实跨进程 NSURL 读取使用 `loadObject(NSURL)`，保留 legacy `loadItem` 回退；文本同时支持 NSString/NSAttributedString/UTF-8、带 BOM 的 UTF-16 Data。回调 bridge 本地最多完成一次；超时/取消后拒收迟到结果，Progress.cancel 只是尽力通知提供方，不宣称其网络立即停止。
- load Task、generation 与 metadata 回调有会话边界；重试保留用户已编辑正文。保存冻结值快照，worker 复制/校验/发布，保存中暂时禁用重复 Save/Cancel 并显示状态；metadata 不再修改保存快照。图像临时文件在 provider callback 内复制，之后 worker 执行校验/hash/缩略图。
- `NSExtensionActivationDictionaryVersion = 2`，保留类型与数量声明，不使用 TRUEPREDICATE。没有启用 strict matching：真实混合 host 在 strict 模式未出现，在 version 2 默认匹配出现。参见 [Apple activation keys](https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html)。
- 同包重复显式 consume 在同一 store 发布边界串行；第二次凭 receipt 只做幂等清理。Extension 不直接写数据库。
- App Group staging 以目录 `.lease` 内核 flock 证明活跃所有权，创建/回收用短 registry lease 排除创建窗口；进程终止释放锁后可回收未发布副本。Pending 不过期、不参与回收；没有 lease 标记的旧目录保留，不能仅按年龄删除。

证据及失败记录（均保留真实结果）：

| 运行 | 结果 | 含义 |
| --- | --- | --- |
| `/tmp/PGOS-Closure-Providers.xcresult` | exit 0；3/3 Unit | 公开混合 provider、unknown、caption、失败回退/部分失败/多来源、once-only 超时/取消/迟到回调 |
| `/tmp/PGOS-Closure-ProvidersUI.xcresult` | exit 65；12 Unit PASS，2 UI FAIL | Safari title caption 重复使原文精确断言失败；初始同 App host 无扩展。未弱化断言。 |
| `/tmp/PGOS-Closure-ProvidersUI2.xcresult` | exit 65；Safari PASS，独立 host FAIL | Safari 语义去重修复通过；排除了仅“自身 host”解释，独立 host strict 匹配仍无扩展。 |
| `/tmp/PGOS-Closure-HostModern.xcresult` | exit 65 | 独立 host 换标准 NSItemProviderWriting 后 strict 仍未显示扩展。 |
| `/tmp/PGOS-Closure-Activation2.xcresult` | exit 65；13/13 Unit PASS，host 进入扩展但未完整保存 | 默认 version 2 匹配实际出现；跨进程 URL 读取失败触发部分保存确认，旧 UI 测试误将 editor 隐藏视为完成，最终入库断言正确失败。 |
| `/tmp/PGOS-Closure-ModernURL.xcresult` | exit 0；1 Unit + 1 UI PASS | 公开 NSURL loadObject 修复后：独立混合 host→系统面板→extension，正文精确匹配、无部分确认、保存后主 App 导入。 |
| `/tmp/PGOS-Closure-ProviderFinalTargeted.xcresult` | exit 0；3 Unit + 1 Safari UI PASS | 并发同包消费、图片首选失败替代成功/图片+网页 URL/10 图数量提示、旧 provider 回退/多来源、最终 Safari 全路径及空搜索提交刷新 |
| `/tmp/PGOS-Closure-StagingTermination2.log` | exit 0 | 生产 staging 代码的独立 macOS 合成进程：FIFO readiness barrier 后活跃时 reclaimed=0；SIGKILL 本测试子进程后 reclaimed=1。不是 iPhone Extension 终止实测。 |

测试 host 是独立临时模拟器 app `com.yocruzer.CaptureFixtureHost`，源码在 `PersonalGrowthOSUITests/Fixtures/CaptureHost/`，构建命令 `sh Scripts/build_capture_fixture_host.sh`（当前成功日志 `/tmp/PGOS-CaptureHost-Build3.log`）。用 `xcrun simctl install 5F04DE28-8329-4774-9488-076D6DDC5230 /tmp/PGOSCaptureFixtureHost.app` 安装。第一次安装时设备为 Shutdown，随后 boot/bootstatus 同一设备成功再安装；没有 erase 或删除用户数据。首次 host 编译因默认 ModuleCache 无权限失败，脚本改用显式 `/tmp` cache 成功。

进程终止验证命令：`sh Scripts/verify_capture_staging_termination.sh`，证据 root `/tmp/PGOS-StagingTermination.dnMai4`。此前 readiness-file 版本也通过，最终用 FIFO barrier 无时间猜测。

xcodebuild test 公共前缀同上。关键通过运行附加参数：

```text
ModernURL: -only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testPublicProvidersPreserveMixedContentAndSkipUnknownAuxiliary -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPublicMixedProviderHostShowsExtensionAndImports -resultBundlePath /tmp/PGOS-Closure-ModernURL.xcresult
ProviderFinalTargeted: -only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testConcurrentExplicitConsumptionCommitsOnceAndCleansIdempotently -only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testImageRepresentationFallbackWebSourceAndCountLimit -only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testProviderAlternativesPartialFailureAndMultipleSourcesAreExplicit -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testExternalCaptureSafariShareAndImport -resultBundlePath /tmp/PGOS-Closure-ProviderFinalTargeted.xcresult
Activation2 (13 Unit pass; UI fail as above): -only-testing:PersonalGrowthOSTests/ExternalCaptureTests -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPublicMixedProviderHostShowsExtensionAndImports -resultBundlePath /tmp/PGOS-Closure-Activation2.xcresult
```

后续仍须：R3 最小失败 Inbox；R7 owned-copy journal/Recovery 补偿、容量与逐文件清理、导出 Pending 边界；R9 脱敏诊断与安全重试；R4 剩余检查点/导出交错；R2 大图主线程响应；新 UI 部分保存/取消；L2 旧文档与 Owner 清单归一及统一 final gate。尚不 READY。


### R3 失败 Inbox 第四组（2026-09-26，定向通过）

- 第三组提交 `a5cd018d23c9742f30280476761cb6b8cb83567a` 普通 HTTPS push 成功；实时 `gh pr view 7 --json number,state,isDraft,baseRefName,headRefName,headRefOid,url` 核实 OPEN Draft、同 SHA、base 仍为 `feature/build9-today-entry-followups`。
- 状态文件位于主 App 媒体根目录，包 ID/稳定原因/稍后处理版本持久化；未知 schema 继续保留。正常包仍被扫描，同一坏包同原因不反复弹窗；稍后处理跨重开，版本变化可重新尝试，手动 Retry 绕过稍后状态。
- 设置页提供 Pending Shares，逐项显示日期、短 ID、状态与操作。未导入丢弃与已提交副本清理有不同说明，确认只移除选中 Pending，绝不删除 Entry/receipt。所有状态操作复用同一发布租约；UI testing 仅访问自己 root 下 UITestInbox，不进入私人共享队列。
- `/tmp/PGOS-Closure-Inbox1.log` exit 70：沙箱无法访问 CoreSimulator，非产品测试结果。
- `/tmp/PGOS-Closure-Inbox2.xcresult` exit 65：两个新 Unit 的测试 ID 使用大写 UUID，与生产 Pending 小写目录不符，逐条操作未命中；夹具改为实际目录 ID，未放宽断言。
- `/tmp/PGOS-Closure-Inbox3.xcresult` exit 65：新增 UI 测试误用不存在的 XCUIElement.lastMatch，未运行；已改为系统确认 sheet 内的按钮。
- `/tmp/PGOS-Closure-Inbox4.xcresult` exit 65：两项 Unit 均通过；UI 的系统 confirmationDialog 实际呈现 popover 并隐藏取消按钮，原取消动作测试失败。改用具有明确取消动作的 alert，继续定向 UI 复验。公共 xcodebuild 前缀同上，附加两项 `ExternalCaptureTests/testFailedInboxDeferralSurvivesReopenAndVersionChange`、`ExternalCaptureTests/testPendingRetryAndDiscardAreSelectedAndReceiptAware` 和 `AppLaunchSmokeTests/testPendingInboxDefersAndConfirmsOnlySelectedDiscard`。日志同名前缀 `.log`。

本组不替代 R7 导入副本补偿/备份边界、R9 诊断或其他剩余收口项；完整 Goal 仍为 IN_PROGRESS。

R3 后续 UI 复验：`/tmp/PGOS-Closure-InboxUI5.xcresult` exit 0、1/1 PASS，公共前缀 + `-only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPendingInboxDefersAndConfirmsOnlySelectedDiscard`。取消不删、确认仅选中项、重启不弹窗且保留另一条 deferred 均通过。Inbox4 的失败 UI 层级及录屏导出在 `/tmp/PGOS-Inbox4-Attachments`。首次在进程退出前导出结果包未完成，进程 exit 65 后读取成功；非产物损坏。

R3 补充 Unit `/tmp/PGOS-Closure-InboxUnit6.xcresult`：在 deferred 坏包存在时加入新好包和新坏包，要求新好包提交、新故障单独提示；并回归 receipt 中断重开/删除不复活。公共前缀附加 `-only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testFailedInboxDeferralSurvivesReopenAndVersionChange -only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testPendingRetryAndDiscardAreSelectedAndReceiptAware -only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testImportCommitInterruptionRetryDeletionAndReopen`。exit 0，3/3 PASS。495 个字符串键 en/zh-Hans 完整，JSON 与 `git diff --check` 通过。


### R7 导入副本补偿与备份边界 第五组（定向通过）

R3 第四组提交 `c6b024656c8da28c97d4f8b6fcb244215b8754aa` 已推送；实时 GitHub API 核实 PR #7 OPEN Draft、head 一致、base 未改，PR body 已更新前四组真实进度。

R7 新实现：在每个导入副本写入前，原子持久化 operation/capture ID、预分配图片 UUID、类型与 checksum。启动及扫描/回滚补偿只检查由此精确推导的 Originals/Recovery 路径；已被数据库引用的图片保留，checksum 或归属不符、未知日志/未知 Recovery 保留。逐文件失败继续清理其他条目，并保留失败项日志供之后重试。数据库提交后移除日志；提交与日志清理之间进程终止时，由数据库引用保护文件。

- `/tmp/PGOS-Closure-OwnedCopies1.xcresult` exit 65：既有附件回滚与 receipt 中断两项 PASS；新两项 fixture 把 MediaStore 的 MIME 类型误写成 UTI `public.png`，在复制前正确拒绝，已改为 `image/png`。
- `/tmp/PGOS-Closure-OwnedCopies2.xcresult` exit 65：UI fixture 的 publish 文件字典误用 filename 而非 UUID，编译拒绝，已修正。
- `/tmp/PGOS-Closure-OwnedCopies3.xcresult` exit 65：3 Unit PASS；UI fixture 的附件 filename 不符合已存在 UUID 协议，未到达复制检查点，已修正 fixture，未修改协议。
- `/tmp/PGOS-Closure-OwnedCopies4.xcresult` exit 0：1 Unit + 1 UI PASS。`ImportExportRecoveryTests/testExportDrainsValidSharesAndDisclosesOnlyUnimportedPending` 证明合法分享先导入后包含于可恢复备份，future schema 包保留且排除数量为 1。`AppLaunchSmokeTests/testKilledImportBeforeSaveReclaimsOwnedCopyAndRetriesPending` 在实际图片持久化后/DB save 前暂停 worker，确认 Record Tab 可交互后终止测试 App，再两次重开，证明 Pending 只导入一次、Originals 一份、Recovery 为零。仅测试独立 root，不操作默认用户库。
- 本组各定向结果如下；全目标 final gate 仍待其余收口项稳定，不以这些局部结果宣称 READY。

R7 备份新增行为：可消费分享先导入；随后在共享发布边界内统计无 receipt 的 Pending 并制作快照。导出完成后，若排除数量非零，明确告知并由用户选择分享备份或取消；Pending 保留。已提交仅清理失败的副本不计入排除数量。容量不足增加扩展可理解提示，并新增发布前 ENOSPC/主导入低容量注入验证。

容量/导出 UI 定向运行 `/tmp/PGOS-Closure-CapacityExport5.xcresult`，公共前缀附加 `-only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testStorageFailureNeverPublishesOrCommitsPartialShare -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testBackupDisclosesPendingExclusionAndCancelKeepsShares`；exit 0，1 Unit + 1 UI PASS。容量验证为合成故障注入，不代表实际耗尽真机磁盘。OwnedCopies3 参数为两个 `testOwnedCopy*` Unit、`testAttachmentRollbackRetryAndMetadataFallback` 与上述 kill UI；OwnedCopies4 参数为上述导出 Unit 与 kill UI。均使用本节统一 xcodebuild 前缀，日志为同名前缀 `.log`。

第五组补充核查：数据库引用保护、未知 Recovery 保留、每文件失败继续及重试均通过；备份 v6 结构未改，Pending 不打包、不删除。`git diff --check` 与 499 键 en/zh-Hans 完整性检查通过。R4 剩余交错、R2 大图响应、R1/R5 部分保存/取消 UI、R9 与 L2/最终门禁仍未完成。


### R9 诊断与安全重试 第六组（定向通过）

第五组 `b0fbdc975cf8b26a02fbc79dc946d737e9d1ba61` 已推送，PR #7 远端核实一致且仍 OPEN Draft/base 不变，handoff 已更新。

- 诊断只包含固定 role/stage/category、受限版本/build、schema、操作 UUID、允许的 NSError domain/code。不会输出 localizedDescription、完整 userInfo、SQL、标题/正文/图片/URL query 或私人路径；unknown domain 与非版本格式字符串显示 unlisted/unknown。
- 启动阶段区分路径准备、store-open、media-recovery、integrity；保留故障并提供复制报告和复用原库的 Retry。重试明确 resetDataOnLaunch=false，不添加清库/重建 fallback。导入失败诊断存入本地 Inbox 状态并可逐项复制，成功处理后随该待处理项消退；扩展读取/保存错误亦可复制 role=shareExtension 的报告。
- `/tmp/PGOS-Closure-Diagnostics1.xcresult`：2 Unit PASS；UI FAIL（整体 exit 65），实际报告已显示，但父级 accessibilityIdentifier 覆盖了报告与按钮的独立标识。已修正父级标识作用域，未放宽隐私或保留 Entry 的断言。失败实际 UI 层级在 `/tmp/PGOS-Diagnostics1-Attachments`。
- `/tmp/PGOS-Closure-Diagnostics2.xcresult` exit 0，2 Unit + 1 UI PASS。公共前缀附加 `-only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testDiagnosticsUseOnlyAllowlistedFieldsAndDistinguishFailures -only-testing:PersonalGrowthOSTests/ExternalCaptureTests/testFailedInboxPersistsSanitizedDiagnosticUntilSuccessfulRetry -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testStartupDiagnosticCopiesAndSafeRetryPreservesExistingEntry`。日志同名前缀 `.log`。启动故障为合成注入，非模拟真实 Owner 数据事故。

历史模拟器只读证据：`/tmp/PGOS-Closure-HistoricalStoreMetadata.json`。通过 simctl 定位当前标准 App root（非 UITesting），只以 SQLite `mode=ro&immutable=1` 读取 Z_METADATA 模型元数据，不读取记录正文、不 replay WAL、不迁移或删除。主文件标识为 `8.0.0`，14 个模型，与仓库冻结 Build8V8Fixture 的模型集合相同，仅 `HabitPlanRevision` 模型 hash 不同；与 V7 fixture 也不完全相同。WAL/SHM 均存在，因此本证据只描述主文件元数据，不能冒充已完整分析当前 WAL 状态。这个历史库为何形成该 hash、是否对应任何 Owner 真机库仍 UNKNOWN/OWNER_REQUIRED；实际日志 Cocoa134504 不被抹除，不以测试库 PASS 宣称历史库已修复。

第六组诊断由 App 自己生成的日志与复制报告遵循白名单；系统 CoreData 既有控制台错误不被改写或复制进报告，也未通过抑制日志掩盖历史故障。509 个字符串键双语完整，`git diff --check` 通过。下一步补齐 R4 剩余交错/导出 cutoff、R2 大图响应、R1/R5 部分保存/取消 UI，归一 L2 后执行统一 final gate。


### 第七组进行中：R4 剩余交错、R2 九图与 R1/R5 host 边界

- `/tmp/PGOS-Closure-ExportCutoff1.xcresult` exit 0，1/1：`testExportCutoffQueuesShareAndCancelledConsumerWithoutLosingDraft` 在共享发布锁内 snapshot 后暂停；排队分享及取消的第二消费者不越过 cutoff，导出恢复仅包含 cutoff 原始 Entry/图片，释放后分享恰好导入，主草稿保留。新增可选 exportCheckpoint 仅供确定性测试，生产默认 nil。
- `/tmp/PGOS-Closure-RemainingEdges1.xcresult` 整体 exit 65；其中 `testRestoreEmptyRecheckPreservesConcurrentUserImageAndQueuedShare` 与 `testSuccessfulRestoreDoesNotRollbackDraftCreatedDuringPublication` 两项 Unit 通过：安装后二次空库检查保留并发用户 Entry/图片，恢复失败仅清自己拥有的文件；成功恢复时排队分享仅在锁释放后提交，主草稿保留。整体失败来自下述 UI，不记为整组通过。
- `/tmp/PGOS-Closure-HostStates1.xcresult` exit 65：部分保存与取消重开 UI 均失败。第二次部分确认按钮需等待真实可交互状态；保留原产品确认语义后 `/tmp/PGOS-Closure-HostStates2.xcresult` 的部分保存 UI 通过，日志确认 saveRequested → partialConfirmed → publishStarted → committed/cleaned。取消确认保留原文，明确确认才发布。该运行整体仍 exit 65，取消重开失败。
- 取消重开在 HostStates2、RemainingEdges1 及 `/tmp/PGOS-Closure-LargeCancel1.xcresult`（exit 65）均停在返回 host 后按钮不可点击。同一 host 进程 activate、Progress 完成及 completion 显式 dismiss 尚未解决；没有终止 host 来规避晚到 callback。当前新增 host 窗口/控制器诊断，责任边界未定，不能声称取消重开已通过。
- LargeCancel1 的九图选择器误用了文件名对应类，九图未执行，不构成九图证据；修正为 `ExternalCaptureTests/testNineLargeImagesKeepMainActorAvailableAndDraftIntact` 后单独运行 NineLarge1。使用真实随机 PNG、九份附件，总量 >180 MiB，校验 worker 上执行、九次 MainActor 响应与未保存草稿。`/tmp/PGOS-Closure-NineLarge1.xcresult` exit 0，1/1 实际执行通过（5.099 秒）；该结果证明异步执行与草稿边界，不代表真机峰值内存或帧率验收。
- L2 已将 Owner checklist、Known Limitations、V1 tracker、UX debt 的当前入口与历史记录明确分开，沿用 ZIP 03 的集中真机矩阵；仍待最终证据校核。当前仍 IN_PROGRESS，未执行 final gate。

取消诊断续查：`CancelDiagnostic1/2.xcresult` 均 exit 65；第二次固定字段日志 `/tmp/PGOS-CancelDiagnostic2-HostFinal.log` 证明 host 主线程收到 late-provider 与 after-share，窗口 key/visible/interaction 正常，但 `presentedViewController` 仍为 UIActivityViewController，completion 回调未触发。`ReadyCancel1.xcresult` exit 65，读取完成后取消也无法恢复 host 按钮；问题不局限于慢 provider。正在用真实 Safari 取消→再分享作 host 对照。标准取消 API 未替换成成功完成 API；参考 [Apple cancelRequest](https://developer.apple.com/documentation/foundation/nsextensioncontext/cancelrequest(witherror:))，取消与成功仍保持语义区分。

`/tmp/PGOS-Closure-SafariCancel1.xcresult` exit 65：真实 Safari 取消后 MoreMenuButton 同样不可点击；录屏 42 秒帧 `/tmp/PGOS-SafariCancel42.png` 明确显示空白系统分享面板仍在，不能归因于合成 host。已开始验证自定义扩展控制器 dismiss 完成后再调用标准 cancelRequest 的顺序修复，未改为 completeRequest，不发布取消内容。原始失败断言保留。

`CancelDismiss1.xcresult` 两项取消 UI 均失败（整体 exit 65）：先 dismiss 后 cancelRequest 未改变结果，已撤销这一无效试验及 host 临时生命周期日志/强制 dismiss；标准 cancelRequest 保留。扩展系统日志 `/tmp/PGOS-CancelDismiss-System.log` 确认 cancelRequest 已送达 ExtensionFoundation 并执行 teardown，未出现取消内容发布。下一步需继续检查系统 host 的取消收尾/空白面板，不能把正确发送取消通知等同完整用户流程通过。新取消回归断言保留，当前已知失败，尚未 final gate 或 READY。


### 第八组：取消流程的系统对照（进行中）

上一组未解决结论继续接受反证，未修改产品取消实现。`/tmp/PGOS-CancelHost-System.log` 显示系统收到 `activityDidFinish:NO`、`success=NO`，主动选择 `shouldCallCompletionHandler:NO`：取消活动不等于关闭系统分享选择器。因此直接要求 host 按钮恢复可点击的断言不能单独证明产品故障。

建立独立 `SLComposeServiceViewController` 对照，仅覆盖 `isContentValid`，取消由 Apple 默认实现执行，不调用产品 reader/metadata/取消代码。可复现构建脚本 `Scripts/build_capture_cancel_control.sh`；安装 `/tmp/PGOSCancelControlApp.app` 后与原 host 分开。首轮 StandardCancel1 因使用 extension display name 而非所属 App 名称找不到入口，exit 65，无取消证据；StandardCancel2 使用正确名称后确实取消，但直接回 host 断言仍失败（exit 65）。对照录屏 `/tmp/PGOS-StandardCancel20.png` 显示系统分享选择器仍在。

`/tmp/PGOS-Closure-PickerCancel1.xcresult` exit 0，2/2：对照与产品使用完全相同的“取消后选择器入口可点击”断言均通过，生产代码不变。这里修正的是经独立系统对照证伪的测试流程假设，不删除“不发布、可重开、无旧会话污染”的要求。进一步 CancelFlow1 正在验证实际点击重开、正常手势关闭 picker 后同 host 新分享及真实 Safari 取消再分享；旧 provider 返回后会显示完成标记，再检查无幽灵 Entry。结果未出前不将 R5 写为最终完成。

`/tmp/PGOS-Closure-CancelFlow1.xcresult` exit 0，3/3：真实 Safari 取消→系统 picker 再打开→保存→搜索刷新/来源跳转/重启；读取完成取消后实际点击重开；加载中取消→正常手势关闭系统 picker→同一个 host 新分享→旧 provider 确实返回→只出现新正文一次，旧正文不存在。旧回调返回前已开始新分享，未通过杀 host 消除迟到回调。

`/tmp/PGOS-Closure-CancelVisual1.xcresult` exit 0，2/2：Safari 与独立 host 均保留取消后 picker 截图，已人工查看，入口和内容可见、可交互。截图 `/tmp/PGOS-CancelVisual1-Attachments/EE32FF1B-2A11-4500-97DA-873201FD19F3.png` 与 `33EF63CF-D4E4-4690-AF3E-4630763DF587.png`。原“取消必然卡住 host”结论已反证：取消活动回到系统 picker，关闭 picker 是下一用户动作；原空白帧保留为历史观察，不能覆盖当前标准对照、实际重开与可见截图证据。生产 cancelRequest 未替换、未改为成功。

对照构建脚本首版缺 CFBundleDisplayName，重建成功但安装失败（exit 1），补齐后 ReproBuild2 exit 0 且安装 exit 0。脚本不会删除模拟器数据。仅移除本轮误放于 `/tmp/PGOSCaptureFixtureHost.app/PlugIns` 的生成对照副本，独立对照 App 与 host 各自安装，未删任何 App 数据。

下一步统一门禁以此组提交为候选：全量 Unit、完整 UI suite（覆盖本轮相关集成与旧功能 smoke）、unsigned generic iOS Release app/appex、project/plist/String Catalog 静态检查。未完成门禁前仍 IN_PROGRESS。
