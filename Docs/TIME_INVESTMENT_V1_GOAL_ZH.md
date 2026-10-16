# Codex Goal — 随心log「时间投入 V1」完整实现与独立审查闭环

- 授权版本：1.0（2026-10-16）
- 仓库：yoCruzer/PersonalGrowthOS
- 固定产品基线：ad0720ad743f495ac6f2ee3e97b16577266351db
- 固定 base：codex/sleep-routine-v1 / Draft PR #11
- Goal 承载分支：plan/time-investment-v1-goal
- 产品工作分支：codex/time-investment-v1
- 新 Draft PR base：codex/sleep-routine-v1，不从过期 main 或 Todo worktree 开始
- 产品契约：Docs/TIME_INVESTMENT_V1_DESIGN_ZH.md；须读取全文

目标：在个人真机候选上实现一个真正可以日常使用的时间投入记录模块，优先低摩擦计时、手工活动记录、可选体验反馈，并在第一天就把参与者归属建模正确，为未来家长代记录/独立 App 保留边界。Codex 负责实现、验证、独立只读 Review、限定修复、普通 push 与新 Draft PR，最后停 Owner 真机测试 Gate。

## 一、启动与分支保护

1. 按用户提供的 Goal 文档 SHA 获取这两份固定 Markdown，核实其直接以 ad0720ad 为父、只新增预期文档。先读取 AGENTS.md / INDEX 中适用 Foundation、DEVELOPMENT_CONTRACT、CURRENT_STATE/CURRENT_TASK 和相关现行源码。
2. 轻量核对真实仓库、worktree、dirty、branch/upstream/PR。Codex 主工作区的 project.pbxproj、Localizable.xcstrings、xcshareddata/xcodecloud 未提交变动仍需保留，不擅自 stash/reset/restore/clean/覆盖/吸收。
3. 从精确 Goal 文档提交（它包含最新已安装产品基线）开独立 worktree / codex/time-investment-v1；若同名 branch/PR 已存在，先核验再安全续接；不可盲目 pull/rebase/merge。
4. 现有 PR #8→#9→#10→#11 仍是依赖链，不擅自合并、修改 base、强推或把新功能提交进旧 PR。重要日子/睡眠已通过的真实机版本为基线；新功能只能追加最小契约和适配。

## 二、开发职责与分批节奏

先检查当前 SwiftData 最新 Schema/备份、Today/Growth 接线、分享/Widget target 以及主模型生命周期，不做全面重构。

阶段 A（优先先跑通的真实路径）：
- 正计时/简易倒计时、暂停恢复/结束；切 App、锁屏后继续可靠计时，非后台循环计数；发生回拨或进程终止时有可靠恢复或手工确认，不假装精确。
- 默认唯一参与者「我」的稳定 participantID，Activity 身份独立；一名参与者不能双活；Session 时长、来源、反馈、备注、事实/填写/技术时间边界正确。
- 手工补记时长/日期/可选时间、5档体验和说明，保存/编辑/删除/取消/中断重开；仅填日期+时长时不虚构时刻。
- Growth 入口、简单进行中状态与必要 Today 紧凑入口，保持其它原页面不回归。

阶段 B（完整 V1 门禁）：
- 7/30 天/按活动基础汇总和详情回跳；跨日、归档、重复/部分记录、时区与系统时间异常按产品契约处理。
- 历史 Schema/备份版本链更新、旧盘库直接升级与新包空库恢复重开；合成来源图片/外部收据/重要日子、睡眠、Todo、Habit、Weight 保持。
- 中文/英文、Light/Dark、大字号、基础 VoiceOver、错误/取消与离线。
- 产品契约全部必选实现；不能以阶段 A 通过就停止或请 Owner 逐批批准。普通可逆实现细节自主决定。

## 三、不可逾越的产品边界

不引入家庭协作/孩子管理 UI、不做独立 App、不锁手机、不要求使用者只停留在计时画面；无需 Apple Intelligence、服务器、网络、云账户。现有 Record 仍是一键图文入口，不增第六个 Tab，不把 Session 当 Entry/HabitLog/Todo 伪写，也不自动产生 Quiet Wins 成果或将睡眠计时搬过来。

优先可用、可靠和真实使用路径，不为了未来重构通用计时框架、复杂监控平台或多应用同步架构。不能牺牲旧数据保存和新增字段的来源真实性。

## 四、测试与独立审查

- 不在起点重复旧完整测试。代码改动阶段只跑受影响 Unit/集成/UI，并尽快对后台/恢复状态、V13迁移、备份数据做固定时钟合成路径测试；全量 Unit/集中关键 UI 在功能及主要 Review 问题收敛后择一次执行，局部修复只补受影响项。不要为了“全绿”删断言/跳过失败，也不要拼接不同轮的 PASS。
- 真实实现者 + 独立只读 Reviewer；早期审查数据、计时/参与者身份、跨日/中断、迁移/恢复；后期审查 Today/Record/旧模块影响、实包身份、故障和真机路径。
- Reviewer 读固定提交 diff、生产代码与原始测试证据，不自己改代码；主 agent 验证发现、先红后绿限定修复，再请求复审。关闭范围内新 P0/P1，影响必选路径/数据可信度的 P2 也关闭。
- 测试至少覆盖设计文件 S1–S10：真实背景锁屏/进程恢复的模拟状态与可用 UI，计时重复防护、纯时长补记、体验后补、个人 participant ID、Activity 改名/归档、统计归属、V11/V12/V13→新库、备份导出/恢复以及 Sleep/ImportantDays/Todo/QuietWins/Record/Share/Widget 相邻回归。开发环境无真机时未运行必须写 NOT_RUN。
- 只有一个活跃 Xcode 测试队列，不并行启动多个重复构建；固定产品/测试 SHA 做最终 Debug 与 unsigned Release 构建，核对 App/Share/Widget 嵌入、Bundle ID、provenance；无签名产物不是已可安装 IPA。
- 关键 run 写清精确 SHA、selector、结果/失败/跳过数、日志/xcresult；失败原证据保留。诊断脱敏且不含活动正文、时长私密笔记或孩子信息。

## 五、交付与停点

授权在新工作分支合理 commit、普通 push、新建一个 Draft PR（base 固定 codex/sleep-routine-v1），不影响既有 PR #8/#9/#10/#11，不 merge、tag、force push、Archive、TestFlight 或真实手机操作。允许新分支对 Foundation/CURRENT/INDEX 做必要且最小的批准增量，不能回写旧阶段真实证据或悄悄降低历史 Schema/恢复保护。

建立精简交付文档：Docs/TIME_INVESTMENT_V1_EXECUTION.md、Docs/TIME_INVESTMENT_V1_REVIEW_ZH.md、Docs/TIME_INVESTMENT_V1_ACCEPTANCE_ZH.md，写明固定 Goal SHA、当前分支、实际产品/测试/交付 SHA、真实验证范围、旧数据保护与后续真机清单。文档-only 最终提交不重复耗时构建。

内部开发/独立审查闭环后正常停 READY_FOR_OWNER_DEVICE_GATE；只有确实受阻才报 REVIEW_BLOCKED/BLOCKED_ENVIRONMENT/BLOCKED_AUTH，说明可完成部分与具体障碍。不要在完成计划、中期 commit、首轮 Review、普通 push 后等待批准。所有用户沟通和验收记录默认中文。不开下一个功能模块。
