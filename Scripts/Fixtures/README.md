# 真实 Build 12 同源 fixture

本合成库由 `git archive c5a3c0ac859efc3ffa4e5d9f77909ec43565c871` 的精确源码生成；没有复制 Owner 库或修改历史 schema。使用 Xcode 27 / iOS 27 Simulator。生成测试只追加在临时归档的 `PersonalGrowthOSTests/PersistenceMediaFoundationTests.swift` 末尾，工程与产品源码保持基线。

复现：把该 commit 归档到新的临时目录，将 `CreateBuild12V10Fixture.swift` 追加至上述测试文件；对共享 scheme 仅执行 `PersonalGrowthOSTests/Build12FixtureGenerationTests`。生成目录为 `/tmp/pgos-todo-evidence/Build12V10Fixture`，仅用于本流程的合成数据，复跑应使用空的同名合成目录。测试生成 V10 sqlite、原始图片、v6 备份和来源文件。进程关闭后复制 sqlite/Media/expected-v6.zip/SOURCE.txt；无需 WAL（已 checkpoint，长度为 0）或 SHM。

迁移验收把资源复制到临时目录，在新 V11 容器打开、重开、完整导出并逐字段与原 v6 数据比较；另外验证媒体字节和分享 receipt。现有真实 V7/V8 fixture 保持原样。
