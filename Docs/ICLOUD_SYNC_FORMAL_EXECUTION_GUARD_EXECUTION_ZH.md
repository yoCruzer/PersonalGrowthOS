# 正式 Development 执行保护：实现与验证

本批从 `07c1bcff2d2fae1f1a2d17271e36266aadb97d6a` 接续，独立工作树 `/private/tmp/PersonalGrowthOS-icloud-execution-guard`、分支 `codex/icloud-formal-execution-guard`。这是获批后续开发的代码准备，不是正式容器执行或 P0 通过。独立 App ID、关联、profile 和本机签名权限已在上一节点完成，不重复申请；CLI 已接入 `enroll-guard` / `run-approved`，要求精确目的、Owner 输入与摘要、真实自身资格及持久消费；仅实现和验证前置拒绝，尚未执行这两个真实命令。三种离线 inspect 入口保持独立。

## 实现边界

- `ExecutionLedger` 使用固定每用户目录、目录/锁 inode 绑定、跨进程 flock、独占文件与 fsync、Keychain 锚定的 HMAC 链。资格消费必须先于请求；失败、崩溃、输出位置变化不释放旧批次。测试使用合成 anchor store，真实 Keychain enrollment **NOT_RUN**。
- Owner 输入绑定有效窗口、OS 用户、run/dataset/plan/schema、签名二进制/CDHash/profile/receipt/source pins。严格 JSON 和摘要不是人类授权的密码学证明；只能在获得真实决定后制作。墙钟回拨和单调时间到期拒绝，窗口最多 15 分钟。
- 真实进程资格通过 Security API 读取自身代码与实际 entitlements，不接受外部成功布尔值。检查封存文件、签名证书与 profile 成员关系、离线 Apple 信任链、Mac profile 签名用途、当前设备资格。禁网络检查不包含在线吊销/OCSP/notarization，均 **NOT_RUN**。
- 账户 provider 仅能在真实资格、Owner 窗口和已持久消费的 permit 全部满足后构造固定正式容器。所有资格读取均要求对应 durable intent，最多 12 次账户 API 调用；原始 user record name 仅在内存，私人 ledger 保存 keyed HMAC，公开证据不写账户原值。
- 固定 runner 为 2 次初始账户资格读取、每个数据阶段前后各一次身份复核及 5 次 transport 调用。5 次为精确 zone 探测、zone 保存、3 条 asset 保存、3 条 mutation 保存、6 个精确 ID 读取。17 是 API 调用上界，不能解释为 HTTP 请求数。没有 query、业务枚举、删除、补偿写或自动重试。
- 显式 CKOperation bridge 保留逐项/整体/取消/晚到回调，证据先保存再发请求或取消。账户 convenience API 没有可取消 SDK operation，其 `localWaitOnly` 只取消本地等待，不声称服务器已取消。所有未知/部分失败保留，晚到回调归属原 permit，不能推进新批次。
- 合成 runner 使用外部测试 factory，报告明确 `INJECTED_OR_EXTERNAL_FACTORY`、`realNetworkQualificationClaimed=false`。另有固定生产拼接入口：先真实自身资格/OS 会话，再固定本地状态、持久消费，之后才构造固定容器。每进程只能有一次生产尝试；真实外层 stdout 封套明确为派生观察，并引用持久内层报告摘要，不冒称外层已被 ledger 锚定。

## 本轮发现及修复

1. profile 仅用普通 X.509 信任不足以证明用途，独立审查要求精确 Apple Mac provisioning profile signer 用途；采用公开 Security 实现的 standalone `1.2.840.113635.100.4.11`、WWDR intermediate `1.2.840.113635.100.6.2.1` 与 Digital Signature key usage。Apple CPS 1.32 中对应记载与公开系统实现不一致，原始拒绝保留，未将文档差异伪装为通过。
2. 动态/静态代码校验不接受 `checkTrustedAnchors` 参数，实际返回 -67070。移除此无效参数，仍保留固定 Apple requirement、禁网络、有效期检查，并独立执行离线代码证书链校验；不是忽略校验错误。
3. 独立替换锁文件曾允许第二持有者，现将锁 dev/ino 与目录身份一起锚定。持久窗口按最初消费时间校验，不能通过重新打开 ledger 或冻结墙钟延长。
4. 已写回调证据被原位改字节，初版 runner 仍可能发布成功。现在写入立即 readback，后续阶段、提交和晚回调再次核对已写文件；validation/prepared/published 报告摘要也加入持久链。失败原件保留。
5. 仅 await 前后检查窗口无法终止永不回调的 SDK 等待；新增到期 watchdog，主动取消本地等待/当前 operation，保留未知结果和已消耗资格。

## 实际外部观察

真实已签中间副本依次暴露 `selfSignatureInvalid`（-67070）、`profileTrustUnavailable`、`deviceEvidenceUnavailable`。设备证据不可用属于当次真实观察，原因未获证明，**不是** CloudKit 失败。加入固定阶段/数字诊断后，新签名副本通过自身资格；没有放宽设备要求，不能把单次成功解释成此前失败原因已查明。所有这些调用都是 `inspect-runtime`，没有构造真实 CKContainer，没有查询当前 iCloud 账户或业务记录。

原始 profile、CMS/证书、设备值及签名输出保留在仓库外私人目录。公开资料只包含必要的 hash、固定原因、数字状态、原创合成输入和可复现测试。实际签名资格、自动化合成保护和真实服务行为分别记录，不能互相替代。

## 剩余依赖

最终签名候选的只读自身资格、OS 会话与 Application Support 检查均通过（exit 0，云调用 0）。现在的外部依赖是 Owner 确认测试会话，并批准固定 Development 窗口及本地 guard enrollment。清单须固定一台 Mac、一个已确认测试 OS/iCloud 会话、新 run/dataset、最多 12+5 次 API 调用，以及 Development 首次保存可能新增 3 类型/11 字段的副作用。不得自动切换用户或把本轮签名许可扩展成云写入许可。

尚未完成：真实账户/SDK 云往返、线上 schema 观察、P0/P1/P2、Production、正式产品迁移、持久 outbox/inbox 和 39 实体集成。现有只读 schema 原件和正式 App 关联无需 Owner 重做。G1 手机接受范围、Mac CK_2 非阻塞例外与未覆盖故障矩阵保持。

本机最终完整包 156/156 PASS；最低 iOS17 SDK 编译 PASS、运行 NOT_RUN；实际打包 38 检查 PASS。独立 ledger/runner 20、runtime/边界 9（原运行同组另有21实现者测试，不能计入独立数）、生产入口 6 项通过。生产入口覆盖新增 OS/目录/一次性尝试，原 runtime/边界报告保留其当时源码绑定；远端统一复验最新源码。早期完整包 145 项中的测试字段数误计失败保留，修正为明确17键集合后定向5项通过，最终新完整包为156项。

[完整证据和实际签名结果](Evidence/iCloudSyncFoundation/20261108/execution-guard/README.md)。当前源的远端 CI 单独记录，不沿用上一节点结果。
