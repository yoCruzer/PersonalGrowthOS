> 最新结论：2026-11-07按Owner调整的手机侧范围完成本轮G1收口（OWNER_ACCEPTED_PHONE_SCOPE）；原完整矩阵未全PASS，Mac CK_2作为已接受例外保留。见[收口说明](ICLOUD_SYNC_G1_OWNER_CLOSEOUT_ZH.md)。以下旧状态为历史记录。

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

本轮签名修复提交`8245f74c2362bb96fc8bfedfdbd112bca0d5f699`已普通推送至Draft PR #16。[定向CI 42327436273](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42327436273)和自动触发的[既有iOS regression 42327441520](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42327441520)交接时RUNNING，尚不声明通过。独立限定复核30/30、仓库8/8已通过，原失败证据保留。待Owner登记/账户答复时不进行依赖的云步骤。

后续同轮取回：[定向CI42327436273](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42327436273)完成SUCCESS，实际产物核对签名门禁8/8、原生33/33、unsigned iOS Simulator BUILD SUCCEEDED；见[ci-accepted.json](Evidence/iCloudSyncG1/resume-20261107/ci-accepted.json)。上段RUNNING为先前采样；自动iOS regression仍在运行，未声明通过。

## 2026-11-07 后续授权登记与账户更正

Owner明确批准将当前Mac mini登记至既有开发团队并生成描述文件；使用限定SyncLab工程的`xcodebuild -allowProvisioningUpdates -allowProvisioningDeviceRegistration`成功，Mac Debug BUILD SUCCEEDED，实包签名严格校验PASS。实体iPhone的`devicectl device info details`连接探测exit0；之前tunnel disconnected只是先前采样，不能继续笼统称设备不可连接。

Owner随后明确更正：当前Mac与其测试iPhone使用不同系统iCloud账户。撤回此前同账户前提。签名Mac SyncLab只启动至离线初始页面，未点击账户连接/保存/同步，随后退出；未在手机安装、未发送测试数据或切换系统账户。建议Mac专用本地测试用户登录手机同一iCloud，或使用已有同一iCloud的另一台Mac；已询问Owner选择，实际登录由Owner完成。CloudKit真实主路径及账户切换仍NOT_RUN，不能用两个不同private database的客户端证明收敛。

[授权登记与账户更正证据](Evidence/iCloudSyncG1/resume-20261107/authorized-mac-and-account-correction.json) · [Mac签名结果](Evidence/iCloudSyncG1/resume-20261107/mac-signing-after-registration.json)。这两个新证据替代此前“Mac登记待授权/缺profile”作为当前缺项；旧失败保留。

## 2026-11-07 专用普通用户已创建

Owner选择专用本地用户方案并亲自完成密码步骤；系统设置已观察新建haha普通用户，原管理员保持。现待Owner在新用户中登录手机同一iCloud后切回原会话，测试用户保持登录。已准备临时签名包及启动入口，复制签名PASS，启动器语法PASS、原日常用户负例exit1；不包含私钥，不重复登录开发者账户。新用户云资格/运行方式尚未验证。

[准备记录](Evidence/iCloudSyncG1/resume-20261107/test-user-preparation.json)。自动产品回归42327441520结束FAIL：Release/Unit成功，UI smoke 3/5通过，2项短中文名称单行高度断言失败；[原样记录与日志摘录](Evidence/iCloudSyncG1/resume-20261107/product-regression-result.json)。本次签名工具改动未改产品/产品测试，根因仍未定，不宣布产品门禁通过或私自改G1范围。SyncLab定向CI保持PASS。

## 2026-11-07 受限Debug探针就绪

Owner已在haha中登录测试手机同一iCloud并切回当前会话。跨用户直接执行需要密码，未尝试索取或绕过；实现一次Owner启动的受限合成测试入口，详见实验README。当前工程门禁及独立复核通过；[39项原生/13项工具/签名及审查证据](Evidence/iCloudSyncG1/probe-engineering-20261107/README.md)。已请Owner在haha中运行`/private/tmp/SyncLab-Probe-20261107/Start-SyncLab.command`并保留会话，同时连线解锁iPhone。最近手机App查询被CoreDevice4016拒绝，尚未安装；复核后仅排队Mac账户访问探测，结果尚未返回，未排队save/sync。真实测试后另记结果，绝不拿工程门禁补填真实矩阵。

## 2026-11-07 单Mac真实Development部分验证

专用haha用户运行签名Debug后，13条固定合成命令及独立复核通过：文字/68字节原图、真实SDK ACK及pending清空、checkpoint持久、同进程Store/Engine重开与再次同步、独立对象新增/修改/逻辑删除且历史完整。20个内存篡改负控拒绝。[运行证据及限定](Evidence/iCloudSyncG1/runtime-20261107/README.md)。矩阵1/5/7取得单Mac部分证据，所有双端/进程崩溃/空库重建要求仍未完成，不改G1为通过。

iPhone本轮安装在DDI personalization阶段失败；Owner确认重启、重连、首次解锁后仍为12040/12051/TatsuError4。官方devicesupport更新无匹配27B52包，未实施系统降级、关闭安全措施或设备重置。Owner授权通过官方Configurator尝试已准备且验签的同一Debug IPA；待实际结果，自动启动/取回证据也需另验。产品回归42332546608再次出现同两项布局失败，Release/Unit成功，既有失败保持。

Configurator官方商店GET后确认窗口无确认按钮，Owner观察一致，退出重开商店重试仍复现；工具与手机实验包未成功安装。已记录为明确环境阻断，不以安装尝试替代成功。probe-014已停止云引擎，完整快照与空pending保持，临时本机桥已关闭。恢复时先重新准备短期通道，原合成库与证据保留；既有安装授权持续有效。
