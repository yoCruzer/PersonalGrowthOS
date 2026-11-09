# 2026-11-09 Production 部署、同包同步与删除重装恢复测试 SOP

**状态：SOP_READY / 本轮真机步骤尚未执行。** 本文回答 Owner 关于人工部署、点击“立即同步”和删除重装恢复的三个问题；依据已安装版本静态代码与 Apple 官方文档编写。当前最后一份手机证据仍是 `cloudFailure(12)`、待同步 429。本文没有把计划写成部署成功、上传成功或恢复成功。

适用版本：随心 log `1.0 (Build 19)`，源码 `4d4fc812739fb51394364f4c5e629ff7cd42ea4f`，TestFlight 标签 `testflight-icloud-sync-v1-20261109`。目标容器仅为 `iCloud.com.yocruzer.PersonalGrowthOS`，Production，当前 iCloud 账户的 private database。产品工作继续沿 `codex/icloud-product` / Draft PR #19；本文属于独立文档分支，不改变产品代码。

相关背景见 [故障分析与 Codex 交接](ICLOUD_PRODUCTION_FAILURE_20261109_ZH.md)。

## 一、先给结论

1. **可以由 Owner 直接在 CloudKit Console 部署，不必通过 Codex。** 先核对本次实际 Development → Production 差异，确认与已审核范围一致，再点最终 Deploy。部署 schema 不会复制 Development 的业务数据。
2. **部署完成后，可以继续使用手机现有 Build 19，点击一次“立即同步”。** 如果唯一阻断就是缺 schema，无需为此重新打包。先验证原队列收尾，再验证一条新增和一次修改。
3. **删除重装是有价值的恢复测试，但属于下一阶段。** 先保留 App 外可验证的完整备份、确认还能安装同版，并核实当前实际 Production 工作区身份。此版本默认新装指向固定工作区，而 ZIP 恢复会创建随机工作区；不能只凭“同步完成”就删除唯一的本地副本。

## 二、阶段 A：人工部署 Production schema

### A1. 选择目标并审核当前差异

1. 打开 [CloudKit Console](https://icloud.developer.apple.com/)，进入 CloudKit Database。
2. 选择正确团队和容器 `iCloud.com.yocruzer.PersonalGrowthOS`。
3. 从 Development 进入 `Deploy Schema Changes`（具体界面可能称 Deploy Schema to Production）。
4. 阅读**这一次**的差异预览。仓库历史审核不能替代当前预览；该动作涉及当前待部署差异，不能假定只会发布自己心里想的三种类型。

本次预期业务结构：

| Record type | 业务字段与类型 |
| --- | --- |
| `PGMutationV2` | `manifest BYTES`、`sha256 STRING`、`wireVersion INT64` |
| `PGPayloadChunkV2` | `byteCount INT64`、`chunk ASSET`、`sha256 STRING`、`wireVersion INT64` |
| `PGOriginalV2` | `byteCount INT64`、`original ASSET`、`sha256 STRING`、`wireVersion INT64` |

历史审核还包含对应的 9 个带索引字段 / 21 个索引标记，以及新类型原有 grants；`Users` 不变。完整索引及 grants 见故障分析第三节。这里的 **11 是业务字段数**，不包括 Console 额外显示的系统字段；21 是索引标记数，不是 21 个独立字段。

若 Production 已完整匹配，则跳过部署，直接进入阶段 B。若已有部分匹配结构，实际增量可以只包含缺失项，不要求再次出现完整的三类型新增。若预览多出无关类型、改动既有结构，或与上述契约不符，先让 Codex核对具体差异，再决定本次发布范围。

### A2. 部署并回读

1. 差异符合预期时点击最终 `Deploy`，等待控制台给出完成结果。
2. 切到 **Production → Record Types**，核对三种业务类型及每个字段的类型；有导出能力时保存部署后的 schema，供 Codex只读比对。
3. 保存部署结果与时间，进入阶段 B。

若部署页显示没有待部署差异，但 Production 字段实际仍不匹配，仍按未就绪处理，交给 Codex定位；空 diff 不能代替逐字段核对。

Apple 说明部署合并类型、字段、索引，**不会复制 Development records**。Production 中已发布的类型和字段受不可删除/不可改型限制，所以最终差异值得逐项确认。部署成功后没有业务记录，仍可能是正常状态：手机尚需实际上传。[Apple 官方部署说明](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema)

不必为了这一后台结构修正先生成新 TestFlight 版本；也没有依据要求固定等 5 分钟或 24 小时。以控制台真实完成/处理中状态为准。若查询结果暂时不可见，应区分查询索引可见性与实际按 recordID/zone 同步，不能为浏览 Console随意添加索引或据此判定上传失败。

## 三、阶段 B：保留现有安装，验证上传与增量

### B0. 保存可回退材料和测试身份

- 从当前 App 导出完整 ZIP 备份，另存到 App 自身目录之外，优先复制到 Mac；确认文件确实存在且可读取。若导出报告待导入分享，先记录并单独保留这些内容，不能默认已全部进入 ZIP。
- 记录 `Build 19 / 4d4fc8127`、iOS 版本、Production、测试时间（含时区）和起始待同步数。429 是待同步修订数，不能用它当恢复后业务记录总数。
- 选少量容易认出的内容作为核对样本：一条较早记录、一条近期修改记录、一条带原图的记录，以及自己实际使用的一类关联或业务数据。

**备份验证注意：** 同版 `previewPackage` 和实际导入都要求目标业务库为空，不能在现有已装满数据的 App 内靠“导入预览”验证备份。可由 Codex在 Mac 上只读校验 ZIP/manifest/data 与媒体字节数、SHA-256；需要恢复预演时用隔离的空目标，保持日常数据不受影响。结构与哈希校验能证明归档完整性，不能冒称已经完成完整导入测试。

### B1. 让原队列完成一次同步

1. 确认 A2 已完成，打开现有 App → 设置 → iCloud 同步。
2. 如果仍为“同步已暂停”且同步开关启用，点一次 **立即同步**。代码允许此入口在旧 session 已失效时重新启用；无需先反复关闭再开启。
3. 如果同步已关闭，则点 **启用 iCloud 同步**并确认。
4. 保持 App 在前台，观察检查账户、上传、下载、应用等阶段；阶段可能很快掠过，无须逐一截图。同步中先不编辑业务内容。
5. 等待出现完整成功状态、合理的最新完成时间，且待同步数为 0、没有残留错误或待核对冲突。
6. 打开原有几条记录和原图，确认仍可读取；离开同步页再回来，并在完成后正常重开 App，确认完成时间和内容保留。

**B1 通过条件：** 现有队列收尾、下载/应用流程结束、完成时间更新、无残留阻断、已有内容仍可读。计数暂时不下降不等于没有任何 CKRecord 成功；一个修订的 manifest 和全部依赖资产完成 ACK 后才计为完成。

**B1 失败处理：** 若再次出现 `cloudFailure(12)`，记录这一次时间、阶段、画面及剩余数，转给 Codex核对真实 Production schema和原始 CloudKit 错误。一次明确失败即可进入定位，不靠连续点击重试猜原因。若只是长时间没进度，可先以约 5 分钟作为人工观察点记录现状；这是本 SOP 的沟通时间点，不是 Apple 超时保证，也不是判定失败或取消活跃传输的硬阈值。此时暂不进入阶段 C。

### B2. 验证一条新增与一次修改

1. 新建醒目测试记录，例如 `iCloud 验证 2026-11-09 HH:mm / v1`，附一张非敏感小照片。
2. 等本轮同步完成；若需手动点击立即同步，记录这一事实，不把手动成功写成自动同步通过。
3. 把同一条记录改为 `/ v2`，再次等待完整成功。
4. 重开 App，确认修改后的文字和照片可读，队列为 0，完成时间合理。

**B2 通过条件：** 首轮之后还能持续提交新修订，照片相关请求没有阻断。只在本机读到刚创建的内容，不能独立证明它已在新设备下载成功；这一点留给阶段 C。

若本轮只做阶段 A/B，到这里已完成一次有用的同包验证，无需马上删除 App。保存一张最终状态图、一张测试记录图及开始/完成时间即可交接。若准备进入 C，等待测试记录和修改同步完成后，再导出一份最新完整备份作为恢复对照基线。

## 四、阶段 C 前必须核对的代码边界：工作区身份

### C0. 当前工作区是否会被新装找到

源码 `ProductSyncStoreSelection.defaultDatasetID(for:)` 的 Production 默认值为：

```text
EAB541A0-45A1-43E4-9009-4E6F316EA002
```

对应私有 zone 为：

```text
PGSyncV2-eab541a0-45a1-43e4-9009-4e6f316ea002
```

真正的新安装没有本地 dataset 时会使用该默认值。相同 iCloud 账户、容器、环境和 dataset 才指向相同的私有工作区；不同用户不会因这个常量而共用私有数据库。

但是，**在 Production 中通过 ZIP 恢复创建的工作区会获得新的随机 UUID**。现有 transport 只发送/获取当前 binding 的单个 zone，没有远端工作区目录、遍历查找并让用户选回旧工作区的实现。因此，如果当前成功上传的工作区是这种随机 dataset，新装可能回到默认工作区，找不到刚上传的那份数据。

这不是对用户既往导入行为的猜测：目前不知道用户是否处于此情况。删除前应由 Codex利用可用的设备同步诊断、本地同步状态，或同一 iCloud 账户的实际私有 zone证据，**只读核对当前 active Production dataset/zone**。普通备份 v12 故意不含同步元数据，不能仅凭 ZIP 推断当前身份；如果当前包没有可用诊断通道，先补最小只读身份诊断或在保留原机的前提下做备用设备恢复验证。

- 当前 dataset 确认为默认值：具备走现有默认恢复路径的代码基础，可在备份保护下继续 C；这仍不等于真实恢复已通过。
- 当前为随机 dataset：先解决重新发现/选回该工作区的问题，再考虑删除唯一副本。不要通过强行改 UUID、清 token或合并 zone假装解决身份问题。
- 当前无法确认：保留原机，优先在已有备用设备的真正空安装上验证，或先取得诊断证据。备用设备不是必须购买的新前提。

**空库不会自动删除云端记录。** `ProductSyncCommit.stage` 只对本地以前已有 ObjectState、此次 capture 中消失的对象生成 tombstone。真正新装没有旧状态，空库不会凭空产生删除记录；当前 transport 也没有物理删 record/zone 的允许路径。相反，在 App 内批量删除业务记录会走正常同步删除，这不能用来模拟本次“清空本地”。

**“同步完成”不能单独证明恢复完成。** 当前成功判断可在绑定空工作区、没有待传修订且没有错误时成立。因此恢复后必须核对旧内容、数量、关系和原图，不能仅凭绿色状态或待同步 0。

## 五、阶段 C：单机删除重装恢复 SOP

### C1. 开始前的四项确认

1. 阶段 B 已通过，最后一轮新增/修改也已收尾。
2. 最新完整 ZIP 已另存到 App 之外，并完成可用性校验；知道怎样在隔离空目标恢复它。若依赖完整导入预演，记录它是否实际执行，不能把仅解压成功当成导入通过。
3. 已确认同一 TestFlight 版本仍可重新安装；手机仍使用同一个 iCloud 账户；C0 的工作区条件已经满足。
4. 留下恢复对照：旧记录、最近修改记录、刚建的 `/ v2` 记录、原图、代表性关联和各主要业务对象/照片数量。数量可从备份 manifest由 Codex提取，不要求 Owner 手工逐条统计。对照期间避免继续编辑；活动计时或日期派生值按事实字段核对，不要求显示的实时值逐字相等。

### C2. 执行删除和安装

1. 在 iOS 系统中对这个 App 执行 **删除 App**。不要只从主屏幕移除，也不要选择 **卸载 App / Offload**。
2. 保留 iCloud 的 App 数据；不要在 iCloud 储存管理、CloudKit Console或应用管理功能里删除云端数据。
3. 从 TestFlight 装回同一版本。删除后不需要人为等固定时间，关键是删除前同步已完成、现在得到真正空的本地状态。
4. 首次打开先确认业务内容为空，随后直接进入 iCloud 设置。先不创建测试记录、保存业务设置、启动活动或导入 ZIP；如一开始就已有旧内容，先记录来源，不能把它算作本轮从空库下载的证据。
5. 启用 iCloud 同步。当前版本统一的确认框仍叫“将此工作区上传至 iCloud？”，代码随后也会下载；在已经核对正确默认工作区且本地确实为空的前提下，可按正常启用入口继续。这里没有另一个已实现的“选择旧云端工作区”页面，不能把未来功能写成现有操作。
6. 等待下载、应用、完成时间更新。空库一开始待同步就可能是 0，因此初始 0 不算成功。若出现额外的“云端没有工作区 / 创建工作区”确认、账户不一致、错误，或完成后仍是空库，先记录并停止推进，交给 Codex定位。

Apple 明确区分：卸载 App 保留文稿和数据，删除 App移除本机应用及相关数据；一般而言已存储在 iCloud 的数据不会因为系统删除 App 而同时删除。这是平台规则，并不是本项目能够找回正确工作区的证明。[Apple：移除或删除 App](https://support.apple.com/zh-cn/guide/iphone/iph248b543ca/27/ios/27)；[Apple：储存空间及卸载/删除区别](https://support.apple.com/zh-cn/108429)

### C3. 内容验收和持久化验收

1. 核对较早记录、近期修改记录、`/ v2` 测试记录均已回来，内容正确，没有出现一批重复记录。
2. 打开原图而不只看列表缩略图；检查标签、关联和自己使用的主要业务类型，例如待办、习惯打卡、体重等。
3. 下载结束后切到飞行模式，确认 Wi-Fi/蜂窝均断开，再完全退出并重开 App。检查上述内容及原图仍可读取；可以包含一张这次恢复后尚未提前打开过的旧图。此步骤不做新增或删除。
4. 恢复网络，导出恢复后的完整 ZIP，由 Codex在私有位置与 C1 基线比较：同步范围内的业务 ID 集合、稳定内容、关系，以及原图 SHA-256 和 byteCount。整体 ZIP 哈希、exportID、导出时间、缓存或设备权限不要求一致；若含设备本地偏好或实时派生值，按当前同步契约判断。发现差异应列明，不做静默忽略。
5. 完成对照后，把已恢复的测试记录改成 `/ v3`，确认能再次同步收尾。这一项检查恢复后的持续写入路径，而不是只验一次读取。

**C 通过条件：** 真正空安装从正确云端工作区恢复了基线中的同步业务内容和原图，关系正确、无重复，离线重开可读，恢复后新增修订还能收尾。人工抽查只证明样本；做过全量备份内容对照后才能给出相应全量结论。测试范围内未验证的类型继续标为未覆盖。

### C4. 恢复不成功时怎样处理

- 保留错误、时间、界面和观察到的数量；停止新建/编辑，必要时先关闭同步，等待排查。
- 不 reset 云端、不删除 zone、不用 App 内全选删除代替本地清理，不连续尝试不同账户或工作区。
- 若急需取回本地可用状态，可用已校验 ZIP在空目标按现有恢复流程恢复；先妥善保留恢复测试期间产生的任何新内容。该操作属于 **ZIP 本地恢复**，本轮 iCloud恢复仍判未通过。
- ZIP 恢复会建立新的 dataset，且同步默认关闭；不要未经确认就再次启用并宣称回到了原云端工作区。Codex需先处理其与原工作区的身份关系。

## 六、这种恢复测试的好处与限制

| 方面 | 具体意义 |
| --- | --- |
| 真实恢复价值 | 检验数据是否能在失去原本地库后回来，接近误删 App或更换设备后的需要。 |
| 链路覆盖 | 能暴露上传后找错 zone、首次下载、关系重建、原图缺失、下载状态不落盘等问题。 |
| 设备成本 | 可以只用一台手机完成，已有备用设备时则可保留原机，降低唯一副本风险。 |
| 本地代价 | 会丢失未上传/未备份内容、本地同步元数据、待处理分享及部分设备设置；也可能丢失排错所需现场。 |
| 安装变量 | 同版 TestFlight是否仍可安装、实际 iCloud账户、共享容器残留或系统恢复可能影响“真正空安装”的判定。 |
| 范围限制 | 不能替代两台设备同时编辑、冲突解决、实时推送、离线多次修改、账户切换或跨版本迁移验证。 |

当前代码和既有合成测试提供了恢复路径的基础，但没有证据证明这次 Production新装已实测通过。现有 `SyncProductIntegrationTests` 明确采用 value-array handoff，不调用 enable/start/CloudKit，并直接给两个测试库注入相同 dataset；不能用这些测试替代本 SOP 的真实验收。

## 七、最小结果记录与 Codex交接

本表由实际执行者填写，当前全部为未执行：

| 项目 | 记录内容 | 当前状态 |
| --- | --- | --- |
| A：Production | 实际容器、部署时间、当前差异、部署后字段核对 | NOT_RUN |
| B1：原队列 | 起止时间、起止 pending、完成时间、原内容抽查 | NOT_RUN |
| B2：增量 | 唯一测试记录标识、v1/v2及照片、自动/手动收尾 | NOT_RUN |
| C0：身份 | 当前 active dataset 是否默认、同一私有 zone、取证方式 | NOT_RUN |
| C1：备份 | App 外路径、文件完整性、媒体校验、是否实际预演导入、同版可安装 | NOT_RUN |
| C2/C3：恢复 | 空库证据、恢复内容/数量/原图、离线重开、对照差异、v3同步 | NOT_RUN |

私人 ZIP、数据库、原图和完整诊断留在私有位置；仓库只记录脱敏技术结论及摘要。给 Codex描述实际完成项，不把计划步骤或按钮点击当成成功结果。

可按真实状态补全以下简短交接文字；这是模板，不会自动授权或执行部署、卸载及云端写操作：

```text
请读取 plan/icloud-production-incident-20261109 的
Docs/ICLOUD_PRODUCTION_DEVICE_TEST_SOP_20261109_ZH.md 和上一份故障分析。
手机仍为 Build19 / 4d4fc8127。
我实际完成的步骤和结果是：[填 A、B1、B2 的真实结果及时间]。
请核对这些证据，更新原 PR19 的状态；若失败，先定位具体错误。
下一步想测试删除重装恢复，请先只读确认当前实际 Production dataset/zone
是否与新安装默认 A002 匹配，并验证我已另存的完整备份。
若当前是 ZIP 恢复产生的随机工作区，先说明并处理重新找到旧工作区的问题；
不要把待同步0当成恢复通过，不替我删除 App、清本地数据或改云端记录。
```

## 八、固定源码依据

以下均绑定安装 SHA `4d4fc812739fb51394364f4c5e629ff7cd42ea4f`，行号不应用于后续修改版本。

- [SyncPersistence.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/Sync/SyncPersistence.swift)：36–40 默认工作区；113–120、137–139、235–238 ZIP 恢复隔离新身份；278–303只为已有本地 ObjectState生成删除版本。
- [SyncProductCoordinator.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/Sync/SyncProductCoordinator.swift)：149–153真实新建使用环境默认身份；174–208首次建区与既往尝试恢复；235–237手动重启 session；436–459完整 ACK；500–508成功判断；548–636下载完整性与持久发布。
- [SyncCloudTransport.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/Sync/SyncCloudTransport.swift)：179–200私有库和 fresh engine；216–236先发再取且限定 zone；339–345、409–421拒绝物理删除；354–358只接受当前工作区事件。
- [CloudRecordCodec.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/Packages/SyncFoundation/Sources/SyncFoundation/CloudRecordCodec.swift)：8–15 schema及 zone命名。
- [ImportExportService.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/ImportExport/ImportExportService.swift)：123–188导出及待分享计数；224–335构建归档与原图校验；371–413预览/导入要求空目标；726真实导入触发新 dataset。
- [TransferModels.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/ImportExport/TransferModels.swift)：备份 v12、manifest、各类 objectCounts与媒体摘要。
- [SyncProductIntegrationTests.swift](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOSTests/SyncProductIntegrationTests.swift)：8说明无真实 CloudKit调用；29–36注入相同测试身份；95–137空库接收、重复/乱序与持久化；169–194原图齐备才发布。

本轮完成静态代码核对、官方规则核实和测试步骤整理；没有修改产品、操作 Apple后台、删除/安装 App或执行真实 Production测试。本文为纯文档，不重跑不受影响的完整原生测试套件。
