# 时间投入 V1 外部 Review 修复 — READY_FOR_OWNER_DEVICE_GATE（2026-10-17）

本节覆盖本轮外部 Review 修复，后文原始阶段记录完整保留。固定输入/最终 SHA/剩余设备边界见 [CURRENT_STATE](CURRENT_STATE.md)。指定评论原文已完整保存为 `external-review-6234984209.json`，SHA-256 `2493c7dc5742fb359143a8cc865e346426c8cdc8c484966333d4764a7a680e3d`。

## 环境、固定对象与命令

本轮从 clean92dc 沿原 worktree `/Users/himini/.codex/worktrees/time-investment-v1/PersonalGrowthOS` 安全续接；不是重建分支。只读首检 `xcodebuild -checkFirstLaunchStatus` 与 `xcrun simctl list devices available` / runtimes 均 exit0。Xcode27.1/27A9275、CoreSimulator1174.9.2、专用 sim `540825BC-D0D4-4D71-B8DF-D73B243C3726` / iOS27.0/24A434。无 sudo、系统修复、删模拟器或真实私库访问。仅对该合成 sim 显式设 Dark/Light；最终恢复 Light，不根据 launch 参数推断外观。始终单一 Xcode 队列。

最终产品/测试 `2c5b4c52edbf69c1562ff9eae491616335b97472`；最后生产 `c91866e6abfef0241ae4ae266ee8f02f51f76393`；固定 BASE/Goal1.1、V14/v10及所有历史 schema 不变。新日志/result 均 `/tmp/pgos-ti-review-<run>.log/.xcresult`；SHA、完整命令、计数、log SHA-256 和 warnings 在新证据根 `native-run-index.json`。旧证据 `/tmp/pgos-time-investment-evidence` 原样保留。

```sh
xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -sdk iphonesimulator -arch arm64 -derivedDataPath /tmp/pgos-time-investment-derived -resultBundlePath /tmp/pgos-ti-review-compile10.xcresult CODE_SIGNING_ALLOWED=NO build-for-testing

xcodebuild test-without-building -xctestrun /tmp/pgos-time-investment-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=540825BC-D0D4-4D71-B8DF-D73B243C3726' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-ti-review-final-unit-ax1.xcresult -only-testing:PersonalGrowthOSTests -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testExternalR3ChineseDarkAXConfirmationPreservesOrExplicitlyReplacesSegments

xcodebuild test-without-building -xctestrun /tmp/pgos-time-investment-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=540825BC-D0D4-4D71-B8DF-D73B243C3726' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-ti-review-final-dark4.xcresult -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testExternalR3ChineseDarkAXConfirmationPreservesOrExplicitlyReplacesSegments

xcodebuild test-without-building -xctestrun /tmp/pgos-time-investment-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=540825BC-D0D4-4D71-B8DF-D73B243C3726' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-ti-review-final-light1.xcresult -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testExternalR2FailedCloseKeepsEditorAndRetrySurvivesColdLaunch -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testExternalR3MultipleSegmentsRequireExplicitContinuousReplacement

xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/pgos-time-investment-release-derived -resultBundlePath /tmp/pgos-ti-review-release2.xcresult CODE_SIGNING_ALLOWED=NO build
```

第二条完整 Unit 命令实际执行于 clean d5db223/compile5；不能拿本节最终 compile10 倒推它的源码。其后逐候选有独立 build-for-testing，最后两条 UI 用同一 f077598 产物 test-without-building，不重复构建。该 Release 仅编译验证，不是可安装签名 IPA。

## 分轮真实结果

| SHA / run | 实际结果 | 解释 |
| --- | --- | --- |
| 39c162b / compile1 | FAIL | 新测试缺 Entry.createdAt 参数；原 log 保留，精确 exit 未单独保存，未写假数字 |
| c8b6b54 / compile2、red1 | 编译 PASS；5 项 **0 PASS/5 FAIL/0 SKIP，exit65** | 原生产行为经注入 seam/等价提取真实复现，三磁盘＋两 UI；不是先修复再声称红测 |
| 499e75d / compile3、green1 | 编译 PASS；**4 PASS/1 FAIL，exit65** | R1/R2/R3磁盘及R2UI过；native confirmationDialog 只显示替换，取消按钮缺失，保留失败 |
| 0200511 / compile4、green2 | 编译 PASS；**21/21 PASS，exit0** | 19持久＋R2/R3UI；原型alert在英文Light完整可读，2条Invalid frame。后续新增AX发现不能沿用这一视觉结论 |
| d5db223 / compile5、final-unit-ax1 | Unit467项 **466 PASS/0 FAIL/1 SKIP**；整轮468项 **466 PASS/1 FAIL/1 SKIP，exit65** | 完整相邻回归；独立Reviewer要求新增delete前后故障/新UUID/参与者反例PASS。额外中文AXUI失败：系统alert截断warning/20→25，测试取消后只向下找上方minutes也失败 |
| a722fe9 / compile6、final-dark1 | **44 PASS/1 FAIL/0 SKIP，exit65** | 核心23＋持久20全PASS，相邻中文Record草稿AX1PASS；可滚动确认页内容完整，但内层导航条手势未关闭，UI余下步骤NOT_RUN |
| c91866e / compile7、final-dark2 | 编译 PASS；UI **0 PASS/1 FAIL，exit65** | 显式内层false未解决相同导航条手势，不声称继承禁用根因已证实 |
| 89c4754 / compile8、final-dark3 | 编译 PASS；UI **0 PASS/1 FAIL，exit65** | 按录屏/二进制事件定位真实grabber后，手势关闭/仍20/确认25/Save成功；最后单向滚动精确查独立时长失败，实际AX已是组合“日期、0:25:00” |
| f077598 / compile9、final-dark4 | 编译 PASS；中文Dark最大AX **1/1 PASS，exit0** | 保留全部取消/手势/确认断言，将末尾加强为真正冷启动稳定统计25分钟/1条；实图核读 |
| f077598 / final-light1 | 英文Light R2/R3 **2/2 PASS，exit0** | 原导航栏拖动后仍在（非抓手实证）；明确关闭失败保留/成功冷重开；内层sheet取消20/明确替换25及冷重开统计 |
| 2c5b4c5 / compile10、final-dismiss1 | 编译 PASS；Light R2 **1/1 PASS，exit0** | 同 R3 成功的顶部区域正/负配对，外层不关闭，失败/重试/冷启动断言全部保留；仅测试增量 |
| 2c5b4c5 / release2 | **BUILD SUCCEEDED / exit0** | unsigned generic iOS；六真实App/Share/Widget包与两App clean fullSHA provenance验证 |

八项本轮新增持久测试覆盖逻辑删除/丢弃/消费、两关联草稿同事务 beforeSave/actualSave后throw、健康草稿不动、外部未保存Entry不提交、旧库合法清理与坏原始payload拒绝、真实旧v10 ZIP恢复与重导出、新UUID旧编辑/跨参与者拒绝、首个及更新draft实际提交后报错精确重试、原20分钟分段默认/取消/备注保存/重开/ZIP保持及确认25分钟正向。未放宽坏包、完整快照、历史保护/媒体或回滚断言。

完整 Unit 在 d5db223 已覆盖 ImportExport55、InvestmentFoundation23/Persistence20及全部邻接模块；最终只改确认展示块与UI驱动，42份Unit源/fixture blob相同，移除该展示块后的生产文件逐字相同，复用理由与具体 SHA 见 `full-unit-reuse-proof.json`。不把467项写成f077598或最终2c5b4c5重新执行。旧计时/后台/冷重开/统计及Files真实ZIP门禁按原证据复用；本轮原生相邻Record AX另过。

## 原失败、警告、边界及交付

所有红测/系统框失败/AX截字/手势与查询驱动失败均留原 log/xcresult/summary/attachments。dark2录屏由只读AVFoundation提帧，实际导航条起点(201,115)、抓手约y80；没有从未改变的失败盲目重试。修复前测试 seam 默认仍真实context.save；DEBUG合成夹具仅PGOSUITesting加专用参数启用，不影响Release或私人数据。

green2两条、final-dark1两条 Invalid frame 保留；最终 Dark/Light **1 / 2** 条仍在原日志/summary。注入损坏库的CoreData错误及宿主SDK诊断不删除，不与测试失败数混淆。

Safari unsigned仍FAIL（旧真实扩展client is not entitled/无App Group entitlement），未重跑已证失败或改签名绕过。唯一UnitSKIP仍专用32MB HFS+镜像/marker缺失，物理低空间NOT_RUN；不填满主盘。真实iPhone/私库/签名、实际通知/桌面Widget/Photos/VoiceOver/飞行模式、远端独立CI（workflows=0）NOT_RUN。

`final-static-proof.json` 核对完整项目/签名/历史schema文件不变、原1032文案逐条不变及五条新中英键；`final-bundle-proof.json` 核六包身份1.0(7)/两App clean同SHA。最终产品后仅五份Markdown；普通push后原PR/全远端blob/旧PR8–11和原workspace三项未知dirty由 `final-delivery-proof.json` 核对。真正独立Reviewer逐轮闭环范围内问题，停在READY_FOR_OWNER_DEVICE_GATE，不代表设备或签名通过。

最终 test-only `2c5b4c5` 另以 R3 已成功的同一顶部区域 `(.5,.09)→(.5,.95)` 补跑 R2（`final-dismiss1`）**1/1 PASS/exit0**，外层仍在、失败后输入/错误保留、重试关闭并真正冷启动同草稿；产品与 `c91866e` 完全相同。该补验另保留 1 条 Invalid frame，不把旧导航条拖动当作抓手保护实证。

---

# 时间投入 V1 外部 Review — FIXES_IN_PROGRESS（2026-10-17）

本轮按 Owner 新授权处理固定 `92dc10a47add519604546e597672af9afb87d10e` 的[外部 Review](https://github.com/yoCruzer/PersonalGrowthOS/pull/12#issuecomment-6234984209)，仅 R1/P1、R2/P2、R3/P2 及关联数据安全/可靠性。原 `codex/time-investment-v1` / Draft PR #12 与固定 Goal1.1/BASE 保持；真实独立只读 Reviewer 已确认三项。当前不能沿用旧 READY 结论，先补修复前反例，再限定修复、原生磁盘/ZIP/UI及独立复核。旧失败/警告/Safari unsigned FAIL、物理低空间 SKIP、真实设备/签名/CI NOT_RUN 保持。

新证据根 `/tmp/pgos-time-investment-review-fixes-evidence`；指定评论原文已完整读取并保存独立副本。原工作区三项未知dirty保留，任务工作树从clean92dc续接；不重建分支，不操作真实私人数据，不合并/tag/Archive/TestFlight。下方为前轮交付与历史原始记录，不代表本轮三项已关闭。

---

# 时间投入 V1 — READY_FOR_OWNER_DEVICE_GATE（2026-10-17）

本节是当前交付证据，下方旧IMPLEMENTING/BLOCKED/RUNNING保留为历史。固定Goal1.1 `72ee8bdf954a5628806db867682a6b021e63545b`、PLAN_ROOT `043a2673c2463cb4f2259dbd27f58dc998b62bc5`、BASE `ad0720ad743f495ac6f2ee3e97b16577266351db` 均未重建。最终产品/测试与最后生产 **`2ae01f3d2af2117a3f957ee6cd275d50e19b892d`**；之后仅五份交接Docs及INDEX一句状态指引（六份Markdown）。最终delivery SHA以Git/原PR12和 `/tmp/pgos-time-investment-evidence/final-delivery-proof.json` 为准。

原工作树 `/Users/himini/.codex/worktrees/time-investment-v1/PersonalGrowthOS`、原分支/upstream `codex/time-investment-v1` / `origin/codex/time-investment-v1`；PR12保持OPEN Draft，base为 `codex/sleep-routine-v1` / BASE。原workspace仍有project/catalog/xcodecloud三项未知dirty，未吸收；旧PR8–11保持。普通push，不merge/force/tag/Archive/TestFlight，不读取真实私库或操作手机。

## 当前环境与命令

恢复首步只读执行 `xcodebuild -checkFirstLaunchStatus`、`xcrun simctl list devices available` / runtimes，均exit0；Xcode27.1/27A9275、CoreSimulator1174.9.2，iOS27.0/24A434。只启动既有专用PGOS-TimeInvestment-V1模拟器 `540825BC-D0D4-4D71-B8DF-D73B243C3726`（bootstatus21s）。未sudo、删模拟器、改系统配置。Dark截图只切专用sim appearance，运行后恢复light；没有改全机字号/网络。结束尾检一次未提升权限的simctl被沙盒拒绝访问用户目录；随后以授权的只读同项返回light，未修复系统或重跑原生队列。

下列均在上述worktree，单一Xcode队列；每轮完整命令均在同名log首部。日志/result均为 `/tmp/pgos-time-investment-<run>.log/.xcresult`，摘要及SHA索引在 `/tmp/pgos-time-investment-evidence/native-run-index.json`。

```sh
xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -sdk iphonesimulator -arch arm64 -derivedDataPath /tmp/pgos-time-investment-derived -resultBundlePath /tmp/pgos-time-investment-testcompile23.xcresult CODE_SIGNING_ALLOWED=NO build-for-testing

xcodebuild test-without-building -xctestrun /tmp/pgos-time-investment-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=540825BC-D0D4-4D71-B8DF-D73B243C3726' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-time-investment-native-fullunit3.xcresult -only-testing:PersonalGrowthOSTests

xcodebuild test-without-building -xctestrun /tmp/pgos-time-investment-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=540825BC-D0D4-4D71-B8DF-D73B243C3726' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-time-investment-native-final-ui1.xcresult -only-testing:PersonalGrowthOSUITests/InvestmentUITests

xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/pgos-time-investment-release-derived -resultBundlePath /tmp/pgos-time-investment-release3.xcresult CODE_SIGNING_ALLOWED=NO build
```

## 收敛的最后几轮

| 固定SHA / run | 实际结果 | 说明 |
| --- | --- | --- |
| 02b1858 / testcompile18、native-ax-final2 | 编译PASS；1/1 UI PASS、exit0 | 原滑动拨错wheel修正后，日期未变/起止/回顾/详情/草稿断言过；但主agent和Reviewer实际看图确认按日横排数字拼接，S9视觉FAIL，未提前READY |
| 02b1858 / release2 | BUILD SUCCEEDED/exit0 | 当时unsigned产物，后续AX修复后已被release3取代；capture见release2-and-debug23-bundle-capture.json |
| 38e7919 / testcompile19；af377f2 / testcompile20 | TEST BUILD SUCCEEDED/exit0 | 按日ViewThatFits仅布局；后者只补详情贡献截图 |
| af377f2 / native-final-scope1 | 36/36 PASS、0SKIP、exit0 | 核心22/持久10/四UI；实际日期与0:45:00纵排、详情LabeledContent贡献可读。两agent独立查看A6441B99/2A15B495截图；记录“不相交”断言不等于原问题必红 |
| 525526d / 新T4磁盘测试 | test-only提交 | 补旧内存故障证据缺口，随后真实运行，不把旧内存证据冒充磁盘重开 |
| d49829b / testcompile21 | TEST BUILD SUCCEEDED/exit0，测试NOT_RUN | 初拟max-1为坏包；经独立Reviewer确认采用合法耗尽/受控报错配对，不随意降低技术上界，下一test-only调整为max/min坏包 |
| 05f2c4a / testcompile22、native-revision-red1 | 编译PASS；2项1PASS/1FAIL、exit65 | 新T4磁盘PASS；真正Int.max Session及Operation ZIP被错误接受（scenario16/18），各三断言/共6处FAIL，target及独立磁盘重开各22对象而非0 |
| 2ae01f3 / testcompile23 | TEST BUILD SUCCEEDED/exit0 | 最终干净生产/测试编译，所有target |
| 2ae01f3 / native-fullunit3 | **459项458PASS/0FAIL/1SKIP，exit0** | 核心23/持久12、完整ImportExport55含20坏包、全部相邻Unit。唯一SKIP为专用32MB HFS+；原始结果及summary保存 |
| 2ae01f3 / native-final-ui1 | **4 PASS / 0 FAIL / 0 SKIP，exit0** | 四项完整时间投入UI；没有重复跑已确认unsigned Safari失败 |
| 2ae01f3 / native-light-final1 | **1 PASS / 0 FAIL / 0 SKIP，exit0；1条duration聚焦Invalid frame** | 最终四UI英文截图实际仍Dark，启动参数不能证明Light；专用sim明确设Light后复用既有构建，仅补英文Manual UI与实际白底截图 |
| 2ae01f3 / release3 | **PASS / exit0** | unsigned generic iOS，六包/版本/两App clean fullSHA provenance核验；不是可安装IPA |

最终核心限定修复：8处revision增量统一checked next，非法Int.max/负数包拒绝；合法max-1可验证/备份恢复，但实际写入受控报错，不wrap、不生成非法max、不丢事实。磁盘配对逐写路径/新container重开，含先改Session后Op耗尽回滚。补显式participantID贡献入口，UI只传“我”；真实两参与者90/60秒、次数/明细独立、recorder仍“我”。无家庭UI、历史Schema或签名变更。Reviewer固定2ae01f3复核两问题及T4证据闭环。独立终审确认必选本地门禁完成，无范围内尚未关闭confirmed P0/P1/P2；最终交付同步以原PR及final-delivery-proof.json为准。

## 保留的失败、警告及未执行项

最初native-affected1的自动诊断收尾卡在本任务 `simctl diagnose --timeout600`，测试已结束；仅终止诊断子进程PID69484，保留xcresult，未杀系统服务/模拟器。其后使用 `-collect-test-diagnostics never`，仍保留原生结果、失败截图和录像。

早期各原生/编译/mac探针红测和exit70均在下方历史及run-index；不删除、改名或拼接绿数。fullunit2一条旧GoalFixture PGOS-S7 SQLite unlink/invalidated保留；集中14UI三条Invalid frame（QuietWins/Manual decimal焦点/Sleep Weight），targeted13一条；最终fullunit3无unlink/invalidated/Invalid frame，summary runtimeWarnings为空，但保留注入provider错误/IOSurface提示。最终四UI警告：3条Invalid frame，分别在duration聚焦、中文AX轮外滚动到Save前、冷重开手工note聚焦；数据与导航断言通过，保留原始记录，未将warning当作零。release3未记录warning或error；历史AppIntents提示仍见对应原log。

Safari：最初URL提交交互错误另记；473f测试调整为真实Go后进入扩展，19:00:56.657系统明确client is not entitled，真实unsigned包无App Group entitlement，空编辑器/保存禁用截图 `safari-current-failure.png`。后续取消/保存/导入没有通过，保持FAIL。Share源码/身份/签名设置相对BASE不变，V14外部导入Unit已跑；依Goal99保留签名系统路径给Owner，不绕过、不改签名。

唯一SKIP：`TodoFoundationTests/testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure`，未挂载专用32MB HFS+卷和marker，物理低空间NOT_RUN；注入故障门禁已跑，不填满主盘。远端workflows=0，独立CI NOT_RUN。真实iPhone/私库/签名、实际通知/桌面Widget/Photos/VoiceOver/飞行模式/发行 NOT_RUN。

仅host72665确认退出后清理专用task App tmp白名单239合成根，manifest `post-host-synthetic-cleanup.json`；不删模拟器、原fixture或其他容器。其余证据保留。固定输入/历史Schema/原937文案/目标签名配置/最终六包证明见final-static-proof.json、final-bundle-proof.json。远端普通push后核对原PRhead、全文件blob和旧PR/原workspace边界，见final-delivery-proof.json；不把未知原workspace宣称clean。

---
## 以下为逐轮执行历史

# 时间投入 V1 执行证据

状态：IMPLEMENTING_A；不是交付或验收通过。执行日期 2026-10-16。

固定输入：BASE `ad0720ad743f495ac6f2ee3e97b16577266351db`；PLAN_ROOT `043a2673c2463cb4f2259dbd27f58dc998b62bc5`；GOAL_SHA `72ee8bdf954a5628806db867682a6b021e63545b`。两份规格全文均为1.1。

`git merge-base --is-ancestor` 已核验 BASE→PLAN_ROOT→GOAL_SHA；PLAN_ROOT父提交为BASE；`git diff --name-status BASE GOAL_SHA` 严格只有两份时间投入规格。原规划有三次文档提交，不要求最终GOAL直接父提交为BASE。

独立worktree `/Users/himini/.codex/worktrees/time-investment-v1/PersonalGrowthOS`，从GOAL_SHA建立 `codex/time-investment-v1`。远端同名分支/PR不存在；PR#11 OPEN Draft head/base核验为 `ad0720a` / `codex/important-days-v1`；新PR预定base `codex/sleep-routine-v1`，其当前head仍为BASE。原工作区三项未知dirty保留，不stash/reset/clean/吸收。旧PR快照 `/tmp/pgos-time-investment-evidence/old-pr-snapshot.json`。

## 实际状态机与事务

- running→paused/resume；running→按目标投影targetReached；unfinished→finish冻结pendingSave。
- 不同进程/单调锚点失效/壁钟异常/超过18小时的自动累计→recoveryRequired，保留此前可信检查点。
- pendingSave/targetReached/recoveryRequired→原子写Session和saved终态；discarded/deleted保留操作墓碑，旧ID不复活。
- 每参与者一个unfinished，不限制其他参与者。统计只读正式Session，区间按原时区自然日分摊、按Session ID去重。
- 写入使用同库独立ModelContext，失败只rollback本次context；计划在界面接线时补持久草稿与生命周期检查点。

## 已运行命令与真实结果

环境：macOS本机，Xcode 27.1 / 27A9275。构建均使用本任务 `/tmp/pgos-time-investment-derived`。

1. `xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -sdk iphonesimulator -derivedDataPath /tmp/pgos-time-investment-derived CODE_SIGNING_ALLOWED=NO build`：exit65，throwing短路表达式编译错误。日志 `/tmp/pgos-time-investment-build1.log`；原错误保留。
2. 修正该表达式后，增加 `-arch arm64` 的同一Debug命令：exit0 / BUILD SUCCEEDED，日志 `/tmp/pgos-time-investment-build2.log`。此时UI尚未接线，不代表验收通过。
3. 本任务`xcrun simctl list devices available`触发Xcode包装脚本`xcodebuild -runFirstLaunch`，卡住约四分钟。仅结束本任务PID76479/76470/76469，不终止其他任务或系统服务。当前已安装CoreSimulator=1171.7.0，Xcode要求1174.9.2，构建明确报 simulator device support disabled。直接读取已安装引擎清单可见iOS27.0设备；不绕过Xcode版本检查，不安装或操作旧模块模拟器。

所有新Unit/磁盘集成/UI目前为NOT_RUN；测试编译和后续门禁另追加。原Debug构建通过不等于SwiftData运行或设备通过。没有启动真实手机或私人库，没有发布、merge、tag或Archive。

## 阶段 B 实现与第一轮独立审查（进行中）

固定核心提交 `d21f8fae8cb8c4855dc76c82061ca67936be774c` 交给真实独立只读 agent `/root/time_investment_reviewer`。其报告四项：R1改活动未同步Operation、R2时钟微漂移产生重叠、R3恢复到目标后继续仍被目标封顶、R4零秒跨日首段日期不匹配。限定修复及回归已加入，尚待下一固定提交独立复核；不能写成最终通过。

已接线：Growth/Today紧凑状态、活动改名/归档/弱重复、正/倒计时、持久确认与手工草稿、五档体验/备注、全部累计/7/30自然日筛选、历史和原时区日分摊详情、修改后共享快照刷新、中英新文案。默认参与者惰性创建，记录者有独立ID。统一包v10新增原外部导入收据保全，v1–v9不反推原来缺失的收据；新实体/收据纳入空库及发布检查。恢复后的计时转换为待复核，隔离与重开验证只对这项明确状态转换比较期望，其余字段继续完整相等。

新增测试：五种V10/11.0/11.1/V12/V13磁盘Schema直升/媒体与事实保留、运行/暂停/到目标/待保存计时真实ZIP恢复继续、预览后新计时竞态/重复恢复、发布前失败回滚、15类实际坏ZIP、三项时间投入UI及真实设置Files恢复前浏览时间投入。它们目前仅编译，不是运行证据。

- `/tmp/pgos-time-investment-testcompile1.log`、`testcompile2.log`、`testcompile3.log`、`testcompile4.log`、`testcompile5.log`：均exit0 / TEST BUILD SUCCEEDED。逐轮扩展范围，不将它们累加成测试通过数。
- `/tmp/pgos-time-investment-unit1.log`、`unit1.xcresult`：对本任务新建隔离模拟器 `540825BC-D0D4-4D71-B8DF-D73B243C3726` 的一次运行尝试exit70；Xcode因CoreSimulator版本不匹配禁用目的地，运行0项。后续不循环重试。已请Owner完成Xcode组件更新；目前未收到完成确认。真实iOS Unit/磁盘/恢复/UI及全量回归仍NOT_RUN。
- 为继续发现核心问题，建立临时macOS探针 `/tmp/pgos-time-investment-mac-probe`。原样编译生产InvestmentFoundation/InvestmentTransfer、原始CivilDay/日期编码依赖及同一InvestmentFoundationTests；仅测试容器和TransferData外壳为适配器，独立内存schema，不是iOS V14/迁移/ZIP/UI验证。源文件SHA清单在该目录SOURCE_MANIFEST.json，生成命令在 `/tmp/pgos-time-investment-evidence/make-mac-probe.py`。
- `swift test --package-path /tmp/pgos-time-investment-mac-probe`：`mac-probe1.log` 16/16、`mac-probe2.log` 20/20 PASS/exit0；它们是不同轮次，不能相加。对应当时源码在探针manifest记录；后续新修改仍需补验。
- 用审查固定d21f8fa的原生产Foundation替换探针对应文件，运行相同R1/R2反例：`mac-review-red1.log` 2测试失败、5断言/错误（1unexpected），exit1。明确复现原问题，不删断言。
- 新增94个双语键；静态逐项比较937个原键值未变，git diff --check通过。界面真实视觉/无障碍验证仍NOT_RUN。

固定a873b5f后追加限定修复R5–R7，不扩产品范围。`testcompile6.log`成功，`mac-probe3.log`21/21通过，但其运行早于a873最终两处校验；不能冒称完整a873运行。为此保存 `a873b5f-mac-source-manifest.json`，独立run `mac-probe4-a873b5f.log`和`testcompile7.log`；后续最终限定修复仍需对应新提交证据。

## R5–R7 补充运行与失败保留

产品/测试固定 `3c1116a09d90cd0c851d48c8d9599ce33b2de50f`：testcompile8及xcresult为TEST BUILD SUCCEEDED/exit0，仍有CoreSimulator版本警告；mac-probe5为24项中23PASS/1FAIL、exit1。失败为R6测试假定补零的`00:20`，实际Foundation输出 `31/12/2026, 23:50:00 → 01/01/2027, 0:20:00`；原时区前后相等断言通过。增加失败值的diagnostic定向run仍1/1失败，日志`mac-r6-diagnostic.log`。只调整对可变格式补零的断言为`0:20:00`，保留跨设备默认时区前后相等及23:50/次日00:20事实检查，不改生产格式化算法。

探针扩展仅原样提取生产EditorState/Workspace/Formatting声明与原R5/R6测试方法（去除未引用UI imports）；它验证实际共享工作区控制流、反馈保留和日期格式化，仍不代表原生SwiftUI渲染或实际iOS生命周期。R5关闭确认→继续→再结束的生产Workspace反例已在mac-probe5通过；22项核心（含R7合法回拨/未来伪造配对）均通过。补零修正后另记录定向/完整探针结果，不把本轮失败改成全绿。

## 固定干净产品/测试检查点 0abe55f

完整SHA `0abe55f0f722b920a73ecedf6e1fc395181994a5`。

- `swift test --package-path /tmp/pgos-time-investment-mac-probe`：mac-probe6-0abe55f.log，24/24 PASS、0FAIL、exit0；22核心＋2原样Workspace/格式化方法。源清单 `/tmp/pgos-time-investment-evidence/0abe55f-mac-source-manifest.json` 与固定提交逐项核对，生成先于日志。此为补充macOS内存Schema，绝不代替iOS迁移/ZIP/UI门禁。
- `xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -sdk iphonesimulator -arch arm64 -derivedDataPath /tmp/pgos-time-investment-derived -resultBundlePath /tmp/pgos-time-investment-testcompile9.xcresult CODE_SIGNING_ALLOWED=NO build-for-testing`：exit0 / TEST BUILD SUCCEEDED，原始同名.log。只编译，不运行测试。
- `xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/pgos-time-investment-release-derived -resultBundlePath /tmp/pgos-time-investment-release1.xcresult CODE_SIGNING_ALLOWED=NO build`：exit0 / BUILD SUCCEEDED，release1.log。unsigned generic iOS不是可安装IPA，没有签名、Archive或安装。
- 两构建均保留CoreSimulator过旧/目的地禁用警告与既有AppIntents提取提示；不能把构建成功当作环境已恢复。旧NoUsage仅返回值提示已用正常discardable API标注处理；没有改变断言。
- 实包检查 `/tmp/pgos-time-investment-evidence/0abe55f-bundle-proof.json`：Debug及Release各App/Share/ImportantDaysWidget六包均原Bundle ID与1.0(7)，两App provenance为clean/full0abe/localGit/空Tag。历史V1–V13 Schema定义前缀逐字相等，原entitlements、URL身份、Share导入、App主启动及Development Contract源码未变。
- 第三轮真正独立只读Reviewer确认R1–R7代码层闭环，无新增confirmed范围内问题。iOS完整运行与最终READY依然被环境阻塞。
- R7另保留原a873生产验证器的定向反例：mac-r7-red.log，1项失败/exit1（未来事实未抛错）；24/24修复绿测在此前已保存。探针生产Transfer已恢复固定0abe，不用混合源码红测结果冒称整提交运行。

后续交接仅Markdown，不再改固定产品/测试。新PR保持Draft和BLOCKED_ENVIRONMENT；环境恢复后按验收文档补齐所有本地必选门禁，再固定新产品/测试提交复审。当前Goal未完成，不进入READY或下一模块。

## 普通推送与唯一新Draft PR

已普通推送 `codex/time-investment-v1`，upstream为 `origin/codex/time-investment-v1`；唯一新 [Draft PR #12](https://github.com/yoCruzer/PersonalGrowthOS/pull/12)，base `codex/sleep-routine-v1`，实际base复核仍为固定BASE `ad0720ad743f495ac6f2ee3e97b16577266351db`。未变旧PR head/base/OPEN Draft；前后快照在证据根。远端workflows实际为0，独立CI NOT_RUN；空checks不代表通过。

产品/测试固定 `0abe55f0f722b920a73ecedf6e1fc395181994a5`；最后交接只改Markdown，交付HEAD以Git/PR实时head和证据根delivery-proof.json为准，不在同文件写自引用提交SHA。最终源与远端内容/工作树核对随后完成。

结束前重新只读核实安装的CoreSimulator为1171.7（日志显示1171.7.0），仍小于Xcode包装器要求的1174.9.2。Owner未报告完成组件更新，未循环启动已知失败的原生队列。Goal保持active，明确未达到READY_FOR_OWNER_DEVICE_GATE；当前阻塞为本机Xcode组件更新/管理员认证环境，非产品验收已完成。

恢复执行：先只读核实组件更新，然后复用本任务隔离模拟器540825BC-D0D4-4D71-B8DF-D73B243C3726，单一队列运行InvestmentFoundationTests/InvestmentPersistenceTests/ImportExportRecoveryTests和相邻原迁移路径；使用新日志/result名，保留unit1真实exit70。失败则按生产路径限定修复并交同一独立Reviewer复核；核心与UI收敛后跑一次全量Unit及集中联合UI，再固定产品/测试构建/审查。不能跳过原生门禁直接把本Draft标READY。


## 连续三轮环境阻塞审计

初始实现交接、第一次自动续接及本次第二次自动续接均确认同一阻塞：系统CoreSimulator仍1171.7，低于Xcode27.1包装器要求1174.9.2；两次只读 `xcodebuild -checkFirstLaunchStatus` 均exit69。上轮属于阻塞重核、未完成新产品工作，不是活进程等待；当前没有本任务仍在运行的构建/测试句柄。未把旧进程文件或历史日志当作活任务，也没有重启已确认环境失败的测试。

可独立执行的实现、编译、补充核心验证、真正只读审查和Draft交接已完成；余下必选iOS磁盘迁移、真实ZIP、UI及联合/全量回归依赖组件更新，不能用macOS探针替代。已满足连续三轮同一真正阻塞条件，Goal现标记blocked（非complete、非READY）。组件更新后按上节从现有分支/唯一Draft PR #12安全续接，不重建分支或覆盖旧工作。最后产品/测试仍为0abe55f，后续仅交接Markdown。


## 2026-10-17 安全续接与原生首轮

交付起点 4c83c8441c6e129e07cc7c49469455f59ab623df；产品/测试源码与固定 0abe55f 完全相同，故复用 `/tmp/pgos-time-investment-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun`，没有为文档重建。原工作区未知 dirty、旧 PR 与原 Draft PR #12 base/head 已只读核对，未吸收其他工作。

只读 `xcodebuild -version`、`xcodebuild -checkFirstLaunchStatus`、`xcrun simctl list devices available`、`xcrun simctl list runtimes` 均正常（Xcode27.1/27A9275，CoreSimulator1174.9.2，iOS27.0/24A434）。仅启动已有任务隔离模拟器 `540825BC-D0D4-4D71-B8DF-D73B243C3726`，bootstatus完成；无 sudo/删除模拟器/系统配置操作。

以下共同命令前缀：`xcodebuild test-without-building -xctestrun /tmp/pgos-time-investment-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=540825BC-D0D4-4D71-B8DF-D73B243C3726' -parallel-testing-enabled NO`，串行队列。

1. 加 `-resultBundlePath /tmp/pgos-time-investment-native-persistence1.xcresult -only-testing:PersonalGrowthOSTests/InvestmentPersistenceTests -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests/testInvestmentV10MalformedPackagesRejectWithoutChangingTarget`，同名.log：exit0，9/9 PASS。涵盖五历史磁盘Schema直升V14、四计时未完状态真实ZIP恢复重开、故障回滚/竞态、16种坏ZIP。结构化摘要 `/tmp/pgos-time-investment-evidence/native-persistence1-summary.json`。存在SQLite unlink警告，不能将功能PASS写成零警告。
2. 加 `-resultBundlePath /tmp/pgos-time-investment-native-affected1.xcresult -only-testing:PersonalGrowthOSTests/InvestmentFoundationTests -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests -only-testing:PersonalGrowthOSTests/SleepPersistenceTests -only-testing:PersonalGrowthOSTests/ImportantDayPersistenceTests -only-testing:PersonalGrowthOSTests/TodoFoundationTests/testOriginalV11CandidateMigratesWithoutLosingTaskEventBytesAndInfersReminderLead`，同名.log：测试执行90项、4断言FAIL/0unexpected（88通过、2测试方法失败各2断言）；xcodebuild仍在失败诊断收尾时记录此节，最终退出码/xcresult待收尾。两个旧V11迁移测试用v7恢复oracle比较新快照，actual含1条原收据而oracle为空；原测试已另行确认迁移收据1/旧包0。

Reviewer独立只读immutable SQLite确认旧夹具收据恰好1条，ID `c71ad985-c3a0-45f3-879a-b23c5760d10c`，ZIMPORTEDAT=811692800（2001参考纪元）。修正先断言旧包0收据，再将此独立常量补入oracle，保留全部字段、媒体、保护原字节及重开比较；不从actual反填、不删生产收据。测试根/TransferTestFixture不再于host仍活时删除磁盘；仅合成数据保留至退出后。Reviewer区分原生产Verification库立即删除的警告，故两个同步autoreleasepool完整包住首次落盘及独立重开验证；未加等待/过滤/跳校验，效果待补跑。


固定 c84a680e9132d76e8457dd8ef7190e817178e672 限定修正：独立Reviewer复核diff未发现新增confirmed问题，明确不能预判autoreleasepool已关闭资源，须以运行验证。`testcompile10`按testcompile9同命令、仅结果路径改为`/tmp/pgos-time-investment-testcompile10.xcresult`：exit0/TEST BUILD SUCCEEDED。

首轮affected1最终exit65，结构化摘要90项88PASS/2FAIL/0SKIP，共4断言；证据`native-affected1-summary.json`。测试结束后Xcode自动`simctl diagnose --timeout=600`持续收尾，仅对本任务诊断子进程PID69484发TERM，未结束模拟器/系统服务；xcresult完整落盘。后续使用官方`-collect-test-diagnostics never`关闭额外verbose诊断，不跳过测试、原生日志、结果或截图。

`native-affected2`沿共同test-without-building前缀，加`-collect-test-diagnostics never`，沿affected1全部selector并加`-only-testing:PersonalGrowthOSTests/InvestmentPersistenceTests`：exit0，98/98 PASS，0FAIL/0SKIP。完整ImportExport55、Investment核心22/持久8、Sleep4/ImportantDay8/OriginalV11迁移1。原失败两个方法全绿；本轮原日志`vnode unlinked`/`invalidated open fd`均0，含Verification路径，不能抹去旧警告。仍保留故障注入预期的Widget projection failed日志。结构化摘要`/tmp/pgos-time-investment-evidence/native-affected2-summary.json`。后续三项InvestmentUITests单队列运行，日志/结果`/tmp/pgos-time-investment-native-ui1`，尚待结果。


`native-ui1`固定c84a680，selector `-only-testing:PersonalGrowthOSUITests/InvestmentUITests`，其余沿affected2前缀：exit65，3项1PASS/2FAIL/0SKIP。手工保存/编辑/删除同页刷新PASS。中文AX失败在Record键盘遮挡Tab时导航，现场只读截图`/tmp/pgos-time-investment-ui1-live.png`确认；Dark启动参数未使现场变深色，本轮不能列Dark PASS。计时失败在pause后已出现pendingSave与确认sheet，resume点击坐标无效，随后finish不存在；同List行VStack默认buttonStyle可能串触发多动作。限定修正timer controls显式bordered样式，保留首轮红测，并加入pause/resume状态和不出现确认sheet断言；统计UI补日贡献下钻/45分钟、编辑30分钟、删除0计数/时长。原日志含1条Invalid frame dimension，不改标全绿。全部失败层级/截图导出`/tmp/pgos-time-investment-evidence/ui1-attachments`，摘要`native-ui1-summary.json`。


固定 b091a5b0f3a470e6476f4b2c6998f55e181b21e1：testcompile11 exit0；`native-ui2`仅Timer/Manual两方法，exit65，1PASS/1FAIL。Timer逐步paused/running且无提前确认、明确结束、关闭继续再结束、Home/activate、冷启动保存完整通过；Reviewer确认R8/P1同row默认automatic按钮联动，统一bordered修复可关闭，未改核心状态机。Manual失败仍未进入History（独立review录屏末帧、层级确认导航栏Time investment、Hub累计0:45:00），不误称统计缺陷。该轮Invalid-frame=0，原UI1警告仍保留。

`native-ui3-dark`同b091，只运行中文AX/Record方法，先只对本任务模拟器设appearance dark，结束恢复原light（原content_size=large未修改），exit65，0PASS/1FAIL，body.swipeDown仍未收键盘。没有反复点击绕开；新限定修正QuickCapture Form的scrollDismissesKeyboard(.immediately)，保持draft/保存/消失清理行为；InvestmentHub仅创建成功后清空名称并FocusState=false，失败保留输入/焦点。Reviewer只读认可这是S8相邻导航接缝。测试显式等待keyboard消失、save卡消失及History导航栏，普通启动明确默认字号；不放宽数值或状态断言。后续原生与受影响Record/分享路径仍需补验。


固定cc09f9c `native-ui4` Timer/Manual：exit65，1PASS/1FAIL；Timer完整继续通过。Manual已成功History/1次/45分钟/日贡献，新增编辑时长后decimal键盘遮住备注；失败保留，测试改为使用现有原生Done后再编辑备注，并补返回同一review逐项7/30/全部累计30分钟/1次，删除0数值。不改生产算法或跳过断言。

固定cc09f9c `native-ui5-dark` 中文最大AX/Record：exit0，1/1 PASS、0SKIP；受控task simulator appearance dark结束还原light。新滚动确实收起Record键盘，浏览/活动保存后Record原草稿逐字保留。实际截图已导出`/tmp/pgos-time-investment-evidence/ui5-dark-attachments`（Chinese-Dark-AX-editor、Record-draft-retained）；不要用测试后的Springboard live截图当产品视觉证据。后续仅UITest增强，不改cc09生产源码。


视觉复核新增R9/P2：UI5自动PASS截图实际Occurrence date标签/长中文日期在最大AX横向裁切，且复用旧Activity键导致中文显示“本周动态”。独立Reviewer确认不能以自动PASS关闭S9。限定改日期控件：正常字号保持原生默认，AX独立纵向标签+原生wheel（含可展开Start/End），不缩放整张表单；新增专用Investment activity中英键、旧值保持；展示分钟统一trim尾零，原有8位小数精度与权威Double秒值保留，不将展示值回写。补真实磁盘亚秒/只改备注/重开/no-op精度反例；待新构建/运行/截图验证。固定486bdc3 testcompile13已PASS，但没有冒称运行新增强UI；后续因本轮视觉修正继续编译。


固定06acdc3 `native-review1`：全部InvestmentPersistence9 + 增强Manual UI1，exit0，10/10 PASS、0SKIP。9项含亚秒备注编辑重开初版；Manual完成同回顾日贡献45分钟→编辑30分钟→7/30/全部30分钟/1次→删除0/0真实UI。Reviewer额外发现合法极小正秒被固定8位格式化为0会阻止仅备注保存，故追加正数回退（含Double最小正值）与实际UI共享hasValidDuration校验；不会改权威秒值。测试扩展三种秒数，no-op后用全新Context重取防缓存虚绿。中文AX补展开Start/End截图与专用活动标签断言，仍需后续最终固定提交运行。


固定ced1a4ff1eb9c172f4e3a31646967f8546c2edc1：testcompile15 PASS。`native-fullunit1`同test-without-building前缀，selector仅`-only-testing:PersonalGrowthOSTests`，exit65：455项451PASS/3FAIL/1SKIP，共7断言。新R9三种极小正数及全部Investment持久9通过。独立Reviewer确认三处旧测试oracle问题：Todo两V10磁盘迁移预期来自v6包，缺独立已知收据；QuietWins导出已是v10却仍断言v7恢复缺收据。限定测试修正保持生产不动：immutable V10中唯一ID c3dcb188-3715-4ce3-afd9-edb3bfeafae6、ref811692800补入完整旧JSON预期；QuietWins新增完整v10恢复/重开/精确快照及3收据，再构造真实v7 wire（删除不支持数组、计数/版本/数据哈希/ZIP同步更新）保留旧accepted limitation与全媒体比较。原失败不抹去。

该轮唯一SQLite unlink在DayOperations旧test helper活库teardown，不是Verification或投资root复发，Reviewer独立核对来源；限定延后该合成根清理。唯一SKIP=`TodoFoundationTests/testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure`，未挂载专用32MB HFS+卷；不擅自挂载或填满主盘，该物理低空间场景NOT_RUN，注入低空间/备份/迁移/回滚路径均运行。结构化摘要`/tmp/pgos-time-investment-evidence/native-fullunit1-summary.json`。新的测试oracle/配对覆盖及失败需要后续补验；未因结果FAIL修改任何生产事实或Reader。


## 2026-10-17 完整回归与最终覆盖补验

固定47fc0b250b084a921b03438d2954a9d9da9bf452：testcompile16 PASS；native-fullunit2全部PersonalGrowthOSTests，exit0，455项454PASS/0FAIL/1SKIP。原三失败和真实v7/v10配对全部闭环；唯一SKIP仍为未挂载的专用32MB HFS+物理低空间场景，NOT_RUN，不擅自挂载。该轮一条旧GoalFixture PGOS-S7活库teardown unlink及对应invalidated fd保留，不是Verification或投资根复发；独立Reviewer核对BASE已存在，不扩大生产改动。host72665确认退出后限定清理239个task App tmp白名单合成根，manifest /tmp/pgos-time-investment-evidence/post-host-synthetic-cleanup.json。

固定47fc native-concentrated-ui1：14UI，exit65，12PASS/2FAIL/0SKIP。完整命令在同名.log首行。通过投资Manual统计/Timer生命周期、五Tab/Record重开/Habit/Goal+Flag/Todo+Library搜索/QuietWins五来源、真实Settings Files导出预览取消/浏览投资空库恢复、ImportantDay创建关联、Sleep晨间/Weight/Record草稿/R1图表刷新。Safari失败停URL编辑态，不归为unsigned；Widget热路由因主agent遗漏项目既有外部URL driver而失败，保留执行配置错误。该轮3条Invalid frame分别QuietWins、Manual聚焦decimal文本框、Sleep/Weight聚焦；断言通过但不宣称零warning。

最终覆盖固定473f456cc892339b16bd4330879318d7bfba004d，仅三份测试文件新增，生产/配置与47fc相同；testcompile17 PASS。native-targeted-final1通过 /tmp/pgos-time-investment-evidence/run-route-without-building.py 运行（命令在.log/.driver.log）：10项InvestmentPersistence + 3UI，exit65，12PASS/1FAIL/0SKIP。真实running Home/kill/relaunch转待复核、手工草稿后台/冷重开保持且不入历史PASS；真实v10 ZIP无效手工草稿保留原输入/备注/nil、源库不变、纠正后仅1正式事实PASS。Widget由原marker逻辑实际发出两次simctl openurl，均exit0，UI PASS。

Safari补验已加载fixture并进入扩展，仍FAIL于share-text为空。当前系统日志 /tmp/pgos-time-investment-evidence/safari-current-system.log 的19:00:56.657明确ShareExtension[79409] client is not entitled；当前codesign无App Group entitlement。原生产先ShareInbox.shared()成功才读取provider，和空编辑器/禁用保存现场一致；Share/SharedCapture/签名配置相对BASE未变。独立Reviewer确认这是既有unsigned边界；保留FAIL，后续取消/保存/导入没有通过，不绕过容器，不执行签名。实际末帧 safari-current-failure.png；当前签名路径留Owner Gate，非当前PASS。

native-ax-final1固定473f，真实Dark/最大AX，exit65，0PASS/1FAIL。初始截图已正确显示投入活动及完整发生日期/三列wheel；失败在generic中心swipeUp拨动日期轮（10月变4月），Form仍0%，不是日期裁切复发。限定仅测试reveal新增avoidingWheel，按已核实wheel x41..361、Form宽402的外侧拖动；普通交互不变，并补保存发生日等于初始picker日期断言。完整展开起止/回顾/详情视觉仍待新补验。实际截图 /tmp/pgos-time-investment-evidence/ax-final1-attachments/EA2FD65F-2359-47F4-B3BD-BC44370EF37D.png。

原455全量证据按未变生产和原测试等价复用，新增持久化与UI定向执行，不冒称456全量。全轮索引 /tmp/pgos-time-investment-evidence/native-run-index.json（后续结果另补）。此前试图追加本节的一次Python stdin编码错误未写文件；没有影响产品或测试，现补全实际记录。
