# 本次可送审构建上传步骤

## 2026-11-13 21时实际进度

- 非skip候选321219f61fd2dedf3be69d6f49c3af23896cccd4，required CI43347067614整体SUCCESS，本机双语联系UI/干净Release与三Bundle资源exact。
- Xcode27.2原生 Reports → Cloud → PersonalGrowthOS → TestFlight-workflow：Restrict Editing已开，仓库/项目正确；Tag Changes为“tags beginning with testflight-”，Any File Changes，Auto-cancel开；Xcode/macOS Latest Release保持，当前编辑器无Clean选项，不虚构已修改。
- Archive-iOS/PersonalGrowthOS的发行准备原为TestFlight Internal Testing Only，已改为当前UI名称**App Store Connect**（eligible for all testers and customers），Save后重新打开，Last Modified 21:05且选项仍选中。
- 原TestFlight Internal Testing post-action与空Groups表保持，没有添加测试人员。
- 唯一annotated tag testflight-appstore-free-1.0-20261113已普通push并ls-remote回读；对象fed76bc6a95d43b1b187574a9ebc845dd832b663 → 源码321219f，无skip标记。不要再推新tag试探。
- 原生Xcode已出现该tag下**Build21**；详情Started21:08，Commit321219f，Xcode27.2/27B52、macOS27.2/26B123。Archive与TestFlight后处理SUCCESS，35条Warnings；实际1.0(21)已验证、无Internal徽标且商店可选，已保存关联并于11月14日新会话回读。
- Safari后台应用页加载间歇停滞；商务页已完成DSA。备用内置浏览器已打开官方登录页，Owner已重新登录Safari，内置浏览器不作为必需通道。不导出/搬运Safari凭据。

## 剩余执行

1. 从上述Xcode Reports入口观察Build21 Archive/后处理真实结果，失败时先分析日志，不重推tag。
2. 可取得发行Archive时核对三个Bundle版本、BuildProvenance精确321219f/tag/Dirty=false、生产entitlements、签名、三个Privacy Manifest及四份政策；源码12不当作实际云端编号。
3. TestFlight读取1.0(21)处理与内部专用标记，正式1.0构建选择器确认可选后保存关联。不把Archive成功、上传成功、Add for Review和Submit for Review混为一谈。
4. 继续免费价0、Owner新确认香港/澳门/台湾/美国供应范围、中英文资料回读；大陆待准入后开放。必要真机清单只绑定实际新包，沿用旧数据与CloudKit证据，不卸载/清库。
5. 材料/构建/必要人工事项关闭后按授权真正Submit for Review，手动发布模式保持，最终公开仍需Owner确认。

依据：[Archive发行准备选项](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions)、[正式发行工作流](https://developer.apple.com/documentation/xcode/creating-a-workflow-that-builds-your-app-for-distribution)、[内部标记含义](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers)。2026-11-13查阅。工作流保存、唯一tag触发、Build21成功及正式关联均已观察；签名包完整下载/独立字节核验NOT_RUN，送审尚未执行。
