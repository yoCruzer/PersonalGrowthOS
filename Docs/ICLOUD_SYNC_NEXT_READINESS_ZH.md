# 2026-11-08 更新：两环境导出已收到，正式App关联仍待核对

Owner刚提供两份原始CKDB及对应正式容器截图。两文件逐字节相同、各356B，SHA256均为`60fec48392126eab598a05dbe0f7f9557494a992df8fb62295ccd3752a7768db`，仅Users7fields。与实际v2 SDK候选的差异是新增3种业务类型/11个业务字段，系统字段与权限仍单独审查，不生成可部署DDL。详见[本轮正式结构审查](ICLOUD_SYNC_FORMAL_SCHEMA_REVIEW_ZH.md)及[原始来源记录](Evidence/iCloudSyncFoundation/20261108/formal-schema-intake/receipt.json)。

**不需要重复导出。** 现在只缺正式App `com.yocruzer.PersonalGrowthOS` 的iCloud/CloudKit support/Push和已关联容器的只读结果；两张Console截图不能替代App ID能力关联。云数据未查询，P0/P1/P2保持未通过。离线比较与锁定的Development SDK适配准备已完成本机及远端验证，实际执行仍待后续具体门禁。

剩余只读动作预计2–3分钟，手机前台/数据线均0分钟。前置条件是能登录对应Apple Developer团队；密码/验证码由Owner在Apple界面输入。

1. 在Apple Developer的Certificates, Identifiers & Profiles → Identifiers，打开Bundle ID精确为`com.yocruzer.PersonalGrowthOS`的正式App，确认所选Team与项目Team一致。
2. 只读查看iCloud是否启用、是否包含CloudKit support、Push Notifications是否启用。若需展开iCloud关联窗口，只查看目前已选容器，不改勾选、不Save。
3. 回复四项实际结果即可：`iCloud=…；CloudKit support=…；Push=…；容器=…`。目标容器为`iCloud.com.yocruzer.PersonalGrowthOS`；未显示、无法查看或尚未配置均照实记录，不把未知填通过。

完成判据是正式App的当前能力及容器关联有明确只读结果；没有缺项需要变更时不安排额外操作。后续签名准备与Development执行清单依赖此结果，无法现在合并成可执行的云写入步骤；Production仍需在Development覆盖/读回后形成精确差异并另行批准。

下面保留2026-11-07准备记录，其中“待导出/Production未查看”描述的是当时状态，以本段新证据为准；原导出步骤仅作复现说明，不是要求Owner再做一遍。

---

# iCloud Sync 后续开发：正式 wire 与 Apple 门禁准备

日期：2026-11-07（Asia/Shanghai）。只读评估基线：`e57fe3503995771a89754fbc4077ea16627c15be`，后续工作树 `/private/tmp/PersonalGrowthOS-icloud-foundation`。本文件区分仓库事实、已有 Owner 确认与尚未完成的外部验证；不是 Production 部署批准单。

## 当前授权及依赖

Owner 本轮明确授权连续完成后续开发、测试、修复、独立审查和可评审交付。因此旧 G1 Goal 的“只做实验／批次结束停止”不再阻挡本轮代码侧工作。正式容器配置变更、Production 部署/写入、合并、Archive、TestFlight及发布边界仍保留。

G1 保持 `OWNER_ACCEPTED_PHONE_SCOPE`：6份手机原始报告、27条命令通过；此前基础双向同步与真实冲突解决收敛有效。Mac CK_2 为接受的非阻塞例外，原失败保留，不继续排障；VPN 原因未独立证明。完整真实故障矩阵仍有未覆盖项，见 [Owner 收口](ICLOUD_SYNC_G1_OWNER_CLOSEOUT_ZH.md)，不借后续离线代码测试改写。

P1/P2 未通过阻挡正式云写入和大规模领域接入，但不阻挡：正式 wire 候选实现与本机验证、V16/v12 合成基线升级准备、同事务写入接缝清点、现存产品回归修复、独立审查。所有准备只使用显式合成数据和临时目录；不读取日常主库。

## 本轮只读核验

| 核验对象 | 可重复仓库事实 | 限制 |
| --- | --- | --- |
| 正式身份 | `PersonalGrowthOS.xcodeproj/project.pbxproj`：Team `83SKX2PM7B`，Bundle ID `com.yocruzer.PersonalGrowthOS`，iOS 17.0 | 不是当前门户/profile证明 |
| 正式能力 | `PersonalGrowthOS/PersonalGrowthOS.entitlements` 只有 `group.com.yocruzer.PersonalGrowthOS` | 未添加CloudKit；不由源码推断门户未配置 |
| 本地数据库 | `PersistenceFoundation.swift` 的最新版本为 V16；两种 factory 均显式 `.none`；已有历史迁移链保持 | 未运行新同步迁移，不得改写V16定义 |
| 写入协调 | `ExternalCaptureImport.swift` 的 `StorePublication` 是按规范根路径的进程内锁；多服务有自己的context/save/rollback | 锁不是事务outbox；通知也不能替代outbox |
| G1 wire | `Protocol.swift`：每对象完整历史最多512 mutations、envelope最多262144编码字节、文字32768 UTF-8字节；仅一个可选图片引用 | 不是可直接用于全部领域的容量契约 |
| 图片差异 | G1单图上限8388608字节；正式 `MediaStore.maximumOriginalByteCount` 为25MiB；Entry最多9图 | 正式wire必须覆盖已合法保存原图，不得靠压缩或截断通过 |
| 聚合容量 | `NetWorthFoundation.swift` 允许快照最多10000明细；结构中还有冻结历史、未知金额与来源状态 | 不可把完整快照盲塞一个G1普通payload字段 |
| 实验隔离 | G1 Binding固定实验容器与Development；源entitlements也是实验容器、Development | 不能作为正式容器签名/Production证据 |
| 正式资源与本轮门户 | 历史Owner确认注册；本轮主代理只读检查Safari现有CloudKit会话，实际Team `83SKX2PM7B` 的容器列表包含正式容器，选择该容器Development → Record Types，仅见Users、7 fields | 未Query Records；正式App关联及Production schema仍待核验，不重新要求注册 |
| CLI能力 | 本机 `xcrun cktool export-schema --help` exit0，支持team/container/environment/output-file | 只看帮助；没有执行云导出、登录或读取记录 |

实际检查命令包括 `git rev-parse HEAD`、限定源码的 `rg`/`sed`、entitlement读取和 `xcrun cktool export-schema --help`。本评估没有启动客户端、切换系统账户、修改Apple能力或请求业务记录。主代理补充的上述门户观察未读取业务记录；尝试Export前Safari被并发切到其他页面，旧元素失效，导出未发生。为避免干扰Owner操作已停止浏览器控制，未继续尝试，未读取其他项目数据。Development原始schema文件仍未取得，Production未打开；只见Users不能代替字段清单导出或P0通过。

## P0冻结前必须解决的工程项

1. **有界单条记录与持续增长历史分开。** G1每次发送对象全历史会在512条或256KiB停止。正式候选须定义不可变mutation身份、分页/分片或独立asset策略，明确缺页、重复、乱序及部分失败行为；不得删除旧候选解决容量问题。
2. **完整聚合发布。** manifest必须绑定聚合身份、协议版本、全部成员/资产的身份、长度与摘要。只有依赖当前有效版本、全部成员与原图核验完成后才能发布。缺成员、未知版本、摘要错误留存待处理，不能回退旧活版本或关闭启动完整性检查。
3. **身份和设备状态分开。** 稳定typed对象ID、mutationID与业务自然键分别处理；container/environment/account/dataset/generation须参与本地分区与回调栅栏。account指纹、SDK token/changeTag/system fields、device权限/Widget公开授权不进入业务备份。备份缺谱系时先恢复独立数据集。
4. **保存先于网络。** 业务事实、精确版本与outbox同一store显式save；旧ACK只确认实际上传版本。网络、文件下载与权限请求不得挤入事务；cancel后所有旧发送/安装/ACK均受epoch拒绝。
5. **容量使用产品上限。** 本机验证至少包含25MiB原图、9图Entry、10000行净资产编码、长期mutation历史；限制按编码字节而非字符计数。超过资源预算要明确保留输入及错误，不截断或伪造“完整”。
6. **真实codec生成清单。** 候选类型、字段、类型、索引、权限说明及其hash应由实际codec样本导出。未使用query时不添加猜测索引。代码候选与服务器Development逐字段读回一致后，才可提出P0冻结；单纯编译/本机CKRecord构造不是P0通过。

最小连续代码切片：先实现与现有App和G1安装隔离的正式协议候选及真实CKRecord codec；用纯合成夹具验证绑定、asset/manifest闭合、幂等、同ID异字节拒绝、未知版本、容量正负界限和乱序。与此同时准备真实V16/v12基线夹具与写入接缝。随后按依赖接持久outbox/inbox及小纵向领域，再准备正式Development差异；不能因小包测试通过就宣布39实体完成。

## 本轮代码侧候选已完成的独立复核

`Packages/SyncFoundation` 已实现独立协议/CloudKit本地codec候选v2：每mutation独立记录、typed对象UUID、有序payload chunk与独立原图CKAsset、逐块及完整聚合hash、资产闭合校验、内存epoch fence，以及从实际SDK记录生成字段清单的 `SyncSchema`。它未接入正式App、数据库或云调度，不改变手机SyncLab。

初版16MiB payload不能覆盖真实合法净资产容量；其8项独立测试及schema保留为[v1历史证据](Evidence/iCloudSyncFoundation/20261107/review/README.md)，不算作v2通过。当前v2采用4MiB chunk、最多32块、128MiB总payload候选预算和64KiB manifest。精确V16源码生成的49,190,297字节合法合成聚合已通过12块SDK编解码、流式hash与逐字节重组。

最终v2独立新增12项native测试12/12通过，修复并保留源变化未拒绝及Foundation临时内存累积的原红例/测量；逐块释放后本机128MiB流式prepare/verify测试进程RSS40,058,880字节，4MiB对照44,236,800字节，不把该结果泛化为所有设备的内存保证。schema CLI确定性/已有目录拒绝及完整字段/hash、SyncPayloadProbe正负例通过，详见[v2独立终审](Evidence/iCloudSyncFoundation/20261107/review-v2/README.md)。当前expected schema SHA256为 `6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003`，仅本地候选，不是部署批准单。

128MiB是候选资源预算，字符数量上限不等于任意Unicode组合序列的字节上限；超预算输入必须保留源并明确拒绝，后续分段/版本策略及各真实领域容量仍需验证。没有把协议包通过写成持久outbox、V16升级、真实云状态、39实体投影或P0完成。

## 不依赖导出的批次准备器已实现

独立终审后继续完成[正式Development批次准备器](ICLOUD_SYNC_FORMAL_PROBE_PREPARATION_ZH.md)：固定合成计划、实际SDK六条回放、只读签名preflight，完整包34/34、独立22条CLI及并发签名替换负例、本机iOS17共享核心编译通过。候选独立Bundle ID未注册/关联/签名，工具没有网络通路。计划/记录及字段预期可供后续真实适配器复用；不是双端客户端已完成，也不改变下面P0/P1/P2状态。

## 正式门禁状态

| 门禁 | 当前结论 | 解除条件 |
| --- | --- | --- |
| P0 正式wire冻结 | **未通过**；G1类型不是正式冻结候选 | 最终codec/容量/manifest审查、本机正负例及对应Development实际字段覆盖；代码和schema hash可追溯 |
| P1 正式Production schema | **NOT_RUN / 未授权部署** | 正式容器当前两环境导出、精确差异、Owner批准后实际部署及回读比对 |
| P2 正式Production真实往返 | **NOT_RUN / 未授权写入** | 正式容器Production签名的隔离客户端、专用合成dataset、双向文本/原图/修改/删除意图/重开验证 |
| P3 正式候选配置 | **NOT_RUN** | 正式App最终候选实际签名/profile/container/environment/schema版本一致；不以实验App替代 |
| P4 TestFlight验收 | **NOT_RUN / 未授权发布** | 另获发布授权后，同候选实际设备验证；可评估iPhone+Apple silicon Mac，不要求第二台iPhone |

P0候选后续发生字段、索引、容量或协议语义变化时，重新评估相关门禁。接受G1 CK_2例外不等于放行正式P1/P2。

## 可以立即集中完成的Owner只读操作

目的：补齐正式容器两环境的真实schema导出和正式App关联，消除部署差异的未知输入。正式容器存在及Development仅Users的本轮只读观察已完成，不需重复证明；仍需完整导出和Production只读检查。**现在只读取，不保存能力变更、不初始化schema、不部署、不查询记录。** 前置为Owner已有Apple Developer/CloudKit Console访问权限；密码和验证码只在Apple界面输入，不粘贴到聊天。

预计5–10分钟；手机前台0分钟，数据线0分钟；若Apple要求身份验证，仅需Owner完成其验证提示。不要求haha登录或切换iCloud。

1. 打开 [Apple Developer Identifiers](https://developer.apple.com/account/resources/identifiers/list)，选择Team `83SKX2PM7B`，打开**既有** `com.yocruzer.PersonalGrowthOS`。只查看并记录iCloud/CloudKit、Push及关联容器；不点Save，不更改Bundle ID/App Group。预期正式容器为Owner已确认注册的 `iCloud.com.yocruzer.PersonalGrowthOS`；如关联不同，记录实际值后停止猜测，不另建。
2. 打开 [CloudKit Console](https://icloud.developer.apple.com/)，选择相同Team、准确正式容器。仅查看Schema，不进入Records。分别记录Development和Production的record types、字段类型、索引与权限；导出两环境schema文件，保留导出时间和环境说明。禁止点Deploy/Reset/Import或创建记录。
3. 如果Console提供schema导出，直接保存两份只含结构的文件。如果没有可用导出入口且本机**已经**安全配置cktool访问凭证，可在Mac终端使用下列已核对参数的只读命令；本轮不要求创建或把management token发给Codex。无现成凭证时保留脱敏的Schema视图和访问结果即可，导出仍标待补。

```sh
schema_dir=$(mktemp -d /private/tmp/PGOS-FormalSchema.XXXXXX)
xcrun cktool export-schema --team-id 83SKX2PM7B --container-id iCloud.com.yocruzer.PersonalGrowthOS --environment development --output-file "$schema_dir/development.ckdb"
xcrun cktool export-schema --team-id 83SKX2PM7B --container-id iCloud.com.yocruzer.PersonalGrowthOS --environment production --output-file "$schema_dir/production.ckdb"
shasum -a 256 "$schema_dir/development.ckdb" "$schema_dir/production.ckdb"
```

完成判据：两份真实schema及摘要（或准确的权限/导出失败状态），精确Team/container/environment、正式App实际关联记录齐全。空schema、只有Users或无部署差异属于有效观察，**不是P0/P1通过**。公开交付只保留结构、hash和脱敏检查结果，屏幕中的账户姓名、邮箱、访问token与其他项目不提交。

## 后续外部操作为什么不能现在合并执行

上述只读窗口可以现在完成；正式Development能力/内容准备和Production部署窗口必须依赖已审候选，否则批准的不是最终可评审差异。到达该节点后，Codex先交付固定代码SHA、真实codec样本/schema hash、现状与目标的逐字段diff、签名验证客户端与固定合成dataset计划，再集中提交一份具体授权单。当前不请求“先同意一切Production操作”。

未来窗口应依次执行：已核实正式App/容器的必要能力配置与profile刷新 → 正式Development合成覆盖并回读 → 精确Production schema差异批准与部署 → P1回读 → 获批P2合成往返。任何阶段失败保留原件，只阻挡其依赖项；本机领域/迁移准备继续。

P2设备预计采用当前iPhone+Mac mini专用haha用户，运行前只读重新确认会话与同账户资格；不自动切用户、不退出日常iCloud、不卸载/清空现有SyncLab。签名隔离客户端与最终计划未准备前，不给出虚假的手机占用时长或预约窗口。P2手机时长、数据线时长及命令数量须随最终批次清单给出；P4只有获授权实际TestFlight候选后才能安排。Intel Mac仅为已核验工具链/系统可用时的替代端，不设为额外前提。

参考与既有权限边界：[Apple就绪门禁](ICLOUD_SYNC_V1_APPLE_READINESS_ZH.md)、[G1环境台账及后续核验](ICLOUD_SYNC_G1_ENVIRONMENT_ZH.md)、[修订审计](ICLOUD_SYNC_V1_AUDIT_ZH.md)。本文件没有把历史NOT_RUN视为永久停工，也没有将任何未知门禁改为通过。
