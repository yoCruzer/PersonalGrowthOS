# Information Architecture

| Item             | Value                         |
| ---------------- | ----------------------------- |
| **Project**      | Personal Growth OS            |
| **Document**     | `INFORMATION_ARCHITECTURE.md` |
| **Version**      | v0.2                          |
| **Status**       | Foundation Draft              |
| **Last Updated** | 2026-07-15                    |

---

# Purpose

本文档定义 Personal Growth OS 的信息架构（Information Architecture）。

它回答以下问题：

* 用户如何理解整个产品？
* 产品的一级信息结构如何组织？
* 各个模块分别负责什么？
* 用户最常见的操作路径是什么？

本文档关注产品的信息组织方式，而不是具体 UI 设计。

---

# Scope

本文档讨论：

* 一级导航结构；
* 模块职责；
* 用户信息流；
* 核心使用路径。

本文档**不讨论**：

* 页面视觉设计；
* UI 样式；
* 动画效果；
* 数据模型；
* 技术实现；
* 数据库存储；
* V1/V2 功能优先级。

这些内容将在其他 Foundation Document 或开发阶段确定。

---

# Design Goals

Information Architecture 应满足以下目标：

* 容易理解；
* 容易记录；
* 容易回顾；
* 容易找到内容；
* 不制造额外管理负担；
* 能够长期扩展。

整个产品应围绕：

> **记录 → 成长 → 回顾**

而不是围绕功能菜单组织。

---

# Overall Structure

Personal Growth OS V1 采用四个核心区域：

```text
Today

Timeline

Growth

Library
```

此外提供两个全局能力：

```text
Quick Capture

Search
```

以及一个系统区域：

```text
Settings
```

---

# Today

## Purpose

Today 是产品默认首页。

它回答：

> **今天，我需要记录什么？完成什么？**

Today 承载最高频的日常操作。

---

## Responsibilities

Today 负责：

* 快速记录；
* 今日 Habit；
* 当前 Goal / Flag；
* 今日重点。

Today 不负责：

* 浏览历史；
* 数据整理；
* 复杂统计；
* 长期分析。

---

## Core Sections

Today 建议包含：

```text
Quick Capture

Today's Habits

Active Goals
```

V1 支持用户手动创建轻量 Review Entry，但 Today 不要求设置独立 Review 区域。

未来可以增加：

* Review 提示；
* 今日 Journey；
* 今日推荐回顾。

但这些不是 V1 必需内容。

---

# Timeline

## Purpose

Timeline 是统一的人生时间轴。

它回答：

> **过去发生了什么？**

Timeline 是所有历史内容的主要浏览入口。

---

## Responsibilities

Timeline 展示：

* Entry；
* Review Entry；
* 重要 HabitLog；
* Goal 生命周期事件；
* Journey（未来）；

Timeline 应帮助用户：

重新理解自己的成长过程。

---

## Display Principles

Timeline 保存完整事实。

但展示应控制噪声。

例如：

一天完成多个普通 Habit：

可以聚合。

包含：

* 心得；
* 图片；
* 重要变化；

的记录：

应独立展示。

Timeline 的目标：

不是展示最多数据。

而是展示最有回顾价值的内容。

---

# Growth

## Purpose

Growth 是主动成长模块。

它回答：

> **我正在成长什么？**

Growth 管理：

长期持续存在的对象。

而不是一次性的记录。

---

## Responsibilities

Growth 包括：

```text
Habits

Goals
```

未来可以扩展：

* Learning；
* Skills；
* Challenges。

---

## Habits

Habits 管理：

* 当前 Habit；
* Habit 打卡；
* Habit 历史；
* Habit 生命周期。

Habit 是长期对象。

HabitLog 是具体执行记录。

---

## Goals

Goals 管理：

* Goal；
* Flag 的独立产品表达；
* Goal 生命周期；
* 与 Goal 关联的 Review Entry。

V1 的核心实体是 Goal，Flag 是 `GoalKind.flag`，不是另一套独立核心模型。

未来如果行为明显不同，再独立建模。

---

# Library

## Purpose

Library 是资料库。

它回答：

> **我的内容在哪里？**

Library 承担：

整理、

浏览、

搜索、

归档。

而不是：

日常记录。

---

## Responsibilities

Library 包括：

```text
Inbox

All Entries

Tags

Archived
```

未来可以增加：

* Places；
* People；
* Projects；
* Review Entry 独立浏览视图；
* Attachments。

---

## Inbox

Inbox 是：

Quick Capture 的缓冲区。

它表示：

> **尚未进一步整理。**

它不是：

待办事项。

用户长期保留 Inbox 内容也是正常状态。

系统不应制造：

"必须清空 Inbox"

的压力。

---

# Quick Capture

## Purpose

Quick Capture 是整个产品最重要的能力。

它应在任何页面都可使用。

Quick Capture 不属于任何单独模块。

而属于：

整个产品。

---

## Default Flow

```text
点击 +

输入文字和/或添加图片

保存
```

只要至少存在正文或一张图片，即可保存 Entry。正文不是必填项，因此 Quick Capture 支持仅文字、仅图片和图文混合。

默认：

创建：

Entry。

默认状态：

```text
kind = quickNote

status = inbox
```

保存之后，

用户可以稍后：

* 分类；
* 标签；
* 关联；
* 修改时间。

这些都不是保存前必须完成的操作。

---

# Search

## Purpose

Search 是全局能力。

而不是单独页面。

它帮助用户：

重新找到过去。

---

## Search Targets

V1 至少支持：

* Entry；
* Habit；
* Goal；
* Tag。

Review Entry 作为 Entry 的一种类型参与搜索。

未来：

支持：

* Journey；
* Place；
* Project。

搜索不要求用户：

先知道内容属于哪个模块。

---

# Settings

## Purpose

Settings 管理系统行为。

它不属于产品核心导航。

---

## Responsibilities

Settings 包括：

```text
Privacy

Notifications

Appearance

Data Export

Data Import

Sync（Future）

About
```

其中：

Data Export 和 Data Import 是 V1 的实际能力，而不只是架构预留。

基础导出覆盖 V1 核心数据和原始图片，可使用统一导出包承载结构化数据、原始图片和基础完整性信息，用于手动备份和设备迁移。

基础导入与导出格式相对应，并在导入后尽量恢复对象标识、关联关系和图片。

自动定时备份、复杂备份管理和多设备实时同步不属于 V1。Local First does not mean Local Only，未来仍可增加用户选择的同步能力。

---

# Navigation Principles

整个产品遵循：

> **高频操作更近，低频管理更远。**

因此：

Quick Capture、

Habit、

Timeline

应尽量减少操作步骤。

而：

设置、

导出、

恢复、

高级配置

可以放在较深层级。

---

# Primary User Flows

## Flow 1 — Quick Capture

```text
Any Screen

↓

+

↓

Input

↓

Save
```

Input 可以是文字、图片或两者组合。

---

## Flow 2 — Habit Check-in

```text
Today

↓

Habit

↓

Complete
```

如果补充心得：

创建并关联：

HabitLog

+

Entry。

简单打卡只创建 HabitLog。文字心得和图片由关联 Entry 承载，HabitLog 不直接拥有图片文件。

---

## Flow 3 — Goal

```text
Growth

↓

Goals

↓

Create

↓

Save
```

---

## Flow 4 — Browse History

```text
Timeline

↓

Browse

↓

Open Entry
```

---

## Flow 5 — Manual Review

```text
Create Review Entry

↓

Select Optional Period

↓

Relate Entries / Habit / Goal

↓

Save
```

Review 使用 `EntryKind.review`，由用户手动创建。自动 Review、AI Review、复杂统计和模板不属于 V1。

---

## Flow 6 — Organize

```text
Library

↓

Inbox

↓

Edit Entry

↓

Organized
```

---

# Information Hierarchy

整个产品采用：

```text
Today

↓

Timeline

↓

Growth

↓

Library
```

其中：

Today

代表：

现在。

Timeline

代表：

过去。

Growth

代表：

未来。

Library

代表：

长期管理。

它们共同组成：

Personal Growth OS。

---

# Future Expansion

未来可以增加：

* Journey；
* Places；
* Projects；
* 自动或高级 Review；
* People；
* AI Assistant。

但这些应建立在：

当前 Information Architecture

之上。

而不是重新设计一级导航。

---

# Decision Summary

当前已确认：

* 产品采用四个一级区域：Today、Timeline、Growth、Library。
* Quick Capture 是全局能力，而不是独立页面。
* Search 是全局能力，而不是一级导航。
* Today 是默认首页。
* Timeline 是统一回顾入口。
* Growth 管理长期成长对象。
* Library 管理整理与检索。
* Inbox 是缓冲区，而不是待办列表。
* Review 在 V1 中是用户手动创建的 `EntryKind.review`，可关联 Entry、Habit 和 Goal。
* 简单打卡只创建 HabitLog；文字和图片由关联 Entry 承载。
* Flag 是 `GoalKind.flag`，而不是独立核心实体。
* Quick Capture 支持仅文字、仅图片和图文混合。
* Data Export 和 Data Import 是 V1 的实际备份与迁移能力。
* 高价值内容优先展示，低价值内容可以聚合展示。

---

# Open Questions

当前无需要阻塞开发的开放问题。

后续若一级导航发生长期变化，再更新本文档。

---

# Related Documents

Foundation Documents：

* `VISION.md`
* `DESIGN_PRINCIPLES.md`
* `CORE_MODEL.md`
* `V1_SCOPE.md`
* `ROADMAP.md`（Planned）

---

# Change History

| Version | Date       | Change                    |
| ------- | ---------- | ------------------------- |
| v0.1    | 2026-07-15 | Initial Foundation Draft. |
| v0.2    | 2026-07-15 | Reconciled review, capture, habit-log, flag, and data-transfer flows. |
