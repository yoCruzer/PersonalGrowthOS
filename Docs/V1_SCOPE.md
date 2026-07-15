# V1 Scope

| Item             | Value              |
| ---------------- | ------------------ |
| **Project**      | Personal Growth OS |
| **Document**     | `V1_SCOPE.md`      |
| **Version**      | v0.1               |
| **Status**       | Foundation Draft   |
| **Last Updated** | 2026-07-15         |

---

# Purpose

本文档定义 Personal Growth OS Version 1（V1）的产品范围（Scope）。

它回答以下问题：

* V1 的目标是什么？
* V1 应包含哪些能力？
* V1 明确不做哪些事情？
* 如何判断 V1 已经成功？
* 什么时候应该停止继续开发 V1，并进入 V2？

本文档用于控制产品范围，避免 V1 无限扩张。

---

# Scope

本文档讨论：

* V1 产品目标；
* 目标用户；
* In Scope；
* Out of Scope；
* Success Criteria；
* Exit Criteria。

本文档**不讨论**：

* UI 设计；
* 技术实现；
* 数据模型；
* Roadmap；
* V2 功能规划。

这些内容将在其他 Foundation Document 中定义。

---

# Product Goal

V1 的目标不是打造一个功能最丰富的 Personal Growth OS。

V1 的目标只有一个：

> **做出第一个真正值得每天使用的 Personal Growth OS。**

当用户产生记录冲动时，

能够自然地打开 Personal Growth OS，

完成记录，

并愿意长期坚持使用。

V1 的定位是：

> **Daily Driver，而不是 Release Candidate。**

它首先服务于真实生活，

再逐步走向更广泛的用户。

---

# Target Users

V1 面向：

> **自己，以及与自己需求高度相似的人。**

V1 并不试图一次满足所有用户。

产品的发展应建立在真实使用体验之上，

而不是假设需求。

用户既是产品的使用者，

也是产品持续演进的验证者。

---

# In Scope

V1 包含以下核心能力。

---

## Rich Entry

支持创建人生记录。

一条 Entry 可以包含：

* 标题（可选）；
* 正文（可选）；
* 图片（0～9 张）；
* 时间；
* 标签；
* 关联对象。

图片属于 Entry 的核心内容，

而不是附件。

支持：

* 仅文字；
* 仅图片；
* 图文混合。

---

## Quick Capture

提供最快速的记录入口。

支持：

* 一步创建 Entry；
* 默认进入 Inbox；
* 后续整理。

记录优先于整理。

---

## Timeline

统一浏览历史内容。

展示：

* Entry；
* HabitLog；
* Goal 生命周期事件；
* Flag 生命周期事件。

Timeline 应帮助用户重新理解自己的成长。

---

## Habit

支持：

* 创建 Habit；
* Habit 打卡；
* HabitLog；
* Habit 生命周期管理。

---

## Goal / Flag

支持：

* 创建 Goal；
* 创建 Flag；
* 生命周期管理；
* 与 Entry 建立关联。

V1 中：

Flag 作为 Goal 的一种特殊类型。

---

## Library

提供：

* Inbox；
* All Entries；
* Tags；
* Archived。

帮助用户：

整理、

浏览、

重新找到内容。

---

## Search

支持全局搜索：

* Entry；
* Habit；
* Goal；
* Tag。

搜索应帮助用户重新找到过去，

而不是要求用户记住内容放在哪里。

---

## Local Storage

V1 的核心能力应完全支持离线使用。

没有网络时，

依然能够：

* 创建记录；
* 浏览历史；
* 搜索内容；
* 管理 Habit；
* 管理 Goal。

---

## Data Ownership Foundation

V1 应为长期数据所有权建立基础。

包括：

* 数据导出；
* 数据导入（基础能力）；
* 数据备份与恢复的架构预留。

同步能力可在后续版本逐步完善。

---

# Out of Scope

以下内容明确不属于 V1。

不是因为它们不重要，

而是因为它们不影响 V1 成为 Daily Driver。

---

## AI

包括：

* AI 总结；
* AI 标签；
* AI 回顾；
* AI 写作；
* AI 分析。

---

## OCR

包括：

* 图片 OCR；
* 文档 OCR；
* 自动识别。

---

## Audio / Video

包括：

* 录音；
* 视频；
* Live Photo；
* 音频转文字。

V1 聚焦于：

文字与图片。

---

## Journey

旅行、

城市、

路线、

地图、

地点点亮。

保留长期规划，

不进入 V1。

---

## People

人物、

联系人、

关系管理。

不进入 V1。

---

## Projects

复杂项目管理、

任务协作、

团队能力。

不进入 V1。

---

## Family Sharing

家庭空间、

多人协作、

共享数据。

不进入 V1。

---

## Widgets

包括：

* Home Screen Widget；
* Lock Screen Widget；
* Apple Watch。

后续版本再考虑。

---

## Advanced Analytics

包括：

* 高级统计；
* 趋势分析；
* 数据洞察；
* AI Growth Report。

不属于 V1。

---

## Cross-platform

V1 聚焦：

iPhone。

Mac、

iPad、

Web

后续规划。

---

# Technical Boundary

V1 的技术边界：

* 平台：iPhone；
* iOS 17+；
* SwiftUI；
* Local First；
* 支持 Rich Entry；
* 为未来同步能力预留架构。

具体技术实现不属于本文档范围。

---

# Success Criteria

满足以下条件，

说明 V1 已达到预期目标。

---

## Daily Usage

用户连续使用 Personal Growth OS 进行真实记录。

记录来源于真实生活，

而不是为了测试。

---

## Default Capture Tool

> **80% 以上想记录的内容，都会下意识打开 Personal Growth OS。**

它成为用户默认的人生记录入口。

而不是 Apple Notes、

微信收藏、

截图、

纸笔等其他工具。

---

## Natural Usage

用户不会因为记录流程复杂，

而放弃记录。

记录已经成为自然习惯。

---

## Core Workflow Complete

用户能够完整完成：

```text
Capture

↓

Timeline

↓

Growth

↓

Review（基础回顾）
```

形成一个完整的成长闭环。

---

# Exit Criteria

满足以下条件后，

停止继续开发 V1，

进入 V2。

---

## Success Criteria 全部满足

首先，

V1 已达到 Success Criteria。

---

## Continuous Real-world Usage

至少连续 30 天，

真实使用产品。

不是为了测试，

而是真正记录生活。

---

## No Daily Blockers

产品不存在阻碍日常使用的核心缺失。

如果某项能力每天都会影响使用，

则继续完善 V1。

否则，

进入 V2。

---

## Everything Else Goes to V2

凡是不影响 Daily Driver 的新增需求，

全部进入 V2。

包括但不限于：

* AI；
* Journey；
* OCR；
* Widgets；
* Family；
* 高级统计；
* 地图；
* 视频。

避免 V1 无限扩张。

---

# Design Philosophy

V1 不追求功能完整。

而追求：

> **每天都会打开。**

真正决定 V1 是否成功的，

不是功能数量。

而是：

> **它是否已经成为用户记录人生最自然的地方。**

---

# Decision Summary

当前已确认：

* V1 的目标是 Daily Driver，而不是 Release Candidate。
* V1 面向自己及需求相似的用户。
* Rich Entry（文字 + 图片）属于 V1 核心能力。
* 图片是 Entry 的核心内容，而不是附件。
* 产品采用 Local First。
* 产品遵循 Data Ownership。
* V1 聚焦记录、成长与回顾。
* AI、Journey、OCR、家庭共享等能力全部进入 V2。
* Success Criteria 以真实使用为标准，而不是功能数量。
* Exit Criteria 以 Daily Driver 为判断依据，而不是继续增加功能。

---

# Open Questions

当前无需要阻塞开发的开放问题。

V2 功能规划将在 `ROADMAP.md` 中讨论。

---

# Related Documents

Foundation Documents：

* `VISION.md`
* `DESIGN_PRINCIPLES.md`
* `CORE_MODEL.md`
* `INFORMATION_ARCHITECTURE.md`
* `ROADMAP.md`（Planned）

---

# Change History

| Version | Date       | Change                    |
| ------- | ---------- | ------------------------- |
| v0.1    | 2026-07-15 | Initial Foundation Draft. |
