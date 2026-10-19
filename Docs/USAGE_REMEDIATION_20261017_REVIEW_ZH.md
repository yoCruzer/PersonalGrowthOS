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
