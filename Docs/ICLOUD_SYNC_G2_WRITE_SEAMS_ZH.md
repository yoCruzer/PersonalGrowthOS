# G2 写入接缝与基线准备

2026-11-07。基线产品 `96f72339a1a3082c43018e06d6115dd93df1df97`，接续 G1 `e57fe35`。本表来自现有代码，不代表已经接上 outbox。正式 App 仍 V16/v12、CloudKit `.none`；不改历史 schema，不开启自动镜像。

## 接入顺序和事务边界

每个写入口需要在其实际保存业务事实的同一个 `ModelContext` 中插入版本及 outbox，再进行一次显式保存。不能在保存后的 Notification 或 UI 回调补队列。网络/asset上传在事务外；上传ACK只确认已发mutation。新 schema 应追加版本，不修改V16节点。没有正式容器P1/P2证据前，不进行39实体的大规模接入。

| 接缝 | 现有入口 | 后续同事务范围/特别约束 |
| --- | --- | --- |
| Entry与原图 | `PersistenceFoundation.swift` 的Entry仓储、创建/编辑/删除服务 | Entry、ImageMetadata、关系和删除意图；图片持久staging/lease必须先于提交，不能在GC中删唯一待传副本 |
| Tag与ObjectLink | `OrganizationFoundation.swift` | normalized别名与typed endpoint；关系只在当前有效对象闭合后发布 |
| Habit | `HabitFoundation.swift` | Habit/Configuration/PlanRevision/LifecycleEvent；bootstrap是本机升级来源，不能误生成新的用户事实 |
| HabitLog | `PersistenceFoundation.swift`、`HabitFoundation.swift` | Log、LocalDay metadata、可选Entry及关联同提交；once/day业务键与multiple/day独立事实分开 |
| Goal | `GoalFoundation.swift` | Goal状态与LifecycleEvent一起提交 |
| Weight与BodyReference | `WeightFoundation.swift` | 数值/日期原精度；设置稳定单例，不按日期擅自合并体重 |
| WeeklyReview | `WeeklyReviewFoundation.swift` | 自然周键与并发文字版本；冲突预览不当成已确认统计 |
| EntryPin/FollowUp | `PersistenceFoundation.swift` | 保持附属身份，不改父Entry技术时间；pin只限制展示前三项 |
| 分享收件箱 | `ExternalCaptureImport.swift` | Entry/原图/来源/CaptureImportReceipt同save；receipt删除后仍防重放复活；扩展只投递本地inbox |
| Todo | `TodoFoundation.swift` 的transaction | Task/Event/List/Series/Source/Preferences/ReminderIntent成合法系列提交，单Open后继和停止事实一致 |
| 设备提醒日志 | `TodoReminders.swift`、`TodoAlarmReminders.swift` | 设备实际授权/request/排期日志不进入wire；只同步业务提醒意图，接收不弹权限 |
| ImportantDay | `ImportantDayFoundation.swift` 的StorePublication+commit | 日期规则、typed links和Cover；桌面公开许可仍是本机状态 |
| Sleep | `SleepFoundation.swift` | Record/GoalRule自然日身份、证据来源；未知不变零；本机提醒独立 |
| Investment | `InvestmentFoundation.swift` 的transaction；`InvestmentViews.swift` 的草稿persist转调service | Participant/Activity/Session/Operation；草稿保存也是写入口；consumed不复活、uptime/processID不跨机继续 |
| NetWorth | `NetWorthFoundation.swift` 的write | 临时context禁autosave，整体校验后commit；Item/正式Snapshot/未完成Draft都保护，不叠加并发金额 |
| 完整备份恢复 | `ImportExportService.swift` verificationContext与publicationContext | 验证库不产生发送；发布空库重检、取消和回滚保护后隔离新dataset；不恢复SDK token/ACK/账户绑定 |
| 启动/修复 | `AppContainer.swift`、各完整性/bootstrap入口 | 先保留旧库/WAL/原图，再迁移；坏图/未知远端隔离，不能关闭完整性检查或清库逃避 |

只读辅助搜索命令：

```sh
rg -n 'StorePublication|\.save\(|transaction\(' PersonalGrowthOS --glob '*.swift'
```

该搜索在G1接续源码产生93行命中，含非写入声明、注释、Debug/UI合成夹具与调用者，**不是93个正式事务或全部入口覆盖证明**。例如PersonalGrowthOSApp的直接save、ImportantDayUITestFixture和QuietWinsReader中的种子写入须按Debug/launchMode识别；InvestmentViews中的Release草稿commit则不能按文件位于UI层而漏掉。正式接入时须对每组追踪实际context、save/rollback及后台调用者，补“事实+outbox同时有/同时无”、迟到ACK、进程退出与恢复反例。

## 当前V16/v12固定输入

`Scripts/Fixtures/CreateSyncV16BaselineFixture.swift` 只追加到精确产品基线的归档测试文件，产品源码保持原版。它生成合成Entry/原图、标签与关系、Habit/Log/计划、Goal/事件、Weight、WeeklyReview、Pin/FollowUp、分享来源及防重收据、Todo系列及后继、ImportantDay、Sleep、Investment、净资产资产/负债历史与未完成草稿，使用实际V16 factory与v12 ZIP导出。

验证逐字段TransferSnapshot、净资产独立整数分预期、原图原字节、磁盘重开及v12 ZIP均保留分享防重收据（包括已删除来源的收据）。不是覆盖全部39实体所有可选组合，不新增V1–V15/v1–v11支持承诺。未来追加同步模型时，应复制该固定输入到新临时目录迁移并比较，不改写fixture或把新版本生成的数据冒称旧版本。

实际命令、尝试轮次、hash、结果与未验证限制见本轮交付证据。当前仅固定输入准备，V16→同步新schema迁移及所有写入outbox均尚未实现。

## 实际容量反证与候选修订

固定96f产品源码的实际 `NetWorthItemValue.validate` / `NetWorthSnapshotValue.validate` 接受10000行、每行160中文名称/80中文归属/1000个emoji备注、每行1分的正式快照；实际 `JSONEncoder` 编码 **49,190,297字节**，完整decode等值、净值独立预期10000分。本机专用模拟器1/1通过，原件SHA256 `9e97f46caef1fb89babb217a5cb7e25ee223beec74d6ce71408f211672fb9b13`。

这直接反证初版候选16MiB payload足够的假设，故继续实现有序4MiB分块manifest，不能只把它列为遥远风险。原始失败/工作目录纠正过程和最终原生日志见 `Evidence/iCloudSyncFoundation/20261107/capacity/`；49MB合成原件留本机，生成器可复现，不把伪造JSON行数当成真实领域容量证明。Swift的字符数量上限不能保证UTF8字节上限（组合字符可能更多字节），最终仍必须有显式资源预算及不截断/不丢本地输入的超限处理，不宣称有限分块预算能承载所有任意字节输入。
