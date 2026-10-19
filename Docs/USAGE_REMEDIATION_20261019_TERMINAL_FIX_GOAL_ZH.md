# PR #13 真机前终态一致性补修 Goal

## 0. 固定身份、授权与当前状态

- 仓库：`yoCruzer/PersonalGrowthOS`；唯一 PR：[#13](https://github.com/yoCruzer/PersonalGrowthOS/pull/13)。
- 原分支：`codex/usage-remediation-20261017`；base：`codex/time-investment-v1`，`5a70f0110b151f8a45ac7c33d3f443823b1cff24`。
- 本次审查产品/测试：`53eeb1d3410630f836bbc3e713c79f9f157a4081`；前次文档交付：`8cc085e353fc6508b9a003d1e633370326cb7799`。
- 前次集成 Goal：`b495bead6c9910ec1e15631227c1146176819583`。本文件的固定提交由手机引导 prompt 中 `TERMINAL_FIX_GOAL_SHA` 指定。
- Owner 已明确批准继续限定修复，并要求每次提出修复时同时准备执行 prompt，不再增加一次“是否准备 prompt”的往返。
- 当前是 `LOCAL_REVIEW_FIX_REQUIRED / FIX_GOAL_READY`：本文件交付只包含规格与审查归并，不代表本次产品修复、原生反例或验证已运行。旧文档的 READY 是前次本地交付结论，不是本次补修完成条件。

本 Goal 不改变 Foundation 的产品方向。授权 Codex 在本机合成、隔离环境中连续完成 TF-A→TF-D；内部阶段、普通修复与补验不等待 Owner 再说“继续”。不进入私人设备、私人数据库、签名安装或发行。

## 1. 编号归并与审查证据更正

此前两份外部答复使用了不同编号，并且后一份摘要漏列设置失败收尾。以下是本次唯一台账，不以未提及等同于已关闭：

| 本次沿用编号 | 旧编号对应 | 证据状态与处置 |
| --- | --- | --- |
| RR-01 | IC-01；IR-02 的恢复端 | 源码确认的 P2 逻辑缺陷。修复前先在真实持久化/生产排程链建立有区分力的反例，再修复。 |
| RR-02 | IC-V1；V-01 的睡眠自动写入分支 | 未接入互斥的结构事实已确认；该睡眠路径的原生等待时长、错误和恢复尚未实测。必须有界原生验证，确认则同批最小修复，不冒称已有原生红例。 |
| IC-02 | 后一份 RR 摘要漏列；IR-03 的当前失败收尾 | 源码合同下的 P2 一致性缺口；真实设置页关闭后的完整反例待跑。沿现有挂载测试有界确认；成立则同批修复，若不成立须提供生产链反证。 |
| O-01 | 原 O-01 | 非阻断 UNCONFIRMED；没有新增证据则不改导航，不重复开项。 |

RR-01 的两个旧状态来源不是两个问题：优先使用旧普通编辑改变本次提醒但不应用未来的路径；旧清单删除使 nil 系列时间戳变化的路径作为邻接起点按影响检查。两者均针对隔离后同值明确纠正未换代。不得要求用户通过额外改变时间来绕开。

前次外部审查读到的是固定源码、测试正文与入库运行记录；没有独立取得开发机的全部 xcresult/录屏/实包，也没有复跑 iOS 原生测试。旧 568=567 PASS/0 FAIL/1 SKIP、UI 7/7 等仍是前次版本化开发端证据，不能转记为本 Goal 新 PASS。

## 2. 目标与收敛方法

本次检验的是用户操作结束后的完整结果，而不只是中间字段：任务/规则、用户意图、设备账本、实际 native 请求、可见反馈，以及重试/冷重开后的可用性应一致。发生合法失败时，保留原值和输入；不借保守拒绝之名永久堵住用户已经明确授权的恢复。

每项在实现前写一行“合法起点→生产入口→异步/锁边界→终态→合法相反操作”。从真实旧操作或真实 Service 创建起点。测试替身只负责可控的外部系统结果/错误；不得替换待验证的生产策略。不能仅设置 hasPending=false、generation 改了、error 回调了就判完成。

避免重复整改：保留已认可 IR-01/03/04/05 主体、IR-02 两渠道取消主体与原 V-01 Todo 修复；保留 SR、BV、CR、F5、迁移/原值恢复、计时与独立草稿保护。不重做 A–D，不泛化重构整个提醒或存储系统。

## 3. RR-01：被隔离规则的同值明确恢复

### 源码依据（均绑定已审版本）

- [当前 TodoFoundation](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOS/Todo/TodoFoundation.swift)：`edit`、`setIntent`、`reminderOffset(for:)`、`applyTemplate`、`refreshRepeatingReminderTimes`。
- [旧 f1 TodoFoundation](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/Todo/TodoFoundation.swift)：旧 `edit` 没有当前的保留偏移前置处理；旧普通编辑可保留 nil 偏移与 false 覆盖标记。旧 `deleteList` 也可能改变系列时间戳而不固定偏移。
- [设备账本与排程](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOS/Todo/TodoAlarmReminders.swift)：`quarantineFutureRequests`、`retireObsoleteRequests`、`reconcile`。
- [实际编辑入口](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOS/Todo/TodoViews.swift)：`TodoEditorView.save`。
- [已有集成测试](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOSTests/ImportExportRecoveryTests.swift)：`testIntegrationIR02BothOwnedFutureChannelsCancelConfirmColdReopenAndCorrect`。

### 触发与现有盲区

真实 V11 nil 偏移系列，经旧 f1 普通编辑修改本次提醒、不应用未来，形成 `isInstanceOverride=false` 的合法旧状态；其未来请求已被接受。升级后跨区刷新不能安全推导旧规则，隔离取消请求并留下 G 代次的 retired。用户保持当前提醒时间/渠道，明确应用到未来并保存，系列偏移被补齐，但 `setIntent` 只有 renew/渠道变化/覆盖标记变化才换代；本例全部不成立，仍是 G。调度看到同代次 retired，不安排当前提醒。后续跨区调整 fireAt 也不会自动释放同代次终止记录。

现有两渠道恢复测试从 override=true 开始，并主动更改 fireAt，因此触发了既有换代条件，不能证明上述同值恢复。

### 实现约束

明确识别“确认并恢复被隔离的旧策略”这一有效用户意图，为需要恢复的当前/受影响开放期次建立合适的新身份。不得让所有 retired 自动复活，不得把所有标题/备注/清单编辑或所有 futureSeries 编辑无条件换代。需要额外显式确认时，应在当前纠正入口可见且不丢草稿，不要求改变分钟数绕过。

未知规则不能被猜成已知；取消未确认时不能越过旧所有权安排新的并行提醒。规则纠正保存失败须回滚规则与意图；成功后不要让幂等重试不断换代。若改动持久化模型，先证明非改不可并评估历史 Schema/ZIP；优先复用现有模型与真实语义，不预先升级。

### 必须覆盖的最小验收

1. Notification 与 Alarm 各跑完整链：可追溯旧数据→accepted future→隔离→确认取消→同值/同渠道明确纠正→实际新代次和新请求→冷重开仍正确；业务计划/截止、历史事件不被重写。
2. 同值纠正与改值纠正对照，override=false 与现有 true 对照；取消未确认→纠正→后续确认时不得双重排程或丢所有权。
3. 正常 System Stop、主动停系列、删除/完成/取消、普通元数据修改/刷新不复活；正常 ringing 不误取消；健康 Todo/ImportantDay/Sleep 与容量等待不退化。
4. 修复后的实际编辑器至少证明一次无需改时刻就能完成纠正，检查状态对应真实请求，不以仅 Unit helper 代替入口。

## 4. IC-02：设置页关闭后，当前失败的完整收尾

### 源码依据

- [ReminderFoundation](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOS/App/ReminderFoundation.swift)：`LocalReminderScheduler.update`、`ReminderSettingsUpdate.submit`、共享 Scope。
- [AppShell/MediaStorageView](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOS/AppShell.swift)：关闭控制、enabled 的 onChange、updateDaily/WeeklyReminder、错误回调与重新打开的 task。
- [设置真实挂载测试](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOSTests/AppCompositionTests.swift)：`testIntegrationIR03ActualSettingsSheetCloseReopenSameValueIntent`。
- [外部结果替身与边界测试](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOSTests/ImportantDayReminderTests.swift)：`SystemSettingsLateClient` 及 IR03 的无新 B/旧出口测试。

### 反例与确认方式

已存在正常08:00重复提醒→用户改09:00→真实 scheduler 的 addRepeating 挂起→实际设置 sheet 完全关闭且没有新 B→添加返回普通错误、旧08:00请求仍存在。当前回调把 AppStorage enabled=false；真正的关闭却依赖已移除页面的 onChange。重新打开只读取权限，没有为关闭偏好确认旧请求移除。可能形成开关显示关闭但旧请求仍可提醒。

这是外部 async throws 合同内的场景，不声称某一真实 iOS 已自然发生该故障。必须以已有客户端注入错误、保留生产 updater/scheduler/gate/AppStorage/真实页面移除；先证明存在旧 pending，并观察完整 settle/重开后的偏好、请求、反馈，而不是手动调用 apply 就算 UI 反例。daily 和 weekly 都检查。有真实生产机制保证一致则提交完整反证，不能以正常成功案例或“原生一般不会失败”关闭。

### 成立后的限定修复

由生命周期稳定的所有者负责设置命令的完整结果，页面只展示/发起意图；不能依赖已移除 View 再触发一轮 onChange 来完成必要系统清理。

优先沿现有失败关闭语义，明确撤销该渠道旧/未确认新请求并检查实际不存在；清理未确认时诚实显示待确认/可重试，不伪称完全关闭。另一个合法策略是保留并明确展示已确认的旧配置、提示新修改失败，但不能显示09:00而实际08:00；实现者应选择最小且与现有产品一致的策略并记录，不为普通技术选择停问 Owner。

操作/清理都遵循当前有效意图与共享 gate。不能在旧失败 catch 中无条件删除固定 identifier，从而删除后来的 B；不能因 sheet 关闭而无条件取消所有合法 A。确认失败、旧错误/成功/取消、无新 B 当前错误/成功、新 B 同值/不同值/关闭、两渠道独立，以及失败后重开反馈都应有最终状态断言。必要的反馈保留在稳定 owner；生命周期结束不能吞掉用户需要知晓的当前失败。

## 5. RR-02：raw 导出与睡眠自动生效写入

### 源码依据与已知事实

- [AppShell](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOS/AppShell.swift)：active 时先 sleepWorkspace.refresh，随后才 await importShares。
- [SleepViews](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOS/Sleep/SleepViews.swift)：`SleepWorkspace.refresh` 先调用 observe，错误统一转 corrupt。
- [SleepFoundation](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOS/Sleep/SleepFoundation.swift)：`setGoal` 创建未来待生效目标，`SleepGoalSemantics.observe` 在 MainActor 直接 save。
- [StorePublication](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOS/ExternalCapture/ExternalCaptureImport.swift)、[raw capture](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOS/App/AppContainer.swift)、[导出入口](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOS/ImportExport/ImportExportService.swift)。
- [可复用 V01 原生实验](https://github.com/yoCruzer/PersonalGrowthOS/blob/53eeb1d3410630f836bbc3e713c79f9f157a4081/PersonalGrowthOSTests/ImportExportRecoveryTests.swift)：`testIntegrationV01RawWriterActualAlarmJournalSaveAndIndependentMainProbe`。

当前只确认睡眠自动保存未加入同一互斥；不能用已经通过的 Todo 保存实验替代睡眠实验，也不能只凭源代码宣布已原生复现阻塞。

### 有界原生实验与处置

用真实 SleepService 设置次日生效目标；受控业务时钟跨到生效日，保持原模型/验证合法。真实 exportRetainedQuantityData 已进入 BEGIN IMMEDIATE 且持有 writer 后，经实际前台刷新使用的 SleepWorkspace.refresh→observe 尝试保存。独立执行器在实际保存入口之后提交 MainActor probe，并设独立 fail-safe、外层超时、唯一合成根目录与可靠释放，不能让红例锁死整轮测试。

记录 writer-held、生产观察/保存入口、probe 提交/执行、保存成功/错误、实际 ROLLBACK 与后续恢复的因果。必须真的命中待生效规则和保存；无变化/未触发不能判安全。不得用手写 SQLite UPDATE 替代 SwiftData.save，不修改宿主时间或真实账户。

确认主线程等待或终态错误，则复用现有发布保护做最小修复。主线程不等待后台发布锁；后台仍保留一致快照。等待后重读权威状态，不重放过期 ModelContext/旧规则，不产生无限重试或重复事件。busy 与数据损坏区分，保留输入/事实与诚实反馈，锁释放后有可靠恢复路径。失败时不伪称生效标记已经持久化；跨区/时钟回拨不使已经生效的规则重新成为可改历史，覆盖延后保存与后续状态变化的相反操作。

只对导出期间真实可达的自动写入口列有限核对表：根页面前后台、Todo journal/时区对账、Sleep observe、Investment checkpoint、Share importer。每项标明使用同锁、已串行隔离、只读或需要同因补修的证据。不要仅按函数名字判断，只因修共享锁产生的同类可达缺口纳入本批；不要扩成全仓储重写。

补验原 raw SQLite/媒体保留、原非有限数量 bitPattern/ID/unit/result、原图字节、旧 V01 Todo、计时 checkpoint/晚暂停完成，以及正常无竞争睡眠目标生效。RR-02 最终只能记为 VERIFIED_SAFE、DISPROVED 或 CONFIRMED_AND_FIXED，均须真实原生结论；VALIDATION_BLOCKED 不得写 READY。

## 6. TF-A→TF-D 连续执行

### TF-A：轻量续接与红例

按 AGENTS/INDEX/Development Contract 读取必要上下文及两份 CURRENT 最新章节，fetch 后核对 PR/head/base、工作树和祖先关系，安全续接原 worktree，保留主目录未知改动及后续有效提交。不得 reset 重建旧基线、force push、自动合入其他 PR。只接收规格不执行一轮全量基线。

接收本固定 Goal 后，先在两份 CURRENT 顶部追加本轮边界与编号归并，保留旧正文；相应追加 EXECUTION/ACCEPTANCE/REVIEW，状态为 FIXES_IN_PROGRESS。规格投递阶段未重写长历史 CURRENT，不能把旧 READY 当成本次授权不执行的理由。

先登记反例和最终状态矩阵，安排未参与实现的 reviewer 独立提出反例。针对 RR-01/IC-02 建立确定性反例；RR-02 准备有界原生验证。一个环境点阻塞时记录并继续其他可执行项，不伪造结论。

### TF-B：限定修复及邻接闭环

按上述三项实现/验证。每次只跑影响相关测试，先解决同因消费者和相反操作，不做完每小阶段就跑全量 Unit/UI。失败区分产品、夹具、驱动、环境，回归必须重新执行完整方法，不能只验证尾断言。受控日期与原真实链路保持。

### TF-C：固定候选集中验证与独立复核

收敛后固定干净产品/测试 SHA，执行一次完整 Unit、必要关键 UI/挂载场景、Debug 与 unsigned generic iOS Release，读取实际 App/Share/Widget 的原身份、版本、provenance、AlarmKit 弱链接与用途说明。不是 Archive。纯文档追加不重建。

关键场景至少覆盖同值纠正规则入口、设置关闭后的失败/新意图保护、睡眠导出竞争与恢复。已有实际挂载 Unit 证明页面生命周期时不机械重复同义 UI；用 UI 验证必要可达性/可见错误和布局。无影响旧 UI 按路径/依赖/候选关系记录复用，不冒称重跑全部矩阵。

reviewer 不写本轮实现，在固定候选上检查完整相关调用链、未改消费者、真实起点、终态和反向操作，读取本机原始 log/xcresult/必要截图与实包，不凭 PASS 总数或实现者关闭表放行。确认的范围内问题继续本轮闭环并复核。无具体触发/证据的架构担忧不无限阻断，不把 O-01 升格。

### TF-D：交付与停点

更新两份 CURRENT、EXECUTION、ACCEPTANCE、REVIEW、PR 描述；新运行台账可用 `Docs/USAGE_REMEDIATION_20261019_TERMINAL_FIX_RUNS.json`，不得重写上一轮38轮记录。保留原始 FAIL/SKIP/NOT_RUN 与补验，不拼称所有历史一次全绿。

普通 commit/push 唯一原分支，PR 保持 OPEN Draft/base 不变。分开列产品/测试 SHA 和纯文档交付 SHA，核对远端及任务工作树；未知改动保留，不能把主目录未经核对说成干净。

完成条件：RR-01 修复或严格生产反证；IC-02 经真实页面链确认并修复或严格反证；RR-02 原生结论明确且确认问题已修复；必要本地验证和独立终审完成，无未关闭范围内 confirmed P0/P1/P2。此时才恢复 READY_FOR_OWNER_DEVICE_GATE，否则诚实保留 FIX_REQUIRED/VALIDATION_BLOCKED 并给出明确阻塞。

## 7. 不变边界与最终回复

不操作私人设备/库，不签名安装、不卸载覆盖升级、不 merge、force push、tag、Archive、TestFlight，不改变其他 PR/base/Bundle ID/主库路径，不清理私人样本，不引入付费服务或额外外部依赖。

D1–D4 NOT_PASSED、AlarmKit 原生正向 NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间 SKIP/NOT_RUN、远端 CI NOT_RUN 保留；本次没有授权补建 CI 或操作系统原生权限来把这些门刷绿。

最终中文简报给出：逐项处置/可追溯证据、真实测试分轮与复用、产品/测试及交付 SHA、PR/工作树状态、剩余设备门。不要只写“独立终审无问题”。若仍有下一步必要修复，交付应同时给出可执行续接 prompt 或明确的账号/权限阻塞，不再以“要不要我准备 prompt”增加无意义往返。
