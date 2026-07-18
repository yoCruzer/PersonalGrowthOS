# V1 Autonomous Execution Plan

| Item                     | Value                                        |
| ------------------------ | -------------------------------------------- |
| Project                  | Personal Growth OS                           |
| Document                 | `V1_AUTONOMOUS_EXECUTION_PLAN.md`            |
| Version                  | v0.1                                         |
| Status                   | Owner Review Draft                           |
| Last Updated             | 2026-07-18                                   |
| Program Type             | Isolated-branch autonomous V1 implementation |
| Authorized Product Range | Macro Stage S1 through Macro Stage S10       |
| Proposed Working Branch  | `feat/v1-autonomous-build`                   |
| Final Result             | Owner-reviewable V1 Candidate                |

---

# Purpose

本文档定义 Personal Growth OS V1 的自主执行模式。

它将 Owner 已接受的 Foundation Documents、`DEVELOPMENT_CONTRACT.md` 和 `V1_IMPLEMENTATION_PLAN.md` 转化为一次可持续执行的 Agentic Engineering Program，使 Codex 能够在明确边界内：

* 自主规划；
* 自主拆分任务；
* 自主实现；
* 自主运行构建和测试；
* 自主修复失败；
* 自主提交阶段性结果；
* 自主进入后续 Macro Stage；
* 在上下文中断后根据仓库状态恢复执行。

本文档的目标，是避免 S1–S10 之间反复进行低价值的人工定义、授权和确认，同时保留必要的数据安全、架构约束、验证证据、Git 隔离和最终 Owner Review。

本文档不修改 Personal Growth OS 的产品愿景、Core Model、Information Architecture 或 V1 Scope。

---

# Execution Model Decision

Personal Growth OS 正式停止以下默认执行方式：

```text
定义一个小型子 Stage
↓
Owner 单独批准
↓
Codex 执行
↓
Owner 审查
↓
再次定义并批准下一个子 Stage
```

V1 改为以下自主执行方式：

```text
Owner 一次性批准 V1 Autonomous Build Program
↓
Codex 创建隔离分支
↓
Codex 自主执行 Macro Stage S1–S10
↓
内部持续规划、实现、验证、修复和提交
↓
仅在明确的高风险条件出现时暂停并升级
↓
完成完整 V1 Candidate
↓
Owner 对完整结果统一审查
```

Macro Stage 仍然保留，但其职责变为：

* 实现边界；
* 测试边界；
* Commit 边界；
* 状态记录边界；
* 故障定位边界；
* 回滚边界。

Macro Stage 不再默认是逐个等待 Owner 批准的行政审批边界。

---

# Authority and Precedence

自主执行期间，Codex 必须按照以下优先级理解项目：

1. `Docs/INDEX.md` 及其定义的 Foundation Documents。
2. `DEVELOPMENT_CONTRACT.md`。
3. 本文档。
4. `Docs/CURRENT_STATE.md`。
5. `Docs/CURRENT_TASK.md`。
6. `Docs/V1_IMPLEMENTATION_PLAN.md`。
7. 现有代码、测试、构建结果和 Git 历史。

其中：

* Foundation Documents 继续决定产品方向和 V1 范围；
* `DEVELOPMENT_CONTRACT.md` 继续决定长期开发原则；
* 本文档决定 S1–S10 的一次性自主执行授权方式；
* `V1_IMPLEMENTATION_PLAN.md` 继续定义 Macro Stage 的能力范围、依赖关系和 Exit Criteria；
* 本文档仅覆盖原有“每个子 Stage 必须单独获得 Owner 批准”的执行机制。

如果低优先级文档与高优先级文档冲突，必须遵循高优先级文档。

不得为了方便实现而静默修改、弱化或重新解释 Foundation 决策。

---

# Program Goal

本 Program 的目标是：

> 在一个与 `main` 隔离的开发分支上，自主实现 Personal Growth OS Macro Stage S1–S10，交付一个可以构建、运行、测试并供 Owner 真实体验和统一审查的 V1 Candidate。

V1 Candidate 应至少覆盖：

* Entry Domain Foundation；
* SwiftData 本地持久化；
* 图片文件存储和媒体一致性；
* Quick Capture；
* Timeline；
* Rich Entry 创建和编辑；
* Library；
* Inbox；
* Tags；
* Search；
* Habit；
* HabitLog；
* Goal；
* Flag；
* 核心对象关系；
* Lightweight Manual Review；
* Data Export；
* Data Import；
* V1 集成和 Daily Driver 技术准备。

本 Program 不以 App Store Ready、Release Candidate 或正式发布为目标。

---

# Result Classification

本 Program 完成后产生的结果是：

```text
V1 Candidate
```

这意味着：

* S1–S10 的技术实现已经完成；
* 适用的构建、自动化测试和模拟器检查已经通过；
* 核心工作流已经可以运行；
* Codex 已完成自身能够执行的技术验证；
* 结果可以交给 Owner 进行真实使用和产品判断。

这不意味着：

* V1 已自动获得 Owner 接受；
* V1 可以自动合并到 `main`；
* V1 已完成正式的连续 30 天真实使用观察；
* V1 已成为 Release Candidate；
* V1 已准备提交 App Store；
* 产品交互和视觉设计不再需要改进。

Foundation 定义的正式连续 30 天 V1 Exit Observation，仍然只能在 S10 达到技术 Exit Criteria 后，由 Owner 通过真实生活使用完成。

Codex 不得自行宣布 V1 已满足真实世界 Daily Driver Success Criteria。

---

# Governance Adoption

开始 V1 产品实现前，应先完成一次仅包含治理文件的准备变更。

治理准备应：

1. 将本文档加入仓库；
2. 更新 `Docs/V1_IMPLEMENTATION_PLAN.md` 的 Macro Stage Governance，使其允许 Owner 通过 Autonomous Execution Program 一次性批准多个 Macro Stages；
3. 更新 `Docs/CURRENT_STATE.md`，记录 S0 已完成、当前真实 `main` 基线以及下一执行模式；
4. 更新 `Docs/CURRENT_TASK.md`，将当前任务设置为 V1 Autonomous Build Program；
5. 创建初始 `Docs/V1_AUTONOMOUS_STATUS.md`；
6. 不修改任何产品代码；
7. 形成一个独立、可审查的 Governance Commit；
8. 在 Governance Commit 完成后停止，等待一次明确的 V1 Autonomous Build 执行批准。

接受本文档作为规划基线，不自动等于开始产品实现。

开始产品实现仍需要一次明确的 Owner 指令，例如：

```text
批准启动 V1 Autonomous Build Program。
请从当前 clean main 创建 feat/v1-autonomous-build，
并按照 Docs/V1_AUTONOMOUS_EXECUTION_PLAN.md 自主执行 S1–S10。
```

该指令一旦给出，S1–S10 不再需要逐 Stage 获得新的 Owner 批准。

---

# Execution Baseline

Codex 在正式开始执行时必须：

1. 读取 `AGENTS.md` 规定的项目上下文；
2. 确认当前位于 `main`；
3. 确认工作区 clean；
4. 确认本计划和相关治理更新已经存在于 `main`；
5. 记录当前 `main` 的准确 Commit SHA；
6. 将该 SHA 写入 `Docs/V1_AUTONOMOUS_STATUS.md`；
7. 从该 Commit 创建：

```text
feat/v1-autonomous-build
```

所有 S1–S10 产品实现必须发生在该隔离分支上。

不得直接在 `main` 上实现产品功能。

如果执行开始时：

* `main` 不 clean；
* 本地 `main` 与预期基线不一致；
* 已存在同名分支但状态无法确认；
* 存在未归属的产品代码变更；
* 当前仓库无法确定安全起点；

则必须停止并升级给 Owner。

---

# Authorized Macro Stages

一次性执行授权覆盖以下 Macro Stages：

| Macro Stage | Name                                      | Primary Result                  |
| ----------- | ----------------------------------------- | ------------------------------- |
| S1          | Entry Domain Foundation                   | Entry 稳定语义、规则和验证                |
| S2          | Local Persistence and Media Foundations   | SwiftData、Repository 和安全的一图存储基础 |
| S3          | First Runnable Capture → Timeline Slice   | 第一个可重启、可真实运行的记录闭环               |
| S4          | Rich Entry Media and Editing              | 多图、编辑、删除和媒体资源边界                 |
| S5          | Library, Inbox, Tags and Search           | 内容整理和重新查找能力                     |
| S6          | Habit and HabitLog                        | Habit 创建、生命周期和打卡                |
| S7          | Goal, Flag and Core Relationships         | Goal、Flag、关系和生命周期事件             |
| S8          | Lightweight Manual Review                 | 基于 Entry 的轻量手动回顾                |
| S9          | Export / Import Recovery                  | 可实际使用的数据导出和恢复                   |
| S10         | V1 Integration and Daily Driver Readiness | 完整集成、技术稳定性和 V1 Candidate        |

Codex 必须保持 Macro Stage 之间的必要依赖，但可以在不改变范围的情况下：

* 将 Macro Stage 拆成更小的内部任务；
* 合并高度耦合的小型实现步骤；
* 在同一 Macro Stage 内重新排序工作；
* 提前编写后续阶段必然需要、且当前阶段已经证明必要的最小接口；
* 在发现测试或架构问题时回到前一 Stage 修复；
* 为保持系统一致性，在相邻 Stage 之间进行小范围协调性修改。

Codex 不得：

* 跳过任何 V1 必需能力；
* 因实现困难而静默删除某个 Macro Stage；
* 将 Out of Scope 项目加入实现；
* 用占位实现冒充已完成能力；
* 将后续重大能力预先塞入当前 Stage；
* 以“未来再做”为理由绕过当前 Stage 的 Exit Criteria。

---

# Internal Milestones

为了控制复杂度和形成稳定检查点，S1–S10 分为三个内部 Milestone。

这些 Milestone 不需要逐个获得 Owner 批准。

## Milestone A — Core Recording

覆盖：

```text
S1 → S2 → S3 → S4
```

目标：

* 建立 Entry 语义；
* 建立本地持久化；
* 建立图片文件存储；
* 打通 Capture → Persist → Timeline；
* 支持 Rich Entry 的创建、查看、编辑和媒体生命周期。

Milestone A 结束时，应存在第一个可以真实记录文字和图片的核心版本。

## Milestone B — Growth and Organization

覆盖：

```text
S5 → S6 → S7 → S8
```

目标：

* 完成内容整理和搜索；
* 完成 Habit 与 HabitLog；
* 完成 Goal 与 Flag；
* 完成必要关系；
* 完成 Lightweight Manual Review。

Milestone B 结束时，应形成 Foundation 定义的主要产品结构和成长闭环。

## Milestone C — Ownership and Readiness

覆盖：

```text
S9 → S10
```

目标：

* 完成基础 Data Export；
* 完成基础 Data Import；
* 验证对象标识、关系和图片恢复；
* 完成整体集成；
* 处理 Daily Driver 技术阻塞；
* 形成供 Owner 体验的 V1 Candidate。

---

# Autonomous Engineering Loop

Codex 在每个 Macro Stage 内应持续执行以下循环：

```text
读取当前仓库事实
↓
检查当前 Stage 的范围和 Exit Criteria
↓
制定内部实施计划
↓
实现最小完整能力
↓
运行聚焦构建和测试
↓
检查完整 diff
↓
自主修复发现的问题
↓
运行完整 Stage 验证
↓
更新状态文件
↓
创建阶段性 Commit
↓
自动进入下一 Stage
```

Codex 不应因为普通实现选择、命名选择、文件布局、SwiftUI 组件选择或可恢复的测试失败而暂停等待 Owner。

当存在多个合理方案时，应按照以下顺序选择：

1. 符合 Foundation Documents；
2. 保护用户数据和隐私；
3. 支持快速记录；
4. 保持 Local First；
5. 保留原始内容；
6. 使用最简单、最可逆的方案；
7. 使用 iOS 17 原生能力；
8. 降低实现和维护复杂度；
9. 避免提前抽象；
10. 有利于自动化测试和后续真实使用。

选择完成后，应直接执行，并在状态文件中记录重要而非显然的决策。

---

# Autonomous Decision Rights

在已批准的 V1 范围内，Codex 可以自主决定：

* Macro Stage 的内部任务拆分；
* 普通 Swift 类型和文件命名；
* 文件和目录组织；
* 小型 value object 和 validation result 的表达；
* View、ViewModel、Service 和 Repository 的局部职责划分；
* 可逆的 SwiftUI 页面结构；
* 原生控件和导航方式；
* Timeline 和列表的基础呈现；
* Capture 和编辑流程的普通交互细节；
* 合理的空状态、错误状态和加载状态；
* Unit Test 和 UI Test 的组织方式；
* 测试 fixture 和 temporary store 设计；
* 局部重构；
* 编译错误和测试失败修复；
* Stage 内部 Commit 数量；
* 不影响长期产品方向的性能优化；
* 基于实际测量设置的资源阈值；
* 不改变 Foundation 范围的可访问性改进；
* 使用系统默认样式完成初始功能性 UI。

UI 尚未被 Foundation Documents 精确定义时，Codex 应优先采用：

* 清晰；
* 克制；
* 原生；
* 可理解；
* 易修改；
* 适合真实使用测试；

的实现。

不得因为缺少完整视觉稿而停止 V1 实现。

不得为 V1 创建大型 Design System、复杂主题引擎或与当前产品规模不相称的组件框架。

---

# Decisions That Do Not Require Escalation

以下情况默认不需要暂停：

* 两个普通类型名称之间的选择；
* 文件放在哪个职责目录；
* 使用 `NavigationStack` 的具体组织方式；
* 一个页面拆成几个小型 View；
* 使用原生 `List`、`ScrollView` 或 `Form`；
* 普通错误文案；
* 普通空状态；
* ViewModel 是否拆出一个小型 helper；
* 测试使用内存配置还是 temporary directory；
* 为修复测试增加合理 dependency seam；
* 某个小型协议是否当前确有必要；
* 普通 SwiftData predicate 或 sort descriptor 设计；
* 可逆的界面布局修改；
* 测试失败后的局部代码修复；
* 当前范围内的模型字段命名；
* 当前范围内的性能和内存修复；
* 为满足现有验收标准进行的小范围重构；
* 在 Stage Commit 前修正前一 Stage 的缺陷。

如果决定：

* 在批准范围内；
* 不改变 Foundation；
* 可恢复；
* 可测试；
* 不增加外部承诺；

Codex 应自主推进。

---

# Mandatory Escalation Conditions

只有出现以下情况之一时，Codex 才必须暂停并请求 Owner Review。

## Product or Authority Conflict

* Foundation Documents 之间存在实质冲突；
* 本计划与 Foundation Documents 冲突；
* V1 Scope 无法支持某项必需实现；
* 完成目标必须新增、删除或重新定义 V1 产品能力；
* 必须改变 Core Model 的长期对象或关系；
* 必须将明确属于 V2 的能力引入 V1。

## Major Architecture Change

* 必须放弃当前单一原生 iOS App 工程方向；
* 必须引入 Swift Package 拆分才能继续；
* 必须建立字段完整重复的 Domain Model 和 Persistence Model；
* 必须更换 SwiftData 作为 V1 持久化方案；
* 必须更改图片文件与数据库元数据分离的方向；
* 必须改变标准 ZIP 导出包方向；
* 必须进行难以回退的长期架构改变。

普通局部架构选择不属于本项。

## External Commitment

* 必须增加第三方依赖；
* 必须使用付费服务；
* 必须添加远程 API；
* 必须提供新的凭据或密钥；
* 必须创建外部账号或云资源；
* 必须引入分析、广告、AI 或远程数据处理服务。

## Apple Platform Boundary

* 必须改变 Bundle Identifier；
* 必须改变 iOS 17.0 minimum deployment target；
* 必须增加 iPad、Mac、Web 或其他平台；
* 必须持久化 Development Team；
* 必须启用 CloudKit、iCloud、Push Notifications、App Groups、Sign in with Apple、Background Modes 或其他未批准 Capability；
* 必须新增 Entitlement；
* 必须进行 App Store Connect、TestFlight 或发布操作。

## User Data and Destructive Risk

* 必须对 Owner 的真实数据执行破坏性操作；
* 无法证明删除、导入或恢复操作的回滚边界；
* 可能发布部分导入结果；
* 可能产生无法恢复的媒体和数据库不一致；
* 数据迁移无法保证现有测试数据安全；
* 继续执行会降低隐私、数据所有权或原始内容保护。

所有自动化破坏性测试必须使用测试 fixture、临时数据库和临时文件容器，不得使用 Owner 的真实数据。

## Validation Failure

* 必需的构建或测试环境不可用；
* 无法执行 Stage 的关键验证；
* 同一个关键阻塞已经经过至少三种有实质区别的合理修复尝试，仍无法解决；
* 继续修改只能依靠未经验证的猜测；
* 为报告成功必须禁用、跳过或弱化既有测试；
* 仓库状态已经无法可靠解释；
* 工作区出现来源不明或不属于当前 Program 的变更。

## Git Safety

* 无法确认当前分支或准确基线；
* `main` 出现非预期修改；
* 需要 force push；
* 需要重写已经共享的历史；
* 需要自动合并到 `main`；
* 需要删除远程分支、Tag 或 Release。

---

# Escalation Format

触发升级时，Codex 必须停止进一步扩大变更，并提供：

1. 当前 Stage；
2. 最近一个已验证通过的 Commit；
3. 已确认的仓库事实；
4. 精确阻塞点；
5. 已尝试的方案；
6. 为什么继续需要 Owner 决策；
7. 可选方案；
8. 每个方案的影响；
9. 推荐方案；
10. 当前工作区是否 clean。

升级前应更新 `Docs/V1_AUTONOMOUS_STATUS.md`，使新的 Codex 会话可以恢复上下文。

---

# Scope Guardrails

自主执行不允许扩大 V1 范围。

明确禁止加入：

* AI；
* OCR；
* Audio；
* Video；
* Live Photo；
* Journey；
* Places；
* People；
* Projects；
* Family Sharing；
* Social；
* Widgets；
* Apple Watch；
* iCloud multi-device sync；
* real-time sync；
* advanced analytics；
* automatic review；
* AI review；
* automatic backup scheduling；
* incremental backup；
* complex backup history；
* merge import；
* cross-platform abstractions；
* App Store publication work。

不得为了“未来可能使用”而创建：

* 空的 AI service；
* 空的 sync service；
* 空的 analytics service；
* 通用知识图谱；
* Service Locator；
* 大型 Dependency Injection Framework；
* 通用 Repository Framework；
* 跨平台抽象层；
* 未使用的协议层；
* 未使用的数据库实体；
* 未使用的配置系统；
* 未经当前需求证明的缓存和索引系统。

---

# Git Strategy

## Branch Rules

产品实现只允许发生在：

```text
feat/v1-autonomous-build
```

Codex 不得：

* 在 `main` 上实现产品功能；
* 自动合并到 `main`；
* 删除 `main`；
* force push；
* 重写已共享历史；
* 创建 Release；
* 创建 Tag；
* 自动发布 App。

## Commit Rules

每个 Macro Stage 至少应形成一个可独立理解的 Commit。

一个 Macro Stage 可以形成多个 Commit，但必须保持：

* 每个 Commit 具有明确目的；
* 不混入无关变更；
* Commit 之间能够解释开发过程；
* 测试修复和实现保持合理关联；
* Stage 结束时存在一个明确、可验证的边界；
* 不为了追求单 Commit 而制造超大且不可审查的变更。

建议 Commit subject 使用：

```text
feat: establish entry domain foundation
feat: add local persistence and media foundation
feat: deliver capture timeline slice
feat: complete rich entry editing
feat: add library tags and search
feat: add habits and habit logs
feat: add goals flags and relationships
feat: add lightweight manual review
feat: add export import recovery
feat: complete v1 integration
```

具体 subject 可以根据实际实现调整。

## Remote Push

如果执行环境已经具备有效 GitHub 凭据，Codex可以将：

```text
feat/v1-autonomous-build
```

以非 force 方式推送至 `origin`，用于阶段性备份和上下文恢复。

允许推送仅限该自主执行分支。

不得：

* 修改远程 `main`；
* 自动创建或合并 Pull Request；
* force push；
* 删除远程分支；
* 修改仓库设置；
* 创建 Release 或 Tag。

如果凭据不可用，Codex 应继续保留本地 Commit，不得因此停止产品实现。

---

# Validation Strategy

验证必须与变更风险相匹配。

通过构建不等于功能完成。

通过 Unit Tests 不等于 UI 可用。

通过自动化测试不等于满足真实世界 Daily Driver Success Criteria。

## Per-change Loop

在小型实现循环中，Codex 应优先运行：

* 相关文件编译；
* 聚焦 Unit Tests；
* 聚焦 Repository 或 Media Tests；
* 聚焦 UI Test；
* 静态检查；
* `git diff --check`。

## Per-Macro-Stage Validation

每个 Macro Stage 结束前必须：

1. 运行该 Stage 的所有聚焦测试；
2. 运行受到影响的已有测试；
3. 构建 App；
4. 审查完整 diff；
5. 确认没有明显越界实现；
6. 更新状态文件；
7. 创建 Stage Commit。

## Per-Milestone Validation

Milestone A、B、C 结束时必须：

1. 完整构建共享 App scheme；
2. 运行完整 Unit Test suite；
3. 运行适用的 UI smoke tests；
4. 在可用 iPhone Simulator 上启动 App；
5. 检查关键用户流程；
6. 检查无网络依赖；
7. 检查无新增未批准 Capability；
8. 检查无第三方依赖；
9. 检查 Git working tree；
10. 记录验证命令和结果。

## Final Validation

S10 结束时必须至少验证：

* App 在可用 iPhone Simulator 上成功构建；
* App 可以启动且不崩溃；
* 完整 Unit Test suite 通过；
* 关键 UI smoke tests 通过；
* Quick Capture 可以创建文字 Entry；
* Quick Capture 可以创建图片 Entry；
* Quick Capture 可以创建图文 Entry；
* 保存后重启 App，数据仍然存在；
* Timeline 能够显示记录；
* Entry 能够编辑；
* Entry 能够归档；
* Entry 能够永久删除且不遗留错误媒体；
* Library、Inbox、Tags 和 Search 可用；
* Habit 与 HabitLog 可用；
* Goal 与 Flag 可用；
* Review Entry 可用；
* Export 可以生成结构完整的包；
* Import 可以在测试环境恢复数据；
* 导入失败不会发布部分数据；
* 图片不会被保存为数据库 binary；
* 删除不会影响其他 Entry 的图片；
* 无 dangling Links；
* 无未批准网络、CloudKit 或账号依赖；
* `git diff --check` 通过；
* 工作区 clean。

---

# Test Data Boundary

所有自动化和破坏性验证必须使用：

* in-memory SwiftData configuration；
* temporary on-disk store；
* temporary media directory；
* generated image fixtures；
* synthetic Entry、Habit、Goal、Tag 和 Link fixtures；
* temporary export package；
* temporary import destination。

不得：

* 读取 Owner 的真实 Personal Growth OS 数据；
* 删除 Owner 的真实文件；
* 覆盖真实数据库；
* 将测试导入到真实 App container；
* 为测试访问相册、联系人、iCloud 或其他真实用户数据；
* 将测试内容上传到网络。

---

# Failure Handling

失败是工程证据，不是停止自主执行的默认理由。

Codex 应在范围内自主处理：

* 编译失败；
* Unit Test 失败；
* UI Test 失败；
* SwiftData schema 问题；
* 临时文件清理问题；
* 媒体一致性问题；
* 页面状态问题；
* 导入导出 fixture 问题；
* 局部性能问题；
* 可恢复的架构问题；
* 前一 Stage 暴露出的缺陷。

处理过程应遵循：

1. 确认失败能够复现；
2. 找到最可能的根因；
3. 实施最小修复；
4. 重新运行聚焦测试；
5. 重新运行受影响的完整测试；
6. 检查是否引入新的范围外复杂度；
7. 记录重要修复。

Codex 不得：

* 删除失败测试；
* 永久 skip 必需测试；
* 降低断言强度；
* 用延时掩盖竞态而不解释；
* 吞掉错误；
* 将失败路径改成表面成功；
* 用 mock 替代本应验证的真实本地行为；
* 为通过测试而破坏产品语义。

如果同一个关键问题经过至少三种实质不同的合理方案仍无法解决，应升级，而不是无限循环或继续堆积补丁。

---

# Context Continuity

为了避免 Codex 会话中断、上下文压缩、网络失败或新线程导致状态丢失，执行期间必须维护：

```text
Docs/V1_AUTONOMOUS_STATUS.md
```

该文件至少包含：

```text
# V1 Autonomous Status

## Program Baseline
## Current Branch
## Current Macro Stage
## Current Internal Task
## Completed Macro Stages
## Latest Verified Commit
## Latest Build Result
## Latest Test Result
## Important Decisions
## Known Limitations
## Active Blockers
## Next Action
## Repository State
```

更新要求：

* Program 启动时初始化；
* 每个 Macro Stage 结束时更新；
* 每个 Milestone 结束时更新；
* 发生重大设计决定时更新；
* 发生无法解决的阻塞时更新；
* Codex 准备停止或切换会话前更新；
* 最终交付前更新。

该文件只记录可验证的执行状态，不记录冗长聊天历史或临时思考过程。

新的 Codex 会话应能够通过读取仓库文件和 Git 历史继续执行，而不依赖旧会话上下文。

---

# Documentation Rules

执行期间：

* Foundation Documents 默认保持不变；
* `DEVELOPMENT_CONTRACT.md` 默认保持不变；
* 本计划默认保持不变；
* `Docs/V1_IMPLEMENTATION_PLAN.md` 不应因普通实现细节频繁修改；
* `Docs/CURRENT_STATE.md` 应反映已经验证的稳定仓库状态；
* `Docs/CURRENT_TASK.md` 应保持 V1 Autonomous Build Program 边界；
* `Docs/V1_AUTONOMOUS_STATUS.md` 应反映持续执行状态；
* 必要的用户说明和操作说明应更新到适当文档；
* 不应把会话临时信息写入长期文档。

如果实现发现 Foundation 产品决策必须修改，Codex 必须升级，不得自行编辑 Foundation Documents 后继续。

---

# Product and UI Quality Boundary

Codex 需要交付一个可真实体验的 V1 Candidate，而不只是后台模型集合。

因此：

* 所有 V1 核心能力应有可访问的用户路径；
* 关键流程不能只通过测试或 Debug API 使用；
* 页面应使用合理的原生 SwiftUI 结构；
* 用户应能理解当前页面的主要操作；
* 空状态和错误状态不能完全缺失；
* 关键控件应具有可理解的 Label；
* 核心 UI Test 应使用稳定 accessibility identifier；
* 不应依赖隐藏手势才能完成核心流程；
* 不应为了视觉效果牺牲记录速度；
* Quick Capture 应保持高频、直接、低阻力；
* Inbox 不应被设计成必须清空的任务列表；
* Timeline 应优先展示有回顾价值的内容；
* 图片应被视为 Entry 核心内容，而不是次级附件。

Codex 可以自主选择初始视觉实现，但应避免：

* 过度装饰；
* 复杂动画；
* 非必要自定义控件；
* 过早品牌设计；
* 大型主题系统；
* 以展示效果优先于核心可用性。

---

# Interruption and Recovery

如果执行因为网络、Codex 上下文、工具、进程或环境问题中断，新会话应：

1. 读取 `AGENTS.md`；
2. 读取 Authority Chain 中的文档；
3. 读取 `Docs/V1_AUTONOMOUS_STATUS.md`；
4. 检查当前分支；
5. 检查 `git status --short`；
6. 检查最近 Commit；
7. 检查未提交 diff；
8. 重新运行必要的聚焦验证；
9. 从 `Next Action` 继续。

不得仅因为会话中断而：

* 重建已经存在的实现；
* 放弃未完成 Stage；
* 创建新的平行自主分支；
* reset 已验证 Commit；
* 重新解释已经记录的稳定决策。

如果未提交工作可以可靠识别，应在当前分支继续。

如果无法可靠确认未提交工作的来源和意图，应停止并升级。

---

# Program Stop Conditions

Codex 只在以下情况停止自主执行：

## Successful Completion

* S1–S10 的技术 Exit Criteria 已满足；
* Final Validation 已完成；
* 最终文档已经更新；
* 已创建最终 V1 Candidate Commit；
* 工作区 clean；
* 已准备 Owner Review 报告。

## Mandatory Escalation

出现本文档定义的高风险升级条件。

## Environment Failure

执行环境无法构建、测试或可靠访问仓库，并且继续修改会导致状态不可信。

## Safety Failure

继续执行可能破坏真实用户数据、降低隐私或制造不可恢复状态。

除以上情况外，Codex 应继续自主推进，不应因普通实现选择而停止。

---

# Final Deliverables

Program 成功结束时，Codex 必须交付：

1. `feat/v1-autonomous-build` 分支；
2. S1–S10 的完整实现；
3. 清晰的 Stage / Milestone Commit 历史；
4. 完整构建结果；
5. 完整 Unit Test 结果；
6. 关键 UI Test 结果；
7. 适用的模拟器运行结果；
8. 最终 `Docs/V1_AUTONOMOUS_STATUS.md`；
9. 更新后的 `Docs/CURRENT_STATE.md`；
10. 更新后的 `Docs/CURRENT_TASK.md`；
11. V1 Candidate 的核心功能说明；
12. Owner Manual Validation Checklist；
13. Known Limitations；
14. 未解决但不阻塞技术 Candidate 的问题；
15. 完整变更文件列表；
16. 最终 Commit SHA；
17. clean working tree 证明。

最终报告必须明确区分：

* 自动化验证已经证明的内容；
* Codex 通过模拟器观察的内容；
* 仍需 Owner 真机或真实生活验证的内容；
* 不能由 Codex 声称完成的 30 天 Daily Driver 观察。

---

# Definition of Done

V1 Autonomous Build Program 只有在以下条件全部满足时，才算技术完成：

* Macro Stage S1–S10 均达到各自技术 Exit Criteria；
* V1 Scope 中的必需能力均存在实际用户路径；
* 适用构建和测试通过；
* 数据和媒体一致性验证通过；
* Export / Import 在隔离测试环境中可用；
* 最终 diff 不包含明确 Out of Scope 能力；
* 未引入未经批准的第三方依赖；
* 未引入未经批准的 Capability 或 Entitlement；
* Foundation Documents 未被静默改变；
* 状态和交接文档反映真实仓库状态；
* Commit 历史可审查；
* 工作区 clean；
* Codex 已停止在 Owner Review 边界；
* 未自动合并到 `main`；
* 未自动发布。

本 Definition of Done 只表示：

```text
V1 Candidate Technical Completion
```

它不替代 Owner Review、真机验证、真实生活 Dogfooding 或正式 30 天 V1 Exit Observation。

---

# Owner Review Boundary

Program 完成后，Codex 必须停止。

Owner 将决定：

* 接受完整 Candidate；
* 请求修复；
* 要求局部重构；
* 要求修改交互；
* 要求补充验证；
* 从某个 Stage Commit 重新开始；
* 放弃部分实现；
* 是否创建 Pull Request；
* 是否合并到 `main`；
* 是否开始真实 Dogfooding；
* 是否进入正式 30 天 V1 Exit Observation。

Codex 不得把“自主执行授权”解释为：

* 自动接受所有实现；
* 自动批准合并；
* 自动批准发布；
* 自动批准未来 V2；
* 自动改变 Foundation Documents。

---

# Decision Summary

当前执行模式确认如下：

* V1 采用一次性 Autonomous Build 授权；
* 授权范围为 Macro Stage S1–S10；
* S1–S10 保留为工程和验证边界；
* 不再逐 Stage 等待 Owner 批准；
* Codex 在批准范围内自主规划、实现、测试、修复和提交；
* 普通、可逆、可验证的实现决策不升级；
* 只有方向冲突、重大架构、外部承诺、数据风险、平台边界和无法验证等高风险情况才升级；
* 所有产品实现发生在 `feat/v1-autonomous-build`；
* 不直接修改或合并 `main`；
* 不自动发布；
* 通过状态文件和 Commit 历史支持上下文中断恢复；
* 最终交付 V1 Candidate；
* 最终结果必须统一经过 Owner Review；
* 正式 30 天真实使用观察不由 Codex 自动完成或宣布通过。

---

# Open Questions

当前没有阻塞本文档进入 Owner Review 的开放问题。

具体 UI、局部类型设计、文件组织和普通实现选择，已经明确授权 Codex 在执行过程中按照本计划自主决定。

---

# Related Documents

* `Docs/INDEX.md`
* `Docs/VISION.md`
* `Docs/DESIGN_PRINCIPLES.md`
* `Docs/CORE_MODEL.md`
* `Docs/INFORMATION_ARCHITECTURE.md`
* `Docs/V1_SCOPE.md`
* `DEVELOPMENT_CONTRACT.md`
* `Docs/V1_IMPLEMENTATION_PLAN.md`
* `Docs/CURRENT_STATE.md`
* `Docs/CURRENT_TASK.md`
* `Docs/V1_AUTONOMOUS_STATUS.md`
* `AGENTS.md`

---

# Change History

| Version | Date       | Change                                                                           |
| ------- | ---------- | -------------------------------------------------------------------------------- |
| v0.1    | 2026-07-18 | Initial Owner Review Draft defining isolated-branch autonomous S1–S10 execution. |
