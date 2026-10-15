# PR #10 独立深度审查 — 重要日子 V1

日期：2026-10-15  
仓库：`yoCruzer/PersonalGrowthOS`  
结论：**CHANGES_REQUESTED（审查意见，未向 GitHub 提交状态变更）**。本轮确认四处需要限定修复的 P2 代码问题；未确认新的 P0/P1。另有一处不单独阻塞的 P3 预览不一致。不建议继续沿用“范围内 P0/P1/P2 全部关闭”的结论。

本报告不授权更改产品范围、合并、tag、Archive、TestFlight 或真实手机数据操作。远端 PR/代码均未修改。

## 1. 固定审查对象

| 项目 | 核对结果 |
| --- | --- |
| PR | #10，OPEN Draft；head `codex/important-days-v1`，base `codex/quiet-wins-on-d72` |
| 产品基线 | `20d315a62179ad29a6cbcf76c33c11638412e54e` |
| 固定规格 | `3365561c5888701ce662ac6c8655ad1629ded6d0` |
| 最后生产代码 | `9f34034357ea9329730ab18bfbf6d4b6e426b4b4` |
| 产品/测试提交 | `b3cc408d323e5828e9550decac72ae534f1b0b20` |
| 本轮审查 HEAD | `4e407591868d63c96a647494d5aa8a91a6fcc5b3` |
| 9f → b3 | 一个提交，只改 `PersonalGrowthOSTests/ImportExportRecoveryTests.swift` |
| b3 → 4e | 一个提交，只改五份交接 Markdown；不是五个提交 |
| 相对产品基线 | 10 个提交、57 个变更文件；核对变更清单，并重点深读新生产逻辑、集成差异及新测试 |

比较依据：[9f→b3](https://github.com/yoCruzer/PersonalGrowthOS/compare/9f34034357ea9329730ab18bfbf6d4b6e426b4b4...b3cc408d323e5828e9550decac72ae534f1b0b20)、[b3→4e](https://github.com/yoCruzer/PersonalGrowthOS/compare/b3cc408d323e5828e9550decac72ae534f1b0b20...4e407591868d63c96a647494d5aa8a91a6fcc5b3)。

## 2. 证据等级与执行边界

### 本轮实际做了什么

- 通过 GitHub 连接器读取固定 SHA 的代码、PR diff、提交比较、验收/执行/审查文档和新测试。
- 针对日期、关联、持久化与备份、通知协调、照片所有权、组件快照/撤权/渲染、路由和工程配置做代码复核。
- 本地用 Swift 6.2.1 / Linux 执行了四组“反例 + 对照”逻辑探针；它们实际显示了本报告 R1–R4 的错误状态。另运行了 R5 预览诊断。
- 日期源文件复制后核对 Git blob SHA 为 `456a4cca8a78c51f49fd6f263bafd19f9e712163`，与固定仓库文件一致。

### 本轮没有做什么

- 没有 Xcode、SwiftUI、SwiftData 或真实 iOS 运行环境；没有重跑 App 的 XCTest、模拟器 UI、签名或真机测试。
- 逻辑探针对视图状态/服务排序表达式进行了隔离，不是实际 SwiftUI 生命周期或 SwiftData 磁盘集成测试。R1 的真实跨日编辑、R2 的 Picker 更新、R4 的搜索中拖动仍应在修复任务中补实际 App 反例测试。
- 没有读取开发者 Mac 上 `/private/tmp/pgos-important-days-evidence` 的原始 xcresult、日志和 PNG。仓库文档中的运行结果属于开发方记录，不当作本轮独立重跑证据。
- 没有逐项人工核对整个本地化字串表，也没有把工程配置正确等同于实际签名/发布成功。

### Linux 编译适配说明

直接编译原日期文件时，Linux Swift 6.2.1 对下面表达式出现名字解析/类型推断错误：

```swift
let original = try rule.year.flatMap { try original(rule, in: $0) }
```

为了运行探针，仅在临时副本中把被调用的静态方法限定为 `Self.original(rule, in: $0)`，未改变日期算法或产品仓库。该兼容性差异**没有被列为 iOS 构建缺陷**。实际完整输出见同目录 `verified_probe_results.txt`。

探针退出码为 0 表示“成功观测到预期的反例及对照”，绝不表示“四个产品测试全部通过”。

## 3. R1 — P2：默认纪念期次未固定，编辑跨日后可能关联到下一年

### 位置

- [ImportantDayViews.swift:121–144](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/ImportantDays/ImportantDayViews.swift#L121-L144)：`occurrenceYear` 为可选状态，未设置时根据 `nextOccurrence` 计算 `selectedYear`。
- [ImportantDayViews.swift:170–183](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/ImportantDays/ImportantDayViews.swift#L170-L183)：打开指定期次只改变 Bool，未冻结默认年份；点击写记录只设置 `writing = true`。
- [ImportantDayViews.swift:229–257](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/ImportantDays/ImportantDayViews.swift#L229-L257)：保存闭包读取 `selectedOccurrence`；跨日、重要时间变化和前台恢复会更新 `referenceDate`。
- [QuickCaptureView.swift:353–368](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/Capture/QuickCaptureView.swift#L353-L368)：真正点击保存时才调用传入的 `saveDraft`。

### 触发与结果

保存一个 2020-10-15 开始的年度纪念日。2026-10-15 打开“关联某个纪念年份”，接受界面默认的 2026 年，不滚动年份 Picker，进入写记录。编辑过程中跨过午夜，或次日前台恢复后保存。

此时 `occurrenceYear` 仍为 nil。界面参考日更新到 2026-10-16 后，`nextOccurrence` 为 2027-10-15，保存闭包读取的 `selectedOccurrence` 也随之变为 2027-10-15。用户原本正在记录的 2026 年纪念内容会关联到下一年。

本地探针实际输出：

```text
opening period=2026-10-15
same nil-year selection after midnight=2027-10-15
explicitly frozen year keeps period=2026-10-15
```

这是关联事实可能写错，不只是屏幕上的倒数发生变化。Entry 的正文不丢失；“新记录默认发生在今天”也不应因此被改坏。

### 限定修复

在发起写记录/关联记录/相关待办时，固定一个操作上下文：日子稳定 ID、明确选中的期次日期或 nil。保存读取该上下文，不读取会随着“今天”变化的展示计算值。用户未主动改期次，就不能因跨日偷偷更改。

如果原日子的规则在操作期间改变，重新验证并明确提示，不把原选项静默替换成下一期。无需重做导航架构或持久化整套编辑会话。

### 必要回归

在实际 App 代码可注入的参考时钟下：接受默认年份→打开编辑→跨午夜→保存，断言链接仍是打开时的期次；手动选定历史年份为正对照。再覆盖普通关联 nil、农历跨公历年、取消重开。不要用真实等待午夜替代可重复测试。

现有 `testExplicitPastLunarPeriodSavesActualCivilDateAndFiltersAfterRelaunch` 主动滚动选择了 2024 年，因此不覆盖默认 nil 年份的路径。

## 4. R2 — P2：取消最后一条带期次的关联后，筛选失效且切换入口消失

### 位置

- [ImportantDayViews.swift:127–131](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/ImportantDays/ImportantDayViews.swift#L127-L131)：从当前关联生成 `periods`，但 `relatedEntries` 持续按旧的 `occurrenceFilter` 过滤。
- [ImportantDayViews.swift:186–198](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/ImportantDays/ImportantDayViews.swift#L186-L198)：只有 `periods` 非空才显示 Picker；滑动解除关联后没有修复当前筛选值。

### 触发与结果

一个日子有两条普通关联记录、另有一条标记为 2026-10-15 的纪念记录。在详情中筛选到 2026-10-15，再解除这一条记录的关联。

解除后 `periods` 已经为空，Picker 被隐藏；`occurrenceFilter` 仍是 2026-10-15，所以两条普通记录也无法显示。页面出现“暂无相关记录”，而不是让用户回到“全部”。退出重进可以恢复，但当前页面没有可用的筛选复位入口。

本地探针结果：剩余关联 2 条，`periods=[]`，显示记录 `[]`；仅将 filter 改为 `all` 就重新得到两条普通记录。

这是**可见性/导航状态错误，不是两条普通记录被删除**。

### 限定修复

来源关联变化后，检查当前具体期次是否仍存在；不存在就回到“全部”等确定的可用筛选。有效期次应保留。或者始终保留能够切回全部/普通记录的入口，不能把唯一的恢复控件一起隐藏。

### 必要回归

“普通记录 + 最后一条特定期次记录”→筛选→解除关联→留在原页，断言普通记录立刻可见且筛选有效。补删除对应 Entry、另一个期次仍存在的对照。测试必须覆盖视图/选择状态，单独测 `unlinkEntry` 删除成功不能证明此问题已修复。

## 5. R3 — P2：农历闰月切换到公历后，隐藏的闰月标志阻止保存

### 位置

- [ImportantDayViews.swift:327–341](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/ImportantDays/ImportantDayViews.swift#L327-L341)：表单有效性依赖规则校验；历法确认只更新确认状态。
- [ImportantDayViews.swift:448–484](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/ImportantDays/ImportantDayViews.swift#L448-L484)：历法 onChange 不清理不兼容字段；闰月开关只在农历时可见。
- [ImportantDayDate.swift:70–82](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/Shared/ImportantDays/ImportantDayDate.swift#L70-L82)：公历规则要求 `isLeapMonth == false`，这一校验本身正确。

### 触发与结果

编辑一个有效农历闰月日子，例如 2023 年闰二月初一，`isLeapMonth=true`。切换成公历，并明确确认使用新历法下的日期。

公历年月日数值可以有效，但隐藏的 `isLeapMonth` 仍然为 true；公历校验拒绝该规则，保存不可用。公历页面又不显示闰月开关，用户只能猜出需要切回农历清除标志再重新切换。

本地探针验证：公历数值日期有效、闰月开关应隐藏、规则校验仍失败；只清除不兼容闰月标志后，同一公历日期即可通过校验。

### 限定修复

在明确的历法切换/确认流程中，构造合法的目标历法规则并清理不兼容字段，同时保留当前已经实现的“重新解释日期需确认”语义。不能通过放宽公历验证、允许“公历闰月”来绕过。

注意不要回归刚修复的表单首次加载误触历法确认问题；加载已有草稿与用户主动换历法仍需区分。

### 必要回归

闰月农历→公历→确认→保存→重开；普通农历→公历正对照；公历→农历需确认；切换后取消不修改原日子。断言隐藏状态与保存的规则一致，避免只调用 `rule.validate()` 而遗漏编辑器转换。

## 6. R4 — P2：在搜索结果中调整常看顺序，会写坏全局手工排序

### 位置

- [ImportantDayViews.swift:21–32](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/ImportantDays/ImportantDayViews.swift#L21-L32)：`favorites` 来自已经按搜索和归档条件过滤的 `visible`。
- [ImportantDayViews.swift:51–57](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/ImportantDays/ImportantDayViews.swift#L51-L57)：onMove 只提交当前可见 favorites 的 ID。
- [ImportantDayFoundation.swift:189–199](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/ImportantDays/ImportantDayFoundation.swift#L189-L199)：将传入的子集从 0 重新编号并保存，未同时处理隐藏项目的排序值。

### 触发与结果

原全局常看顺序 A0、B1、C2、D3。搜索只匹配 C、D，在可排序模式中将 D 移到 C 前面。

服务写入 D0、C1，却保留 A0、B1，造成两个 0 和两个 1。清除搜索后，排名相同的项目改由 UUID 平局规则排序；在本地确定性样例中，结果为 A、D、B、C，而不是只在原 C/D 位置上交换后的 A、B、D、C。

这里的问题不只是不符合某种拖动偏好：它将局部排序当成全局序号写入，丢失全局排序不变量，而且代码会保存这些值。

### 限定修复

最小方案：有搜索过滤时禁用拖动并解释需要先清除搜索；正常完整常看列表仍允许重排。另一方案：将可见子集的新排列合并回完整常看列表，保留隐藏项目位置，再统一更新全局顺序。

归档筛选下的排序也要使用明确的序号域，不能再次混用部分视图与全局排序。无需引入通用排序平台。

### 必要回归

全量常看排序、搜索匹配子集、清除搜索、磁盘重开，断言隐藏项目相对位置与全局排序一致。现有 `testLowSpaceCoverSaveAndFavoriteReorderFailuresPreserveCommittedFacts` 测的是完整 ID 集合和失败回滚，不覆盖过滤子集。

## 7. R5 — P3，非单独阻塞：额外预览可能早于起始年份

位置：[ImportantDayViews.swift:520–522](https://github.com/yoCruzer/PersonalGrowthOS/blob/4e407591868d63c96a647494d5aa8a91a6fcc5b3/PersonalGrowthOS/ImportantDays/ImportantDayViews.swift#L520-L522)。

`previewDates` 从 today.year-1 开始枚举，没有约束候选年份不小于 `rule.year`。例如参考日 2026-10-15，起始年设为 2030、纪念月日为 12-01：主引擎给出 next=2030-12-01，额外三行却显示 2026、2027、2028。

主日期引擎和提醒规划器有起始年约束，本轮没有证据表明该差异已污染存储或通知，所以不升级为核心日期算法 P1/P2。建议顺手让预览复用相同的起始年约束，并添加一个未来起始年对照。

## 8. 目前没有确认新阻塞缺陷的路径

以下是已读代码层面的结论，不代表实际运行门禁 PASS：

| 范围 | 代码层核对结果 | 仍需区分的证据边界 |
| --- | --- | --- |
| Schema 与身份 | V12 追加四个实体，未在本 diff 中改旧 Entry/Todo 模型定义；工厂/迁移链/当前库保护同步指向 V12 | 真机覆盖升级、签名未重跑 |
| v8 备份 | 日期、关系、独立封面纳入序列化与媒体校验；新版本四数组有缺失/null拒绝；旧版本不能假带新 keys | 原始 xcresult 不在当前环境；不得把 source=nil 来源恢复限制说成已修 |
| Entry/Todo | 独立关系，没有用伪 Entry 冒充；删除清理引用，不级联删对方；新 Todo 关系在既有事务内创建 | 本轮所报 R1/R2 是上层状态组合，不否认这些底层保护 |
| 媒体所有权 | 独立封面副本、保存失败回滚/删除新文件、源 Entry 删除不持有同一文件所有权 | 完整 Photos UI 和设备中断没有实测 |
| 提醒 | Todo/日子共享候选、容量、串行 gate，保留每日/每周前缀；实际 pending 复核；部分排期状态保留 | 系统递送、Focus、跨时区长期表现仍是设备项 |
| Widget 隐私 | 仅显式授权日子进入快照；不读主 SwiftData；撤权优先撤共享文件；背景照片及文字检查隐私 redaction | 系统已渲染缓存不由 App 保证立即清除，真实桌面与着色没有实测 |
| 路由 | UUID 路由、未授权/删除/归档降级；已有 modal 时暂存请求；不重建五 Tab | 当前环境没有实际重跑草稿/冷启动/通知 UI |
| 工程 | 新 target、sources、resources、App Group、Embed App Extensions、URL scheme 的差异已核对 | 未签名构建报告不等于签名与发布成功 |

相关源文件以固定 HEAD 下的 `PersistenceFoundation.swift`、`ImportExportService.swift`、`TransferModels.swift`、`ImportantDayTransfer.swift`、`TodoReminders.swift`、`ImportantDayWidgetPublisher.swift`、`ImportantDayWidgetSnapshot.swift`、`ImportantDayWidgetViews.swift`、`ImportantDayRouting.swift` 和 `project.pbxproj` 为准。

Apple 对 root 环境读取 `.redactionReasons` 以提供定制隐私内容有明确说明：[RedactionReasons.privacy](https://developer.apple.com/documentation/SwiftUI/RedactionReasons/privacy)。本轮没有把已经加入背景隐私分支的修复重复报成 P1，也不把离屏渲染自动当作真实桌面证明。

## 9. 如何看待这次 358/362 → 53/53 + 17/17

开发方记录：9f 完整 Unit 362 项，358 成功、4 失败、0 跳过；b3 只修 `ImportExportRecoveryTests.swift` 的旧 wire/计数夹具，随后整个备份类 53/53、集中 UI 17/17；三种无签名构建通过。记录见固定 HEAD 的 `Docs/IMPORTANT_DAYS_V1_ACCEPTANCE_ZH.md`、`IMPORTANT_DAYS_V1_EXECUTION.md` 和 `IMPORTANT_DAYS_V1_REVIEW_ZH.md`。

本轮独立核对 b3 的改动确实仅在测试文件。旧格式处理只在新数组为空时移除新字段，没有把非空新数据静默剥除；还加入 v8 缺失/null 负例和合法 v7 对照。没有确认到为了绿灯弱化生产校验的做法。

因此，**“未再跑完整 362 项”不应自动成为要求整套重做的理由**；这是已批准的按风险补测策略可接受的用法。但也不能据此写成一次 362/362 全绿。本轮四个发现来自现有测试未覆盖的状态组合，而不是这四个夹具修复本身。

对 b3 查询 combined commit status 和连接器支持的 PR-triggered workflow runs 均为空；未取得独立 CI 通过证据。工作流列表 GET 不被当前连接器允许，因此本轮不以此声称重新独立证明了仓库“工作流总数为 0”。

## 10. 建议的限定修复与复审边界

在原 `codex/important-days-v1` / Draft PR #10 上处理 R1–R4，不重开重要日子完整 Goal，不扩展功能，不更换数据方案。

1. 先在实际生产状态层或 App UI 中补每项反例测试，再做最小修改。本文逻辑探针不能直接冒充最终回归测试；其断言本来就是观测当前错误行为。
2. 优先固定操作期次与修复历法转换，再归一筛选状态、明确过滤排序政策。R5 可顺手修，但不拖成大范围 UI 翻新。
3. 运行受影响日期/关联/排序/编辑 UI；重跑现有“明确往年期次”“编辑 preset 后期次复位”“最短记录/重开”等相邻正对照。
4. R1 若改 QuickCapture 的通用接口，则补默认 Record 与关联记录、草稿/取消/路由回归；R4 若改排序保存服务，则补失败回滚与磁盘重开。不修改旧业务源字段或来源判断。
5. 仅此范围不要求机械重跑整个 362 项；若实际扩到迁移、备份或共享通知，再按真实影响扩大验证。
6. 独立审查固定新 product/test SHA，逐项关闭 R1–R4；交付文档如实更新状态和测试证据，不保留“所有 P2 关闭”与新发现互相矛盾的陈述。

原有 v7/v8 导入收据恢复限制、Goal 时钟回拨 P2、四条已有布局警告继续按原接受边界保留，不借此轮重新扩修。

四项修复与复审收敛后，再进入“未来旅行、过去起点、农历生日、已有图文周年”的 Owner 真机验证。不要把代码侧已知、可自动复现的问题先转给 Owner 手工兜底。

## 11. 可复现逻辑探针

文件：`ReviewProbes.swift`、`run_review_probes.py`、原始 `ImportantDayDate.swift`、`verified_probe_results.txt`。

已有本地仓库时，脚本仅通过 git show 读取固定 SHA，不 checkout、不修改工作区、不访问网络：

```bash
python3 run_review_probes.py --repo /path/to/PersonalGrowthOS --output review-probe-results.txt
```

没有本地仓库时，将原始日期源文件、探针和脚本放在同一目录，再运行：

```bash
python3 run_review_probes.py --output review-probe-results.txt
```

脚本先核对源文件 blob，编译在临时目录完成。Linux 下只有明确记录的一行名称限定适配；macOS 默认编译原文件。当前实际运行环境是 Linux，不声称上述 macOS 运行已经执行。

---

**总体判断：实现架构与数据保护方向没有需要推倒重做的证据；问题主要集中于“显示状态 → 用户选择 → 保存事实/全局状态”的交界处。先用一轮限定修复收口这四处 P2，再保留真机阶段去验证系统真正只能在设备上证明的部分。**
