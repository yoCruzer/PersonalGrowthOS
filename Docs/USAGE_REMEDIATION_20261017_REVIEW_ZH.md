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
