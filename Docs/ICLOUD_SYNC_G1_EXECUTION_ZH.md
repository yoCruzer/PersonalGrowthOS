# G1 中文执行报告 — BLOCKED_ENV

2026-11-06。本轮从PR #15指定HEAD `304a91984f17efc2c61b179f0a9e85a14ba87d95`创建`codex/icloud-sync-g1`，祖先含原审计`e036b01`及产品基线`96f7233`。原工作区三项未知修改保留。Owner确认四个Apple资源已注册，随后选择“暂时只能完成离线工程与门禁交付”。因此本轮交付隔离工程和可执行门禁，**不声称G1真实服务目标完成**。

## 已实现的边界

独立`Experiments/iCloudSyncG1/`包含可签名配置的iOS/Mac SwiftUI App、无依赖Swift Package、原生SwiftData `.none`事实/outbox/inbox、CKSyncEngine/private zone实际接口、CKRecord/CAS合并处理、CKAsset原图、合成快照与退出重放工具。默认禁止云访问；正式产品源码、工程、App Group、现有数据库、历史schema和发布工作流未修改。新增的`SyncLab offline gate`仅运行实验测试和unsigned构建，不发布或获取Apple凭据。

所有数据样本均合成。支持Entry-like文字、单张原图、依赖图与显式冲突选择；微型协议不是39实体领域合并器。恢复使用持久发布门，当前没有映射解锁接口。当前应用完整保留历史与图片，不做GC；容量、后台和生产领域接入仍在后续边界。

## 本地实际验证

命令、退出码、日志路径和最终源码hash见[证据目录](Evidence/iCloudSyncG1/README.md)。本机macOS27.0.1 / Xcode27.2 (27B52)，SDK目标iOS17/macOS14；没有伪称在最低系统实际运行。

| 验证 | 实际结果与边界 |
|---|---|
| 既有协议检查 | 16+4+14 = **34 PASS**；不改原审计四项FAIL证据 |
| 原生定向测试 | 最终 **33 PASS / 0 FAIL**，包含真实SwiftData事务/重开、R1四反例、排列重放、旧ACK、图片、恢复、跨账户分区、实际CKRecord codec入口，以及显式模拟的CAS/配额/部分成功 |
| 独立进程退出 | 未提交save中`_exit(73)`→重开旧事实与outbox完整；接收内容提交后、检查点之前`_exit(74)`→独立重开保留内容并可幂等重放。使用占位checkpoint字节，**不是SDK token测试** |
| iOS/Mac工程 | 独立unsigned Debug构建通过；不是签名/设备/服务通过。最终代码的iOS检查由定向CI再独立核验 |
| 签名负例 | unsigned包核验脚本退出1；一次离线iphoneos手动签名构建退出65，明确缺带iCloud与Push能力的SyncLab profile；不自动注册/刷新 |
| 图片 | 内置1×1 PNG真实ImageIO解码；原图字节/hash、截断保全与正确副本修复、缺图依赖不发布、缺图导出失败 |
| 快照边界 | 4096条可导出并恢复，4097条拒绝完整导出；129对象拒绝，保留所有原事实；不把不可恢复包称完整备份 |
| 独立Review | 独立reviewer初审R1–R6及后续边界问题，五个原生红例明确失败，修复后回归通过；独立反例重放与源码终审记录另列 |

历史轮次保留：首次沙箱SwiftPM因缓存权限失败；初次库构建成功但未添加测试时`no tests found`退出1；首轮23项通过；Review红测05有2 FAIL、06有3 FAIL；修复后28→29→31→32→33项分别随新增覆盖运行。没有把初轮FAIL改标全绿。原始日志为实际输出，不以最后一轮覆盖旧文件。

## G1八项矩阵：本地证据与真实服务严格分开

| 要求 | 当前证据 | 仍未完成 |
|---|---|---|
| 1 双客户端文字/原图/编辑/删除/重开/断网恢复 | 本地保存/删除投影/原图/独立进程重开 | 全部真实双端往返、真实断网及逐ID/字节oracle NOT_RUN |
| 2 服务器CAS/changeTag及冲突 | codec system fields实现；CKError.serverRecordChanged明确注入；确定性候选/基线/显式解决测试 | 真实服务器并发CAS与双端收敛 NOT_RUN |
| 3 R1四反例与乱序依赖 | Python34、Swift因果/传递依赖/环/缺图父对象正负验证 | 真实CloudKit分批乱序 NOT_RUN |
| 4 旧ACK后重新调度 | 精确payload ACK原生正负；sent/didSend后重排代码 | SDK成功移除队列后另一端收到新修改 NOT_RUN |
| 5 fetched/state与退出 | SwiftData独立进程退出、内容先落盘、opaque原始入站保留；SDK串行契约核对 | 真正State.Serialization事件/退出点与服务器重放 NOT_RUN |
| 6 A→B→A及冷启动 | 不同accountHash本地分区重开；epoch晚回调拒绝；同账户signIn重建zone+record | 真实系统账户切换/CK账户事件 NOT_RUN |
| 7 图片staging/hash/lease | 原子安装、坏件保留与修复、无GC保留上传引用、缺图不能完整备份 | 两端CKAsset下载、进程退出/在途lease真实云验证 NOT_RUN |
| 8 恢复与云到达竞争 | 快照恢复gate持久跨重开、晚回调拒绝、无token/ACK恢复 | 真实云到达并发 NOT_RUN；产品v12 ZIP仍属后续G2 |

quota/rateLimit/部分成功只属于**显式故障注入**；token过期、zone删除恢复、系统后台调度、最低/当前iOS运行、真机UI/VoiceOver与真实网络均NOT_RUN。新增CI也是离线验证，不能提高上述服务证据等级。

## 环境、Production与下一步

[环境台账及一次性最小Owner清单](ICLOUD_SYNC_G1_ENVIRONMENT_ZH.md)已区分证书存在、旧profile、门户未知与设备不可用；不重复要求资源注册。[wire候选与Production清单](ICLOUD_SYNC_G1_WIRE_SCHEMA_ZH.md)由实际codec产生字段，P0未冻结，P1/P2未授权且未执行。正式Production必须在大规模接入前验证，实验容器通过也不能代替正式容器。

恢复真实验证时按[README](../Experiments/iCloudSyncG1/README.md)核验Development签名并设置新的合成dataset，执行八项矩阵。只有这些真实Dev证据通过，才可改为`DEV_PROBE_PASSED_PRODUCTION_GATE_PENDING`。当前不进入G2/G3，不merge、tag、Archive、TestFlight、Production部署/写入或云重置。

实现提交`099ff1766854f8731fc82aeabe670a9f22dc26df`已普通推送。定向[CI run42067859222](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42067859222) **PASS**：33/33原生测试、unsigned iOS Simulator Debug构建；实际checkout为同一push HEAD。环境为macOS27.0.1、Xcode27.1(27A9275)、xcode-27-arm64 image20261104.0337.1。原始产物/checkout摘录及摘要见[CI证据](Evidence/iCloudSyncG1/ci-42067859222/accepted.json)。最终Mac本地构建也在该源码上通过。

后续交接提交只含文档/证据，使用`[skip ci]`避免触发与隔离改动无关的产品全量回归；已通过的实验源码及workflow不变，明确不是发布候选。源码/报告的`git diff --check`通过；全范围检查在保留的原始Xcode输出上报告尾空白/末尾空行，按原字节保留，不伪称无提示。完整目标仍未完成，离线交付不替代真实服务验收。

最终交付：[Draft PR #16](https://github.com/yoCruzer/PersonalGrowthOS/pull/16)，base `codex/icloud-sync-v1-audit` / `304a91984f17efc2c61b179f0a9e85a14ba87d95`。PR保持OPEN Draft，完整交付HEAD以PR元数据为准；实现源码固定099ff17，后续只文档/证据。按Owner本轮离线选择停止在此批次边界，完整G1真实服务目标仍待恢复条件满足后继续。

2026-11-06设备策略补充：Owner确认可用iPhone/Mac mini/Intel Mac，默认走iPhone+Mac mini双端，第二台iPhone不是固定门禁。具体账户隔离及同候选TestFlight的Apple silicon条件见[环境台账新增路线](ICLOUD_SYNC_G1_ENVIRONMENT_ZH.md)。本次仅文档澄清，未新增设备/云运行证据，未改变已归档测试结果。

## 2026-11-07：Owner解锁后的实际门户与签名核验

- Safari原生控制恢复，已登录Apple Developer / CloudKit Console。Team与工程一致；SyncLab App ID支持iOS/macOS等平台，iCloud、Include CloudKit support、Push均已启用，App Groups未启用，唯一勾选容器为`iCloud.com.yocruzer.PersonalGrowthOS.SyncLab`。没有改变门户能力。
- CloudKit容器归属该Team，当前登录用户有Manage Permissions/Edit Development/Edit Production；仅只读查看Development schema（Users），未查记录、未进入Production、未部署。权限存在不代表Production获授权。
- 本机arm64 / Mac18,5 / macOS27.0.1 / Xcode27.2(27B52)。实体iPhone17,3 / iOS27.2已配对、Developer Mode enabled，初查localNetwork tunnel disconnected；sameMachine条目为模拟环境，未冒称实体客户端。
- iOS Debug `xcodebuild ... -sdk iphoneos -destination generic/platform=iOS -allowProvisioningUpdates build` exit0，原有实验身份获得有效开发profile，实体手机包含其中。实际签名严格限定CloudKit、Development、实验容器、development Push且无App Group。
- 首次脚本exit1：Apple profile使用`icloud-services="*"`和`[Production, Development]`。依据[Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)，profile是允许列表，区别于App实际声明；修正仅profile服务通配符及环境顺序，signed claims严格要求不变。8项正反例通过，同一实包复验exit0；旧失败保留。该修正不证明OS实际运行或真实CloudKit访问。
- Mac Debug签名exit65：当前Mac未登记到开发团队、无匹配Mac App Development profile。尚未使用`-allowProvisioningDeviceRegistration`。已询问Owner登记这台Mac（向Apple提交设备标识、占用设备名额）；另询问两端iCloud是否一致。未收到确认前不执行依赖步骤。
- 只读沙箱硬件/签名检查曾失败，非沙箱复核后才给出上述结论；原始签名日志含设备/证书个人字段，只保留在本机`/private/tmp/g1-resume-20261107/`，仓库保存摘要哈希与脱敏JSON。源码二进制基线为`56a1d39`，其后改动仅签名辅助脚本/对应定向CI及文档；未改App或同步实现。

证据：[本轮环境](Evidence/iCloudSyncG1/resume-20261107/environment.json)、[原签名门禁失败](Evidence/iCloudSyncG1/resume-20261107/ios-signing-before.json)、[修复后签名通过](Evidence/iCloudSyncG1/resume-20261107/ios-signing-after.json)、[8项正反例](Evidence/iCloudSyncG1/resume-20261107/signing-gate-tests.log)。E0门户部分已核实，账户/连机仍待确认；E1仅iOS签名子项通过；E2/P0实际Dev/P1–P4仍NOT_RUN。
