# iCloud Sync V1：Apple 环境及 Production 就绪门禁

2026-11-05。此文件是配置/验收规范，**不是已完成配置的证明**。本轮没有登录 Apple 后台，所有门户/设备/生产部署状态为 UNVERIFIED/NOT_RUN。

## 1. 三个入口不能混为一谈

- Apple Developer → Certificates, Identifiers & Profiles：App ID 的 iCloud/CloudKit 能力、容器关联及 provisioning profiles。
- Xcode → Signing & Capabilities：目标的 CloudKit、Push Notifications、签名；按需要配置 Background Modes/Remote notifications。自动签名可协助登记关联，但必须检查最终构建产物，而不只看源码 entitlements。
- CloudKit Console → CloudKit Database：选择准确 Team、容器和环境；管理 schema 并执行 Deploy Schema Changes。App Store Connect 是构建/TestFlight 发布入口，不是替代上述配置的一个“打开同步”按钮。

TestFlight 使用 Production，Development 成功不能替代它；不用先正式上架才能测试 Production。

## 2. 固定身份，先检查再创建

仓库中已核实（不是门户核实）：产品 Bundle ID `com.yocruzer.PersonalGrowthOS`，App Group `group.com.yocruzer.PersonalGrowthOS`，当前主 App entitlement 仅 App Group。不改变现有产品身份。

| 用途 | 标识 | 状态/约束 |
| --- | --- | --- |
| 正式产品 CloudKit 容器 | 建议 `iCloud.com.yocruzer.PersonalGrowthOS` | 仅建议，未确认存在/归属。若已有正式容器先复用实际配置，不另建或随意改名 |
| G1 独立实验 App | 建议 `com.yocruzer.PersonalGrowthOS.SyncLab` | 与正式安装/数据库隔离；不得复用产品 App Group |
| G1 实验容器 | 建议 `iCloud.com.yocruzer.PersonalGrowthOS.SyncLab` | 仅合成数据；实验环境通过不等于正式容器通过 |

同一个 CloudKit 容器有 Development 和 Production 环境，不是必须创建两个“生产/开发容器”。额外 SyncLab 容器是实验隔离选择。创建标识前先由 Owner 确认名称、归属及必要性，不碰轻快记账等其他项目容器。

## 3. 现在可以做的最小人工准备

先确保 Xcode 已登录正确开发团队、具备签名权限，Owner 能以有权限的账号进入 CloudKit Console。无需先在 App Store Connect 新建版本或发布 App。

需要人工配置时，Codex 一次给出精确的 Team/App ID/container 与缺项，不让 Owner 猜：

1. 在 Identifiers 选择对应 App ID，启用 iCloud，选择 Include CloudKit support，并关联核实过的容器；没有容器才按已确认名称创建。G1 先配置独立实验 App，不随意改正式工程。
2. 让 Xcode 自动签名刷新，或重新生成受影响的 provisioning profiles；添加能力会影响已有 profile 的有效性。
3. 在实验目标选择正确容器，核对签名后的 application-identifier、iCloud services/container/environment、aps-environment 及 profile。不能把 `aps-environment` 与 CloudKit environment 混为一个开关，不能靠只改 plist 强行取得权限。
4. 两个同步客户端登录同一测试 Apple Account；另一账户仅用于隔离测试。确认 Development 访问资格。不能未经同意退出 Owner 日常主账号。设备不足时明确阻断；iPhone+签名Mac实验可作为跨平台双客户端证据，但不冒称两台 iOS 验收。

新建 Apple 永久 Identifier、变更正式 App ID、部署 Production、切换个人系统账户由 Owner 明确确认后执行；不在本次 GitHub 修订中执行。

## 4. Production 不能“先部署空库就算完成”

推荐顺序：环境/签名预检 → Development 最小真实闭环 → 稳定核心 wire schema 清单 → Owner 审核部署差异 → 正式容器 Production 合成数据冒烟 → 大规模领域接入。

原生 CKSyncEngine 方案部署的是实际 wire CKRecord types/字段，不是机械照搬39个 SwiftData实体；不能调用 Core Data 自动初始化当作本方案 schema 已建立的证明。用实际 codec 的合成样本/显式 schema 工具覆盖所有拟发布字段（含可选字段、asset引用及需要的索引），核对版本/hash。

Owner 在 CloudKit Console 选择准确容器，进入 Deploy Schema Changes，审核 record types、字段、必要索引和权限差异后部署；再切 Production 核对。**只复制 schema，不复制 Development 里的测试记录。** Production 记录类型/字段不能像 Development 一样随意删除，因此不要现在部署尚未稳定的实验模型。

“没有待部署差异”或“Production记录数为0”均不足以通过：必须与应用期望 schema 清单逐项对照。未初始化所需 types 时也可能没有有用差异；private database 记录视图还需正确账户/zone。不能把空视图自动解释成丢数据。

## 5. 明确的门禁和证据

| 门禁 | 必须记录的证据 | 当前 |
| --- | --- | --- |
| E0 身份/访问 | Team、App ID、实际container、角色、设备与测试账户资格（公开报告脱敏） | UNVERIFIED |
| E1 签名/配置 | 实际构建SHA、签名entitlements与profile匹配；Development真实读写 | NOT_RUN |
| E2 Dev双客户端 | A保存文字+图片→B校验内容/hash；B改→A；删除、冲突、队列恢复 | NOT_RUN |
| P0 wire冻结 | 待部署types/字段/索引清单、版本/hash、Development对应证据 | NOT_RUN |
| P1 正式Production schema | Owner授权的精确差异、部署结果、正式容器Production核对 | NOT_RUN |
| P2 正式Production真实往返 | 使用正式容器且Production签名的隔离验证客户端、合成dataset；双端新增/读回/修改/删除及原图hash | NOT_RUN |
| P3 正式候选配置 | 真正产品候选的App ID/签名/profile/container/environment及schema版本一致 | NOT_RUN |
| P4 TestFlight验收 | 另行授权发布的实际构建、同测试账户两设备往返与重启/离线恢复 | NOT_RUN |

P1/P2 必须在大规模接入前关闭；若未获Production操作授权/环境不具备，写 `DEV_PROBE_PASSED_PRODUCTION_GATE_PENDING`，暂停大规模接入，不冒称整体已就绪。实验容器的 Production 测试不能填正式 P1/P2 的 PASS。P3在正式候选打tag/发布前复核；P4只可能在明确授权的真实TestFlight发布后完成。

每次新字段/索引/wire变化都重做相关 P0/P1/P2/P3 检查；初次部署通过不是永久通行证。任何 P1–P3 缺项都不得把正式发布状态写 READY。本轮 Goal 不授权部署Production、正式发布或操作真实用户数据；到相应门禁输出一次精确清单等待 Owner，不悄悄跳过。

## 6. 发布链额外检查

最终用于 `testflight-*` 的候选提交不得包含 `[ci skip]`/`[skip ci]` 等跳过标记；本轮纯Docs补正可跳过无关全量CI，但不是发布候选。将来只在明确发布授权后创建非跳过的可追溯候选，不改写历史、不移动已有tag。Xcode Cloud构建成功、TestFlight安装成功都不能替代 P1–P4。

## 7. 官方依据（2026-11-05核对）

- [Enable app capabilities](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/)：iCloud关联和profile重新生成。
- [Create an iCloud container](https://developer.apple.com/help/account/identifiers/create-an-icloud-container/)：标识注册与角色。
- [Configuring iCloud services](https://developer.apple.com/documentation/xcode/configuring-icloud-services/)：Xcode能力、CloudKit/Push、容器关联与自动签名。
- [Deploying an iCloud Container’s Schema](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)：schema部署、仅复制结构及Production演进限制。
- [Testing Your CloudKit App](https://developer.apple.com/library/archive/documentation/DataManagement/Conceptual/CloudKitQuickStart/TestingYourApp/TestingYourApp.html)：TestFlight使用Production；页面为官方归档，入口名称以当前Console为准。
- [CKContainer](https://developer.apple.com/documentation/cloudkit/ckcontainer)：签名environment及发布前Production测试。
