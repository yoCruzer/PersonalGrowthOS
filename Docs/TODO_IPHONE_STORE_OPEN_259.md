# Todo V1 首次真实 iPhone storeOpen 259 — 合成复现与诊断修复报告

日期：2026-10-10。事故 Review HEAD：`dc4bacc930f9490128896c4e6b66d67540a074ac`；Owner 报告原安装为 TestFlight Build 12 / `c5a3c0ac8`，无线 Run 安装成功后显示 `stage=storeOpen / NSCocoaErrorDomain / 259`。本报告不含私人正文、图片、数据库或私人内容摘要。

## S0 已核实与未核实

- `git rev-parse HEAD` 为上述完整 SHA，`git status --short --branch` 显示原分支 `codex/todo-v1-personal-actions`、工作区干净（记录前）。
- 只读 `plutil -p` 检查本机 DerivedData 的 `Build/Products/Debug-iphoneos/PersonalGrowthOS.app/BuildProvenance.plist`：Commit 为上述 SHA，Source=localGit，Dirty=true，Tag 空。该资源修改时间为 2026-10-10 18:59:36 +0800。这证明现存本机产物的溯源字段，不能独立证明已安装二进制身份，也不能保证构建时没有未提交差异。
- 本机 `xcodebuild -version`：Xcode 27.0 / 27A266a。
- Owner 确认升级前已手动导出 ZIP，仍在 iPhone；本机路径与可读性未核实。Owner 表示失败状态的完整 `.xcappdata` 没有下载和复制，可能已清除；没有把“可能”记成确定删除。
- **Owner 完整 App Data Container 下载与独立备份尚未确认，路径尚未提供。S0 未完成。** 不得重新 Run、Retry、安装、迁移、重置、替换容器或修改真实设备数据。

Owner 保全步骤：停止调试并关闭 App，通过 Xcode 设备管理窗口选择该 iPhone 与 PersonalGrowthOS，使用 Download Container 保存完整 `.xcappdata`；再复制整个容器到独立位置，最好外置磁盘。保留下载原件、独立备份与第三份工作副本。不要只复制 SQLite；WAL、媒体与 Recovery 一并保留。不要上传私人容器。以上门禁仍适用于真实数据；Owner 随后明确授权“现在以无法获取失败现场继续推进”。据此仅使用仓库合成 fixture 与新建临时库继续 S1–S4，不要求先获取私人库，也不视为真机安装或恢复授权。

## S1 只读代码审查的边界

SDK `FoundationErrors.h` 定义 `NSFileReadCorruptFileError = 259`。该错误码并不单独证明 SQLite 损坏。

`AppContainer.make` 在创建 Store 目录后将 stage 设为 storeOpen，直到可写 ModelContainer 创建成功才改为 integrity。因此至少存在以下不同错误路径：

1. `StartupStoreProtection.isCurrentStore` 读 SQLite `Z_METADATA.Z_PLIST`，检查版本标识是否为 11.1.0；失败返回 false，不抛出 259。false 分支进入 `StartupRetainedData.capture(...beforeMigration)`。
2. `capture` 的 `storeSignature` 在源 Store 或已有保护副本中找不到主 SQLite 文件时显式抛出 `CocoaError(.fileReadCorruptFile)`。已有 `Recovery/BeforeMigration` 的 Store 文件签名与 COMPLETE 清单不一致时，同样显式抛出 259。该分支发生在 SwiftData 可写打开之前，不能归因为迁移失败。
3. 当前版本分支的只读 `PersistenceContainerFactory.makeOnDisk(...allowsSave:false)` 与后续可写 `makeOnDisk` 均调用 SwiftData `ModelContainer`；框架错误也会在 storeOpen 阶段传出。现有 diagnostic 没有记录具体调用点或完整底层错误链。
4. `fingerprint` 的 SQLite 打开/查询失败也显式抛出 259，但只用于 integrityFailure 快照，不属于 beforeMigration 的身份计算。不能把该路径直接当作本次首次升级根因。

迁移计划为 V10 → 冻结原 V11 11.0.0 → V11.1 11.1.0，两段 lightweight；只读审查未修改 Schema 或迁移计划。事故基线 `SharedCapture/ShareInbox.swift` 的 report 固定输出 `storeSchema=10 captureSchema=1 backupSchema=6`，这些字段不是实际持久化版本证据。

**本次实际抛出 259 的函数与分支尚未确定。** 原现场不可获取时，无法反向确定当时 Store/WAL、metadata 与 COMPLETE 状态；本轮用独立合成正负实验缩小范围。不能将候选路径、旧合成 fixture 通过或代码推测写成真实根因。

## S2 独立合成证据

- checked-in Build12V10Fixture 来自 `c5a3c0ac859efc3ffa4e5d9f77909ec43565c871` 的精确产品源码，但生成环境为 Xcode 27 / iOS 27 Simulator。它是同源合成 fixture，不是手机 TestFlight Build12 的真实数据库；不能替代不同 SDK/系统生成的实际 model hash。
- 两份已 checkpoint 合成库复制到 `/tmp/pgos-259-evidence/checkpointed-fixtures-ee8if27x/`，使用 SQLite `mode=ro&immutable=1` 检查。只有确认源 fixture 无 WAL 后才使用 immutable；含 WAL 的测试使用普通 SQLite read-only 连接，绝不忽略 WAL。
- `PRAGMA integrity_check` 均为 ok；Z_METADATA 持久化 versionIdentifiers 分别为 `[10.0.0]`、`[11.0.0]`；entity model hashes 已存本机 technical-metadata.json。检查前后主文件 SHA 相同。所有输入仅合成，无私人正文/图片/数据库。
- 新 WAL 测试保持原 V10 主文件不变，通过 UPDATE 在 WAL 中提交合成 Entry 正文；复制前后源 main/WAL 与保护 main/WAL 均字节相等。独立只读打开保护副本读出 WAL 事实；关闭并重复 capture，再升级，Entry 和所有原图片字节保留。
- 早期 Python 对新复制 WAL-mode 主文件直接 mode=ro 打开失败，未检查成功、未将它当坏库证据；后续只对明确 checkpoint 的副本用 immutable 检查。Xcode/xcresulttool 首次受 sandbox 服务/缓存权限限制；经限定的本机模拟器与结果读取授权后运行，未涉及真实设备。

## S3 已复现路径与最小修复

`testInvalidBeforeMigrationSnapshotProduces259BeforeSwiftDataAndPreservesSource` 使用同源 V10 合成库先建立完整保护副本，然后仅损坏本测试副本的 SQLite 字节。三次 AppContainer.make 均在 `StartupRetainedData.capture` 的已有 snapshot 签名比对处抛出 Cocoa 259，stage=storeOpen；源主文件、损坏副本均不变，源仍为旧版本。**这是保护校验失败的候选原因，不是迁移器抛错，也不是原手机根因已证实。** 当前没有依据修改或绕过该保护行为。

另一个独立负向实验将合成 V10 的 Z_PLIST 改为非法 plist。其 SQLite 文件仍可读取与复制，但 SwiftData ModelContainer 返回 `SwiftDataError`，诊断 allowlist 不收录其未知 domain/code。首轮误设 Cocoa259 预期而失败；按实际类型修正测试，保留原字节与保护副本断言，不能把该实验说成第二条 Cocoa259 复现。

已确认并修复的是两处诊断缺陷：

1. 原报告将保护校验、复制、只读打开、可写打开统一标为 storeOpen，无法定位函数。新增可选固定枚举 startupStep：snapshotValidation / preMigrationProtection / storeReadOnlyOpen / storeWritableOpen；已有副本校验错误包装保留原始 error，AppContainer 不再丢弃其具体定位；恢复页副本失败也保留该定位。
2. 原报告硬编码 Schema。diagnostic v2 删除固定 Schema 值，输出 `schemaEvidence=notCollected`，不冒充实际数据库版本。新增字段为 optional，旧已保存 diagnostic JSON 缺字段仍可解码。报告仅固定枚举、既有 allowlist 数字信息，不输出 localizedDescription、SQL、路径或私人字段；原隐私负向与 JSON 往返断言保留。

没有 startup 修复被证实必要：未改 Schema/MigrationPlan、模型、数据库文件、恢复副本布局、签名算法、媒体清理、Todo 规则或校验条件；无清库、删除已完成 Recovery、副本替换、绕过迁移或放宽完整性检查。**诊断修复不承诺使存在真实损坏的库自动启动。**

## S4 实际验证与失败审计

环境 macOS 27.0.1 / Xcode27.0(27A266a)；iPhone18Pro / iOS27.0(24A434) Simulator，UDID `FD666264-A2DF-445C-A77D-534B9E8ED595`。证据根目录 `/tmp/pgos-259-evidence`。

| Run | 实际结果 |
| --- | --- |
| baseline | exit0，2/2：Build12同源V10完整对象/媒体/v7与重开、原V11迁移。 |
| wal-and-259 | exit0，2/2：新V10 committed WAL与已有保护副本259路径；尚未修改产品。 |
| diagnostic-red | exit65，0/1：snapshotValidation定位断言失败。诊断Schema测试 selector 错用 PersistenceMediaFoundationTests，实际类为 ExternalCaptureTests，该项 NOT_RUN。未把缺测计入通过。 |
| diagnostic-green | exit0，3/3：snapshot定位/WAL/旧损坏副本不覆盖；同一错误 selector 的Schema单项 NOT_RUN，随后 full-unit 和 corrected 用正确类实际覆盖。 |
| full-unit | exit0，306 PASS / 0 FAIL / 1 SKIP，总307；runtimeWarnings=[]。物理32MB低空间卷测试缺marker而SKIP。 |
| startup-ui | exit0，2/2：启动诊断复制、安全重试保留Entry、损坏库Retry/重启/raw导出。runtimeWarnings=[]。 |
| release | exit0，unsigned Simulator Release App/ShareExtension build。无Archive/TestFlight。 |
| metadata-259 | exit65，1/2：诊断兼容通过，metadata故障的Cocoa259假设失败；实际SwiftDataError，字节/定位断言通过。 |
| metadata-negative-corrected | exit0，2/2：实际SwiftDataError与字节保留、诊断安全/新旧JSON兼容。runtimeWarnings=[]。 |
| final-unit | exit0，307 PASS / 0 FAIL / 1 SKIP，总308；runtimeWarnings=[]。新增metadata负向测试加入后重跑；同一物理低空间测试SKIP。 |

共同实际命令模板（每次独立日志与xcresult；selector 见上表与下方）：

```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-259-evidence/<run>.xcresult <only-testing selectors> > /tmp/pgos-259-evidence/<run>.log 2>&1
xcrun xcresulttool get test-results summary --path /tmp/pgos-259-evidence/<run>.xcresult
xcodebuild build -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pgos-259-release-derived CODE_SIGNING_ALLOWED=NO > /tmp/pgos-259-evidence/release.log 2>&1
```

Unit selector 前缀 `PersonalGrowthOSTests/TodoFoundationTests/`：baseline 使用原 `testExactBuild12V10FixtureMigratesAndReopensPreservingAllOldFactsAndMedia` 与 `testOriginalV11CandidateMigratesWithoutLosingTaskEventBytesAndInfersReminderLead`；新测试 `testBuild12CommittedWALProtectionRetryAndMigrationPreserveEntryAndMedia`、`testInvalidBeforeMigrationSnapshotProduces259BeforeSwiftDataAndPreservesSource`、`testCorruptV10MetadataIsDistinguishedFromInvalidProtectionAndRetainsBytes`。green另含 `testDifferentFailurePreservesEarlierSnapshotAndIncompleteSnapshotIsNeverOverwritten`。metadata轮另选正确的 `PersonalGrowthOSTests/ExternalCaptureTests/testDiagnosticsUseOnlyAllowlistedFieldsAndDistinguishFailures`。完整Unit选择 `-only-testing:PersonalGrowthOSTests`。UI前缀 `PersonalGrowthOSUITests/AppLaunchSmokeTests/`，选择 `testTodoIntegrityFailureRetainsDataAndOffersDiagnosticAndRawExport` 与 `testStartupDiagnosticCopiesAndSafeRetryPreservesExistingEntry`。

完整Unit覆盖既有v7合法旧包/非法包、导出/恢复/取消/并发/回滚、Build12同源V10/原V11、原Entry与媒体、Todo/提醒/正常启动；不称全量UI通过。物理低空间卷未重新挂载（该项SKIP）；本轮未修改复制容量策略，不复用旧物理测试冒称新通过。

## 交接与仍未证明的事项

本轮代码/合成验证可供原 Draft PR #8 独立审查；**原手机实际根因 UNKNOWN，启动恢复未验证，事故不标已解决。** 无现场条件下已有证据不足以安全决定迁移或数据修复；未来若Owner提供ZIP可在隔离副本核对数据，但不等于重获失败SQLite现场。

真实私人库、原ZIP检查、真机再安装/恢复、真机数据保留验证均 NOT_RUN。远端 `gh api repos/yoCruzer/PersonalGrowthOS/actions/workflows` total_count=0，独立CI NOT_RUN，不把空checks当通过。只普通推送原 `codex/todo-v1-personal-actions` / OPEN Draft PR #8，base `codex/external-capture-v1`；不合并、改Ready状态、打Tag、改发行号、触发TestFlight。最终推送与候选一致性另记录。独立审查仅对本轮诊断变更与合成证据成立，不作为手机重装授权。
