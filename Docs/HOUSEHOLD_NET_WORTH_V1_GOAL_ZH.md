# Codex Goal · 家庭净资产 V1

- 版本：1.1（2026-11-01）；状态：GOAL_READY / IMPLEMENTATION_NOT_STARTED。
- 仓库：`yoCruzer/PersonalGrowthOS`。
- 固定产品基线 BASE：`5827c657095945aff30b2250b20bae104c7b0357`。
- 本 Goal 与 `HOUSEHOLD_NET_WORTH_V1_SPEC_ZH.md`、`HOUSEHOLD_NET_WORTH_V1_ACCEPTANCE_ZH.md` 同一版本。
- 产品分支：`codex/household-net-worth-v1`。
- 新 Draft PR base：`codex/usage-remediation-20261017`（开始前必须核对远端实际 PR/base/head）。

## 1. 目标与授权

完整实现家庭净资产 V1：用户定期用几分钟更新家庭资产与负债余额，保存可追溯快照，查看净资产长期变化。界面必须像随心 log 正式模块，统一、有设计感，不能交付 demo。

本 Goal 是连续授权：A→B→C 同一批次自动推进，不在阶段、commit 或第一次 review 后重复等待 Owner 批准。允许本功能必要实现、定向测试、独立只读审查及范围内修复、普通 push 和创建/更新本功能唯一 Draft PR。结束于 `READY_FOR_OWNER_DEVICE_GATE`。

不授权 merge、force push、tag、Archive、TestFlight/发布、操作 Owner 私人数据库/设备、清理旧分支或修改其他 PR。

## 2. 启动前固定核对

1. 从 BASE 核对仓库历史、分支、PR、工作树、worktree、upstream、当前 Xcode/模拟器；不假设历史状态仍成立。
2. 阅读 `AGENTS.md`、`Docs/INDEX.md`、Foundation、`DEVELOPMENT_CONTRACT.md`、`Docs/CURRENT_STATE.md`、`Docs/CURRENT_TASK.md`。
3. 再全文读取本功能固定提交中的：
   - `Docs/HOUSEHOLD_NET_WORTH_V1_SPEC_ZH.md`
   - `Docs/HOUSEHOLD_NET_WORTH_V1_GOAL_ZH.md`
   - `Docs/HOUSEHOLD_NET_WORTH_V1_ACCEPTANCE_ZH.md`
4. 本版 1.1 明确取代旧 `HOUSEHOLD_ASSETS_V1_*` 1.0。旧文档只作历史，不得把旧版 Entry 关联、Face ID、过度复杂的快照/项目规则重新加入。
5. 保留所有未知 dirty/untracked 工作和旧 PR；不 stash/reset/clean/restore，不吸收无关改动。确认 BASE 是固定规格提交祖先，规划差异仅限本次文档。
6. 从固定规格 SHA 创建独立 worktree 与产品分支；若同名已存在，核实来源和未完成工作后安全续接，不盲目重建/覆盖。
7. 当前固定基线预期 SwiftData V15、backup v11；必须从代码再次核对。若不一致，先停止并记录真实基线，不可硬套版本号。

## 3. 产品边界（不可扩大）

以完整 SPEC 为准。核心是余额项目 + 正式快照：
- 一个统一 NetWorthItem 领域对象，side 区分资产/负债；不要复制两套账户模型。
- 一个 NetWorthSnapshot，冻结当次项目金额、分类和状态；优先两个持久实体，快照明细可用 typed Codable 值。
- 不另存第二份 current balance；所有总额和图表从正式快照派生。
- 颗粒度由用户选择，可录汇总余额或逐账户余额。
- CNY only、手工更新；不做交易、收益率、银行连接、多币种、家庭协作、Entry 关联、Face ID 保险箱、通知或 Widget。
- 保留金额隐藏和后台遮挡；不得声称数据加密。
- 首版不改五 Tab，Growth 增加“家庭净资产”二级入口。

## 4. 连续实施阶段

### A — 原生最短闭环与视觉定调
- 完成项目新增/编辑/归档、首次盘点、后续盘点草稿、原子保存和总览。
- 早期完成金额精度、未知/零、估算/沿用、日期和统计范围标记。
- 尽早完成真实 SwiftUI 总览与盘点表单，接入现有 Growth 入口；用合成数据在模拟器运行，和 Growth/体重/习惯页面并排检查。
- 核实并实现真实 V15→V16 磁盘升级及 backup v11→v12；新模型进入真实空库/保护/导出/导入/隔离恢复/发布检查。旧版本历史迁移不可修改。
- 阶段提交后直接进入 B。

### B — 历史、图表、导出和完整体验
- 净资产趋势、资产构成、负债趋势/明细；按真实日期，不填假数据；点击图表点/分类进入同一快照的冻结明细。
- 历史补录、更正、删除、项目归档、草稿冷启动和失败恢复。
- CSV 与完整备份恢复真实往返；旧 v11 包可读且新模块为空。
- 金额隐藏、后台遮挡、VoiceOver/动态字号/深色/中英文/键盘/空态。
- 不引入 Entry 关系、Face ID 或其它已明确后置能力。

### C — 集中验收、独立审查与交付
- 按 Acceptance 执行风险驱动测试和约 8–10 张真实生产 UI 截图。
- 由真正未参与实现的独立 reviewer 检查固定 diff、金额/快照语义、真实磁盘升级/恢复、隐私、旧模块影响和原始截图；修复本范围内确认问题后复核。
- 本地只跑受影响测试和必要最终门禁；不要每阶段跑完整 Unit/UI。现有 CI 的最终必选检查由一次有意义的 push/PR 触发。
- 普通 push 产品分支，创建/更新本功能唯一 Draft PR，base 保持本 Goal 指定分支。跟踪真实 CI 结果。
- 更新执行记录、Review、Acceptance 和 CURRENT 顶部状态；保留历史失败与未运行项，不把 NOT_RUN 写成 PASS。

## 5. 视觉质量是完成条件

不允许把“功能可用”当作视觉完成。按 SPEC 实现真实原生 SwiftUI 页面：
- 首页一个主焦点：净资产 + 最近盘点日期；资产/负债次级呈现。
- 有节制的排版、留白、语义色、金额数字层级；不堆彩色 KPI 卡、渐变和装饰图标。
- 表单适合反复快速录入；旧值/日期/本次输入/沿用状态清晰，键盘不挡操作。
- 与现有 Growth、Weight、Habit 页面并排像同一个 App。
- 浅/深色、最大辅助字号、窄屏、长名称、隐藏金额、空态、单点、部分盘点、错误重试均可用。
- 约 8–10 张截图必须来自真实主 App 生产路径，记录 SHA、设备/模拟器、系统、locale、主题、字号和合成数据。静态图、Preview、HTML 不能代替。

## 6. 数据语义关键保护

- 资产/负债金额非负，净资产可负；货币精确，不能用 Double 求和。
- 未知不等于零；两侧范围明确且计入项均有已知金额才显示完整净资产。
- 沿用值保留原金额日期，不假装今天重新估值。
- 正常新增账户/账户重组不自动判定统计范围变化；资金内部转移不改变净资产。
- 补录既有遗漏资产或真正改变统计范围，需用户明确标记；仍保留真实点，但差额不称收益/涨幅，趋势在标记处断线。
- 房产估值和房贷剩余本金分开；信用卡未偿金额；券商净值避免融资负债重复计算。
- 草稿不影响首页；失败不能丢输入；历史项目元数据变化不能重写冻结快照。
- 真实 V15 fixture 由固定 BASE 生成；不能用新 schema 临时造库冒充旧库升级。

## 7. 测试与工程纪律

- 仅用合成数据和任务隔离模拟器/临时磁盘库；不扫描或读取私人目录。
- 改金额规则跑金额定向测试；改 schema/backup 跑真实磁盘迁移与 ZIP 恢复；改图表/布局跑关键 UI 和截图。
- 测试必须调用生产服务和生产 View 路径；不另写一套仅供测试通过的算法。
- 只在影响范围扩大时增加相邻回归；避免完整测试重复运行。最终遵循现有 CI 必选 lane。
- 一个 Xcode 测试队列；不叠加多套全量测试。
- 保留失败、SKIP、NOT_RUN；不删断言、不弱化校验、不改写历史结果。
- 独立 reviewer 不参与实现，必须审查真实 diff 与证据，不可由主 agent 自称换角色代替。
- 所有阶段文档和 Codex 对话默认中文；代码符号/命令/固定枚举保留原文。

## 8. 交付与停止条件

至少交付：
- 完整可用的家庭净资产 V1 原生功能与必要测试/本地化。
- `Docs/HOUSEHOLD_NET_WORTH_V1_EXECUTION_ZH.md`：阶段、实际 schema/backup 版本、SHA、命令、测试结果、限制。
- `Docs/HOUSEHOLD_NET_WORTH_V1_REVIEW_ZH.md`：独立 reviewer、审查 SHA、发现项和关闭证据。
- 更新 Acceptance 实际状态；保存 8–10 张合成数据截图。
- 更新 CURRENT_STATE / CURRENT_TASK 顶部，历史交接原文保留。

只有必选实现、真实可执行验证、现有 CI 和独立审查完成，且本范围内没有未关闭阻断问题，才可标记 `READY_FOR_OWNER_DEVICE_GATE`。真机/Owner 私人库仍由 Owner 自行验收。不得 merge、force、tag、Archive、TestFlight 或发布。