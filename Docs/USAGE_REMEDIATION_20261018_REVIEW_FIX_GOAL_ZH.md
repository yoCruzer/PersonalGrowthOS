# PR #13 独立复核后的本地修复目标

版本：1.0；日期：2026-10-18；初始状态：**FIX_GOAL_READY / LOCAL_REVIEW_FIX_REQUIRED**。

本文件已由 Owner 的“可以，请继续”批准作为下一轮 Codex 执行目标。当前提交只准备修复规格与交接记录，**尚未修改产品代码、运行本轮原生测试或关闭下列问题**。

## 1. 固定身份与执行授权

| 身份 | 固定值 |
| --- | --- |
| 仓库 / 唯一目标 PR | `yoCruzer/PersonalGrowthOS` / [Draft PR #13](https://github.com/yoCruzer/PersonalGrowthOS/pull/13) |
| 继续开发的分支 | `codex/usage-remediation-20261017` |
| PR base 分支 / 原 BASE | `codex/time-investment-v1` / `5a70f0110b151f8a45ac7c33d3f443823b1cff24` |
| 原整改 GOAL_SHA | `68373d4edf10cff8ca3e212b9ff10a28e6da9c73` |
| 已审查产品 / 测试 / 原实包提交 | `9601ff211fbdafc954e32f9e25206a38479e972b` |
| 已审查交付提交 REVIEWED_DELIVERY_SHA | `f1b52b58fd11c41f508ec665d583827879ffa202` |
| 本修复规格 FIX_GOAL_SHA | 以 Owner 引导 prompt 指定的完整提交 SHA 为准；从该提交读取本文件，避免文件内自引用 |

这是同一整改目标、同一 PR 的后续本地修复批次。连续完成核实、修复、必要回归、独立审查、普通 push 和交接；不在方案完成、单个阶段结束或首轮 review 后停下来要求重复授权。允许范围内必要的生产代码、测试、局部查询结构和文档修改。实现方案由 Codex 根据当前代码选择，本文件规定可观察结果与必须保护的行为。

本授权替代旧 CURRENT / 验收文档中“本地已完成、下一步仅等待 Owner D1–D4”的停点，**只替代这一局部修复的执行停点**。原始运行结果和 D1–D4 的真实状态保留。不得将旧 R1–R8 已关闭等同于本次新发现已经关闭。

本文件使用的 **F1–F5** 是 2026-10-18 外部独立复核编号；**UX1 / UX2** 是本轮确定的日期交互决策。它们与旧 PR #13 R1–R8、时间投入 V1 的历史 F1 / R1–R3 分开记录。

## 2. 开工与连续执行方式

1. 按 `AGENTS.md` 阅读 INDEX、已存在的 Foundation、DEVELOPMENT_CONTRACT、CURRENT，再读固定 FIX_GOAL_SHA 的本文件，以及原整改 GOAL / DESIGN / ACCEPTANCE / REVIEW。`ROADMAP.md` 的 Planned 状态不阻塞开工。
2. 先核对 git status、worktree、分支、PR head/base 和 FIX_GOAL_SHA 祖先关系。优先继续原任务工作树；如仍在 f1，安全 fetch / fast-forward 到包含规格的分支。保留未知改动，必要时隔离；不要 reset、从旧 BASE 重建产品、覆盖并发提交或创建重复 PR。若 PR 已有后续代码，逐项核对问题是否仍存在并保留进展。
3. 先用最小、生产路径可达的回归复现 F1–F4，确认 F5 的真实调用链和成本边界。可只读并行分析，涉及同一文件的写入及 Xcode 执行串行安排。无需开工先重跑全部历史测试或重复研究竞品。
4. 建议内部顺序：**RF-A 提醒 F1–F3 → RF-B 体重 F4 / UX2 → RF-C 时间投入 F5 / UX1 → RF-D 集中验证与独立复核**。阶段属于一个授权批次，可以按依赖调整，不新增阶段批准流程。
5. 修复与验证完成后普通提交并推送同一分支，更新现有 Draft PR 的交接信息。固定最终产品 / 测试 SHA，随后只提交交付文档时明确区分产品 SHA 与交付 SHA。

## 3. 问题与修复验收

下面的源码位置均指固定 `f1b52b58fd11c41f508ec665d583827879ffa202`，只作为导航依据；以完整调用链为准。外部复核在源码与测试层完成，未在本环境执行 Xcode 或声称真机通过。

### F1 — 被撤回的后继再次启用后仍沿用已退休的提醒代次（P2）

**证据与触发**：`Todo/TodoFoundation.swift` 的 `reopen` 撤回当前后继，`advance` 再次完成前一任务时复用该后继；复用路径只在提醒时间改变时更新代次。`Todo/TodoAlarmReminders.swift` 的对账已将该代次取消并退休，再次启用相同时间的后继会被判定为 stopped。直接 reopen 当前任务已有换代逻辑，不能据此认为“撤回后继再复用”也得到覆盖。

固定源码：[后继撤回与复用](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/Todo/TodoFoundation.swift#L519-L593)、[意图对账](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/Todo/TodoAlarmReminders.swift#L234-L349)。旧 `TodoFoundationTests` 的 reopen 循环未接提醒协调器，旧 reminder reopen 测试覆盖的是直接重开。

**要求**：仅在确实从 `successorWithdrawn` 重新启用时建立有效的新提醒代次，保持期次身份、计划日期、时间和渠道正确。同样的对账、刷新、改标题不得反复换代；用户主动停止或已消费的提醒不能因此自动复活。

**验收**：创建未来每日提醒 A → 完成 A → 实际协调器安排 B → 重开 A → 对账确认 B 已取消 → 当天再次完成 A → B 再次拥有且只拥有一个有效请求。普通通知和 AlarmKit adapter 各验证应用协调器路径；重复 reconcile、真实落盘重开仍幂等。补充取消失败分支：任务重新启用及新提醒意图可先原子落盘；旧请求未确认消失时保留其 ownership，并阻止同系列冲突请求的系统排程。确认旧请求已取消后，才能安排新的系统请求。Fake 能证明应用行为，不能写成 AlarmKit 原生正向调用通过。

### F2 — 真正旧库的 nil 系列提醒偏移会被单次改期污染（P2）

**证据与触发**：旧系列的 `reminderDayOffset` 可为 nil，现有逻辑从期次的可变提醒墙钟字段推断。单次“明天同一时间提醒”先覆盖了唯一旧实例的原值，完成 / 跳过时又用覆盖后的值推断系列偏移：短延期可把未来系列整体偏移；超过 366 天可能触发 `invalidReminderOffset`，使事务回滚且无法完成 / 跳过；改了分钟还可能丢失原来的提前一天规则。

固定源码：[单次改期与偏移推导](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/Todo/TodoFoundation.swift#L419-L454)、[完成与跳过](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/Todo/TodoFoundation.swift#L554-L593)。现有 long elapsed 测试显式设置 offset=0；含早期已完成实例的迁移夹具也会掩盖此缺口。

**要求**：覆盖原字段之前，从可靠的旧规则 / 旧实例 / 旧事件恢复原系列偏移，与此次任务及事件 / 提醒意图变更原子保存；或采用能保留同样信息的等价方案。不得简单忽略 override 后默认 0、放宽 366 天约束、改变计划日 / 截止日 / 系列锚点，或修改历史事件字节来迎合测试。

**验收**：使用真实旧模型（包括 V11.0）和对应旧备份 v7 的有效单一未完成实例，初始 offset=nil、没有早期完成实例代为提供线索。以代表性参数覆盖原偏移 0 / -1、短期 / 超过 366 天、同分钟 / 改分钟，覆盖 complete 与 skip；单次提醒按用户意愿改变，后续系列仍使用原偏移。验证落盘重开及导出 / 恢复；注入保存失败，任务、事件、提醒意图与偏移一起回滚且不调度。使用合理的参数化覆盖即可，无需机械展开全部组合。

### F3 — 已接受的 Todo 通知退出共享队列分配，新增更早提醒无法获得位置（P2）

**证据与触发**：`TodoReminders.swift` 排除已有 accepted / prepared / cancelPending ownership 的 Todo，又把其请求当成保留占用；在队列满时，已接受的较晚 Todo 不能参加新一轮优先分配。59 个必须保留的外部请求 + 1 个较晚 Todo 已接受后，再新增 10 分钟后的 Todo，会一直 queueFull。新增 ImportantDay / Sleep 也可能无法置换较晚 Todo。初次空队列排序正确不能证明后续重排正确。

固定源码：[共享规划及保留项](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/Todo/TodoReminders.swift#L174-L230)、[队列满分支](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/Todo/TodoAlarmReminders.swift#L321-L349)。这里的 **60 是应用当前保守的普通通知预算**，不是本文件宣称的系统硬上限，也不是 AlarmKit 容量。

**要求**：受本应用管理的普通通知，包括已接受的新 ownership Todo、兼容旧 Todo、ImportantDay / Sleep，应继续参加同一个既定时间优先与类别公平规划。被预算暂缓的提醒保持用户意图，在有位置后可以恢复；必须与主动停止、已消费、已退休代次区分。重新安排前先确认旧请求取消；保留 MutationGate、取消不确定时的占用及同系列后继阻塞。AlarmKit 使用自身策略。

**验收**：上述满队列场景下，更早 E 被安排、较晚 L 进入可恢复等待；E 完成并释放位置后 L 能恢复，原 59 项保持，身份 / 时间 / 用户意图正确。覆盖 Todo→Todo、至少一项“新增 ImportantDay / Sleep 置换旧 Todo”的方向及既有类别公平回归；取消失败与恢复期间不超预算、不双排、不复活已停止项。不得用删掉全部 journal、将所有 retired 统一视为可重试或只改首次排序来通过。

### F4 — 体重分页的旧异步结果能覆盖新的日期查询（P2）

**证据与触发**：`WeightMeasurementPage` 的加载更多 / 重试使用独立 Task；其完成校验比较的是旧 View 值捕获的 key，而非共享状态中当前查询。A 日先显示 50 条，加载 A 第二页未完成时切到 B；B 已返回后 A 才返回，会改写共享 records / loadedKey。再切回 A 可能误判已经加载，显示 B+A 第二页的混合数据并缺少 A 第一页。

固定源码：[分页任务与提交结果](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/Weight/WeightViews.swift#L199-L287)。现有顺序分页测试与每日期少量记录的 UI 测试没有覆盖此竞态。本问题是展示状态串线，不声称源数据库已被写坏。

**要求**：初始加载、更多、重试都归属当前查询，查询改变时取消旧任务，并在提交结果时核对共享的当前 query / generation。不得继续用同一个旧值两次相等作为有效性证明。可用稳定 loader 对象或等效的结构化任务方案，不限定新架构。

**验收**：可控 reader 挂起 A 第二页，先让 B 完成，再允许 A 完成，证明 B 不被改写；返回 A 必须得到完整正确第一页及后续分页。覆盖重试和刷新失效共用保护；记录保存 / 删除、日期 / 时区切换使旧结果失效。计数、页内容与截止快照一致。以确定性调度测试为主，不依赖随机快速点击“未出现”证明正确。

### F5 — 时间投入仍在草稿变动时全量读取历史，详情分页只是末端切片（P2，原 T7 未完成项）

**性质与证据**：此成本在 PR 前已有，不能记成这次新引入的回归；PR #13 已复用部分日贡献统计，但还没有完成原批准 T7。`InvestmentWorkspace.refresh()` 在检查 session 是否相等前，全量 fetch / DTO 解码 Session 与 Operation；备注 / 时长输入持久化发出 `investmentChanged`，AppShell 再触发该 refresh。历史视图另取 20 条时，workspace 仍常驻全量、含备注和完整分段的 SessionDTO；单条详情继续从该数组读取。

固定源码：[workspace 与 checkpoint](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L74-L124)、[草稿输入](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L458-L499)、[历史与详情](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L703-L742)、[事务通知](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/TimeInvestment/InvestmentFoundation.swift#L266-L275)。已有 10,000 条夹具只记录首次 refresh 耗时及统计 generation，不能证明每次草稿保存的生产链没有重复 I/O 和解码。

**必须达到的结果**：

1. 没有正式 Session 变更的草稿文字 / 时长、计时状态和 checkpoint，不再触发 UI 刷新对全部 Session 或全部已保存 Operation payload 的读取和解码。可以采用有类型的变更事件、受影响 ID、未完成操作缓存等局部方案；统计不变时不重建正式历史事实。单个草稿 / 操作查找应尽量按 ID；checkpoint 使用有效的未完成操作集合并正确恢复冷启动状态。
2. workspace 不再把全部完整 SessionDTO 当作历史详情存储。统计保留轻量的活动 / 日期贡献、稳定 ID 与排序字段；完整备注和分段按历史 **20 条一页**及单个 ID 详情读取。编辑器、重复候选和路由消费者一并适配，不能只是把 ForEach 改为 20 项。
3. 期间 / 日期 / 页切换和活动重命名 / 归档复用可用的轻量事实；重命名只需更新相关元数据。正式记录新增 / 编辑 / 删除、导入 / 恢复、参与者范围变化时正确失效并更新统计、ID 集合、页面和详情；旧异步结果不能回写新快照。
4. 初始加载、冷启动、导入、参与者变化或正式 Session 变更，可进行一次必要的批次读取 / 统计重建。允许逐批临时解码完整旧 payload 后释放不需要的备注 / 分段，再保存轻量聚合；不强制实现增量数据库、物化视图、新 Schema 或通用缓存平台。必要重工作脱离主线程或分批，UI 状态更新遵守隔离要求。
5. 保存命令中的重复、重叠、冲突、业务完整性校验，与“UI 因草稿通知而重复加载历史”分开统计。不得为满足读取计数删除必要校验或把所有业务扫描机械限制为 20 条；保留扫描时注明真实用途及触发范围。仅为查找某 ID 而全量展开记录的路径应局部改进。
6. 真实读取失败显示可重试错误，不能以零时长 / 空数组伪装成功。历史 R1 的已消费 / 已删除内容清除必须同时覆盖缓存与编辑器；R2 的失败保存保留输入、最后成功草稿可恢复、关闭与 checkpoint 语义必须保持。不得通过取消持久化或仅增加 debounce 来消除刷新成本。

**验收**：在真实落盘的 10,000 个有效 Session 及成对 Operation 夹具上复用现有设施，适量记录含较长备注和多分段。首次加载后，经真实 Service → 变更事件 → Workspace 链连续成功保存多次草稿，再执行后台 checkpoint / 暂停 / 继续，用读取与解码计数证明没有额外 UI 引起的正式全历史扫描；重开能恢复最后成功保存的草稿。分别验证第二页、单条详情的有限读取及正确 ID，正式编辑 / 删除 / 导入后的统计、列表、详情和旧结果失效；故障注入覆盖读取失败及 R2 保存失败。可注入生产读取接口计数，不能只测脱离事件链的 helper 或 generation。

记录实际环境、耗时 / 内存观察与计数口径，不用跨硬件任意毫秒阈值制造假门槛，也不强制无助于结论的 Instruments 批次。证明达到上述边界后停止额外性能测试。仅将相同全量任务搬到后台、解码后比较相等、在全量数组上再切 20 条，都不能关闭 F5。

### UX1 — 时间投入选中当前期间之外的日期时，自动切换“全部累计”

这是交互清晰度决策，原复核未将其冒充已确认数据损坏。现确定行为：用户在最近 7 / 30 天中主动选择窗口外日期，同一次交互切换到 **全部累计**，保留所选日期与活动过滤，并让月份预览定位到该日期。窗口内日期继续使用原期间。不能被原 `.onChange(days)` 随后清空刚选的日期。

界面明确显示“全部累计”、实际选中日期及该日统计；可用简短行内说明“已切换全部累计，查看所选日期”，不增加确认弹窗。无记录日期诚实显示空状态。清除日期选择后保留当前已显示期间；用户主动更换期间 / 活动时可按现有合理规则清除日期，但不得隐式回退期间。

**验收**：固定 today=2026-10-18，最近 7 天视图选择 9 月 1 日（该日有 45 分钟 / 1 条记录），自动切至全部累计，所选日期保持 9 月 1 日、月份为 9 月、数值为该日 45 分钟 / 1 条，不显示零或全部历史总和；再测窗口内日期、无记录日期、清除选择及活动过滤。

### UX2 — 体重主页面最近记录遵守当前截止快照

体重主页面未选具体日期时，“最近 5 条”表示 **截至当前快照截止日的最近记录**：下界不强加趋势窗口开始日，上界使用 snapshot.endExclusive，且记录时间遵守 snapshot.now；处于历史截止日时标题写明“截至 X 的最近记录”。选择具体日期的查询上界也不能越过 cutoff，日期选择范围不晚于 asOf；修改截止日要清理不兼容选择并使旧查询失效。

独立的“全部体重记录”保持全历史管理用途，可以寻找截止日以后的记录；不要把主页面 cutoff 传成全局过滤而使旧记录无法管理。现有未来记录标记 / 编辑等语义保持，时区规则沿用同一快照。

**验收**：固定 today=2026-10-18，有 10 月 1 日与 17 日记录；主页面截止设为 10 月 10 日，最近列表只出现 1 日，清除具体日期选择后仍如此；进入全部记录仍能查询 17 日。覆盖编辑日期、删除、时区刷新和旧加载任务晚返回，图表 / 计数 / 主页面列表的截止一致。

## 4. 兼容性与既有保护

- 保留五 Tab、Record 独立草稿、清单管理、星期重复、成长日聚合、体重日均 / BMI、只读入口不创建默认参与者等已批准行为。范围内正常回归可以修复，不拓展时间投入 AlarmKit / Live Activities、新模块、AI、家庭、HealthKit、云端或第三方依赖。
- 保留已存在 Schema V1–V15 的固定历史模型及对应历史备份兼容性，当前候选 V15 / 备份 v11 必须可继续读写和恢复。优先使用现有字段与局部内存结构；若修复确实需要新持久化能力，只做必要的追加版本，并完整证明旧候选迁移 / 导出 / 恢复，禁止改写历史模型校验和来掩盖迁移问题。
- 提醒保持每个系列单个有效当前期次、普通通知与 AlarmKit 渠道互斥、Stop 不完成任务、取消确认后才能安排冲突请求、旧回调不复活、恢复的是用户意图而非另一设备队列 / 权限。
- 时间投入保持 ContinuousClock、continuous-v1 进程域、50ms / 18h 墙钟一致性保护、暂停不计时、25 分钟倒计时晚 50 分钟返回仍封顶 25 分钟、显式继续才新计时、结束冻结与跨进程待确认；草稿 / checkpoint / 备份能够恢复。历史 R1 消费或删除后清理内容、R2 保存失败保留输入且只在必要保存成功后关闭、R3 覆盖多段需明确确认且取消 / 手势退出保留原值，都要保持。
- 不改变原 Bundle IDs、共享容器、最低系统 / signing / 版本发布策略来规避编译或验收问题。不动未知用户工作区、旧 PR 或私人数据库。

## 5. 验证、独立复核与交付

### 5.1 实现与验证记录

每项记录：复现条件、生产入口、修改文件、真实运行命令 / 环境、对应产品 SHA、PASS / FAIL / SKIP / NOT_RUN、局限和后续。先做有区分力的定向回归；问题收敛后运行一轮覆盖所有本次受影响类的 Unit 与关键 UI 组合。仅为剩余具体风险或项目已有必要门禁扩大测试，不每改一份文档重跑全量。

F1–F3 的协调器 / 共享队列属于共同风险，需要一次组合回归；F4 / UX2 与 F5 / UX1 分别验证查询切换和统计一致性。UI 至少覆盖体重分页切日及截止、时间投入窗口外选日 / 历史详情 / 草稿保留、既有混合 Today 导航与独立 Record 草稿；针对真正改变的界面检查默认 / 最大动态字体和 Light / Dark，保留可追溯截图。不要仅改断言、删警告或略过旧失败来制造通过。

收敛的干净产品 / 测试提交完成一次 Debug Simulator 构建（有效 build-for-testing 可计入）与一次 unsigned generic iOS Release，串行执行 Xcode。核对两种配置的 App / Share / Widget 实包身份、原版本 / minOS、App provenance、AlarmKit 弱链接；沿用现有 proof 设施，不新增发行流程。构建后仅追加 Markdown 交付记录，允许引用相同产品 SHA 的实包证据而不重复构建。

旧失败轮次与补验逐轮保留；不同轮次 PASS 数不得拼成“整套全绿”。历史结果可以引用其固定 SHA，不能当作修改后同候选测试。远端 workflows / checks 为空仍为 CI NOT_RUN，无需为本轮另建 CI。

### 5.2 独立只读复核

安排至少一个没有编写本轮修复代码的独立 reviewer，对固定产品 SHA、diff、相关源文件 / 测试和原始运行证据进行只读检查。重点检查 F1–F3 联动、真实旧 nil fixture、旧异步结果拒绝、F5 实际生产通知链与读取边界、R1–R3 / 取消确认 / 恢复兼容性。reviewer 的原始结论入既有 REVIEW 文档，实施者修复后再核对关闭；不由实施者代写“独立全部通过”。

若当前代码已消除某个发现，以固定代码与有区分力的生产路径证据标记“不再复现 / 已由后续提交修复”，不要重复实现。若认为某项判断不成立，提交明确反证与边界，不静默改成低优先级或已知债务；尤其原 T7 的必达结果不能通过重命名来豁免。合理的新本地回归继续修复直至收敛。

### 5.3 完成停点

只有 F1–F5 的必达要求、UX1 / UX2 的确定交互、必要本地回归、双构建与独立复核均有同候选有效证据，且范围内无已确认未关闭 P0 / P1 / P2，才能将 CURRENT 恢复为 **READY_FOR_OWNER_DEVICE_GATE**。不可运行的本地必需项真实记为 VALIDATION_BLOCKED；修复未完成记为 FIXES_IN_PROGRESS / REVIEW_BLOCKED，先完成其余可执行工作，不伪报关闭。

更新本文件的执行摘要或既有 REVIEW / ACCEPTANCE，并更新两份 CURRENT：逐项 F1–F5 / UX1 / UX2 状态、固定产品与交付 SHA、真实失败与补验、独立审查原文、剩余设备门。普通 push 到既有分支，PR #13 保持 Draft、base 保持原分支，不创建重复 PR。

**不包含的设备 / 发行操作**：D1 权限及真实锁屏 / 静音 / 专注响铃、Stop / Open、取消确认；D2 硬件睡眠计时与恢复；D3 Owner 独立备份、签名后不卸载覆盖升级和私人库核对；D4 真实 VoiceOver / Photos / 分享 / 桌面 Widget / 离线组合，仍等待 Owner 后续设备授权。本轮不操作私人手机 / 私人库，不签名安装、不 merge、force push、tag、Archive 或 TestFlight。

保留原已知状态：AlarmKit 原生正向调用 NOT_RUN；Public Share **FAIL/environment**；unsigned Safari **FAIL**；物理低空间 **SKIP/NOT_RUN**；签名 / 真机 D1–D4 与远端 CI **NOT_RUN**。这些不阻止已授权的本地修复，也不能被模拟器、fake 或文档准备改成 PASS。

## 6. 本规格准备时的验收基线

| 编号 | 初始状态 | 下一步证据 |
| --- | --- | --- |
| F1 | OPEN / 本轮执行 NOT_RUN | 撤回后继复用、两渠道协调器与取消失败恢复 |
| F2 | OPEN / 本轮执行 NOT_RUN | 真旧 nil 系列、单期改期、完成 / 跳过及原子恢复 |
| F3 | OPEN / 本轮执行 NOT_RUN | 已接受项参与共享重排、跨类别、等待恢复与取消失败 |
| F4 | OPEN / 本轮执行 NOT_RUN | A 第二页晚于 B 返回的确定性复现与修复 |
| F5 | OPEN / 本轮执行 NOT_RUN | 10,000 条真实链读取 / 解码计数、20 条分页与缓存失效 |
| UX1 | 决策已确定 / 实现验收 NOT_RUN | 期间外选日自动全部累计并保留日期 / 月份 / 活动 |
| UX2 | 决策已确定 / 实现验收 NOT_RUN | 主页面最近记录遵守截止、独立全历史仍可管理 |

关联文档：[原 GOAL](USAGE_REMEDIATION_20261017_GOAL_ZH.md)、[原 DESIGN](USAGE_REMEDIATION_20261017_DESIGN_ZH.md)、[验收矩阵](USAGE_REMEDIATION_20261017_ACCEPTANCE_ZH.md)、[独立审查记录](USAGE_REMEDIATION_20261017_REVIEW_ZH.md)、[当前状态](CURRENT_STATE.md)、[当前任务](CURRENT_TASK.md)。
