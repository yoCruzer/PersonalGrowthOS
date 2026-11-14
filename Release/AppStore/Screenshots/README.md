# 商店截图（简体中文 / English）

每种语言5张，依次为Today、Timeline、Record编辑中、Growth、Library。全部来自候选代码的真实模拟器界面，原始PNG未拼接、未重绘UI、未替换屏幕内容。文字和插图为原创演示内容，使用独立uiTesting数据库；自动云同步关闭，没有操作个人记录或真实iCloud。

- 设备：独立PGOS-AppStore-20261113 / iPhone18Pro / iOS27.0，1206×2622，RGB PNG，无alpha。
- Apple当前规格：iPhone with Dynamic Island (medium display) 接受1206×2622。项目仅iPhone，不额外生成不受支持的iPad截图。[官方规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)，核对日期2026-11-13；后台具体槽位仍待登录回读。
- 统一系统浅色/默认字号，模拟器状态栏9:41/100%电量；内容不伪造功能或云端成功状态。演示插图明确标识demo。
- 测试：`AppLaunchSmokeTests/testAppStoreScreenshotsAndOfflinePolicies`，最终Screenshots3 PASS；双语均额外确认草稿保存入时间线、隐私政策和支持正文可读。前两轮测试误用中文Tab名、录入时未先保存便尝试点被键盘遮住的Tab，均失败并保留记录；未修改产品行为或放宽断言。
- 已逐张视觉检查10张成品，无缺图/文字乱码/不实同步状态。原生滚动内容在Tab栏后自然延续，Record截图保留正常输入键盘。
- `manifest.json`：每张尺寸、PNG色彩类型、SHA256及原始attachment名。

复现：

```sh
xcodebuild test -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS \
  -destination 'platform=iOS Simulator,id=E1E2C997-C665-4CCE-968B-B90B9FC61A3E' \
  -derivedDataPath /private/tmp/PGOS-AppStore-DD \
  -resultBundlePath /private/tmp/PGOS-AppStore-Screenshots3.xcresult \
  -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testAppStoreScreenshotsAndOfflinePolicies \
  CODE_SIGNING_ALLOWED=NO
xcrun xcresulttool export attachments \
  --path /private/tmp/PGOS-AppStore-Screenshots3.xcresult \
  --output-path /private/tmp/PGOS-AppStore-Screenshots3-export
python3 Scripts/AppStore/export_screenshots.py /private/tmp/PGOS-AppStore-Screenshots3-export
```

现有xcresult不覆盖重用；重跑须用新的结果目录。不要在用户日常设备上运行ResetData或演示fixture。
