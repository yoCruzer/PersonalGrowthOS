# PR #13 系统审查后的真机前修复目标

版本：1.0；日期：2026-10-19；规格状态：**FIX_GOAL_READY / LOCAL_REVIEW_FIX_REQUIRED**。

本 Goal 与 [系统审查及原因复盘](USAGE_REMEDIATION_20261019_SYSTEM_REVIEW_ZH.md) 配套。用户要求先查明多轮遗漏的原因，再以完整业务生命周期检查当前代码，把真机前需要解决的问题一次归并，交给 Codex 修复。本次规格交付不修改产品、不新增原生 PASS。

**Codex 收到 Owner 的执行 prompt 后，按本 Goal 连续完成本地核实、修复、必要验证、独立审查、普通 push 和交接。**不要在写完计划、某阶段完成、首轮测试或首次 review 后要求重复“继续”。本轮是原统一整改的收敛批次，不从 BASE 重写产品。

## 1. 固定身份与开工

| 项目 | 固定值 |
| --- | --- |
| 仓库／唯一 PR | yoCruzer/PersonalGrowthOS / [Draft PR #13](https://github.com/yoCruzer/PersonalGrowthOS/pull/13) |
| 目标分支 | codex/usage-remediation-20261017 |
| 原 base 分支／BASE | codex/time-investment-v1 / 5a70f0110b151f8a45ac7c33d3f443823b1cff24 |
| REVIEWED_PRODUCT_SHA | c296a3691d53ce7f5b5bff36fbf7de525d86510f |
| REVIEWED_DELIVERY_SHA | 62210d9910bae50acf0d58e6cb928e52a67c4a6f |
| 原整改 Goal | 68373d4edf10cff8ca3e212b9ff10a28e6da9c73 |
| SYSTEM_FIX_GOAL_SHA | 由 Owner 短 prompt 指定本文件所在的完整提交 SHA；避免在文件内自引用 |

先按 AGENTS.md 阅读 INDEX、既有 Foundation、DEVELOPMENT_CONTRACT、两份 CURRENT，再完整阅读本 Goal、配套 SYSTEM_REVIEW，以及前两轮 FIX_GOAL/FIX2_GOAL 和 ACCEPTANCE/REVIEW/EXECUTION 的有关证据。同一会话已读且未变的长期文档可复用，不重复研究竞品或重写原需求。

轻量核对工作树、head/base、原任务 worktree、远端与 SYSTEM_FIX_GOAL_SHA 的祖先关系。优先安全续接原任务工作树，fetch/fast-forward 到包含规格的原分支。保留未知主工作区改动和后续有效提交；不能 reset/clean/stash 未知改动，不能回退覆盖后续产品，不改 base、不建重复 PR。若远端已有本 Goal 之后的有效修复，逐项核实现状并保留，不机械重做。

规格是纯 Markdown，**接收规格不跑构建或全量基线测试**。当前“仅等 Owner D1–D4”的旧本地停点已被本次 LOCAL_REVIEW_FIX_REQUIRED 取代；旧实际运行结果与设备/发布边界不变。

## 2. 必须改变的工作方法

之前已经要求独立审查、相关调用链和按影响测试。本次不能只再写同样口号，而要产出下面可核对的四列：

| 修复项 | 不变量 | 全部同类调用者／消费者 | 合法状态组合／反例与证据 |
| --- | --- | --- | --- |
| SR-01 | 终止清理不依赖未知未来策略；健康提醒不被单条策略问题拖停 | offset recovery 的全部调用者、Stop/delete/edit/list/timezone/coordinator | 活跃／停止、有根／无根、当前／未来编辑、原始／已覆盖旧 nil、真实回滚与重开 |
| SR-02/03 | 事实无损往返；同一事实业务日与截止一致 | Weight 输入/解析/保存，Habit/QuietWins/Weekly，Weekly 的 Entry/Habit/Weight | no-op/日期-only、跨区跨周、历史周与实际 asOf、当前未来事实 |
| SR-04/05 | 长操作不阻塞 MainActor；旧异步结果不得覆盖最新用户意图 | StorePublication 全使用方；daily/weekly 设置→调度→结果回流 | 持锁导出×scenePhase×timer/editor；旧 A 挂起→新 B→旧普通错误／成功 |
| SR-06/07 | 正式成功释放编辑器；同语义入口一致 | 新 manual/timer/正式编辑/草稿；所有习惯变体和底部反馈 | 成功/失败/稍后/删除；默认和中文 Dark 最大 AX |

实施者先填写实际消费者清单、说明哪些沿用已有规则，再设计改动。不是机械笛卡尔积，优先选择足以区别故障类的代表序列。同因的相关回归自动属于本次修复范围；新模块、产品扩张与无依据理论优化不在范围。

每项至少要有真实生产路径的区分证据。测试应通过实际 Service/Workspace/reader/设置结果边界和正式数据；不要在测试里复制一份正确算法，或只增加与实现一一对应的 helper 测试。局部 UI 文案不需要新增重复单元测试。

旧 R1–R8、F1–F5、CR-01～06、UX1/UX2、OBS-01/02 的有效保护继续存在；不能以它们已关闭为由跳过同因邻接，也不能无证据全数重开。

## 3. 范围与批次

SR-01～07 当前 OPEN；BV-01/02 为限定验证，先不算 confirmed 缺陷。详细源行、成因、影响边界见配套报告。

| 内部批次 | 内容 | 产物 |
| --- | --- | --- |
| SF-A 提醒生命周期 | SR-01、SR-05；共享预算／取消／旧规则的保护 | 终止与恢复完整矩阵、可控旧任务晚返回回归 |
| SF-B 事实与展示 | SR-02、SR-03、SR-07 | 无损编辑、全消费者截止与业务日、混合变体 UI |
| SF-C 计时与资源 | SR-04、SR-06、BV-01/02 | 非阻塞可靠检查点、成功缓存释放、两个有界结论 |
| SF-D 集中交付 | 合并后的受影响链、最终验证、独立异议审查、文档/push | 固定产品 SHA、逐项关闭与复用、准确设备门状态 |

批次是同一连续任务，可按依赖调整。只读分析可并行；同一文件写入、Xcode/模拟器操作串行协调，避免互相覆盖或跑错候选。

## 4. 逐项实现和关闭要求

### SR-01 / P2：旧 nil 系列完整终止生命周期

不要只补 NR-01 切区和 NR-02 空清单两个 if。

**必须满足：**

- 需要未来规则的生成／套用仍要求可追溯的原 offset，0/-1 与更大合法 offset 保持。
- Stop、delete、停止后的当前编辑／关闭提醒、清单解绑不被未来策略推导阻断。
- 已经保存的 stopped/orphan nil 状态可处理；不能仅修“以后 Stop 前先冻结”的新状态。
- Stop/delete 不因无法推导而被拒绝，停止系列不会被重排或复活。
- 合法但不可自动恢复的单条旧 active 规则，呈现诚实的局部待修正状态；健康 Todo/ImportantDays/Sleep 继续安排。真正数据库／结构完整性失败仍保守处理，不能 catch-all 后排陈旧快照。
- 保留现有历史事实与事件字节；保留来源 Entry；清单删除只做规范解绑；写失败原子回滚。

**有区分力回归：**

| 起点（由真实旧模型／旧 f1 行为产生） | 正式用户操作 | 必须断言 |
| --- | --- | --- |
| V11 nil、有根、有提醒 | Stop → 换时区 → 完整 coordinator | 健康三类别可安排；停止系列零新请求；刷新不再反复全局失败 |
| nil、唯一根属于清单 L | delete 根 → deleteList L → 磁盘重开 | 空清单删除；无悬空关联；正式完整性通过 |
| nil、Stop、保留任务 | deleteList | 任务回未分类；历史保留；不复活 |
| nil、多期且仍有 open | 删除另一旧期 → 切区／解绑／关闭当前提醒 | 同因兄弟分支正常收敛 |
| nil、无 override、Stop | 默认当前 Edit 关闭 Reminder | 实例提醒成功关闭、系列仍停止 |
| 旧 f1 nil+override、Stop | 默认当前 Edit 只改标题/备注 | 原覆盖时间保留，修改成功，不要求 futureSeries=true |
| 合法但策略不可推导的 active nil | 协调健康邻接类别 | 该条明确失败/待纠正，其它继续；不猜规则 |
| 显式 0/-1 与活跃可恢复旧 nil | 代表性 complete/skip/reschedule/reopen | 既有未来规则、代次与幂等不回归 |

复用真实 V11 与旧候选备份夹具，验证落盘重开、一次实际导出/恢复后代表操作、保存失败回滚。不能通过直接拼损坏模型证明“生产必坏”，也不能只经新服务首次覆盖就冒称旧 f1 已覆盖状态。

### SR-02 / P2：体重编辑无损

编辑字段的可往返表达和展示精度分离。Locale.current 为 en_US 等逗号分组地区时，1000→“1,000”→1 是必须关闭的范围内反例；只切 App 语言不等于切地区，测试要明确 locale。

验证：

- 1000、72.345、常规值，打开直接保存／只改日期，原数值不变。
- en_US、中文地区、至少一个逗号小数地区。
- 真实用户修改值正确生效，小数点/逗号已有合法输入保留，混合错误输入有明确拒绝。
- 实际 formatter→parser→service→磁盘 reopen，变化后的趋势/BMI/历史一致。

不能全库统一舍入、缩小合法范围，不能声称恢复以前已经损失的精度。

### SR-03 / P2：周回顾统一事实归属与 asOf

这是一组共享口径修复，不能只给 weight filter 补一行。

**习惯：**以保存的 HabitLogDayMetadata/LocalDay 判断业务周与活跃天数，occurredAt 作为实际发生时刻参与 asOf 截止；真实打卡次数不变。只读统计不补写旧元数据，不改 occurredAt；缺元数据按既有明确回退契约。

**事实截止：**Weekly 的 Entry、completed HabitLog、WeightRecord 均需不晚于同一实际 asOf，再各自按正确业务时间归入所查看的周。Entry 仍用 occurredAt，Weight 仍用 recordedAt，不改成 createdAt。未来原始事实保留在全历史，到了时刻后合法纳入。

EntryEditor 正式允许未来日期；其条数、记录日数、带图条数、TopTags、RecentEntries 都从 weeklyEntries 派生，需要一起保护。Habit 服务允许五分钟未来容差，可作边界对照。Habit名称/Tag/ObjectLink 是已选事实的当前元数据，不无依据按元数据 createdAt 再截一次。

**选择周与统计时钟必须分离。**referenceDate/weekIdentifier 用于选择周，不能拿历史周周一作为 asOf，错删周后半段。当前 Weekly 无 Sleep/Goal/Investment 事实输入，不为本问题新增这些模块摘要。

**组合验收：**

- 正式 HabitCheckInService 在洛杉矶周日 2026-10-18 23:30 保存；换上海仍属原业务周。原业务日早晚两次仍 1 天/2 次。
- 同数据跨年周、DST、补记/撤销、缺元数据旧数据，与 Habit analytics/QuietWins 一致。
- 当前周存在未来 Weight、带图/标签 Entry、合法五分钟容差 Habit；asOf 前排除、推进至发生后纳入。
- 历史整周仍包含该周后半段，切时区仍保留明确所选周。
- 编辑/删除刷新派生统计、RecentEntries、TopTags 及详情；只读不写事实。
- 原 Weight/Today/Growth 的截止与独立全历史边界保持。Timeline 的绝对时刻排序/时分展示按原语义，不机械替换全部 occurredAt。

### SR-04 / P2：共享发布权等待与检查点

让 MainActor 不同步等待导出/后台媒体工作，同时保证自动检查点最终执行。保留原备份数据及真实媒体快照互斥。方案由实施者选最小一致改动，不强制全面新并发框架。

**必须保护：**

- 等待放在适当隔离的异步／worker 路径；只是 Task 包住同一个 MainActor 同步函数不算修复。
- 不跨 actor 传活的 ModelContext/持久模型；用正确所有权与独立 context。
- 同一发布权保护源库/媒体；不能删除锁或放任媒体在快照后被替换/删除。
- 排队/合并保留最终必需 checkpoint；锁忙不能静默永久跳过。
- 获得写权后检查权威 operation/revision/generation；晚请求不能覆盖已暂停/完成/删除的新状态。
- ContinuousClock/process token、50ms/18h、暂停不计时、倒计时封顶/显式继续、跨进程待确认保持。
- 编辑输入及失败重试保留，异步返回只更新仍拥有该操作的编辑器；主 context 中无关草稿不连带保存/回滚。
- 审查同锁 MainActor 使用方（Investment 全 mutation、ImportantDay save/createEntry/delete）和安全 worker（Share/import/export）。按真实可达入口验证，不把所有 worker 等锁误定为问题。

**确定性测试：**真实 export 的持锁 checkpoint barrier → 投递正常生命周期 checkpoint → MainActor probe。用独立后台 fail-safe 有界释放，红测也不会卡死。修复后主 probe 在释放 barrier 前完成；释放后计时/草稿正确写入、导出仍为原 cutoff。覆盖 export 完成、取消、失败重试，running 与纯 paused 对照、保留编辑器、多次 checkpoint 合并、checkpoint 之后明确 pause/finish 的所有权保护。测试因果次序，不能只断言“总耗时小于 N 秒”。

### SR-05 / P2：daily/weekly 最新设置所有权

现有代码在 async throws 的普通晚错路径能回写 false。确认的是源码合同，不冒称原生系统已复现。

在实际设置结果落点保护旧 success、CancellationError、普通 error 的所有权；被取消或被新 generation 替代的结果不得更新最新 enabled/时间/weekday/授权显示/错误。当前有效失败仍反馈，明确关闭仍生效。共享 gate/预算/未知请求保护保持。

可控 A 已进入 addRepeating 挂起 → 用户提交 B → 取消 A → A 返回普通失败。最终 B 的 M2/weekday 保留、只有最新请求；B 为明确 off 时保持关闭。补旧成功晚返回与当前真失败；每日/每周两条路径均覆盖。不要复制 UI 闭包到测试里，只测一个改良副本。

### SR-06 / P3：成功编辑器寿命

仅清理 Workspace 对**新 manual 保存成功、timer confirmation 保存成功**的 finished editor 持有。已有正式编辑 draft 的 discarded 清理有效，继续保护；持久 saved operation 是幂等证据，不能因清内存一起删除。

连续多次成功新 manual/timer 后缓存不累积 finished editor；当前视图可在关闭动画期间短暂保留引用，不要求保存返回瞬间销毁。失败、Keep draft、Confirm later、编辑其他记录、重复确认的输入保持；成功双层关闭落点、正式 ID 详情、取消/删除正文擦除和 F5 真实计数保持。

### SR-07 / P3：共同 UI 语义闭环

- Today daily once、daily multiple、weekly、monthly 习惯使用一致装饰图标列、标题/副标题列；保留直接打卡、44pt hit target、普通/最大 AX 自然布局。
- 不强行固定所有行同一高度；内容不同时允许自然增高。
- Sleep 与 ImportantDays 保存消息改成“知道了”等明确收起动作，点击不改提醒或业务事实。
- Dismiss 还用于丢弃待处理外部路由，局部改反馈，不全局替换翻译。
- Weight 历史截止下连贯性说明使用所选截止日口径，不再一律称“今天/昨天”。

在已有 mixed UI 加入周/月与多次变体，不新造重复大套件。保留 Today 的投入运行中/已保存、Weight/ImportantDays/Review，默认和真实中文 Dark 最大 AX 截图检查文字列、附加内容、点击/导航。截图中 Light/Dark 与实际系统 appearance 一致；不能只设参数就推断 Dark。VoiceOver 实际阅读留 D4，必要的静态 label/value 修正可顺同文件处理但不填原生 PASS。

## 5. BV 的限定处置

### BV-01 / NOT_RUN：Growth 全局 didSave 成本

一次真实混合规模观察即可。Growth 已真实加载/挂载，约 10k Weight/Sleep 历史，经真实 InvestmentService 草稿和正常 checkpoint 触发保存，统计 Growth reader 实际 fetch/模型读取及主执行器响应。覆盖可见/切离后的订阅状态，先确认生产链是否真的触发；不能拿事件次数或手工调用 reader 次数代替数据库读取。

若重复无关全历史读取得到确认，在现有结构上限定失效/轻量缓存/统计，保持正式事实新增编辑删除、import、参与者/活动、日期/时区变化正确刷新，真错误不显示伪零。性能判断优先读取次数/体量/因果响应，不以跨硬件任意耗时门槛制造阻断。没有复现则用明确生产条件和证据关闭；不引入通用缓存平台或无目标 Instruments 批次。

### BV-02 / NOT_RUN：Habit 非有限数量落库与备份

通过正式输入/Service 验证 inf、NaN、溢出指数；save、磁盘 reopen、实际 export。包含 finite 正对照。

若输入/持久化已经拒绝且无异常事实落库，记录 DISPROVED/VERIFIED_SAFE；若确可落库并影响导出，记录具体新子项并同批补最小有限数校验及已存在异常数据的恢复策略。不能静默删原日志或 quantity、不能跳过坏事实却报完整备份；对原事实作任何必要修正须明确、可恢复。旧合法记录/包恢复保持。

BV 结果只有有证据的 DISPROVED / VERIFIED_SAFE / CONFIRMED_AND_FIXED 或具体 VALIDATION_BLOCKED。若本地环境无法执行，完成其它工作，明确缺什么，不能把 BV 偷换成假定已安全。

## 6. 保护范围与自主边界

允许本 Goal 需要的产品、测试、局部共享服务/查询及文档改动；一并修复被证实的同因回归。保留五 Tab、Record 独立草稿、清单管理、星期重复、成长聚合、体重/BMI、Time Investment V1、睡眠/重要日子和所有已批准只读/旧数据合同。

保留 Schema V1–V15 固定历史模型与既有备份版本，当前 V15/v11 候选继续兼容。优先不新增 schema；如确实无法用现有合法结构修复，说明原因，按既有合同做最小追加版本及真实迁移/旧包恢复证明，不改历史模型校验和掩盖失败，不重新解释旧事件快照。

不新增时间投入 AlarmKit/Live Activities、AI、家庭、多用户、HealthKit、云同步、第三方依赖或新功能模块。本轮不需要 merge、force push、tag、Archive、TestFlight、签名安装、不卸载升级或读写私人设备/用户库。D1–D4 留待 Owner 设备任务。不能因 D1 未授权停止本地可完成的工作。

## 7. 验证与独立复核：一次收敛，证据不外推

### 阶段内

围绕新增不变量先做有区分力定向测试，失败与修复后结果都保留。不是每次改文件跑全套，也不以改测试弱化断言、跳过原失败或改变 host 日期换绿。

新回归必须能区别修复前后。若 API 重构使旧源码不能直接编译新测试，保留改动前最小生产路径反例/调用证据，并解释差异，不能伪造一次红测。并发使用 barrier/明确所有权，时间测试注入固定 clock/calendar，迁移使用真实历史模型与可追溯旧数据。

### SF-D 最终集中验证

本轮修改横跨 AppShell、共享发布、统计消费者和持久化，因此在收敛候选安排**一次完整 Unit 运行**，加一组有明确范围的关键 UI；不要求每阶段全量，也不把所有原生环境项目重新混进可通过的 UI 门。

关键 UI 与组合至少覆盖：

- SR01 Stop/delete/list/default Edit 的代表入口与提醒反馈，保留渠道/过期操作。
- SR02 日期-only 编辑不改原值，SR03 本周/历史周及未来事实的正确摘要。
- SR04 真实生命周期/导出持锁因果测试（适合 Unit/集成），SR05 设置晚错确定性测试；UI 验证正常设置仍有效。
- SR06 timer confirmation 成功落点、manual/失败/Keep draft；原 CR04 候选 B 修改返回 A。
- SR07 全习惯变体 mixed Today/Growth、Record 独立草稿。
- 原 Weight 截止/全历史/分页切日、Investment 窗外选日及20条页/单ID详情、F5实际读取保护。
- 共享提醒旧R/F/CR保护、真实旧nil恢复、取消不确定、满队列与停止负例、备份恢复/媒体失败。

完整 Unit 中合法 SKIP 逐项说明；真实 FAIL 修复补验后，按实际变动完整受影响类补跑，并写清分轮和复用。不把多轮局部 PASS 拼成一次全绿。一次充分验证后停止可选扩大测试。若最后只改 Markdown，沿用同产品 SHA 的证据。

固定干净最终产品/测试 SHA 后，串行完成一次 Debug Simulator 构建（同候选有效 build-for-testing 可计入）和一次 unsigned generic iOS Release，核对实际 App/Share/Widget 包身份、1.0(7)、minOS17、provenance 的完整 SHA/Dirty、AlarmKit弱链接与用途说明。沿用现有 proof 设施，不为本任务新增发行流程。doc-only 交付另一个 SHA 不重建。

### 独立审查必须看什么

至少一位未编写本轮实现的 reviewer 审固定产品 SHA；条件允许可按领域并行。**先从不变量独立列合法反例，再核对实现者给的用例**，避免只复述修复说明。

核对完整本轮 diff、相关未改调用者/事实消费者、组合入口/终态、失败结果落点、原有保护、新测试的实际生产接线，以及本机可读原始日志/xcresult/截图/包。至少一次跨分工反证 SR01 的停止权威、SR03 三类事实与选周/截止区别、SR04 同步锁/晚检查点、SR05普通catch、SR06仅释放成功缓存。

发现范围内真实问题后连续修复并按影响补验；不增加 Owner 批准停点。reviewer 原文保留，不由实施者代写“独立全部通过”。同一有效候选和证据可复用；没有新的风险或必要验证缺口，不重复运行。

### 可追溯证据

每条 SR/BV 记录：

- 生产入口、合法起点、关键预期／反证、实际新增/复用 test selector。
- 对应产品 SHA、环境/locale/clock、命令、退出码、PASS/FAIL/SKIP/NOT_RUN。
- 原始证据位置、文件哈希、独立 reviewer 实际读到哪一层。
- 小型机器可读结果摘要和最终覆盖表入 Git；大 xcresult/实包留本机既有证据目录，不新增 Release 或将私人数据信息入库。
- “开发机有路径/哈希”不等于远端 reviewer 读过原始证据；不声称 CI 已运行。

## 8. 文档、提交与完成定义

持续更新既有 EXECUTION / ACCEPTANCE 和 CURRENT；SR/BV 使用本轮独立编号，旧R/F/CR原文与失败轮次保留。SYSTEM_REVIEW 是本次固定审查原文，关闭证据追加或另开清晰章节，不改写原问题为“从未存在”。

同一原分支普通 commit/push，唯一 PR #13 保持 Draft、原 base。交接写明 SYSTEM_FIX_GOAL_SHA、最终产品/测试 SHA、纯文档交付 SHA、工作树和未知主工作区改动状态。PR 对外评论/消息仅在用户另有明确授权时发送；推送会自然更新 PR diff。

| 状态 | 条件 |
| --- | --- |
| FIXES_IN_PROGRESS | 正在本地实现/验证 |
| REVIEW_BLOCKED | 仍有本轮确定缺陷未关闭 |
| VALIDATION_BLOCKED | 必要本地验证能力受阻，说明具体动作和原因，继续其余工作 |
| READY_FOR_OWNER_DEVICE_GATE | SR01～07全部有明确关闭/有效反证，BV两项完成有界结论，必要本地验证/双构建/独立审查完成，无范围内未关闭 confirmed P0/P1/P2及明确P3收尾 |

恢复 READY 后 D1–D4 仍未通过。AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、远端CI NOT_RUN 的真实状态继续显示，不能用本地桩和 unsigned 包替代。

最终答复用中文说明：修复了哪些不变量和同因分支、哪个旧保护未受影响、实际测试分轮与证据、仍待设备验证什么。不要只报“SR全关闭/无P2”；提供最终消费者/状态矩阵和复用依据。完成到该停点即交接，不开展本轮未授权设备或发布操作。

