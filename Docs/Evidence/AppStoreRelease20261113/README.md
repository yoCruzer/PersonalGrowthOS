# 首发收尾本机证据（2026-11-13）

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
- 原始截图导出：`python3 Scripts/AppStore/export_screenshots.py /private/tmp/PGOS-AppStore-Screenshots3-export` PASS；10张1206×2622/RGB无alpha，原始SHA256见`../../../Release/AppStore/Screenshots/manifest.json`（以仓库根Release路径为准）。十张已实际逐张查看。
- `git diff --check` PASS。生产同步目录、持久化schema与服务没有修改。仅新增设置静态页面、资源、Debug演示夹具、UI素材验证及发布文档。

正式xcresult的runtimeWarnings数组为空；保留既有编译warnings和模拟器控制台Objective-C WebKit可访问性类重复警告，不宣称所有输出零warning。Release本机构建标识基线4ec39f7/Dirty=true，准确表示当时尚未提交修改；不是可签发/上传证明。新代码普通提交后应在稳定候选上执行远端既有required CI，上传前再核对干净来源与真实Apple构建。

## 复用与未执行

R1–R5同步修复源码仍为5910422，源目录未变，复用既有本机61/61、最终transport28/28以及产品CI714PASS/1SKIP、Smoke8/8和定向CI证据。不因新增静态政策重复运行全量本机715测试。

NOT_RUN：网站浏览器视觉QA/公开托管验证；本次新候选远端CI（待push/PR）；发行签名/Archive上传/TestFlight处理；App Store内部专用标记检查、价格/地区/协议/DSA/备案实际详情；真机最终覆盖冒烟；旧schema额外迁移矩阵（本轮未改schema，原证据保留）。Apple会话失效已请求Owner登录；公开联系/托管及地区等待确认。
