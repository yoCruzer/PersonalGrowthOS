# App Store 免费首发执行台账

更新时间：2026-11-13；状态：**IN_PROGRESS / BUILD21_CLOUD_SUCCESS / NATIVE_UI_UNLOCK_REQUIRED**。Owner已恢复执行并完成Apple登录。下列当前快照优先于后附历史日志；整个首发Goal尚未完成。

## 2026-11-13 晚间续接（以本节覆盖旧待办）

Owner已回复“已解锁”“已填电话”，并确认本次无欧盟分发计划；指定公开版权显示“2026 随心log”；明确尚无备案。21时左右Computer Use实际可访问Safari，Apple会话有效。审核电话已在Apple私密字段回读，未复制到公开文件；免登录/审核备注/中文支持URL和五张截图均回读到，保存按钮disabled。版权显示已填写并保存。

英文版本资料已填写、五张英文原始截图上传后观察5/10；刷新持久化回读时Apple页面加载缓慢，尚不能把英文全部字段视为最终回读通过。将优先处理XcodeCloud可送审Archive配置，等待后台页面加载时继续台账。DSA已具备Owner事实确认，可保存“非交易商或无EU分发计划”；大陆尚无备案，不擅自移除/编造。Owner后续明确确认具备代码/图标/素材的分发权利，且不提供第三方内容服务，此人工事项已关闭。

21:05通过Xcode原生编辑器将既有Archive发行准备由Internal Only改为App Store Connect；重新打开确认已保存，Restrict Editing/原仓库/项目/iOS scheme/testflight-前缀任意文件触发保持。Latest Release环境保持，当前原生界面未暴露Clean选项，不冒称已改。唯一tag `testflight-appstore-free-1.0-20261113`已推送并回读：对象fed76bc6a95d43b1b187574a9ebc845dd832b663 → 非skip源码321219f。实际**Build21已在21:08启动并Running**，Xcode27.2/27B52、macOS27.2/26B123；尚未观察Archive成功/上传/处理或商店可选。

DSA已按Owner无EU计划保存；商务页显示“目前已完成所有监管要求”，DSA行状态有效（仅该商务页结论，不替代大陆App准入）。

已准备[大陆准入/备案成品技术材料](../Release/AppStore/Review/CHINA_MAINLAND.md)，含名称/Bundle/团队技术ID/功能说明/公开URL/图标截图与本人实名边界。尚无备案不能自动豁免；Owner已明确选择先港澳台美，大陆待准入后开放；待后台页面恢复后保存这四区，不自动选全球。

## 当前快照

| 项目 | 真实状态 |
| --- | --- |
| 已提交候选 | **`321219f61fd2dedf3be69d6f49c3af23896cccd4`**，已普通push，包含获准公开邮箱与网页入口；无skip构建标记 |
| 分支 / PR | `codex/app-store-free-release-20261110`；[Draft PR20](https://github.com/yoCruzer/PersonalGrowthOS/pull/20)，base `codex/icloud-product` / `4ec39f7`；未合并其他PR |
| 当前工作树 | `/private/tmp/pgos-app-store-release-20261110`；原主工作区三项他人改动完整保留 |
| 独立CI | [43341685409](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/43341685409)，前候选head741a00e，Release/Unit/Smoke全部SUCCESS，optional extended UI按原条件SKIP；Unit714PASS/1SKIP，Smoke8PASS。新候选321219f [CI43347067614](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/43347067614)整体SUCCESS：Release SUCCESS、Unit714PASS/0FAIL/1SKIP、Smoke8PASS/0FAIL/0SKIP。三份官方ZIP摘要/CRC、完整tree及独立测试节点计数均核验；optional extended UI按原条件SKIP |
| 源码版本 | App与两扩展1.0(12)；这是源码默认号，不能当作上传build号 |
| 最新实际TestFlight | 本轮前最新1.0(20)已验证但内部专用、商店禁选；新**Build21**已通过唯一标签实际启动，来源321219f，Archive与TestFlight后处理均SUCCESS，35条均Warnings；上传/处理/商店可选待读 |
| Apple正式版本 | **1.0 准备提交**。手动发布已保留；尚未Add for Review或Submit for Review |
| 版本字段 | Owner审核电话已在Apple私密字段回读，免登录/备注/中文支持URL、五张中文截图均回读且保存disabled；版权按Owner填写“2026 随心log”并保存。英文文案与五截图已填写/上传观察5/10，刷新完整持久化回读因后台加载停滞尚未完成 |
| App信息 | 名称沿用随心log；中文副标题“记录生活、习惯与每一步成长”；主生活/次效率已保存。英文名称随心log/副标题Journal, habits, small steps已观察“已保存” |
| 年龄分级 | 7步问卷复核，健康主题是、医疗治疗信息无，其余无；Apple计算**9+**，非儿童类，已保存 |
| App Privacy | 中文隐私URL与“未收集数据”答复已保存并发布。英文URL已保存并回读privacy-en.html；隐私答复发布不等于App上架 |
| 协议与DSA | 免费App协议有效；付费协议本次无需签。Owner确认无EU计划后DSA已实际保存，商务页监管完成提示及DSA行“有效”已回读 |
| 内容权利/版权 | Owner已明确确认代码/图标/素材分发权利且无第三方内容服务；版权显示指定“2026 随心log”，不改变AGPL-3.0 |
| 价格与地区 | **当前价格时间表**popover实际回读美国(USD)$0.00，不用通用价格计算器冒充当前值；四区已保存，澳门/美国/台湾/香港均“App发布时供应”，其他171区未供应。大陆待准入后开放 |
| 大陆备案 | Owner明确尚无备案；已完成备案技术材料成品。根据Owner新决定列为大陆开放前待办，不阻止继续四区材料/构建 |
| 公共网页 | 已上线并HTTP200/源码exact/桌面QA：主页与双语隐私、支持，gh-pages54df17e；公开邮箱已获准 |
| 公开联系 | justincookiec@outlook.com可公开；Apple审核电话仅在Apple私密字段，不进入仓库/网页/截图证据 |
| 构建与送审 | 本机定向UI/干净Release、新required CI均通过；testflight-appstore-free-1.0-20261113对象fed76bc6→321219f，Xcode原生确认Build21 Archive/后处理SUCCESS，35 warnings。17.1MB Archive/10.6MB app-store包下载已启动但未取得完整文件，锁屏后不能继续原生界面；尚未读到TestFlight处理/商店可选，未送审 |
| 当前浏览器能力 | Safari应用页通过列表重新进入后恢复，继续保存后台；备用内置浏览器官方登录页已打开，但登录不再是必需事项，已告知Owner。原生Xcode已完成Build21工作流；不转移Safari凭据 |
| 公开上线 | 未发布。审核通过后展示版本、免费价、四区与店页，等Owner一次明确确认再公开上线 |

## 授权、身份和数据边界

已授权必要代码修复、定向测试、普通提交/推送、独立分支/Draft PR、素材与后台保存、满足材料/构建/人工事项后提交审核及常规技术返修。免费0，无广告、IAP或订阅。本次沿用现有应用，不重写同步系统，不操作真实云库、不常规卸载或重复部署schema。

- 正式名称：随心log；Bundle `com.yocruzer.PersonalGrowthOS`；App Group `group.com.yocruzer.PersonalGrowthOS`；CloudKit `iCloud.com.yocruzer.PersonalGrowthOS`；Team `83SKX2PM7B`。
- App Store ID `6796425674`；[首发版本入口](https://appstoreconnect.apple.com/apps/6796425674/distribution/ios/version/inflight)。iPhone-only，iOS17+，简体中文/英语。签名TestFlight元数据已与源码身份核对。
- 最新产品线为 `codex/icloud-product` / `4ec39f7`，原Draft PR19 base `codex/icloud-sync-foundation`。main `dd09975`陈旧；原主工作区 `codex/todo-v1-personal-actions` / `d72c016`不充当发布候选。
- 用户2026-11-09手动部署Production schema后，在当时Build19“立即同步”成功，删除App/本地数据再安装观察到云端恢复。仅记录OWNER_REPORTED成功与恢复观察，不代表关系/原图/双设备/后台等全部场景通过。
- R1–R5本地保存、可恢复续传、busy尾部唤醒、推送过滤修复已存在于5910422；本轮真实代码复核和 `git diff --exit-code 5910422 -- PersonalGrowthOS/Sync PersonalGrowthOS/Persistence Packages SharedCapture`通过，未修改同步与schema。复用仍适用的61/61、transport28/28及既有迁移证据。
- 原工作区原有project.pbxproj、Localizable.xcstrings、xcodecloud目录修改未触碰；仓库AGPL-3.0许可证保持。私人联系方式/账户地址/税务标识不写公开证据。

## 成品、证据与实际限制

- [双语商店字段](../Release/AppStore/Metadata/README.md)、[数据流/问卷依据](../Release/AppStore/QUESTIONNAIRES.md)、[十张真实截图](../Release/AppStore/Screenshots/README.md)、[一轮真机清单](../Release/AppStore/Review/DEVICE_SMOKE.md)、[网页源码](../Release/AppStore/Website/dist/index.html)。
- [本机与CI证据](Evidence/AppStoreRelease20261113/README.md)：隔离模拟器E1E2C997-C665-4CCE-968B-B90B9FC61A3E，未登录真实iCloud；演示fixture仅DEBUG+UITesting+Reset，automaticSync=false。10张1206×2622原始RGB PNG，无alpha，逐张查看；未虚构界面或使用私人记录。
- 干净321219f本机Release来源/三个Bundle与四份政策资源逐字核验通过（clean-release-source-321219f.json），不是签名/上传证据；旧741a00e本机Release也通过。CI实际merge checkout a84f98c与741a00e完整tree相同。Unit唯一SKIP需隔离32MB HFS+镜像，未将SKIP当PASS。新增联系双语UI1PASS，新的候选Release/Unit/Smoke已全部通过。
- 已有5910422 Xcode Cloud成功Archive记录与Build20真实TestFlight状态保留，不能冒充本轮新代码签名/上传证据。

## 当前仅本人事项

- 当前没有新的必填本人事实缺项。英文隐私URL保存后Mac再次锁屏，已请Owner手动解锁；我未修改锁屏/密码设置。备用浏览器可以读到未登录页，但焦点交互失败，未视为已验证可替代原生界面。后续必要真机步骤只绑定实际处理成功的发行包。
- 已关闭人工事项：Mac解锁、审核电话、无EU计划的DSA事实、版权显示、代码图标素材分发权利/无第三方内容服务、四区首发决定；不重复询问。
- 大陆后续：Owner尚无备案，已明确四区先发/大陆待准入后开。本人实名/备案按[成品材料](../Release/AppStore/Review/CHINA_MAINLAND.md)后续办理，当前不购买服务或提交私人资料。
- 公开发布仍需审核通过后Owner最后一次明确确认；当前尚未到该阶段。

## 接下来持续执行

1. 获准联系与URL的双语定向UI、干净Release已通过，321219f已普通commit/push，原required CI已整体SUCCESS；不重复无变化本机全量715。
2. 后台恢复/备用浏览器登录后回读中英文版本和截图、补英文副标题/隐私URL，保存免费价0与Owner明确四区；确认Mac/Vision兼容分发与已验证设备范围一致。
3. Cloud配置、唯一tag及Build21 Archive/后处理成功已完成；解锁后先恢复下载并读取TestFlight处理/商店可选，完成发行包来源/签名/版本核验。不能再推第二个tag试探。
4. 观察上传/处理/版本匹配/商店可选；把少量真机步骤绑定实际新build，再集中处理Owner事实与验证。材料与阻塞关闭后Add for Review并真正Submit for Review，记录实际状态。
5. 审核中如不能持续监控，记录下次检查入口，不能声称后台等待。审核通过仍人工发布，需Owner最后明确确认；未公开可下载前不写已发布。

价格页另已读到默认开启Apple芯片Mac和Vision兼容分发（Vision当前不兼容）；本次iPhone首发须在后台明确收窄到已验证iPhone设备，尚未修改/保存。

拟用唯一标签`testflight-appstore-free-1.0-20261113`已只读ls-remote确认不存在，尚未创建。候选321219f完整提交消息无skip；最终tag必须指向该通过验证的非skip代码提交，不指向后续文档提交。Apple现有流程/发行准备尚需界面核实。[发行配置操作依据](../Release/AppStore/Review/XCODE_CLOUD_UPLOAD.md)。

本轮可独立完成项已收尾：候选321219f本机定向UI/干净Release及新独立CI全部通过；最后文档提交仅记录证据，不作为新发行候选。旧外部等待在晚间Owner回复后已关闭；Build21现已Archive与后处理SUCCESS，35 issues详情/处理状态仍需核对；Safari恢复后已继续完成四区/零价/英文副标题与政策URL；之后Mac又锁屏，目前需解锁再续接。继续执行入口为首发版本页与XCODE_CLOUD_UPLOAD.md；没有常驻监控Apple或声称后台等待审核。

2026-11-13后续Computer Use在“添加定价”时再次返回Mac已锁定；已请Owner解锁，代码/素材/台账同步继续。没有将本次锁屏当作Owner要求暂停Goal。

## 当前精确续接入口

1. 解锁Mac后读取原生Xcode：已打开的发布工作树 → Reports → Cloud → PersonalGrowthOS → TestFlight-workflow → testflight-appstore-free-1.0-20261113 → Build21 → Archive → Artifacts。Archive及app-store下载已开始，先观察完成/失败，不盲目重复下载或重推tag。可取得完整发行包后核验BuildProvenance、版本、签名/生产entitlements、Manifest与政策资源。
2. Safari当前已进入正式1.0版本页，尚未关联构建。先查看“添加构建版本”中实际新包是否可选；若未可选，进入TestFlight读取新包实际build号、处理/加密状态与内部标记。不能把Cloud build21编号直接当成已核实的TestFlight编号。
3. 中文/英文元数据与各5张截图已保存/观察；英文首轮被异步locale加载覆盖，已在加载稳定后重填保存。最终回读时等字段加载完，再确认描述/关键词/支持URL无回退。英文名称/副标题已观察“已保存”，双语政策URL已回读。
4. 已保存当前价美国USD$0.00；已保存澳门/美国/台湾/香港四区“App发布时供应”，其它171未供应；Mac与Vision可用性均0且保存完成。保持手动发布，最终公开仍等Owner明确确认。
5. Xcode此次自动生成xcshareddata/xcodecloud/manifest.json，产品ID65882429/target543C8892与既有记录一致；这是非运行时云产品绑定元数据，不改变发行候选321219f。主工作区原有同名未提交文件不触碰。

## 历史执行日志（不代表当前状态）

## 2026-11-13 恢复执行

- 用户“继续”撤销暂停。远端分支/标签与PR19未变化，原有主工作区三项修改未动。
- Computer Use可访问Safari；现有应用列表显示“随心log iOS1.0准备提交”，并提示DSA交易商状态。进入分发详情一直空白；刷新后官方登录页返回`authResult=FAILED`。没有读到当前构建、价格、地区、协议或版本字段，更没有保存后台。已请Owner在Safari直接登录及验证，不索取密码/验证码。
- 新增中英文商店字段成品：`Release/AppStore/Metadata/{zh-Hans,en-US}.json`；名称沿用随心log，副标题/描述/关键词/审核说明基于现有功能；关键词按100字节限制收紧。分类建议Lifestyle为主、Productivity为辅，后台未保存。
- 中英文隐私/支持静态网页：`Release/AppStore/Website/dist`，并有同文的App内离线版本。拟用GitHub Pages与公开Issues；已经集中询问Owner，尚未确认/部署。Apple支持网址要求实际联系方式，已单列请求可公开邮箱/地址/电话，未使用私人账户资料。
- App设置新增离线“隐私与支持”入口；无同步算法/业务schema变化。补三个可执行目标的Privacy Manifest，Widget元数据尺寸检查声明C617.1。完整数据流/问卷与依据见`Release/AppStore/QUESTIONNAIRES.md`。
- 隔离模拟器：`PGOS-AppStore-20261113` / `E1E2C997-C665-4CCE-968B-B90B9FC61A3E`，iPhone18Pro/iOS27.0；新建空设备，仅合成演示数据。已有uiTesting隔离库与automaticSync=false保持，未登录真实iCloud。
- Debug构建PASS，日志`/private/tmp/PGOS-AppStore-Debug.log`。首轮UI：本地保存/编辑/两次重开1PASS；新截图/政策测试因测试误写“时间轴”（实际“时间线”）1FAIL；原结果`/private/tmp/PGOS-AppStore-Screenshots1.xcresult`与log保留。修正测试名称，第二轮仅重跑该新测试。Release三Bundle构建进行中，不提前称通过。
- `python3 Scripts/AppStore/validate_materials.py`已PASS：字段字符/字节限制、本地网页链接、无脚本表单、网页/离线正文一致、清单plist可解析；JSON保存在`Docs/Evidence/AppStoreRelease20261113/materials-validation.json`。网页浏览器视觉QA和公开访问验证尚未完成。
- 仓库LICENSE为AGPL-3.0，保持原样；版权主体/实际分发权利需Owner事实确认，不自动改许可。

当前待办：完成双语截图视觉QA、最终Release包资源核对、普通提交推送及Draft PR；登录后核对并保存Apple必填项/免费价0/手动发布，读取真实TestFlight build及是否Internal Only；托管/公开联系/地区与法律事实等待Owner后合并处理。不以代码完成代替送审。


### 本机收尾与截图已完成

最终Screenshots3为1PASS/0FAIL/0SKIP（exit0），双语各5张原始RGB PNG、1206×2622、无alpha已导出到`Release/AppStore/Screenshots`并逐张视觉检查。第一轮本地保存/编辑/重开1PASS；第一、二轮截图测试失败原件保留，不改标成功。第二轮因测试在键盘显示时尝试切Tab，最终改为先正常保存并确认入时间线，再继续；未改产品或放宽断言。

Release三unsigned Bundle构建PASS，各自Manifest及四份政策资源逐字核对，source=4ec39f7/Dirty=true如实保留；不是签名/上传证明。详细实际命令、结果和NOT_RUN见[本机证据](Evidence/AppStoreRelease20261113/README.md)。没有重复本机全量Unit。此稳定节点将普通提交/推送并建立独立Draft PR，沿现有CI接受独立验证；不合并旧PR。


### GitHub交付与续接顺序

741a00e已普通push并创建/附加Draft PR20；实际CI43341685409运行中，未把空checks或排队当通过。`git diff --exit-code 5910422 -- PersonalGrowthOS/Sync PersonalGrowthOS/Persistence Packages SharedCapture`通过，复核四项同步修复仍在且未变化。当前发布分支干净，原工作区原有修改保持；主工作区台账副本同步供原入口查看。

Owner最小待办已集中发出：Safari官方App Store Connect完成登录/身份验证；确认拟用GitHub Pages＋Issues及公开支持联系方式；确认目标地区（推荐大陆/港澳台/美国，大陆准入待核实）。没有回复不视为确认。协议/DSA/备案/审核联系人/版权事实须登录后按实际缺项一次整理，当前不编造。

收到输入后：核对Apple真实最新build与Internal Only标记；将经确认的公开联系/托管信息合入成品并部署公开访问验证；最后固定候选、复用CI和适用验证，再用唯一testflight标签触发现有XcodeCloud并核实真实构建/处理。将[一轮集中真机清单](../Release/AppStore/Review/DEVICE_SMOKE.md)绑定实际build后使用，不现在重复要求陪测。全部满足后按已授权完成Add for Review及真正Submit for Review；不等同于公开发布。


干净候选增量Release复验：`PGOS-AppStore-CleanRelease-741a00e.log` exit0，BuildProvenance精确741a00e/Dirty=false，四份正文仍逐字一致（`clean-release-source.json`）。此次只为将已验证资源绑定普通提交，不重跑无变化全量测试。回环网页预览HTTP200，Codex浏览器预览请求queued，未冒称浏览器视觉QA已通过。


原正式图标已核对：`PersonalGrowthOS/Assets.xcassets/AppIcon.appiconset/PersonalGrowthOS-AppIcon-1024.png`存在，1024×1024、无alpha；已实际查看并确认编译App的CFBundleIcons/AppIcon资源存在。沿用既有图标，不重制品牌。
