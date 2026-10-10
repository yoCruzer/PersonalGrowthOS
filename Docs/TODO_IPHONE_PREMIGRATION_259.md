# Build 16 preMigrationProtection / Cocoa259 — 路径别名修复

日期：2026-10-10。审查基线 `fb830a1d555b9738d15867546d395239d38e1edc`；原分支 `codex/todo-v1-personal-actions`、原 OPEN Draft PR #8、base `codex/external-capture-v1` 保持。本轮只处理与新诊断相匹配的保护阶段路径缺陷及细粒度诊断。

## S0 数据与构建边界

Owner 报告本地 Xcode Run Build16：stage=storeOpen、startupStep=preMigrationProtection、NSCocoaErrorDomain/259、schemaEvidence=notCollected。只读核对本机现存 Debug-iphoneos App：1.0(16)、内嵌 SHA=上述基线、Source=localGit、Dirty=true、Tag空；不能据此独立证明已安装二进制身份或构建时无未提交差异。仓库/PR起点 SHA 相同且工作区干净，仓库发行设置仍为1.0(7)，本轮不改号。

Owner 本轮明确回复“尚未下载／独立备份；继续合成测试”。没有完整 `.xcappdata` 副本，也无读取私人副本授权。本轮没有连接或操作真实 iPhone，没有 Run/安装/Retry/迁移/重置/恢复私人数据，没有读取升级前私人ZIP，没有上传私人正文、照片、路径或数据库。真实设备任何后续操作仍须先保全并另获授权。

## S1 259 路径清单与排除

| 位置 | 可能错误与新定位 |
| --- | --- |
| capture 建 Recovery、获取 lease | FileManager/锁的原生错误；新 protectionStep=recoveryDirectory/protectionLock。没有在这里主动构造259。 |
| withFrozenStore | SQLite open/BEGIN/SELECT 失败主动抛 `SQLite` domain 数字错误，不是 Cocoa259；readerOpen/writerOpen/writerTransaction/readerTransaction。闭包抛错可透传。 |
| 初次 storeSignature(source Store) | 枚举失败为 fileReadUnknown；resourceValues/FileHandle 原生读错误可透传；**找不到相对键 PersonalGrowthOS.sqlite 时主动抛 Cocoa259**。新 protectionStep=sourceSignature。 |
| 已有 BeforeMigration 读取 COMPLETE、校验 Store | 原生读取/解码错误或签名不一致259，但已有专门 startupStep=snapshotValidation；与此次 preMigrationProtection 不同，不能沿用上轮根因。 |
| staging/copyItem/SHM清理 | FileManager 原生错误，包括可能的读错误；新 stagingCleanup/stagingDirectory/storeCopy/copiedSHMCleanup。注入copy Cocoa259也会产生同样旧阶段，证明旧字段不足唯一归因。 |
| 复制后的源/副本签名 | 内部 storeSignature 的主库缺失仍可259；两份签名不等主动抛 fileReadUnknown，不是259；新 sourceSignatureRecheck/copiedSignature。 |
| COMPLETE 写入与原子发布 | 原生I/O错误；新 completeWrite/snapshotPublication。不会把失败副本发布成完成副本。 |

fingerprint 只在 integrityFailure 身份计算中使用，beforeMigration 不调用；其显式259不是本次已报告路径。raw archive 自己的副本校验也不在 AppContainer 首次保护调用路径。SwiftData 只读或可写打开分别有 storeReadOnlyOpen/storeWritableOpen，当前诊断尚未到这些步骤。schemaEvidence=notCollected 保持，不将任何硬编码字段当实际持久化版本证据。

## S2–S3 已证明的缺陷与最小修复

Foundation 文件枚举会把传入目录的祖先路径别名解析成物理路径。旧 storeSignature 用传入 directory.path 的字符长度直接截断返回的 url.path，假定两者前缀完全相同。容器根经过系统 `/var` 与 `/private/var` 别名，或不同长度的合成目录链接时，该假定不成立：实际主库存在且健康，却被登记为错误的相对键；末尾“必须有 PersonalGrowthOS.sqlite”检查误抛 Cocoa259。

新测试使用同源Build12V10 fixture，仅创建合成容器祖先别名；不损坏数据库或已有保护副本。基线红测明确得到 **storeOpen / preMigrationProtection / Cocoa259**，源库字节不变；失败发生在初次源签名、创建完整 BeforeMigration 之前。这与Owner的新字段一致，区别于上轮人为损坏已有快照的snapshotValidation。**已确认这是代码缺陷；没有私人现场证据证明Owner设备一定触发了它。**

修复：

- AppContainer 在建立运行目录之前统一根URL为 `standardizedFileURL.resolvingSymlinksInPath()`，媒体与后续服务使用相同物理根，仍访问同一容器与文件。
- storeSignature 对根与枚举文件使用完全相同的规范化流程，先验证原始文件类型/拒绝内部符号链接，再校验目录边界并计算相对名。祖先容器别名可以使用，内部链接不能作为数据文件被跟随。
- raw archive 中同样的截断缺陷一起修正，保证ZIP的Store/Media相对名正确，仍排除Recovery树与旧导出，不把raw包变为普通v7包。
- 新增可选固定枚举 protectionStep，标识保护过程的具体调用阶段；包装保留原始error和已有startupStep。没有输出路径、文件名、SQL、localizedDescription、内容hash或正文。旧v1/v2已保存JSON缺新增字段仍可解码，现有allowlist不扩张。

首次路径修复通过保护后在媒体恢复失败，证明只修签名不足；统一App运行根后完整对象/媒体/导出/重开通过。首次物理HFS+全量回归还发现规范化顺序不一致：root和child会分别呈现`/tmp`与`/private/tmp`。最终统一根/子URL的流程；没有靠去掉边界检查让测试通过。

没有改变Schema、MigrationPlan、模型、历史fixture、发行号、AppGroup或签名。未删除已完成保护副本、未清库、未跳过迁移、未减少签名范围、未放宽数据完整性校验。原“缺主库/损坏副本必须拒绝”保持；临时失败仍只清未发布staging。若现场本来已经损坏，本修复不会自动修复或替换其数据。

## S4 验证与失败记录

环境：macOS27.0.1 / Xcode27.0(27A266a)；iPhone18Pro / iOS27.0(24A434) Simulator，UDID `FD666264-A2DF-445C-A77D-534B9E8ED595`。全部输入为仓库同源合成库或新临时测试文件，证据在 `/tmp/pgos-pre-migration-evidence`，没有私人数据。

| Run | 实际结果 |
| --- | --- |
| alias-red | exit65，0/1；fixture父目录未建立，未到达目标路径，不能用作259证据。 |
| alias-red-2 | exit65，0/1；完整目标诊断preMigrationProtection/Cocoa259，源字节不变，首次源签名误判缺主库。 |
| alias-green | exit65，2/3；保护已通过，但alias完整启动在mediaRecovery失败；未改标全绿。 |
| targeted | exit0，7/7，0SKIP、runtimeWarnings=[]。V10alias完整升级/v7/媒体/重开；raw路径/内部symlink拒绝；copy Cocoa259阻断/重试；EIO/ENOSPC；WAL；旧坏副本snapshotValidation；新旧JSON与隐私。 |
| final-unit | exit65，310/311，0SKIP、runtimeWarnings=[]；HFS+路径边界差异让低空间snapshotFailure误报store。 |
| capacity-detail | exit65，0/1；固定诊断protectionStep=sourceSignature，定位规范化流程差异。 |
| canonical-volume | exit0，3/3、0SKIP、runtimeWarnings=[]；HFS+真实低空间、alias完整升级、raw及symlink安全通过。 |
| final-unit-2 | exit0，**311/311 Unit PASS，0FAIL/SKIP、runtimeWarnings=[]**。修正跨卷规范化后最终完整门禁。 |
| release | exit0，unsigned Simulator Release App/唯一ShareExtension build。 |
| startup-ui | 2/2 PASS，0 FAIL/SKIP，runtimeWarnings=[]；完整性失败保全/raw导出与诊断、安全Retry保留Entry。 |

新增3项测试：

- `TodoFoundationTests/testBuild12V10ContainerAliasMigratesWithoutFalseMissingStore259`：文件枚举返回物理路径的独立前提断言；alias首次打开、物理根重开；BeforeMigration原主库字节、整个TransferData与原v6 expected精确相等、每张图片字节相等、Todo/Link完整性。
- `TodoFoundationTests/testAliasedProtectionRawArchiveKeepsNamesAndRejectsInternalSymlinks`：直接alias capture与跨别名复用、raw ZIP提取后主库/媒体字节及目录名正确，不含Recovery；source内部symlink和raw媒体symlink分别拒绝，重要副本保留。
- `TodoFoundationTests/testCocoa259DuringCopyIsLocatedAndDoesNotMigrateOrPublish`：仅注入原生copy错误，固定protectionStep=storeCopy；原主库字节不变、仍V10、无已发布/未完成副本，恢复正常复制后可升级，保护原字节保留；诊断不含测试私密标记。

完整Unit还涵盖原V10/原V11、V7/V8、v7旧包/坏包/取消/并发/回滚、Entry/媒体、WAL恢复、checkpoint竞态、故障Retry和正常启动。不用同源fixture冒称已验证Owner真实TestFlight库或其SDK生成的hash。物理低空间用本轮新32MB HFS+ image，始终只填该卷，未压满主磁盘；测试结束后卸载，image与日志保留。

实际命令：

```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-pre-migration-evidence/<run>.xcresult <only-testing selectors> > /tmp/pgos-pre-migration-evidence/<run>.log 2>&1
xcrun xcresulttool get test-results summary --path /tmp/pgos-pre-migration-evidence/<run>.xcresult
xcodebuild build -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pgos-pre-migration-release-derived CODE_SIGNING_ALLOWED=NO > /tmp/pgos-pre-migration-evidence/release.log 2>&1
hdiutil create -size 32m -fs HFS+ -volname PGOS_PreMigration_Test /tmp/pgos-pre-migration-evidence/low-space.dmg
hdiutil attach /tmp/pgos-pre-migration-evidence/low-space.dmg -mountpoint /tmp/pgos-p1-low-space -nobrowse
touch /tmp/pgos-p1-low-space/RUN_LOW_SPACE_TEST
hdiutil detach /tmp/pgos-p1-low-space
```

Selectors：alias-red/red-2只选新增alias测试；alias-green选alias、原committedWAL和原snapshot259；targeted选上方3新增 + `testMigrationCopyFailureStopsBeforeOpeningOriginalV10`、`testInvalidBeforeMigrationSnapshotProduces259BeforeSwiftDataAndPreservesSource`、`testBuild12CommittedWALProtectionRetryAndMigrationPreserveEntryAndMedia` 与 `ExternalCaptureTests/testDiagnosticsUseOnlyAllowlistedFieldsAndDistinguishFailures`；canonical-volume选alias/raw加 `testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure`。Unit前缀 `PersonalGrowthOSTests/`；full选 `-only-testing:PersonalGrowthOSTests`。UI前缀 `PersonalGrowthOSUITests/AppLaunchSmokeTests/`，选 `testTodoIntegrityFailureRetainsDataAndOffersDiagnosticAndRawExport`、`testStartupDiagnosticCopiesAndSafeRetryPreservesExistingEntry`。

## 交接与剩余风险

本轮可复现路径缺陷已修复；Owner真机具体归因和修复后成功启动仍未验证。preMigrationProtection/Cocoa259还可能来自原生源文件读取/复制错误，细粒度diagnostic用于将来进一步区分，不能自动把所有259认作路径别名。真实私人Container、ZIP、真机安装/升级/通知/AppGroup等均NOT_RUN。未经完整备份确认与明确授权，不能把本报告当再次Run许可。

原PR仍OPEN Draft；普通推送同一分支，最终候选以git/PR HEAD一致性为准。远端workflows=0，独立CI NOT_RUN，不把空checks当通过。**READY_FOR_INDEPENDENT_REVIEW**：停止实现，仅交接独立审查与Owner保全后的设备门禁，不merge、改Ready状态、打Tag、改号或触发TestFlight。
