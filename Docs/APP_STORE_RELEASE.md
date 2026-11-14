# App Store 免费首发执行台账

更新时间：2026-11-14 09:15（Asia/Shanghai）。**IN_PROGRESS：1.0 (21) 已上传、已验证并关联正式版本；尚未送审、尚未公开发布。** 用户恢复执行的授权保持有效。本页当前状态优先于历史记录；没有常驻后台监控。

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
| 正式版本 | **1.0 准备提交**；未Add for Review、未Submit for Review |
| 发布方式 | **Manually release this version**，11月14日新会话回读选中；审核通过后仍须Owner最终明确确认才公开 |
| 价格与供应 | 当前价格时间表实际回读美国USD **$0.00**；香港、澳门、台湾、美国4区“App发布时供应”，其余171区未供应；Mac/Vision兼容分发关闭。11月14日新会话再次展开当前价popover及四区清单确认 |
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

## 本人事项与下一步

1. 11月14日09:05实测Mac**未锁屏**，但Safari旧会话authResult=FAILED；Owner已重新登录，应用列表和正式版本已读，登录阻塞关闭。未更改锁屏/密码设置。
2. 已在既有内部群组实际读到两台设备11月14日安装1.0(21)，无需再关联或邀请；已向Owner发出[一轮约5分钟真机清单](../Release/AppStore/Review/DEVICE_SMOKE.md)，不卸载、不清库、保持原iCloud账号。等待实际执行结果，不能提前记PASS。
3. 构建关联/手动发布已新会话回读；复核双语截图、零价四区与有效URL。材料与必要人工事项关闭后，按既有授权执行Add for Review并真正Submit for Review，分别记录实际状态，不重复请求普通操作许可。
4. 审核期间如无持续运行能力，保存检查入口并如实标等待；技术拒审自行分析/修复/重提。审核通过后展示最终版本、免费价、四区与店页，等Owner一次明确公开确认；未公开可下载前不写“已发布”。

已关闭人工事实：公开托管/邮箱、审核电话、DSA无EU计划、版权显示、代码图标素材分发权利/无第三方服务、四区决定。AGPL-3.0保留，不重复询问。原开发分支/他人修改不动，不处理无关PR或改写远端历史。

## 精确续接入口

- [正式1.0版本](https://appstoreconnect.apple.com/apps/6796425674/distribution/ios/version/inflight)；[App审核](https://appstoreconnect.apple.com/apps/6796425674/distribution/reviewsubmissions)；[价格与销售范围](https://appstoreconnect.apple.com/apps/6796425674/distribution/pricing)。
- [Build21元数据](https://appstoreconnect.apple.com/teams/e47fce78-79c8-4993-88a4-32f833bc1936/apps/6796425674/testflight/ios/c3af9b4a-278d-429d-ad12-4367e654d8f5/metadata)；[既有内部群组](https://appstoreconnect.apple.com/teams/e47fce78-79c8-4993-88a4-32f833bc1936/apps/6796425674/testflight/groups/b8156fe6-1389-471b-be34-59d81bf20fd8)。
- [Cloud Build21](https://appstoreconnect.apple.com/teams/e47fce78-79c8-4993-88a4-32f833bc1936/xcode-cloud/products/543C8892-7DD6-4620-B16C-B4F7DFE0255E/builds/4ef1895e-3551-4cd4-98b9-2050d779abbf/summary)；[上传执行记录](../Release/AppStore/Review/XCODE_CLOUD_UPLOAD.md)。
- 历史逐步观察见本目录Git历史及[本机/CI证据](Evidence/AppStoreRelease20261113/README.md)，不将旧“待上传/待保存”当作当前状态。
