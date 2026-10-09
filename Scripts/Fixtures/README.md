# 真实 Build 12 同源 fixture

本合成库由 `git archive c5a3c0ac859efc3ffa4e5d9f77909ec43565c871` 的精确源码生成；没有复制 Owner 库或修改历史 schema。使用 Xcode 27 / iOS 27 Simulator。生成测试只追加在临时归档的 `PersonalGrowthOSTests/PersistenceMediaFoundationTests.swift` 末尾，工程与产品源码保持基线。

复现：把该 commit 归档到新的临时目录，将 `CreateBuild12V10Fixture.swift` 追加至上述测试文件；对共享 scheme 仅执行 `PersonalGrowthOSTests/Build12FixtureGenerationTests`。生成目录为 `/tmp/pgos-todo-evidence/Build12V10Fixture`，仅用于本流程的合成数据，复跑应使用空的同名合成目录。测试生成 V10 sqlite、原始图片、v6 备份和来源文件。进程关闭后复制 sqlite/Media/expected-v6.zip/SOURCE.txt；无需 WAL（已 checkpoint，长度为 0）或 SHM。

迁移验收把资源复制到临时目录，在新 V11 容器打开、重开、完整导出并逐字段与原 v6 数据比较；另外验证媒体字节和分享 receipt。现有真实 V7/V8 fixture 保持原样。

## 原 Todo 候选 V11 fixture

`OriginalV11Fixture` 由本轮起点 `4625602b27d8b4e4df4f6da20b7f11bf30b21d8c` 的产品源码生成。生成时只追加 `CreateOriginalV11Fixture.swift` 中的测试至同一 TodoFoundationTests.swift（私有date helper可用），定向运行 `testGenerateOriginalV11CandidateFixture`；实际本轮在任何产品改动前的 s1-red 中生成成功。重现应先将该HEAD用git archive读出到新的临时目录，生成路径改为新空合成目录，禁止覆盖checked-in fixture。退出进程、确认WAL=0后复制store.sqlite/task-id.txt/SOURCE.txt，未复制SHM。数据只有合成月重复、提醒提前一日和完成/后继，没有Owner内容。

原V11 11.0.0模型节点在新代码中冻结；11.1.0只给候选TodoSeries增添可选reminderDayOffset。`testOriginalV11CandidateMigratesWithoutLosingTaskEventBytesAndInfersReminderLead`复制资源后打开/重开、核对原事件传输bytes、后继生成提前一日。旧V10/V7/V8资源不改写。
