# 真实 Build 12 同源 fixture

本合成库由 `git archive c5a3c0ac859efc3ffa4e5d9f77909ec43565c871` 的精确源码生成；没有复制 Owner 库或修改历史 schema。使用 Xcode 27 / iOS 27 Simulator。生成测试只追加在临时归档的 `PersonalGrowthOSTests/PersistenceMediaFoundationTests.swift` 末尾，工程与产品源码保持基线。

复现：把该 commit 归档到新的临时目录，将 `CreateBuild12V10Fixture.swift` 追加至上述测试文件；对共享 scheme 仅执行 `PersonalGrowthOSTests/Build12FixtureGenerationTests`。生成目录为 `/tmp/pgos-todo-evidence/Build12V10Fixture`，仅用于本流程的合成数据，复跑应使用空的同名合成目录。测试生成 V10 sqlite、原始图片、v6 备份和来源文件。进程关闭后复制 sqlite/Media/expected-v6.zip/SOURCE.txt；无需 WAL（已 checkpoint，长度为 0）或 SHM。

迁移验收把资源复制到临时目录，在新 V11 容器打开、重开、完整导出并逐字段与原 v6 数据比较；另外验证媒体字节和分享 receipt。现有真实 V7/V8 fixture 保持原样。

## 原 Todo 候选 V11 fixture

`OriginalV11Fixture` 由本轮起点 `4625602b27d8b4e4df4f6da20b7f11bf30b21d8c` 的产品源码生成。生成时只追加 `CreateOriginalV11Fixture.swift` 中的测试至同一 TodoFoundationTests.swift（私有date helper可用），定向运行 `testGenerateOriginalV11CandidateFixture`；实际本轮在任何产品改动前的 s1-red 中生成成功。重现应先将该HEAD用git archive读出到新的临时目录，生成路径改为新空合成目录，禁止覆盖checked-in fixture。退出进程、确认WAL=0后复制store.sqlite/task-id.txt/SOURCE.txt，未复制SHM。数据只有合成月重复、提醒提前一日和完成/后继，没有Owner内容。

原V11 11.0.0模型节点在新代码中冻结；11.1.0只给候选TodoSeries增添可选reminderDayOffset。`testOriginalV11CandidateMigratesWithoutLosingTaskEventBytesAndInfersReminderLead`复制资源后打开/重开、核对原事件传输bytes、后继生成提前一日。旧V10/V7/V8资源不改写。

## 重要日子固定产品基线 V11.1 fixture

`ImportantDayBaselineV11Fixture` 从精确 `20d315a62179ad29a6cbcf76c33c11638412e54e` 的 `git archive` 生成，仅向归档的 PersistenceMediaFoundationTests.swift 追加 `CreateImportantDayBaselineFixture.swift`。Xcode27/iOS27专用合成模拟器定向1/1通过。进程结束后WAL=0，仅复制sqlite、Media、expected-v7.zip、SOURCE.txt，不复制SHM。包含各旧模块、Entry图片/来源/收据、月重复Todo和完成后继；不含私人数据。新测试通过直接磁盘覆盖/重开与独立v7导入比较全部支持事实，并分别断言本地收据保留、备份恢复不含收据的已接受边界。

## 同步接入前固定 V16/v12 合成基线 — 2026-11-07

`CreateSyncV16BaselineFixture.swift` 只追加至 `git archive 96f72339a1a3082c43018e06d6115dd93df1df97` 中的 PersistenceMediaFoundationTests.swift，产品源码保持精确基线。新运行先将脚本output改为从未存在的新临时目录，再执行 `PersonalGrowthOSTests/SyncV16BaselineFixtureGenerationTests`。禁止覆盖已有fixture或直接打开冻结数据库。

固定产物与sha256清单位于 `Docs/Evidence/iCloudSyncFoundation/20261107/baseline-v16/`及同级清单，保留SQLite+非空WAL+原图+实际v12ZIP。验证磁盘副本重开、完整TransferSnapshot/原图等值、两份分享防重收据（含已删除来源）、净资产整数分与未完成草稿。原失败、独立验证脚本及命令见同目录README；不宣称已经完成V16→Sync schema迁移。

`MeasureSyncV16Payload.swift` 则仅追加到同基线NetWorthTests.swift，以实际领域validator和JSONEncoder测量合法万行Unicode快照；不打开数据库。输出必须为新目录，容量证据与原始尝试见本轮证据目录。
