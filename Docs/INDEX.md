# Foundation Document Index

| Item             | Value              |
| ---------------- | ------------------ |
| **Project**      | Personal Growth OS |
| **Document**     | `INDEX.md`         |
| **Version**      | v0.1               |
| **Status**       | Foundation Draft   |
| **Last Updated** | 2026-07-15         |

---

# Purpose

本文档定义 Personal Growth OS Foundation Documents 的阅读顺序、文档职责和维护规则。

它帮助读者从长期愿景逐步理解设计原则、核心模型、信息架构和 V1 范围，并保持文档之间的一致性。

---

# Scope

本文档讨论：

* Foundation Documents 的阅读顺序；
* 各文档的职责边界；
* Foundation Documents 的维护规则；
* 当前文档状态。

本文档**不讨论**产品功能、UI、技术实现或开发计划。

---

# Reading Order

1. `VISION.md`
2. `DESIGN_PRINCIPLES.md`
3. `CORE_MODEL.md`
4. `INFORMATION_ARCHITECTURE.md`
5. `V1_SCOPE.md`
6. `ROADMAP.md`（Planned）

---

# Document Responsibilities

## VISION.md

回答：为什么做这个产品？

## DESIGN_PRINCIPLES.md

回答：设计和取舍时必须遵循哪些长期原则？

## CORE_MODEL.md

回答：系统中有哪些长期存在的核心领域对象和关系？

## INFORMATION_ARCHITECTURE.md

回答：用户如何理解、浏览和使用产品中的信息？

## V1_SCOPE.md

回答：V1 做什么、不做什么，以及何时结束 V1？

## ROADMAP.md

回答：后续版本如何演进？

---

# Foundation Document Rules

1. 不使用数字编号，采用稳定文件名。
2. 使用 `INDEX.md` 管理阅读顺序。
3. 一级标题使用文档名称，项目名称放在元信息中。
4. 所有 Foundation Documents 使用统一模板。
5. Foundation Documents 追求长期稳定，仅在长期决策变化时更新。
6. Foundation Documents 用于消除重大不确定性，不用于阻塞实际开发。
7. Done is better than perfect.
8. 除非长期方向发生变化，否则 UI、实现细节和普通迭代不应频繁修改 Foundation Documents。

---

# Current Status

| Document                     | Status                |
| ---------------------------- | --------------------- |
| `VISION.md`                  | Foundation Draft v0.2 |
| `DESIGN_PRINCIPLES.md`       | Foundation Draft v0.2 |
| `CORE_MODEL.md`              | Foundation Draft v0.2 |
| `INFORMATION_ARCHITECTURE.md` | Foundation Draft v0.2 |
| `V1_SCOPE.md`                | Foundation Draft v0.2 |
| `ROADMAP.md`                 | Planned               |

---

# Decision Summary

当前已确认：

* Foundation Documents 使用稳定文件名，并由 `INDEX.md` 管理阅读顺序。
* 每份文档保持清晰、互不替代的职责边界。
* 当前五份 Foundation Documents 均为 Foundation Draft v0.2。
* `ROADMAP.md` 尚未创建，状态为 Planned。

---

# Open Questions

当前无需要阻塞开发的文档治理问题。

---

# Related Documents

Foundation Documents：

* `VISION.md`
* `DESIGN_PRINCIPLES.md`
* `CORE_MODEL.md`
* `INFORMATION_ARCHITECTURE.md`
* `V1_SCOPE.md`
* `ROADMAP.md`（Planned）

---

# Change History

| Version | Date       | Change                    |
| ------- | ---------- | ------------------------- |
| v0.1    | 2026-07-15 | Initial Foundation Draft. |

## 已批准产品增量

`TODO_V1_SCOPE.md`：Build 12 同源提交后的轻量个人行动管理与构建溯源；原 V1 历史范围与发行事实保持。

验收与当前交接：[TODO_V1_ACCEPTANCE.md](TODO_V1_ACCEPTANCE.md)（A1–A25、P1–P8、Owner十分钟清单）；[TODO_V1_EXECUTION_LOG.md](TODO_V1_EXECUTION_LOG.md)（实际命令/结果/失败与补验）。

## 重要日子 V1 批准增量 — 2026-10-14

Owner 已批准独立 ImportantDay、Entry/Todo 有类型引用、独立封面、公历/农历日期规则、Today 条件摘要、共享本地提醒与两个桌面 Widget（数字/照片/清单）。保持五 Tab、Record 主路径、原 Bundle ID/主库位置及历史数据。允许必要的追加 Schema/备份版本与 Widget target；原 Widgets 后置范围仅被本增量限定替代。完整边界见固定版本 `IMPORTANT_DAYS_V1_GOAL_ZH.md` / `IMPORTANT_DAYS_V1_DESIGN_ZH.md`；不授权发布或操作私人库。


睡眠与作息 V1：`SLEEP_ROUTINE_V1_DESIGN_ZH.md` / `SLEEP_ROUTINE_V1_GOAL_ZH.md` 为批准规格与执行授权；`SLEEP_ROUTINE_V1_EXECUTION.md`、`SLEEP_ROUTINE_V1_REVIEW_ZH.md`、`SLEEP_ROUTINE_V1_ACCEPTANCE_ZH.md` 记录本轮进度、独立审查与组合验收，不覆盖重要日子历史证据。


## 时间投入 V1 批准增量 — 2026-10-16

时间投入 V1：`TIME_INVESTMENT_V1_DESIGN_ZH.md` / `TIME_INVESTMENT_V1_GOAL_ZH.md` 为固定1.1批准增量；执行、独立审查及验收分别见 `TIME_INVESTMENT_V1_EXECUTION.md`、`TIME_INVESTMENT_V1_REVIEW_ZH.md`、`TIME_INVESTMENT_V1_ACCEPTANCE_ZH.md`。当前状态以 `CURRENT_STATE.md` / `CURRENT_TASK.md` 及验收记录为准，不代表设备或发行通过。

## 使用反馈统一整改批准增量 — 2026-10-18

基于时间投入 V1 最终交接 5a70f0110b151f8a45ac7c33d3f443823b1cff24，统一处理使用反馈 20261017 九项与时间投入同类展示问题。执行规格：[USAGE_REMEDIATION_20261017_GOAL_ZH.md](USAGE_REMEDIATION_20261017_GOAL_ZH.md) / [DESIGN](USAGE_REMEDIATION_20261017_DESIGN_ZH.md) / [ACCEPTANCE](USAGE_REMEDIATION_20261017_ACCEPTANCE_ZH.md)，均为同一固定提交的 1.0。阶段属于一个连续执行目标，现仅规格准备；不表示实现、独立实现 review 或设备门禁通过。范围增量见 V1_SCOPE，本轮进展以 CURRENT 两份文件与新验收记录为准，旧历史原样保留。


## PR #13 独立复核后的本地修复 — 2026-10-18

[PR #13 独立复核后的本地修复目标](USAGE_REMEDIATION_20261018_REVIEW_FIX_GOAL_ZH.md)：基于已审交付 f1b52b58fd11c41f508ec665d583827879ffa202，连续修复新 F1–F5 并落实 UX1 / UX2，沿用既有 PR #13 与原 base。新 FIX_GOAL_SHA 由引导 prompt 固定。当前仅规格准备，执行 / 验证均待完成；本地执行停点由新 Goal 和 CURRENT 最新章节替代，旧 A–D / R1–R8 证据及设备 / 发行边界保留。

## PR #13 第二轮独立复核限定补修 — 2026-10-18

[第二轮限定修复 Goal](USAGE_REMEDIATION_20261018_REVIEW_FIX2_GOAL_ZH.md)：基于已审交付 e75ac561 / 产品597552a，处理 CR-01～06 和 OBS-01/02 的限定补验。Owner 已批准沿同一 Draft PR #13 / 原 base 连续执行，FIX2_GOAL_SHA 由短引导 prompt 固定。本次仅规格准备，新的实现与原生验证均未执行；两份 CURRENT 最新章节和新 Goal 取代前轮仅等设备的本地停点。已认可修复作为保护，旧失败轮次和设备/发行边界保留。
