# 睡眠与作息 V1 执行断点

状态：IMPLEMENTING。固定产品基线 `5614246f98ae63732ccd4fd8a6b66f4a425336f2`；批准文档快照 `1bed2f46b08c547d52e1ca2f28d74ac0f6696003`。已核验祖先关系，二者差异仅批准的两份 Markdown。

工作树 `/Users/himini/.codex/worktrees/sleep-routine-v1/PersonalGrowthOS`，唯一产品分支 `codex/sleep-routine-v1`，从文档快照创建；原工作区三处 dirty 保留。PR #8/#9/#10 只读核对，尚无本任务 PR。

## 顺序与门禁

1. 读取当前 V12/v8、保全/迁移、共享提醒和路由真实接线；追加 V13/v9、独立睡眠事实与目标规则，完成定向磁盘/区间/字段时间测试。
2. Today/Growth 单屏记录、历史和 7/30 日回顾、设置与共享提醒；三项选择无预选，日期固定，失败保草稿。
3. 一名独立只读 Reviewer 首轮审查数据及提醒契约；核实反例并限定修复。
4. 固定收敛 SHA：全量 Unit 一次、集中关键 UI 一次、Debug Simulator/unsigned Release generic iOS 实包；后续只补受影响项。Reviewer 第二轮检查固定 diff 和原始证据。
5. 更新验收/审查/当前文档，普通 push，新 Draft PR base `codex/important-days-v1`，远端核验后停 READY_FOR_OWNER_DEVICE_GATE。

所有测试只用隔离合成数据；不操作真实手机/私库，不 merge/tag/Archive/发布，不修改旧 PR。启动阶段未重跑旧全量。

## 当前断点

实现/首轮审查修复产品与测试快照 `a1530d14276325af50aa25393904e15a1da42d1a`。已追加 V13/v9、晨间表单、历史/区间回顾/目标/共享提醒及过期路由。独立 Reviewer 首轮五项 P2 已补反例并修复，第二轮固定 SHA 复审进行中。

下一步：一次完整 Unit（含已挂载真实 32MB HFS+ 合成低空间卷）、一次集中关键 UI，随后固定 clean 产品/测试 SHA 的两构建、独立终审与交付。不得标 READY。

## 已执行命令与结果

证据根 `/tmp/pgos-sleep-evidence`；每个 `.log` 首部保留完整 xcodebuild 命令，`.xcresult` 为原始包；构建缓存 `/tmp/pgos-sleep-derived`。Xcode 27.0 (27A266a)，iOS27.0 iPhone18Pro 合成模拟器。首轮使用既有合成 EC7758DB-5D1B-4D1C-AA4D-900A9E11B66A，收敛阶段创建专用 `C3FD4FD7-983B-43CE-83D4-12933FDB3728`。从未操作真实手机/私人库，也没有清理旧模拟器数据。

统一命令为 `xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=<上述UUID>' -derivedDataPath /tmp/pgos-sleep-derived -only-testing:<实际selector> -collect-test-diagnostics never -parallel-testing-enabled NO -resultBundlePath /tmp/pgos-sleep-evidence/<Run>.xcresult test CODE_SIGNING_ALLOWED=NO`。MorningUI2 另外使用 `SWIFT_EMIT_LOC_STRINGS=YES` 提取实际编译键；后续静态比对确认新键中英覆盖，原条目保留。

| Run | 真实结果与边界 |
| --- | --- |
| Compile1 | 初始接线 + WeightFoundationTests，9/9 PASS、exit0；以原始包计数为准 |
| Domain1 | 24/24 Unit PASS、exit0，10睡眠+原共享提醒14 |
| UICompile1 | 10/10 Unit PASS、exit0；名字不代表已跑UI |
| Data1 | 8/8 Unit PASS、exit0；另一个拼错 selector 执行0项，不作为WAL证据；后面正确补验 |
| MorningUI1 | 0/1 UI、exit65，Section 内 sheet 消失；移到稳定 Today 父层后闭合 |
| ReviewRed1 | 0/3 Unit、5断言FAIL、exit65；真实复现回拨目标、跨记录回拨、DST部分记录 |
| ReviewGreen1 | 25/25 Unit PASS、exit0，含正确alias/WAL、睡眠/提醒/迁移/审查回归 |
| MorningUI2 | 0/1 UI、exit65，主记录/重开/编辑/回跳/删除完成，删除后覆盖摘要在列表上方未滚动；保留原断言并补正常滚动 |
| SleepUI3 | 1/3 UI PASS、exit65，主晨间+体重路径通过；Record键盘遮挡Tab导致测试点击无效、AX表单等待了屏幕外save |
| Transfer1 | 66/66 Unit PASS、exit0，完整54备份+8重要日子+4睡眠持久化 |
| EdgesUI4 | 7/7 Unit + 1/2 UI PASS、exit65，中文深色AX通过；原Record键盘Tab测试仍失败，后续改为真实路由保护草稿 |
| RouteUI5（固定a153） | 11/11 Unit + 3/4 UI PASS、exit65，过期路由/Recovery/两类草稿通过；唯一设置状态在保存目标新增规则后被推到屏外，下一次正常滚动补验 |

初期 Unit host 在原合成模拟器打开了开发中已变化的未发布 V13 形状，出现 unknown-model 启动日志；正式 V11/V12 fixture 升级测试均通过。没有清库掩盖问题，最终门禁改用新合成模拟器。unsigned App Group Widget projection 日志、既有平台提示与真实 runtime warning 将按最终包分别记录，不宣称零警告。

隔离低空间卷命令：`hdiutil create -size 32m -fs HFS+ -volname PGOSSleepLowSpace /tmp/pgos-sleep-evidence/low-space.dmg`，attach 至 `/private/tmp/pgos-p1-low-space`，写入 `RUN_LOW_SPACE_TEST` 标记。只允许现有测试填充该32MB卷，不填主磁盘。

