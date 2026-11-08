# 真机首次启用 missingSupplement 修复

## Owner原始反馈

Owner已完成独立备份，并报告build8覆盖安装、本地原数据/编辑保存/重启检查通过；截图显示同步默认关闭、Pending0。随后按当前iPhone账户Development首次启用，Owner说明可能点击2–3次，截图原文为 `Sync paused (missingSupplement). Local data and pending changes are kept.`，Pending0、仍显示Enable。截图及私人备份不上传仓库。本地检查为Owner报告，不冒称agent读取或验收私人业务数据。

## 原因与最小修复

正常生产入口 `HabitService.create(name:plan:)` 的每日一次计划保存原始HabitConfiguration.dailyTargetCount=1，既有HabitSettingsResolver/TransferSnapshot按有效语义输出nil。同步supplement需保留原始行UUID、count与updatedAt，原校验却把raw1直接和有效nil比较，误抛missingSupplement。此bug可独立合成复现，不以多次点击或网络解释；尚未读取Owner数据库以确认其具体触发行。

修复仅按原记录模式比较有效目标：multiplePerDay比较原count，oncePerDay比较nil；原配置字节字段与身份不改。未知模式、不同模式、活动目标不一致、孤立子记录等仍拒绝，备份格式/历史V16/迁移/传输协议不改。Installer仍保留原UUID/count/updatedAt，不以删除或重新生成配置绕过校验。build8旧客户端同类问题仍存在，相关客户端应统一升级build9。

按已审查enable控制流，此missingSupplement发生在initialize，早于transport.start及zone创建。重复点击可能重复账户只读查询，不能称网络0；Pending0也不是云成功凭证。没有为排障重跑云命令、清库、退出账户或读私人数据库。

## 实际验证与独立审查

本机Xcode27.1/macOS27.0.1，隔离iOS27.0模拟器，合成数据：

- 红阶段：`PGOS-Supplement-Red.xcresult`，2执行/2失败，两个用例均明确missingSupplement；真实业务service创建→codec/installer与初始化路径独立复现。原日志`/private/tmp/pgos-supplement-red.log`、摘要保留。
- 绿阶段：`PGOS-Supplement-Fix.xcresult`，**112/112 PASS，0FAIL/0SKIP**。同一模拟器/DerivedData，`xcodebuild test`，只选择SyncDomainCodecTests、SyncDomainInstallerTests、SyncPersistenceTests、SyncCoordinatorTests、SyncProductIntegrationTests、HabitFoundationTests；日志`/private/tmp/pgos-supplement-fix.log`。没有重复全量本机测试。
- 新增三项测试：正常service创建raw1与有效nil往返、完整installer再捕获保持原UUID/count/updatedAt；负例拒绝目标不一致/跨模式/未知模式；三次initialize保持相同mutation IDs及outbox数量，独立context读取保留配置。
- 独立review确认最小语义修复与身份保留、原拒绝门未放宽，无must-fix。重复initialize测试覆盖本地幂等，不冒充真实账户API/云重试验收。

## 安装产物

源码 `1e4fdca5d0657b3a1b4363a393a7feb52b9412eb` / Dirty=false，正式App和两个扩展build9。本机目录 `/Users/himini/Development/Builds/PersonalGrowthOS-iCloud-Dev9-1e4fdca`；与旧build8并存，原失败包不覆盖。

ZIP `PersonalGrowthOS-iCloud-Dev9-1e4fdca.app.zip`，11989994 bytes，SHA256 `17d6a7b6a3dc8e6073b9ce76397edbd4afda583756cac2aa44c850158dc7628c`。主程序SHA256 `3596090786630528553bf6f1df6b9a781353ac731a944e2c06aabe14a06a2ce9`。实际Security API权限为精确正式App/容器、CloudKit、Development、开发push、get-task-allow；原bundle与ZIP解包后的codesign严格验签通过，三个二进制摘要一致。只做普通Debug build，未Archive/安装/发布；真实profile及设备授权只本机保留。

## 远端及真机状态

Owner已确认build9覆盖安装、原数据正常，来源为Owner回复，未读取私人数据。定向CI [42496931888](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42496931888) SUCCESS；官方ZIP SHA256 `18496888e6b602527f5918d7ebdc7bfa3e33cfb4e3a9ef96f67519fcc79d413f`、307成员CRC、24源码pins与1e4fdca Git对象逐一核验，32打包检查通过，未执行Mac云探针。

[产品CI42496931856](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42496931856) SUCCESS：Release三个unsigned bundle，Unit672执行=671PASS/0FAIL/1SKIP，Smoke6/6。两个runtimeWarnings为空，低空间镜像测试跳过、optional extended UI按条件SKIPPED。actual merge checkout `95358d3d46567ad453df5d74a7ae6808c436d15c`，Xcode27.0；三个官方ZIP的digest/CRC/headSHA/摘要核对通过。CI通过不替代下方真实SDK事件失败。

| build9 CI产物 | SHA256 |
| --- | --- |
| ios-unit-1 | `1b5789bf6ab013fe87973836fdca60e81fda97c6a2c15c9caab10f0ff074d812` |
| ios-smoke-1 | `a584f138a8023774e8beb898f608d8db031403eb2177dfee83eaa3babcbb53cb` |
| ios-release-1 | `48c19b8eb79eed3afabe0847bdfa26bccdba4dd091432b19190f7c1410a8f66d` |


## 2026-11-09 真机后续：账户首次事件和取消覆盖

Owner已确认build9覆盖安装且原数据正常，然后按原范围启用一次。Owner提供本机截图`截屏 2026-11-08 23.58.21.png`：Operation Cancelled(20)、Pending429，界面已启用；只返回上级再进入读取本地状态，`截屏 2026-11-09 00.03.08.png`显示持久原因accountChanged、Pending仍429。Owner明确确认期间未退出/切换/改变iPhone iCloud登录。没有将429队列或CK20当作上传成功，也未再次发云重试指令。两张截图和备份仅Owner本机保留，不发布operation identifier。

审查确认两项代码缺口：正式App将所有CKSyncEngine.accountChange一律pause，遗漏G1已验证的同账户signIn分支；pause持久化原始原因后cancelOperations导致外层CK20，Coordinator又覆盖已读回的原始原因。手机未捕获SDK具体changeType，故不能假称已观测该事件值；Owner未换账户与持久accountChanged支持此诊断，真实验收仍待新包。

build10修复：仅匹配既有完整绑定账户的signIn可重排持久outbox；signOut/switchAccounts/其他账户仍拒绝。zone重排需本会话授权与持久初建资格交集，绝不因signIn新建丢失zone。session保留firstPauseReason，CK20为次级code；取消本身无前因时仍失败。Coordinator仅匹配当前generation/account/container/environment/dataset时显示持久首因，旧activation回调不覆盖用户关停或新状态。

为避免首次setup被取消后永远卡在attempted状态，加入显式初建恢复：只做expected zone元数据读，顶层zoneNotFound且前后同account/每次await后绑定仍有效，才可提供确认。资格还须never-established、!lost、!reconciliation、无lastSuccess、无任何inbox/nonlocal mutation/completed outbox/ACK，损坏ACK拒绝。单次内存确认绑定旧fullbinding，取消/disable/新activation/重启失效；确认后重读账户和exactzone，存在则采用，仍missing且全部资格再次成立才允许初次create。保留attempted、UUID、所有mutation/outbox/inbox/ACK；不自动重建。弹窗明确无法恢复曾仅存iCloud的内容，因为本地无回执不能证明云保存从未发生。

验证：核心`PGOS-SignIn-Fix.xcresult`59/59PASS；进一步恢复/首因/队列资格`PGOS-InitialSetup-Fix.xcresult`42/42PASS，均0FAIL/0SKIP/runtimeWarnings空。两轮范围不同不相加声称同轮全量；前一轮后补activation/初建恢复由后一轮覆盖。独立SDK合成24/24与iOS17typecheck通过，独立账户/持久化审查通过。实际云create次数与build10真机结果未被这些测试证明。

build10最终代码、剩余恢复意图检查、签名产物和最终CI收口中，不能沿用build9 CI冒称新代码通过。真实云双向、推送、Production/TestFlight均仍未验收。

恢复serialization中的旧saveZone意图另经完整范围校验后，仅在当前不再允许建区时撤销exact同zone的冗余意图，再严格校验；不清record队列及其他状态。foreign/delete整体拒绝。独立合成26/26、iOS17typecheck和最终只读复核通过。最终`PGOS-Build10-Final.xcresult`为44核心/恢复/双库集成+6产品UI，**50/50 PASS，0FAIL/0SKIP/runtimeWarnings空**，日志`/private/tmp/pgos-build10-final.log`。


## build10固定产物与当前验证

最终运行源码 `9882c288a24b241af5dc22b6b74637ab9ca8b69f`，BuildProvenance回读Dirty=false。正式App及两个扩展build10，实际签名精确为正式App/容器、CloudKit、Development、开发push、get-task-allow；原bundle及ZIP解包后严格验签，三个二进制摘要一致。目录仅本机 `/Users/himini/Development/Builds/PersonalGrowthOS-iCloud-Dev10-9882c28`，含app/ZIP/receipt/安装步骤，不发布profile。

ZIP `PersonalGrowthOS-iCloud-Dev10-9882c28.app.zip`，12022478 bytes，SHA256 `ba4aa9b4c9ecee3c0daee9dde1aaadc4268f73ac3abd771e0ac3779e8c898556`；主程序 `b008794b79ce0cd1e407e36927e3f9c25a204db75f390ee59ced5c8d26d1e82a`。

[定向CI42499136819](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42499136819) SUCCESS；[产品CI42499136863](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42499136863) Release SUCCESS、Unit/Smoke运行中。未沿用build9通过结果。

已集中给Owner一次build10覆盖更新+Sync now复测说明；若初建元数据明确missing且资格满足，额外初始化只由Owner阅读弹窗并主动Create workspace重新授权，不自动执行。当前等待Owner页面状态，真实云未判通过。无需Mac测试用户、清库或重跑G1。


## Owner停止真机协助；仅修复导航阻塞（build11）

Owner提供`截屏 2026-11-09 00.23.13.png`，说明build10打开后底部错误文字遮挡Tab。截图中的accountChanged是既有持久状态；没有Owner确认Sync now已执行，不能据此宣称build10又发生了新的云失败。Owner随后明确不再继续陪测，本轮不再请求任何安装/点击/截图或云操作。

已移除TabView根部的bottom safeAreaInset错误提示；暂停原因仍在同步设置页可查，不改同步状态、数据、队列或恢复权限。补充仅DEBUG+uiTesting+reset显式参数才运行的合成paused fixture，不触及正常启动/私人库；新UITest在常规及最大字号启动参数两次启动后分别点选五个Tab并断言选中，打开Settings→iCloud确认原始accountChanged仍可读。该项`PGOS-Paused-Navigation-Fix.xcresult` **1/1 PASS、0FAIL/0SKIP/runtimeWarnings空**，一项内共10次Tab切换、两次设置访问。两张合成截图已导出并人工查看，底部导航完整，无错误文字覆盖；字号参数传入不泛化为所有视图字号响应验收。日志`/private/tmp/pgos-paused-navigation-fix.log`、截图`/private/tmp/PGOS-Paused-Navigation-Images`保留本机。该回归加入现有Smoke列表，后续7项。

build11仅作为恢复正常导航的Development修复包准备，保留原数据及同步暂停；不要求Owner安装或恢复真机验证。build10远端定向/Release通过、Unit/Smoke在最新检查时仍运行，不提前判通过。后续源码CI按真实状态记录；真实云验收暂停、Production/TestFlight未执行。所有此前真实失败与未完成项保留。
