# 本次可送审构建上传步骤

当前非skip候选：321219f61fd2dedf3be69d6f49c3af23896cccd4；新required CI43347067614整体SUCCESS（Release成功、Unit714PASS/1SKIP、Smoke8PASS）。拟用唯一标签testflight-appstore-free-1.0-20261113，已只读确认远端不存在，尚未创建。旧不可移动标签不移动。

实际后台1.0(20)二进制已验证，带内部标记，在正式版本构建选择器中20–16禁选；12及更旧可选。旧包不能覆盖新隐私/支持入口，也不能用于本次送审。

按Apple官方配置说明，内部专用Archive不能转为App Store发行，需要新的Archive。解锁后在已有TestFlight-workflow最小调整并回读：

1. General沿用原product/项目/仓库；启用或保留Apple要求的Restrict Editing（正式发行要求），不新增访问者。
2. Start Conditions核对原testflight-*标签、分支/文件条件，确保唯一新tag精确源码能触发；不反复推tag试探。
3. Environment按Apple发行工作流要求Clean，沿用验证过的Xcode/SDK配置。
4. Archive沿用iOS/PersonalGrowthOS scheme/Release，将Deployment Preparation设为**TestFlight and App Store**，不是TestFlight Internal Testing Only。保持应用身份/自动签名/原组，不增加外部测试人员。
5. 回读Workflow保存结果与触发条件；CI通过后，对精确非skip候选创建annotated tag并普通push，立即记录tag对象和解引用SHA。
6. 实际观察新XcodeCloud run对应tag和SHA、Archive/上传/处理及实际build号；源码默认12不作为云端编号。核对App和扩展版本一致、真实签名/entitlements/Production CK/APS及打包资源。
7. 在正式1.0选择器确认新build可选，保存关联，执行一次绑定该包的真机冒烟；不将Archive成功、上传成功、Add for Review混称Submit for Review。

依据：[Archive发行准备选项](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions)、[正式发行工作流](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution)、[内部标记含义](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)。2026-11-13查阅。这里只记录成品步骤，尚未声称已保存工作流或触发新构建。
