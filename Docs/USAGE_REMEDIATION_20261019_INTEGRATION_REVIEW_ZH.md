# PR #13 集成边界独立复核

| 项目 | 内容 |
| --- | --- |
| 日期 | 2026-10-19，Asia/Shanghai |
| 已审产品／测试 | c55dc10fde79f1fe4dec18b03195119c2049830f |
| 已审交付／远端 head | c1fe56477f2573930a65a95c46d4b7ab7296d6af |
| 前轮 Goal | 3dad3b04e3ff703c2e799899035285f64a5976a4 |
| PR／分支 | [PR #13](https://github.com/yoCruzer/PersonalGrowthOS/pull/13)；codex/usage-remediation-20261017 |
| base | codex/time-investment-v1；5a70f0110b151f8a45ac7c33d3f443823b1cff24 |
| 本轮结论 | LOCAL_REVIEW_FIX_REQUIRED；4 项 confirmed P2、1 项 confirmed P3 测试收尾，未发现 P0/P1 |
| 执行入口 | [集成边界修复 Goal](USAGE_REMEDIATION_20261019_INTEGRATION_FIX_GOAL_ZH.md) |

## 1. 审查方式和证据边界

本报告记录 ChatGPT 对实际远端代码和测试正文的独立复核，按提醒、持久化与异步、事实与界面三个领域并行，主审再交叉反证。审查者未编写 c55 的产品实现。前轮开发者及其 reviewer 的自述作为待核对材料，不直接作为本轮结论。

核对 Goal→交付共 3 个提交、38 个变更文件；本次用于审查的 130 个本地文件全部与 c1fe564 的 Git blob 一致，tree 未截断。核对 c55 相对完整 Unit 候选 00b65b70d988ef26455d719ccf35eda61233120a 只调整三个 UI 测试文件，生产及 Unit 源码未变化。PR 在审查结束和本文准备时仍为 OPEN Draft，head/base 未变化。

审查环境为 Linux。实际阅读生产源码、相关未改调用者、测试正文、已入库的执行矩阵和机器摘要；没有运行 Xcode、SwiftData、模拟器或真机，没有读取开发机 /tmp/pgos-pr13-system-evidence 中的原始 xcresult、录屏、图片和实包。报告中的源码反例不冒称本环境原生复现。日期反例另用 Python zoneinfo 按测试原公式独立复算，见第 7 节。

旧记录的完整 Unit 557=556 PASS/0 FAIL/1 SKIP，以及 UI 首轮 18 PASS/3 FAIL、后续 4/4 PASS 的提交归属可核对；原始运行真实性仍以开发机证据为准。这些计数不能关闭未被对应测试覆盖的集成路径。

本报告保持为固定输入版本的审查记录。后续发现反证、完成修复或补验，追加处置和新 SHA；不改写这里的原始发现、优先级或“尚未原生运行”的事实。

## 2. 本轮问题登记

| 编号 | 级别／状态 | 实际缺口 | 对应前轮范围 |
| --- | --- | --- | --- |
| IR-01 | P2 / OPEN | 跨区 stopped／unresolved 无修改仍发事件，AppShell 反馈持续自触发对账 | SR-01 |
| IR-02 | P2 / OPEN | 局部旧策略隔离只清理 Notification，已有未来 Alarm 保留旧区计划 | SR-01、双渠道取消 |
| IR-03 | P2 / OPEN | Settings 关闭重建后的旧 owner 可在偏好回原值时覆盖新设置 | SR-05 |
| IR-04 | P2 / OPEN | 活动重命名遇 busy 后关闭，重开时覆盖失败名称 | SR-04 显式命令失败输入 |
| IR-05 | P3 / OPEN | BV-01 和 Weekly 新时间夹具依赖宿主时钟，合法条件下自行失败 | 测试可重复性；既有 CR-06 经验 |
| V-01 | REQUIRED_BOUNDED_VALIDATION / NOT_RUN | live raw capture 的 SQLite 写事务与 Todo 主执行器保存竞争；原生影响未确认 | BV-02 新增导出入口 |
| O-01 | UNCONFIRMED / 非阻断观察 | 已打开 Weekly 的选周身份在父视图重建时是否保持 | SR-03 原生视图寿命 |

IR-01～04 均有合法起点和生产源码链，不能以 D1–D4 未运行为由推迟本地处理。IR-05 是测试问题，不将其重命名为体重或 Weekly 产品统计错误。V-01 的写竞争已由源码确认，但“主线程会卡住”的影响尚未证实；O-01 不计入 confirmed 数量。

## 3. IR-01：无变化发布形成持续对账反馈

### 合法起点和完整链

当前版本创建带提醒的重复待办→停止系列→更换时区→前台或启动对账，就能触发，不需要旧库。停止只改变系列停止状态，任务仍 open，原 remindAt 和 reminderTimeZoneID 保留。

TodoFoundation.refreshRepeatingReminderTimes 659–662 将这类任务选入候选；663 进入 transaction 后，666 才跳过 stopped。对 active 且无法恢复旧 offset 的任务，668 捕获 invalidReminderOffset、放入 unresolved 后跳过，同样保留原跨区字段。

transaction 301–302 即使零修改也 save，并同步 post .todoTasksChanged。AppShell 217–219 收到同容器事件又启动 reconcile Task。TodoReminders 160 先增加 generation，162 才发现已有 running 并返回；当前轮在 214 await permission 后因代次变化 continue，下一轮仍遇到同一候选并再次发布事件。

### 影响和限定

对账不能自然静默收敛。正常异步挂起可使每轮失效，健康 Todo／ImportantDay／Sleep 的当前安排迟迟无法完成；整个循环持 NotificationMutationGate，daily／weekly 设置可能长期等待。即使某轮系统调用立即返回并释放 gate，该轮自己发布的 Task 仍可启动下一轮无变化对账。这里确认持续自触发，不宣称所有设备必然同步死锁整个 UI。

### 为什么已有测试没有覆盖

ImportExportRecoveryTests 2880–2896、2966–3005 直接调用 coordinator，未挂接 AppShell 的事件反馈；notification stub 通常立即返回。单次 coordinator 成功不证明正式根页面的事件循环能收敛。

### 最小关闭要求

无事实变化不发送事实变更事件；stopped 在需写入候选前排除，unresolved 仍能返回局部状态。混合健康任务第一轮真实跨区更新后，下一轮应无变化退出。接实际生产事件桥及可控 async barrier，验证发布／对账次数有界、健康三类别完成和 daily／weekly gate waiter 能继续。保留真实变化通知和回滚，不改写 stopped 历史字段、猜 offset 或禁用全局事件来绕过问题。

源码：[刷新](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/Todo/TodoFoundation.swift#L655-L688)、[事务](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/Todo/TodoFoundation.swift#L290-L303)、[AppShell 订阅](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/AppShell.swift#L217-L226)、[对账代次](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/Todo/TodoReminders.swift#L159-L215)。

## 4. IR-02：待纠正规则遗漏存量未来 Alarm

### 合法起点

原始 V11 nil offset 系列升级旧 f1；用户选择 Alarm，对当前期连续两次覆盖提醒，最终未来 Alarm 已 accepted。旧 f1 rescheduleOwnedReminder 419–433 尚无后来的 preserve 防线，允许此合法事件链。升级当前版本并换时区，保守 offset 恢复判为不可推导。当前 fix2OldF1Override 夹具复刻了该旧行为，但 2733–2735 强制使用 Notification。

### 当前链和实际结果

TodoAlarmReminders.targets 169–178 仍认为目标 active，fireAt 保留原值；retireObsoleteRequests 251–268 判断 accepted Alarm matches、未来标题未变，不取消。刷新将其列为 unresolved，TodoReminders 183 不纳入新计划；rebalanceNotifications 293–308 只处理 Notification。311 将 unresolved 放入 blocked，intent reconcile 323/340 直接跳过，314–320 最终显示 legacyRuleNeedsCorrection。

因此旧区未来 Alarm 仍在系统 pending 中，没有收到取消；界面只提示规则需要纠正。此问题独立于 IR-01，单次 coordinator 也存在。

### 缺失证据和关闭要求

现有 2978–2995 测试证明 Notification 的已有请求、取消失败、确认后局部状态，但没有实际 Alarm channel，也未把同一个 Alarm client 贯穿两次调度。应以旧真实行为产生合法两渠道数据，实际 scheduler 建立 accepted future 后再隔离，验证取消失败→持久待确认→冷重开→确认不存在→明确纠正规则→新计划恢复。

同样处理两渠道存量未来请求；取消未确认时不能用局部规则提示盖掉 cancellationPending。系统 Stop／已 retired 不得因普通刷新、元数据编辑或修复被复活；正常已到点仍 ringing 的 Alarm 保持原保护。本项只确认 fireAt>now 的未来旧请求，不要求无条件取消 Alarm。现有桩和真实调度器足以验证调用与持久状态，不依赖原生 AlarmKit 正向。

源码：[匹配清理](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/Todo/TodoAlarmReminders.swift#L251-L340)、[局部显示](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/Todo/TodoReminders.swift#L310-L320)、[已有夹具](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOSTests/ImportExportRecoveryTests.swift#L2722-L2739)、[当前隔离测试](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOSTests/ImportExportRecoveryTests.swift#L2966-L3005)。

## 5. IR-03：设置页重建后旧结果所有权失效

SR-05 同一个 ReminderSettingsUpdate 内已经统一成功、普通错误和取消出口，并检查 token／取消／当前偏好。这部分认可。

但 AppShell 256–261 将设置作为可关闭的 sheet；1037–1038 的 updater 是 MediaStorageView 自己的 State。Done 1220 和交互关闭只受 transfer 限制，1325–1328 只取消 transfer，不失效 reminder owner。ReminderFoundation 165–169 的不结构化 Task 捕获旧 self，任务可继续；新 sheet 使用新的 owner，无法更新旧 generation。

合法顺序：A 开启并已进入 addRepeating await→关闭 Settings→重开→B 关闭再开启、参数回到 A 的值→A 普通错误返回。旧 token 仍匹配，isCurrent 只比较 enabled／minutes／weekday，在值回原状后又成立，旧 failure 写 AppStorage=false。用户更新的意图被旧请求覆盖。无需假定任务乱序开始，A 已持 gate、B 排队即可。

这是源码与正常 SwiftUI 生命周期合同下的反例，未冒称本环境原生捕获。Apple 说明 State 存储跟随 view identity/lifetime，视图移除后重建初始存储，区别于同一 view 的普通 body 重算：[Demystify SwiftUI](https://developer.apple.com/videos/play/wwdc2021/10022/)。

ImportantDayReminderTests 206–253 虽经生产 updater→scheduler→barrier，但只使用一个 owner。修复需稳定的 per-channel 所有权跨越设置页生命周期，或等效的共享请求票据；参数相同不代表用户意图相同。验证双 owner／真实重开、共享偏好及 gate、旧普通错／成功／取消、B 真失败和明确 off。没有新 B 时 A 的合法完成也必须保留；仅 onDisappear cancel 不能留下“偏好已开、请求被取消未完成”。

源码：[owner](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/App/ReminderFoundation.swift#L152-L174)、[页面 State](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/AppShell.swift#L1027-L1038)、[旧结果写入](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/AppShell.swift#L1357-L1378)、[测试](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOSTests/ImportantDayReminderTests.swift#L206-L253)。

## 6. IR-04：活动重命名失败输入不可重试

InvestmentHubView 456 在 run 捕获保存错误后仍清 editingActivity，关闭 alert；454 的呈现绑定也会在关闭时清它。471 保留错误，但下一次 406 进入编辑时无条件 rename=activity.name，失败名称被正式旧值覆盖。新 busy 文案声称输入已保留，但没有可达的输入重试路径。

自然竞争入口：打开活动重命名→切去 Photos/Safari 分享合法含图内容→返回前台→AppShell 206–208、379–384 自动 importShares。ExternalCaptureImporter.run 164–166 的 worker 持 StorePublication 执行整个 scan/consume，包含真实附件复制和保存。用户此时保存名称，InvestmentService.updateActivity 的 transaction 遇主线程 try-lock 返回 busy，正式名称未变；失败后关闭／重开产生上述丢稿。不需要假设用户能在导出设置 sheet 背后编辑。

重命名 alert 的旧失败清理在前版已存在；本轮把正常锁竞争改为立即 busy，却没有核对该旧调用者失败后重入。属于旧 UI 缺口被新错误路径暴露。其它 createActivity、start、正式 editor 保存的成功清理位于 try 成功后，本次未确认相同遗漏。

修复应以活动 ID 和名称草稿为明确所有者，失败后有可达编辑／重试，成功或明确取消才释放。系统 alert 有自身关闭语义，不能只移动一条清 nil，也不要用任意延迟重新弹出。采用已有可重试 sheet 模式或等效结构即可。

验收：真实 importer 持锁 barrier→真实重命名输入 A→B 并提交→MainActor 可响应、正式仍 A、草稿 B 可见且可重试→释放后成功仅一次；普通错误、明确取消、成功关闭及另一活动不串稿。只测 service 抛 busy 不够。

源码：[编辑入口](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L402-L407)、[保存和清理](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/TimeInvestment/InvestmentViews.swift#L454-L471)、[自动导入](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/AppShell.swift#L201-L210)、[共享发布权](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/ExternalCapture/ExternalCaptureImport.swift#L152-L168)。

## 7. IR-05：两组新增时间夹具不稳定

### BV-01 的绝对 24 小时不等于自然日

AppCompositionTests 436–440 使用 Date()/TimeZone.current，并按 index*86400 秒回退，随后 474–475 硬断言 10001／10000 个记录日。SleepRecord.wakeDay 还有唯一约束，夹具可能出现重复夜。

独立 Python zoneinfo 复算同一公式：

| 地区／2026-10-19 起点 | 10000 个时刻的不同自然日数 |
| --- | ---: |
| America/Los_Angeles 00:30 | 9973 |
| America/Los_Angeles 10:30 | 10000 |
| Asia/Shanghai 00:30 | 10000 |

第一组首次相邻重复日是 2025-11-02。下列计算只验证夹具日期数学，不冒称运行过 SwiftData：

~~~python
from datetime import datetime
from zoneinfo import ZoneInfo
zone = ZoneInfo("America/Los_Angeles")
stamp = datetime(2026, 10, 19, 0, 30, tzinfo=zone).timestamp()
days = [datetime.fromtimestamp(stamp - i * 86400, zone).date()
        for i in range(10000)]
assert len(set(days)) == 9973
~~~

### Weekly 的相对实时时钟前提会过期

PersonalGrowthOSApp 60–74 将当前三事实设为 now-60s，未来设为 now+120s；AppLaunchSmokeTests 3131–3153 固定要求当前周 1 条／1 次／70kg，未来不存在。周一 2026-10-19 00:00:30 启动时，当前事实实为周日 23:59:30，属于上周；测试运行拖过 120 秒后，未来事实又可被实时截止纳入。这是夹具与断言冲突，不是 Weekly 产品错算。

IR-05 合成一个 P3。使用固定可注入的 clock/calendar/timezone，按自然日建立明确基数，生成和真实 reader 共用受控业务时钟；保留 Service→事件→真实挂载 reader 和真实 UI。验证 LA 午夜/DST、周一首分钟及未来时钟推进的代表反例即可，不改主机日期、不弱化断言、不重写产品聚合。这不推翻之前在其他宿主条件下得到的 actualFetches=0 或已记录 PASS。

源码：[BV-01 测试](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOSTests/AppCompositionTests.swift#L432-L475)、[Weekly 夹具](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/PersonalGrowthOSApp.swift#L60-L74)、[UI 断言](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOSUITests/AppLaunchSmokeTests.swift#L3131-L3153)。

## 8. V-01：live raw capture 与 Todo 写入的限定验证

新增 exportRetainedQuantityData 192–205 在运行中 App 调 StartupRetainedData.capture。AppContainer 248–266 使用 SQLite BEGIN IMMEDIATE 排斥其它写者；314–377 在事务内做文件签名、逐表 fingerprint、Store 拷贝和多轮校验。TodoFoundation.transaction 及 TodoAlarmReminders.write 198–208 的 MainActor SwiftData.save 不经过 StorePublication。

自然独立入口是 AppShell 221–226 日切／significantTimeChange，或 TodoReminders 132–136 的 Alarm 观察；合法切区提醒刷新、accepted 请求消失的设备 journal 等会真实保存。单独 .active 链不能作绕锁论据，因为 208–209 先 await importShares，而 importer 自己等待 StorePublication。

已确认结构上的写竞争；是否立即 busy 错误、内部等待及其响应影响，需真实 SwiftData 验证。SQLite busy handler/timeout 是连接行为，不能从源码推导所有设备固定等待时间：[busy handler](https://sqlite.org/c3ref/busy_handler.html)、[busy timeout](https://sqlite.org/c3ref/busy_timeout.html)。

限定实验：真实 raw capture 已取得 writer transaction 后设 barrier，触发实际生产对账和实际 SwiftData 写入，再投递 MainActor probe；以独立 fail-safe 有界释放。探针先于释放则继续核对快速错误、原数据、状态和释放后恢复；探针只能在释放/内部超时后执行则形成 confirmed 阻塞，并同批最小修复后补验。测试不能换成手写 SQLite 保存或只测普通 export 的 NSLock。

必须观察到 raw writer 事务仍持有时，生产保存入口已尝试实际 SwiftData.save。probe 由独立执行器投递，不以等待 save/reconcile 完成为前置条件；记录写入尝试、probe、锁释放及保存结果的因果顺序。前置权限查询尚未完成或保存尚未尝试时的 probe 不能证明安全；先等保存返回才发 probe 也不能证明阻塞。未命中实际竞争保存，不登记 VERIFIED_SAFE/DISPROVED。

本项不是新备份工程，也不预设要改并发架构。新非有限数拒绝、旧 raw 原值保留与非普通备份语义已认可，必须保持。已有一条记录的 raw 提取/重开测试不覆盖该并发关系。最终必须有 VERIFIED_SAFE／DISPROVED（对应具体影响假设）／CONFIRMED_AND_FIXED，或说明具体能力缺失的 VALIDATION_BLOCKED；不能没有运行就填安全。

源码：[入口](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/ImportExport/ImportExportService.swift#L192-L205)、[冻结](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/App/AppContainer.swift#L245-L266)、[保存](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOS/Todo/TodoAlarmReminders.swift#L198-L211)、[已有 raw 验证](https://github.com/yoCruzer/PersonalGrowthOS/blob/c55dc10fde79f1fe4dec18b03195119c2049830f/PersonalGrowthOSTests/ImportExportRecoveryTests.swift#L2928-L2960)。

## 9. 已认可修复与未确认观察

| 前轮项 | 本轮认可范围和保护 |
| --- | --- |
| SR-01 | Service 的旧 nil Stop/delete/default Edit/list 终止权威、真实 V11/ZIP/回滚及显式 offset 主体；IR-01/02使完整集成仍未关闭 |
| SR-02 | 编辑使用可往返 Double 文本；1000/72.345、三 locale、日期-only、真实磁盘重开；不全库舍入 |
| SR-03 | Weekly Entry/Habit/Weight 同一实际 asOf，Habit 保存业务日，历史周后半段，派生 TopTags/RecentEntries；测试 IR-05另修 |
| SR-04 | MainThread try-lock、worker 等待后自动 checkpoint、重新取权威 revision、pause/finish 不被覆盖；显式重命名例外 IR-04 |
| SR-05 | 同 owner 的 late success/ordinary error/cancellation 统一出口有效；跨 sheet 例外 IR-03 |
| SR-06 | 正式保存入口调用 Workspace，成功按身份移除 editor、失败/其它草稿保持、持久 saved operation 保留 |
| SR-07 | daily once/multiple/weekly/monthly 共用结构，反馈收起不改事实，历史截止文案；不强制各行同高 |
| BV-01 | 只跳过确知无关的 Operation/Session；未知、混合、正式实体和失效通知保守刷新；真实读数链保护 |
| BV-02 | 新非有限值在写前拒绝，旧异常阻止普通备份且 raw 保留ID/bitPattern/unit/result；V-01补新入口并发 |

Habit analytics 的既有日粒度进度、Weekly/QuietWins 的实际时刻截止和缺元数据回退边界并非完全相同。本轮不把已有差异扩张成重写习惯引擎；排队 checkpoint 保存最后 clock supplier，等待结束重新采样，不冒称冻结了请求时刻。

O-01：WeeklyReviewViews 38–46 的 weekIdentifier 为普通 let；Today AppShell 681–688 默认构造 WeeklyReviewView，594–596 的跨日/时间变化/前台更新父状态。如果活动 destination 因此重建，选周和未保存草稿可能受影响。但这里依赖实际 NavigationLink 生命周期，尚无原生反例。作为非阻断观察原样保留；可随 IR-05 已需 UI 检查顺带观察，不要求单独大矩阵，不先改产品。若产生明确证据，则同批处理范围内缺陷；未证实允许继续 UNCONFIRMED，不以它单独拒绝放行。

## 10. 反复修复的本轮经验

现有测试已经跨入真实 Service、磁盘和部分挂载 UI；仍遗漏的是“下一层消费者”：单次 coordinator 后的事件回路、单渠道之外的存量 Alarm、单 owner 之外的页面寿命、service 拒绝之后重新进入编辑的输入状态，以及测试自己的时间边界。

IR-01/02 是本轮局部隔离接入后产生的组合缺口；IR-03 是新 owner 生命周期范围不足；IR-04 是旧 UI 失败落点被新 busy 契约暴露；IR-05 是新增夹具重犯实时时钟依赖。不能把全部归为真机或 SDK 限制，也不能据此否认已经有效的测试与修复。

下轮完成证明必须包括：生产入口→共享服务→事件/异步结果→所有相关消费者→关闭/重开/恢复后的可操作状态；逐项写合法起点、最新意图/终态权威、失败落点及有区分力证据。按故障类检查相邻分支，而不是围绕问题编号只补 helper。独立 reviewer 应先提出跨边界反例，再看实现者关闭表。

当前本地停点由本报告和新 Goal 更新为 LOCAL_REVIEW_FIX_REQUIRED。历史审查原文、失败与补验全部保留。D1–D4 NOT_PASSED、AlarmKit 正向 NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间 SKIP/NOT_RUN、远端 CI NOT_RUN 仍是既有状态，不由本次源码审查改写。
