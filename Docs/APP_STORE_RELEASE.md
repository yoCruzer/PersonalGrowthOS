# App Store 免费首发执行台账

更新时间：2026-11-15 15:30（Asia/Shanghai）。**COMPLETE / PUBLIC_RELEASE_VERIFIED：随心log 1.0 (21) 已获审核通过、经Owner明确确认并发布；港澳台及美国四区公开商店记录、版本1.0与免费价格均已核验，实际公开产品页面已打开。** 本次免费首发Goal已完成，无剩余本人事项。

## 最终上线结果与公开入口

- 已发布：**随心log 1.0 (21)**；非skip代码候选**321219f61fd2dedf3be69d6f49c3af23896cccd4**；沿用Bundle、App Group、CloudKit及Team身份。
- 发布授权：Owner在核对已批准版本/免费价格/四区/Apple产品页面预览后，明确回复**“确认公开上线”**。15:20点击并确认四区发布，Apple currentVersionReleaseDate为**2026-11-15T07:20:37Z（北京时间15:20:37）**；后台变为可分发、构建21保持。
- 公开核验：15:29–15:30 Apple公共API四区均返回唯一6796425674、正确Bundle、**1.0**、**price0**；Safari实际公开美国店页完整显示正式图标、五张截图、英文副标题、Only for iPhone、**Free**、**9+**、隐私链接及©2026 随心log。
- 首发范围仅**香港、澳门、台湾、美国**，后台四区均可供应，其余171区未供应；Mac/Vision分发关闭。大陆按Owner决定仍待备案/准入后开放，不是本次首发遗留阻塞。

| 公开商店 | 免费价格（公开API） | 产品页面 |
| --- | --- | --- |
| 香港 | HKD 0 / 免費 | [随心log 香港](https://apps.apple.com/hk/app/%E9%9A%8F%E5%BF%83log/id6796425674) |
| 澳门 | USD 0 / 免費 | [随心log 澳门](https://apps.apple.com/mo/app/%E9%9A%8F%E5%BF%83log/id6796425674) |
| 台湾 | TWD 0 / 免費 | [随心log 台湾](https://apps.apple.com/tw/app/%E9%9A%8F%E5%BF%83log/id6796425674) |
| 美国 | USD 0 / Free | [随心log 美国](https://apps.apple.com/us/app/%E9%9A%8F%E5%BF%83log/id6796425674) |

[批准凭证](Evidence/AppStoreRelease20261113/app-review-approved-20261115.json)、[Owner确认/发布/公开核验](Evidence/AppStoreRelease20261113/public-release-20261115.json)、[四区最终记录](Evidence/AppStoreRelease20261113/public-four-storefronts-20261115.json)。没有当前需回复的Apple留言、技术返修或Owner待办。

早期公开Lookup返回0和页面未找到均按原样保留。普通id-only查询头max-age约24小时，缓存了首发前空结果；明确entity=software后四区返回记录，实际canonical页面也已显示。旧空结果不再代表当前状态。Lookup旧contentAdvisoryRating为4+，现代公开店页与后台问卷为9+，未为消除差异而更改任何问卷。Agent未做商店版真机安装，核验范围为公开商店提供获取及既有Build21 Owner功能冒烟；不宣称完成新的安装测试。

## 候选、身份与交付

| 项目 | 已核实状态 |
| --- | --- |
| 应用 | 随心log；App Store ID 6796425674；iPhone / iOS 17+；简体中文、英文 |
| 身份 | Bundle `com.yocruzer.PersonalGrowthOS`；App Group `group.com.yocruzer.PersonalGrowthOS`；CloudKit `iCloud.com.yocruzer.PersonalGrowthOS`；Team `83SKX2PM7B` |
| 非skip代码候选 | **321219f61fd2dedf3be69d6f49c3af23896cccd4**；其后的文档提交不改变此候选 |
| 标签 | `testflight-appstore-free-1.0-20261113`；对象fed76bc6a95d43b1b187574a9ebc845dd832b663 → 精确321219f；唯一且不可移动，不再推tag试探 |
| Git交付 | `codex/app-store-free-release-20261110` / [Draft PR20](https://github.com/yoCruzer/PersonalGrowthOS/pull/20)，base `codex/icloud-product` / 4ec39f7，未合并其他PR |
| 工作树 | `/private/tmp/pgos-app-store-release-20261110`；主工作区原有project.pbxproj、Localizable.xcstrings及xcodecloud目录修改保留 |
| 代码边界 | App内双语隐私/支持入口、三目标Privacy Manifest、隔离演示素材与发布材料；未改同步系统、持久化schema或应用身份 |

## Apple 后台实态

| 项目 | 实际证据与剩余限制 |
| --- | --- |
| 构建 | **1.0 (21)**，TestFlight元数据“已验证”，无Internal徽标；11月13日21:20上传。版本选择器21可选、20–16禁选；11月14日重新登录后正式版本表格回读21 / 1.0，Save disabled，构建关联已持久化 |
| 云构建 | 原工作流发行准备已保存为App Store Connect；原testflight-触发条件保持。Build21来源321219f，Archive及后处理SUCCESS，35条Warnings，非零warnings；Xcode27.2/27B52，云macOS27.2/26B123 |
| 正式版本 | **1.0可分发，四区公开记录与实际产品页面已验证**；11月15日Owner确认后发布，构建21保持 |
| 发布方式 | 手动发布已执行；Owner最终确认已收到，15:20发布、15:30公开核验完成 |
| 价格与供应 | 当前价格时间表实际回读美国USD **$0.00**；香港、澳门、台湾、美国4区“App发布时供应”，其余171区未供应；Mac/Vision兼容分发关闭。11月15日审核通过后再次展开当前价popover及四区清单确认 |
| 名称与类别 | 随心log；中文副标题“记录生活、习惯与每一步成长”；英文“Journal, habits, small steps”；生活为主、效率为次，已保存 |
| 文案与截图 | 中英文各5张真实候选界面原始截图，1206×2622/RGB无alpha。英文曾被异步locale加载覆盖，稳定重填后完整14段描述、关键词、support-en URL、5截图、Save disabled全部回读；中文文案11月14日新会话再次读到 |
| 审核信息 | 不需要开发者账号登录；备注已保存；获准公开邮箱已填；Owner审核电话仅在Apple私密字段，11月14日确认仍存在，不入库。版权“2026 随心log” |
| 隐私与年龄 | 依据实际数据流完成Data Not Collected答复并发布，双语隐私URL已保存；无广告/跟踪/第三方分析。Apple年龄问卷计算9+，健康主题是、医疗治疗无，非儿童类 |
| 协议与DSA | 免费协议有效2026-10-29至2027-07-27；本次免费无IAP不签付费协议。Owner确认无EU计划，DSA已保存、商务行有效；该页面结论不替代大陆准入 |
| 大陆 | Owner明确尚无备案，并选择先港澳台美、大陆待准入后开放。[备案成品技术材料](../Release/AppStore/Review/CHINA_MAINLAND.md)已备；不编造豁免、不静默改变地区 |

## 已完成的验证与成品

- [本机/CI详细证据](Evidence/AppStoreRelease20261113/README.md)：最终候选本机联系入口UI 1PASS、干净Release成功；三个unsigned Bundle身份与Manifest、四份政策资源逐字相同，BuildProvenance精确321219f / Dirty=false。源码默认1.0(12)与实际云包1.0(21)区分记录。
- [required CI43347067614](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/43347067614)整体SUCCESS：Unit714PASS/0FAIL/1SKIP，Smoke8PASS/0FAIL/0SKIP，Release成功。实际checkout e30c26e完整tree与321219f相同；三个官方ZIP摘要/CRC、独立测试节点计数核验。唯一低空间测试需32MB HFS+镜像，optional extended UI按原条件未跑。不因文档/后台变化重跑715。
- 同步R1–R5修复仍来自5910422，本轮源码比对未变化；复用本机61/61与transport28/28、既有升级证据。用户11月9日手动部署Production schema后，Build19立即同步成功并观察删装后恢复，仅记OWNER_REPORTED，不能代表全部同步场景。禁止为本轮重复部署相同schema、清真实云库或常规卸载。
- [双语商店字段](../Release/AppStore/Metadata/README.md)、[数据流及问卷依据](../Release/AppStore/QUESTIONNAIRES.md)、[10张真实截图](../Release/AppStore/Screenshots/README.md)、[一次真机清单](../Release/AppStore/Review/DEVICE_SMOKE.md)。演示数据仅隔离模拟器DEBUG+UITesting+Reset，automaticSync=false，不接真实iCloud，不含个人记录。
- [公开主页](https://yocruzer.github.io/PersonalGrowthOS/)、双语隐私/支持共6静态文件部署gh-pages54df17e，Pages43344768324；HTTP200/源码exact、Safari桌面视觉QA通过；11月14日再次联网检查6文件均200且字节相同（public-urls-20261114.json）。公开邮箱justincookiec@outlook.com与GitHub Issues均获Owner授权。App内离线正文与网页一致；移动viewport/大陆网络实测NOT_RUN。

## 发行包核验限制

Apple已验证的21元数据：Bundle正确、最低iOS17、arm64/iPhone、双语、含符号、非豁免加密No。Widget可见entitlements有正确Team/App Group、get-task-allow=false；AX完整文本截断，主App生产entitlements尚未独立导出核验。

原生Xcode/官方下载同一app-store产物多次网络停滞；11月14日09:05文件仍不完整：Safari835069字节、Xcode6159323字节、Archive0字节，均非完整ZIP。未取得完整签名包，签名/包内资源逐字核验**NOT_RUN**，不以unsigned构建冒充通过。权限导出启动TextEdit发生工具长时间超时，未导出成功；未重建、未重推标签、未导出会话凭据。后续优先使用已验证Apple元数据/来源及已有资源证据，下载如恢复再补独立二进制核验，不把反复下载当成必然发布门。

## 完成、后续边界与续接

- **本次Goal完成，当前无本人待填/待测/待确认事项。** 1.0(21)已审核批准、确认公开、发布并核验四区公开零价；不再重复请求确认、推tag、构建或提交同一版本。
- 未来常规版本、一般体验优化、大陆备案后开放不并入本次首发扩大开发。按新任务边界推进；App身份、AGPL-3.0与Owner已确认事实保持。
- 仍保留真实测试限制：签名包独立字节核验NOT_RUN、同步复杂场景非全覆盖、没有agent商店版真机安装。它们不是被伪记为PASS的发布门；Apple已验证构建、本机/CI、Owner Build21冒烟及公开记录证据各自限定。
- 原主工作区三项修改保留，Draft PR20保持原base且不擅自合并；发布素材/源码/证据均已普通推送独立发布分支。没有改写远端历史、处理无关PR、清生产数据或重复部署schema。

## 精确续接入口

- **优先公开入口：上表四区App Store链接。** 后台[四区供应状态](https://appstoreconnect.apple.com/apps/6796425674/distribution/pricing/availability)**；[可分发版本](https://appstoreconnect.apple.com/apps/6796425674/distribution/ios/version/deliverable)；公开美国页面 `https://apps.apple.com/us/app/id6796425674`；Apple Lookup按HK/MO/TW/US查询6796425674。
- [本次实际审核提交](https://appstoreconnect.apple.com/apps/6796425674/distribution/reviewsubmissions/details/ba1b52ad-7773-426f-997f-6bac1671795e)**。
- [正式1.0版本](https://appstoreconnect.apple.com/apps/6796425674/distribution/ios/version/inflight)；[App审核](https://appstoreconnect.apple.com/apps/6796425674/distribution/reviewsubmissions)；[价格与销售范围](https://appstoreconnect.apple.com/apps/6796425674/distribution/pricing)。
- [Build21元数据](https://appstoreconnect.apple.com/teams/e47fce78-79c8-4993-88a4-32f833bc1936/apps/6796425674/testflight/ios/c3af9b4a-278d-429d-ad12-4367e654d8f5/metadata)；[既有内部群组](https://appstoreconnect.apple.com/teams/e47fce78-79c8-4993-88a4-32f833bc1936/apps/6796425674/testflight/groups/b8156fe6-1389-471b-be34-59d81bf20fd8)。
- [Cloud Build21](https://appstoreconnect.apple.com/teams/e47fce78-79c8-4993-88a4-32f833bc1936/xcode-cloud/products/543C8892-7DD6-4620-B16C-B4F7DFE0255E/builds/4ef1895e-3551-4cd4-98b9-2050d779abbf/summary)；[上传执行记录](../Release/AppStore/Review/XCODE_CLOUD_UPLOAD.md)。
- 历史逐步观察见本目录Git历史及[本机/CI证据](Evidence/AppStoreRelease20261113/README.md)，不将旧“待上传/待保存”当作当前状态。
