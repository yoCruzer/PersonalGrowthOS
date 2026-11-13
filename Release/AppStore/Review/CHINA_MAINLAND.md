# 中国大陆准入与备案续接材料

更新时间：2026-11-13。Owner明确“尚无备案”。原目标为大陆、香港、澳门、台湾、美国；Owner已明确改为香港、澳门、台湾、美国先首发，大陆待准入后开放。四区清单尚未后台保存。不能把未具备备案事实写成已备案，也不能因免费/核心离线/使用iCloud直接认定豁免。

## 当前依据和待核实边界

Apple的App信息说明要求适用App的ICP编号和简体中文元数据与工信部备案一致；备案通过后编号会展示在产品页。Apple还为缺少/无效ICP设置了中国大陆不可用状态。[Apple App信息](https://developer.apple.com/cn/help/app-store-connect/reference/app-information/app-information)、[地区上架状态](https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-submission-statuses)。

工信部说明，主办者通过网络接入服务提供者或应用分发平台在线报送，涉及本人实名核验；材料齐全准确时在二十个工作日内办理，并要求新业务先履行适用备案手续。[工信部官方解读](https://www.miit.gov.cn/zwgk/zcjd/art/2023/art_39b4f1acc36745b98478e0ec3e07128d.html)、[备案系统](https://beian.miit.gov.cn/)。

本App核心可离线，但具备主动启用的CloudKit私库同步、网页来源预览和外链。本次不声称它是完全不联网的单机App，也不擅自作法律豁免声明。具体接入备案路径/适用性仍需平台或备案受理方核实；没有必要为“凑备案”新增无关服务器或功能。GitHub Pages支持网页的托管不等于App已经备案。

## 可直接使用的技术与内容材料

| 字段 | 已核实值 |
| --- | --- |
| App正式名称 | 随心log（含中文，沿用App Store现有身份） |
| iOS Bundle ID | com.yocruzer.PersonalGrowthOS |
| Apple Store记录ID | 6796425674 |
| 开发团队技术ID | 83SKX2PM7B；不是实名主体或备案编号 |
| 当前版本/上传候选 | 1.0；非skip代码321219f；XcodeCloud Build21正在构建 |
| 支持系统和语言 | iPhone，iOS17+；简体中文、英语 |
| 简短功能说明 | 个人图文生活记录、习惯、轻量待办、目标、重要日子、体重/睡眠/时间投入和手工家庭净资产记录；核心本地保存，可选用户自己的iCloud私库同步，无公开内容分发、银行连接、诊疗或投资服务 |
| 商店分类 | 生活（主）、效率（次）；备案平台分类需按其实际选项匹配，不冒充金融或医疗机构 |
| 免费与商业模式 | 下载0，无广告、内购、订阅 |
| 公开隐私政策 | https://yocruzer.github.io/PersonalGrowthOS/privacy-zh.html |
| 公开支持页面 | https://yocruzer.github.io/PersonalGrowthOS/support-zh.html |
| 公开支持邮箱 | justincookiec@outlook.com（Owner已明确允许公开） |
| 图标 | PersonalGrowthOS/Assets.xcassets/AppIcon.appiconset/PersonalGrowthOS-AppIcon-1024.png；1024×1024，无alpha，沿用既有正式图标 |
| 真实功能截图 | Release/AppStore/Screenshots/zh-Hans/01-today.png 至05-library.png；隔离合成演示数据、原始1206×2622 PNG |
| 内容权利 | Owner已确认具备代码/图标/素材分发权利，不提供第三方内容服务；AGPL-3.0不变 |
| 商店版权显示 | 2026 随心log；该展示文字不能替代备案实名主体 |
| iOS发行证书/公钥等备案技术字段 | 待最终签名Archive可取得后核对；不能使用unsigned本机包、猜值或私钥。按受理方具体字段提供必要的公开证书信息 |

## 必须本人办理的最小部分

1. 在实际接入服务提供者/应用分发平台核实适用备案路径，按本人或真实机构身份填写主体资料并完成实名/短信验证。当前未替Owner创建备案账户、接受新协议、购买服务或发送私人资料。
2. 所需签名等技术字段由最终Build21发行包/证书核实后提供，素材及上述技术值已经准备。备案需要的手机号/证件资料由Owner直接提交给受理方；Apple审核联系电话不能自动挪用于此用途或公开。
3. 取得有效App备案号后，在Apple「App信息 → 中国大陆ICP备案号」填写，并检查App名/主体/标识一致和后台验证结果；按适用要求补App内备案展示，再做受影响的定向验证。不能借用网站或其他App的编号。
4. 根据Owner最终地区决定保存供应范围。若先四区，大陆作为明确后续事项保留；若等待五区，继续完成构建和可办材料，真实标注备案外部等待。

本文件是成品技术材料和续接步骤，未声称已获得备案、法律豁免或中国大陆上架许可。
