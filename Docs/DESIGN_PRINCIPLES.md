# Design Principles

| Item             | Value                  |
| ---------------- | ---------------------- |
| **Project**      | Personal Growth OS     |
| **Document**     | `DESIGN_PRINCIPLES.md` |
| **Version**      | v0.2                   |
| **Status**       | Foundation Draft       |
| **Last Updated** | 2026-07-15             |

---

# Purpose

本文档定义 Personal Growth OS 的长期设计原则（Design Principles）。

它回答以下问题：

* 做任何产品设计时，哪些原则不能违背？
* 当多个方案都可行时，应该如何做取舍？
* 哪些价值观会长期指导产品的发展？

本文档关注长期原则，而不是具体功能或交互实现。

---

# Scope

本文档讨论：

* 产品设计原则；
* 产品价值观；
* 长期设计哲学。

本文档**不讨论**：

* 页面布局；
* UI 风格；
* 数据模型；
* 技术实现；
* V1 功能范围；
* 具体交互细节。

这些内容将在其他 Foundation Document 中定义。

---

# Principle 1 — Human First

产品始终服务于人的成长，而不是服务于数据、指标或活跃度。

每一个设计都应该回答：

> **它是否真正帮助用户记录、理解或改善自己的人生？**

如果答案是否定的，那么它不应该进入产品。

---

# Principle 2 — Capture Before Organize

记录永远优先于整理。

当用户产生一个值得记录的想法时，产品应该帮助用户快速保存，而不是要求用户先完成分类、标签或整理。

系统应该允许：

* 先记录；
* 后整理；
* 不整理。

永远不要因为流程复杂而让一条重要记录消失。

---

# Principle 3 — Preserve the Original

原始记录具有不可替代的价值。

Preserve the Original 主要约束系统自动处理，包括自动分类、自动摘要、格式转换和未来 AI 处理。

这些能力不得不可逆地覆盖用户输入。未来的 AI、自动摘要或自动分类结果，应作为附加信息或建议，而不是替换原始用户内容。

用户可以主动修改自己的 Entry。V1 不要求保存每次用户编辑的完整历史版本，也不因此引入复杂版本控制系统。

成长不仅来自最终结论，也来自认知变化的过程。

---

# Principle 4 — Privacy by Default

人生记录可能包含最真实、最敏感的内容。

因此：

隐私保护不是一个可选功能，而是默认原则。

任何涉及数据共享、云同步或 AI 处理的能力，都应建立在用户明确知情和主动选择的基础上。

---

# Principle 5 — Local First

用户的数据首先保存在本地。

核心功能应尽可能在本地完成。

即使没有网络，用户依然应该能够：

* 创建记录；
* 查看历史；
* 搜索内容；
* 管理 Habit；
* 管理 Goal；
* 完成日常使用。

**Local First 并不意味着 Local Only。**

本地优先强调的是：

> **本地设备是用户数据的主要来源（Primary Source of Truth）。**

而不是：

> **数据永远不能离开当前设备。**

网络能力属于增强能力，而不是产品存在的前提。

---

# Principle 6 — Progress Over Perfection

成长不是追求完美，而是持续前进。

产品不应因为连续打卡中断、目标放弃或阶段性失败而制造羞耻感。

失败、暂停、改变方向和重新开始，都是成长的一部分。

系统应该记录这些经历，而不是隐藏它们。

---

# Principle 7 — Reflection Creates Value

记录本身并不能创造价值。

真正的价值来自：

* 重新阅读过去；
* 理解自己的变化；
* 发现长期规律；
* 总结经验；
* 形成新的认知。

因此，产品设计应始终围绕：

> **帮助未来的自己理解过去的自己。**

---

# Principle 8 — Connection Should Be Natural

人生中的经历本来就是相互关联的。

产品应该帮助用户自然建立这些联系，而不是要求用户维护复杂的数据结构。

任何关联，都应该让未来：

* 更容易搜索；
* 更容易回顾；
* 更容易理解。

如果一种关联没有实际价值，就不应该增加它。

---

# Principle 9 — Quiet by Design

Personal Growth OS 不应该成为另一个争夺注意力的 App。

它不会通过：

* 焦虑营销；
* 红点轰炸；
* 无限通知；
* 排行榜；
* 社交比较；

来提高活跃度。

用户打开 App，

应该因为：

> **我想记录我的人生。**

而不是：

> **App 希望我回来。**

---

# Principle 10 — Build From Real Life

所有新功能，都应该来自真实生活。

设计之前，应先回答：

* 这个场景真实存在吗？
* 用户真的会遇到吗？
* 当前有哪些痛点？
* 它是否值得长期保存？

产品的发展应建立在真实使用体验之上，而不是假设和想象。

---

# Principle 11 — Data Ownership

用户真正拥有自己的数据。

Personal Growth OS 不应通过技术或产品设计，将用户的数据锁定在某一台设备、某一种同步方式或某一个平台中。

系统应长期支持：

* 数据导出；
* 数据导入；
* 数据备份；
* 数据恢复；
* 多设备同步；
* 用户自主选择同步方式。

例如：

* iCloud；
* 本地文件；
* 用户未来选择的其他同步方式。

同步方式可以不断演进。

但数据所有权始终属于用户。

即使未来停止开发 Personal Growth OS，用户依然应该能够完整带走自己的人生记录。

> **Your memories belong to you.**

---

# Design Decision Priority

当多个方案都可以实现时，建议按照以下优先级进行取舍：

1. 保护用户数据与隐私；
2. 保证快速记录；
3. 保留原始内容；
4. 保证用户拥有自己的数据；
5. 保持长期可维护性；
6. 提高回顾价值；
7. 降低学习成本；
8. 丰富功能。

如果一个方案能够增加功能，却明显降低记录效率或增加使用负担，应优先选择更简单的方案。

---

# Development Philosophy

Personal Growth OS 采用渐进式产品开发方式。

Foundation Document 的目标，是消除重大方向上的不确定性，而不是提前解决未来所有问题。

当整体方向已经明确，并且架构不存在明显问题时，应尽快进入开发和真实使用。

真实使用，是产品设计最重要的反馈来源。

> **Done is better than perfect.**

> **Good enough to build.**

---

# Decision Summary

当前已确认：

* 产品始终以用户成长为中心，而不是以活跃度为中心；
* 记录优先于整理；
* 用户可以主动编辑 Entry，V1 不要求完整版本历史；
* 系统自动处理不得不可逆地覆盖用户输入，自动处理结果应作为附加信息或建议；
* 默认保护用户隐私；
* Local First 是长期架构原则，而不是 Local Only；
* 用户始终拥有自己的数据；
* 回顾比收集更重要；
* 产品应帮助用户建立自然联系；
* 产品保持克制，不争夺注意力；
* 所有功能都应来自真实生活场景；
* 产品采用渐进式开发，而不是一次性设计完整。

---

# Open Questions

当前无需要阻塞开发的开放问题。

未来新增长期设计原则时，再更新本节。

---

# Related Documents

Foundation Documents：

* `VISION.md`
* `CORE_MODEL.md`
* `INFORMATION_ARCHITECTURE.md`
* `V1_SCOPE.md`
* `ROADMAP.md`（Planned）

---

# Change History

| Version | Date       | Change                    |
| ------- | ---------- | ------------------------- |
| v0.1    | 2026-07-15 | Initial Foundation Draft. |
| v0.2    | 2026-07-15 | Clarified original-content preservation and document status. |
