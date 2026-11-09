# 2026-11-09 Production 成功后的 iCloud 同步独立审查

**结论：核心收发已经可用，当前工作区恢复获得 Owner 正向实测反馈；可靠性收尾仍需完成。建议保留现有架构，集中修复 R1–R5。** 本文不是实现交付；本轮未修改产品、执行原生测试、读取私人库或操作 CloudKit。

## 一、最新事实与审查边界

Owner 在本轮明确反馈：

1. 在 CloudKit Console 手动执行 Deploy Schema Changes 后，用手机现有 TestFlight 版本点击“立即同步”，过一会显示同步成功。
2. 系统删除 App 和本地数据，再安装，“好像可以拉回刚才同步到 iCloud 的数据”。

因此更新状态如下，不再沿用“Production 始终未执行”的旧结论：

| 项目 | 当前可支持的结论 |
| --- | --- |
| Production schema 操作 | `OWNER_REPORTED_DEPLOYED`；本轮未重新导出后台 schema |
| 原故障后的同包同步 | `OWNER_REPORTED_SUCCESS`；这次后台部署解除原先阻断的证据很强 |
| 当前工作区删除重装恢复 | `OWNER_REPORTED_RECOVERY_OBSERVED`；已有数据返回的正向证据，保留 Owner“好像”的完整性限定 |
| 全业务数量、关系和原图逐项一致 | 未取得对照证据，不把上述反馈扩写成全量一致性通过 |
| 长期自动同步、真实双设备冲突、后台传播 | 本次反馈未覆盖；其中部分另有明确代码缺口，见下文 |

按上下文，本轮手机沿用 `1.0 (Build 19)` / `4d4fc812739fb51394364f4c5e629ff7cd42ea4f`；Owner 未反馈更新到另一源码。本次实时读取远端确认：`codex/icloud-product` / Draft PR #19 仍在 `ddc5af8b91fcf9d3cde7434bb7bda074d859ad4a`。与安装 SHA 的 compare 只有后续两次文档/证据提交，没有应用代码变化。

本轮按固定源码审查正式 App、SyncFoundation、已有集成与边界测试，并以 Apple 官方文档核对 CKSyncEngine 自动调度和订阅类型。协议、生命周期和恢复/领域三个方向独立检查；R1 由主审及两位 reviewer 交叉确认。没有把静态调用链说成已经执行的 Xcode 回归，也没有把计划变成 Owner 的新授权。

## 二、是否“做好了”：采用明确的完成标准

- **手动上传已获成功反馈；当前工作区重装后已观察到数据返回。** 不应继续按“功能尚不可用”处理。
- **可作为日常功能继续试用：有依据。** 但 R1 会在特定未完成下载状态下影响本地保存，应优先修复；当前成功不能证明这个异常分支安全。
- **无需经常人工干预的稳定自动同步：尚未收口。** R2–R4 是具体调度/通知问题。
- **任意 ZIP 恢复后再次找回、多设备自然键冲突、长期无限增长：现版本仍有清楚边界。** 这些不否定本次成功，也不应被隐去。

没有证据支持推倒重写。下一步应修正现有同步状态与业务保存、自动调度之间的几个接口，并更新准确的完成记录。

## 三、已实现且值得保留的架构

| 设计 | 当前实现的价值 |
| --- | --- |
| 本地 SwiftData 与显式 CloudKit 分工 | 核心业务库采用 `.none`，同步由独立 coordinator/transport 承担，符合 Local First |
| 业务事实、mutation、outbox 同事务 | 本地业务保存与待传修订共同提交，避免已保存内容漏入队列 |
| 不可变修订与因果父版本 | 不依赖两台设备时钟直接最后写入覆盖，保留冲突与删除关系 |
| durable inbox 与 engine checkpoint | 先持久接收数据，再推进引擎状态；远端投影不重复生成本地 outbox |
| 精确 ACK 与原图闭合 | 一条修订的 manifest、chunks、originals 全部确认才收尾；哈希/字节数不匹配不能当成功 |
| 账户、容器、环境、dataset、generation 隔离 | 对旧回调和跨身份写入保留约束 |
| 领域适配 | 23 个聚合覆盖 38 个业务实体，包括随记、原图、关系、习惯、待办、重要日子、睡眠、时间投入、净资产等 |

这些属于实际代码能力；此前合成测试为其提供部分证据，本次真实 Production 往返补充了实际服务路径。设备提醒执行日志、桌面展示授权、运行计时的进程/uptime 锚点刻意留在设备侧，不应把它们当作业务数据漏同步。

## 四、建议本轮关闭的确定问题

以下行号全部针对安装 SHA。P1 表示特定条件下阻断核心本地使用；P2 表示影响自动同步可靠性或可维护性的明确问题，并不表示用户此次已遭遇它。

### R1 · P1：远端未发布对象会连带阻止无关本地保存

**场景：** 云端一条新 Entry 的版本清单/文字分块已经到达，本机还没收到它的原图。这条 Entry 暂时不进入业务库是合理保护；问题是此时另一条无关 Entry 的新增或编辑也可能保存失败。

确定调用链：

1. `SyncProductCoordinator.swift:548–581` 因缺原图不认为整轮投影完整。
2. `599–609` 仍持久化远端新对象的 `ProductSyncObjectState`：`fingerprint=unpublished`、`deleted=false`、`projectionState=pending`，但没有对应业务 Entry。
3. 用户另存一条 Entry，`SyncPersistence.swift:239–244` 按 dirty kind 调用 `stage`。
4. `279–300` 捕获该 kind 全部本地业务对象，并把没有在 capture 出现、尚未标记 deleted 的旧 state 当作本地删除候选。上述远端新对象因此落入错误分支。
5. `prepare:310` 因 pending 状态抛 `unresolvedConflict`；`save:244,260` 将整次本地业务提交回滚。

影响是**同 kind 的无关保存**，不能夸大为任何情况下所有模块都无法保存。关闭同步也不能可靠绕开：`save:242` 检查的是 `initialized`；`disable` 只改 enabled/generation，这原本用于保留关闭期间的后续修改。

还存在条件性恢复卡住：冷启动后无活跃 driver，手动 Sync now 会走 `enable → initialize(stage all kinds)`；初始化发生在网络获取之前，同一 pending state 可再次阻止启动，因而无法先下载已经补齐的原图来解除阻断。原活跃 session 仍在时，手动获取仍可能恢复。

**最小复现与测试位置：** 现有 `SyncProductIntegrationTests.testOriginalBytesGatePublicationAndDeletionWaitsForRelationshipTombstone` 第188行已投递 `withoutOriginal`，189确认远端 Entry 未发布。直接在190补原图之前增加 `createEntry(b, body: "independent local")`，现实现将沿上述路径抛错。现有测试跳过了这个间隙里的本地写入。本轮没有执行此新增断言，应在修复前先保留实际失败证据。

**修复原则：** 从本地 capture 缺席推导删除，只能针对确实曾发布到本地的业务基线。远端已知、尚未发布的对象不能被推导为本地删除，不能阻断无关对象写入。继续保护真正被编辑的冲突对象；不能简单删除 `prepare` 的冲突 guard。验证关闭同步后的普通保存与冷启动继续获取也能恢复。

### R2 · P2：暂时性失败和缺件等待被归入人工阻断

`SyncCloudTransport.swift:190` 关闭 SDK 自动调度，由应用显式 send/fetch。这个选择本身可以成立，但 `216–235,514–529` 将暴露到应用的网络/服务暂时不可用、限流等错误统一压为 pause。`Coordinator:483–498` 持久化 blockedReason；`refreshStatus` 与 `311–318` 的自动调度条件因 requiresAttention 拒绝由本地提交、回前台或推送触发的后续自动同步。这一条本身不等于本地业务保存失败，保存问题见 R1。

因此当一次可恢复错误已经返回给应用后，恢复网络并不保证自动续传，通常要手点。不能写成每次短暂断网都必然立刻失败：SDK 可能内部处理部分错误，缺口在应用实际收到失败之后。

同类情形出现在 `project:632`：暂时缺父版本/原图也被写成 blockedReason；另一设备后来上传齐全，本端仍不能自动续拉。应区分可等待/重试、完整性/版本不支持、真实账户变化与云端删除等状态。

**最小处理：** 在现有调度入口区分可重试等待与需要用户处理，尊重 retry-after、有界退避，允许同一已启用身份下回前台/网络恢复继续；保持 pending、ACK、首因和 generation 防护。不要直接把 `automaticallySync` 改 true 就宣称完成，现有整轮 inbox 应用和单 zone 范围都要保持正确。

### R3 · P2：同步忙碌期间提交的新记录可能没有后续上传机会

`Coordinator:73–77` 本地提交只调用 `scheduleSync`，`311–314` 在 busy 时直接返回，不记录后续工作。`235–244` 一轮结束只清 busy/activity。`Transport:226–231` 一轮是 send 后 fetch；fetch 期间新增的修订虽然已经持久化，却不会再次 send，SDK 自动调度又已关闭。

明确时序为：发送完成 → 正在 await 下载 → 用户保存新记录 → 唤醒因 busy 被忽略 → 本轮结束。若用户不再编辑、不重新回前台或手点，该修订可以一直 pending。队列没有丢，自动推进缺少尾部处理。

**最小处理：** 忙碌时合并一个待处理标志，本轮结束检查持久 outbox/待获取事件，串行补一轮；不能并发启动多份 transport。用受控 fetch 暂停点验证即可，不需要新的实验平台。

### R4 · P2：推送桥过滤掉默认数据库通知

`Transport:188–191` 使用默认 subscriptionID 的 CKSyncEngine；Apple 说明默认发现/创建 `CKDatabaseSubscription`。但 `SyncPushBridge.receive`（`Coordinator:693–701`）只接受 `.recordZone`，会把合法 `.database` 通知直接返回 noData。

正式 App delegate 在 `ImportantDayRouting.swift:24–28` 调用该 bridge；后台 remote-notification 配置与 APS 接线已有，未见产品另行建立 `CKRecordZoneSubscription` 来匹配这个过滤条件。

手动同步与前台恢复可掩盖此缺口，因此本次重装成功不验证后台通知路径。不能宣称所有后台情况绝对失败：启动还可能另行触发 resume，系统通知也不保证固定时延。证实的是当前 bridge 拒绝默认正确通知类型。

**最小处理：** 正确接受并验证本容器/private database 的 database notification，再进入同一串行调度入口；保留兼容的 recordZone 时核对其范围。通知只作为获取变化的提示，不将一条通知当作一条业务记录。定向覆盖合法通知、无关容器/数据库、busy 合并和用户关闭同步。

### R5 · P2：错误诊断仍过度简化，状态文案未随证据收口

`Transport:514–524` 与 `Coordinator:494` 仍把底层问题压成 `cloudFailure(rawValue)` 一类字符串，原始说明、阶段和 partial errors 无法从页面复制。后台修好并不解决以后再次排错的信息缺口。

同一轮补最小、有界、脱敏的诊断快照及复制入口：时间、构建、环境、阶段、domain/code、recordType、成功/失败数、允许公开的原因以及有界 underlying/partial errors。保留首因与已成功 ACK；不输出正文、原图、完整 CKRecord或可识别账户的信息。

启用文案应解释双向连接能力。固定“此开发版本/真实 iCloud和Production验收尚未完成”的文案可改成准确的测试阶段说明，不能因本次成功就宣称全场景已验收；“同步完成”应与待获取/待应用/待上传状态一致。

## 五、应保留记录、但不扩大本轮修复的边界

### K1：ZIP 恢复工作区仍缺少再次发现路径

普通 Production 新装默认 dataset 为 A002；ZIP 导入通过 `.restoreNewDataset` 生成随机 dataset。现有 transport 只处理当前 binding 的单个 zone，没有旧工作区目录/选择入口。用户此次成功说明本次工作区路径实际可行，不证明“ZIP 恢复 → 上传到随机工作区 → 再次删除重装”也可行。

优先明确单工作区恢复语义，区分连接既有云端内容与保留独立本地恢复副本，再做必要身份处理。无需一开始建设完整多工作区管理；也不能直接把随机 UUID 改回默认值，混淆不同因果历史。此项应在承诺任意备份恢复后都能再次从云端找回之前解决。

### K2：跨 UUID 的业务唯一键冲突缺少用户处理闭环

例如两台设备离线分别创建同名标签、同一天睡眠记录或同一周回顾：业务 UUID 不同，但部分字段具有唯一性。

`SyncDomainInstaller:178–183` 拒绝跨 UUID 的唯一键碰撞，避免 SwiftData 静默 upsert；标签、周回顾和睡眠各有对应检查。`SyncDomainInstallerTests:82–91` 明确测试同名不同 UUID 标签被拒绝并保留原对象。这是正确的数据保护。

不过现有冲突 UI 来自 `Coordinator:577–579` 的同一对象多因果头，不能直接处理跨 UUID 的唯一键冲突。产品尚缺具体对象说明与明确处理入口。此限制已经被历史交付记录接受为保留/暂停，不能说本轮新发现了静默丢数据。

在扩大为日常双设备并行使用前，应补最常见类型的识别与处理；本轮不自动合并全部领域。图片冲突目前主要显示数量/文件名/尺寸，视觉比较也可在同一后续阶段完善。

### K3：历史增长有明确上限和成本

`CausalProjectionLimits` 默认限制 10,000 个 manifest、32 MiB 编码总量、2,000,000 次图遍历。`Coordinator.project:532–576` 每次传入该 dataset 全部持久历史，尚未交付安全历史整理。

**10,000 是历史修订数，不是当前业务记录数。** 新增、修改、删除、解决冲突都会积累版本。这里是本项目实现的容量约束，不是 Apple 宣布 iCloud只能存 10,000 条记录。之前的 429 待同步数也不能直接作为今天所有云端历史的总量或据此计算剩余空间。

历史文档已经明确承认这些上限及未完成的历史整理。建议诊断能显示历史规模和接近限制的状态，后续依据增长安排按对象投影、索引或安全压缩；不能直接删除祖先和 tombstone，破坏旧设备回归与删除防复活。

另有可测量的性能成本：整轮仍遍历/校验全历史；上传 record 查找重复读取全部修订；原图在同步资产、inbox bytes和业务原图有多种持久表示。当前“每轮统一投影”已比逐 record 重放改善很多，本轮没有测量真机耗时/磁盘量，不宣称现机必然卡顿、发热或占用某个倍数。优化按真实规模推进，不作为重写理由。

## 六、建议给 Codex 的一次限定收尾

本节是下一轮可执行规格；只有 Owner 实际发送执行指令后才成为本轮开发任务，不因执行器读到本文自动新增权限。

### 目标 1：R1，本地保存与未完成远端状态正确隔离

先扩展现有集成测试保留红测，再修最小调用链。验证未到齐原图/父版本时，无关 Entry 能新增与修改、关闭同步后仍能保存；不生成针对未发布远端对象的本地删除；真正被编辑的冲突对象继续受到保护。重开磁盘库后走实际启动编排，能够继续取回缺件并完整应用，不靠直接投递 packets 绕过入口。用现有隔离合成库与可控 transport seam，不建新的外部实验环境。

### 目标 2：R2–R4，同一串行调度入口完成自动推进

复用当前 coordinator/transport：忙碌时保留待处理请求，一轮结束继续完成新 outbox；暂时网络/服务错误与缺件等待可恢复，账户变化、云端删除或结构损坏保持保护性暂停；正确接收默认数据库推送并验证容器/private scope。保留单 zone、enabled、account/generation 校验和统一应用边界。

定向覆盖发送后新增、下载中提交、retry-after、恢复网络/回前台、缺件后来到齐、正确/无关推送、关闭同步后不被唤醒、旧 epoch 回调不推进新状态。测试应通过状态与实际行为断言，不仅测试一个布尔 gate。

### 目标 3：R5，诊断与真实交付状态收口

增加最小复制诊断，保留具体首因与有界脱敏错误链。说明可等待/重试与需用户处理的区别；启用说明双向行为；将 Owner 本次部署/同步成功与恢复观察如实记入证据，不把完整性和两设备验收补写为通过。清楚保留 K1–K3，不强迫本轮实现所有边界。

### 交付和停止条件

- 沿当前 `codex/icloud-product` / 原 Draft PR #19，先检查实际最新头与本地改动，保留已有成功实现。
- R1–R5 有针对性的失败/修复证据、受影响构建与独立复核；遵守既有必需 CI，不为每个小改动重复整套历史测试。
- 更新 CURRENT 和本轮证据，普通提交/推送。给 Owner 一次明确的新包验收清单，不把同步修补变成一轮新的 Mac 探针或长期陪测。
- 本规格不需要改 CloudKit schema、清库、清 token/ACK、删云端 records/zone、重置工作区或再次让 Owner 删除 App。
- TestFlight分发按 Owner 已有有效授权及真实候选代码执行，不能给 `[skip ci]` 文档提交打发行 tag。不得把本轮分析文档当成已经修复、合并或公开上架的证据。

## 七、Owner 后续只需做的少量确认

现有反馈已被认可，无需为证明同一件事重复删除重装。若方便，可在当前恢复后的 App抽看较早记录、最近修改和原图，帮助将“看起来恢复了”推进到更清楚的样本结论。

上述修补完成、覆盖安装候选后，优先一次完成：

1. 新增一条带照片记录并修改一次，观察自动同步收尾，不主动点击立即同步。
2. 离线保存一条测试记录并重开，确认本地可读；恢复网络后确认最终自动收尾。
3. 抽查恢复旧内容和原图，确认本地日常功能正常。

忙碌丢唤醒、缺件状态和重启恢复优先由 Codex用定向自动测试构造，不要求 Owner手工制造时序。将来准备声明真实双设备自动同步和冲突体验完成时，再使用已有第二设备补一次有限的传播/冲突验收；不把购买设备或重建实验环境作为本次代码修补前提。

## 八、证据与来源

固定应用源码：

- [SyncPersistence.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/Sync/SyncPersistence.swift)
- [SyncProductCoordinator.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/Sync/SyncProductCoordinator.swift)
- [SyncCloudTransport.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/Sync/SyncCloudTransport.swift)
- [SyncProductIntegrationTests.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOSTests/SyncProductIntegrationTests.swift)
- [SyncDomainInstaller.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/Sync/SyncDomainInstaller.swift) 与 [对应测试](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOSTests/SyncDomainInstallerTests.swift)
- [SyncDomainCodec.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/Sync/SyncDomainCodec.swift) 与 [对应测试](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOSTests/SyncDomainCodecTests.swift)
- [CausalProjection.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/Packages/SyncFoundation/Sources/SyncFoundation/CausalProjection.swift)
- [ImportExportService.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/ImportExport/ImportExportService.swift)
- [ImportantDayRouting.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/ImportantDays/ImportantDayRouting.swift)
- [此前明确容量/自然键边界与测试范围](https://github.com/yoCruzer/PersonalGrowthOS/blob/ddc5af8b91fcf9d3cde7434bb7bda074d859ad4a/Docs/Evidence/iCloudProduct/20261108/README.md)
- [产品头相对安装源码的仅文档差异](https://github.com/yoCruzer/PersonalGrowthOS/compare/4d4fc812739fb51394364f4c5e629ff7cd42ea4f...ddc5af8b91fcf9d3cde7434bb7bda074d859ad4a)

Apple 官方来源：

- [CKSyncEngine automaticallySync](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/configuration/automaticallysync)：自动调度及可恢复错误重试；关闭时由应用显式 send/fetch。
- [CKSyncEngine subscriptionID](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5/configuration/subscriptionid)：默认发现或创建数据库订阅。
- [CKNotification.NotificationType](https://developer.apple.com/documentation/cloudkit/cknotification/notificationtype-swift.enum)：database 与 recordZone 为不同通知类型。

审查结束状态：核心 Production成功与恢复观察按 Owner报告入账；R1–R5 是下一轮明确修补，K1–K3 保留已知边界。本轮仅交付审查和规格，未产生新的产品测试通过记录。
