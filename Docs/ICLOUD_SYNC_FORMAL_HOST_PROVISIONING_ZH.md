# 独立Mac正式容器验证客户端：配置清单与执行边界

2026-11-08。本文件是针对固定候选的可评审操作单，尚未执行门户配置、开发者签名或CloudKit操作。

## 已完成的只读输入

Owner已确认正式App `com.yocruzer.PersonalGrowthOS` 的iCloud、Include CloudKit support、Push Notifications启用，并关联`iCloud.com.yocruzer.PersonalGrowthOS`。正式两环境schema已收取并比较。无需再次修改正式App或重新导出当前schema。

本机两个标准profile目录检查了6份可解析profile，没有精确匹配独立候选的profile；现有覆盖名称的通配profile不适用于macOS且没有CloudKit配置。这是本机可用性结论，不能证明门户尚未注册候选Identifier。另以证书subject OU匹配Team并与有效codesigning身份交叉核验，本机找到1个现有Apple Development身份，应优先复用，不要求新建证书；最初仅按显示名筛选得到0的结果已被准确核验取代。当前Mac的明确provisioning UDID被1份同Team、未过期的macOS profile设备列表覆盖，应先在门户核对并复用既有当前Mac，不默认重新注册。该覆盖不证明候选profile资格。原始profile、设备标识、证书及个人姓名不进入仓库。

## 本次拟配置的精确对象

| 项目 | 值 |
| --- | --- |
| Team | `83SKX2PM7B` |
| 独立App ID / Bundle ID | `com.yocruzer.PersonalGrowthOS.FormalSyncProbe`（先查是否已存在，存在则核对复用） |
| 名称 | `PersonalGrowthOS Formal Sync Probe` |
| 平台及最低系统 | 原生macOS，14.0；当前只准备本机架构 |
| CloudKit容器 | 复用`iCloud.com.yocruzer.PersonalGrowthOS`，不创建新容器 |
| 能力 | iCloud → Include CloudKit support；只关联上述容器 |
| Profile类型 | Development → **Mac App Development** |
| Profile建议名称 | `PGOS FormalSyncProbe Mac Development` |
| 签名环境 | Development；本机候选entitlements包含sandbox/network client，无产品App Group |

当前固定手动批次不依赖APNs订阅，不要求新增APNs证书或Push能力；正式App已启用的Push保持。这个独立ID不替换正式App或SyncLab，不接触其数据库。

## 获批后一次完成的配置步骤

前置条件：Owner能登录正确团队并具备Account Holder/Admin权限；本机有可复用的开发证书及对应私钥；目标Mac已注册。证书或设备不具备时先报告精确缺项，不默认撤销/重建证书或改注册设备。密码、验证码由Owner在Apple界面输入。

1. Apple Developer → Certificates, Identifiers & Profiles → Identifiers，先精确搜索候选Bundle ID。仅缺失时创建App ID，选择Explicit，填写上表名称与Bundle ID；已有时核对其用途与归属。
2. 仅为这个独立候选启用iCloud，选择Include CloudKit support，关联既有正式容器。审核后保存/注册；不改正式App或SyncLab配置。步骤依据[Apple App ID注册说明](https://developer.apple.com/help/account/identifiers/register-an-app-id/)和[iCloud能力关联说明](https://developer.apple.com/help/account/identifiers/enable-app-capabilities/)。
3. Profiles → + → Development → Mac App Development，选择该独立App ID、可在当前Mac签名的已有开发证书和目标Mac，按建议名称生成并下载。已有完全匹配且有效的profile可直接复用。步骤依据[Apple Development profile说明](https://developer.apple.com/help/account/provisioning-profiles/create-a-development-provisioning-profile/)。
4. 将下载profile留在本机，并提供文件路径。profile可能含设备/证书信息，不提交GitHub，不需要提供密码、验证码或导出私钥。
5. Codex对固定隔离App副本嵌入匹配profile并进行Development签名，只读复核实际代码签名、entitlements、profile、平台与有效期。运行静态preflight和离线inspect；即使静态资格匹配，也不能授权真实CloudKit操作。

预计10–15分钟（已有证书/设备时）；手机前台0分钟、数据线0分钟，不需要切换haha或退出日常iCloud。完成判据：精确候选的有效macOS Development profile、实际签名产物与计划身份一致，静态preflight通过；离线host仍拒绝云执行。若证书/设备缺项，耗时另计并先说明具体依赖。

## 为什么配置和真实云执行不能合并成当前一次默认操作

该操作单只到隔离客户端签名资格。持久单次执行、账户/环境认证及真实执行授权factory仍未实现；没有这些条件，不能通过修改命令行或票据打开当前host。正式Development执行还需最终固定计划、实际会话/同账户资格、合成dataset及可保留失败的日志路径。其输出决定P0冻结和精确Production差异，因此不能提前把Production部署或写入混入本单。

项目[Apple就绪门禁](ICLOUD_SYNC_V1_APPLE_READINESS_ZH.md)明确规定：“新建 Apple 永久 Identifier、变更正式 App ID、部署 Production、切换个人系统账户由 Owner 明确确认后执行”。本次已收到的回复确认既有正式App配置，并非新增独立Identifier的许可；因此先交付本机产物/验证及这份具体清单，再集中请求配置授权。Production、Archive、TestFlight、merge均不在本单范围内。
