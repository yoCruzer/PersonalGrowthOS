# PersonalGrowthOS PR #11 深度独立审查

**结论：CHANGES_REQUESTED。确认三个本轮范围内 P2；未确认新 P0/P1。**

本结论是外部审查意见，不是对 GitHub PR 状态的实际修改。未修改仓库、PR、标签或发布流程。建议先限定修复以下三项，再恢复 READY_FOR_OWNER_DEVICE_GATE；不是要求推翻睡眠架构或重做重要日子。

## 固定范围与证据等级

- 仓库：yoCruzer/PersonalGrowthOS；PR #11，Open Draft，base `codex/important-days-v1`。
- 基线：`5614246f98ae63732ccd4fd8a6b66f4a425336f2`。
- 产品/测试：`138616cd0970b0f4fba9d0c7d7d44f6ca7d30b53`。
- 交付：`5f7dc3eeba4d159d72e03029f487cf67bf77ab1a`；父提交是上述产品 SHA，交接变更为 Markdown。
- 核对：批准的设计/Goal、PR diff、五个睡眠生产文件、Schema/启动保护/备份/恢复、AppShell 与通知协调、工程注册，以及睡眠 Unit/UI 和相邻测试变更。未重新对整个重要日子历史实现做全库审计。
- 独立执行：Linux x86_64 / Swift 6.2.1 上的 `review_probe.swift`。按固定生产源码移录纯逻辑与协调器末段，使用简单 DTO/注入通知状态；无 SwiftData/SwiftUI/UNUserNotificationCenter 运行环境，不是 iOS 工程测试。
- 原报告的 xcresult、截图、签名包和系统日志位于 Owner Mac 的本地路径，本次没有访问这些原始产物。406/406、410/410 等是仓库报告记录的运行结果，不是本次重新执行的结果。

## R1 · P2：回顾页编辑保存后，旧计算时钟把新填写字段误排除

### 生产位置

- `PersonalGrowthOS/Sleep/SleepViews.swift`：SleepReviewView 的 `reference`、snapshot 构造及页面事件（约 357–437 行）；SleepEditorView.save（235–245 行）。
- `PersonalGrowthOS/Sleep/SleepFoundation.swift`：SleepRules.timing 以及 save 中字段实际填写时间更新。
- `PersonalGrowthOS/Sleep/SleepReview.swift`：按字段 timing.included 筛选。

### 最短反例

08:00 进入回顾页，页面保留 `reference = 08:00`。从回顾中打开已存在记录，08:01 修改感受或时间并保存。SleepService 正确把被改字段的 FilledAt 更新为 08:01，workspace 也重新加载新数据；但回顾页没有在保存、数据变更或 sheet 关闭时同步刷新 reference。

在父页面没有重新触发 onAppear 的 sheet 路径上，snapshot 仍以 `now = 08:00` 评价 `FilledAt = 08:01`，SleepRules.timing 的 `stamp <= now` 检查返回 unknown。有效评分数、时间样本或间隔因此暂时减少；重新进入页面/回到前台后又可能恢复。数据没有丢失，但“可信回顾”给出错误呈现。

### 独立探针

相同正常时序、没有系统回拨：旧 reference 得到 `unknown / included=false`，更新 reference 后得到 `sameDay / included=true`。同时校验次日补记、较早回忆和未知证据正对照。

该探针证明错误判定链；没有冒充真实 SwiftUI sheet 测试。修复应补真实页面回归，不能依赖某种呈现模式恰好再触发 onAppear。

### 最小修复和验收

让数据快照与评价时钟一致地刷新；在相关保存/数据更新/返回路径明确推进评价时刻。不能简单删掉“未来填写时间应未知”的保护，也不能把所有未来时间硬钳制为现在。

在真实回顾页打开原记录修改评分和时间，保存后不退出回顾、不切后台，立刻断言新的分布、时间样本与来源一致。另保留晚补字段仍排除、只改备注不影响时间字段、真实回拨仍未知的对照。

## R2 · P2：保存一个本来就关闭的目标，会消耗“首次今日生效”语义

### 生产位置

- `PersonalGrowthOS/Sleep/SleepViews.swift`：SleepSettingsView 保存按钮（约 462–472 行）。
- `PersonalGrowthOS/Sleep/SleepFoundation.swift:288–308`：setGoal 无条件插入 nil cutoff 规则。
- 同文件 SleepGoalSemantics.proposedDay：以 rules.isEmpty 区分首次/后续设置。

### 最短反例

没有任何目标的用户进入设置，开关保持默认关闭，点一次“保存就寝目标”。此时 setGoal(nil) 写入今天生效的禁用规则。用户当天再第一次打开目标并保存，rules 已非空，proposedDay 返回明天，而不是承诺的首次今日生效。

以 2026-10-15 为例：未发生上述空操作时首次开启是 10-15；先保存关闭状态后再首次开启变成 10-16。这不涉及旅行、改系统时钟或伪造备份，是普通界面路径。

### 独立探针

读取真实保存分支确认 nil 规则会落库；对原 proposedDay 纯逻辑分别输入空规则和已插入的禁用规则，结果确为 10-15 / 10-16。探针 DTO 不是 SwiftData 持久化运行证明。

### 最小修复和验收

没有目标历史且目标仍关闭时，保存应为无操作，不创建生效规则。界面可以同时禁用无变化保存，但服务层也应保护该语义。

补真实 SleepService 测试：初始关闭保存后仍无规则；首次开启今日生效；已经生效的目标之后修改/关闭仍从下一起床日生效，历史不回写。不要为修复此项删除已有真实禁用历史或变更 Schema。

## R3 · P2：批量排期期间已递送的提醒，会丢失当天防重复证据

### 生产位置

- `PersonalGrowthOS/Todo/TodoReminders.swift:191–218`：add 成功后，等整个批次结束才以 pending 确认；pending 缺失一律改 failed。
- `PersonalGrowthOS/Sleep/SleepReminders.swift`：SleepReminderHistory.confirm / elapsedDays、SleepReminderPlanner.requests。

### 最短反例

首次启用睡眠提醒，08:59:59 成功 add 当天 09:00 请求；其余请求提交或最后 pending 查询期间到了 09:00，请求被系统正常递送。最后读取 pending 时已经不包含当天 ID。

当前代码只把“仍在 pending 且 scheduled”的请求写入睡眠排期历史，随后把所有已成功 add 但不在 pending 的请求改成 failed。结果：实际已递送，但当天没有进入防重复台账。09:00 后把提醒改到 11:00，planner 会再次生成当天请求。

Apple 的 pendingNotificationRequests 返回待递送本地通知，并不代表所有曾成功提交的请求；已经递送的通知有另一组查询 API。因此“已不在 pending”不能单独证明 add 失败。

### 独立探针

以符合该 API 语义的状态注入：所有 add 均成功，批次结束前仅当天请求从 pending 移入已递送状态。执行生产协调器相关末段和原 planner/history，输出：当天状态 failed、elapsed 台账不含当天、11:00 再次生成当天请求。

正对照：排期确认先完成再递送，原逻辑能阻止第二次；真正提前取消的请求仍可在新时刻重新排期。该探针不声称已经在真实 iPhone 收到两次通知。

### 最小修复和验收

分开保存成功提交、确认提前取消、到期/递送及真实提交失败的证据。成功请求的防重复证据不能只依赖批量末尾 pending 命中；也不能为了消除重复而永久锁死真正提前取消的日期。

用实际 TodoReminderCoordinator + 可控客户端补反例：首次排期在最后确认前已递送，后续改晚不再排当天；真实提前取消后仍能按允许规则重排；generation 变化、重启持久化和 Todo/重要日子容量状态均不回归。实现方式可局部调整，不要求新通知框架。

## 未作为本轮新阻塞的问题

### 升级与恢复

新版本采用 V13 追加 SleepRecord / SleepGoalRule，并沿 V12 迁移，未在 diff 中改写旧 Schema 定义。查看了真实旧 V11 fixture 直接升级、用 V12 模型创建旧磁盘库、跨源保护快照、v9 往返及畸形包原子拒绝测试源码。未发现新的确认数据丢失问题；这些源码和报告不替代本次未运行的 Xcode/私人库升级门禁。

### Safari FAIL

报告归因为 unsigned Share Extension 缺 App Group entitlement。当前 diff 没有修改 ShareExtension/SharedCapture 的生产源码，工程变更是新文件注册而非签名设置。这个环境解释有合理性，但本次未拿到报告所指 system log、签名 entitlement 和截图，不能把根因当作已由本次独立重证，更不能写成当前候选 Safari PASS。

修复上述三项后，签名候选仍应补一次实际 Safari 分享→入箱→前台导入→来源/内容保存，才关闭当前候选的系统分享设备项。旧 SHA 的成功证据不能替代这一项。

### 验证报告口径

保留全量 Unit 两轮、集中 UI 15/17、各次补验和 Safari 剩余 FAIL 的原始区别，不拼成一次全绿。没有新增证据时，CI/签名/系统通知递送/桌面 Widget/Photos/VoiceOver/私人库继续 NOT_RUN 或 Owner Gate。

## 建议修复批次

只修 R1–R3，并沿当前 PR #11 普通提交。先对真实生产路径补反例，再做限定修复与独立复审。优先跑受影响睡眠逻辑/服务/回顾 UI、共享通知与既有取消/交错回归；这三个已定位问题本身不要求改 Schema，也不应因此重新打开全部重要日子开发。只有实际修复范围扩大时才按风险补更广回归。

在三个 P2 关闭以前，不建议沿“全部代码层面通过”的结论直接发布。关闭后继续原有两功能组合真机测试，无需再启动新功能。

## 固定代码与 API 来源

- [固定产品源码](https://github.com/yoCruzer/PersonalGrowthOS/tree/138616cd0970b0f4fba9d0c7d7d44f6ca7d30b53)
- [SleepViews.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/138616cd0970b0f4fba9d0c7d7d44f6ca7d30b53/PersonalGrowthOS/Sleep/SleepViews.swift)
- [SleepFoundation.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/138616cd0970b0f4fba9d0c7d7d44f6ca7d30b53/PersonalGrowthOS/Sleep/SleepFoundation.swift)
- [SleepReview.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/138616cd0970b0f4fba9d0c7d7d44f6ca7d30b53/PersonalGrowthOS/Sleep/SleepReview.swift)
- [SleepReminders.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/138616cd0970b0f4fba9d0c7d7d44f6ca7d30b53/PersonalGrowthOS/Sleep/SleepReminders.swift)
- [TodoReminders.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/138616cd0970b0f4fba9d0c7d7d44f6ca7d30b53/PersonalGrowthOS/Todo/TodoReminders.swift)
- [Apple pending notification API](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getpendingnotificationrequests(completionhandler:))
- [Apple notification center: pending versus delivered](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)

探针执行：`swift review_probe.swift`。`probe_output.txt` 是本次实际运行输出；所有输入为合成数据。
