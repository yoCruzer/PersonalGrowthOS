# PR #13 系统审查与多轮修复复盘（2026-10-19）

版本：1.0。审查结论：**SYSTEM_REVIEW_COMPLETE / LOCAL_REVIEW_FIX_REQUIRED**。

本报告由外部审查者根据固定源码、完整相关调用链、测试内容和提交演变形成。审查分工为 Todo／共享提醒、持久化／计时／备份、事实统计／跨模块 UI；主审交叉核对实际入口、失败传播和反证。这里的“确认”指源码与合法操作／接口合同足以推出问题，**不表示在本环境运行过 Xcode、模拟器或真机**。

用户本次授权的是原因复盘、系统 review、在 GitHub 记录，以及准备给 Codex 执行的修复目标。本次交付只修改 Markdown。产品修复和新原生运行尚未执行；执行规格见 [真机前修复 Goal](USAGE_REMEDIATION_20261019_PREDEVICE_FIX_GOAL_ZH.md)。

## 1. 固定对象与证据层级

| 对象 | 固定身份 |
| --- | --- |
| 仓库／PR | yoCruzer/PersonalGrowthOS / [Draft PR #13](https://github.com/yoCruzer/PersonalGrowthOS/pull/13) |
| head 分支 | codex/usage-remediation-20261017 |
| base 分支／BASE | codex/time-investment-v1 / 5a70f0110b151f8a45ac7c33d3f443823b1cff24 |
| 本次已审产品与测试 | c296a3691d53ce7f5b5bff36fbf7de525d86510f |
| 本次已审交付 | 62210d9910bae50acf0d58e6cb928e52a67c4a6f |
| 上一轮已审产品／交付 | 597552a020eab22673feed108d8676359efd8822 / e75ac56110cb9c4f58158eaf494087b2ed946324 |
| 第一批整改产品／交付 | 9601ff211fbdafc954e32f9e25206a38479e972b / f1b52b58fd11c41f508ec665d583827879ffa202 |
| 原始 Goal／上两轮修复 Goal | 68373d4edf10cff8ca3e212b9ff10a28e6da9c73 / 2add10b0c67d064b7e77478fb18a11479d3c94dc / 41ef47c384464823f9456e9816d574ba7edff563 |

审查时远端为上述 62210d9，PR 仍 OPEN Draft、原 base、未 merge。BASE 到 62210d9 的比较包含 30 个提交、52 个变更文件；本次没有把范围局限在最后一轮的 19 个变更文件。源码快照包含全部生产 Swift 和测试 Swift，并以固定 Git blob 核对；同时审查未在最后 diff 中出现的事实消费者、输入入口和共享资源使用方。历史图片附件不可读，不能据此宣称检查过原截图。

证据分层：

- **源码确认**：本报告 SR 项的操作序列、状态条件及调用链；开发端须以实际生产路径的有区分力回归验证修复。
- **既有运行报告**：251 PASS / 0 FAIL / 1 SKIP、UI 分轮 1/1 与 8/8、双构建及实包核对，是仓库记录中的开发端结果。本环境没有读取开发机临时目录中的全部原始 xcresult、截图或二进制，也没有重新执行，不转述为“本次独立跑过”。
- **限定待核验**：BV-01、BV-02 尚有关键运行事实未知，不能预先计为 confirmed P2。
- **原生／环境门**：D1–D4、AlarmKit 正向、Share/Safari、物理低空间、远端 CI 原状态保留。读取提交状态未得到可作为 PASS 的远端 CI 运行。
- “未发现新确认缺陷”只表示本文列明的源码审查范围内没有新增反例，不能扩张为所有设备和所有数据组合已验证。

## 2. 为什么反复出现问题

### 2.1 难度确有差别，主要原因可以改进

原反馈的文案、分类入口、行布局、副标题本身不属于高难度工程。难度较高的部分是已经批准的状态和兼容性组合：日历重复、普通通知与 AlarmKit、共享请求预算和取消账本、真旧 Schema 与备份、计时草稿和正式事实、跨时区统计，以及后台与备份的一致性。

这些组合需要明确不变量，但不能用“复杂”解释已经点名的相同提示文案遗漏，或用原生环境受限解释源码中可确定的前置条件冲突。也没有证据证明某位执行者投入不足或主观敷衍；可判断的是产物与流程覆盖不足。

### 2.2 有证据的原因与责任边界

| 原因 | 实际证据 | 本次应吸取的教训 |
| --- | --- | --- |
| 修复影响分析停在原触发条件附近 | CR-03 为旧 nil 增加“规则时间未变且根证据存在”的恢复条件；c296 又在改期、编辑、切区、删清单前恢复策略，但正式 Stop/delete 会改变同一时间或删根。SR-01 是合法状态组合与新条件冲突 | 新增前置条件时逐一分类全部调用者：继续未来策略、当前事实修改、终止清理、只读展示；不能把一个条件套给所有操作 |
| 新领域口径没有传播到全部使用方 | QuietWins/Habit 使用保存业务日，WeeklySummary 仍按设备时区的 occurredAt；Weight/Today 排除未来，Weekly 仍纳入整周未来体重 | 审查“一个事实被谁消费”，包括没有出现在本轮 diff 的旧页面 |
| 测试以问题编号／函数为单位，缺少完整操作序列和往返 | 旧 nil 续接测试仍是活跃且根完整；体重只测手写数字解析，没有读旧值→编辑→保存；混合 UI 夹具仅有 once/day，没有周/月习惯 | 测试矩阵列合法前置状态、用户动作、后续动作、实际落点；给同一数据走完整一圈 |
| 单模块结论被外推到系统组合 | F5 证明特定命令不重读历史，不证明成功编辑器释放；导出和计时各自被测过，不证明导出持锁时前后台检查点可响应 | 明确每个 PASS 证明什么；共享锁、事件、时钟、缓存的所有上层使用方必须进入检查 |
| 既有 UI 变体没有按动作语义统一 | Todo“知道了”已改，Sleep/ImportantDays 仍“关闭提示”；每日和其他入口走 ModuleEntryRow，周/月习惯仍裸标题列 | 按共同动作和行结构查全部同类入口，不能只按最初被点名的页面搜索 |
| 后续独立复核偏重上一轮缺陷的关闭 | 历史原文确有跨模块审查和反例，不是只看一个文件；但没有完整、可核对的生命周期／消费者矩阵解释未改入口为什么安全 | 主审承认前几轮覆盖不足；“独立 reviewer 无已知 P2”不能当系统全覆盖证明 |

不能把问题简单归为“每轮都把代码修坏”。本次至少有两类不同来源：

1. **修复引入的后续操作回归**：SR-01 的恢复约束与终止操作冲突，可定位到最近旧规则恢复及续接保护。
2. **一直存在的漏审**：WeeklyReview 两个统计问题、WeightEditor 数值往返在 f1、e75、当前快照均存在；计时 MainActor 争锁和成功编辑器留存在时间投入 V1 的 BASE 已存在。它们这次被发现，不等于这次才产生。

过程证据：[最初独立审查与 R1–R8](https://github.com/yoCruzer/PersonalGrowthOS/blob/62210d9910bae50acf0d58e6cb928e52a67c4a6f/Docs/USAGE_REMEDIATION_20261017_REVIEW_ZH.md#L18-L56)、[第一轮修复 Goal 的完整消费者与验证要求](https://github.com/yoCruzer/PersonalGrowthOS/blob/2add10b0c67d064b7e77478fb18a11479d3c94dc/Docs/USAGE_REMEDIATION_20261018_REVIEW_FIX_GOAL_ZH.md#L79-L94)、[第二轮独立复核要求](https://github.com/yoCruzer/PersonalGrowthOS/blob/41ef47c384464823f9456e9816d574ba7edff563/Docs/USAGE_REMEDIATION_20261018_REVIEW_FIX2_GOAL_ZH.md#L135-L151)。

之前规格已经写过完整调用链、相关消费者和独立审查，不能把责任推给“prompt 没要求”。实际不足是这些要求没有稳定转化为可检查的覆盖清单，执行与复核仍容易围绕已知编号收敛。长篇追加的交接文档也增加了辨认最新状态的成本，但没有证据证明某次实现确实误用了旧标题，故不将其定为主要原因。

用户要求不要每阶段反复全量测试是合理的。缺少测试场景，不能靠重复运行同一组测试补上。后续采用阶段内定向反例、末尾一次有理由的集中验证，停止无目标扩大测试。

## 3. 真机前修复登记

以下是 **7 组修复工作，包含 5 组 P2 和 2 组 P3**；同因的多个现象归在同一组，避免重复计数。所有 SR 当前均 OPEN。P3 纳入本次是因为直接完成既定统一整改，或是小范围、明确的生命周期清理，并非声称它们与 P2 风险相同。

| 编号 | 级别 | 问题／影响 | 来源 |
| --- | --- | --- | --- |
| SR-01 | P2 | 旧 nil 系列停止／删除后，切区可阻断共享提醒协调；空清单不能删，当前提醒和普通编辑可能不能修改 | NR-01/02 同因扩展；最近修复回归 |
| SR-02 | P2 | 体重编辑的格式和解析不对称，只改日期／直接保存也可能改写原体重 | 旧输入路径漏审 |
| SR-03 | P2 | 周回顾习惯错周／错天数；Entry/Habit/Weight 缺统一实际截止，未来事实提前计入 | 旧事实消费者漏审 |
| SR-04 | P2 | 导出长时间持锁，前后台计时检查点在 MainActor 同步等待，阻塞 UI 回调 | 时间投入 V1 与备份的组合漏审 |
| SR-05 | P2 | 每日／每周提醒的旧任务晚报普通错误，可以关闭用户最新设置 | 共享异步结果回流漏审；接口合同确认 |
| SR-06 | P3 | 新手工记录／计时确认成功后，已结束编辑器持续留在 Workspace | 既有缓存生命周期遗漏 |
| SR-07 | P3 | Today 周/月习惯缺共同图标列；Sleep/ImportantDays 保存反馈仍有“关闭提示”歧义 | 原反馈 3、9 的同类入口漏项 |

### SR-01：旧重复系列终止操作与未来策略恢复耦合

**源码证据**：[preserve 与恢复前置条件](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Todo/TodoFoundation.swift#L412-L487)、[默认编辑条件](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Todo/TodoFoundation.swift#L527-L564)、[切区、Stop、delete、deleteList](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Todo/TodoFoundation.swift#L655-L728)、[共享协调入口及失败边界](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Todo/TodoReminders.swift#L167-L335)。

合法原始数据是旧 V11／旧候选能产出的 reminderDayOffset=nil 且有 reminderMinutes 的重复系列，不是假造损坏库。

- **A：停止→切时区。** Stop 会更新 rule.updatedAt，当前实例仍可 open、有墙钟时间。refreshRepeatingReminderTimes 仍选中该实例并恢复未来 offset，随后因 updatedAt != createdAt 抛错。共享 coordinator 在读取其他健康 Todo/ImportantDays/Sleep 候选前终止，后续前台会再次失败。影响是其他提醒安排／刷新受阻，不能夸大为所有已在系统内的请求被统一删除。
- **B：删除根任务→删除原空清单。** 正式 delete 合法保留 stopped rule/listID，但删除其根任务和相应历史；deleteList 仍强制恢复该 rule 的 offset，规则时间和根证据条件都不成立，事务回滚，空清单无法删除。保留 stopped 实例再删清单也受同因影响。
- **C：停止→普通编辑。** 无 override 的旧系列停止后，默认关闭 Reminder 会进入 preserve 并失败。若旧 f1 已产生 nil+instanceOverride，停止后只改标题／备注也会失败。futureSeries=true 可能绕开，但不应要求用户编辑一个已停止系列的未来模板才能完成当前修改。
- 删除别的一期导致系列停止、仍保留 open 实例，是必须覆盖的兄弟分支。

**修复原则**：需要继续生成或套用未来模板的行为才依赖可信 offset。终止、删除、终止后的当前编辑、关闭提醒、清单解绑应可正常完成；历史事实不改写，stopped 不复活。对于合法但不可自动推导的旧 active 规则，策略不确定可以拒绝猜测并明确提示，但不能传播成健康类别的全局失败。仅隔离可识别的局部策略恢复失败，真正数据库／完整性故障不能 catch-all 吞掉。

**禁止的捷径**：把 preserve 简单移到 Stop/delete 开头；统一默认 offset=0；选一个后继“投票”当原规则；放松原事件链校验；删除历史或为了清单删除重建用户任务。

**关闭证据**：真旧模型／旧 f1 来源夹具，经正式 Stop、delete、默认 Edit、切区及真实 coordinator；包含有根／无根、删除兄弟期、0/-1 对照、落盘重开、导出恢复及失败回滚。健康三类别继续安排，停止系列零新请求，操作只改变该改变的事实。

### SR-02：体重编辑应无损往返

**源码证据**：[编辑字段初值与保存](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Weight/WeightViews.swift#L332-L413)、[合法数值与解析](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Weight/WeightFoundation.swift#L44-L58)。

字段从 Double 用最多两位小数的本地化展示格式生成，保存时把逗号全替换为点再 Double 解析。

- 合法 72.345 被先舍入到 72.35，用户只改日期／不改输入保存也改变原值。
- 在默认 en_US 分组下合法 1000 显示为 1,000；当前 parser 得到 1.000，即 1 kg。1000 是当前服务和测试允许的合法边界，不是人为突破校验。Foundation 默认浮点分组示例可核对 [Apple 官方文档](https://developer.apple.com/documentation/foundation/floatingpointformatstyle/decimalseparator%28strategy%3A%29)。

**修复与关闭**：区分展示文本与可无损编辑文本；保留原值或者使用无分组、与解析匹配的往返方式。用实际生产 formatter→parser→service→磁盘重开验证 1000、72.345、常规值，在 en_US、中文及逗号小数 locale 下日期-only/no-op 不改值，真实改值仍更新趋势/BMI/历史。不能缩小合法范围来移除反例，也不能改变用户原有事实精度。

### SR-03：同一事实在周回顾使用同一归属与统计截止

**A：习惯业务日。** Domain 明确保存后的民用日不随设备时区改变；正式打卡保存 HabitLogDayMetadata，Habit analytics/QuietWins 使用它。WeeklySummary 未读取该元数据，而是按 occurredAt 是否落入当前时区的周区间过滤，再用当前 startOfDay 去重。

例：洛杉矶 2026-10-18 周日 23:30 的打卡保存业务日 10-18，对应上海 10-19 周一 14:30。旅行后 Weekly 会把事实移到下一周；原业务日的早晚记录也可能被拆成两天。

**B：体重截止。** 编辑器和服务允许保存未来 recordedAt，独立全历史可管理；Weekly 只过滤整周，当前周尚未到来的记录会成为“最新体重”和变化。Weight/Today/Growth 已排除未来，口径不一致。

**源码证据**：[Habit 不变量](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Domain/Habit/HabitDomain.swift#L25-L26)、[正式写入业务日](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Habit/HabitFoundation.swift#L1164-L1188)、[Weekly 统计](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Review/WeeklyReviewFoundation.swift#L309-L404)、[Weekly 真实调用者](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Review/WeeklyReviewViews.swift#L15-L68)。

**修复与关闭**：周归属和 activeDayCount 用已保存业务日，次数仍是真实日志数；显式 asOf 排除尚未发生事实，历史整周仍可完整查看。缺元数据的旧事实使用与既有领域一致的保守规则，只读时不改历史。真实服务写入再重开，测试跨周／跨年、DST、同一天多次、补记／撤销；同一数据核对 Habit/QuietWins/Weekly 与 Weight/Today/Growth，推进时钟后未来事实才纳入，编辑删除使各消费者刷新。

**同因扩展已核实：**Weekly 的 Entry、completed HabitLog、Weight 三组事实都只有周过滤。正式 [Entry 日期编辑器](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Capture/EntryDetailView.swift#L498-L507) 允许将随心记改到本周未来，[服务](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Persistence/PersistenceFoundation.swift#L898-L903) 正式保存 occurredAt，当前会提前计入条数、天数、带图条数、TopTags 与 RecentEntries。Habit 允许五分钟未来容差。三类事实需同一实际 asOf；referenceDate/weekIdentifier 是选周，不能用历史周周一截掉该周后半段。当前 Weekly 没有 Goal/Sleep/Investment 事实输入，不新增这类摘要；Habit名称/Tag/ObjectLink 作为所选事实的当前元数据不无依据按 createdAt 过滤。

Habit Timeline 的绝对时刻排序和详情时间标签有不同语义，**不能机械把所有 occurredAt 替换为 LocalDay**；需要业务日统计一致，实际时分展示可以保持。

### SR-04：导出持锁期间，自动检查点不能同步阻塞 MainActor

**源码证据**：[生命周期调用](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/AppShell.swift#L201-L209)、[Workspace checkpoint](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L168-L180)、[MainActor 事务](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/TimeInvestment/InvestmentFoundation.swift#L258-L290)、[同步发布锁](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/ExternalCapture/ExternalCaptureImport.swift#L10-L29)、[持锁导出](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/ImportExport/ImportExportService.swift#L130-L318)。

真实用户路径：running timer 或未结束的保留编辑器 → 设置导出含媒体备份 → 导出仍在哈希/ZIP/校验时切后台或返回 → scenePhase 同步 checkpoint → MainActor 的 InvestmentService.transaction 等同一个 NSLock。锁在完整导出完成／失败前不释放，因此主执行器同步等待剩余导出，UI 和取消回调不能及时执行。

设置页限制关闭不能阻止 scenePhase，故路径成立。代码没有“每 30 秒自动 checkpoint”这一周期入口；本问题不依赖该说法。纯 paused 且没有待持久化编辑器是反向对照。

**结论边界**：确认结构性主线程等待；没有测出具体卡顿秒数，不声称死锁、watchdog 或丢数据。

**修复原则**：把等待发布权移出 MainActor，保留一致的备份数据和真实媒体快照。自动检查点可排队／合并，最终请求可靠执行；占锁后读权威版本，防旧 revision/generation 回写；受信任 clock、暂停不累计、倒计时封顶、草稿隔离保持。允许小范围异步发布或非阻塞显式命令设计，不强制新通用框架。

审计同一 StorePublication 全部调用者：InvestmentService 的 MainActor 写入、ImportantDayService 写入、ExternalCaptureImporter/import/export worker。邻接测试应基于实际可达路径，不假造导出 sheet 背后可以任意编辑。不能去掉备份互斥，不能锁忙就永久跳过检查点。

**关闭证据**：真实导出在已拿锁的 checkpoint 用 barrier 悬停，按顺序投递生命周期 checkpoint 与 MainActor probe；独立后台 fail-safe 在有界时间释放，防红测挂死。修复后 probe 应先于 barrier 释放执行；随后核对导出截止、最终计时/草稿落盘、暂停/倒计时、取消导出、失败重试和无关草稿未提交。以因果先后判断，避免任意毫秒阈值。

### SR-05：旧每日／每周提醒结果不得覆盖最新设置

**源码证据**：[设置变更监听](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/AppShell.swift#L1219-L1235)、[任务与 catch 写回](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/AppShell.swift#L1346-L1383)、[排程 await 与取消检查](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/App/ReminderFoundation.swift#L116-L145)。

合法异步合同序列：

1. A 保存 M1，持有共享 gate 并挂起在 addRepeating。
2. 用户改为 M2/另一天，UI 取消 A，B 以 enabled=true 排队。
3. A 晚返回普通、非 CancellationError 的错误。
4. AppShell 只区分错误类型，没有已取消／代次 guard；旧 catch 将最新 enabled 置 false。
5. false 的 onChange 再启动关闭，最终用户 M2 意图被关闭。

同样保护旧 success 的权限／错误显示。gate 只串行系统请求，不管理 UI 最新意图。以上不依赖 Swift Task 的任意非 FIFO 推测；确认的是现有 async throws 客户端合同下结果应用错误，**没有声称在某版 iPhone 系统捕获到该晚错**。

**修复与关闭**：每日和每周结果都验证任务所有权／最新 command generation，旧 success 和普通 catch 均不改当前偏好或提示；当前真实失败仍有明确反馈。测试实际设置更新边界，先让 A 到真实 await 挂起点，再提交 B，最后释放 A 普通失败。覆盖 M2/weekday、B 明确关闭、当前失败、旧成功晚回；保留共享预算和未知请求。不能只在成功路径追加一次取消检查。

### SR-06：成功结束的新编辑器应释放

**源码证据**：[Workspace 编辑器字典及清理](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L95-L214)、[成功保存](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L625-L646)、[saved/erased 读取区分](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/TimeInvestment/InvestmentFoundation.swift#L685-L708)。

新 manual 或 timer confirmation 保存使同 ID operation 进入 saved，视图只设 editor.finished=true。UIReader 的 erased 仅含 deleted/discarded，Workspace 不清 saved editor，连续成功会话按 UUID 累计持有正文、分段和输入。

已有正式记录编辑的独立 draft 会 discarded，当前清理正确；已落盘取消同样正确，不能混称都失效。没有测得内存超限、崩溃、重复正式记录，不推翻 F5 或旧 R1 的有效范围。

**修复与关闭**：可信成功完成后释放对应编辑器；失败、保留草稿、稍后确认保留输入。连续若干新 manual/timer 保存后缓存不累计 finished editor；规范事实仍可按 ID 查，CR-05 双层关闭落点、失败重试、正式编辑/取消删除与 F5 读取计数不回退。

### SR-07：同类 UI 一致性收尾

**A：周/月习惯行。** [AppShell 周月入口](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/AppShell.swift#L636-L651) 使用 [HabitOverviewRow 的裸 VStack](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Growth/HabitViews.swift#L408-L423)，没有每日及其他 ModuleEntryRow 的图标列。原 mixed 夹具仅 once/day，不覆盖这一变体。

**B：保存提示。** [ImportantDays](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/ImportantDays/ImportantDayViews.swift#L565-L590)、[Sleep](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Sleep/SleepViews.swift#L519-L531) 仍使用 Dismiss/“关闭提示”，实际只清保存消息，与原反馈相同歧义。Todo 已使用“知道了”。

**修复与关闭**：所有 Today 习惯变体复用一致标题/副标题/装饰图标列，保留 44pt 动作、直接打卡及最大 AX 分行。共同底部保存反馈采用明确收起语义；点击不取消提醒。只局部修改反馈，外部待处理导航的 Dismiss 有丢弃请求语义，不能全局替换词条。

用同一真实混合页面覆盖每日单次、每日多次、周/月习惯、长名称、计时中/已保存投入、Weight、ImportantDays、Review。默认与中文 Dark 最大 AX 检查文字列、行高、按钮命中和副标题；不要求不同内容硬凑相同行高。顺手校正 Weight 历史截止模式仍称“今天/昨天”的连贯性文案，显示为所选截止日口径，不改统计算法。

## 4. 两项限定验证，不预先定性为缺陷

### BV-01：Growth 全局保存刷新是否重读无关历史

源码 [GrowthView / GrowthEntryCounts](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Growth/HabitViews.swift#L60-L92) 在任何 ModelContext.didSave 后回主 RunLoop，从新 context 全量 fetch Weight/Sleep 并去重，以及取活动。仅 F5 Workspace 内计数不能覆盖这个消费者。

必须做一次限定生产读取观察：混合数据含约 10k 体重／睡眠历史，保持 Growth 已加载，通过真实 InvestmentService 草稿／正常 checkpoint 保存触发事件，统计 Growth 真实 fetch/模型读取及主执行器响应。先判断订阅在实际 UI 生命周期中是否存活、请求是否发生；不能用独立重写的计数函数替代生产链。

如果确实重复读取无关历史，局部限定失效来源或改为轻量统计/缓存；正式 Weight/Sleep/活动修改、导入、跨日跨区应正确刷新，真实读取失败不伪零。若生产路径未触发或已有足够隔离，以证据关闭。没有测得卡顿，故不能把源码成本直接写成“真机已卡顿”。这不是新通用统计平台任务。

### BV-02：非有限 Habit quantity 是否可以落库并阻断备份

[输入](https://github.com/yoCruzer/PersonalGrowthOS/blob/c296a3691d53ce7f5b5bff36fbf7de525d86510f/PersonalGrowthOS/Growth/HabitViews.swift#L1898-L1909) 使用 Double(text)，正式服务未见 isFinite 校验；transfer 复制 quantity，整包导出使用默认 JSONEncoder。**尚未证明 SwiftData 会正式保存并重开这些非有限值**，因此不能宣称已存在整库备份故障。

有界探针：实际输入／服务 inf、NaN、溢出指数 → save → 磁盘 reopen → 实际 export。若输入/保存明确拒绝且无异常事实落盘，记录观察关闭；若合法服务链能落库且影响导出，升级为具体修复：领域有限数校验、可理解输入错误、既有异常数据的可恢复处理。不能静默删历史、吞掉整条 HabitLog 或改写历史事实来让备份“成功”。验证 finite 正常记录和旧包仍能恢复。

两 BV 均须产出 DISPROVED / VERIFIED_SAFE / CONFIRMED_AND_FIXED 或带具体环境原因的 VALIDATION_BLOCKED。不可用未执行的推测关闭，也不可无限扩展样本直到出现问题。

## 5. 本次系统覆盖矩阵

表中“已审、无新增确认问题”不等于新原生 PASS。文件均来自第 1 节固定产品。

| 范围 | 完整工作流／关键不变量 | 本次结论 |
| --- | --- | --- |
| 清单及普通待办 | 新建、来源、改名/换清单、删除清单保留任务、事务回滚、重开 | 主路径已审；旧终止系列清理 SR-01 |
| 日历重复 | 工作日/周末/自选、首次日期、月末/闰年/DST、complete/skip、重开后继、Stop/delete、旧 nil/0/-1 | 当前规则与 F1/CR03 已有保护认可；终止组合 SR-01 |
| 本机提醒 | 通知↔Alarm、代次、容量置换、失败取消跨 fireAt、重启对账、主动停止不复活、prepared 恢复、旧异步返回 | CR01/02 及主 journal 路径无新增确认错误；SR-01/05；D1 原生保留 |
| 过期与反馈 | 过期重设未来时间、只收起保存提示、不误取消 | Todo 已审；同类反馈 SR-07 |
| 成长事实依据 | 保存业务日日聚合、次数与天数、原 ID 下钻、删除刷新、只读不造记录 | QuietWins 主算法可认可；同消费者 Weekly 见 SR-03 |
| Growth 入口统计 | active habit/goal、已发生体重日、wakeDay 睡眠、未归档活动/日子、纯读无默认参与者写入、错误态 | 语义已审；成本 BV-01 |
| 体重 | 等权日均、日历 3 月/年、四均线、动态轴、断点、截止与全历史、20条分页、选日/旧返回、编辑删除 | 核心聚合/F4/UX2/CR06 可认可；输入 SR-02、周回顾 SR-03 |
| BMI | 自愿身高、清除、中国/WHO 明示选择、未舍入分类、临界提示、成人适用范围、偏好备份 | 算法/来源/持久化接口已审，无新增确认问题；不新增医疗建议 |
| Today 统一布局 | 所有模块、每日/周/月/多次变体、动作命中、高字号、图标/副标题 | SR-07；实际 VoiceOver/动态阅读留 D4 |
| 时间投入计时 | Start/checkpoint/pause/resume/finish/save/discard、ContinuousClock、50ms/18h、倒计时封顶/继续、跨进程待确认 | 状态/时间保护认可；与导出组合 SR-04，硬件行为 D2 |
| 时间投入编辑/读取 | 草稿/正式隔离、duplicate 失效、成功落点、typed event、10k 真实读取、20条页、单ID详情、切日/截止/跨日 | F5、CR04/05、OBS01 范围内保护认可；结束缓存 SR-06 |
| 睡眠与作息 | 部分事实、编辑/删除/revision、wakeDay、跨区、目标生效/关闭、回拨、分母和截止 | 服务/统计未发现新增确认问题；反馈 SR-07 |
| 周回顾/Goal | Weekly 的习惯、体重、Entry 期间事实，键盘/草稿入口；独立 Goal 生命周期与关联 | SR-03 三类事实统一截止；不为 Weekly 新增 Goal 输入 |
| 升级/备份/恢复 | 真 V11及后续模型、迁移前保护、V15/v11、ZIP/媒体原子安装、取消/失败、空库门、device journal不跨机恢复 | 未发现新的确认丢数据；SR-04，BV-02；签名覆盖升级 D3 |
| 原 Entry/媒体/关联 | Entry 删除清理 Todo source/ImportantDay/Habit 引用、文件失败回滚、trash恢复、后台 Share 发布 | 相关链已审，无新增确认丢数据；公开系统入口仍有旧环境 FAIL |
| 启动/路由/隔离 | startup保护、前台/保存/切区、外部 deep link、存储sheet期间阻断编辑、同一容器恢复 | 不将不可达的并发假说列 blocker；原生路由需设备核验 |
| 配置/发行证据 | 原 Bundle ID、minOS、App Group、URL、AlarmKit availability/weak link、provenance | 代码/配置审查与实包验证分层；最终实际包仍由 Codex 本机核验 |

### 已检查但不列本轮新 blocker 的假说

- Workspace 换 container 不清旧 editor：当前成功路径没有实际替换容器，恢复使用同一空容器，缺少现有合法触发。
- 导入期间 Sleep 未用同一锁导致覆盖：设置 transfer 状态及外部路由阻断普通并发编辑，发布区另有空库复查；没有证明可达覆盖路径。
- 复杂旧 nil 不能自动推导：拒绝猜测本身可接受；本次要修的是终止清理/健康类别不应一并被阻断。
- 旧 OBS-02：已有分页入口加固保留，未证明原生 SwiftUI 起步次序竞态；不把它重新记成已确认原生缺陷。
- OBS-01：实际落盘后报错的失效修复认可；其它严格 revision 保护不因理论错误注入而放宽。
- 时间投入累计的实际 VoiceOver 值阅读、图表手势、Photos/Widget/系统 Stop/Open 属于可明确验收的 D4/D1 项，不靠静态推断填 PASS。
- 未测出的大规模 Todo 历史极限、UI内存峰值，不作为继续无边界压测的理由。

## 6. 新一轮如何避免继续“按点补丁”

每个 SR 修复必须交付四件事：

1. 一句话领域不变量，以及被修复条件的全部调用者／事实消费者列表。
2. 真实生产路径红例或等价因果证据，加正常、相反动作、终止、失败回滚、晚返回/重开等适用的兄弟场景。
3. 修复后可观察结果，包括最终页面落点、规范数据、系统副作用和缓存寿命；不能只证明某 helper 返回值。
4. 固定产品 SHA 下的关闭证据及复用范围，由未写实现的 reviewer 用独立场景反证。

不机械跑状态的笛卡尔积，优先覆盖新增前置条件、所有状态终点和共享资源交叉。已认可的 R1–R8、F1–F5、CR01–06、UX1/2 是保护基线，不无依据重开，也不能用旧关闭编号排除同因新回归。

阶段定向验证，最终一次覆盖本轮共享风险的集中 Unit 与关键 UI、Debug/unsigned Release 和实包核对；文档提交不触发新构建。准确记录原失败、后续修复和复用，不相加成虚构的一次全绿。

## 7. 进入设备门的判定

目前不恢复 READY。需要 SR-01～07 的明确收尾、BV-01/02 有界结论、本轮必要本地验证及独立审查完成，才能恢复 **READY_FOR_OWNER_DEVICE_GATE**。这只代表设备测试前的本地工作可交接，不能承诺不存在任何未知缺陷。

| 设备/环境项 | 本次保持的状态与内容 |
| --- | --- |
| D1 | NOT_PASSED；权限允许、锁屏/静音/专注真实响铃、Stop/Open、取消确认 |
| D2 | NOT_PASSED；硬件睡眠、暂停、倒计时晚返回/继续、真实后台限制 |
| D3 | NOT_PASSED；独立备份后签名，不卸载覆盖升级与恢复核对 |
| D4 | NOT_PASSED；真实 VoiceOver、Photos/分享、桌面 Widget、离线组合 |
| AlarmKit 正向 | NOT_RUN；fake 生命周期和直接 intent 不代替系统正向 |
| Public Share / Safari | 旧 FAIL/environment / unsigned FAIL 保留，签名正向未通过 |
| 物理低空间 | SKIP/NOT_RUN 保留 |
| 远端 CI | NOT_RUN；不能把无 check-runs 当成功 |

执行时若系统审查确认新的同因 P0/P1/P2，应记录并在授权范围内一并闭环；无证据理论风险不能无限扩展任务。若本地能力确实不足，完成不受影响的工作后明确 VALIDATION_BLOCKED 和缺的具体证据，不假报 READY。

