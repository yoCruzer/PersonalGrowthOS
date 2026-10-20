# 2026-10-20 UI专项追加批次 — READY_FOR_OWNER_DEVICE_GATE

本轮UI/本地化修复及额外无障碍问题闭环，固定产品/测试 `537a6f9103f6ccbf08b8634edf6dfc976247b4c8`。最终定向Unit111/111、英文3/3、浅深色原生UI/图标按下/状态/布局及Debug/unsigned Release实包检查完成；独立终审无未关闭finding，见 [本轮REVIEW](UI_READABILITY_LOCALIZATION_20261020_REVIEW_ZH.md)；交付以 [本轮执行与验收](UI_READABILITY_LOCALIZATION_20261020_ZH.md)、[运行台账](UI_READABILITY_LOCALIZATION_20261020_RUNS.json)、[截图证据](Evidence/UI20261020/README.md) 为准。历史失败/缺口与Owner设备门保留，不能以历史READY替代本轮。PR #13 Draft/base不变，不发布、不合并。

---

> **2026-10-19 系统复核：LOCAL_REVIEW_FIX_REQUIRED。** 固定产品 c296a369 / 交付 62210d9。7 组 SR 修复工作开放（5 组 P2、2 组 P3），BV-01/02 待有界验证。原因复盘、合法反例、完整消费者/生命周期覆盖和证据层级见 [系统审查原文](USAGE_REMEDIATION_20261019_SYSTEM_REVIEW_ZH.md)；执行 [真机前修复 Goal](USAGE_REMEDIATION_20261019_PREDEVICE_FIX_GOAL_ZH.md)。本次只审源码/测试/提交并写文档，未运行新原生测试。下方既有 R/F/CR 关闭原文和失败轮次完整保留，旧 READY 不作为当前结论。

---

> **2026-10-18 第二轮外部独立复核：CR-01～03 为仍开放 P2，CR-04～06 为 P3；当前 LOCAL_REVIEW_FIX_REQUIRED。** 基于产品 597552a / 交付 e75ac561 的源码和测试内容；未执行本轮原生测试。下一轮执行规格见 [第二轮限定修复 Goal](USAGE_REMEDIATION_20261018_REVIEW_FIX2_GOAL_ZH.md)，本次复核摘要在本文末尾。以下保留上一轮全部原文；其中“无未关闭 P2 / READY”不作为当前结论。

---

> **2026-10-18 最新复核：新 F1–F5 与 UX1–UX2 本地闭环，固定产品597552a，独立原文终审见本文末尾。** 下方旧R1–R8报告、外部F1–F5发现及原待修状态完整保留为历史；不覆盖设备/签名/CI遗留。

---
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


## 2026-10-18 外部独立复核补充 — 新 F1–F5 未关闭

复核固定交付 `f1b52b58fd11c41f508ec665d583827879ffa202`，对应产品提交 `9601ff211fbdafc954e32f9e25206a38479e972b`。复核使用实际源文件、调用链与测试内容，没有把上方实现者交接或旧审查结论当作正确性证明；本环境未执行 Xcode、模拟器或真机，因此本节不新增原生 PASS。

| 编号 | 独立复核结论 | 当前状态 |
| --- | --- | --- |
| F1 / P2 | 被撤回的后继再次启用时可能复用已退休提醒代次，任务 open 但不再安排提醒 | OPEN；待两渠道完整协调器回归 |
| F2 / P2 | 真旧 nil 系列偏移从单次改期后的可变值推导，可能偏移未来系列或阻止完成 / 跳过 | OPEN；待真实旧模型及旧备份反例 |
| F3 / P2 | 已接受 Todo 通知退出共享预算候选，新出现的更早或其他类别提醒不能正常置换 | OPEN；待动态重排与取消失败恢复 |
| F4 / P2 | 体重旧分页任务晚返回，可覆盖新日期查询并使后续返回出现混合 / 缺失页面 | OPEN；待可控 A/B 乱序测试 |
| F5 / P2 | 原 T7 未完成：草稿变动仍全量读取 / 解码历史，完整详情仍常驻后再切页 | OPEN；既有成本，非本 PR 新引入回归 |
| UX1 | 时间投入期间外选日自动切到全部累计，保留所选日期、月份与活动 | 交互决定已批准；实现验收 NOT_RUN |
| UX2 | 体重主页面最近记录遵守当前截止快照；独立全部记录保留全历史管理 | 交互决定已批准；实现验收 NOT_RUN |

逐项生产路径、固定源码链接、复现、修复边界和必要回归见 [PR #13 独立复核后的本地修复目标](USAGE_REMEDIATION_20261018_REVIEW_FIX_GOAL_ZH.md)。本轮 F1–F5 与旧 R1–R8 和时间投入历史 F1 / R1–R3 分开跟踪；旧审查原文不被改写，也不能据此声称新发现已关闭。

Owner 已授权下一轮 Codex 继续本地修复、验证和独立复核，当前文档提交仅使执行目标具体可审。新的独立实现复核须在修复后的固定产品 SHA 上进行，原始结论与修复后核对再追加到本文件。D1–D4 及原 FAIL / SKIP / NOT_RUN 保留。


## PR #13 修复批次独立终审（597552a）

以下为未编写本轮代码的reviewer原始结论；作者未代写独立通过。

独立只读终审：固定产品/测试候选 `597552a020eab22673feed108d8676359efd8822` 未发现仍未关闭、已确认的范围内 P0/P1/P2。F1–F5、UX1/UX2 及本轮复核追加问题已具备源码和本地验证闭环，可进入文档交付与 Owner 设备门交接。

Reviewer：`/root/pr13_fix_independent_reviewer`。我未编写本轮代码、修改文件、运行构建或测试、操作模拟器或 push；独立检查了固定规格 `2add10b0c67d064b7e77478fb18a11479d3c94dc`、完整增量、生产调用链、测试、原始日志、结果摘要、实际截图及实包字节。

| 项目 | 独立核查结论 |
| --- | --- |
| F1 | 撤回后继重新启用时更新提醒代次；普通通知与 Alarm 两渠道覆盖取消失败、确认后替换、冷启动和重复对账幂等。 |
| F2 | 在覆盖旧实例字段前，同事务冻结原系列偏移。真实 V11.0 单一 open/nil 实例和旧 v7 ZIP 恢复覆盖 0/-1、短期/>366 天、改分钟、完成/跳过、失败回滚、重开及再次导出恢复；原创建事件字节保持。 |
| F3 | 已接受普通通知重新参加共享规划；较晚 Todo 可被较早 Todo、ImportantDay 置换并恢复。预算等待、取消待确认、已停止/退休有区分；59 项保留请求、取消失败占用和同系列阻挡保持。已停止项不会借预算等待复活，停止项空位也不会继续占用一次分配。 |
| F4 | 初始、更多、重试共用稳定 loader 的当前 query/generation；提交结果同时校验取消和票据。确定性 A/B 晚返回、重试/刷新失效及真实 50→60、切日返回 A 第一页闭环。 |
| F5 | Workspace 保存轻量贡献/ID及非终态操作；完整详情经真实 20 条分页、单 ID reader 读取。Service→事件→`Workspace.receive` 的真实链有读取和解码计数。正式编辑、删除、导入、读取失败/显式重试及失败草稿恢复均覆盖；必要业务重复校验扫描仍保留并与 UI 刷新区分。 |
| UX1 | 期间外选日自动切换全部累计，保留日期和活动，月份定位正确；实际中文 Dark 最大字号截图和测试显示 2026-09-01、45 分钟、1 条及正确详情。 |
| UX2 | 主页面最近记录使用截止快照上界，独立全部记录仍可管理截止之后的数据；英文及中文 Dark 最大字号的截止标题、历史查询和编辑删除刷新已核对。 |

本轮复核提出的追加问题也已关闭：prepared/查队失败继续保持原确认语义；重复候选不再显示伪零贡献，排序与输入失效正确；Editor 擦除同时清理重复候选及待确认精确区间副本；统计读取失败后草稿事件不会隐式重扫历史，顶部提供显式 Retry；新增截止标题具备中文翻译。

F5 最终 `final-unit2` 的真实落盘夹具含 10,000 个有效 Session 及配对 Operation，含长备注和多分段。首次读取各 40 批、各解码 10,000 条；连续草稿保存、checkpoint、暂停、继续后正式历史及全部 Operation 的批读取数保持 40/40，正式事实解码数仍为 10,000，局部 Operation 解码为 9。两页共解码 40 条、单条详情解码 1 条。首次刷新 0.317755103 秒；整个测试进程峰值 RSS 前后均为 553,107,456 bytes，包含夹具与测试宿主，不能解释为 Workspace 独立内存或节省量。

验证记录按轮保留：

- 最终 clean `597552a`：`final-unit2` 九个完整受影响类，242 项＝241 PASS / 0 FAIL / 1 SKIP，runtimeWarnings=[]；SKIP 为隔离 HFS+ 物理低空间环境。
- `final-ui1` 在 clean `f946d651` 上为 **8 PASS / 2 FAIL**，保持失败。两处分别为部分可见整行导航与导航区内输入框未取得焦点。
- `597552a` 相对 `f946d651` 仅改 UITest；我独立核对生产与 Unit 零 diff。八个已通过方法及其相关辅助逻辑未变，可按明确 blob 证据复用，不能称该轮全绿。
- 最终 `final-ui-supp1` 为 **4 PASS / 0 FAIL / 0 SKIP**，runtimeWarnings=[]。补验仍点击整行，保存了完整可见区域的几何和截图；输入框获得键盘后继续验证输入变化清候选和保存。另补体重编辑删除及中文截止展示。
- `candidate-unit1` 的提醒确认语义失败、`review-fix-unit1` 的事件 expectation 重复 fulfill，以及此前 red/focused UI 失败均保留；后续修复与补验没有改写旧结果。

`final-debug2` 与 unsigned generic iOS `final-release1` 均来自 clean `597552a`、退出 0。我直接读取两种配置的 App/Share/Widget 实包并重算可执行文件哈希，与 proof 一致：原 Bundle IDs、1.0(7)、minOS 17 保持；两 App provenance 均为完整 `597552a`、Dirty=false、localGit、Tag 空。实际 Release Mach-O 的 AlarmKit 为 `LC_LOAD_WEAK_DYLIB`，Debug 证据亦一致。历史 Schema、TransferModels、ZIPArchive 和工程配置相关 blob 未改写。

以上结论限于本轮实现及本地证据。AlarmKit 原生正向调用 NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间 SKIP/NOT_RUN、远端 CI NOT_RUN 继续保留；D1–D4、私人设备/私人库、签名覆盖安装和发行验证均未通过，不能由本报告改为 PASS。

## 2026-10-18 第二轮外部独立复核摘要 — CR-01～06

审查固定产品/测试 `597552a020eab22673feed108d8676359efd8822`、交付 `e75ac56110cb9c4f58158eaf494087b2ed946324`。ChatGPT 外部只读核对远端身份、相对 2add 的四提交/24文件差异及相关调用链，并对三个 P2 做反证复核。本节为源码审查摘要，不是新原生运行报告，也不改写上方既有 reviewer 原文。

| 编号 | 判定 | 缺口与现有测试边界 |
| --- | --- | --- |
| CR-01 | P2 / OPEN | capacityCancellationPending 在同一开放意图跨过 fireAt 后被重排前置条件跳过，Recheck 不收敛并遮蔽过期重设；现有 F3 固定时钟且取消及时恢复。 |
| CR-02 | P2 / OPEN | 容量 pending 和 waiting 两次真实未落盘，而 native 移除成功，accepted 缺失被误退役，释放容量不能恢复原意图；不把抛错但精确读回成功混为此例。 |
| CR-03 | P2 / OPEN，存量兼容遗漏 | 有效旧 V11→旧 f1 已保存单次覆盖→当前 V15/v11 路径仍从覆盖后实例推导 nil 偏移；新测试只覆盖用当前服务第一次改期。 |
| CR-04 | P3 / OPEN | 正式候选 B 编辑/删除后，未变草稿 A 仍保留旧 duplicateIDs；原测试改 A 自身，未覆盖候选成员变化。 |
| CR-05 | P3 / OPEN | 保存后终态操作退出缓存，内层编辑器关闭但外层 Timer sheet 不关闭，内容可能为空；现有保存测试未检查最终落点。 |
| CR-06 | P3 / OPEN，测试稳定性 | 固定 2026 年 10 月夹具而日期选择器用 Date()，仅查 October 10/10月10；跨月/年不可重复。 |

两项观察单列：OBS-01 是既有“save 后抛错”故障模型下同一 Workspace 刷新/retry 的恢复缺口，未证明生产 SwiftData 自然出现此分支；OBS-02 是旧分页按钮任务很晚才进入 loader 的入口防御观察，未证明真实 SwiftUI 调度可达，不据此重新打开 F4。其补验与有界停止条件见新 Goal。

可认可的代码层修复：原 F1 后继重新启用换代、F4 已进入 reader 的旧结果晚完成保护、UX1 窗外选日与 UX2 截止/独立历史边界；F5 确实接入 Service→事件→Workspace 的按 ID 刷新、轻量事实及真实有界详情，10k 测试不是单纯 generation helper。上述范围作为本轮保护，不重复开发。

外部审查未取得开发机 xcresult、截图或实包，不能独立复算上一轮 241/0/1、8/2 后补 4/4、双构建与哈希声明；没有把它们判为虚假，也没有冒称本次运行通过。远端身份可核对，产品 check-runs 为 0，CI 仍 NOT_RUN。设备门及历史 FAIL/SKIP/NOT_RUN 保留。

结论：当前不认可无未关闭 P2/READY_FOR_OWNER_DEVICE_GATE；Owner 已批准依 [第二轮限定修复 Goal](USAGE_REMEDIATION_20261018_REVIEW_FIX2_GOAL_ZH.md) 在同一 PR 连续修复和验证。本规格提交未关闭任何 CR。后续 reviewer 在此追加实际独立结论和逐项关闭证据。


## 第二轮限定补修独立终审（2026-10-19）

固定规格41ef47c；候选`c296a3691d53ce7f5b5bff36fbf7de525d86510f`。以下保留未参与本轮实现的 reviewer 原文；原始证据根 `/tmp/pgos-pr13-fix2-evidence`，其确实为本机只读复核，非远端CI。发现与修复过程、失败和补验见EXECUTION/ACCEPTANCE的同轮追加。

```text
独立终审结论（2026-10-19，reviewer：`/root/pr13_fix2_reviewer`）

审查固定规格 `41ef47c384464823f9456e9816d574ba7edff563`，最终产品/测试候选 `c296a3691d53ce7f5b5bff36fbf7de525d86510f`。本人未编写本轮实现或测试，未运行 Xcode、操作模拟器、写入文件或 push。已只读核对完整最终 diff、相关生产调用链、新旧测试、真实旧 V11 夹具来源、本机原始日志、xcresult 摘要、实际截图及 Debug/Release 实包。原规格、已审交付和原 base 均为候选祖先；任务工作树干净，主工作区三项未知改动仍保留。

**CR-01～CR-06 已关闭，OBS-01 已完成限定验证及恢复修复，OBS-02 已完成最小入口加固与有界核验。范围内没有尚未关闭的 confirmed P0/P1/P2。**

| 项目 | 独立复核结论 |
| --- | --- |
| CR-01 | 容量取消确认已与未来排队资格分离。跨过 fireAt 后，实际 native 缺失或最终取消成功均能收敛为 elapsed/retired；未确认时继续阻挡，过期不重排。可推进时钟、冷启动、重复对账及未来等待恢复对照通过。普通通知过期判断不改变正常 ringing Alarm 的既有行为。 |
| CR-02 | 容量取消原因必须可靠落盘或精确读回，之后才允许移除 native。真正未保存、pending 保存而 waiting 未保存、实际保存后仅报告错误三种分支有区分；故障恢复后保持原 generation，等待意图可以恢复，停止负例和应用预算保护仍在。此结论不扩展为 AlarmKit 原生容量证明。 |
| CR-03 | 显式规则 offset 优先；nil 恢复使用经过事件链及末端事实验证的第 0 期原始创建/转换证据，派生后继不参与规则投票。已核对真 V11.0→迁移→旧 f1 等价覆盖事务→V15/v11 ZIP 恢复的来源；等价事务与旧服务 happy path 一致，没有声称运行旧二进制。0/-1、短/长延期、同/改分钟、完成/跳过、再改期、重开、历史字节、原子回滚均有证据。当前版本元数据编辑、时区刷新和清单删除会先冻结偏移，包含任务与模板清单不一致分支。 |
| CR-04 | 正式候选编辑/删除后，草稿 A 的候选 IDs、基线、对话框和陈旧重复提示失效，输入及最后成功草稿保留；真正保存错误不被清除。默认编辑 B、中文 Dark 最大字号删除 B 后返回未变 A 并正常保存的完整 UI 通过；仍匹配时的重复确认负例保留。 |
| CR-05 | 内层保存成功后，外层 Timer 按 dismiss 顺序返回有效 Hub；未恢复常驻终态 payload。最终完整 UI 同时覆盖中英文失败保留输入、重试成功、两层退出、稳定 Hub、恰好一条 3 分钟事实和正确详情备注。我实际查看了中文稳定落点和单条历史原图。 |
| CR-06 | 页面与夹具共用仅 DEBUG+UITesting 可启用的固定时钟，原生日期弹窗核对 2026 年 10 月，再选择 10 日。Unit 以 2026-11、2027-10 的 live 日期作对照；无测试授权时继续使用真实日期。中英文截止、全历史 17 日、分页切日断言保留。未修改主机时间，也未冒称在未来日期真实运行。 |
| OBS-01 | 同一预热 Workspace 在实际提交后报错及实际未提交的对照中，普通刷新、Retry、后续命令、checkpoint 和关联删除清理均通过。错误失效限定在真正尝试 commit 后；业务重复拒绝不发布事实失效，真实 RunLoop 交付反例已补验，避免误清刚展示的候选。仍报告原错误，未把故障注入描述为 SwiftData 自然必现问题。 |
| OBS-02 | 旧按钮入口不能再通过 load 重选旧 query；切换权由 initial/select 持有。正常首载、分页、重试、显式切日和已启动旧 reader 晚完成保护通过。真实 SwiftUI 是否可产生原观察中的启动顺序仍为 UNCONFIRMED；未据此重开原 F4。 |

CR-03 的自动恢复存在明确证据边界：技术时间相等不能单独证明规则未变；缺失第 0 期、旧规则缺少可识别 policy，或存在无法区分的复杂墙钟编辑时，代码拒绝编造偏移并保留事实，可由显式系列规则纠正。此边界已在测试和交接草稿中披露，未冒称任意旧 nil 状态均能自动恢复。

审查过程中发现并闭环了旧 V11 派生后继错误导致的回归、同时间戳/转换来源歧义、新元数据/时区/清单操作污染恢复线索，以及业务 duplicate 错误失效清除候选的问题。原有断言保留；相关红测、编译错误、夹具模型生命周期崩溃和 UI 驱动失败均保留，没有改写为一次全绿。

最终本地证据已实际读取：

- `final-unit4`：干净 c296a36，九完整类 **252＝251 PASS / 0 FAIL / 1 SKIP**，exit 0；不是全仓重跑。低空间环境 SKIP 保留。
- `final-ui-cr05`：同候选 **1/1 PASS**；`final-ui-regression`：同候选 **8/8 PASS**。其余两项 Weight、duplicate、CR-04 仅复用完整通过的方法，并核对生产路径、测试方法和 helpers 的 SHA/blob 关系。原取消轮及失败轮分别记录，不能称一次 13/13。
- F5 真实 10k Service→事件→同一 Workspace 链保持 40/40 批次、10000/10000 解码，草稿和计时命令无额外正式历史扫描；两页详情解码 40、单 ID 详情 1、已保存正文常驻 0。RSS 是包含夹具的整 host 观察，未作为 Workspace 独立峰值或节省量。
- 最终 Debug 与 unsigned Release 均为干净 c296a36、exit 0。App/Share/Widget 原身份、1.0(7)、minOS 17 保持；App provenance 完整 SHA、Dirty=false、localGit、Tag 空。实际承载二进制的 AlarmKit 弱链接与中英用途说明已核对。Release 主程序 SHA-256 经我独立重算为 `350819f01ff4035a9fe2d64a437ccd851316335fd59540bc2bde6aa71c6329cc`，与 proof 一致。

原始证据位于 `/tmp/pgos-pr13-fix2-evidence`。最终 Unit/UI 摘要与原日志一致，四份最终日志哈希经独立重算与小型摘要一致。交接矩阵及小型结果草稿未见错误计数或过度主张；本机读取不代表远端 reviewer 已取得临时产物。

本地产品验证与独立复核门已满足 **READY_FOR_OWNER_DEVICE_GATE** 条件；实施者仍需完成文档交付、普通 push 及 PR Draft/base/head 核对。D1–D4 未通过；AlarmKit 原生正向 NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间 SKIP/NOT_RUN、远端 CI NOT_RUN 均保留。本结论不授权私人设备/库操作、签名安装、merge、force push、tag、Archive 或 TestFlight。

```


## 2026-10-19 系统复核登记 — SR/BV

本轮完整独立审查与原因复盘固定保留于 [SYSTEM_REVIEW](USAGE_REMEDIATION_20261019_SYSTEM_REVIEW_ZH.md)。SR-01 合并此前 NR-01/02 并扩展停止后普通编辑同因分支；SR-02 体重无损编辑、SR-03 Weekly 全事实业务日/截止、SR-04 MainActor 发布等待、SR-05 settings 旧任务晚错、SR-06 成功编辑器释放、SR-07 同类 UI 收尾。BV-01 Growth 真读取、BV-02 非有限 quantity 正式落库/备份，先不定性为 confirmed P2。

这次结论否定的是“本地已可直接交接设备门”的当前停点，不抹去旧 CR-01～06 在其原适用范围的修复证据。本次未读到开发机全部原始运行产物、没有重跑 Xcode；新修复关闭必须由 Codex 固定产品 SHA 后补证，不能用旧251PASS代替。


## 2026-10-19 系统整改独立终审 — 原文保留

以下为未参与本轮实现的reviewer原文。预登记反例SHA256 `785a144529913ed867f71a6d888d9e5cbbf6f13b84f902c6adc2cd66bcba9404`；终审原文SHA256 `97a2b772840552d3ae5f56d34f2017c5332f10d4d4ebd5ddf5a124897ca5f469`。主agent仅追加外层说明和分隔，不改原文；固定产品/测试c55dc10fde79f1fe4dec18b03195119c2049830f。

# PR #13 独立反例预登记

Reviewer: /root/pr13_system_independent_reviewer；仅只读产品/测试/仓库文档。
固定规格 3dad3b04e3ff703c2e799899035285f64a5976a4；审查候选 c55dc10fde79f1fe4dec18b03195119c2049830f。
本文件在阅读实施者最终关闭矩阵、新测试说明与实现 diff 前写定。已读取 AGENTS/bootstrap、Foundation、Contract、CURRENT 最新状态、固定 Goal 与系统报告；以下由其领域不变量独立推导，不把旧报告的关闭声称作为证据。

1. SR01：原始 nil offset 的系列 Stop 后再执行默认当前 edit（包括原 override 与无 override）、关闭提醒、换区、删除清单；根已删、兄弟期已删仍有 open、stopped/orphan 均不需要猜未来 offset。检查 Stop 权威先于策略恢复，普通标题保存不隐式打开 futureSeries，不让健康 Todo/ImportantDay/Sleep 因单个合法歧义失败。相反检查 active nil 仍不被猜为0、显式0/-1可续接；取消不确定状态不得被停止/刷新复活。事务失败须不改历史/来源/清单绑定。
2. SR02：以合法1000、72.345、常规值开编辑器，不改数值或只改日期，经 en_US、zh_CN、逗号小数地区保存重开；展示分组不得参与解析，无损字符串必须在科学计数/最大有效精度仍可往返；真修改/混合错误输入区别处理。
3. SR03：同一洛杉矶周日业务日早晚两条日志移到上海，必须同原周1天2次；跨年和DST相同。选择历史周周一但实际 asOf 在未来，周后半仍保留；反过来当前周未来带图/标签 Entry、未来Weight、五分钟容差Habit必须整套派生摘要排除。元数据较晚创建不应隐去已选事实；只读不补写，删除/撤销要刷新。
4. SR04：真实导出持 publication 锁，scene checkpoint 与保留编辑器同时请求，MainActor probe 必须先于释放；纯paused不得增长。排队后 pause、finish、discard/delete 或新revision胜出，旧checkpoint不得回写。第一次因锁忙/写失败之后必须有可靠重试路径，最新编辑输入不得丢，无关主context草稿不得被保存/回滚。逐个找全同锁MainActor调用者，防只把自动checkpoint搬入Task仍同步等锁。
5. SR05：A进入真实addRepeating await，B改时间/weekday或关开关，A分别晚success、CancellationError、普通error；旧A不能改B偏好、权限、提示。B真失败应关闭并提示；daily与weekly都覆盖，串行gate不等于结果所有权。
6. SR06：连续新manual/timer成功只清对应内存editor，saved operation与正式ID仍可幂等查；失败、Keep draft、Confirm later、另一个editor及正式编辑必须保留。保存成功释放期间旧checkpoint回调不能重建finished缓存。
7. SR07：daily once/multiple/weekly/monthly/长名统一文字列和可点击动作，真实中文Dark最大AX需要看像素；Sleep/ImportantDay“知道了”只收消息不改提醒。外部路由Dismiss的丢弃语义保留；Weight历史截止文案按截止日。
8. BV01：Growth真实挂载与切离后，10k Weight/Sleep上Investment草稿保存不得全历史重读；同时正式Weight/Sleep、活动归档/import/跨日跨区不能因过滤而漏刷新，过滤器不得捕获失活ModelContext或container导致寿命crash；错误不能伪零。
9. BV02：inf/NaN/overflow经正式Service到磁盘和export，输入拒绝不等于旧非有限事实可备份。旧异常quantity必须完整、可恢复且不静默删除；finite精度和旧包恢复保持，未知编码不能误解释。

证据优先级：直接源码/实际接线与原日志/xcresult、真实截图/实包 > 机器摘要 > 实施者说明。逐轮原FAIL、合法SKIP与复用分别报告，不把多轮相加为一次全绿；D1–D4及所有原生/签名/CI限制保持。


---

# PR #13 真机前系统整改独立终审原文

审查者：`/root/pr13_system_independent_reviewer`，未参与本轮产品或测试实现。审查日期：2026-10-19。结论：在下述固定代码和证据范围内，SR-01～07 有明确关闭依据，BV-01/02 均为 **CONFIRMED_AND_FIXED**；未发现本轮范围内仍未关闭的 confirmed P0/P1/P2，明确要求的 P3 收尾 SR-06/07 也已完成。可以进入本地批次交付；此结论不代表设备、签名、发布或远端 CI 通过。

## 1. 固定对象、独立性与方法

- SYSTEM_FIX_GOAL_SHA：`3dad3b04e3ff703c2e799899035285f64a5976a4`。
- 固定审查产品/测试 SHA：`c55dc10fde79f1fe4dec18b03195119c2049830f`。
- 完整 Unit 和首轮关键 UI 候选：`00b65b70d988ef26455d719ccf35eda61233120a`；向 c55 的变动只有三个 UI 驱动方法所在文件。
- 工作树：`/private/tmp/PersonalGrowthOS-usage-remediation-20261017`。开始时 HEAD c55、工作树干净。审查后段主 agent 正常追加五份交接文档，产品 SHA 不变；本人没有写产品、测试或仓库文档，没有接触默认主工作区的未知改动，没有运行 Xcode/模拟器、push 或发送外部消息。
- 按 AGENTS/bootstrap 阅读 INDEX 定义的现有 Foundation、Contract、两份 CURRENT 最新状态，再完整阅读本轮固定 Goal/系统报告；并核对前两轮修复 Goal、EXECUTION/ACCEPTANCE 的有关保护及本轮分轮资料。

本人在看实现 diff、实施者最终关闭矩阵和新测试说明前，先写定 `/tmp/pgos-pr13-system-evidence/independent-counterexamples.md`。其 SHA256 是 `785a144529913ed867f71a6d888d9e5cbbf6f13b84f902c6adc2cd66bcba9404`。预登记包括：停止 nil 系列后的默认 edit/删根/删清单/切区；数值无损往返；业务日跨周跨区和三类未来事实；导出持锁与晚 checkpoint 的暂停/完成/删除权威；每日/每周旧 success、CancellationError、普通 catch；只释放成功编辑器而保留其他草稿；全部习惯变体、反馈语义，以及两个 BV 的实际生产观察和反向保护。以下结论是对这些反例及合法后续操作的核对结果，不以实施者关闭标签替代证据。

完整审阅 `3dad..c55` 的生产、测试及文档/机器摘要变动；另查未改的 Todo intent/journal、默认编辑器、Stop/delete、Habit resolver/analytics、QuietWins reader、Weight service/reader、Investment service/reader/state machine、ImportantDay 全部同锁调用方、Share/import/export worker、反馈/设置结果和双层导航。没有发现新增 schema、修改历史 schema、改变既有传输版本或工程身份的 diff。

## 2. 独立反例核对与逐项结论

### SR-01 / P2：关闭，终止权威与未来策略恢复已解耦

关键位置：`TodoFoundation.swift:412` 的 preserve、`:527` 起默认 edit、`:657` refresh、`:679` Stop、`:690` delete、`:714` deleteList；`TodoReminders.swift:170` 后完整协调；未改 `TodoAlarmReminders.swift:170` targets 和 `:183` current。

- Stop/delete 先保留终止权威，不需要恢复 nil；preserve 和换区刷新跳过 stopped，删清单对 stopped/orphan 不推导未来 offset。默认当前 edit 仍走原业务入口：无 override 时关闭 Reminder，以及旧 f1 nil+override 时只改标题/备注均不要求 futureSeries=true。override 原时间保留；真正继续生成/套用未来模板仍需可信原规则。
- 真 V11 原模型迁移和已有 `OriginalV11Fixture` 被实际测试使用。`fix2OldF1Override` 按旧正式 reschedule 的 fresh context、墙钟、before/after事件、revision和override意图构造已保存状态，而不是调用新防污染路径后再冒称旧状态。原始 nil、有根/根已删、多期删兄弟仍有 open、保留来源 Entry 和空清单解绑都进入测试。
- active 的合法不可推导 nil 只捕获 `TodoFailure.invalidReminderOffset`，不会用0猜策略。协调器跳过该条并显示待明确规则；健康 Todo/ImportantDay/Sleep 继续。JSON解码、corruptData、数据库错误没有 catch-all 伪装成局部策略失败。负例 `testSystemSR01InjectedIntegrityReadFailureIsNotSwallowedAsLocalLegacyPolicy` 确认不排陈旧快照。
- 跨领域反证：局部规则警告没有覆盖真实 cancellationPending。最终状态还查旧 legacy/retired/rebalanced/display snapshot 的取消不确定性；原请求未确认消失时保留重查入口，不把它当已取消。未改 intent targets/current 仍以 stopped 为非活跃，标题编辑或冷重开不能复活停止系列。显式0/-1/7/366、skip/complete/reopen续接与幂等、满队列/两渠道/停止负例保护仍实际运行。
- 新测试：ImportExportRecoveryTests 五个 `testSystemSR01*`，TodoFoundationTests 的 `testSystemSR01ExplicitZeroLeadAndLargerOffsetsKeepOverrideGenerationAndTermination`；包含保存失败原子回滚、磁盘重开、实际 ZIP 导出/恢复、完整性和既有历史事件保留。红轮 red-a 在旧逻辑真实抛 invalidReminderOffset；最终完整 Unit 上述方法均 PASS。

本次未发现停止系列、默认 edit、清单删除及健康邻接类别仍存在可达的同因失败。明确规则纠正仍是无法推导的 active 旧策略的诚实边界，不是自动修复历史猜测。

### SR-02 / P2：关闭，编辑表达与显示精度分离

关键位置：`WeightFoundation.swift:47`、`WeightViews.swift:336`。编辑初值用 Swift Double 最短可往返字符串、无分组；逗号小数地区只替换小数分隔符，与既有 parser 配对，显示舍入不再写回事实。检查合法科学计数表达仍能经 parser 往返，未缩小1000合法边界，也没有全库舍入。

`testSystemSR02EditorRoundTripPreservesExactWeightAcrossLocalesAndDisk` 经实际 formatter→parser→WeightRecordService→磁盘重开，覆盖 en_US/zh_CN/de_DE、1000/72.345/65.2、日期-only及正常点/逗号修改，混合错误和非有限输入拒绝。red-a 保存了 en_US 1000→1 的真实红断言。UI `testSystemWeightNoOpAndDateOnlyEditsPreserveFullValueAfterRelaunch` 实际开编辑器直接保存、改日期、处理1000、重启再开；已看最终72.345/Oct11像素。Weight趋势/BMI/截止/分页原 service 与 reader 未变，相关旧 Unit/UI 仍运行。不能据此声称恢复以前已经损失的精度。

### SR-03 / P2：关闭，三类事实共用实际 asOf，选周保持独立

关键位置：`WeeklyReviewFoundation.swift:307` 起，`WeeklyReviewViews.swift:37` 选周身份和 `:65` summary、`:109` TimelineView；未改 `HabitFoundation.swift:336` resolver、`:1160` 正式日志写入及 QuietWinsReader 的业务日读取。

- Habit 周归属和 activeDayCount 均用保存的 civil day，实际 occurredAt 只承担时刻截止；没有机械改 Timeline绝对时刻排序/标签。缺元数据沿现有 Habit resolver 的当前区保守回退，只读不写 metadata。QuietWins 现有“需要保存元数据才作可信证据”的边界保留，不能把缺元数据的旧事实声称为三个消费者完全同口径。
- Entry/完成HabitLog/Weight 各先不晚于同一 asOf，再按 respective业务时间归周。条数、天数、图片、TopTags、RecentEntries均从过滤后 Entry 派生；Tag/Habit名称/ObjectLink当前元数据没有无依据追加createdAt截止。
- init把所选周固定成身份，环境区变化按同一身份重建；实际 cutoff由Date()及periodic刷新推进，不取历史周周一。已读真实 UI callsite，不是只测试一个多了参数的 helper。
- `testSystemSR03SavedCivilDayAndActualCutoffAcrossZonesAndHistoricalWeeks` 通过正式 HabitCheckInService 和磁盘重开验证 LA周日→上海、跨年、春秋DST，原业务日早晚两次为1天2次，analytics/QuietWins配对，undo和无元数据只读也检查。`testSystemSR03AllWeeklyDerivedFactsUseSameActualAsOf` 正式保存带图Tag未来Entry、容差内Habit、未来Weight，先排除再推进纳入，随后编辑/删除/undo派生刷新。
- red-b保留错周和未来事实两项红例。最终Unit两项PASS。UI当前周截图显示当前Entry/1次habit/70kg而没有未来99kg；历史周截图显示周日Entry/69kg，证明历史周后半段未被referenceDate误截。未增加Sleep/Goal/Investment摘要。

### SR-04 / P2：关闭，MainActor不等发布锁，检查点可靠重读

关键位置：`ExternalCaptureImport.swift:19–42`，`InvestmentViews.swift:179–217`、`InvestmentFoundation.swift:266` 事务；生命周期原入口 `AppShell.swift:203`。

- Main thread用try-lock，忙则抛明确可重试busy；真正阻塞等待在detached worker，只传root URL。不是把原同步MainActor等待再包一个Task。后台Share/import/export仍持同一个规范root锁，真实媒体/库快照互斥没有移除。
- 自动checkpoint遇busy保存最后clock并合并任务。worker等可用之后回MainActor创建新context、读当前operation/revision；没有携带旧running模型/上下文跨actor。若可用到命令之间另一worker再次拿锁，会再次busy并排队，不永久跳过。暂停不累计、finish冻结、discard/delete从active读取移除或擦除editor；因此晚请求不能重放旧running revision。显式命令在busy时保留输入、反馈重试，失败不会把其他主context草稿连带save/rollback。
- 搜索核对同锁全部使用方：Investment全部mutation；ImportantDay save/createEntry/delete（忙在实际变更前返回，调用者原catch保留输入）；ExternalCaptureImporter.run、export、import.publish和新增raw恢复worker。没有把后台worker合法等待误报为UI阻塞，也没有依赖导出sheet背后可任意编辑的不可达假说。
- 三个 `InvestmentPersistenceTests/testSystemSR04*` 使用真实export持锁barrier和独立后台fail-safe。red-c原MainActor probe只能在barrier超时释放后执行，真实失败；最终probe先于release，之后落盘120秒，备份仍60秒cutoff，无关Entry草稿未提交。合并等待后显式pause/finish拥有最新revision；纯paused无工作、完成/取消/导出失败与保留editor之前写失败再重试均有区别。
- 删除终态主要由代码与原删除/擦除测试反证：refresh的erased清理+service authoritative读取不把旧editor复活；没有声称新增了独立“导出等待后删除”的专门native实验。原ContinuousClock/process token/50ms/18h/倒计时/跨进程/回滚和F5保护都在本轮完整Unit执行。

本次没有测量真机卡顿秒数或watchdog；结论限于确定性因果次序与规范状态/快照正确。

### SR-05 / P2：关闭，三个结果出口同一所有权校验

关键位置：`ReminderFoundation.swift:155–174`、`AppShell.swift:1357` daily和`:1370` weekly。

提交B会取消A并换generation；success、CancellationError和普通catch先归入Result，再统一验证Task取消/generation/当前偏好快照后才apply。AppShell真实daily/weekly都接该边界，enabled/minutes/weekday按提交值捕获；即便绑定变了而onChange尚未提交，isCurrent也可拒绝旧结果。当前普通失败仍disable并反馈；明确off仍正常移除。原MutationGate、60保守预算和未知请求保留，不把gate当UI所有权。

两个 `ImportantDayReminderTests/testSystemSR05*` 挂起实际scheduler.addRepeating，再投递B on/off、M2/weekday和旧A三种晚结果；当前真失败必须抵达反馈，快照先变后提交的窗口也验证。不是在测试复制一个改良UI闭包。它们在完整Unit PASS，UI正常off/relaunch PASS。旧源码普通catch可达序列是源码合同证据，不虚构一次原生晚错捕获或不存在的旧helper红测。

### SR-06 / P3：明确收尾完成，仅释放成功缓存

关键位置：`InvestmentViews.swift:253–269` 以及editor.persist、refresh erased分支。只有service可靠成功后才completeEditor并按同一对象身份从Workspace字典移除；正式编辑清临时正文。saved operation和规范Session未删除，继续承担重试幂等证据。失败、Keep draft、Confirm later、其他editor输入仍保留；晚checkpoint遍历当前未finished editor，不会重建成功缓存。

`testSystemSR06SuccessfulEditorsReleaseWithoutErasingDurableEvidenceOrOtherDrafts` 连续3次manual与3次timer，首个写失败后保留、成功释放，其他草稿一直存在；saved operation、按ID正式详情和重复saveTimer均检查。正式edit临时输入擦除也验证。原CR04/05、失败关闭重试、Record独立草稿和F5实际读取保护在Unit/UI组合中保持。

CR05原始after-save-landing的空Timer帧属于双sheet关闭动画期间；本人没有把该帧称为有效落点。后续stable-Hub-true像素已回到有内容的“时间投入”，测试等待并核对正式事实恰好一条。这个短暂引用/动画符合Goal允许的边界，未发现稳定空页复发。

### SR-07 / P3：明确收尾完成，全部变体和反馈语义有证据

周/月HabitOverviewRow复用ModuleEntryRow，daily once/multiple沿既有同列结构；没有硬定不同行相同高度。mixed测试补入multiple/week/month且实际点多次+1和周/月详情，检查44pt动作（只给CGFloat表示误差1e-6余量）。已看默认Light、中文Dark最大AX的实际像素：daily once/multiple、周/月长名称图标和标题/副标题列，内容自然分行，周/月check动作在独立行。Growth中文Dark与原模块链亦核对。

Sleep和ImportantDay底部“Got it/知道了”仅清message或savedImportantDayID，未调用关闭提醒；外部路由Dismiss的丢弃pending语义未改。Sleep UI收起后仍保留23:00、随后冷启CRUD；ImportantDay UI先启用onDay=1再收起反馈、关联Entry/冷启，最终通过。ImportantDay开关的实际截图与原失败帧已看；反馈点击和不改变事实的依据为源码及原日志/完整UI断言，不声称独立看过不存在的专用反馈截图。Weight历史连续性说明改为所选截止日/前一天，中英文资源均在。实际VoiceOver仍留D4。

### BV-01：CONFIRMED_AND_FIXED，有界读取结论成立

原 `bv01-probe.log` 明确可见和切离各actualFetches=2、weightModels=20000、sleepModels=20000、mainProbe=true，来自真实UIHostingController/TabView挂载的生产Growth、10k+10k数据、实际Service草稿+正常checkpoint，并非事件次数估算。最终 `final-unit1.log:93/95` 同条件均0。

最终Growth仅在通知持久标识全部为InvestmentOperation/Session时跳过；活动/参与者metadata、Weight/Sleep/习惯/目标/日子、未知格式、空payload、批量失效都保守刷新，失败counts=nil并显示Retry，未伪零。正式Weight新增删除和活动新增走真实刷新；跨日跨区依靠significantTimeChange/active/onAppear原入口。Session在当前Growth入口只影响活动数之外的正式投入事实，因此跳过Session本身不漏当前入口计数。

必须保留真实中间缺陷：`green-e` 4PASS/1FAIL为host crash，不是测试断言或环境偶发被跳过。本人读了原ips，主线程栈明确为旧 `GrowthEntryCounts.needsRefresh(_:container:)` 的HabitViews.swift:84→GrowthView.onReceive，位于延迟RunLoop接收路径。最终过滤器不读notification.object、不解引用sender ModelContext/container，只读取值类型persistent identifier与entityName，移除了同因访问。随后受影响组合与一次完整557 Unit通过；未声称仅凭一次局部重跑就证明一切寿命竞态不存在。

没有把读取量直接外推成真机已卡顿，性能结论限本次混合规模和当前消费者。

### BV-02：CONFIRMED_AND_FIXED，旧异常保留与正常备份诚实区分

原 `green-c.log:47–50`：inf和溢出1e999经正式服务保存、磁盘重开仍inf，实际export在habitLogs.quantity JSON编码失败；NaN被SQLite归一为nil且export PASS，2.5正常。不能把NaN也写成“重开仍NaN”。

最终详细输入parser和普通/带心得checkIn都在写前validate finite；final-unit原探针显示三种新异常saved=false，finite保存/导出正常。`testSystemBV02RejectsNonfiniteBeforeSaveAndPreservesOldInvalidFactInRawRecovery` 验证无异常Log/Entry写入、finite实际ZIP恢复；随后重建已证实的旧inf事实，普通export typed失败，不跳过quantity/整条日志假称完整备份。用户可明确准备独立raw支持恢复包，提取SQLite重开核对ID/infinity bitPattern/unit/result，源事实不变。该包不是可直接导入的普通备份，未许诺自动纠正或恢复已经被SQLite丢失的NaN。没有为编码成功静默删历史或更改schema。

## 3. 实际读取的证据层级、分轮与复用

本机证据根 `/tmp/pgos-pr13-system-evidence`。本人没有重新运行产品测试；独立动作是读源码、现存原日志、xcresulttool解析、图片像素、plist和实际二进制。xcrun xcresulttool只读取现有结果，不触发Xcode或模拟器。

- 逐条解析system-runs全部run记录（完整command、sourceHead、dirty、exit、summary），重新SHA256核对其108个record/log/raw-summary文件，0不匹配。大xcresult本身未声称计算目录整体hash。
- 直接调用 `xcrun xcresulttool get test-results summary --path ...` 读取final-unit1、final-ui1、final-ui2及green-e；同时读取原日志结尾、全部新selector的实际PASS行、BV和F5计数、红例与UI失败段。并非只读仓库“全部PASS”说明。
- red-a=1PASS/2FAIL（旧nil及1000→1），red-b=2PASS/2FAIL（业务日/未来事实），red-c=0PASS/1FAIL（主执行器barrier）；阶段green与编译失败保留，不混入最终次数。red快照TodoFoundation、TodoReminders、ExternalCaptureImport逐字等于固定基线；Weight/Weekly快照为适配新测试签名的等价旧行为，实际读到formatter仍两位+分组、Weekly新参数未使用，故不把它们冒称完全未改的旧源码编译。
- final-unit1：00b clean，一次whole `PersonalGrowthOSTests`，557=556PASS/0FAIL/1SKIP，exit0，49.545秒。唯一SKIP是 `TodoFoundationTests/testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure`，原日志1837行明确需要独立32MB HFS+镜像；没有以填满主盘替代。
- final-ui1：00b clean，21=18PASS/3FAIL，exit65。三错原AX/日志、视频导出附件保留。本人查看原层级文本及提取帧：Todo反馈遮行，ImportantDay开关滑到导航栏区域后误点Save而返回列表，Investment中心滑动拨动日期wheel至六月，测试尚未抵达分段操作。
- c55仅改三个驱动：Todo收反馈并等待详情，ImportantDay整行避开导航/键盘后点击并保留onDay=1，Investment用已有侧边避wheel手势；没有删complete/skip/Stop/restart计数、提醒启用/关联Entry或分段保留/取消/明确替换/冷启统计断言。final-ui2在c55 clean完整补跑三个失败方法+相邻拒绝权限反馈，4PASS/0FAIL，exit0。不能拼称“一次21项全绿”。
- 本人通过Git直接比较00b与c55的PersonalGrowthOS和PersonalGrowthOSTests目录tree，完全相同；再独立逐项提取21个测试方法区域，恰为18个未变/3个变化，和reuse proof一致，且相关shared helper未在最终diff变化。因此复用whole Unit和18个UI的实际结果有源码依据，未为只改驱动/Markdown无理由重跑Unit。
- 已读最终Debug/Release原命令/日志与构建产物：final-debug2 c55 clean `build-for-testing` exit0；final-release1 c55 clean unsigned generic iOS build exit0，42.5秒。环境由原记录为macOS27.0.1、Xcode27.1/SDK27.1、专用iPhone18Pro模拟器iOS27.0；这是原执行环境，未声称用真机复验。

F5本轮原日志还有 `REVIEW_F5_CHAIN factDecoded=10000 operationBatchDecoded=10000 initialFactFetches=40 initialOperationFetches=40 afterDraftAndTimerFactFetches=40 afterDraftAndTimerOperationFetches=40 afterDraftAndTimerFactDecoded=10000 operationIDDecoded=9`，说明原Service→事件→同Workspace保护仍执行；不把Growth的新观察与Workspace这组计数混为一件事。

### 附件与像素范围

重新核对final-ui1/2各manifest及final-attachment-map：179项附件、95PNG，所有179文件SHA256匹配。本人实际看19张代表图/提取帧，未声称逐张看95张或播放全部MP4：默认mixed Today；中文Dark最大AX daily once/multiple/week/month和Growth；Weekly当前未来排除与历史周日；Weight72.345日期-only重开；CR05失败输入、瞬时landing和stable Hub；ImportantDay完整开关及原fail15/19/21；Todo原fail25；ExternalR3两选择确认与25分钟冷启统计；另看mixed旧失败末帧。图像均来自现有本机证据，没有修改或重绘。

特别可追溯代表（目录相对证据根）：

- `final-ui1-attachments/C32990AE-1CC7-4F0A-8F2B-BC0C4CAA7FF7.png` daily once/multiple，`216E444A-B6D7-4DB1-85F5-848547D929D0.png` week，`C515E98C-7059-4902-885F-693F40943A5A.png` month：像素为真实黑底、中文最大AX；文字和动作按自然多屏查看。
- `E9ADEF34-E414-4D25-B2B7-B7AB5500EDB0.png` 历史周；`CC4BA5E5-4FDC-4D37-A1C5-3D5CAFE840BE.png` 当前周；`8FD1A6F8-EFD4-441D-99C8-53DF2B097FC1.png` CR05稳定Hub。
- `final-ui2-attachments/995CBB71-EC5D-4EFA-B020-DD4622730B90.png` 开关完整避遮挡；`8F1AE9BF-860A-479D-A08F-7580A1889941.png` 两种分段选择；`5B7210B9-B5CA-4D8E-B6B1-433B5261E95A.png` 冷启25分钟。

### 实包直接核对

直接读取 `/tmp/pgos-pr13-fix-derived/Build/Products/Debug-iphonesimulator/PersonalGrowthOS.app` 和 `/tmp/pgos-pr13-fix-release/Build/Products/Release-iphoneos/PersonalGrowthOS.app`，不是只读proof声称：

- 两套App/Share/Widget实际Info.plist均原ID `com.yocruzer.PersonalGrowthOS` / `.ShareExtension` / `.ImportantDaysWidget`，1.0(7)、MinimumOS17.0。
- 两App实际BuildProvenance.plist均完整c55、Dirty=false、Source=localGit、Tag空。
- 实际中英文InfoPlist.strings和用途说明存在；对Debug业务dylib、Release executable重新 `otool -l`，均见 `LC_LOAD_WEAK_DYLIB` 指向AlarmKit。
- 六个executable以及Debug所有相应dylib重新SHA256，与两份bundle proof全匹配。Release App `aab2e40436080a78176068fe99c84113f8f959cf5964945071db712719c55be8`，Debug业务dylib `07be5c9f6284a93ef06ec288f3e33fac189977c4f3cd7d7a8bfb28227a70e3de`。

关键原始文件SHA256：

| 文件 | SHA256 |
| --- | --- |
| system-runs.json | `5892f22ab41ec711ddb8de7d1db512dffa70a59d1adb646341bd3160932fe125` |
| final-unit1.log | `66f23b9ec16027b807c6ebdb45e15e5e0aa8e731e3b8ff7c4f78c931aad99400` |
| final-ui1.log | `bdf2e73c4c221a76c8d242e6c5408c5757238e312cbae7a61769d53008461c6f` |
| final-ui2.log | `f5b10a9cc7aca004ba08e62345c3f2c1931b1a9a254273412e8e2d2a97e8161c` |
| final-debug2.log | `6985a7257a8a9f1f483db0d2aba5c3ab0f878e01d485e3281ae25c7f0da9a8e6` |
| final-release1.log | `f618b7b313ee65018d929fa10f794f65cd4b641da40d4b89e9fb29a7faff1d81` |
| green-e-crash.ips | `61e9abc6c96b31bf55e0fde0748efb414988e8ce793f73e498d34d4a3ddaf381` |
| final-attachment-map.json | `41118144f00d6dc2ab7aaf01659303a5ddfb163fa669d889d4415de6d0960b42` |
| final-evidence-reuse-proof.json | `952ffd30f9510f28e8edcf6b5000ccc0a238b94e5232a2d4e735ad724eff2e57` |

## 4. 剩余问题与交接边界

本次独立审查没有新增confirmed缺陷，因而没有虚构优先级/源行/可达序列清单。已确认的历史SR与BV按第2节具体源点、生产序列及正反证关闭；green-e真实新增crash与首轮UI三个FAIL均明确保留并有最终处置，未降成“未发生”。本轮明确P3 SR-06成功缓存和SR-07同类UI/反馈均完成，没有将它们静默移到未来债务。

剩余状态继续原样：D1–D4 **NOT_PASSED**；AlarmKit原生正向 **NOT_RUN**；Public Share **FAIL/environment**；unsigned Safari **FAIL**；物理低空间 **SKIP/NOT_RUN**；远端CI **NOT_RUN**。没有重新执行签名安装、不卸载升级、私人库/私人设备、Archive、tag、TestFlight、merge或force push。fake、模拟器、直接intent和unsigned包不能填这些门为PASS。

本结论支持固定c55候选的本地修复交付与后续Owner另行授权设备门；它是有限范围的独立代码/证据审查，不是对未知数据组合或所有设备不存在缺陷的保证。报告写定后请原文追加，不由实施者改写独立结论。


## 2026-10-19 外部集成边界复核补充 — LOCAL_REVIEW_FIX_REQUIRED

新的独立完整报告见 [INTEGRATION_REVIEW](USAGE_REMEDIATION_20261019_INTEGRATION_REVIEW_ZH.md)，固定产品/测试c55dc10fde79f1fe4dec18b03195119c2049830f、交付c1fe56477f2573930a65a95c46d4b7ab7296d6af。该报告按提醒、持久化/异步、事实/界面并行阅读，主审交叉反证；未编写本轮产品、未在Linux运行原生测试或读取开发机原始大产物。源码及测试设计结论不能冒称新native PASS。

确认IR01～04四项P2和IR05一项P3测试收尾，无P0/P1。原始raw导出的SQLite写竞争列为V01必须有界验证，尚未确认卡顿；Weekly活动页周身份O01保持非阻断UNCONFIRMED。完整合法起点、源码、现有测试为何不足、修复边界及已认可矩阵均在新报告中。

本次更新当前本地放行判断，不覆盖或代写上方开发机独立reviewer原文，不把旧通过/失败改成不存在。SR02/03主体、SR06/07、BV01过滤和BV02原值保留等继续作为保护；IR01/02补SR01完整集成，IR03补SR05页面寿命，IR04补SR04旧调用方失败落点，IR05补新夹具稳定性。

Owner已批准 [新Goal](USAGE_REMEDIATION_20261019_INTEGRATION_FIX_GOAL_ZH.md) 的连续本地修复。实施和新原生回归仍待执行；不能以这次文档交付关闭IR/V或恢复READY。后续独立审查原文及最终证据另追加，D1–D4和设备/环境/发布边界保持。


## 2026-10-19 集成边界修复独立预审：反例预登记

审查者：`/root/integration_independent_reviewer`。未参与本轮实现，保持只读，未运行 Xcode、模拟器或产品测试。本次先读取固定规格提交 `b495bead6c9910ec1e15631227c1146176819583` 中完整 INTEGRATION_FIX_GOAL / INTEGRATION_REVIEW，再按 AGENTS 阅读 INDEX、现有 Foundation、Development Contract、CURRENT 最新章节，检查现有 AppShell、ReminderFoundation、TodoFoundation / TodoReminders / TodoAlarmReminders、InvestmentViews、raw capture、Weekly 和 Growth 测试链。此文在收到实现者关闭表之前形成，不构成修复通过结论；之后终审需绑定固定候选与本机原始证据。

### 预登记不变量与合法反例

1. **IR-01：事件反馈必须静默收敛，同时真实变化仍通知。** 权威是持久 Todo/Series/偏好及真实事实变化。消费者包含 AppShell 的 todoTasksChanged / importantDaysChanged / significantTimeChange / day-change 订阅、TodoReminderCoordinator 的 generation、共享 NotificationMutationGate、Todo/ImportantDay/Sleep 状态，以及等待中的 daily/weekly scheduler。分别从当前显式 offset→Stop→切区、真实 V11 nil→Stop→切区、旧 f1 合法多次覆盖形成 active unresolved→切区出发；观察实际生产事件桥，不能只直接 await coordinator 一次。异步 permission/query barrier 要让反馈 Task 确实运行，断言最后一次必要事件之后事件/轮数不再增长，三健康类别能发布，gate waiter 能完成。相反正例：健康任务跨区确有变化必须恰当地保存/通知；混合数据首轮修改后第二轮静默；外部 mutation 在 await 中到达必须淘汰旧 generation；保存失败不能留下半写事实，释放后仍可重试。不得以改 stopped 字段、猜 unresolved offset 或关闭订阅消除循环。

2. **IR-02：隔离是两个渠道对既有未来 ownership 的实际处理。** 权威同时包含当前规则、intent generation、durable device journal 和 native 存在性，任何一项不能被状态文案替代。消费者包含 retireObsoleteRequests、rebalanceNotifications、reconcile、status/display snapshot、冷 coordinator、显式 futureSeries 编辑与健康同队列。需用真实 V11/旧 f1 行为分别生成 Notification/Alarm 的合法 nil+多次覆盖，再以同一真实 scheduler/client 建 accepted future，切区后隔离。预登记三个可区分失败点：取消前 phase journal 不落盘、native cancel 失败/仍存在、native 已不存在但确认 journal 不落盘；每种失败后必须查实际 native 与持久身份，不能只在内存看到 cancellationPending。代表序列须经过冷重开再次核对，确认缺席后才仅显示纠正规则。明确 futureSeries 纠正后必须出现新的实际请求及正确 generation/phase；普通标题/清单编辑、普通刷新不得让系统 Stop/retired 复活。相反正例包括正常已到点仍 ringing Alarm、停止/已消费、原容量取消等待恢复与健康 Todo/ImportantDay/Sleep 同队列。不能借用 capacity reason 让纠正前自动重排，也不能把隔离伪记为用户关闭。

3. **IR-03：值相同不等于意图相同，所有出口服从跨页面稳定的 per-channel 所有权。** 消费者包括 MediaStorageView 的 AppStorage enabled/minutes/weekday、permission/error/message、LocalReminderScheduler、共享 gate 与 native daily/weekly 固定 identifier。确定顺序：A 真正进入 addRepeating barrier→Settings 关闭销毁→新 owner B off/on 并回到 A 同值→A success / ordinary error / CancellationError 返回。三种旧出口都不能改 B 偏好和显示，最终系统请求须服从 B。另测 B 明确 off、B 当前真实错误可见、daily/weekly 相互独立，以及无新 B 时旧 A 仍能合法完成。仅关闭时 cancel 不足，不能形成偏好 true 却没有合法请求的稳定状态；必须同时检查旧 transport 完成后 gate 中排队的最新 mutation 是否真正执行。参数已变而 onChange 尚未提交的保护仍需保留。至少一条实际 Settings 关闭/重开接线证据，不能只有共享 helper 双实例测试。

4. **IR-04：busy/保存错误不终结活动 ID 所有的名称草稿。** 消费者包含活动行编辑入口、真实 form 呈现/关闭 binding、InvestmentService.updateActivity、workspace refresh/缓存、ExternalCaptureImporter scan/consume 的 StorePublication 及成功后的正式列表。自然反例是 A 输入 B 后，前台真实 importer 取得发布锁并停在 checkpoint，再点击保存：主响应先于释放、正式仍 A、B 输入在当前表单或明确重试入口可见；释放后真实重试只保存一次并成功关闭。普通保存失败、明确取消、成功、再次打开另一活动都要经实际界面路径核验；私有 State 暂时存着 B 但用户不可达仍属失败。相反保护是 create/start/正式 session editor 成功后仍正常释放，saved operation 幂等与 Record 独立草稿不被回退；archive/restore 若沿同一编辑表单，也应检查失败后是否意外关闭或串用名称。

5. **IR-05：测试日历和截止时钟须成为真实读者共同输入。** BV-01 以固定 LA 午夜 00:30、明确 calendar 按自然日构造 10000 个不同 wakeDay，跨 DST；Weight/Sleep 唯一日与 Growth 实际按日读取必须一致。继续挂载真实 Growth，真实 Investment Service→didSave，在可见与切离状态都检查 actual reader fetch/decode；正式 Weight 增/删和 activity metadata 必须触发原应触发刷新。Weekly 以固定周一首分钟构造 seed、显式所选周和实际 summary asOf，测试本周/历史周后半段/未来事实排除，推进受控时钟后未来应纳入。慢执行不能改变测试截止；普通 App 不得被 test clock 冻结。测试若只修 seed 而 reader 仍 Date()，反例未关闭；UI 硬编码标题也不构成事实读取证据。O-01 可以同路观察已打开周和未保存文本遇父刷新/跨周，但未证实不得预改产品。

6. **V-01：raw writer 与真实 SwiftData 保存的因果竞争必须被命中。** 入口须为 exportRetainedQuantityData→StartupRetainedData.capture 的真实 BEGIN IMMEDIATE writer 已取得后 barrier；竞争须来自 independent significantTimeChange/Alarm 状态→production reconcile→实际 SwiftData.save，不能用 .active 单链或手写 SQLite save 替代。raw writer 仍持有时记录生产 save-attempt，独立执行器在看到 attempt 后投递 MainActor probe，独立 fail-safe 释放；同时记录 attempt/probe/release/save-result 顺序。probe 在权限 await 前抢先跑不能证明安全，先 await reconcile/save 再 probe 不能证明阻塞。若 probe 只能在释放或内部 timeout 后执行，影响已确认，需同批最小修复并以同一反例补验；若快速失败，必须查无丢失/无误报成功、journal/提醒显示诚实、raw 原 bitPattern/身份/媒体/文件仍保留及锁释放后重试能恢复。最小修复不得删除 raw 冻结互斥或仅把 MainActor save 包进仍在 MainActor 的 Task。最终 VERIFIED_SAFE/DISPROVED 必须明示否定的影响假设；未命中 save 不可关闭。

### 终审所需原始材料

请提供固定产品/测试 SHA、相对固定 Goal 的完整 diff、每条 selector/命令/退出码和 clock/locale、红绿轮次归属、原始 xcresult/日志/代表图/实包路径及哈希。终审将自行读取与复算所需材料，并检查未改调用者和上述合法相反操作；不会以 PASS 总数或实现者关闭表作为覆盖证明。集中完整 Unit、必要关键 UI、干净同候选 Debug/unsigned Release 与实际 App/Share/Widget provenance 要按实际运行轮次报告；旧有效证据只按 blob/方法/依赖配置明确复用，保留全部真实 FAIL/SKIP/NOT_RUN。D1–D4、AlarmKit 正向、Share/Safari、物理低空间与 CI 的原状态不由本次审查改写。

预审结论：上述条目均待固定候选及原生证据终审；此时不支持恢复 READY_FOR_OWNER_DEVICE_GATE。没有新增产品范围，也没有将 O-01 升格为 confirmed。

## 2026-10-19 IF-A 独立阶段复审（非最终终审）

审查者 `/root/integration_independent_reviewer`，未参与实现。本次只读审查固定 checkpoint `cf3d3208206f50f805e252da2f17d42f063a6329` 相对固定 Goal `b495bead6c9910ec1e15631227c1146176819583` 的 IR01～03 完整生产/测试 diff，核对未改的 scheduler gate、cancel/write、status/display、Alarm 系统 adapter 和活动入口。没有运行 Xcode 构建、模拟器或测试；使用 `xcresulttool get test-results summary` 解析既有原始产物。

### 发现：IR02 邻接查询失败仍可打断健康队列（P2，待修复）

`TodoAlarmReminders.swift:297` 中新增的 `if record.phase == .retired, try await !present(record)` 没有局部错误出口。合法序列：真实旧 nil 多次覆盖的 future Alarm 已接受→切区后成功隔离并保存 retired→冷重开→系统 `AlarmManager.shared.alarms` 暂时抛查询错误。开头 `retireObsoleteRequests` 对同一查询失败已捕获为该任务的 `cancellationPending`，但随后 quarantine 对 retired 再次查询时向外抛，`TodoReminderCoordinator.reconcile` 在生成/安排健康三类之前进入全局 catch，清空状态，并将整个轮次标失败。该错误也使当前已知局部 pending 被全局失败覆盖。

这是源码可追踪的生产反例，尚未原生运行。应将此 native 查询失败保留为局部待确认，保持 durable 身份，并补真实生产对账反例：已隔离 retired future Alarm→查询失败→同队列健康 Todo/ImportantDay/Sleep 仍调度且该任务 cancellationPending→查询恢复/冷重开→仅纠正规则提示、不重建旧请求。不能把存储/结构错误一并当局部错误吞掉。

### 已核对证据与当前支持范围

- 直接读取 `/tmp/pgos-pr13-integration-evidence/{red-a,red-b,green-a2,focused-a}.log`、运行 JSON、对应原始 xcresult summary。red-a 为 2 个方法 FAIL（日志 12 断言失败），red-b 为 1 个方法 FAIL（日志 19 断言失败），green-a2 为 6 PASS/0 FAIL/0 SKIP，focused-a 为 45 PASS/0 FAIL/0 SKIP。未将红例改写为通过。
- 逐项复算 source manifest 中 113 个文件 SHA256，并与固定 cf3d320 的 Git 内容比较：focused-a 与 focused-a-build 全部一致；green-a2 只有 `ImportExportRecoveryTests.swift` 不同，后续 focused-a 已包含新增回滚/Stop/ringing 及外部 mutation 加强。后续最终候选仍须重新绑定。
- IR01 的新生产事件桥确由 AppShell 使用，挂载测试使用同一桥；stopped 在候选前排除，active unresolved 在 fresh read context 无变化时不 save/post。挂载序列经过权限 await，验证 1/1/2 个事实事件、健康三类别最终 scheduled、daily waiter 完成；外部编辑与回滚/重试正例存在。当前未发现 IR01 新 confirmed 问题。
- IR03 的 Scope 由 AppShell State 持有，MediaStorage 的新 updater wrapper 共用 root 的 daily/weekly Scope。真实 MediaStorage sheet onDismiss/onAppear 重建及 AppStorage onChange 链已运行，旧普通错误被同值新意图拒绝，最终 native repeating request 存在；双 owner 生产 updater→scheduler→gate 的六出口矩阵补足成功/错误/取消、无 B 合法完成、B off/当前失败及渠道独立。当前未发现 IR03 新 confirmed 问题。
- IR02 的 accepted future 六场景真实持久化、冷容器、新 generation/新 native ID 已直接核对，正常 elapsed Alarm 不被取消、系统 Stop 不复活的对照存在；但没有覆盖上方 retired native 查询失败，故不能据六场景通过关闭完整 IR02 集成。
- 原始 xcresult runtime 为 iOS **27.0** / build **24A434**，SDK/xctestrun 文件名为 27.1。EXECUTION 将环境笼统写成“iOS Simulator 27.1”需区分 SDK 与实际运行 runtime。

阶段结论：IR01/IR03 当前定向证据有效，IR02 仍有本轮范围内 confirmed 源码问题；尚未审核 IF-B/IF-C/最终集中门，不支持恢复 READY_FOR_OWNER_DEVICE_GATE。D1–D4、AlarmKit 正向、Share/Safari、物理低空间、CI 与发行权限边界保持。

## 2026-10-19 PR #13 集成边界修复独立终审

审查者：`/root/integration_independent_reviewer`；未编写本轮产品或测试实现。固定 Goal：`b495bead6c9910ec1e15631227c1146176819583`。固定最终产品/测试候选：`53eeb1d3410630f836bbc3e713c79f9f157a4081`。

**终审结论：支持该固定候选完成本地集成边界修复并恢复 READY_FOR_OWNER_DEVICE_GATE。IR01～05 有直接关闭证据，V01 为 CONFIRMED_AND_FIXED；未发现本轮范围内尚未关闭的 confirmed P0/P1/P2 或明确 P3。** 这是限定范围的本机代码与原始证据审查，不表示设备门、远端 CI 或发行通过。

### 审查顺序和实际读取层级

先于实现者关闭表独立登记不变量、跨边界合法反例与相反操作，原文已存 `independent-counterexamples.md` 并追加 REVIEW。阶段复审实际发现 IR02 retired Alarm 查询失败外抛的邻接 P2，原文保留于 `independent-if-a-review.md`，不是事后代写全通过。本次核对固定候选相对固定 Goal 的完整 diff，逐项阅读修改实现和测试，并追查未改调用者：AppShell/MediaStorage 接线，Todo editor/detail/list/提醒重设、ImportantDay createTodo、scheduler gate、journal cancel/write、display snapshot、Alarm 系统 adapter、Search 同步订阅、Share importer/导入 materialize、Investment checkpoint/editor 及 raw capture 的发布/清理边界。

没有自行启动构建、模拟器或测试；直接读取本机原始日志/运行 JSON，使用 xcresulttool 解析既有 red-a、red-b、review-a-red、focused-b-clock、green-a2、focused-a、red-v01、green-v01、final-unit、final-ui 的原始 xcresult summary。另读取重命名各轮原始日志与最终测试正文。直接查看最终导出的八张代表截图，读取实际 Debug/Release App、Share、Widget 的 Info.plist、BuildProvenance.plist、中英用途说明及可执行文件，并自行执行只读 otool/codesign 检查。未用实现者 PASS 数量替代覆盖判断。

独立复算四份最终 source manifest，每份 142 个文件均与固定 53eeb1d Git 内容一致；复算已登记的 34 轮共 68 个原始 record/log 哈希，以及最终四轮 record/log 哈希。最终 UI 的 18 PNG 加 manifest 共 19 项哈希全部复算一致。旧 green-v01 与最终候选的两处差异已核对为实际 SQLite ROLLBACK 后的释放探针及同方法原图/元数据保护加强，最终完整 Unit 已运行该加强方法。此报告不将未读取的历史大产物冒称重新审过。

### 逐项关闭判断

**IR-01：关闭。** stopped 在刷新候选前排除；active unresolved 在 fresh read context 没有事实变化时不会 save/post。生产 AppShell 与挂载测试使用同一个 TodoReminderEvents。最终完整 Unit 中 `testIntegrationIR01MountedProductionEventBridgeSettlesAndReleasesSettingsGate` 经真实事件订阅和权限 barrier，三个合法起点分别收敛为 1/1/2 个必要事实事件；外部真实编辑仍使旧 generation 失效，健康 Todo/ImportantDay/Sleep 最终 scheduled，daily gate waiter 完成。`testIntegrationIR01StoppedRefreshDoesNotSaveOrPublish` 和真实跨区失败回滚/恢复方法同时通过。没有禁用订阅或改写 stopped 原字段；真实修改保存/事件与事务回滚仍有效。

**IR-02：关闭，包含阶段审查新增反例。** `testIntegrationIR02BothOwnedFutureChannelsCancelConfirmColdReopenAndCorrect` 从真实 V11/可追溯旧 f1 保存链出发，以同一客户端建立两渠道 accepted future；取消前 journal/native cancel/取消后确认三阶段失败逐一检查 native 存在性和 durable 身份，经冷容器确认、显式 futureSeries 纠正后产生新 generation/新 native ID。隔离不再借用容量重排理由，取消未确认优先于局部规则提示。系统 Stop/retired 普通刷新或元数据编辑不复活，已到点仍存在的正常 Alarm 不误取消，原容量取消/确认保护由完整 TodoReminderTests 保持。独立发现的 retired native 查询失败最初确实造成 healthy 三类别失败（review-a-red 1 方法/4 断言 FAIL）；局部 catch 修复后，同一生产对账方法在 focused-b-clock 与最终 Unit 通过，健康三类继续、查询恢复后仅剩待纠正规则且旧 Alarm 未复活。未吞掉持久化或结构错误。

**IR-03：关闭。** 每渠道 Scope 由 AppShell 的稳定 State 持有；MediaStorage 关闭重建后的 wrapper 共用相同 Scope，daily/weekly 独立。实际 MediaStorage sheet 已经过 onDismiss→重开 onAppear→AppStorage off/on 同值提交；旧 A 普通错误不能覆盖新 B，最终实际 repeating request 和 B 偏好保持。双 owner 经真实 updater→scheduler→gate 的成功/普通错误/CancellationError 三种旧出口均被隔离；B 明确 off、B 当前真实失败、无新 B 时 A 合法完成及参数变更先于下次提交的保护全部在最终 Unit 中验证。没有用关闭时无条件 cancel 代替合法完成证明；最终 UI 另验证 daily/weekly 明确关闭跨 relaunch 保持。

**IR-04：关闭。** 新表单按活动 ID 管理输入，busy/普通错误保持可见输入和错误，成功或明确 Cancel 才 dismiss；Archive/Restore 同样只在成功后关闭。最终 UI 实际运行 ExternalCaptureImporter.scan/consume 的 attachment checkpoint 持发布锁→名称 A 改 B→Save busy→输入 B/正式 A/锁 held 同时可见→释放→完整重试成功、持久活动数仍为 1。直接查看 `17C729FC...png`、`1E30C7C7...png`、`C4CE58FC...png`、`0DAED3A5...png`，分别证明 busy、释放后成功、普通错误和不同活动的状态；取消重开不串稿也经完整 UI 方法断言。原 red-rename3 在旧 alert 的 Save 后确实输入不可达；前两轮夹具/AX错误和后续两轮驱动失败保留，未假充产品红例或一次全绿。create/start、正式 editor 成功释放、saved 幂等及 Record 独立草稿未回退，完整 Unit 与 CR05 关键 UI 提供相邻保护。

**IR-05：关闭。** BV01 固定 LA 午夜 2026-10-19 00:30，明确 Gregorian calendar 逐自然日建立 10000 日，原 86400 秒公式在同参数下直接反算仅 9973 日。真实 Growth reader 注入同一 now/zone，仍挂载真实页面并经真实 InvestmentService→didSave；可见和切离均 actualFetches=0，正式 Weight 增删和 activity metadata 的应刷新对照保持。Weekly seed、选周及实际 summary 使用同一受控 clock/zone，周一首分钟当前事实保持同周；任意 live 时间推进不改变测试截止，显式 +180s 后真实未来三事实纳入。最终两个 Weekly UI 方法和真实 reader Unit 均通过；代表图直接显示当前 1 Entry/1 Habit/70kg、推进后 2/2/99kg，以及历史周日 69kg。普通启动仍使用实际 Date()/时区，未改宿主时间或放宽统计断言。

**V-01：CONFIRMED_AND_FIXED。** red-v01 原始记录为 `writer-frozen → production-journal-entry → native-save-held → independent-probe-submitted → probe-failsafe-timeout → release-requested → writer-released → native-save-success → main-probe`。实际入口为 live raw export 的 BEGIN IMMEDIATE 和独立 Alarm 观察回调；生产 journalCommit 确实执行 SwiftData.save，probe 由独立执行器在保存入口之后投递，故该红例证明 MainActor 等 writer 释放，不能解释为前置权限等待或伪 SQLite 保存。

修复复用既有 StorePublication 按真实 store root 的互斥，Todo 事务与 journal commit 在 MainThread try-lock 快速返回 busy；原 SQLite 冻结和媒体发布合同保留。最终加强方法 `testIntegrationV01RawWriterActualAlarmJournalSaveAndIndependentMainProbe` 在完整 Unit 通过，顺序变为 `writer-frozen → production-journal-entry → independent-probe-submitted → main-probe → todo-command-busy-input-retryable → release-requested → writer-released`；互斥阻止 writer 持有期间的 native save，MainActor 在真实 ROLLBACK 前响应，状态诚实 confirmationRequired，显式 Todo 命令未误报成功、事实未变且释放后可重试。raw ZIP 重开保留原 HabitLog ID/Infinity bitPattern/unit/result、Entry/图片 ID 与正文，归档和源图片字节均核对；释放后命令重试和 journal 退役收敛。旧非有限值拒绝/普通备份保护也在本轮完整 Unit 中通过。

对新 mutex 的邻接审查：Todo 内部 transaction 没有嵌套 acquisition；ImportantDay createTodo 不位于另一个 StorePublication 闭包内；导入 materialize 不调用这两个 MainActor 服务；同步 todoTasksChanged 消费者仅只读搜索或启动稍后执行的 MainActor Task，未形成重入等待。worker 继续等待、主线程继续 try-lock，检查取消及 defer 解锁保留；journal 对 save 后报错仍只按持久精确值确认，native 取消与本地确认失败的身份保护未弱化。没有发现需要额外并发架构的证据。

### 集中门、保护范围和限度

固定干净 53eeb1d 上：final-debug-build 的 Debug build-for-testing exit 0；一次 final-unit 共 568=567 PASS/0 FAIL/1 SKIP；final-ui 七个完整关键方法 7/7 PASS；final-release unsigned generic iOS exit 0。原始 Unit/UI runtimeWarnings 均为空。唯一 Unit SKIP 是需要隔离 32MB HFS+ 图的物理低空间方法，未填主卷也未把 SKIP 写成 PASS。环境按原始结果区分为本机 macOS 27.0.1 arm64、Xcode/SDK 27.1、Simulator runtime 27.0 (24A434)。

直接核对 Debug/Release 六个实际 bundle：App/Share/Widget 原身份、1.0(7)、minOS17 均正确；两份 App BuildProvenance 均为完整 53eeb1d、Dirty=false。独立重算六个 executable SHA256 与实包摘要相符；直接 otool 确认 Debug 主 dylib 与 Release App 的 AlarmKit 为 LC_LOAD_WEAK_DYLIB，中英 NSAlarmKitUsageDescription 存在；直接 codesign 检查 Release 三个 bundle 均未签名。没有安装或发行操作。

已认可 SR02 无损编辑、SR03 事实/业务日主体、SR06 成功缓存释放、SR07 共同布局、BV01 限定失效与 BV02 原值保留未被重做。完整 Unit 覆盖既有旧 nil/迁移/恢复/回滚/取消/容量/停止、checkpoint/晚 pause-finish、editor 与 F5 读数等保护；关键 UI 还覆盖重复 Todo Stop/单 open、Settings 关闭及 CR05 中英 Light/Dark 最大字保存落点。Dark marker 的实际切换/恢复记录与直接查看的中文深色大字号截图相符。本次不把先前失败轮次拼接成一次全绿，不要求为无影响的旧 UI/纯文档交付重新跑产品。

O01 未取得已打开 Weekly 跨周/父重建丢输入的原生反例，保持 UNCONFIRMED/非阻断；没有据此预改导航产品。D1–D4 仍 NOT_PASSED，AlarmKit 原生正向 NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间 SKIP/NOT_RUN、远端 CI NOT_RUN 保持。本地结论不外推为这些门通过，也不授权私人设备/库、签名安装、merge、force push、tag、Archive 或 TestFlight。

该固定候选的本地必要修复、集中验证和独立终审已具备。之后纯文档交付可原样追加本审查，不需要重建同一产品；PR Draft/base、普通推送和最终交付 SHA 仍由实施者按实际 Git/远端状态核对，不能由本报告先行宣称已完成。


## 2026-10-19 TERMINAL_FIX — TF-A / FIXES_IN_PROGRESS

固定 Goal `6430a8570ce2d3528c37d491c1252f97066e8da9` 已全文读取；沿原 worktree/分支、唯一 PR #13 连续 TF-A→TF-D。旧运行记录原样保留，不转记本轮 PASS。

- RR-01：真实 V11 nil → 旧 f1 普通编辑（override=false）→ accepted 两渠道 → 升级隔离/取消确认 → 同值同渠道明确应用未来 → 新请求/冷重开；相反操作覆盖 Stop、未确认取消、普通元数据和幂等重试。
- IC-02：真实旧08:00 pending → 设置改09:00/add挂起 → sheet实际移除且无B → 当前错误 → settle/重开核对偏好/native/反馈；对照成功、新B同/异值/关闭、daily/weekly独立及清理未确认。
- RR-02：真实 SleepService 次日目标 → 时钟跨生效日 → raw BEGIN IMMEDIATE held → refresh→observe→SwiftData.save → 独立MainActor probe/可靠释放 → 事实/回滚/恢复；相反操作覆盖无竞争、回拨和等待后规则变化。

尚未运行本轮红例、修复或最终验证；独立预审和原生证据随后原样追加。O-01 不重复开项。


# PR #13 终态一致性补修独立预审原文

审查者：/root/terminal_independent_reviewer。未参与实现，只读源码/测试/规格，未修改共享仓库产品或测试。固定规格6430a8570ce2d3528c37d491c1252f97066e8da9，预审生产基线53eeb1d3410630f836bbc3e713c79f9f157a4081；当前工作树的两份CURRENT/EXECUTION/ACCEPTANCE/REVIEW仅接收规格边界。已按INDEX检查Foundation、Contract、CURRENT、完整Goal和相关生产链。以下是待实验的反例与验收前置条件，不能当作新的原生FAIL/PASS。

## RR-01：确认的源码缺口及最小可证伪链

合法起点：真实V11 nil reminderDayOffset系列，旧f1普通edit改本次提醒但不应用未来，intent仍isInstanceOverride=false；先经真实TodoIntentScheduling完成future native accepted。升级、跨区调用TodoReminderCoordinator→refreshRepeatingReminderTimes→reminderOffset对歧义规则拒绝→quarantineFutureRequests，两渠道旧请求应先真正取消且durable retired仍属于G。用户保持相同remindAt和channel，经TodoEditorView.save的futureSeries=true明确纠正规则。现setIntent只有reminderChanged/channel/override变化才续代，本例均false；retired同G阻止reconcile，错误终态为规则已补齐、编辑保存成功，但实际native请求不存在。

现有testIntegrationIR02BothOwnedFutureChannelsCancelConfirmColdReopenAndCorrect从override=true且改fireAt，不能区分本缺口。新反例需保留真实旧事件因果，而非直接手设retired/false。

期待终态：旧所有权确认取消前不能并行新增；确认后新G'/native ID确实pending，任务计划/截止/历史事件原字节不被重写。冷容器重开、再刷新、同值再保存不继续续代。需成对覆盖false/true、同值/改值、Notification/Alarm。旧deleteList导致rule.updatedAt变化为邻接合法起点，应说明覆盖或给出具体无影响依据。

相反操作：正常System Stop留下retired后，普通标题/备注/清单修改、普通刷新、已知健康futureSeries元数据修改不能复活；stopSeries/完成/取消/删除不能复活；ringing仍保持。纠正保存抛错要回滚policy+intent+events，重试后只一次有效续代；取消未确认时先纠正，再取消成功的次序不能丢旧所有权或重复排程。若恢复标记仅以nil→known判定，应检查它确实对应一次明确future意图，且不误将健康nil首次可推导修补等同主动恢复。

## IC-02：完整页面反例必须包含旧请求

合法起点：生产LocalReminderScheduler先成功建立08:00 repeating pending；真实MediaStorageView启用且显示08:00。改09:00触发onChange→共享ReminderSettingsUpdate.Scope→真实scheduler获得NotificationMutationGate并在外部addRepeating挂起。实际sheet dismiss并等onDismiss，未创建B；外部返回普通throws且保留旧08:00。现catch只在已移除View中设置AppStorage enabled=false及View本地reminderMessage，依赖已移除onChange完成清理，疑似最终开关false/native08:00仍在/错误不可见。必须daily、weekly都在真实挂载链跑并等待settle、重开，再断言偏好/native时间/错误可见。现IR03挂载测试创建B且没有旧08:00作为pending起点，只证明过期错误隔离。

期待终态任选最小一致策略：关闭偏好则实际撤销并确认native不存在，或保留可证明旧配置并明确失败；不能显示09:00实际08:00。错误/清理反馈需要稳定owner留到重开，不只旧View @State。remove无throws不代表删除已确认：stub remove后pending不消失时，要诚实待确认/可重试，不能返回removed。

相反操作：无B旧成功仍合法完成；无B CancellationError不误关闭；新B同值/不同值/关闭时，旧error/success/cancel不能改B偏好或抢删B固定identifier；旧失败若已经开始await清理，B插入并抢占前后都需检查当前generation，清理与system gate遵守同一序列。daily与weekly互不改写。失败后的显式重试能真正排程或关闭，不能只改反馈字段。

## RR-02：结构缺口不等同已测原生阻塞

合法起点：真实SleepService.setGoal先产生已生效初始规则，再设未来待生效规则；业务时钟推进生效日。真实exportRetainedQuantityData detached worker持同root StorePublication并进入BEGIN IMMEDIATE frozen。调用前台实际路径SleepWorkspace.refresh→SleepGoalSemantics.observe→fresh ModelContext.save，after保存入口由独立执行器提交MainActor probe，独立fail-safe负责释放writer。必须证明待生效规则命中且会save，记录writer-held/observe-save入口/probe提交和执行/save结果/ROLLBACK释放/冷读hasTakenEffect及后续恢复的因果与时长。

现observe直接context.save、refresh所有错误corrupt；未接同锁是源码事实，未经上述实验不能声称原生卡顿已复现。旧V01 Todo journal实验不能替代。

若证实，最小同锁保护应main thread try-lock及时busy，后台完整snapshot仍持锁；延后恢复要等待后重读fresh权威规则，不能持旧ModelContext/rules跨await。检查sleep记录/草稿保留、busy不冒充corrupt、锁释放后自动可靠恢复、无无限retry/重复事件。规则已经对用户生效后遇跨区/回拨不可重新成为可编辑历史；持锁期间再修改规则/删除或改目标的合法相反次序也需覆盖。

只核对raw导出时可达自动入口：根.task/active先investmentCheckpoint、sleepRefresh再await share import；Todo时区refresh通过TodoTaskService.transaction同StorePublication，journal通过write同StorePublication；Sleep observe当前缺口；Investment.transaction同锁并Workspace.enqueueCheckpoint异步等待后fresh读取；Share importer detached worker同mediaRoot锁且无await持lease。Widget重建需确认只读业务事实及写出文件与raw媒体互不污染。Sleep手工save/setGoal/delete不是自动入口，但如果同因修复只包observe，需说明export期间原sheet是否可达操作，以及是否落入授权同因范围，不能只按函数名忽略。

保护证据包括raw源SQLite/图片字节、nonfinite quantity bitPattern/ID/unit/result、原Todo V01、Investment晚暂停/完成与无竞争sleep生效。不触碰O-01导航，无新增confirmed证据时保持非阻断。

## 固定候选终审要求

后续固定clean产品/测试SHA后审完整相关diff、未改调用者与上列起点/终态/反向操作；直接读取本机raw xcresult/log/关键图/Debug及unsigned Release实包，复算manifest和SHA关系，保留原FAIL/SKIP及补验。full Unit不能只报告总数，需确认唯一skip原因及本轮selector实际执行；关键UI或真实挂载覆盖页面移除/错误重开/同值编辑器。检查实际App/Share/Widget身份、版本、minOS、provenance Dirty=false与完整SHA、AlarmKit弱链接与用途说明。未独立读取的证据不包装为reviewer已验。

预审结论：RR-01源码缺口成立，IC-02需要真实关闭页面合同反例，RR-02原生结果待跑；当前不能READY。阶段可连续推进，不需要Owner逐段确认。


# TF-B 独立阶段审查（非终审）

审查者 /root/terminal_independent_reviewer，未写实现。直接读取 dirty diff 与 /tmp/pgos-pr13-terminal-evidence/red-chains.log；未将尚未固定候选的结果当作终审。

红例原日志显示3完整方法均FAIL，共19断言失败。IC02 daily/weekly均真实sheet关闭无B，旧08:00留存；RR01首次同值纠正scheduled、generation、native数量断言失败，末尾PGOS_RR01 nativeCount=1是更多重试以后，不能用于否定首个终态失败；RR02实际序列writer-frozen→production-observe-entry→independent-probe-submitted→native-save-held→probe-failsafe-timeout→release-requested→writer-released→marker-durable-after-refresh→main-probe，支持真实主线程等待已确认。xcresulttool summary直接读取尝试因TestReport内部缓存写权限失败，终审需独立副本读取原始bundle，不修改源bundle。

当前修复思路：RR01严格限定futureSeries/open/live nil且原policy不可推导，才same-value续代并重编码当前wall time，方向符合要求；IC02 root Scope存储feedback，当前ticket在shared gate内重查并实际确认删除，方向符合要求；RR02 fence仅保存rule ID/观察instant，try同锁并fresh context合并，避免旧模型跨await，setGoal先flush防回拨，方向符合要求。

## 需闭环的具体源码遗漏

SleepWorkspace deferred retry获取waitUntilAvailable lease后立即释放，再回MainActor执行refresh(deferBusy:false)。raw释放时另一个已等待的Share importer或另一导出可以先拿同锁，因此实际refresh第二次得到busy。当前catch guard deferBusy=false直接返回，publicationRetry已nil，无新等待。真实根active调用顺序sleep.refresh→await importShares→widget/todo，没有import后第二次sleep.refresh；故一次合法active结束且全部锁最终释放后marker仍可能不持久、busy错误永久保留到额外用户动作，未满足可靠恢复。

最小建议：保留coalesced pending refresh请求，在真实busy时继续异步等待同锁（不是主线程等待或轮询），确保每次先重读权威状态；或使用能保证fresh保存和等待之间无抢占的同锁后台值协议。覆盖第二持锁者在waiter完成与main refresh间抢占的确定性测试，断言最终不用用户第二次刷新即marker持久且错误清除。避免为了无无限retry要求而丢弃一次真实busy；所有等待必须具有取消/释放保证。

## 后续证据提醒

RR01还需旧deleteList邻接起点、保存失败回滚、取消未确认时先纠正、正常Stop/元数据不复活及真实编辑器同值入口；IC02需remove不生效的cleanupPending可重试、重开可见反馈，及旧恢复清理期间B同值/改值/关闭保护；RR02需hold内已观察生效后先回拨/再setGoal、后释放的相反操作。现dirty测试还没有完整覆盖这些验收，不能仅三项green放行。


## TERMINAL_FIX 固定744e772独立终审原文

# PR #13 终态一致性补修独立终审原文

审查者：`/root/terminal_independent_reviewer`。我未参与本轮产品或测试实现，仅只读审查并将原文/独立审计副本写入 `/tmp`。固定授权规格为 `6430a8570ce2d3528c37d491c1252f97066e8da9`；最终审查产品/测试候选为 `744e7729f103549184574e99e311ce5c380a4a16`。已直接核对该提交及完整相关差异、未改调用者、原始 log/xcresult、必要实图和实际 Debug/Release 包；没有凭实现者关闭表或 PASS 总数放行。

## 审查过程与新增问题闭环

先独立预登记 RR-01 / IC-02 / RR-02 的合法起点、生产入口、异步/锁边界、终态和相反操作；原文 `/tmp/pgos-pr13-terminal-review-pre.md`，SHA256 `0121b62c6adde124f4979d1c0c3ad0bbde52fa09e259331a7a10674342230b35`。阶段审查独立发现 SleepWorkspace 第一次等待后再次遭遇合法 publisher 时丢失恢复的问题；实现者同批补为仅对真实 busy 合并异步重等，并新增第二 publisher 实际持锁、actual didDefer 后释放、无需额外手动刷新即恢复的确定性验证。阶段原文 `/tmp/pgos-pr13-terminal-review-stage.md`，SHA256 `29bdcded47acf908382114a38216315a09a693245985ab475a6d8385226de5dc`。

终审还亲自导出并查看早期 IC-02 两张图片，发现均为黑图，因此拒绝将其当可见反馈证据。实现者仅修正挂载测试 UIWindowScene/渲染夹具，完整方法补跑；最终候选完整 Unit 再次导出的 daily/weekly 实图均显示关闭开关及对应红字“无法更新提醒，请再试一次。”，布局无截断，证据缺口已关闭。黑图保留为真实无效截图，不追记为旧轮可见 PASS。

## 逐项结论

**RR-01：CONFIRMED_AND_FIXED。** 直接检查原红例，真实 V11 nil 系列经旧 f1 普通编辑形成 override=false、两渠道先 accepted 后隔离取消；首次同值纠正后仍 stopped/同 generation/无新请求的断言失败成立。旧日志末尾 nativeCount=1 是后续更多重试的状态，不能混作首次纠正成功。最终实现只对明确 futureSeries、open/live、nil 且不可推导旧策略续代，成功重试不再换代；当前同一瞬间按当前时区重编码 wall time，避免保存后刷新又改变实际提醒瞬间。最终完整方法经真实 TodoEditorView 加载、仅选择应用未来并调用同一保存入口，保留原时间/渠道，生产排程后客户端 pending 中唯一新请求、计划/截止及旧事件原字节保留、冷容器重开正确。另核对旧 deleteList 邻接起点、整 snapshot 保存失败回滚、未确认旧取消时先纠正不并排、冷开确认后替换、随后 System Stop 与元数据不复活。原 override=true/改值、正常 ringing、停止/完成/取消/删除及容量等待保护随完整 Unit 保留。未把合成外部客户端结果写成真机 AlarmKit 正向验证。

**IC-02：CONFIRMED_AND_FIXED。** 原红例真实 LocalReminderScheduler 先建立08:00旧请求，实际设置页改09:00并在 add 边界挂起，sheet 完全关闭且无 B 后普通错误返回；daily/weekly 均偏好关闭但旧08:00仍在，重开仍在。最终稳定 Scope 拥有当前命令反馈/cleanupPending，恢复在共享 NotificationMutationGate 内检查当前 ticket，查询后再查 ticket，确认请求不存在后收尾，不依赖已移除 View 的 onChange。核对无新 B 当前失败/成功/transport cancel、新 B 同值/改值/关闭、两渠道独立、remove 未生效时诚实待确认及重试、清理 query 已挂起后新 B 抢占的保护；旧 cleaner 不误删 B。最终真实挂载方法偏好 off、pending=0、Scope 错误与实际重开红字均一致。可见反馈证据来自最终 Unit 两图 B759/CEDE；不使用旧黑图支撑。

**RR-02：CONFIRMED_AND_FIXED。** 原 `red-chains` 日志及 xcresult 为3个完整方法均失败；睡眠原生反例实际顺序 `writer-frozen → production-observe-entry → independent-probe-submitted → native-save-held → probe-failsafe-timeout → release-requested → writer-released → main-probe`，真实主线程等待已确认。最终通过同一 raw BEGIN IMMEDIATE writer barrier、实际 refresh/observe 入口、独立执行器 probe 与可靠释放验证；最终 Unit 顺序 probe 在 writer-released 前，持锁时生效标记仍未持久、诚实 busy；回拨后 setGoal 在持锁期间拒绝并保留已观察事实，释放后 fresh context 合并 fence 持久化原生效事实，随后回拨编辑旧历史仍拒绝。第二 publisher 复竞争确实触发 actual didDefer，之后自动恢复为 native-save-free，无手动 refresh，无无限 I/O 错误重试。fence 只保留 ID/观察瞬间，不携旧 ModelContext 或旧规则跨 await。

未改消费者检查：根 `.task`/active 先 checkpoint/refresh 再 share import；Todo 时区事务与 journal 使用相同 StorePublication；Investment transaction 同锁、延后 checkpoint 重读权威操作；Share importer detached worker 同 root lease；Sleep observe 补上同因缺口。手工睡眠编辑不属于导出中可达自动写入口：原设置导出期间 isTransferring 禁止 Done/交互关闭，未额外泛化整个仓储。`setGoal` 因生效 fence 保护而先 flush。旧 V01 Todo raw 竞争、非有限 quantity bitPattern/ID/unit/result、原始图字节、Investment 实际导出/晚暂停完成、正常睡眠生效与回拨保护均由最终完整 Unit 中对应完整方法覆盖。O-01 没有新增证据，保持非阻断 UNCONFIRMED，不重开导航项。

## 原始证据与最终门

本机原始证据根 `/tmp/pgos-pr13-terminal-evidence`。我独立调用 xcresulttool 读取原 red、focused-matrix3、visible-feedback、两次完整 Unit 与最终 UI 的原 bundle（必要时复制到独立 `/tmp` 审计根，xcresulttool 的 TestReport 缓存写权限处理未改变测试）；读取六个 Terminal 方法确实执行且 Passed，核对唯一 SKIP 的具体原文。保留 red 0/3、green 3/3、focused-matrix 与 matrix2 各35/36、matrix3 37/37，以及挂载夹具修正/可见图补验；不将分轮拼称一次全绿。

最终四门均为同一 clean `744e7729f103549184574e99e311ce5c380a4a16`：

- `candidate2-debug-build`：Debug Simulator build-for-testing PASS。
- `candidate2-unit`：53.916秒，574总数 = 573 PASS / 0 FAIL / 1 SKIP，runtimeWarnings为空。唯一 SKIP 为 `testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure`，原因确为需隔离32MB HFS+测试图、不得填满主卷。
- `candidate2-ui`：100.533秒，3/3 PASS、0 SKIP，runtimeWarnings为空。完整方法为重复完成/跳过/停止/冷开、daily/weekly显式关闭冷开、睡眠目标/入口可见性/禁权提醒。前三项新链中的编辑器和设置页生命周期由实际挂载 Unit 完整验证，未机械增加同义 UI。最终 UI 唯一 Sleep PNG 已亲自查看；前两个方法无 PNG 如实记录，不冒称逐图审过。
- `candidate2-release`：43.878秒，unsigned generic iOS Release build PASS，未 Archive。

独立复算19轮 record/log 成对哈希；四份最终 manifest 各142文件完全相同，且逐文件 SHA256 与固定 Git 提交 blob 完全一致。直接读取实际 Debug 与 Release 的 App/Share/Widget 共六包 plist/executable，核对原Bundle ID、1.0(7)、minOS17；两App完整provenance为744e772、Dirty=false。直接运行 otool 检查 App debug dylib/Release executable 的 AlarmKit 为 LC_LOAD_WEAK_DYLIB，中英用途说明存在；直接 codesign -dv 确认Release三包均not signed at all。可见图与附件manifest共8文件哈希亦独立复算。独立审计 `/tmp/pgos-pr13-terminal-review-native/independent-audit-final.json`，SHA256 `7556ed3facb668f1546a0363778221b703a4c8020d50d21f5becb303152c42f0`。

## 终审结论与停点

范围内三项及本审查新增的二次busy恢复、黑图证据问题均已闭环；当前未发现未关闭的 confirmed P0/P1/P2 或本轮明确 P3。支持执行者完成 TF-D 文档交付、普通 commit/push、唯一原 Draft PR #13/base 核对后恢复本地 `READY_FOR_OWNER_DEVICE_GATE`。我没有代执行者声称尚未发生的文档交付或远端 push；交付 SHA 应另外核对，不替换产品/测试 SHA。

READY仅指本地门。D1–D4 NOT_PASSED、AlarmKit原生正向 NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间 SKIP/NOT_RUN、远端CI NOT_RUN继续保留。没有依据将合成客户端/模拟器/unsigned包外推为私人设备、系统实际递送、签名升级或发行通过。原PR/base、已认可历史修复与用户数据边界不变；不操作私人设备/库，不签名安装、merge、force push、tag、Archive或TestFlight。


原文SHA256 `991c9453c63e715c8f9e546d9fb97b0ee43abbbddae5d2293aaba0adbac6364d`。原文由独立reviewer生成，实现者仅原样归档。


## 2026-10-20 TERMINAL_RECHECK 独立预登记

以下原文由未参与实现的 `/root/terminal_recheck_reviewer` 在看到关闭表之前提交；原文件 `/tmp/pgos-pr13-recheck-evidence/reviewer-preflight.md`，SHA256 `36b5bcae182232fc524304fd5690bca57a847403874e12c2bd0e2f6b6afd307c`。终审待固定候选及原始本机证据，不将预审写为READY。

# TC-01～03 独立预登记（2026-10-20）

审查者 `/root/terminal_recheck_reviewer` 未参与本轮产品/测试实现；在收到实现者关闭表之前登记。固定规格 ae92c71e7f4b787456dcaa5ba6f7ea07e91d2627 的 Goal 与 Review 已全文读取；依次阅读 AGENTS、Foundation、Contract 和 CURRENT 最新边界。当前只读审查既有生产链，未执行新原生测试，不将源码推断写为 PASS。

## TC-01：来源对象与受影响对象

生产入口确实允许非 open 来源：TodoEditorView.save 在 futureSeries 且来源非 open 时查开放 successor 并报告。服务 edit 的 correctingPolicy 却限定来源 open，而 applyTemplate 只有 correctingPolicy 或 fireAt 改变才 renew，独立确认规格反例具有区分力。

必须先得到旧 V11 nil offset 的合法链：旧 f1 complete/skip A → B、deleteList → rule.updatedAt 改变、B 原系统 accepted；Shanghai/Hong_Kong 同偏移但 identifier 不同触发 quarantine，确认 B retired/native0。两渠道分别从真实 completed 和 canceled 来源 A 保持相同时间/渠道应用未来，期待 B 新 generation、唯一新 native ID；A 状态/历史/截止/计划/来源关系不复活不损坏。至少一例挂载真实 TodoEditorView 保存，不能只调用 service 或 helper。

相反操作：健康规则的 futureSeries metadata、普通 metadata、已 Stop 系列保持终态；source open 原 RR-01 保留。修复若只删 open guard，也须核实来源本身不会创建可被调度的请求。取消未确认时 B 的旧 ownership 必须保留且不能并排产生新请求；确认后再恢复唯一请求。事务保存失败应恢复 rule offset/updatedAt、A/B intents generation、事件；成功重复提交不得连续换代。冷重开从磁盘读取身份、代次、retired 和 native 独立事实。不同偏移/改值会通过时间变更偶然换代，不能反证同值缺陷。

## TC-02：sheet 寿命与进程寿命

旧 Scope 是纯内存；AppShell .task/.active 只协调 Todo/Sleep/ImportantDay，MediaStorageView 初次 task 不按 off 初值清固定请求。故必须销毁 UIHostingController、AppShell 及 ReminderSettingsIntents，创建新根和新 Scope，保留隔离 UserDefaults suite 与外部 client 原请求。只重开 sheet 或 wrapper 共用 Scope 不成立。

daily/weekly 各自跑旧08→09失败→两次 remove 未确认→off 已保存；冷根在请求仍存在、已不存在、首次再清失败三分支应自动发现/确认或明确可达重试，未确认保持可见。最小 off 启动对账可接受，无需 SwiftData/schema；若用持久责任，不能只落错误字符串，也不能随备份迁移。持久化失败必须诚实保留可见责任。

独立反例：启动清理 pendingIdentifiers await 挂起时，同渠道用户提交同值新 B、异值新 B、明确 off 三类意图。每个 await 后需最新票据检查，gate 获取前后同样检查；过期 A 不能删 B 或发布 A 文案。另一渠道与 Todo/Sleep/ImportantDay/未知 request ID 保留，预算仍共享。denied/notDetermined 不得 requestAuthorization，启动不能开启提醒，无无界轮询。

还需核查未改调用者：AppShell 根 .task/.active、MediaStorageView onChange 与关闭重开、handleReminderResult/失败后自动 off 引发 onChange 的第二次 submit。偏好 off 变化和新 ticket 必须形成一致所有权，不能因新增启动对账反复覆盖当前编辑。

## TC-03：失败与确认成功

同 Scope 与新 Scope 都要覆盖：unconfirmed → confirmed retry → native0、cleanupPending=false、当前“尚未确认”文字消失、Try Again 不再作为死入口。旧 failureMessage 在 success(.removed) 保留的分支可确定重现此错。允许明确历史失败说明，但不能用 pending=false 隐藏按钮却继续显示当前未确认文字。需要真实中文设置页/AX或截图校验，纯字段 helper 不能替代最终 UI。

## 终审门

待固定候选及本机原证据：审产品与测试 diff、上述未改调用者、原 red/green 分轮、xcresult 实数、代表设置/编辑器图与最终 Debug/unsigned Release 三包。独立复算 manifest/hash/provenance、App/Share/Widget IDs、1.0(7)/min17、SHA/Dirty=false、AlarmKit weak 与中英用途；集中 Unit/必要关键 UI 与候选一致。旧 RR-02/IR/Stop/取消/容量/计时/迁移/raw/F5 证据只按依赖不变复用，不要求重做。D1–D4、AlarmKit 正向、Share/Safari、物理低空间、CI 保持既有未通过/未运行。当前不作 READY 结论。


## 2026-10-20 TERMINAL_RECHECK 固定候选独立终审

原文 `/tmp/pgos-pr13-recheck-evidence/reviewer-final.md`，SHA256 `6b75465420b1cfd5043d275ea4c8ba56373f0dddc4cee95cdcf39677e9dbe3f9`；审查者未写本轮产品或测试代码。以下原样追加，不替换预登记或旧轮次。

# TC-01～03 独立终审原文（2026-10-20）

审查者 `/root/terminal_recheck_reviewer` 未参与本轮产品/测试实现；先于实现者关闭表保存独立预登记 `reviewer-preflight.md`（SHA256 `36b5bcae182232fc524304fd5690bca57a847403874e12c2bd0e2f6b6afd307c`）。本次固定 Goal 为 `ae92c71e7f4b787456dcaa5ba6f7ea07e91d2627`，终审产品/测试候选为 `1b150068e76f4d7e7a6defcd51f10622951f4b4b`；最后产品修改包含于 `2b0d4917342d03b0f9e5323a1ef2cf58447953fb`，2b→1b 仅旧 roundtrip 测试增加 disabled synthetic sleepPreferences 一行。直接读 Git 时 HEAD=1b、工作树 clean。本审查仅在本机读取/复算既有运行，不冒称另行重跑产品测试。

## 结论

支持恢复本批本地 `READY_FOR_OWNER_DEVICE_GATE`。TC-01、TC-02 均有具有区分力的生产链红例并完成最小修复，TC-03 成功反馈收尾完成；无本 Goal 范围内未关闭 confirmed P0/P1/P2，明确 P3 已完成。此结论只针对本批本地门和独立终审，不代替 Owner 设备门或发行授权。

## 固定代码及未改调用者

相对固定 Goal，产品只改 ReminderFoundation、AppShell、TodoFoundation 三文件。逐行审查后，规则纠正不再用来源状态代表受影响后继状态；来源的 correction renew 仍限定 open，successor 循环仍限定同系列、较后且 open，已 Stop 规则和可解析健康规则均不进入 correctingPolicy。事务、历史事件、源关联、截止/计划与系统取消 ownership 规则没有被替换。

启动/前台从已持久化 off 偏好重建清理责任，符合最小设备本地对账方案；仅处理 daily/weekly 两个固定 ID，不新增 Schema/备份账本、不申请权限/开启提醒。两渠道共用根 Scope 和 NotificationMutationGate；removeAfterFailure 在 gate 内及 native query 后检查当前票据，submit 在 recover await 后再次检查 generation/取消/最新偏好。updating 仅由当前 token 完成时释放，避免旧任务清新状态。取消或过期启动 A 不能发布错误/成功到新 B。

检查未改调用者包括：TodoEditorView 的实际 save 与 affectedOpenSuccessor 报告、TodoTaskService 的 applyTemplate/setIntent/transaction、TodoIntentScheduling 的 retired/取消确认边界、MediaStorageView 每日/每周 onChange、失败后 off 引发的二次 submit、handleReminderResult、原共享预算及其他类别协调。success(.removed) 仅在当前 cleanupPending 时清当前未确认文案；原已确认清理后的历史更新失败说明仍可保留。上述逻辑与调用者一致，未发现范围内新的 confirmed 问题。

## TC-01 证据

旧 f1 Service 不是改造后 helper：独立从固定 `f1b52b58fd11c41f508ec665d583827879ffa202` 抽取 TodoTaskService 类体，与测试 TerminalRecheckOldF1Service 仅归一类名后逐字相等。本审查 hash 边界是类声明后的首个 `{` 到配对 `}`，不含注解和类名；双方 SHA256 `9b0532bbeb10bc4c340e721115ca66c7fe372bfa785272c496e96d681fbad960`。执行者另存包含 @MainActor/首尾 strip 的 `927023…`，边界不同而非内容矛盾。

真实 V11 nil offset → 旧 f1 完成/跳过 A → B → 旧 deleteList 构成合法前提。两渠道×completed/canceled 四组合先 accepted，生产 refresh(Hong_Kong) 检出等偏移不同 identifier 的不可解析规则，再通过生产 quarantine 隔离；返回原设备区后，从实际 TodoEditorView 同值/同渠道应用未来。`red-a-proper` 的两个方法均 FAIL，stopped/native0/旧代次与目标失败完全对应。更早 `red-chains` 内 TC-01 受 NSTimeZone.default 未改变 .current 的隔离前提失败，不能当 TC-01 产品红例；原记录保持。

最终同方法完整 PASS：B 新代次和唯一 native 请求，旧 ID 不存在；A 原 completed/canceled 状态及来源 generation 不复活，B 原时刻/计划/截止不变，Entry/source 和既有事件保留；重复提交幂等、磁盘冷开、失败全快照回滚、取消未确认仍旧 ownership 且没有第二请求、确认后恢复唯一请求均断言。健康 metadata、System Stop 与 series Stop 相反操作不换代不重排。方法末端 `PGOS_TC01 native=0` 是后续 Stop 负例终态，之前恢复成功的唯一 native=1 由完整方法断言证明；不将该末端打印误读为恢复失败。

## TC-02/03 证据

`red-chains` 独立原生失败包含：完整旧根 daily/weekly Scope 均已释放，新根偏好 off 而旧08:00请求仍存在；同 Scope 确认重试后 pending=false 仍显示中文“尚未确认…”文本。不是只重开 sheet 的测试。

最终 Unit 覆盖 daily/weekly × 冷开请求仍在/已无/首次再清失败三分支。旧 UIHostingController/AppShell/Scope 通过 weak=nil 验证销毁；同隔离 UserDefaults suite 和外部 client 保留，新根实际 .task 自动对账。未确认可见且可重试，随后 confirmed → native0/pending=false/当前未确认文本=nil；denied/notDetermined 零权限申请。实际 AppShell 启动 query 挂起，再经 MediaStorageView onChange 提交同值 B/异值 B/明确 off，2×3组合通过；旧 A 不删新 B，不污染另渠道和其他/未知 ID。helper 级 2×3矩阵为补充，实际根链并未被 helper 替代。

直接查看最终 Unit 导出的六张中文设置图：两种冷根失败保留未确认文案和 Try Again，两种确认成功均展示 daily/weekly off 且当前未确认文案/重试按钮消失；旧 IC-02 重开图继续显示已确认清理后的历史“无法更新提醒”说明。单独重读 daily 成功原图确认两开关完整可见，其与 weekly 成功图像素 hash 相同。我此前在多图合并输出时一度误判 daily 行滚出可见区，已向执行者更正；该误判不是图或产品缺口。另直接查看最终 UI Sleep 实际设置截图，未用黑图替代可见证据。真实 TodoEditorView 保存入口由挂载测试/回调及最终 native 断言证明，没有虚称其额外截图。

## 独立核验与真实失败保留

通过本机 xcrun xcresulttool 直接读取 red-chains、red-a-proper、green-chains、expanded-matrix、focused-matrix、todo-isolation-probe、adjacent-todo 原始结果，逐项与保存摘要比对一致。阶段结果分别为 0/4、0/2、4/4、18/21、22/22、0/1、31/31；真实失败未被改标通过。旧 ImportantDay/Todo 测试的额外 sleep 请求与专用合成模拟器已开启的睡眠偏好相符，测试显式注入 disabled synthetic sleepPreferences，未删除宿主偏好或弱化断言。TodoReminderTests 去掉新增依赖注入后与固定 Goal 逐字相等。

原 2b 完整 Unit 直接读取为 579=577 PASS/1 FAIL/1 SKIP；唯一失败为旧 roundtrip 依赖同类宿主 sleep 偏好，1b 只修该测试依赖，产品三文件不变。最终候选 1b 集中门直接读取：

- 完整 Unit：579=578 PASS/0 FAIL/1 SKIP，runtimeWarnings=[]。跳过节点明确是需隔离32MB HFS+图的物理低空间用例。
- 必要关键 UI：3/3 PASS、0 FAIL/0 SKIP，runtimeWarnings=[]；覆盖每日重复完成/跳过/Stop/Restart、daily/weekly 明确 off 冷重开、睡眠目标/入口/拒绝提醒独立性。UI 仅 Sleep 方法导出一张 PNG，另外两方法无附件，结论由原始 xcresult 与方法断言支持，未声称三方法都有图。
- Debug build-for-testing 和 generic iOS unsigned Release 原始 log 有明确成功标记、运行记录 exit=0，均使用同一 clean 1b 候选。

独立新写只读复算脚本 `reviewer-verify.py` 并执行，输出 `reviewer-final-verification.json`：21轮 record/log及10份摘要共52个 hash 全匹配；最终四份 source manifest 同字节（SHA256 `391c632f1e57e157bcfd794bd717f8989ea355b9cf458eff9331e34ca841f449`），各142文件逐一匹配1b Git blob；三个附件目录共17文件（含manifest）hash匹配。

直接读 Debug/Release 各 App/Widget/Share 六个实包 Info.plist 和二进制，复算 executable/debug dylib hash均与 proof 相符；原 Bundle IDs、1.0(7)、minOS17 保持。两 App 的 BuildProvenance 实为完整1b/Dirty=false/localGit；直接读两 App 中英文 AlarmKit 用途，otool 确认 App实际加载二进制的 AlarmKit 为 LC_LOAD_WEAK_DYLIB。独立 codesign -dv 三个 Release 包均返回未签名。未把 unsigned构建外推为原生AlarmKit正向或设备验证。

RR-02二次busy/fence/回拨、IR事件与取消/Stop/容量、计时checkpoint/pause/finish/F5、迁移/恢复/raw原值等生产相关代码未改；完整 Unit 已覆盖其现有方法，未要求重做 A–D。未受影响旧 UI 只按相应方法/依赖 blob 不变的既有证据复用，不拼成一次历史全绿。

## 保留的外部门禁

D1–D4 NOT_PASSED、AlarmKit 正向 NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间 SKIP/NOT_RUN、远端 CI NOT_RUN 维持。O-01仍非阻断UNCONFIRMED，没有借本批扩大未知观察。没有操作私人设备/库、签名安装、merge、force push、tag、Archive或TestFlight。

上述本地核实支持 TC-01/02关闭与TC-03收尾；后续只需按既有授权完成文档/PR描述与普通交付，不因纯文档变更重建产品。
