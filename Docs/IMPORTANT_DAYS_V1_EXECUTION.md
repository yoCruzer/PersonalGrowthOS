# 重要日子 V1 执行断点

状态：IMPLEMENTING；完整 A/B 均在授权范围内，尚未交付。

- 产品基线：`20d315a62179ad29a6cbcf76c33c11638412e54e`
- 固定 Goal/设计：`3365561c5888701ce662ac6c8655ad1629ded6d0`；已完整读取，祖先核对通过，diff 仅两份新增 Markdown。
- 工作树：`/private/tmp/PersonalGrowthOS-important-days-v1`；分支 `codex/important-days-v1`；当前起点 HEAD 同固定 Goal SHA；尚无 upstream/PR。
- 原工作区保留 project.pbxproj、Localizable.xcstrings 与未跟踪 xcodecloud 改动。
- 远端 base 已核对为固定产品基线；未追逐其他本地分支。

## 实施与验证顺序

1. 纯日期事实/计算、独立农历样例、Today 排序；追加 V12 实体与 v8 备份，保护历史模型。
2. 管理/详情/关联/封面/搜索/Today 与共享通知协调；固定 SHA 独立数据风险审查。
3. Widget target、数字/照片/清单、最小授权快照、路由与隐私；独立产品集成审查与修复复审。
4. 收敛后一次全量 Unit/集中关键 UI，Debug/无签名 Release/generic device 包含关系；普通 push 与新 Draft PR；停 READY_FOR_OWNER_DEVICE_GATE。

## 最后验证与限制

- 启动仅做 Git 与环境核对，未跑旧全量基线。
- Xcode 27.0 (27A266a) 可用；沙箱内 simctl 无法连接 CoreSimulator，需在已有授权的系统工具通道核对，尚非环境缺失结论。
- 日期独立真值来源：香港天文台 2023/2024 公农历年历（代码 fixture 固定期望值，测试离线）。
- 审查 NOT_RUN；测试 NOT_RUN；产品实现进行中。

下一步：实现日期纯模块与边界测试，然后接入追加 Schema。

## 2026-10-15 数据/规则 checkpoint

已实现：共享纯日期模块（1901–2100；上海农历，原始事实与派生值分开）、V12 追加四实体、v8 备份（旧 v1–v7 读取路径保留）、独立封面复制/回滚、Entry/Todo 类型引用及原记录删除清理、创建/列表/详情/搜索/Today 初步集成。提醒在原 Todo coordinator 内统一日子和 Todo 候选与实际 pending，daily/weekly 共用串行 gate；保守总预算 60，日子最多预排两个期次并显示实际覆盖。仍需组件、路由、双语、交互收口与完整验收，不能称 A/B 已完成。

实际命令统一前缀：`xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=EC7758DB-5D1B-4D1C-AA4D-900A9E11B66A' -derivedDataPath /private/tmp/pgos-important-days-data-build -collect-test-diagnostics never -parallel-testing-enabled NO … test CODE_SIGNING_ALLOWED=NO`。Xcode 27.0 / iOS 27.0，专用合成模拟器，无私人数据。

| 运行 | 选择器/结论 | 原始证据（`/private/tmp/pgos-important-days-evidence/`） |
| --- | --- | --- |
| Date1 | 新日期10项，9 PASS/1 FAIL，exit65；误选2023正月三十正例，HKO显示该月廿九。修正为HKO 2025-02-27=正月三十；未删反例。此run使用初始FD666…模拟器；后续专用模拟器。失败后系统diagnose长等待，进程最终自然结束。 | date1.log / Date1.xcresult |
| Data build1 | V12/v8 Debug 编译 PASS exit0，代码尚未固定提交 | data-build1.log |
| Data1 | 日期/数据15项，14 PASS/1 FAIL exit65；精确备份比较暴露Date epoch转换精度。新增v8时间戳复用参考epoch原语；Entry旧格式边界不扩修。 | data1.log / Data1.xcresult |
| Data2 | 同15项全PASS，exit0。fixture teardown前仍持有SQLite导致unlink warning；已改为XCTest teardown，Integration1未再出现该警告。 | data2.log / Data2.xcresult |
| UI build1 | 初步管理/详情/表单/关联与入口 Debug 编译 PASS exit0 | ui-build1.log |
| BaselineFixture | 精确20d315a归档，只追加生成测试，1/1 PASS exit0；生成V11.1磁盘/Media/v7，WAL=0，未复制SHM；脚本及小fixture提交。不是旧全量基线。 | baseline-fixture.log / BaselineFixture.xcresult |
| Reminder build1 | FAIL exit65；复杂compactMap Swift类型推断超时，拆为显式循环，行为不变 | reminder-build1.log |
| Integration1 | 日期10+数据6+重要日子提醒5+旧Todo提醒7+旧迁移保护2 = **30/30 PASS，0失败/跳过，exit0**。选择器为三个ImportantDay测试类、TodoReminderTests、TodoFoundationTests/testOriginalV11CandidateMigratesWithoutLosingTaskEventBytesAndInfersReminderLead、testBuild12V10ContainerAliasMigratesWithoutFalseMissingStore259。保留旧alias路径SQLite诊断；模拟失败通知日志符合测试。 | integration1.log / Integration1.xcresult |

上述为开发中工作树证据，固定checkpoint提交随后由Git产生；不得将其当成最终产品全量验证。尚未全量Unit/集中UI/Release/device构建、Widget、远端CI或独立审查。

农历独立真值：香港天文台 [2023](https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2023e.pdf)、[2024](https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2024e.pdf)、[2025](https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2025e.pdf)。覆盖新年、闰二月、年末和缺三十；全1901–2100年初一遍历为内部一致性测试，不冒充200年逐日独立天文核验。范围外拒绝，不猜测。

当前下一步：固定 checkpoint 并启动独立数据/规则审查；继续Widget target/三种表达/最小授权快照和安全路由，不停在A。
