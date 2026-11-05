# iCloud Sync V1 验证证据（2026-11-05）

基线 `96f72339a1a3082c43018e06d6115dd93df1df97`，远端 Draft PR #14；执行分支 `codex/icloud-sync-v1-audit`，隔离目录 `/private/tmp/PersonalGrowthOS-icloud-audit`。本轮只有 Docs 内容，PoC 未加入工程。主工作区原有 project.pbxproj、Localizable.xcstrings、xcodecloud 目录改动均保留。

环境：Apple Silicon / macOS 27.0.1 / Xcode 27.2 (27B52) / Swift 6.4.2。原生 store 均为脚本在临时目录新建的合成库。没有读取 App 用户库、iCloud 用户数据、凭据或私人备份，没有创建真实容器/注册 capability。

## 运行台账

| 轮次/命令 | 实际结果 | 证据与边界 |
| --- | --- | --- |
| `python3 Docs/PoC/iCloudSyncV1/inventory.py Docs/Evidence/iCloudSyncV1` | exit 0 | 39 实体 / 263 字段 / 52 unique / 221 无默认必填标量；`schema-inventory.json` |
| 原生首轮，`python3 Docs/PoC/iCloudSyncV1/run_native.py Docs/Evidence/iCloudSyncV1` | 编译 exit 1，脚本 exit 1 | `attempt-01-sandbox/`：嵌套 sandbox 不允许宏插件，完整原日志 gzip + SHA256；没有运行用例 |
| 原生第二轮，同一命令，沙箱外授权执行 | compile 0 / shape-local 0 / shape-cloud -6，脚本 exit 1 | `attempt-02-unbundled/`：先得到 134060 模型拒绝，后 CLI teardown bundleIdentifier 异常；未运行后续用例 |
| 原生第三轮，同一命令，接受并严格核验上述负例特征后继续独立本地用例 | 脚本 exit 0；compile 0、shape-local 0、shape-cloud **-6**、compatible-local 0、write 0、rollback 0、crash-before-save **73**、verify 0 | `native-runs.json` 保存逐命令与实际 exit；并未改写 cloud 的 -6 为通过。73 是刻意进程退出 |
| `python3 Docs/PoC/iCloudSyncV1/protocol_probe.py` 初轮 | exit 0，16/16 | `protocol-tests-initial.log`；手写协议模拟 |
| 同一命令，补 ACK 的 account/epoch 拒绝分支后 | exit 0，16/16 | `protocol-tests.log`；同一方法增加迟到 ACK 负例，不把模拟称为服务器测试 |
| `python3 Docs/PoC/iCloudSyncV1/verify_evidence.py` | exit 0 | `verification.log`；native 字段集合与源声明逐项一致，非 Docs 树未改 |

`schema-native-crosscheck.json` 是原始报错逐项交叉核对摘要；`production-source-sha256.json` 为 App Swift 源 hash；最终非 Docs `git diff` 另外覆盖工程、Shared、Extension、Widget、测试和工作流。`evidence-sha256.json` 覆盖最终本目录证据（排除它自己）。`delivery-check.json` 记录交付前的范围/基线检查，不将历史 CI 计入本轮。

## 可以确认

- 使用真实 SwiftData/CoreData 执行存储形状实验，39 实体本地可开；CloudKit 明确列出 221 个 required 属性、Entry.images、52 个 unique。清单与原生拒绝集完全一致。
- 去 unique 的模型能保存两个相同业务 ID；适配 schema 并不能代替业务去重。
- 原生本地 fact/outbox 一次 save、rollback、退出后重开与旧 ACK 保护；本地 CKRecord identity/system fields、CKAsset exact bytes 通过。
- 16 个协议场景通过；并发编辑含 6 个投递排列，重复、相反操作、同 ID 不同字节、旧备份遇 tombstone、账户切换、未知版本与缺图等反例都有明确期望。

## 明确保留的限制

- 生成的 V16 存储形状不是完整生产模块或迁移计划；没有运行真实 App 业务验证器，也没有新跑旧库迁移或全量备份往返。报告对这些路径的结论来自源码审计，旧 #14 测试仍是旧证据。
- CloudKit schema 负例失败后还发生 CLI teardown 异常；未签名、无 bundle、无有效容器。没有正常 CloudKit 成功初始化，没有账号/网络/服务器写入/下载证据。
- CKRecord.systemFields 仅本地往返，没有服务器 changeTag；CKAsset 只是本地引用，不证明上传/下载可用。
- 协议模拟不是 CKSyncEngine、不是生产合并器，没有真实 partialFailure/quota/token 失效、完整业务约束、掉电、磁盘耗尽或大数据性能实测。
- 真正双设备、两测试账号、iOS 17/当前 iOS、后台与 push、签名能力/生产 schema、真实恢复与云事件竞争、设备通知和用户体验全部 **NOT_RUN**。
- 本轮产品源码零变更，不执行不必要全量 App 测试；Docs 审计提交使用 `[skip ci] [ci skip]` 避免现有无路径筛选的产品全量 workflow / Xcode Cloud 自动重跑。没有修改/关闭 workflow、分支保护或测试断言；不声称新 CI 通过，required check 若 pending 仍不得合并。正式同步阶段必需 CI/真机门禁没有被免除。[GitHub skip 说明](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/skip-workflow-runs) / [Apple Xcode Cloud skip 说明](https://developer.apple.com/videos/play/wwdc2022/110374/)。没有推送发行 tag 或手工启动发布任务。

审计结论见 [报告](../../ICLOUD_SYNC_V1_AUDIT_ZH.md)，复现说明见 [PoC](../../PoC/iCloudSyncV1/README.md)。
