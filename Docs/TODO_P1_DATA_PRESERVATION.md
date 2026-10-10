# Draft PR #8 — 最后一轮 P1 数据保全修复

范围：Review 基线 `8be670cd7375c0c7f0352d7749bf8a7ff3114767`；只处理正常启动的全库复制依赖与损坏恢复快照生命周期。原分支 `codex/todo-v1-personal-actions`、Draft PR #8/base `codex/external-capture-v1` 保持。无 Todo 产品增量、合并、Tag、改号、Archive 或 TestFlight。

## 启动与恢复策略

- 新库无需保护副本。当前 V11.1 库只读检查 SQLite metadata（读取 committed WAL），再用 `allowsSave=false`/禁 autosave 的 SwiftData 容器预检 Todo；正常路径不调用 Store copy。可写打开后保留 Todo 检查，再进入原媒体、Habit bootstrap 与服务路径。
- 历史/未知 metadata 在可写打开与迁移之前，必须在 Application Support 根目录的 `Recovery/BeforeMigration` 完成保护副本。复制失败停止打开，源数据库不清空、不重建、不还原；成功副本在迁移成功或失败后均保留。
- Todo 完整性失败返回启动故障页，不创建 AppShell、通知协调或正常服务写入。副本失败仍停止正常写入，保留源库和已有副本，提供脱敏副本失败 diagnostic；空间恢复后 Retry 可重试创建。
- 损坏副本保存在 `Recovery/IntegrityFailure-<SHA256>`。内容身份按排序后的 SQLite 表/行/带类型与长度的值以及外部 Store 文件计算；不依赖 SQLite header、checkpoint 布局、WAL 长度或随机 UUID。同一逻辑内容的 Retry/进程重启复用副本；实际不同的数据故障保留各自副本，不覆盖旧证据。目录摘要是本地内部标识，不作为私人内容诊断上传。
- capture/export 共用根目录内的 kernel-held lease，进程退出自然释放。SQLite writer transaction 排除并发写入，reader 保留 WAL；SHM 不进入恢复包。PASSIVE checkpoint 仍可能写主文件，因此复制前后及副本的所有原文件签名必须相等，才原子发布带 `COMPLETE` 签名清单的副本。不稳定复制失败关闭，清理未发布 staging，Retry 重新取一致副本。
- 已完成副本复用/导出前校验签名。缺失完成标记、缺文件或损坏不会覆盖、删除或静默重建已有副本。
- raw ZIP 只含冻结 Store、现有原文件与 `RECOVERY.txt`，明确 NOT a v7 import package；不把 Recovery 树、其他快照或此前 ZIP 递归塞进新包。ZIP 使用固定未完成文件，完成后原子替换；I/O、ENOSPC、取消失败只删 partial，保留旧成功 ZIP、数据库副本和源库。
- 创建 ZIP、出现 ShareLink、关闭分享面板，都不能证明用户已安全保存到外部位置。**不自动清理任何已发布重要副本**。仅未完成 staging/partial 自动清理。支持人员/Owner 若要人工清理，必须先独立保存并验证外部 raw ZIP 可读、SQLite/WAL/原文件可恢复，确认仍有安全副本；本轮没有增加删除入口或调用唯一副本 cleanup。

## 可复现环境与证据

本机 macOS 27.0.1 / Xcode 27.0 (27A266a)，iPhone 18 Pro / iOS 27.0 Simulator (24A434)，UDID `FD666264-A2DF-445C-A77D-534B9E8ED595`。仅合成库、冻结原 Build12 fixture；没有访问 Owner 私人库。日志与 xcresult：`/tmp/pgos-p1-evidence/`。

| Run | 实际结果 |
| --- | --- |
| s0-red | exit65，新增测试构造参数错误，测试 NOT_RUN；已纠正。 |
| s0-red-2 | exit65，0/2 PASS。健康库 copy EIO 阻断；快照临时目录及每次新路径失败。 |
| s0-red-3 | exit65，0/1 PASS。test-results tests 保留 EIO(5) 与 ENOSPC(28) 两个真实 failure message。S0 低空间是受控 copy 边界 ENOSPC，物理测试卷见 S2。 |
| s1-target | exit65，2/3 PASS；损坏路径读锁顺序遇 SQLITE_BUSY。 |
| s1-target-2 / s1-target-3 | exit65，各2/3 PASS；原字节强断言失败，未改标全绿。当前 schema 增加只读预检；测试 fixture 用只读 reader 固定 WAL 并 busy-wait，排除此前测试写容器退出与取原始证据重叠，数据库/媒体字节相等强断言保留。 |
| s1-bytes / s1-bytes-2 | 前者exit65、后者exit0，0/1与1/1；用于原字节定位，失败保留。 |
| s2-target | exit65，4/6 PASS；fixture reader SQLITE_BUSY 与 raw preview 的未创建媒体根目录容量读取失败；补 busy timeout，raw 验证用明确容量输入。 |
| s2-target-2 | exit65，Int/Int32 optional 比较编译错误，测试 NOT_RUN。 |
| s2-target-3 | exit0，7/7 Unit PASS，0 SKIP，runtimeWarnings=[]。EIO/ENOSPC、V10复制前阻断、WAL恢复、并发writer拒绝、5次启动故障复用、导出失败、物理低空间卷均通过。 |
| s2-wal-final | exit0，5/5 Unit PASS，0 SKIP，runtimeWarnings=[]。真实 PASSIVE checkpoint race 拒绝/Retry成功、不同故障旧副本不丢、缺marker不覆盖、raw ZIP正负与低空间复验。 |
| s3-integration | exit0，2 Unit + 4 UI = 6/6 PASS，0 SKIP，runtimeWarnings=[]。原Build12通过真实AppContainer迁移/重开、恢复页3次Retry/重启重导、Todo五Tab、分享与Files恢复通过。 |

公共测试命令（run 为表中名称，only 为具体选择；每轮日志与结果独立）：

```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-p1-evidence/<run>.xcresult <only-testing selectors> > /tmp/pgos-p1-evidence/<run>.log 2>&1
xcrun xcresulttool get test-results summary --path /tmp/pgos-p1-evidence/<run>.xcresult
xcrun xcresulttool get test-results tests --path /tmp/pgos-p1-evidence/s0-red-3.xcresult
```

具体选择（Unit 前缀 `PersonalGrowthOSTests/TodoFoundationTests/`；UI 前缀 `PersonalGrowthOSUITests/AppLaunchSmokeTests/`）：

- S0-red/red-2：`testHealthyStartupDoesNotRequireCopyUnderIOErrorOrNoSpace`、`testRecoveryCaptureReusesDurableSnapshotAcrossRetryAndRestart`；red-3 仅前者。
- S1-target/2/3：上面2项 + `testTodoIntegrityFailureOffersRawByteRecoveryAndDoesNotReconcileMedia`；bytes/2 仅第三项。
- S2-target/2/3：S1 3项 + `testMigrationCopyFailureStopsBeforeOpeningOriginalV10`、`testRecoveryWALBytesAreConsistentAndConcurrentWriterIsExcluded`、`testCorruptStartupRetryRestartTempPurgeAndExportFailurePreserveOnlySnapshot`；target-2/3另加 `testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure`。
- S2-wal-final：`testPassiveCheckpointRaceIsRejectedAndRetryCapturesConsistentRawFiles`、`testDifferentFailurePreservesEarlierSnapshotAndIncompleteSnapshotIsNeverOverwritten`、上述corrupt/low-space/WAL三项。
- S3-integration：Unit `testExactBuild12V10FixtureMigratesAndReopensPreservingAllOldFactsAndMedia`（已贯通 AppContainer：首次保留原V10字节、第二次注入copy失败但正常启动，完整原对象/媒体/v6转v7/重开断言）、上述corrupt生命周期；UI `testTodoIntegrityFailureRetainsDataAndOffersDiagnosticAndRawExport`（3次Retry、terminate/relaunch、重启后再导出）、`testTodoQuickContinuousInputCompletionStatisticsSearchAndRestart`、`testPublicMixedProviderHostShowsExtensionAndImports`、`testPR6FilesPreviewCancelAndRestore`。

物理低空间卷命令（新空路径；已存在时不要覆盖测试 image）：

```sh
hdiutil create -size 32m -fs HFS+ -volname PGOS_P1_LowSpace /tmp/pgos-p1-evidence/low-space.dmg
mkdir -p /tmp/pgos-p1-low-space
hdiutil attach /tmp/pgos-p1-evidence/low-space.dmg -mountpoint /tmp/pgos-p1-low-space -nobrowse
touch /tmp/pgos-p1-low-space/RUN_LOW_SPACE_TEST
```

低空间测试在该HFS+卷先创建健康/历史/损坏合成库与各4MiB不可clone字节，再用本次拥有的 filler 把空间压到1.5MB以内。真实 `copyItem(Store)` 断言 ENOSPC；健康库仍打开并新增保存第二条Entry；V10不能迁移且原SQLite字节相等；损坏库没有正常写入、snapshotFailure=capacity；删除本次filler后Retry仍拒绝损坏Todo但可建恢复副本。所有filler/库在test defer清理；不压满主磁盘。无测试卷marker时只有该测试显式SKIP，不能声称真实低空间通过。

S2临时清理测试将副本实际放到 Simulator App 的 Application Support，并创建/删除真正 temporaryDirectory 中本测试拥有的导出文件夹；副本继续存在。进程重启另由真实UI terminate/relaunch验证。没有删除任何不属于测试的临时文件或系统/私人数据。

SQLite锁与checkpoint依据：[SQLite WAL](https://www.sqlite.org/wal.html)、[连接关闭checkpoint选项](https://www.sqlite.org/c3ref/c_dbconfig_defensive.html)。正常可写打开使用SQLite原有事务恢复；没有repair、reset、重建、导入替换私人库。

## 最终候选与未执行边界

S3通过，最终候选门禁尚未收口，当前不标READY。最终只执行一次候选完整Unit、真实Debug/unsignedRelease与必要UI；不按阶段重复全量。最终固定候选、counts、普通push/PR head核查完成后更新本节与两个current-context文档。

Owner私人Build12覆盖安装、真机签名/AppGroup/通知、真实设备系统清理/VoiceOver、实际Xcode Cloud/Archive/TestFlight均NOT_RUN/OWNER_DEVICE_GATE。模拟器通过不能替代这些门禁。远端CI以实际workflow/check/status核查为准；本轮不新增或主动触发发行CI。不同内容的重要故障副本会累计保留，占用空间是保全策略的明确代价；没有将分享完成误判为安全外部导出。
