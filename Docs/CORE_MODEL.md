# Core Model

| Item             | Value              |
| ---------------- | ------------------ |
| **Project**      | Personal Growth OS |
| **Document**     | `CORE_MODEL.md`    |
| **Version**      | v0.1               |
| **Status**       | Foundation Draft   |
| **Last Updated** | 2026-07-15         |

---

# Purpose

本文档定义 Personal Growth OS 的核心领域模型（Core Model）。

它回答以下问题：

* 产品中有哪些长期存在的核心对象？
* 它们分别承担什么职责？
* 它们之间如何建立联系？

Core Model 是整个产品的数据抽象，而不是数据库设计。

未来无论 UI、存储方式或技术架构如何变化，都应尽量保持 Core Model 的稳定。

---

# Scope

本文档讨论：

* 核心对象（Entities）；
* 对象职责；
* 对象之间的关系；
* 长期保持稳定的领域概念。

本文档**不讨论**：

* 数据库表结构；
* Swift 类型设计；
* 字段命名；
* JSON 格式；
* CloudKit；
* AI；
* UI 页面。

这些内容将在实现阶段确定。

---

# Design Philosophy

Personal Growth OS 并不是一个「笔记 App」。

它记录的是：

> **人生中的对象（Objects）以及它们之间的关系。**

用户真正记录的并不是一段文字。

而是：

* 一个想法；
* 一个习惯；
* 一个目标；
* 一次经历；
* 一段反思；

文字、图片等只是这些对象的表达方式。

因此，Core Model 应围绕真实人生建立，而不是围绕页面建立。

---

# Core Entities

V1 定义以下核心对象。

---

# Entry

## Purpose

Entry 是整个系统最基础的记录单元。

它代表一次真实记录。

例如：

* 一个想法；
* 一段反思；
* 一次经历；
* 一条备忘；
* 一张照片；
* 图片与文字组合。

Entry 是时间轴（Timeline）的主要组成部分。

---

## Characteristics

Entry：

* 可以只有文字；
* 可以只有图片；
* 可以同时包含文字与图片；
* 可以被修改；
* 可以关联其他对象；
* 默认进入 Inbox。

Entry 不要求：

* 标题；
* 标签；
* 分类；
* Goal；
* Habit。

这些都可以后续补充。

---

# Habit

## Purpose

Habit 表示一种长期培养的行为。

例如：

* 阅读；
* 跑步；
* 冥想；
* 记账；
* 早睡。

Habit 是长期对象。

它不会因为一次完成而结束。

---

# HabitLog

## Purpose

HabitLog 表示一次 Habit 的实际执行。

例如：

* 今天跑步 5 km；
* 今天阅读 30 分钟；
* 今天完成英语学习。

HabitLog 属于具体发生的事件。

它可以：

* 包含备注；
* 包含图片；
* 自动出现在 Timeline 中。

一个 Habit 可以拥有多个 HabitLog。

---

# Goal

## Purpose

Goal 表示一个希望达成的长期目标。

例如：

* 完成 Personal Growth OS V1；
* 减重 10 kg；
* 阅读 50 本书；
* 学会 Swift。

Goal 是长期存在的对象。

它拥有生命周期：

* Active；
* Paused；
* Completed；
* Abandoned；
* Archived。

---

# Flag

## Purpose

Flag 表示一种具有明确完成条件的挑战或承诺。

例如：

* 连续记录 30 天；
* 一个月不喝奶茶；
* 每天运动 21 天。

V1 中：

Flag 作为 Goal 的一种特殊类型。

未来如有必要，可独立建模。

---

# Tag

## Purpose

Tag 用于帮助用户重新找到内容。

Tag 是辅助组织能力。

它不是产品核心。

Tag 不应承担：

* 文件夹；
* 分类体系；
* 数据结构。

Tag 应保持轻量。

---

# Relationship Model

所有核心对象都可以建立自然联系。

例如：

```text
Entry
    │
    ├── relates to Goal
    ├── relates to Habit
    ├── uses Tag
    └── belongs to Timeline

Habit
    │
    └── owns HabitLogs

Goal
    │
    ├── supports Habits
    └── relates to Entries
```

关系存在的目的只有一个：

> **帮助未来更容易理解过去。**

而不是构建复杂知识图谱。

---

# Timeline Model

Timeline 不是一种对象。

它是：

> **所有重要事件按照时间形成的视图。**

Timeline 可以包含：

* Entry；
* HabitLog；
* Goal 生命周期事件；
* Flag 生命周期事件。

未来可以增加：

* Journey；
* Review；
* Place。

Timeline 是展示层，而不是数据实体。

---

# Inbox Model

Inbox 不是对象。

它是 Entry 的一种状态。

它表示：

> **这条记录尚未进一步整理。**

Inbox 不是：

* 待办事项；
* 错误状态；
* 必须清空的列表。

用户长期保留 Inbox 是正常行为。

---

# Rich Entry

V1 正式采用 Rich Entry 模型。

一条 Entry 可以包含：

* 标题（可选）；
* 正文（可选）；
* 图片（0～9 张）；
* 时间；
* 标签；
* 关联对象。

因此：

* 只有图片；
* 只有文字；
* 图片 + 一句话；
* 多张图片 + 长文；

都是合法记录。

图片属于 Entry 的核心内容，而不是附件。

---

# Object Lifecycle

不同对象拥有不同生命周期。

Entry：

```text
Created
↓

Edited
↓

Archived（Optional）
```

Habit：

```text
Active

↓

Paused

↓

Completed / Archived
```

Goal：

```text
Active

↓

Paused

↓

Completed

↓

Abandoned

↓

Archived
```

---

# Design Constraints

Core Model 应长期保持：

* 简单；
* 稳定；
* 易理解；
* 可扩展。

任何新增对象都应满足：

* 来自真实生活；
* 具有长期价值；
* 不与已有对象重复；
* 能提升记录或回顾体验。

否则，不应加入 Core Model。

---

# Decision Summary

当前已确认：

* Entry 是系统最基础的记录对象。
* Entry 采用 Rich Entry 模型，支持文字、图片或两者组合。
* Habit 与 HabitLog 分离建模。
* Flag 在 V1 中作为 Goal 的一种特殊类型。
* Timeline 是视图，不是实体。
* Inbox 是 Entry 的状态，不是独立对象。
* Tag 是辅助组织能力，而不是核心数据结构。
* 对象之间允许建立自然关联，但不构建复杂知识图谱。

---

# Open Questions

当前无需要阻塞开发的开放问题。

未来若新增长期核心对象（如 Journey、Place、People），再更新本文档。

---

# Related Documents

Foundation Documents：

* `VISION.md`
* `DESIGN_PRINCIPLES.md`
* `INFORMATION_ARCHITECTURE.md`
* `V1_SCOPE.md`
* `ROADMAP.md`（Planned）

---

# Change History

| Version | Date       | Change                    |
| ------- | ---------- | ------------------------- |
| v0.1    | 2026-07-15 | Initial Foundation Draft. |
