# 首发收尾本机证据（2026-11-13）

最终状态：非skip候选321219f；本机联系入口UI1PASS、干净Release/三Bundle资源exact；新CI43347067614整体SUCCESS，Release成功、Unit714PASS/0FAIL/1SKIP、Smoke8PASS/0FAIL/0SKIP。三份官方ZIP SHA256/CRC、来源与独立计数核验见ci-*-321219f.json。后附“运行中/待结果”为当时观察，最终由本段及末段取代。Apple配置仍未完成，不是送审/上架证明。

环境：当前主力Mac，Xcode27.2/27B52，macOS27.0.1；新建隔离iPhone18Pro/iOS27.0模拟器E1E2C997-C665-4CCE-968B-B90B9FC61A3E。原主工作区未提交改动保留；没有真机/私人库/真实CloudKit操作。

## 实际命令与结果

工作目录均为`/private/tmp/pgos-app-store-release-20261110`。完整本机输出/xcresult保留在下列`/private/tmp`路径，公开精简证据为本目录JSON与截图原件，未把私密Apple账户或日志放进仓库。

- Debug构建：`xcodebuild build -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -destination 'platform=iOS Simulator,id=E1E2C997-C665-4CCE-968B-B90B9FC61A3E' -derivedDataPath /private/tmp/PGOS-AppStore-DD CODE_SIGNING_ALLOWED=NO` → exit0，`PGOS-AppStore-Debug.log`。早于新演示fixture，后续UI构建覆盖fixture。
- UI通用：`xcodebuild test -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=E1E2C997-C665-4CCE-968B-B90B9FC61A3E' -derivedDataPath /private/tmp/PGOS-AppStore-DD -resultBundlePath <下面路径> <only-testing> CODE_SIGNING_ALLOWED=NO`；stdout/stderr保存同名log。

| 结果包 | 精确选择 | 实际结果 |
| --- | --- | --- |
| PGOS-AppStore-Screenshots1.xcresult | `PersonalGrowthOSUITests/AppLaunchSmokeTests/testAppStoreScreenshotsAndOfflinePolicies` + `PersonalGrowthOSUITests/AppLaunchSmokeTests/testTextCaptureAppearsInTimelineAndSurvivesRelaunch` | 1PASS/1FAIL/0SKIP，exit65。保存、修改、两次重开PASS；截图测试把真实“时间线”误写为“时间轴”失败 |
| PGOS-AppStore-Screenshots2.xcresult | 仅`PersonalGrowthOSUITests/AppLaunchSmokeTests/testAppStoreScreenshotsAndOfflinePolicies` | 0PASS/1FAIL/0SKIP，exit65。录入键盘挡住后续Tab，测试无效tap，未选中Growth；正常产品行为 |
| PGOS-AppStore-Screenshots3.xcresult | 同一新截图/政策测试 | 1PASS/0FAIL/0SKIP，exit0。截图Record后先正常保存、确认进入时间线，再继续Tab；双语10张及四个离线政策/支持页面断言通过 |

- Release构建：`xcodebuild build -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/PGOS-AppStore-Release-DD CODE_SIGNING_ALLOWED=NO` → exit0，`PGOS-AppStore-Release.log`。三个unsigned Bundle、各自manifest、四份正文与源文件完全相同；两语言相机/AlarmKit说明及remote-notification background mode核对。详情`release-bundle-check.json`。
- 素材校验：`python3 Scripts/AppStore/validate_materials.py` PASS；关键词按100字节、reviewNotes4000字节，其余字段按字符计数；本地网页链接、无脚本表单、网页/离线正文一致及plist验证，`materials-validation.json`。
- 原始截图导出：`python3 Scripts/AppStore/export_screenshots.py /private/tmp/PGOS-AppStore-Screenshots3-export` PASS；10张1206×2622/RGB无alpha，原始SHA256见`Release/AppStore/Screenshots/manifest.json`（以仓库根Release路径为准）。十张已实际逐张查看。
- `git diff --check` PASS。生产同步目录、持久化schema与服务没有修改。仅新增设置静态页面、资源、Debug演示夹具、UI素材验证及发布文档。

正式xcresult的runtimeWarnings数组为空；保留既有编译warnings和模拟器控制台Objective-C WebKit可访问性类重复警告，不宣称所有输出零warning。Release本机构建标识基线4ec39f7/Dirty=true，准确表示当时尚未提交修改；不是可签发/上传证明。新代码普通提交后应在稳定候选上执行远端既有required CI，上传前再核对干净来源与真实Apple构建。

## 复用与未执行

R1–R5同步修复源码仍为5910422，源目录未变，复用既有本机61/61、最终transport28/28以及产品CI714PASS/1SKIP、Smoke8/8和定向CI证据。不因新增静态政策重复运行全量本机715测试。

NOT_RUN：本次新候选发行签名/Archive上传/TestFlight处理；免费价与5区保存回读；真机最终覆盖冒烟；旧schema额外迁移矩阵（本轮未改schema，原证据保留）。Apple已登录，免费协议有效；实际1.0(20)内部专用且商店禁选。已完成网页公开托管/桌面视觉QA、年龄9+与App Privacy后台保存。审核电话实际必填导致版本编辑保存失败，不能称全部字段已保存。


已提交候选741a00e之后进行一次增量Release来源绑定，日志`PGOS-AppStore-CleanRelease-741a00e.log` exit0；`clean-release-source.json`核实Commit741a00e/Dirty=false及四份正文一致。现有同源码后续文档不改变此产品候选。PR20已实际触发CI43341685409；本机不重复全量Unit。

## 独立CI与公开网页补充

CI43341685409：head741a00e，Release/Unit/Smoke均SUCCESS；merge checkout a84f98c9b773cc14db71733680354a6acbb41c37完整tree与741a00e相同。三份官方ZIP分别核对SHA256和CRC，见ci-{release,unit,smoke}-verification.json；Unit714PASS/0FAIL/1SKIP，Smoke8PASS/0FAIL/0SKIP，两者runtimeWarnings和testFailures为空。optional extended UI按原条件SKIP，不计PASS。

公开gh-pages54df17e，实际Pages部署43344768324，6文件HTTP200且与获准源文件逐字一致。Safari桌面实际查看主页/中英文政策与支持页，中文政策滚动底部确认mailto；页面无脚本表单/分析。未声称中国大陆网络可达性或移动端实测。Owner获准邮箱已公开，审核电话/Apple私密账户信息不入库。

联系入口增量：ContactUI第一次发现断言中文标签与实际不符，在运行测试前中断exit75（原log保留）；ContactUI2实际0PASS/1FAIL，测试误将SwiftUI Link查询为Button，失败层级显示邮箱Link确实存在，未改产品或放宽可用性断言。修正类型为app.links后仅重跑同一受影响测试ContactUI3，1PASS/0FAIL/0SKIP、exit0（112秒），双语邮箱可点击、在线政策/支持链接存在、正文含获准邮箱、正常本地保存及10个界面截图均通过。旧10张五Tab截图不受政策底部联系修改影响。

干净最终源码321219f增量Release：`xcodebuild build -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/PGOS-AppStore-Release-DD CODE_SIGNING_ALLOWED=NO`，日志`PGOS-AppStore-CleanRelease-321219f.log` exit0；BuildProvenance=321219f/Dirty=false，三个Bundle身份、源码版本1.0(12)、清单及四份文本资源exact。见clean-release-source-321219f.json。新独立CI43347067614已触发，尚待结果。

新候选CI Release官方artifact14002885181已独立下载，SHA256 aab80bdb2b82fcc54ab074a3a7e9c2be0546c7c3f44f9670a1a6fa9aff496bc4与CRC通过；environment来源321219f，实际checkout e30c26e，GitHub commit tree与本地321219f tree都为cc320dedb707e6f520ed9e4dff03b9924e24e591；release.log BUILD SUCCEEDED，bundles.json列出三个unsigned Bundle。Unit/Smoke仍运行，尚不宣称整个run成功。

新候选CI Unit检查SUCCESS，官方artifact14002009073的SHA256 5cee08da4a369154b6f3978cd5c0a4bc123a045f5f095bd4458ab3a05379fdaf与CRC通过；实际head321219f/checkout e30c26e。summary715=714PASS/0FAIL/1SKIP，独立遍历Test Case节点得到同样计数；唯一SKIP为testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure，需要隔离32MB HFS+镜像。runtimeWarnings和testFailures为空。见ci-unit-321219f.json。Smoke尚待结果。

最终Smoke检查及run43347067614均SUCCESS。官方artifact14003641240，SHA256 f6ba4f902d8209a6f8e48bcaa277abe6e518495899f0c3c0faef280f64eada0c与CRC通过；summary与独立8个Test Case节点均8PASS/0FAIL/0SKIP，runtimeWarnings/testFailures为空；head321219f/checkout e30c26e均精确。见ci-smoke-321219f.json，保留所有8个测试标识。新源码验证已完成，不重复启动第三轮全量CI。

最后文档提交只记录321219f已通过结果，不变更产品/测试/构建脚本。发行标签必须指向无skip的321219f，而非后续[skip ci]文档提交。Mac锁屏和Owner字段未完成，未推新TestFlight标签、未上传或提交审核。

## 晚间 Apple 执行实证

Owner已填审核电话，私密字段回读只记录存在而不公开值；DSA无EU计划和代码/图标/素材分发权利/无第三方服务均获Owner确认，版权显示2026 随心log。DSA保存后Business行有效、监管完成提示回读。Owner尚无备案并明确四区先发/大陆待准入后开，供应管理页显示4区且澳门/美国/台湾/香港均App发布时供应，其余171未供应；当前价时间表popover实际回读美国USD$0.00，不把通用价格计算器当当前价格。Mac/Vision兼容分发均关闭并观察已保存。英文名称/副标题观察已保存；英文隐私URLprivacy-en.html保存回读。版本双语各5张原始截图保留；英文文案首轮被异步locale加载覆盖后稳定重填，计数正常并保存，最终版本回读继续。

原生Xcode workflow实际保存/回读与唯一tag/build来源见xcode-cloud-workflow.json和xcode-cloud-tag.json。Build21 Archive/后处理SUCCESS，35条均Warnings（未改变原同步代码）；17.1MB Archive与10.6MB app-store包下载启动，但完整文件尚未取得，未声称发行签名/资源二进制验证通过。Mac再次锁屏后已请求解锁，未改锁屏或密码设置、未清数据。备用内置浏览器可读未登录页但点击/焦点失败，未视为有效登录或可用替代。

NOT_OBSERVED仍包括：实际新TestFlight编号/处理状态/商店可选、最终签名包内容、正式版本构建关联、必要真机覆盖、Add for Review和真正Submit for Review。当前未送审/公开发布。
