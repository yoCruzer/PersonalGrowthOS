# PR #13 终态补修后的独立复核（744e772）

## 固定对象与证据层级

- 已审产品/测试：`744e7729f103549184574e99e311ce5c380a4a16`。
- 已审交付：`d04fbf7f39a6ce77e995202118a0ca78f0d0ccf6`。
- 前一 Goal：`6430a8570ce2d3528c37d491c1252f97066e8da9`。
- 唯一 OPEN Draft PR #13；head 分支 `codex/usage-remediation-20261017`；base `codex/time-investment-v1` / `5a70f0110b151f8a45ac7c33d3f443823b1cff24`。
- 本轮检查固定源文件、旧 f1 合法数据路径、新测试正文、AppShell 启动/前台/设置移除接线、提醒代次与系统账本、睡眠延后观察和已提交执行记录。相对 Goal 为3个提交/16文件；最后产品实现fcd1→744仅AppCompositionTests窗口/截图5增2删，744→d04只有5份Markdown和1份JSON。
- 审查环境为 Linux/Swift 6.2.1；没有运行 Xcode/SwiftData/SwiftUI/原生通知或读取开发机原始xcresult、图片和实包。开发端573 PASS/1 SKIP、UI3/3等保留为其版本化证据，不转写为本次复跑。
- 本报告由外部主审对相关生产链及相反路径作二次核对；没有把开发端独立reviewer的原生读取经历转述为本次实际执行。

## 结论与唯一编号

两项源码确认的P2与一项P3收尾，暂不支持本地READY：

| 编号 | 级别 | 归属 | 结论 |
|---|---|---|---|
| TC-01 | P2 | RR-01的已完成/已取消来源入口 | 当前open实例的同值纠正已修；从终止祖先期次应用未来规则，仍可能不恢复已隔离的开放后继。 |
| TC-02 | P2 | IC-02跨进程清理状态 | 待确认清理仅存Scope内存；偏好off已保存，冷启动既不恢复该状态也不对账该固定请求。 |
| TC-03 | P3 | IC-02成功重试反馈 | 清理确认成功后cleanupPending清除，但旧“尚未确认”文案保留且重试入口消失。 |

TC-02与TC-03属于同一小型状态收尾，可一起修，不扩展业务范围。此前RR-02原始写竞争、二次busy与观察回拨保护可在代码及测试设计层面关闭；不再要求对原RR-02另做一轮相同验证。O-01仍为非阻断UNCONFIRMED。

## TC-01：操作来源已结束，不等于其开放后继无需恢复

### 源码链

1. [当前TodoFoundation](https://github.com/yoCruzer/PersonalGrowthOS/blob/744e7729f103549184574e99e311ce5c380a4a16/PersonalGrowthOS/Todo/TodoFoundation.swift#L538-L591)：`correctingPolicy`被`task.state == .open`限定，随后作为`applyTemplate(... reactivating:)`的入参。若来源A已completed/canceled，所有受影响开放后继都拿到false。
2. 同文件`applyTemplate`只在reactivating或后继fireAt改变时强制换代；渠道与instanceOverride也不变时，`setIntent`保留旧代次。
3. [当前编辑器](https://github.com/yoCruzer/PersonalGrowthOS/blob/744e7729f103549184574e99e311ce5c380a4a16/PersonalGrowthOS/Todo/TodoViews.swift#L334-L356)：仍允许从非open重复期次应用未来；保存后显式找`affectedOpenSuccessor`展示其提醒结果。因此非open来源不是不支持的UI输入。
4. [设备调度](https://github.com/yoCruzer/PersonalGrowthOS/blob/744e7729f103549184574e99e311ce5c380a4a16/PersonalGrowthOS/Todo/TodoAlarmReminders.swift#L254-L406)：隔离保留retired；同generation且系统已无请求的retired不会因普通刷新删除，后续排程直接stopped。
5. [旧f1生成后继](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/Todo/TodoFoundation.swift#L554-L612)不固化nil偏移；[旧deleteList](https://github.com/yoCruzer/PersonalGrowthOS/blob/f1b52b58fd11c41f508ec665d583827879ffa202/PersonalGrowthOS/Todo/TodoFoundation.swift)会更新系列updatedAt并保持nil。此起点是旧产品合法操作，不是损坏数据。

### 最小合法反例

真实V11的每日08:00、offset=nil系列，含当前根A与清单。经旧f1完成或跳过A生成开放B；旧deleteList解除清单但未固化offset，并使系列updatedAt晚于createdAt。为B安排未来请求，两渠道分别验证（Alarm可通过旧普通编辑选择渠道且不改变时刻/未来规则）。

从Asia/Shanghai切为Asia/Hong_Kong，在例示2026-10-20两者同为UTC+08:00、identifier不同。当前refresh会检测切区且无法推导旧规则，将B隔离并取消为retired。用户从已完成A的真实编辑器勾选应用未来，保持原时间、分钟、渠道和模板值不变。

规则offset会成功写成0，B模板应用得到与原来相同的fireAt；因为A不是open，correctingPolicy=false，B代次仍为旧G，后续仍stopped/native0。A本身不应复活，但B应完成这次明确的规则恢复。

选择等偏移时区是为了让`oldReminder != newReminder`不能偶然替代正确的意图识别；不是要求任意时区变化都触发。不同偏移时区可能因时间改变而自动换代，不能作为反证。亦可在隔离后返回原时区再执行同值确认，核对同一不变量。

### 现有测试的缺口与严重度

[testTerminalRR01OldOrdinaryEditSameValueCorrectionCreatesRealRequest](https://github.com/yoCruzer/PersonalGrowthOS/blob/744e7729f103549184574e99e311ce5c380a4a16/PersonalGrowthOSTests/ImportExportRecoveryTests.swift#L3373-L3437)从正在open的同一任务打开实际编辑器；另一RR01回滚/清单邻接方法仍从同一open任务纠正。它们有效关闭了上一轮原反例，但没有覆盖非open来源加open后继。

影响是未来开放期次缺提醒，不是历史任务数据丢失。用户改从B纠正可绕过，但已有“应用未来”入口不能保存规则后仍让B停留旧代次。源码路径确认；新的SwiftData/挂载UI红例未在本环境执行。

## TC-02：待确认清理不能随着App根状态销毁而消失

### 源码链与触发

[ReminderSettingsUpdate.Scope](https://github.com/yoCruzer/PersonalGrowthOS/blob/744e7729f103549184574e99e311ce5c380a4a16/PersonalGrowthOS/App/ReminderFoundation.swift)仅在内存保存failureMessage与cleanupPending；[MediaStorageView](https://github.com/yoCruzer/PersonalGrowthOS/blob/744e7729f103549184574e99e311ce5c380a4a16/PersonalGrowthOS/AppShell.swift)在当前失败时无论清理是否确认都将AppStorage enabled设为false。

合法已有08:00→改09:00失败→两次remove后仍读到旧native请求，得到off/cleanupPending=true/可重试。若用户离开且App进程结束，随后冷启动：off偏好保留，Scope全新构造为false/nil；原请求假如仍存在，就失去清理责任和可见提示。

[AppShell根和启动](https://github.com/yoCruzer/PersonalGrowthOS/blob/744e7729f103549184574e99e311ce5c380a4a16/PersonalGrowthOS/AppShell.swift#L40-L223)只新建Scope、处理Todo/Sleep/ImportantDay协调，并未恢复每日/每周的清理；设置重新挂载task仅查权限/大小，onChange不按初值自动执行；Todo协调对这两个固定identifier保留且不会删除。

这不是声称“每次未确认都永远删不掉”，而是要求在既有测试合同允许的“native仍存在”分支能够恢复。Apple说明本地通知由系统独立于App执行，重复请求会再次安排；UserDefaults可跨启动保留。因此不能依靠App退出自动清掉请求。

官方依据：[Local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)、[Settings](https://developer.apple.com/documentation/foundation/settings)。

### 测试缺口

[当前失败矩阵](https://github.com/yoCruzer/PersonalGrowthOS/blob/744e7729f103549184574e99e311ce5c380a4a16/PersonalGrowthOSTests/ImportantDayReminderTests.swift#L320-L389)只在同一Scope上重试；[实际设置关闭重开](https://github.com/yoCruzer/PersonalGrowthOS/blob/744e7729f103549184574e99e311ce5c380a4a16/PersonalGrowthOSTests/AppCompositionTests.swift#L560-L614)保留同一个根intents，且清理成功。sheet重开不能证明进程重建。源码确认恢复缺口，实际iOS冷启动反例仍由Codex用合成客户端与真实根挂载执行。

修复不必增加SwiftData schema：可从持久off偏好与两个固定请求ID在启动/前台安全重建清理责任，也可保存最小设备本地待办状态。须持续保护后来的B，不能用无票据的启动清理误删最新请求；也不得清理Todo、Sleep、ImportantDay或未知ID。

## TC-03：重试成功后的错误文本仍声称未确认

同一Scope中先得到cleanupPending=true和“Reminder removal is not confirmed. Please try again.”；随后真实remove确认成功并返回`.removed`。`submit`成功分支清cleanupPending，但只有value不为removed才清failureMessage。结果是native0/cleanupPending=false，但仍显示未确认文案；UI因cleanupPending=false隐藏Try Again。

这是独立的可确定文本状态错误，即使不重启App也发生。可保留“之前更新失败”的历史说明，但不得再声称当前清理尚未确认。现有重试测试只断言pending和cleanupPending，未检查文本及最终按钮。

### 本环境实际运行的有限探针

运行了从当前ReminderSettingsUpdate复制的方法和字段的Swift状态探针。Linux Observation库首次链接失败；第二次明确移除`@Observable` instrumentation并提供英文localization passthrough，未改变submit的分支/赋值。没有渲染、SwiftData、系统通知或iOS进程重启测试。

实际输出：
```
after_unconfirmed_failure: enabled=false cleanupPending=true message=Reminder removal is not confirmed. Please try again.
new_root_scope: cleanupPending=false message=nil
after_confirmed_retry: cleanupPending=false message=Reminder removal is not confirmed. Please try again.
ui_retry_visible_from_source_condition=false
scheduled_positive_control: message=nil
calendar_control Asia/Shanghai: offset=28800
calendar_control Asia/Hong_Kong: offset=28800
```
该结果直接支持TC-03的状态变迁及TC-02的默认字段事实，不冒充完整原生故障复现；时区输出仅验证TC-01的等偏移前提。

## 已关闭部分与停止扩大范围

- RR-01原open来源的同值恢复、取消未确认/回滚/冷重开/幂等保护有真实生产测试正文支持；只补TC-01。
- RR-02加入同store互斥、合并等待、二次busy重试；仅ID/观测时间fence与setGoal先flush阻止已观察事实被回拨覆写。其现有反例和相反操作设计可接受，不重开。
- IC-02旧失败在真实sheet移除后完成清理、query内新B保护均已接入；只补冷启动和确认后的反馈终态。
- IR-01事件有限收敛、两渠道隔离、重命名失败草稿、日期夹具、F5读取、原值raw包和既有数据迁移保持保护。没有新的代码依据去重做A–D或增加新的未确认观察。

下一次限定执行见 [TERMINAL_RECHECK_FIX_GOAL](USAGE_REMEDIATION_20261019_TERMINAL_RECHECK_FIX_GOAL_ZH.md)。原19轮与38轮历史、黑图局限、D1–D4和AlarmKit/Share/Safari/低空间/CI状态保持。此报告和配套Goal是文档准备，不是新产品修复PASS。
