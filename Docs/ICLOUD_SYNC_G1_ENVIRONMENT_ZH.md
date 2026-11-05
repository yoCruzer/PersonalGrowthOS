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
