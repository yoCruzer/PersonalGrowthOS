# PR #13 第二轮独立复核后的限定修复目标

版本：1.0；日期：2026-10-18；规格状态：**FIX_GOAL_READY / LOCAL_REVIEW_FIX_REQUIRED**。

Owner 已批准将本轮独立 review 转为 Codex 连续执行目标。本次文档提交只固定问题、范围与交接；**没有修改产品、运行新一轮原生测试或关闭 CR-01～CR-06**。本文件替代此前“下一步仅等待 Owner 设备门”的本地执行停点；旧运行结果、已认可修复和未通过的设备门保留。

## 1. 身份、授权与续接

| 项目 | 固定身份 |
| --- | --- |
| 仓库 / 唯一目标 PR | `yoCruzer/PersonalGrowthOS` / [Draft PR #13](https://github.com/yoCruzer/PersonalGrowthOS/pull/13) |
| 继续开发分支 | `codex/usage-remediation-20261017` |
| PR base 分支 / 原 BASE | `codex/time-investment-v1` / `5a70f0110b151f8a45ac7c33d3f443823b1cff24` |
| 本轮已审交付 REVIEWED_DELIVERY_SHA | `e75ac56110cb9c4f58158eaf494087b2ed946324` |
| 本轮已审产品 / 测试 REVIEWED_PRODUCT_SHA | `597552a020eab22673feed108d8676359efd8822` |
| 上一轮修复规格 FIX_GOAL_SHA | `2add10b0c67d064b7e77478fb18a11479d3c94dc` |
| 本文件 FIX2_GOAL_SHA | 由 Owner 引导 prompt 指定完整提交 SHA；读取该提交的本文件，避免文件内自引用 |

这是同一 PR 的第二轮限定补修。允许必要的生产代码、测试、局部状态恢复与文档修改；连续完成核实、修复、按影响验证、独立复核、普通提交和 push，更新现有 Draft PR 的交接信息。内部阶段不新增批准停点，不在写完方案、首次测试或首次 review 后停下来要求 Owner 再说“继续”。本轮交流与交接优先中文。

开工按 `AGENTS.md` 顺序读取 INDEX / 已存在 Foundation、DEVELOPMENT_CONTRACT、两份 CURRENT，再读本文件、上一轮 FIX_GOAL 及相关 ACCEPTANCE / REVIEW / EXECUTION 最新章节。同一会话已读且未变化的长期文档可复用上下文；聚焦本轮改动，ROADMAP 的 Planned 不阻塞开工。

轻量核对 git status、worktree、分支、远端 head/base 和 FIX2_GOAL_SHA 祖先关系。优先续接原任务 worktree，安全 fetch / fast-forward 到包含本规格的原分支；保留主工作区未知改动。若已有后续有效提交，核对问题现状并保留进展，不能退回固定基线覆盖新代码。不要 reset/clean/stash 未知改动、从原 BASE 重建 A–D、创建重复 PR 或更换 PR base。规格提交只改 Markdown，不需要为接收规格先跑构建或全量测试。

## 2. 范围与编号

本轮 **CR-01～CR-06** 与旧 F1–F5、UX1/UX2、R1–R8 分开记录；**OBS-01/02** 是限定补验事项，不预先算作普通生产 confirmed P2。

| 编号 | 性质 / 初始状态 | 本轮必须处理的结果 |
| --- | --- | --- |
| CR-01 | P2，OPEN | 容量取消跨过原提醒时间后仍能完成确认并显示正确过期动作 |
| CR-02 | P2，OPEN | 容量取消原因两次真实写入失败不会把等待意图误变为已停止 |
| CR-03 | P2，OPEN | 旧候选已经保存过单次覆盖的 nil 系列仍可正确继续 / 恢复 |
| CR-04 | P3，OPEN | 正式候选记录编辑 / 删除后，其他草稿的重复候选失效 |
| CR-05 | P3，OPEN | 计时保存成功后有有效去向或明确结果，外层不留下空表单 |
| CR-06 | P3，OPEN | 体重截止 UI 测试不依赖执行当天的年月 |
| OBS-01 | 既有故障契约补验，NOT_RUN | 同一预热 Workspace 在实际落盘后报错时能刷新 / 重试恢复 |
| OBS-02 | 未确认的任务入口观察，NOT_RUN | 有界核验或局部加固；不得冒称已证明实际 UI 竞态 |

原 F1 后继换代、F4 已启动 reader 晚完成保护、UX1/UX2 主要逻辑，以及 F5 生产链有界读取已有实质修复，继续作为保护基线。原 F2/F3 只因本轮明确残留继续修补；不重新开发整个 A–D，不重新调研竞品或扩展产品范围。

建议内部顺序：**RC-A：CR-01～03 提醒恢复 → RC-B：CR-04/05 与 OBS-01 时间投入 → RC-C：CR-06 与 OBS-02 体重 → RC-D：集中验证、独立复核、交付**。可按依赖调整或只读并行分析；同文件写入、数据库测试资源和 Xcode 执行协调串行。

## 3. CR-01～CR-03：提醒恢复

下面当前源码均以 REVIEWED_PRODUCT_SHA 为定位依据。外部 review 基于固定源码、调用链与测试内容，未在 ChatGPT 环境运行 Xcode、模拟器或真机。Codex 须用有区分力的本地回归核实，不把这些源码结论改写为已经实测 PASS。

### CR-01 — 过期后 capacityCancellationPending 没有收敛入口（P2）

**现象与条件**：普通通知已满，较晚 L 为较早 E 让位；容量取消已写入 `capacityCancellationPending`，但系统取消未及时确认。下次对账已跨过 L.fireAt，任务仍 open、意图 / 时间未改变、通知权限仍 allowed。即使 native 请求后来已消失，正常 Recheck 和冷启动仍卡在取消待确认，遮蔽过期后的重新设置入口。完成 / 编辑意图或权限变化可能经其他路径恢复，不宣称所有操作都无解。

**定位**：[retireObsoleteRequests](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/Todo/TodoAlarmReminders.swift#L247) 的恢复条件缺少容量 pending；[rebalanceNotifications](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/Todo/TodoAlarmReminders.swift#L288) 在 `fireAt > now()` 前置过滤后才处理它；[状态](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/Todo/TodoReminders.swift#L150) 与 [UI](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/Todo/TodoViews.swift#L735) 让取消未确认优先于 elapsed。

**要求**：将取消确认与未来排队资格解耦，仍以 native 实际缺失作为确认依据。确认时仍未来的容量等待意图可恢复；确认时已过期则收敛为 elapsed/retired 等正确状态，并提供设置新时间入口，不重排过去的时间。不要一律按普通停止退役而丢失仍未来的等待意图。保留未确认请求占用、同系列冲突阻挡与重复对账幂等。

**最小回归**：使用可推进时钟，先令 L 的移除未确认，再推进跨过 fireAt；分别覆盖 native 已为空，以及仍存在、再次失败后最终取消成功。检查 Recheck、冷启动、重复 reconcile 能收敛，过期不新排通知，未来对照组仍能等待恢复。原 `testReviewFixF3AcceptedNotificationReallocatedAndWaitingRestores` 固定时钟并及时恢复，不能代替本项。

### CR-02 — 容量原因未落盘却移除 native，随后被误当 stopped（P2）

**现象与条件**：L 的 journal 原为 accepted。容量让位时，写 capacityCancellationPending 实际失败，代码继续移除 native 且成功；写 capacityWaiting 也实际失败。数据库仍 accepted、native 已空，后续 accepted 缺失检查把同一意图写成 retired。即使容量释放，也不再自动恢复；用户只能主动重设新代次。

**定位**：[cancel 的写入 / 移除顺序](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/Todo/TodoAlarmReminders.swift#L218) 与 [accepted 缺失即退役](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/Todo/TodoAlarmReminders.swift#L256)。内层 reconcile 再调用 retire，错误可能在同一轮出现，也可能在存储恢复后出现。

**必要限定**：当前 write 已有精确读回确认。必须注入前后两次状态真正未落盘；“commit 抛错但新状态实际保存且读回正确”是已有可成功确认的分支，不能当作本项红例。此项针对普通通知容量让位，不推导 AlarmKit 容量结论。

**要求**：容量让位在破坏性 native 移除前可靠持久化可恢复的原因；保存原因不成功时保留原请求及占用。pending 原因可靠后，最终 waiting 写失败应可在后续对账恢复。明确区分容量等待与主动停止 / 已消费，不能通过删除全部 journal、让全部 retired 自动重排或丢弃停止保护来修复。

**最小回归**：可选择性注入两次 phase 写入未保存的故障，验证旧实现误退役、新实现保留有效意图；恢复存储后重排、释放名额，L 最终可按原意图恢复。再覆盖 pending 已保存而 waiting 写失败、落盘后仅报告错误的对照，重复对账 / 重开不双排、不超应用预算，停止 / 已消费负例继续有效。60 仍仅表示应用当前普通通知预算，不是系统硬上限。

### CR-03 — 旧候选已经保存的 nil + 单次覆盖状态未修复（P2）

**有效历史**：真实 V11 单一 open 实例、series.reminderDayOffset=nil → 在旧候选 f1b52b58 打开 / 迁移 → 旧正式 rescheduleReminder 改期并保存 `.edited` before 与 override → 升级当前候选。旧服务覆盖了实例墙钟字段但没冻结系列偏移；该状态能通过现有校验并保存在 V15 / 备份 v11，不是损坏或人为绕过校验的数据。

**定位**：[旧 f1 改期](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/Todo/TodoFoundation.swift#L419)、[当前首次改期前冻结](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/Todo/TodoFoundation.swift#L412)、[仍从当前实例推导](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/Todo/TodoFoundation.swift#L445)、[生成后继](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/Todo/TodoFoundation.swift#L602)。

**影响**：没有其他可信未覆盖实例时，同分钟短延期会污染后续偏移；改分钟可因候选为空默认 0，丢失原 -1；同分钟且相对期次超过 366 天，会让完成 / 跳过抛 invalidReminderOffset 并事务回滚。当前“真 V11 / v7 → 首次用新服务改期”的新增测试只证明预防逻辑，不能证明修复了旧候选已经写入的覆盖状态。本项是 F2 存量兼容遗漏，不记为本轮新引入。

**要求**：从可信规则历史、事件 before / created 快照或等价可验证来源恢复原偏移，考虑系列曾被正式编辑后的有效规则，不能无条件把最早 created 当永久规则。不得固化已覆盖实例值、忽略 override 后默认 0、放宽 366 天约束、改计划 / 截止 / 锚点，或改写历史事件字节。恢复出的规则与必要业务变更应原子保存，失败保留原数据；原首次覆盖预防逻辑继续有效。若某种合法状态确实无足够依据，明确证明边界并保留事实，不能编造偏移。

**最小回归**：以旧 f1 服务行为可实际产出的有效“已覆盖 nil”V15 / v11 状态为起点，证明其来源和完整性，而不是仅在新版本首次 override。代表性参数覆盖原 0 / -1、同 / 改分钟、短 / 超 366 天，执行直接 complete、skip、再次 reschedule；后继使用原规则且单次覆盖仍按用户输入。复用夹具验证数据库落盘重开、导出 / 恢复与保存失败回滚。历史事件及其中既有快照字节不改写；当前任务 / 系列仅作本次业务必要的原子变更，失败完整回滚。合理参数化即可，不要求机械笛卡尔全组合或安装旧 App 到私人设备。

## 4. CR-04～CR-06：界面和测试收尾

### CR-04 — 正式候选变化后原草稿继续展示旧 duplicateIDs（P3）

**触发**：草稿 A 匹配正式 B → 继续编辑 A → 从候选详情编辑 B，使其不再匹配，或删除 B → 返回输入未变化的 A。现有清理只覆盖 A 自身输入变化及编辑器自身被消费 / 删除；正式变化后的候选页仍读 A 的旧 IDs，可能列出已不匹配记录或空候选页。再次正常保存会真实校验，因此不宣称数据损坏或永久阻挡保存。

定位：[Workspace 清理](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L131)、[候选页](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L553)。

**要求与验收**：正式记录编辑 / 删除后，使相关草稿候选集合和展示状态正确失效 / 重算；候选详情、数量及分页一致，保留 A 的全部未保存输入和最后成功草稿。测修改 / 删除 B 后返回不变的 A，再正常保存；保留仍匹配时真实重复确认。现有用例修改 A 自身时长，不可替代此例。沿用按 ID / 有界详情，不为此让健康草稿按键重新扫描全部历史。

### CR-05 — 计时保存后外层 Timer 留下空表单（P3）

**触发**：开始 → 结束 → 内层确认保存成功，`.saved` 操作退出非终态缓存，外层 sheet 的 operationID 仍存在；Timer 的 `if let op` 无内容，保存只 dismiss 内层编辑器，用户留在空 Timer。正式事实已保存，关闭仍可用。

定位：[Hub / Timer sheet](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L391)、[保存结束](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L617)、[非终态读取](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/TimeInvestment/InvestmentFoundation.swift#L687)。

**要求与验收**：保存成功后关闭外层 Timer / 返回有效 Hub、定位已保存详情，或显示明确完成结果，按现有导航选择最小一致方案。验证正式记录恰好一条、成功后落点有实际内容；失败仍停留可编辑状态并保留输入，取消 / 稍后确认仍有明确语义。不能只断言没有 save-error，也不能为恢复页面把全部已保存 Operation payload 重新放回常驻缓存。

### CR-06 — 体重截止 UI 测试依赖执行年月（P3，测试稳定性）

**定位与问题**：[英文截止测试](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOSUITests/AppLaunchSmokeTests.swift#L2990)、[中文测试](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOSUITests/AppLaunchSmokeTests.swift#L3032)。夹具固定 2026-10-01 / 17；页面初值为 Date()，测试直接点 October 10 / 10月10，未导航或核对完整年份。跨月会找不到可靠目标，下一年同月可能选错年份。

**要求与验收**：页面与测试夹具共用可注入固定测试时钟，或明确导航并验证 2026-10-10 的完整年月日。正常产品日期规则不变，不修改主机时间。证明测试不依赖真实执行月 / 年；可用测试时钟代表 2026-11 与 2027-10，检查目标仍正确。保持截止统计、主页面排除 17 日、全部记录可查看 17 日，以及中英文 / 大字号断言；不用放宽查找或删统计断言换取通过。

## 5. 两项限定补验

### OBS-01 — 实际落盘后报错时，同一 Workspace 的恢复

当前事务只在 commit 正常返回后发布失效；新 Workspace 的刷新 / Retry 依赖版本或 reader 错误。仓库已有 `try context.save(); throw ...` 的故障契约测试，但常通过新容器或 service 直接读库核对，没有覆盖旧 Workspace 的恢复。定位：[事务](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/TimeInvestment/InvestmentFoundation.swift#L270)、[刷新](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L126)。

**本轮做法**：以一个已预热的 Workspace 缓存 running / revision=r，真实 service 暂停在实际保存 paused / r+1 后注入报错，再让同一 Workspace 普通刷新、显式 Retry、后续计时命令和 checkpoint。核对落盘与缓存 revision、状态和错误是否恢复；覆盖关联正式删除的缓存清理可复用同一机制。若现有契约测试证明恢复缺口，局部修复并补回归；若已有防护，提交具体反证。

必须区分实际未保存与实际已提交，不能把所有写错误都当成功、吞错误或丢失草稿。健康草稿事件仍不额外读取全历史；不要求重建通用缓存平台。**这里没有证明原生 ModelContext.save 自然发生“已提交后抛错”**，报告中不得冒称普通生产已确认 P2。测试须保留同一个 Workspace，不能用重开容器代替恢复断言。

### OBS-02 — 体重旧分页按钮 Task 很晚才进入 loader 的入口防御

[load(value)](https://github.com/yoCruzer/PersonalGrowthOS/blob/597552a020eab22673feed108d8676359efd8822/PersonalGrowthOS/Weight/WeightFoundation.swift#L472) 会 select(value)。若旧 A 外层按钮 Task 在 B 已完成后才首次进入，可把 A 重新设为共享 query；但本次外部 review 没有证明该启动顺序在实际 SwiftUI / MainActor 环境可达。旧 F4 的“reader 已开始、后来才结束”已经修复。

**有界处置**：检查实际任务所有权，采用一次有区分力的本地顺序核验，或做最小入口加固，使加载更多只能追加当前查询，显式切日 / 初始选择拥有切换权。若加固，验证正常首载、分页、重试和显式切日。不能仅用脱离 Swift 调度的状态模型或一般非 FIFO 推论宣称原生 UI 可复现。

未证实可达且不需要加固时，记录检查依据与剩余限定为 UNCONFIRMED / 有界复核完成，**不阻止原 F4 关闭或本轮交付**。不进行无界随机点击、压力长跑或要求先证明所有可能调度顺序。

## 6. 保护边界

沿用上一轮 FIX_GOAL 第 4 节及批准产品规格：五 Tab、Record 独立草稿、现有统一展示、体重 / BMI、星期重复与其他 A–D 已完成行为保持；不新增产品模块、家庭 / 孩子 UI、AI、HealthKit、云同步、时间投入响铃或 Live Activities。

Schema V1–V15 固定历史模型及历史备份保持，当前 V15 / v11 可继续读写与恢复。优先现有字段 / 可信事件和局部结构；确有必要才追加最小版本并证明兼容，不修改历史 schema 校验和。提醒保持单系列有效期次、两渠道互斥、Stop 不完成任务、确认取消才排冲突请求、旧回调不复活；导入恢复用户意图，不移植另一设备队列或权限。

时间投入保持 ContinuousClock / continuous-v1、50ms / 18h 规则、暂停不累计、倒计时晚返回封顶与显式继续、结束冻结、跨进程恢复待确认；R1 消费 / 删除后的正文清理、R2 失败保留输入与可靠保存后关闭、R3 多段替换确认均保持。F5 的 typed event → ID 刷新、轻量历史、20 条页 / 单 ID 详情继续有效，必要业务完整性校验不得为性能计数删除。

保留原 Bundle IDs、App Group、主库位置、最低系统、版本与签名发布策略。使用隔离测试容器 / 专用模拟器，不读写私人设备或私人数据库。

## 7. 验证与独立复核

1. 每项先做与错误分支有区分力的定向回归，确认复现条件和修复结果；能够复用原夹具 / 可控时钟 / journalCommit / reader 的就复用。不要开工先跑全量基线，也不要每完成一个内部阶段就重跑全套 Unit / UI / 双构建。
2. 问题收敛后，按最终 diff 完成一轮覆盖本次受影响类的 Unit 组合，以及关键 UI。提醒三项共同验证容量恢复、已停止负例、旧 nil 兼容、取消不确定和幂等；时间投入覆盖候选 B 编辑 / 删除后返回 A、计时成功落点与失败草稿；体重覆盖固定日期截止及既有分页切日。沿用既有混合 Today / Record 和计时保护的相关用例，只为具体剩余风险扩大范围。
3. 真正改变的界面检查默认字号与中文 Dark 最大动态字号的可见内容、正确落点及可操作按钮；保留可追溯截图。校准滚动 / 焦点驱动可以做，但不得放宽业务断言、删失败或把未看见内容当通过。
4. 若修改 F5 的失效 / 读取边界，复用既有 10k Service → 事件 → 同一 Workspace 计数用例核对健康路径无额外历史读取；不追加无助于结论的性能平台、全新基准或重复 Instruments 批次。
5. 固定干净的最终产品 / 测试 SHA，串行完成一次 Debug Simulator 构建（有效 build-for-testing 可计入）与一次 unsigned generic iOS Release，沿用实包 proof 核对 App / Share / Widget 身份、原版本 / minOS、App provenance 和 AlarmKit 弱链接。已在同候选完成的有效检查可以计入；仅 Markdown 交付提交不重建。
6. 至少一个未编写本轮实现的 reviewer 只读检查固定产品 SHA、完整相关调用链、新增测试与本机可读原始运行证据。重点反证 CR-01/02 的恢复方向、CR-03 有效旧状态来源、CR-04/05 页面收尾以及 OBS 的证据边界。保留 reviewer 原文，按其发现局部修复并补验；不得由实施者代写“独立全部通过”。

每项在既有 EXECUTION / ACCEPTANCE 记录：用例 / 命令、候选 SHA、环境、真实 PASS/FAIL/SKIP/NOT_RUN、关键断言、退出码、原始证据位置和必要哈希。把可供远端核对的小型结果摘要写进仓库；xcresult、截图与实包保留供本机 reviewer 实际读取。文件只存在开发机临时目录时，不能声称远端 reviewer 已独立读取；不要求为此新增 CI、发布 Release 或把大体积构建产物提交 Git。

历史 241/0/1 是九个受影响类共 242 项，不是全仓 517 重跑；原 UI 8/2 与补验 4/4 保持分轮。新轮次同样分开记录，不拼称一次全绿；未变化代码的证据复用须说明 SHA / blob / 用例关系，不能把已变化生产路径的旧 PASS 当新候选通过。

## 8. 完成状态与交付

CR-01～CR-06 逐项以源码与有区分力测试关闭；若已由后续提交修复或有明确反证，记录固定代码、真实边界与 reviewer 结论，不盲目重复实现，不静默降级为债务。OBS-01 必须完成既有故障契约验证与必要恢复修复；OBS-02 按第 5 节有界处置，允许有依据地保留未确认观察。

只有本轮必要验证、双构建和独立复核完成，范围内无未关闭 confirmed P0/P1/P2，且六项明确收尾要求均有处置结果，才恢复 **READY_FOR_OWNER_DEVICE_GATE**。执行中记 FIXES_IN_PROGRESS；仍有确定缺陷记 REVIEW_BLOCKED；必要本地验证不可运行记 VALIDATION_BLOCKED 并完成其余工作，不以设备门未授权作为停止本地修复的理由。

更新两份 CURRENT、既有 EXECUTION / ACCEPTANCE / REVIEW，固定最终产品 / 测试 SHA 与随后纯文档交付 SHA。普通 push 原分支，核对 PR #13 仍 Draft、base 不变、head 对应交付；交接用中文简述各 CR / OBS 结果、失败与补验、独立原文及剩余设备门。无需新建 PR 或给旧 PR 发评论。

**设备与发行边界保留**：D1 真实授权、锁屏 / 静音 / 专注响铃与 Stop/Open；D2 硬件睡眠计时；D3 独立备份后签名、不卸载覆盖升级与私人库核对；D4 真机 VoiceOver / Photos / 分享 / 桌面 Widget / 离线组合，仍需 Owner 后续设备授权。本轮不签名安装、不 merge / force push / tag / Archive / TestFlight。

原 AlarmKit 原生正向 NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间 SKIP/NOT_RUN、远端 CI NOT_RUN 均保留。模拟器 / fake 只能证明各自覆盖层级，不把这些门改为 PASS。

关联：[上一轮修复 Goal](USAGE_REMEDIATION_20261018_REVIEW_FIX_GOAL_ZH.md)、[执行](USAGE_REMEDIATION_20261017_EXECUTION.md)、[验收](USAGE_REMEDIATION_20261017_ACCEPTANCE_ZH.md)、[独立审查](USAGE_REMEDIATION_20261017_REVIEW_ZH.md)、[当前状态](CURRENT_STATE.md)、[当前任务](CURRENT_TASK.md)。
