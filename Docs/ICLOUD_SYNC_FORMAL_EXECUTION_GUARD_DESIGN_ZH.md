# 正式 Development 固定批次：执行保护设计（未实现）

2026-11-08。本文是对当前 `FormalDevelopmentSDK` 的只读审计及下一实现切分，**不是已完成实现、云执行授权或 P0 通过证据**。

当前 Owner 已批准独立 Mac 探针的配置、Development 签名及离线核验。该授权不包含本设计所述的真实 CloudKit 账户资格读取、建 zone 或保存记录。当前 host 继续硬阻断 live；已有 `preflight` 的静态匹配结果、`signatureVerified`、传入的 `CKDatabase` 或任意本地布尔字段，均不能转化成真实执行许可。后续工程可在这个边界内持续实现、离线验证和独立审查，再为固定产物与计划集中提出精确执行窗口。

## 当前代码的确定事实与调用数量

依据 `Packages/SyncFoundation/Sources/FormalDevelopmentSDK/BatchRunner.swift` 和 `Transport.swift`，完整成功路径实际调用以下 **5 次 transport 方法**：

| 顺序 | runner 阶段 | SDK adapter 当前调用 | 对象范围 |
| --- | --- | --- | --- |
| 1 | `zone-probe` | `recordZone(for:)` | 计划 dataset 对应的 1 个精确 zone ID |
| 2 | `zone-save` | `save(CKRecordZone)` | 同一个新合成 zone |
| 3 | `assets-save` | `modifyRecords(saving:deleting:savePolicy:atomically:)` | 3 条：1 原图、2 payload chunk；删除列表为空 |
| 4 | `mutations-save` | 同上 | 3 条 immutable mutation：create、edit、tombstone；删除列表为空 |
| 5 | `exact-fetch` | `records(for:desiredKeys:)` | 上述全部 6 个精确 record ID |

两个保存批次均为 `ifServerRecordUnchanged`、`atomically: true`。tombstone 是新的逻辑删除 mutation，不是 CloudKit 删除操作。已有 zone、缺失/额外结果、部分失败、任何字节/身份不一致都会停止后续阶段。流程没有 query、枚举业务记录、订阅、删除或自动重试。

**5 是 SDK/transport 调用数，不是 HTTP 请求数。** SDK 内部网络实现和重试不能由此推断。当前真实运行过的这些 adapter 方法为 **0 次**；51 项既有包测试及独立 SDK 测试使用 fake transport。现有代码也没有调用 `accountStatus` 或 `userRecordID`。`FormalDevelopmentProbe` 的 6 条离线 codec 检查是另一个计数，不应当作 6 次真实云请求。

当前保护包括 MainActor single-flight、同一个内存 ticket 消耗、每个 await 前后的 epoch/cancel/原计划/asset lease 检查，以及独占创建的逐阶段证据。缺项包括真实资格 factory、持久消耗、跨进程锁、账户变更接入、显式 operation 取消句柄和远端结果未知状态。新进程可以重建 ticket；当前 `used` 标记不是持久的一次性约束。

## 最小实现顺序

### 1. 固定位置的持久批次记录与进程排他

先实现并离线验证一个由独立 Bundle ID 固定定位的每 OS 用户私有状态目录。它不得由 `--output` 或计划目录替换。目录访问沿用 fd/no-follow/类型/所有者检查，拒绝符号链接或身份变化。用固定锁文件的排他锁覆盖整个执行期；另外用排他创建并 fsync 的不可复用记录绑定批准的 run/dataset/plan SHA。仅有锁不够，因为进程退出会释放锁；仅有新输出目录也不够，因为另一个输出路径不能重新授权同一批次。

首次可能触发 CloudKit 的调用之前，先持久记录本次消费。失败、取消、崩溃均不自动释放消费资格，重启、不同输出路径、同账户下另一个本机进程或另一份相同客户端副本不得重跑同一批准批次。恢复时只读检查已有 intent/返回/terminal 证据，记录未完成状态；不自行恢复写入，不重新消耗旧批准。需要后续读取或新的批次时，再准备精确的新动作范围，不删除旧证据。

批准绑定至少包括：Owner 批次决定引用、有效窗口、正式 container/Development、schema candidate SHA、plan SHA/run/dataset、源版本/签名产物指纹、profile 指纹，以及本地账户分区。账户原始标识不进入业务 wire、公开报告或 Git。窗口同时检查墙钟和本次进程的单调时间；时间异常、过期或缺失绑定拒绝。该记录用于约束已经取得的明确 Owner 决定，不是通过写入任意 JSON 或 `approved=true` 来制造决定。

### 2. 当前运行进程的资格 factory

factory 必须从真实运行进程及其不可变 App 产物取得证据，不能只接受外部 preflight 的成功布尔值。核对有效代码签名、实际 Team/独立 Bundle ID、封存产物/profile 指纹、真实签名 entitlements，以及 profile 的平台、有效期、证书成员关系、当前 Mac 设备资格和可信来源。现有 CLI 的元数据匹配不等于这些全部检查已实现。

运行 entitlements 仍要求：正式 container 精确匹配、services 精确 `[CloudKit]`、environment 精确 `Development`，以及既定 sandbox/network client 能力。profile entitlement 按允许集解析；即使其列出 Production，也不得改变运行目标。此区别依据 [Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)。本轮兼容修复仅解决 profile 允许集的类型/匹配，不能因此打开 live。

通过这些检查并满足第 1 步的明确执行窗口后，factory 才能在内部构造固定 identifier 的 `CKContainer` 并选用 `privateCloudDatabase`。不增加 Production 分支、容器覆盖参数、调用者任意 `CKDatabase` 注入入口或跳过资格的开关。签名中的 Development 取值是环境约束的一部分；不能声称 CloudKit 返回一个尚未存在的“环境证明”接口。

本机 SDK 可用的进程签名检查入口包括 `SecCodeCopySelf`、`SecCodeCheckValidity`、签名信息读取及实际 entitlement 读取。实施时仍须核对相关本机 SDK 类型和适用条件；本文不要求新增通用签名框架。原始 profile、证书和设备信息留在本地私人证据，公开内容只保留必要的指纹和合格/不合格原因。

### 3. 账户窗口、可取消 operation 与真实结果状态

在批准窗口内，首次真实资格读取限定为该容器的 `accountStatus` 和 `userRecordID`，不读取业务记录。只有可用账户及预期测试账户 binding 匹配时才能继续。`CKAccountChanged` 通知立即使当前 epoch 失效，禁止后续阶段；通知可能在任意队列到达，应交由同一 actor 处理。首次正式容器账户 binding 必须在 Owner 已确认的测试会话中建立；不得将不同实验容器的 user record ID 或旧 G1 报告当成正式容器当前账户相等的证明。该只读资格结果仍不能自行批准后续写入。

每次数据 operation 发出之前检查本地资格、窗口、取消和账户 binding；每次 await 返回之后再检查，且保存原 run 的返回证据后才能决定是否继续。资格读取本身也是 CloudKit API 调用，必须计入单独的运行记录，不能宣称总调用数始终为 5。实施版本需固定有限的账户复核策略，并在最终执行清单列出其上界；不得出现无界轮询或“复核一次又递归触发下一次复核”。尚未实现该策略，因此本文不虚构未来资格读取总次数。

当前 async convenience adapter 没有由 runner 持有的显式 `CKOperation` 取消句柄。最小后续改动只覆盖上述 5 个阶段对应的精确 zone/record operation，不引入 CKSyncEngine、通用 outbox 或 39 域投影。每个 operation 绑定 run、epoch、阶段、预定 ID 集合，捕获逐项与整体返回。取消应先追加 `CANCEL_REQUESTED`，再请求取消；取消调用成功或收到取消错误都不能证明服务器未写入。

对已发出但结果不完整的请求，报告 `REMOTE_OUTCOME_UNKNOWN` 或同等明确状态；保留已知成功、已知失败和未知项。晚到结果只能追加到原 run，不能驱动新 run 或覆盖旧证据。部分保存后不做补偿删除、不覆盖、不自动重试。完整成功仅表示该批准的合成批次按精确 ID 和字节读回；真实报告应与 `INJECTED_TRANSPORT_ONLY` 区分，继续保留 P0 未冻结状态，直到实际 schema 观察和独立复核完成。

## 无法由本机代码保证的边界

- 固定路径锁和持久记录只约束同一 Mac、同一 OS 用户中遵守该协议的客户端。它们不能跨 Intel Mac/Mac mini、不同 OS 用户、复制后的 ledger 或任意改写客户端提供全局 exactly-once 保证。
- zone 不存在检查与 `save(zone)` 不是原子 create-if-absent。既定批次使用新的随机 dataset，并拒绝观察到的已有 zone；不能因此宣称解决了另一设备同时执行相同计划的竞态。当前不增加未审核的服务器锁 record/type/field。
- 账户变更可能发生在请求已发出之后。通知、重新查询和取消都不能与服务器提交组成事务，不能保证未产生远端效果。真实窗口必须使用稳定的专用测试账户会话，Owner 不在执行期间切换账户；出现变化即停止并保留未知结果。
- 路径绑定检查不承诺抵御同权限恶意进程进行任意 ABA 替换。原件和运行目录仍需私有不可变 lease；所有者、权限、源 hash 及持续 fd 绑定必须实际校验。

## 必需的真实外部许可与集中执行清单

现有配置/签名/离线核验许可不替代以下实际运行许可。代码、测试、签名候选和精确清单准备好后再集中提交，不逐个工程小步骤停下来：

1. 固定哪个 Mac、哪个 OS 测试会话和哪个测试 iCloud。若使用 `haha`，重新只读确认当前会话和账户，不假定旧登录仍有效。若不匹配，由 Owner 在 Apple/系统界面处理；不得自动切换用户、退出日常 iCloud 或读取日常业务数据。
2. 固定一次有效时间窗、批准的产物/plan/schema 指纹、全新 dataset/run、状态目录和私人证据位置；只允许指定的一台 Mac、一个会话、一个进程执行，禁止将同一批准计划分发到第二台机器运行。
3. 明确允许容器资格读取；以及上表的 zone 查询/创建、两批共 6 条合成记录保存和 6 个精确 ID 读回。首次 Development 保存可能生成对应的候选 record types/fields，这一副作用应写进具体许可。不得查询已有业务、删除任何数据或操作 Production。
4. 确定异常时停止且保留部分远端状态和本地原始证据。任何补读、补写或新批次按照实际未知项集中列出；不无限重试环境错误，不占用手机完成已有有效证据。

此阶段不要求第二台 iPhone；固定 Mac 批次本身手机前台及数据线占用为 0。若必须切换 Mac 会话，该交互与实际运行无法预先合并为“已通过”，必须先观察当前会话事实。最终操作时长应由完成的实现、资格检查数和有界超时给出，不以当前未实现代码估算成保证。

## 审查、测试与证据要求

每个切分均做与风险对应的独立正负复核：固定账户/有效签名的合成资格正例，以及错 Team、错 container、Production 运行值、profile 允许集误用、过期窗口和错产物指纹负例；同 plan 不同输出/不同进程/重启重放；崩溃发生在 fsync 消费前后、发请求前后、返回前后；各 await 暂停期间的账户/epoch/源/目录变更；取消后晚 ACK、部分失败、缺额外 ID、错误字节和报告写失败。

持久记录需真实多进程和崩溃注入验证，不能仅用内存 fake 证明。SDK transport 的真实服务行为仍需最终批准窗口，离线测试不得替代实际 CloudKit 结果。首次静态签名成功也不得写成真实 schema/P0 通过。

证据包含固定输入 hash、资格/窗口摘要、准确阶段与 API 调用计数、意图/逐项返回/校验/terminal、退出码、原始失败及 NOT_RUN 限制。账户/设备/证书明文和 CloudKit 任意 userInfo 不公开；公开错误只限已批准合成 ID 及受限技术字段。任何最终报告或持久证据写入失败都不得返回成功。更正应追加并关联前一份证据，不覆盖失败原件。
