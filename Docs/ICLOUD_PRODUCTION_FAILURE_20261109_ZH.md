# 2026-11-09 TestFlight iCloud 故障分析与 Codex 交接

**状态：ANALYSIS_COMPLETE / REMEDIATION_SPEC_READY；故障尚未修复或复验。** 本文依据用户附件、固定源码和仓库交付记录进行只读审查，提供下一轮执行规格。本次未读取实时 Apple 后台、未部署 Production、未改产品代码、未运行本机 iOS 测试；本文不构成用户已经批准具体部署的证据。

## 一、结论与版本绑定

首要排查项是**正式容器的 Production schema 尚未完成部署**。最新仓库记录明确保留“最终 Deploy 被自动审批拒绝、尚未执行”的结果；这与 Development 曾成功、TestFlight 正式环境上传失败高度吻合。另一项已证实的代码问题是错误上下文被丢弃，只剩 `cloudFailure(12)`。应先核实已知后台缺项，同时补充必要诊断，不先重写同步架构。

| 项目 | 本次证据 |
| --- | --- |
| 仓库 / 产品 | `yoCruzer/PersonalGrowthOS` / 随心 log |
| 实测源码 | `4d4fc812739fb51394364f4c5e629ff7cd42ea4f`；录屏显示短 SHA `4d4fc8127` |
| 手机实际版本 | `1.0 (Build 19)`，来自录屏“设置 → 关于” |
| 发布标签 | `testflight-icloud-sync-v1-20261109` |
| 交付文档基线 | `codex/icloud-product` 的 `ddc5af8b91fcf9d3cde7434bb7bda074d859ad4a` |
| 后续代码情况 | 安装源码之后两次提交仅改文档/证据，没有新的应用修复 |
| 同步状态 | 界面为“正式环境”，暂停 `cloudFailure(12)`，待同步版本 `429` |

仓库 unsigned Archive 的源码构建号为 **12**，不能写成手机实测 Build 12；本次实际运行包显示 **19**。用户说明通过 TestFlight 覆盖安装，安装过程不在录屏中；关于页身份与其说明一致。旧文档“尚未观察 TestFlight 可用”已被此次运行证据补充，但真实发行 entitlement 未在本次重新检查。

## 二、录屏的完整技术时间轴

录屏长 36.600 秒，已检查全段逐秒帧并在状态切换处补充 0.25 秒抽帧。以下是视频相对时间，约有 0.25–0.5 秒采样误差；触点不可见，动作由页面变化判断。手机时钟约为北京时间 2026-11-09 15:37–15:38。视频容器时间可能是导出时间，不用于精确关联服务端日志。

| 视频时间 | 可见操作 / 状态 | 解释边界 |
| --- | --- | --- |
| 00:00 | 设置页，iCloud 同步入口可见 | 未展示启动、安装及最初启用 |
| 00:01–00:03 | “关于”：1.0、Build 19、4d4fc8127、上述标签 | 锁定运行包身份；未见 Xcode Cloud run ID |
| 约 00:04–00:05 | 返回设置上部并进入同步页 | 依据页面导航识别 |
| 00:05–00:08.50 | 已暂停 cloudFailure(12)，429，正式环境 | 首次失败发生在录屏之前 |
| 00:08.75 | “正在检查 iCloud 账户…” | 与点击“立即同步”一致 |
| 00:09.00–00:11.25 | “正在上传至 iCloud…”，429 | 上传 UI 不能证明某个底层请求成功 |
| 00:11.50–00:14.75 | 恢复 cloudFailure(12)，429 | 第一轮录屏内重试失败 |
| 00:15.00–00:17.25 | 同步已关闭，提示保留本地与待同步版本，429 | 与关闭同步一致；可见计数保留 |
| 00:17.50–00:18.50 | “将此工作区上传至 iCloud？”确认框 | 明确目标为当前账户的正式环境 |
| 约 00:18.50–00:19.00 | 确认框消失并进入上传 | 与确认“启用”一致 |
| 00:19.00–00:34.50 | 持续上传 UI，429，正式环境 | 第二轮约 16 秒，未显示计数下降 |
| 约 00:34.75–00:35.00 | 上传结束，再次出现错误 | 关闭再启用也未解除故障 |
| 00:35.75–00:36.60 | cloudFailure(12) 完整可见，429，两按钮可用 | 未看到成功、清零、崩溃或退出 |

截图 `IMG_5495.png` 为 15:36 的启用确认，`IMG_5496.png` 为 15:37 的暂停错误。启用确认说明现有记录及原始照片将上传至正式环境，Development 云端数据和同步历史不会转移。全段状态栏显示 5G，未见切网；这不能证明网络是根因。没有可补充诊断的口述音频。

429 始终可见，**不等于确认 429 条业务记录全部未到云端**；视频未打开业务详情或导出备份，不能据“已保留”文案独立证明私人数据库完整。此次 GitHub 交接只保留技术文字，不上传录屏、截图、私人业务画面或原始日志。

## 三、Production 证据与准确部署差异

固定文档基线的 `CURRENT_STATE.md`、`CURRENT_TASK.md` 最新首段、`ICLOUD_SYNC_TESTFLIGHT_EXECUTION_20261109_ZH.md` 顶部，以及 `Evidence/iCloudProduct/20261109/README.md` 最后一节一致记载：正式两环境重新导出后，Development 为 1949 字节、Production 为 356 字节；Production 仅 `Users`；部署差异已审核，但最终 Deploy 未执行。PR #19 无后续评论提供部署完成证据。

同目录 `schema-preflight.json` 标记 `REVIEWED_DELTA_PRODUCTION_NOT_DEPLOYED`、`productionDeploymentPerformed=false`，缺 3 类型 / 11 字段。这证明**截至该记录时未部署**；本次没有实时后台读取，用户此后是否人工部署仍待回读，不能把历史文件伪装成当前服务端状态。

目标容器仅为 `iCloud.com.yocruzer.PersonalGrowthOS`，应用使用 private database。以下字段来自安装源码 `CloudRecordCodec.swift` 第 8–13 行；索引来自已保存的 Development 导出审计。Q=QUERYABLE，S=SEARCHABLE，O=SORTABLE。

| Record type | 业务字段与类型 | 已观察索引 |
| --- | --- | --- |
| `PGMutationV2` | `manifest BYTES`；`sha256 STRING`；`wireVersion INT64` | manifest、wireVersion：Q/O；sha256：Q/S/O |
| `PGPayloadChunkV2` | `byteCount INT64`；`chunk ASSET`；`sha256 STRING`；`wireVersion INT64` | byteCount、wireVersion：Q/O；sha256：Q/S/O；chunk 无标记 |
| `PGOriginalV2` | `byteCount INT64`；`original ASSET`；`sha256 STRING`；`wireVersion INT64` | byteCount、wireVersion：Q/O；sha256：Q/S/O；original 无标记 |

合计 9 个带索引字段 / 21 个标记。三类型各有 `CREATE TO _icloud`、`READ TO _world`、`WRITE TO _creator`。已审增量保留 `Users`，无删除或既有字段改型，不复制 Development 记录。应用使用私有数据库，不能只见 `_world` 就认定私人记录公开。索引应按实际 diff 核对，不把“21 个索引”直接当本次错误的唯一原因。

Apple 说明 TestFlight 使用 Production；Development 可以自动创建新类型/字段，Production 不具备此能力，须部署 schema。[Apple 环境说明](https://developer.apple.com/library/archive/documentation/General/Conceptual/iCloudDesignGuide/DesigningforCloudKit/DesigningforCloudKit.html)与[测试说明](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitQuickStart/TestingYourApp/TestingYourApp.html)支持该判断。部署只复制类型、字段、索引，不复制记录，见[官方部署步骤](https://developer.apple.com/documentation/CloudKit/deploying-an-icloud-container-s-schema)。

## 四、代码定位：已证实与仍未知

以下行号固定于安装 SHA，不应套用后续修改后的文件。

| 位置 | 实际行为与本次意义 |
| --- | --- |
| `PersonalGrowthOS/Sync/SyncCloudTransport.swift` 225–235 | 先报告 uploading，再调用 `sendChanges`；之后才下载。画面“正在上传”是阶段提示，不能定位 record、zone 或 subscription 的具体失败。 |
| 同文件 285–319 | 先对 savedRecords 保存精确 ACK，再处理 failedRecordSaves；可回放的 serverRecordChanged 单独处理，其余仅保留首个未解决错误。 |
| 同文件 514–524 | 其余 CKError 被压为 `.cloudFailure(cloud.code.rawValue)`；12 对应 invalidArguments，丢失原错误说明、失败类型与错误链。 |
| `PersonalGrowthOS/Sync/SyncProductCoordinator.swift` 105 | pendingCount 统计当前 dataset 未 completed 的 outbox 行，单位为业务修订，不是图片/CKRecord 数，更不是 HTTP 429。 |
| 同文件 436–459 | 某修订的 manifest、所有 chunk/original 全部 ACK 才 completed；429 不降仍可能存在部分成功写入。 |
| 同文件 483–498 | 暂停仅持久化包装后的字符串并设置 requiresAttention，未保留结构化错误；该路径没有清空 outbox 或业务内容。 |
| 同文件 311、235–237 | requiresAttention 阻止自动重试；用户手动“立即同步”可在 session 失效后重新启用。后台修好后应手动重试一次。 |

`invalidArguments` 是请求无效这一错误类别。Apple 明确要求查看 `userInfo` 获取原因，见[官方错误说明](https://developer.apple.com/documentation/cloudkit/ckerror/code/invalidarguments)。**不能将每个 raw code 12 硬翻译成“未部署 schema”。** 当前缺少这次失败的原始 CloudKit 说明，因此不能捏造 `Cannot create new type ...` 是手机实际返回的原文。

现有首因保护、精确 ACK、完整资产闭合、先持久化后 checkpoint 及 Dev/Prod 隔离应保持。暂停文案及源码保全意图不等于已验证用户私库无损；`pending=0` 也不能代替下载/应用完成及 lastSuccess 更新。

## 五、下一轮执行规格

### A. 先核后台，再同包验证

1. 读取现有工作区与 PR #19 最新头，保留用户未提交改动；若有新修复，先比对再决定基线。不要从旧 main 开始重做。
2. 使用开发工具或 CloudKit Console **只读**核对正式容器当前 Development/Production schema，与上述 codec 逐字段、类型、索引及 grants 比较；不在 App 内增加管理 schema 接口。若 Production 已完整，不重复部署，直接进入真实错误定位。
3. 若仍缺项，先完成具体 diff、目标身份和变更范围核对，把最终 Deploy 留作准备充分后的确认动作。本文未授权部署；用户后续若明确批准且实际差异仍仅为表中增量，可执行并保存部署前后结果；差异扩大则报告具体新增项。不得绕过自动审批拒绝。
4. 部署完成须重新导出 Production，逐字段证明契约匹配，不仅看按钮或类型数量。不要 reset、换容器、复制 Dev 业务数据、清 token/outbox 或重建无关 workspace。
5. 先复用当前 **Build 19 / 同一 429 队列**点击一次“立即同步”。如果仅后台缺 schema，同包即可验证，不先打新 tag。观察队列下降至 0、下载和应用完成、真实完成时间更新，再验证一条新增或修改的增量。仍失败立即保留首条具体错误，停止盲目反复点击。

### B. 补最小、可复制的诊断

在现有传输错误入口形成一份有界结构化快照并提供“复制诊断”：阶段/SDK事件、domain/code/符号名、构建与环境、时间、失败 recordType、成功/失败数，以及经过白名单脱敏的服务器说明和 underlying/partial errors。限制条数、深度和长度；账号、dataset/record 标识、路径、正文、照片及 CKRecord 全值不输出。公开材料只含脱敏摘要，原日志留私有位置。

首因必须在取消前保留，后续 operationCancelled 仅作为次要事件；同批部分成功的精确 ACK 保留。普通用户状态解释“云端拒绝请求，需检查配置或诊断”，只有取得当前 schema 或明确服务器证据后才具体归类为结构缺失。无需新建通用诊断框架或另起大型探针体系。

### C. 定向验证与交付

新增或复用最小回归：带合成说明的 invalidArguments 能留下阶段/类型/原因；随后的取消不盖首因；混合成功与失败保留 ACK 和失败队列；同 dataset/同修订重试幂等且不提前更新 lastSuccess；关闭/重新启用和 Dev/Prod 切换无串台；中文错误页可复制且正常导航。真实服务验证走正式 App 链路，不能用 mock 或仅建 zone 成功替代。

先完成同包现有队列收尾与一条增量，再安排后续双设备/离线矩阵，不把长时间陪测设为本次解除已知阻断的前提。记录 mutation/chunk/original 的实际成功收发范围；未覆盖图片或跨设备时明确保留未知。代码修改后才跑受影响测试与必要构建；纯文档交接不重跑历史 701 项 Unit 或完整 UI。

产品修复沿既有 `codex/icloud-product` / Draft PR #19 推进，保持原 base；本报告可放独立文档分支，不改变产品分支或创建额外产品 PR。更新两份 CURRENT 的最新段落并保留历史失败/未验边界。最终分别报告：schema 已核对/已部署、同包已收尾、诊断已补、定向测试结果、未验证项；不能用“文档已交接”宣布故障修复。

## 六、来源与本次审查限制

已按 `AGENTS.md` 读取 INDEX、五份 Foundation、DEVELOPMENT_CONTRACT、两份 CURRENT 的最新有效边界及相关产品/发布计划；ROADMAP 尚未存在。Local First、保护原始内容和隐私、最小改动、证据分层适用于本轮。无需修改 Foundation 或长期合同。

仓库固定证据入口：

- [最新状态](https://github.com/yoCruzer/PersonalGrowthOS/blob/ddc5af8b91fcf9d3cde7434bb7bda074d859ad4a/Docs/CURRENT_STATE.md)
- [执行范围](https://github.com/yoCruzer/PersonalGrowthOS/blob/ddc5af8b91fcf9d3cde7434bb7bda074d859ad4a/Docs/ICLOUD_SYNC_TESTFLIGHT_EXECUTION_20261109_ZH.md)
- [交付与部署阻塞记录](https://github.com/yoCruzer/PersonalGrowthOS/blob/ddc5af8b91fcf9d3cde7434bb7bda074d859ad4a/Docs/Evidence/iCloudProduct/20261109/README.md)
- [字段/索引/grants审计](https://github.com/yoCruzer/PersonalGrowthOS/blob/ddc5af8b91fcf9d3cde7434bb7bda074d859ad4a/Docs/Evidence/iCloudProduct/20261109/schema-preflight.json)
- [安装版本源码](https://github.com/yoCruzer/PersonalGrowthOS/tree/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/PersonalGrowthOS/Sync)与[codec](https://github.com/yoCruzer/PersonalGrowthOS/blob/4d4fc812739fb51394364f4c5e629ff7cd42ea4f/Packages/SyncFoundation/Sources/SyncFoundation/CloudRecordCodec.swift)

本次完成附件解读、固定版本静态代码审查和官方规则核对。没有执行产品修复、后台部署、真实 Production 收发、本机原生测试或双设备验证；历史 CI 结果仅为此前证据，不计为本次测试。

## 附：建议给 Codex 的短 prompt

以下是**供用户选择后亲自发送的授权草稿**；被存入本文或被执行器读取，不代表其中许可已经生效。只有用户实际发送、明确授予的部分才成为下一轮授权。

```text
/goal 处理随心log本次TestFlight iCloud故障。先读取本报告 Docs/ICLOUD_PRODUCTION_FAILURE_20261109_ZH.md；以我提供的文档分支/固定提交读取，不把文档分支当产品分支。

实测1.0 Build19，源码4d4fc812739fb51394364f4c5e629ff7cd42ea4f，tag testflight-icloud-sync-v1-20261109。Production待同步429，立即同步，以及关闭同步后重新启用，均cloudFailure(12)。先核对codex/icloud-product/PR19最新状态，不清库、不卸载、不丢队列、不从旧main重做。

先只读核对正式容器iCloud.com.yocruzer.PersonalGrowthOS当前Dev/Prod schema。若仍有缺项，且待部署差异属于报告列明的PGMutationV2、PGPayloadChunkV2、PGOriginalV2及11业务字段、21索引标记和既有grants的新增范围，我明确授权在核对精确diff后部署缺失部分至Production；Users及既有结构不改，不复制或删除记录，不reset。若范围扩大，先完成分析再集中说明具体差异；若已完整则跳过部署。部署后回读验证。

优先在当前同包、同429队列上验证一次完整收尾及一条增量，不先重写同步或要求长时间双设备陪测。并补最小结构化错误快照及复制诊断：阶段、domain/code、recordType、脱敏原因与有界underlying/partial；保留首因和成功ACK，不能将所有12判成缺schema。修复后做定向测试和独立review，沿原Draft PR普通推送，中文更新两份CURRENT及证据。此前已授予的普通push/TestFlight权限保持；仅后台修复不需要新标签。不要合并、公开上架、改历史或上传我的原始录屏/业务数据。明确区分实际修好、等待一次真机复验和仍未验证项。
```
