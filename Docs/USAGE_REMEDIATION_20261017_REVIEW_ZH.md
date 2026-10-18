# 使用反馈统一整改独立审查

Reviewer：`/root/usage_remediation_independent_review`；实现者：`/root`。下方为独立 reviewer 最终报告原文，未将作者自查或规划检查替代独立审查。设备/签名/CI 门不在通过范围。

---

独立终审结论：固定候选 `9601ff211fbdafc954e32f9e25206a38479e972b` 中，未发现仍未关闭、已确认的范围内 P0/P1/P2 实现问题。R1–R8 均有源码修复和相应反例、回归或实际截图闭环。该结论允许提交实现供审核；**不能据此将整个 Goal 标记为全部验收通过**，下述原生、签名、真机及 CI 门仍未完成。

本审查全程只读，没有修改、提交、运行构建或测试、操作模拟器或执行外部写入。独立检查了源码、Git 差异、测试断言、原始日志、结果摘要、实际包及截图，没有把作者摘要作为实现正确性的证明。

**固定输入与范围**

- BASE：`5a70f0110b151f8a45ac7c33d3f443823b1cff24`。
- 规范 GOAL_SHA：`68373d4edf10cff8ca3e212b9ff10a28e6da9c73`。
- 初始候选：`266c9cab7b3745fd8d217793e7acf7a9cfbbb715`。
- 最终审查及 Debug/Release 产品候选：`9601ff211fbdafc954e32f9e25206a38479e972b`，审查时工作树干净。
- 已按 bootstrap 阅读 Foundation、Development Contract、当前上下文，以及固定 SHA 的完整 GOAL、DESIGN、ACCEPTANCE。
- 审查覆盖 A/B/C 的生产变更及相关测试，重点检查身份与去重、证据构建、日期窗口、持久化、并发、取消、迁移和既有 F1/R1–R3 保护。

**确认问题及闭环**

| 编号 | 严重度、复现与后果 | 最终处理及证据 |
|---|---|---|
| R1 | P2。仅修改待办标题，既有通知/闹钟继续显示旧标题。原分支只比较时间、通道等签名。 | `TodoAlarmReminders.swift:255` 等比较 device journal 的 requestedTitle；仅对实际仍存在的本机请求取消确认后替换，停止或已退役请求不重新启用，并检查异步返回后的规范标题。双通道红例、停止负例、读入/调度竞态及取消失败回归通过。 |
| R2 | P2。星期选择顺序受 `Calendar.firstWeekday` 影响，英文地区可能星期日居首，违反固定 N1。 | `TodoViews.swift:697` 固定 ISO 顺序 `1...7`；持久化位值语义保持不变。星期交互与实际中文 Dark 最大 AX 截图闭环。 |
| R3 | P2。旧格式通知取消失败时，同系列后继仍可调度，产生旧、新两个本机请求。 | `TodoReminders.swift:299` 从移除后实际 pending 集合推导未确认取消项，并扩展阻塞同系列；传入 intent 调度器。保留的红例真实复现重复请求，修复后的协调器及相邻回归通过。 |
| R4 | P2。Weight 跨时区刷新保留旧时区绝对午夜，导致新时区查询只覆盖部分一天，日均也可能匹配不到。 | `WeightFoundation.swift:434`、`WeightViews.swift:190` 等按最后已发布时区处理选择：跨区清除，同区归一化；AllRecords 同步处理并增加前台刷新。真实 reader 配对反例验证旧查询遗漏早间记录，而正确新时区完整日为两条、均值 71。Weight/AppComposition 完整受影响类 35/35 PASS。 |
| R5 | P2。Today once/day 状态在最大 AX 下被横向布局挤成逐字竖列。 | `AppShell.swift:497` 附近改为 AX 垂直布局，保留普通布局、动作、禁用状态和标识。独立查看 ui-d8 Today0：状态自然两行，标题完整。 |
| R6 | P2。Growth 的 didSave 订阅可能在后台导入线程修改 SwiftUI 状态；实际出现两条后台发布警告。 | `HabitViews.swift:62` 增加主 RunLoop 调度。真实后台导入回归通过；后续 ui-d5 不再有该警告，ui-d6/ui-d8 runtimeWarnings 均为空。 |
| R7 | P2。7/30 日统计跨午夜改变，但 SessionPage 缓存键不含评价日；总数归零后仍可能显示旧范围明细。 | `InvestmentViews.swift:661` 加入 `today.identifier`，同一天不会按秒刷新。配对测试使用同一事实快照验证 7/30 日边界改变、All-time 不变；完整 InvestmentFoundationTests 31/31 PASS，实际历史窗口/月分页/跨日 UI PASS。纯 Unit 不被表述为触发过 SwiftUI `.task`。 |
| R8 | P2。共享入口图标随 `.body` 放大却仍占固定 24 列，实际侵入标题；完整行空白处也曾无法进入 Goals。 | `AppShell.swift:16,28` 将装饰且 AX hidden 的 glyph 固定 20pt/24 列，并给完整行加矩形 contentShape。ui-d8 实际默认英文及中文 Dark 最大 AX、Goals 导航、真实 Start→Collapse 和 Today 回查全部 PASS；独立查看截图确认图标不再侵入文字，Goal 完整可读。 |

另检查了列表选择行命中区域、投资确认按钮稳定标识及 WeeklyReview 收键盘工具栏修复。后者保留原收键盘动作和保存逻辑；QFiveSources 与原多字段填写、收键盘、保存、冷启动回归通过，先前重复出现的 Invalid frame 在 ui-d6 后续结果中消失。

曾怀疑 fresh ModelContext 重排提醒后，主上下文缓存会使随后完成/取消产生错误修订。真实磁盘、保留主上下文的配对反例通过，包含规范提醒、revision/event 序列、完整性及重开验证。该假设未获证实，已撤回，不列为缺陷。

**测试证据与复用边界**

证据目录为 `/tmp/pgos-usage-remediation-evidence`。

- `final-unit1`：实际 517 项，512 PASS / 4 FAIL / 1 SKIP，不能写成全绿 517。四个失败分别是测试遗漏新增必需空数组计数、仍期待旧确定性提醒 ID，以及旧包 fixture 未剥除新数组。已独立检查测试修正，未削弱生产校验。
- `final-unit-fix1`：完整 ImportExportRecoveryTests 与 QuietWinsReaderTests，60/60 PASS。
- 后续完整 WeightFoundationTests + AppCompositionTests：35/35 PASS。
- 后续完整 InvestmentFoundationTests：31/31 PASS。
- 已核对最终复用证明及 Git 差异：c909 全量 Unit 后仅七个生产文件改变，后续按实际影响补验；没有用局部通过次数拼成一次新的全量通过，也没有隐藏首次失败。
- `final-ui1`：27 项，21 PASS / 5 FAIL / 1 SKIP；原失败与警告均保留。
- `ui-d5`：10 项，7 PASS / 3 FAIL；`ui-d6`：6 项，4 PASS / 2 FAIL。后续修复、断言纠正及环境失败分别记录。
- `ui-d8`：最终同候选 mixed 1 PASS / 0 FAIL / 0 SKIP，runtimeWarnings=[]。独立检查实际截图和严格导航断言，未通过点击特定文字来绕开整行命中缺陷。
- 首次 Unit host 日志的 CoreData 未知模型版本记录应保留，并归因于一次性测试容器持有本任务中间态、未发布 V15；不能因为 xcresult warnings 为空就宣称所有原始日志无告警。V1–V14 未改，相关历史迁移验证通过。

**最终构建及实包**

`final-debug8` 实际 TEST BUILD SUCCEEDED；`final-release1` 实际 BUILD SUCCEEDED，Release 使用 `CODE_SIGNING_ALLOWED=NO`。

直接检查了 Debug 和 Release 的 App、Widget、Share 实包，而非只检查 manifest：

- 原三个 Bundle ID、版本 `1.0 (7)`、最低系统 `17.0` 正确。
- App provenance 为完整 `9601ff2…`、`Dirty=false`、`Source=localGit`、Tag 为空。
- 中英文 `NSAlarmKitUsageDescription` 均存在且内容正确。
- Debug 主 executable 与六个实际 debug/preview dylib 的 SHA256 均与 proof 相符；没有以相同 Debug stub 代替实现库身份检查。
- Release 实际 Mach-O 保留 minOS 17，AlarmKit 为 `LC_LOAD_WEAK_DYLIB`。
- Release 唯一所述 metadata warning 属于 ShareExtension 无 AppIntents.framework 依赖；日志明确其 target，不是 App 的 AlarmKit 元数据被跳过。

独立得到的 Release SHA256 与最终 proof 一致：

- App：`4b591efe9f0b335fdf322ec923a85218de1ddef93c7befcc721a87398d581e5b`
- Widget：`c84903ef08c9b229dd0d0c00ab9759b1fad9a6e4def6c6ee15e720098d9b52e3`
- Share：`43f7ae8385a51f6933e8e2ef1a7818f40d6eca2901e58236e10bdb37da480e4d`

**仍必须保留的限制**

- AlarmKit 授权调用两次真实到达 mobiletimerd，随后立即 denied、没有系统授权提示。真实正向调度、取消、响铃、系统 Stop/Open 仍为 NOT_RUN。fake 生命周期和直接 intent 测试不能替代这些证据。
- Public mixed NSItemProvider 正向测试仍为 FAIL/environment。实际诊断明确 `role=shareExtension / stage=providerRead / category=appGroup`；生产 Share/SharedCapture 与签名设置未因本任务改变。不能称为正向导入 PASS。临时条件 SKIP 和剪贴板探查已移除，严格成功测试恢复。
- 既有 unsigned Safari FAIL 保留；签名后的正向 Share/Safari 验证仍 NOT_RUN。
- 物理 D1–D4，包括真实闹钟与锁屏/静音/专注、硬件睡眠、所有者备份及不卸载签名升级、真实 VoiceOver/Photos/widget/离线组合，仍 NOT_RUN。
- 物理 HFS+ 低空间门为 SKIP/NOT_RUN；远程 CI 仍 NOT_RUN。
- 早先仅设置启动参数却实际仍是白色的截图只能记 Light；本次 Dark 结论使用真实系统 appearance 后的截图。

因此，最终实现审查没有未关闭的已确认 P0/P1/P2；完整 Goal 的原生集成及发布环境验收仍有明确缺口，必须在交付、Draft PR 和最终状态中继续显示。
