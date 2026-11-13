# App Store 免费首发执行台账

更新时间：2026-11-13；状态：**IN_PROGRESS / APPLE_LOGIN_REQUIRED**。Owner已回复“继续”，暂停指令撤销。发布实现与素材继续；Apple后台详情需重新登录。

## 授权与发布边界

目标为现有“随心log”免费（0）首发，无新增广告、内购、订阅。已授权必要修复、定向验证、普通提交/推送、独立分支/Draft PR、素材与后台填写、构建上传及满足条件后提交审核。沿用身份；首发采用 Manually release this version，审核通过后必须等待 Owner 一次明确确认公开上线。身份验证、协议、真实法律/经营身份声明由 Owner 处理。

## 已核实事实

- 仓库：`yoCruzer/PersonalGrowthOS`。原工作区 `/Users/himini/Development/Projects/PersonalGrowthOS` 位于旧 `codex/todo-v1-personal-actions` / `d72c016dd34c8114cf44744d0e061b95bd312091`，有原有未提交 project.pbxproj、本地化和 xcodecloud manifest 修改；全部保留，未改动。
- 远端连接器与实际 SSH ls-remote 均核实最新产品分支 `codex/icloud-product` / `4ec39f7435812f0ad891b846f527e6d55c497409`；[Draft PR #19](https://github.com/yoCruzer/PersonalGrowthOS/pull/19) OPEN，base `codex/icloud-sync-foundation` / `07c1bcff2d2fae1f1a2d17271e36266aadb97d6a`。main 仍是旧 `dd09975d3a3736b24f8646fa4f197cc883ab1796`，不能作为最新候选。
- 现有已验证代码候选：`59104222b0ca654ca5cffa8faed3e2f208e91b2e`。不可移动 annotated tag `testflight-icloud-reliability-20261109` 对象 `031e8eb3678b37ffb89fa02a46aa8073297b776c` 精确解引用该代码；分支后续提交仅文档。
- 发布工作树已建立：`/private/tmp/pgos-app-store-release-20261110`，分支 `codex/app-store-free-release-20261110`，起点 `4ec39f7`。未提交/推送，未建新 PR。同机 `/private/tmp/pfos-app-store-release` 属于其他 PersonalFinanceOS 仓库，不能混用。
- 代码身份：显示名称“随心log”；Bundle ID `com.yocruzer.PersonalGrowthOS`；App Group `group.com.yocruzer.PersonalGrowthOS`；CloudKit `iCloud.com.yocruzer.PersonalGrowthOS`；Team `83SKX2PM7B`；iPhone-only / iOS17+；主App/分享扩展/重要日子Widget均为源码版本1.0(12)。**云端实际build号尚未读取，不能把源码12当作TestFlight build号。**
- App Store Connect记录ID `6796425674`、team路径 `e47fce78-79c8-4993-88a4-32f833bc1936`，来自既有构建证据，尚未本轮后台复验。
- 已有证据 [xcode-cloud-result.json](Evidence/iCloudReliability20261109/xcode-cloud-result.json)：5910422 的 Archive 与工作流 SUCCESS，0 errors/0 test failures/35 warnings；[构建入口](https://appstoreconnect.apple.com/teams/e47fce78-79c8-4993-88a4-32f833bc1936/apps/6796425674/ci/builds/59018cf0-c866-4b25-92c5-8a6052eb6272)。TestFlight可用、处理成功及商店可选状态仍 NOT_OBSERVED。
- PR19与既有文档记录本地保存受阻、可恢复错误续传、busy尾部续跑、推送过滤均已修复。已有最新产品CI Unit715=714PASS/1SKIP、Smoke8/8及三unsigned Release Bundle；本机61/61、最终transport28/28。本轮只读取证据摘要，未重新验证源码或测试，不重复冒称通过；后续需核对当前实现及证据适用性。
- Owner 2026-11-09 已手动部署 Production schema，当时 Build19 立即同步成功；删App/本地数据后重新安装观察到云端数据返回。仅为用户报告的成功/恢复观察，不代表全量关系、原图、双设备、后台或所有同步场景通过。不要求重复部署相同schema或常规删装。

## 能力检查与实际操作

- 已按主工作区 AGENTS 阅读 Foundation、Development Contract、CURRENT；最新产品工作树 INDEX/CURRENT 与 Foundation 增量已读取。续接后按最新工作树约束补齐相关文档再修改产品。
- 本机 Xcode27.2 / 27B52。`gh auth status` 报现有token无效；GitHub连接器具备仓库push/admin权限。沙箱内网络解析失败；获批提权的 `git ls-remote --heads --tags origin` 与 `git fetch origin codex/icloud-product --tags` 成功，不需要因此先要求Owner重新登录gh。
- 独立 `git worktree add -b codex/app-store-free-release-20261110 /private/tmp/pgos-app-store-release-20261110 4ec39f7...` 成功，未触及原有修改。
- Computer Use可发现Safari，无已连接浏览器。读取Safari时返回 **Mac已锁定，自动解锁失败**；未读取Apple后台、未填写、上传或提交。
- 已通知Owner手动解锁；Owner选择暂停整个任务。无构建/测试/上传/送审/公开发布。本轮仅状态核对，无产品代码改动。

## 下一步（Owner恢复后）

1. Owner回到Mac并解锁，明确回复继续；恢复Goal，复验工作树/远端未发生变化。
2. 优先检查已有App Store Connect权限、协议、TestFlight最新build、版本1.0状态、价格、地区、必填项、DSA与大陆备案；可用API优先，界面访问经Computer Use。不得根据Archive成功假设上传处理完成。
3. 完成当前代码与数据流审查、隐私Manifest/权限、真实功能文案和双语字段限制核验；复用仍适用的CI证据，必要修复只做定向验证。
4. 隔离演示环境真实候选界面截图4–6张；制作隐私/支持网页成品；核实获准托管位置及可公开联系方式，不将私人联系方式自动公开。
5. 统一列出地区/大陆备案/DSA/内容权利/加密等必要本人事实确认，继续其他可办事项；材料与实际build齐备后提交审核，人工发布模式保持。
6. 证据/素材写入仓库适当目录；普通推送本发布分支及Draft PR。暂停前尚未执行GitHub同步，恢复后补做，不声称已同步。

## 当前人工事项

仅：回到Mac后手动解锁并回复继续。其余字段尚未后台核对，不预先假设缺项。当前不是已上传、已提交审核或已发布状态。


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
