# iCloud Sync V1 架构审计（独立 Review 修订版）

日期：2026-11-05。产品基线：PR #14 / `96f72339a1a3082c43018e06d6115dd93df1df97`。初次审计：PR #15 / `e036b01e971de9a9f0538d9a5dedfefc099bfc65`。

本文件是当前规范；[初次完整报告](ICLOUD_SYNC_V1_AUDIT_INITIAL_20261105_ZH.md)与原始证据按原字节保留，供追溯，不再以其被修订的语义或历史测试计数指导实现。修订依据见[关闭记录](ICLOUD_SYNC_V1_REVIEW_FIX_ZH.md)。下一轮执行入口是 [G1 Goal](ICLOUD_SYNC_V1_G1_GOAL_ZH.md)，环境配置入口是 [Apple 就绪门禁](ICLOUD_SYNC_V1_APPLE_READINESS_ZH.md)。

## 1. 结论及范围

继续推荐本地 SwiftData `.none` + 同事务 outbox/inbox + 应用控制的领域合并/显式冲突保留 + CloudKit private database / CKSyncEngine。不是从零实现网络调度器，也不是直接给 V16 开自动镜像。可行性有条件成立，产品同步尚未实现，发布仍为 **NO-GO**。

当前版本支持起点固定为上述 V16 数据库（含 WAL、原图）及 v12 备份。保护当前已保存数据，设计 Sync V1 及以后版本的升级；不新增更早 App、V1–V15 或 v1–v11 包的兼容承诺/强制回归。现有旧格式读取代码不主动删除，不改写历史 schema。遇范围外输入应明确拒绝并保留原文件，不能清库。旧 App 兼容与最低 iOS 版本是两回事，不能据此擅自提高 iOS 部署目标。

“不丢数据”指已确认保存的输入、冲突版本及原图具有可定位持久副本，失败可检测、可恢复/导出；不能保证唯一未上传设备物理损坏后仍可恢复，同步不替代独立备份。

## 2. 证据：历史验证与本次补验分开

| 项目 | 结果及限制 |
| --- | --- |
| 原 V16 声明/原生日志 | 39 实体、263 字段、52 unique、221 无声明默认值的必填标量、非可选 Entry.images。生成的存储形状本地可开；CloudKit preflight 134060 拒绝，随后未打包 CLI exit -6。不是完整产品、iOS 或真实云验证 |
| 原 SwiftData/CKRecord/CKAsset 实验 | 同次 save、rollback、进程退出重开、旧 ACK 保护及本地 SDK 编码；没有真实服务器 changeTag |
| 初次协议测试 | 16 PASS；独立追加的四项依赖反例均 FAIL，同一个根因。不得抹去原始失败 |
| 本次修订协议测试 | 原 16 + 原样四反例 + 新 14 投影/依赖检查，共 34 PASS；含排列/重复投递。仅 Linux/Python/SQLite，无云服务 |
| Apple 后台、签名、双设备、Production | 本次全部 NOT_RUN / UNVERIFIED；没有登录后台，不能从仓库文件推断已注册或已部署 |

原始证据见 [Evidence/iCloudSyncV1](Evidence/iCloudSyncV1/README.md)，本次记录见 [review-fix-20261105/results.json](Evidence/iCloudSyncV1/review-fix-20261105/results.json)。本次修订者自测，不冒称另一个 reviewer 已终审。未重跑 SwiftData 原生实验、产品全量测试、真实 ZIP 恢复或任何云端测试。

## 3. 39 实体和设备边界仍然有效

字段逐项清单及源码位置仍见 [schema-inventory.json](Evidence/iCloudSyncV1/schema-inventory.json)。下面是后续设计约束，不是已完成实现。

| 实体组 | 必须保留的边界 |
| --- | --- |
| Entry / ImageMetadata（2） | 原 UUID、正文或图至少一项、最多9图、顺序及时间；独立原图传输与完整清单 |
| Tag / ObjectLink（2） | 同名 alias 与重指、typed endpoint、deduplicationKey；关联依赖当前可发布对象，不能只查历史存在 |
| Habit / HabitLog（2） | once/day 与 multiple/day 分开；独立多次事实不能按内容合并 |
| HabitConfiguration / HabitLogDayMetadata / HabitPlanRevision / HabitLifecycleEvent（4） | 一对一、业务日/时区、计划覆盖及历史事件；不静默重排 |
| Goal / GoalLifecycleEvent（2） | 状态和事件同一合法业务提交；Flag 仍属 Goal |
| WeightRecord / BodyReferenceSettings（2） | 精度和日期保留、设置稳定单例 ID；同日体重不擅自去重 |
| WeeklyReview（1） | 周键唯一；并发文字保留候选 |
| EntryPin / EntryFollowUp（2） | pin 事实保留、确定性展示前三项；补充独立身份 |
| EntryExternalSource / CaptureImportReceipt（2） | URL 不是 Entry 身份；删除 Entry 后 receipt 仍防分享重放复活 |
| TodoTask / TodoTaskEvent / TodoList / TodoSeries / TodoTaskSource（5） | 系列级合并；occurrenceKey、单 Open 后继、事件链、停止/撤销与来源解链 |
| TodoSeriesPreferences / TodoReminderIntent（2） | 同步用户规则和意图，不把 generation 当别机授权/排期证据 |
| TodoReminderDeviceRecord（1） | 仅设备状态：权限、native request、接受/取消日志不进入 wire |
| ImportantDay / 两类 Link / Cover（4） | 日期语义、pairKey、封面独立所有权；本机桌面公开授权与内容偏好拆分 |
| SleepRecord / SleepGoalRule（2） | 唯一 wakeDay/effectiveDay、未知不等零；观察证据不得伪装为接收设备的观察 |
| InvestmentParticipant / Activity / Session / Operation（4） | 默认“我”稳定身份；session 为时长事实；consumed 不复活；uptime/processID 本地有效，不跨机自动续计时 |
| NetWorthItem / NetWorthSnapshot（2） | 外层/JSON身份一致、同日正式快照唯一、单草稿、整数分/未知/沿用日期/冻结历史/归档零余额；不将并发金额相加 |

Startup 完整性检查、StorePublication 进程内提交协调、所有服务级 save/rollback、Share inbox、缓存和通知均需明确接缝。不能关闭完整性检查来迁就半张远端图，也不能用 UI 通知代替同事务 outbox。大 JSON 必须按编码字节限额验证；超限采用版本化 asset/manifest，不能把合法的万行净资产快照盲塞普通 CKRecord。

## 4. R1：历史、候选与可发布状态分开

每个 entity 表示稳定对象身份，不是仅类型名。mutation 有稳定 ID、同对象父版本、wire version、内容和删除意图；同 ID 不同字节拒绝并保留诊断。

1. 完整性检查先解析同对象因果历史。缺祖先、跨对象父版本、循环、未知版本均保留原字节并暂存，不推断成删除，不触发破坏性修复。
2. **先选当前因果 head，再检查它的依赖。** 当前 head 不可发布时，不能通过重新选旧的可发布祖先“回退成活对象”。
3. 本 PoC 的保守规则：被依赖对象须有唯一、存活、依赖递归闭合的当前 head。已删除、删除/编辑并发、多个未决 head、缺依赖或依赖环都不满足条件。
4. 不满足条件的关联留在 inbox/冲突区。父对象正式删除后，不自动复活。删除意图不应等待其正在解除的依赖重新出现。
5. 生产实现必须处理领域聚合及合法循环关系的原子闭合；本 PoC 保守拒绝依赖环，不是所有业务关系通用求解器。未知/损坏记录的隔离、修复、资源上限仍待 G1/G3 设计。

实现位于 `protocol_rules.py`；`protocol_probe.py` 的 `heads()` 现在调用该规则，而非历史上存在任一活版本就放行。

## 5. R2：冲突投影必须是输入集合的确定性函数

禁止以“本机最后一次显示的值”作为已收敛结果。相同持久输入集合（无论到达顺序）必须给出相同可信状态、候选集合及统计输入规则。

- 唯一可发布存活 head：使用该值。
- 当前 head 含 tombstone：正常视图不自动复活；并发输入完整保留为冲突候选。
- 多个存活 head：若恰有一个最近共同祖先，且该祖先仍适合显示，可展示其内容作为**冲突前基线预览**；多个/不存在共同祖先时统一显示待处理，不任意选一支。
- 基线预览仍是冲突状态，`complete=false`，不是已确认当前值。未知/暂存/冲突不能转零。跨对象自然键冲突也不能双计；生产统计必须标明不完整或暂停受影响汇总，不能悄悄排除后仍称完整。
- 用户显式解决产生含全部被解决父版本的新 mutation。原候选在安全持久化前不得清除。
- 本机编辑草稿可以继续显示，但须标为未收敛预览。发布指纹、可信基线、冲突集合、完整性标志均参与 G1 收敛比较。

本次新增的是通用微型投影实验；尚未实现 Habit/Todo/净资产等真实统计 reducer。测试名称已收紧：同业务键只证明候选保留；固定 account/epoch 只证明迟到回调拒绝；旧 mutation 重放不是 ZIP 恢复；相同期次 mutation 去重不是两个设备独立完成的业务合并证明。

## 6. 本地、文件、账户与引擎契约

业务事实、outbox、版本元数据同 store、同显式事务；网络在事务外。上传绑定精确 mutation，旧 ACK 不能清新版本。CKSyncEngine state 不能替代持久 outbox；真实发送成功后必须重新核对最新待发送版本并重入队，避免引擎移除待发送记录后新修改永久搁置。

入站先持久化内容，再允许相应引擎检查点持久化；可重复拉取，不可先推进 state 丢内容。CKSyncEngine state 不是 PoC 的整数 token，禁止直接移植 `max(token)`。冲突用真实 system fields/changeTag/CAS，跨批次的聚合用 manifest 和完整性门禁。

原图使用独立 sync staging、hash/byteCount 校验、原子安装、引用/上传 lease。metadata 已到不等于原件已到。启动 GC 必须认识待下载、待提交及冲突引用；不删除唯一副本；完整备份缺原图必须明确失败。V1 不自动清理无法证明安全的 tombstone。

账户绑定区分 container/environment/account/dataset/generation。切换账户、关闭同步和恢复都需 cancel + epoch fence，含发送、下载、安装、ACK。保留原账户未上传事实与队列，不能带到新账户。账户变化可能重置引擎状态，因此须验证持久队列恢复及冷启动 A→B→A，而非仅验证拒绝回调。

v12 恢复先隔离验证，暂停业务投影/发送，保护空库门。备份不恢复 token、deviceID、权限、ACK、system fields；缺少同步谱系的当前本地备份默认恢复为隔离数据集，显式映射后再合流。缺记录不等于云端删除；恢复不是无条件 upsert；本轮不提供“覆盖全云”。

通知与 Widget 只同步业务意图。本机权限、实际请求、公开展示授权自行重建；远端接收不弹权限、不自动公开、不跨机续计时。V1 运行计时本机独占，未完成输入仍须可备份恢复；跨机实时接管不在 G1。

## 7. 阶段及新的环境前置门禁

| 阶段 | 出口 |
| --- | --- |
| G0 审计及补正 | 当前 Docs/PoC；不等于产品完成 |
| G1-A 环境预检 | 核实 Team/App ID/容器/权限/签名/设备；未知即 UNKNOWN；最小 Owner 操作清单 |
| G1-B Development 纵向验证 | 隔离签名实验，真实双客户端文字+图片+冲突+队列/state恢复+账户隔离；不接全部39实体 |
| G1-P Production 就绪 | 稳定 wire schema 清单和部署差异，Owner 授权后正式容器 Production 的合成数据往返；试验容器通过不能替代正式容器证据 |
| G2 当前基线升级/写入接缝 | V16/v12→Sync V1；所有写入口同事务 outbox。大规模接入前必须关闭生产环境阻断 |
| G3–G4 领域/媒体/系统验收 | 39实体决策、真实备份/提醒/Widget/Share、集中相关回归和独立审查 |
| G5 Owner 发布 | 正式构建签名/Production schema复核、另行授权 TestFlight；实际 TestFlight 双设备验收后才标生产可用 |

G1 开始即可预检，不必先发布 App Store。不能在“开发做完很久以后”才检查 Production；也不能为抢进度把不稳定试验 schema 提前灌进正式 Production。部署有不可逆限制，必须在核心 wire 稳定后按精确差异授权；每次后续新增字段均重验。具体执行和允许停点以 G1 Goal、Apple 门禁为准。

## 8. 验收矩阵保留并收紧

A01 离线保存与独立进程重开；A02 身份正确的初始合流；A03 同输入乱序/重放后投影、候选及完整性标志收敛；A04 删除/编辑/父子乱序和旧设备不复活；A05 原图完整性与完整备份闭合；A06 事实/outbox/inbox/state/文件关键退出点；A07 真实 serverRecordChanged 及配额/部分失败/限流/zone/token故障；A08 A→B→A 与冷启动隔离；A09 恢复和云事件竞争；A10 真实领域不变量及不双计；A11 本地提醒/Widget/分享副作用；A12 当前 V16/v12 升级、失败保留及未来版本策略；A13 容量、后台与最低/当前 iOS；A14 SHA/设备/环境/失败原始证据和隐私。

每项按模拟、原生本地、Development真实服务、正式Production、TestFlight分别计证据。未测写 NOT_RUN，环境不具备写 BLOCKED_ENV；不能将队列为空、accountStatus可用、Console显示0条或无待部署差异单独当作同步成功。

Apple 依据：[SwiftData 同步约束](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)、[CKSyncEngine](https://developer.apple.com/documentation/cloudkit/cksyncengine-5sie5)、[CloudKit 部署](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)。详细生产环境依据与复核步骤见 Apple 就绪门禁。
