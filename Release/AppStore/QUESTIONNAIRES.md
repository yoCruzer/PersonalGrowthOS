# 首发问卷与实现依据（2026-11-13）

按候选代码与2026-11-13实际Apple后台核对。当前已保存健康主题=是/医疗治疗信息=无并由Apple计算9+；隐私URL和“未收集数据”答复已发布。其他问卷是否已保存以Docs/APP_STORE_RELEASE.md为准，不能将准备答案一概视为已提交。

## App Privacy

建议当前答案：**开发者不收集数据 / Data Not Collected**；不跟踪。此结论来自数据流检查，并非由免费或本地优先推导。

| 数据 | 处理位置与对外路径 | 当前申报依据 |
| --- | --- | --- |
| 日记/标签/关联/待办/习惯/目标/回顾 | 本地 SwiftData；主动开启后到用户自己的 CloudKit private database | 未送到开发者后端；开发者不能读取用户私库 |
| 图片与重要日子封面 | 选中的原图复制到App；私有iCloud同步；用户选择的分享/备份目的地 | 无媒体分析或开发者上传端点 |
| 体重/身高/睡眠 | 手动本地记录，可选私有iCloud；无HealthKit | 不把健康数据自动发给开发者；政策明确涵盖这些敏感内容 |
| 时间投入、手工资产负债余额 | 本地记录，可选私有iCloud；ZIP/CSV由用户主动导出 | 无银行连接、行情接口、自动财务上传 |
| 设置/通知/闹钟 | UserDefaults/系统本机调度 | 无推送营销服务器；CloudKit的系统推送只唤醒同步 |
| 小组件 | 同一App Group中的被授权标题/日期/封面投影 | 无额外网络或SDK |
| 网页分享预览及来源/参考链接 | LinkPresentation可请求所分享URL；外部浏览器打开来源/文档 | 不是开发者控制的内容采集端点；如实告知目标站点可接收普通访问请求 |
| 错误/诊断/系统日志 | 本地；用户主动复制/分享 | 无自动遥测；公开问题仅应含脱敏描述。Owner已批准公开GitHub Issues和支持邮箱；主动、可选支持内容只为回复问题处理，不用于营销或其他用途 |
| SDK/依赖 | Apple系统框架与仓库自己的本地SyncFoundation包 | 当前工程无外部分析/广告/崩溃收集SDK，无第三方网络依赖 |

若后续新增开发者收集端点、分析SDK、自动日志上传或其他服务，必须重新审查，不沿用“不收集”。用户向开发者提交支持内容由其主动操作，不能要求其发送真实日记或整库。

[Apple对collect的定义、系统服务及设备内数据指导](https://developer.apple.com/app-store/app-privacy-details/)：关注开发者或合作方是否能持续访问设备外数据；Apple自身处理的数据无需由开发者代报。政策仍完整披露iCloud、分享、备份及外链。

## Privacy Manifest / 权限

- 主App：UserDefaults `CA92.1`（本App偏好）；FileTimestamp `C617.1`（容器内metadata）和 `3B52.1`（用户授权选中文件）；DiskSpace `E174.1`（写入/导入前空间不足时实际拒绝）；SystemBootTime `35F9.1`（进程内计时，raw awakeUptime参数不参与持久化/同步）。
- Widget：`attributesOfItem`检查App Group snapshot尺寸上限，声明FileTimestamp `C617.1`。
- Share Extension：当前源码通过URLResourceValues检查选择内容大小/安全类型，未发现另需声明的所列required-reason API；单独携带无跟踪/无收集清单。
- 相机：主动拍摄请求；照片使用系统选择器；通知/AlarmKit按主动启用请求。无联系人、位置、麦克风、HealthKit或ATT请求。
- 清单与权限说明须进入最终三个Bundle并检查，源码文件存在不代表打包完成。

[Apple API类别与允许理由](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)、[TN3183](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)。

## 年龄分级 / 医疗声明

- 不含广告、公开UGC分发、社交feed、聊天、无限制内嵌浏览器、暴力/性/赌博/随机付费机制或竞赛。
- 用户私人日记及系统分享不是面向广泛用户分发的社交UGC。
- **Health or Wellness Topics：是**。有手工体重/睡眠和成人BMI参考。
- Medical or Treatment Information：无诊断/治疗建议；如后台把成人BMI参照纳入该项，按实际定义说明并选适用最低频次，不一概全否。
- 不是受监管医疗器械，不宣称监测、诊断、治疗；成人BMI不适用于儿童、孕期或专业诊断。
- 不选择Made for Kids。分级由Apple基于实际答案计算，不预填4+。
- Apple公告2026-11-16新增内容描述符，若送审跨该日期须回读新问卷：[公告](https://developer.apple.com/news/?id=yxkh08us)。

[分级定义](https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions)、[设置分级](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)。

## 加密出口合规

现有`ITSAppUsesNonExemptEncryption=NO`。CloudKit/TLS等加密来自Apple系统；自有CryptoKit SHA256用于校验/身份散列，不是自研保密加密。备份明确未加密，无自研AES/ChaCha/加密隧道。按当前代码建议沿用“无非豁免加密”，若后台询问则准确说明仅系统加密与校验哈希，不回答“完全不用任何加密”。最终出口声明责任及无法从代码证明的事实由Owner确认。

[Apple出口文件要求](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/)。

## 内容权利与市场准入（需本人事实）

- Demo插图由本仓库UIKit几何绘制，文案为原创合成内容；不含私人记录、授权未知照片、虚构用户评价。不得冒充真实用户数据。
- Owner晚间已明确确认具备代码/图标/素材分发权利，且不提供第三方内容服务；版权显示按Owner为2026 随心log，许可证不改。
- DSA：Owner明确本次无EU分发计划后，已实际选择“非交易商或无EU分发计划”并完成；Business表格状态有效、监管完成提示已回读。没有因个人/免费自动推断身份。
- 中国大陆：后台ICP字段实际为空；需核对ICP备案适用性和平台准入是否要求、备案主体/名称/标识匹配。未确认时不静默排除大陆，也不擅自全球发行。
- Owner晚间明确决定香港、澳门、台湾、美国先首发，大陆待准入后开放；四区尚未后台保存。免费价0已授权，定价页面加载停滞，尚未保存回读。

[大陆App信息要求](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/)、[DSA指导](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/)。

## 已有代码许可证

仓库根 `LICENSE` 为AGPL-3.0，保留原样；当前工程仅链接Apple框架和本仓库本地包，未新增第三方SDK。公开仓库可取得对应源码，不能把“源码公开”写成无版权限制或自动改成闭源许可。App Store发行所需的版权主体、全部分发权利及任何额外授权，已获Owner明确事实确认；本轮没有更改许可或签署新协议。
