# G1 环境台账 — BLOCKED_ENV

2026-11-06（Asia/Shanghai）。起点为PR #15 HEAD `304a91984f17efc2c61b179f0a9e85a14ba87d95`，分支`codex/icloud-sync-g1`，隔离worktree `/private/tmp/PersonalGrowthOS-icloud-g1`。Owner已注册四个资源，无需重复注册；随后明确本轮“暂时只能完成离线工程与门禁交付”。真实服务验证尚未完成。

## 实际核验

| 项目 | 证据与结论 |
|---|---|
| Xcode/OS | 本机macOS27.0.1、Xcode27.2 (27B52)，SwiftData/CKSyncEngine SDK可编译；iOS17 / macOS14最低部署目标保持 |
| Team | 正式工程及缓存profile均指向`83SKX2PM7B`；门户角色/容器归属仍UNKNOWN |
| 开发签名身份 | 非沙箱只读`security find-identity -v -p codesigning`找到1个有效Apple Development身份；不公开姓名/证书指纹。首次沙箱显示0，不能作为实际缺证书结论 |
| 正式App | `com.yocruzer.PersonalGrowthOS`，Owner确认已注册；现有本机缓存profile有1台设备且到期2027-10-10，但iCloud services/containers/aps均缺失。这是旧缓存事实，不能证明门户当前仍未配置 |
| 正式容器 | `iCloud.com.yocruzer.PersonalGrowthOS`，Owner确认注册；实际关联、Development schema、Production schema、角色均UNKNOWN；未读取私人记录 |
| 实验App/容器 | `com.yocruzer.PersonalGrowthOS.SyncLab` / `iCloud.com.yocruzer.PersonalGrowthOS.SyncLab`，Owner确认注册；没有匹配的本机缓存profile，实际门户能力关联UNKNOWN |
| 构建/签名 | iOS Simulator和Mac unsigned构建通过。一次不允许自动注册/刷新profile的iphoneos手动签名构建失败；unsigned包被签名核验脚本拒绝。没有实际通过E1的签名包 |
| 设备 | CoreDevice只读清点发现一台已知iPhone16为unavailable。现有模拟器属于其他任务，未清除/切换其账户或用于真实云实验 |
| CloudKit CLI | `cktool get-teams`因未配置management token失败；未索取/导出token，未调用import/reset/deploy。已有浏览器控制关闭、Mac锁屏，未访问门户 |
| 账户 | 同一测试Apple Account双客户端、Development访问资格及第二隔离账户均UNKNOWN；本轮Owner选择离线交付，不自动退出系统主账号 |

脱敏权威采集：[environment.json](Evidence/iCloudSyncG1/offline-20261106/environment.json)。初次沙箱读取产生的`cached-profile-capabilities.json=[]`只保留为历史受限观察，不代表真实缓存为空。后续提权只读解析成功且profileDecodeFailures=0。原始含姓名/设备ID的工具输出不提交，公开台账仅保留必要能力字段。

## E/P 门禁

| 门禁 | 状态 | 缺少的实际证据 |
|---|---|---|
| E0 身份/访问 | PARTIAL / BLOCKED_ENV | 门户Team角色、App ID与容器能力关联、测试账户及双客户端资格 |
| E1 签名/配置 | BLOCKED_ENV | SyncLab Development profile、实际签名entitlements/profile一致、设备运行及真实读写 |
| E2 Dev双客户端 | NOT_RUN | G1八项真实服务矩阵，含服务器CAS、原图hash、队列恢复、账户切换 |
| P0 wire冻结 | CANDIDATE_ONLY | 本地实际codec覆盖已有；未有Development schema导出/对照，不能冻结 |
| P1 正式Production schema | NOT_RUN / NOT_AUTHORIZED | 稳定正式wire的精确部署差异和Owner批准，正式容器部署结果 |
| P2 正式Production往返 | NOT_RUN / NOT_AUTHORIZED | Production签名隔离客户端与合成数据双端验证 |
| P3 正式候选配置 | NOT_RUN | 后续正式产品候选与schema/profile一致性 |
| P4 TestFlight | NOT_RUN / NOT_AUTHORIZED | 另获发布授权后的真实构建及两设备验收 |

## 一次性最小 Owner 准备清单

本轮不需要立即操作。恢复真实验证时集中完成以下事项，**不重新注册资源**：

1. 解锁Mac并允许浏览器控制，或Owner自行在Developer/CloudKit Console核验Team `83SKX2PM7B`内两组现有App ID与对应容器关联；SyncLab需iCloud / Include CloudKit support和Push。正式App若需变更能力，由Owner明确执行/批准，不改变正式Bundle ID/App Group。
2. 为已注册SyncLab刷新/提供Development provisioning profile（若使用Mac第二客户端，也核对其平台签名资格）；构建后运行`Experiments/iCloudSyncG1/Tools/verify_signing.py`。证书已存在，不要求重复创建证书。
3. 提供同一测试Apple Account的两客户端：两台iOS，或iOS+签名Mac；设备可连接且允许运行SyncLab。需要账户切换测试时另提供隔离系统账户/设备，Owner执行切换。无需退出日常主账号。

不要求把management token、Apple密码或账户ID粘贴到聊天/仓库。门户可由Owner操作并提供脱敏确认。Production部署授权不在这份准备清单中预先索取：必须先Dev真实通过、稳定wire与可审查差异齐备，再单独批准精确部署。

## Owner现有设备下的推进路线（2026-11-06追加）

Owner确认可用设备为当前日用iPhone、家中Mac mini和Intel Mac；短期没有第二台iPhone，明确要求不因此停滞开发/上线。**第二台iPhone不作为固定前置条件**。此前BLOCKED_ENV指未完成签名/账户/访问核验，不应解读为必须购买或借用另一台iPhone。以下是执行安排，尚不是设备实测通过。

- G1默认采用**当前iPhone + Mac mini**，分别运行独立SyncLab iOS/原生Mac客户端，使用同一iCloud账户、相同合成dataset。Mac伴随工程已经存在。核验OS、Mac平台签名/profile及CloudKit权限后，直接做双向文字/原图、并发、删除、重开和断网恢复；如实标明iOS+macOS覆盖。
- 不要求日用iPhone退出当前iCloud。若两端已有同一iCloud账户，可在Owner确认使用该账户进行仅SyncLab合成测试后复用；“测试账户”表示本轮测试身份，不必额外注册一个全新账户。App ID、容器、本地store独立，正式App与私人库不参与。若两端不同账户，可在Mac的独立本地测试用户中安排匹配账户；实际账户登录/切换由Owner完成。
- A→B→A账户切换放到Mac的专用本地测试用户环境，按串行登录/退出及冷启动验证；不是在日用手机退出主账号，也不能把两个常驻macOS用户冒称同一个客户端发生账户切换。第二测试账户只为这个负向场景准备，不阻挡先完成同账户双端主路径。
- Intel Mac为可选第三端或账户隔离设备；需能运行macOS14及以上、匹配工具链并签名，才可用于当前SwiftData/CKSyncEngine实验。具体型号/OS尚未知。不将Intel工具链适配或升级设为G1关键路径。
- 若Mac mini为Apple silicon，后续在另获TestFlight发布授权后，优先采用**同一份实际iOS TestFlight候选在iPhone + Apple silicon Mac上运行**的两设备路径；先核验构建兼容性，并在测试组启用该能力。该设置是测试组能力，不要求把产品正式上架为Mac应用。原生SyncLab伴随端只能证明它实际覆盖的云协议，不能替代这份正式候选的TestFlight证据。
- 如果上述同候选Mac运行遇到兼容问题，先做有界诊断/最小兼容修复，再明确残余平台覆盖与可用替代测试端；不自动把“再买一台iPhone”列为解决办法，也不提前宣称P4通过。
- 单台真实iPhone承担实际iOS前后台/挂起、锁屏、网络切换、重启、安装/升级等验证，Mac作为远端写入者；这些当前仍NOT_RUN。模拟器可补充iOS版本及故障覆盖，不代替手机上的硬件/后台行为证据。

顺序：Mac解锁及已有Apple门户登录 → 核对并完成SyncLab签名 → iPhone+Mac mini真实Dev主路径 → Mac隔离账户负例 → 稳定wire/P1/P2正式Production前置门禁 → 后续领域接入与获授权后的真实TestFlight候选验收。保留G1完整八项及P0–P4要求；不把跨平台覆盖改称“两台iPhone已验收”。本次只明确设备策略，不授权登录/切换系统账号、安装到日用设备、Production部署或TestFlight发布。

官方依据：[在Apple silicon Mac上测试iOS TestFlight应用](https://developer.apple.com/help/app-store-connect/test-a-beta-version/test-iphone-and-ipad-apps-on-macs-with-apple-silicon)、[CloudKit设备与模拟器账户配置](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app)、[macOS14支持机型](https://support.apple.com/en-ie/105113)。Mac mini具体芯片/系统及两端是否同一iCloud账户，待设备可访问时核验；无需提供账户名或密码。

## 2026-11-07：Owner解锁后的实际门户与签名核验

- Safari原生控制恢复，已登录Apple Developer / CloudKit Console。Team与工程一致；SyncLab App ID支持iOS/macOS等平台，iCloud、Include CloudKit support、Push均已启用，App Groups未启用，唯一勾选容器为`iCloud.com.yocruzer.PersonalGrowthOS.SyncLab`。没有改变门户能力。
- CloudKit容器归属该Team，当前登录用户有Manage Permissions/Edit Development/Edit Production；仅只读查看Development schema（Users），未查记录、未进入Production、未部署。权限存在不代表Production获授权。
- 本机arm64 / Mac18,5 / macOS27.0.1 / Xcode27.2(27B52)。实体iPhone17,3 / iOS27.2已配对、Developer Mode enabled，初查localNetwork tunnel disconnected；sameMachine条目为模拟环境，未冒称实体客户端。
- iOS Debug `xcodebuild ... -sdk iphoneos -destination generic/platform=iOS -allowProvisioningUpdates build` exit0，原有实验身份获得有效开发profile，实体手机包含其中。实际签名严格限定CloudKit、Development、实验容器、development Push且无App Group。
- 首次脚本exit1：Apple profile使用`icloud-services="*"`和`[Production, Development]`。依据[Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)，profile是允许列表，区别于App实际声明；修正仅profile服务通配符及环境顺序，signed claims严格要求不变。8项正反例通过，同一实包复验exit0；旧失败保留。该修正不证明OS实际运行或真实CloudKit访问。
- Mac Debug签名exit65：当前Mac未登记到开发团队、无匹配Mac App Development profile。尚未使用`-allowProvisioningDeviceRegistration`。已询问Owner登记这台Mac（向Apple提交设备标识、占用设备名额）；另询问两端iCloud是否一致。未收到确认前不执行依赖步骤。
- 只读沙箱硬件/签名检查曾失败，非沙箱复核后才给出上述结论；原始签名日志含设备/证书个人字段，只保留在本机`/private/tmp/g1-resume-20261107/`，仓库保存摘要哈希与脱敏JSON。源码二进制基线为`56a1d39`，其后改动仅签名辅助脚本/对应定向CI及文档；未改App或同步实现。

证据：[本轮环境](Evidence/iCloudSyncG1/resume-20261107/environment.json)、[原签名门禁失败](Evidence/iCloudSyncG1/resume-20261107/ios-signing-before.json)、[修复后签名通过](Evidence/iCloudSyncG1/resume-20261107/ios-signing-after.json)、[8项正反例](Evidence/iCloudSyncG1/resume-20261107/signing-gate-tests.log)。E0门户部分已核实，账户/连机仍待确认；E1仅iOS签名子项通过；E2/P0实际Dev/P1–P4仍NOT_RUN。
