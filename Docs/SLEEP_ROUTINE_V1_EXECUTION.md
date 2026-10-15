# PR #11 外部限定复审通过 — READY_FOR_OWNER_DEVICE_GATE（2026-10-15）

据 Owner 本次确认，外部限定复审通过固定产品/测试 `9da1ce8758d868145e9b5690611634ccd292e469`，对应交付 `114558f404ced9cffca5517533a11cb10d2d4ec8`：R1、R2、R3 关闭，未发现范围内尚未关闭的确认 P0/P1/P2。

外部复审独立读取固定源码和测试，通知控制流便携探针 **12/12 通过**。这不是 iOS XCTest、原生 UI、SwiftData 迁移或系统递送验证，不加入原 Unit 数量，也不代表真机通过；本次收口仅记录 Owner 转达的结论，未执行探针、测试或构建。

本次只追加五份交接 Markdown 并更新原 Draft PR #11 描述；产品、V13/v9、主库、身份、签名和发布配置不变，旧审查与分轮失败保留。Safari unsigned FAIL、当前签名分享、私人库升级、真实通知/Widget/Photos/VoiceOver 等继续设备 Gate。等待 Owner 另行签名安装或发布授权；不 merge、tag、Archive、发布或操作真实手机/私人库。

本次文档交付 SHA 以 Git/原 PR #11 head 核对；相对上述交付仅五份 Markdown，不为文档自引用 SHA 重建。分支 `codex/sleep-routine-v1`、base `codex/important-days-v1`、Open Draft 保持；原工作区改动及 PR #8/#9/#10 保留。

以下为原交接与审查历史，原文保留。

---

# PR #11 R1–R3 限定修复 — READY_FOR_INDEPENDENT_REVIEW（2026-10-15）

批准输入 `9e9e29564565a3b6396dc51bb179c29f71bdc726`，起始交付 `5f7dc3eeba4d159d72e03029f487cf67bf77ab1a`。沿原worktree、`codex/sleep-routine-v1` 与[原Open Draft PR #11](https://github.com/yoCruzer/PersonalGrowthOS/pull/11)，base保持 `codex/important-days-v1`。五份输入原样导入，manifest三个SHA-256逐项核对；探针/旧输出未修改、未执行，不是App测试。

最终产品/测试 **`9da1ce8758d868145e9b5690611634ccd292e469`**；最后生产 `f235d9210bf2bb2a9226fda6156d803c4010cc36`，后续仅R1 UI查询歧义修正与更强分布断言。本批交付只再更新五份交接Markdown，精确delivery SHA见Git/远端PR head及 `/tmp/pgos-sleep-r1-r3-evidence/final-delivery-proof.json`，不写自引用hash。

本批只修三个外部P2及同一R3时序的独立审查补缺口，不重开睡眠/重要日子开发。V13/v9/主库/身份/发布配置/来源/Share/Widget均冻结；`scope-proof.json`与实际Git diff核对。原workspace三处未知dirty未吸收，历史FAIL及原审查“当时无发现”结论保留。

R1：Workspace先完整读取局部records/goals，再同一MainActor回合发布事实与同一真实评价时刻；回顾与绘图/评分来源统一从最新snapshot按筛选意图重算，返回/前台/跨日推进真实时钟。未钳制FilledAt、未删未来/回拨保护。实际UI在原回顾内修改两时间和感受立即保持1/1/1及评分1；评分来源改为很好后原较差分组即时为空、新分布1；绘图来源清起床立即变1/0/0，切30天保持归属。晚补/回忆、备注/no-op、回拨与字段证据对照保留。

R2：真实SleepService仅在rules空且cutoff=nil时no-op。三次初始关闭保存仍零规则，首次开启今日生效并磁盘重开；UI关闭保存→开启今日→重启保持通过。已有真实nil规则不清洗；后续修改/关闭、未来待生效规则、回拨/跨时区原测试保持。

R3：每次add成功即保留接受元数据，generation只门禁UI状态；成功接受后到期不以末pending缺失误报失败，elapsed不声称系统已显示。明确取消与失败remove尽早pending复核，防止后续批次跨旧fire锁住真正提前取消日期；未来missing仍failed并移除未到期台账。旧plannedFires键及Double格式未改，重启兼容。替换在旧fire前成功确认可更新；成功返回已跨旧fire时保守保留旧elapsed并撤销较晚新pending，防止重复，不伪造准确接受/实际递送时刻。聚合仅统计真正未来scheduled，全部到期时elapsed/0/nilcoverage；真实失败、拒权、容量优先级保留。

## 本轮验证与证据

证据根 `/tmp/pgos-sleep-r1-r3-evidence`，每个run的`*-sha.txt`记录精确SHA，`.log`开头有完整命令，`.xcresult`原始保留，`*-summary.json`由xcresulttool导出。环境沿用Xcode27.0(27A266a)/macOS27.0.1，专用合成iPhone18Pro/iOS27.0模拟器 `834EED0E-6AA2-4A4E-A81A-97F4F556DFCB`，不改系统时钟或操作真机/私库。只一个活跃Xcode队列。

| Run / 固定SHA | 真实结果与关闭依据 |
| --- | --- |
| Red1 / 500c9dc | 0/2 Unit（7断言FAIL）+0/2真实UI（2FAIL），exit65、0SKIP/warning；旧生产R1字段全部unknown、R2off落规则、R3末确认前到期丢台账均实际复现 |
| Focused1 / 64d5dc2 | 50/50相关Unit + 1/2 UI PASS，exit65、0SKIP/warning；R2 UI通过，R1直接保存1/1/1及评分1恢复；扩展来源测试因Poor行中心落TabBar，未导航。层级783–835、TabBar791起及录像证实，补正常滚动与完整frame断言，未删事实检查 |
| Red2 / 1a732fb | 0/1 Unit，2断言FAIL，exit65、0SKIP/warning；独立Reviewer指出add替换抛错后的remove未及时确认，下一日add跨旧fire后真正提前取消被锁 |
| Green2 / f235d92 | 41/41相关Unit + 0/1 UI，exit65、0SKIP/warning；取消缺口与全部通知/目标/交错对照通过。UI实际走完评分来源改值即时移出、返回与绘图来源打开，失败因Unknown同时匹配菜单与评分未知；限定排除后者，不删清起床与30天断言 |
| UI3 / clean9da1ce8 | 1/1真实UI PASS，exit0、0SKIP/warning；完整走原回顾编辑→评分来源成员即时移出/新分布1→绘图来源清起床→1/0/0→30天归属，无额外离开回顾或后台刷新 |

集中命令选实际五类SleepFoundationTests/SleepReviewRegressionTests/SleepReminderTests/ImportantDayReminderTests/TodoReminderTests及两条R1/R2 UI；后续仅补受影响通知/来源UI，未重跑406/410全量、全套UI或已知Safari环境FAIL。41Unit含legacy键、确认后递送正对照、批末前到期、generation、真正提前取消/失败取消跨期、未来missing、成功提前替换/晚确认保守抑制、关闭/删除恢复、Todo/day/daily/weekly容量与串行gate。没有把不同轮次拼成一次全绿。

R1旧真实图 `R1-old-review-35s.png`（当日0/unknown3）及末帧由Red1录像提取；Focused1的`R1-focused1-failure.png`和层级证明行被Tab覆盖。最终UI截图见 `UI3-attachments/manifest.json`，人工与独立Reviewer核验；R2设置截图复用Focused1（其生产代码后续未变），不机械重跑。

## 独立复审、构建与交付

本轮唯一新独立只读Reviewer `/root/sleep_r1_r3_reviewer`：独立检查固定输入/真实代码/反例与原始日志/截图，不改实现、不运行构建测试；R3失败取消缺口先真红再限定补修。独立Reviewer固定9da1ce8758d868145e9b5690611634ccd292e469完成代码/原始反例/分轮日志与关键PNG、两实包plist终审，R1–R3关闭，无未关闭已确认范围内P0/P1/P2。其本人未运行测试或改实现。

固定clean9da1ce8的Debug Simulator（复用UI3等效构建）与unsigned Release generic iOS均PASS/exit0，六实包身份/1.0(7)/两App provenance同源核验通过，Release仅保留既有AppIntents提取提示。 工程 `PersonalGrowthOS.xcodeproj` / scheme `PersonalGrowthOS`。Debug复用clean9da1ce8 UI3等效构建，路径 `/tmp/pgos-sleep-derived/Build/Products/Debug-iphonesimulator/PersonalGrowthOS.app`；unsigned generic-iOS Release `/tmp/pgos-sleep-release-derived/Build/Products/Release-iphoneos/PersonalGrowthOS.app`。`final-bundle-proof.json`核对App/Share/Widget六实包原身份与1.0(7)、两App clean9da provenance；appex来自同构建图，无独立provenance文件。不是可直接安装IPA。最后Docs-only不为自引用SHA重建。

普通push原PR #11并更新本轮描述，base/Open Draft不变；旧#8/#9/#10、Goal承载分支与固定产品基线只读保持，最终ref及clean同步见delivery proof。未merge/force-push/tag/Archive/签名安装/发布，未操作真实手机/私人库。远端CI NOT_RUN（workflows=0）；Safari unsigned FAIL仍设备Gate，不绕过App Group、不冒称当前候选分享通过；旧体重warning不扩修。私人库升级/签名分享/实际通知递送/桌面Widget/Photos/VoiceOver均NOT_RUN。

停READY_FOR_INDEPENDENT_REVIEW供外部只审R1–R3新固定SHA；外部关闭后再由Owner决定组合真机Gate，不自行安装、发行或开始新模块。

---

# 睡眠与作息 V1 执行断点

状态：READY_FOR_OWNER_DEVICE_GATE。固定产品基线 `5614246f98ae63732ccd4fd8a6b66f4a425336f2`；批准文档快照 `1bed2f46b08c547d52e1ca2f28d74ac0f6696003`。已核验祖先关系，二者差异仅批准的两份 Markdown。

工作树 `/Users/himini/.codex/worktrees/sleep-routine-v1/PersonalGrowthOS`，唯一产品分支 `codex/sleep-routine-v1`，从文档快照创建；原工作区三处 dirty 保留。PR #8/#9/#10 只读核对；本任务新 Draft PR：[Draft PR #11](https://github.com/yoCruzer/PersonalGrowthOS/pull/11)，base `codex/important-days-v1`。

## 顺序与门禁

1. 读取当前 V12/v8、保全/迁移、共享提醒和路由真实接线；追加 V13/v9、独立睡眠事实与目标规则，完成定向磁盘/区间/字段时间测试。
2. Today/Growth 单屏记录、历史和 7/30 日回顾、设置与共享提醒；三项选择无预选，日期固定，失败保草稿。
3. 一名独立只读 Reviewer 首轮审查数据及提醒契约；核实反例并限定修复。
4. 固定收敛 SHA：全量 Unit 一次、集中关键 UI 一次、Debug Simulator/unsigned Release generic iOS 实包；后续只补受影响项。Reviewer 第二轮检查固定 diff 和原始证据。
5. 更新验收/审查/当前文档，普通 push，新 Draft PR base `codex/important-days-v1`，远端核验后停 READY_FOR_OWNER_DEVICE_GATE。

所有测试只用隔离合成数据；不操作真实手机/私库，不 merge/tag/Archive/发布，不修改旧 PR。启动阶段未重跑旧全量。

## 当前断点

固定最终产品/测试与最后生产 SHA **`138616cd0970b0f4fba9d0c7d7d44f6ca7d30b53`**。实现完整，独立只读审查及限定修复闭环；无未关闭的已确认范围内 P0/P1/P2。最后交接提交仅五份 Markdown，交付 SHA 以本地 Git、远端 ref 与 PR head 核验，避免文档自引用。最终同源证据 `/tmp/pgos-sleep-evidence/final-delivery-proof.json`。

下一动作仅 Owner 决定安装与设备验收，不进入下一功能。工作树 clean、普通推送与新 Draft PR 完成后的远端状态见上述 proof；不把 unsigned 产物称为可安装 IPA。

## 已执行命令与结果

证据根 `/tmp/pgos-sleep-evidence`；每个 `.log` 开头保留完整 xcodebuild 命令，`.xcresult` 为原始包；构建缓存 `/tmp/pgos-sleep-derived`。Xcode 27.0 (27A266a)，iOS27.0 iPhone18Pro 合成模拟器。首轮使用既有合成 EC7758DB-5D1B-4D1C-AA4D-900A9E11B66A，收敛阶段创建专用 `C3FD4FD7-983B-43CE-83D4-12933FDB3728`。从未操作真实手机/私人库，也没有清理旧模拟器数据。

统一命令为 `xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=<上述UUID>' -derivedDataPath /tmp/pgos-sleep-derived -only-testing:<实际selector> -collect-test-diagnostics never -parallel-testing-enabled NO -resultBundlePath /tmp/pgos-sleep-evidence/<Run>.xcresult test CODE_SIGNING_ALLOWED=NO`。MorningUI2 另外使用 `SWIFT_EMIT_LOC_STRINGS=YES` 提取实际编译键；后续静态比对确认新键中英覆盖，原条目保留。

| Run | 真实结果与边界 |
| --- | --- |
| Compile1 | 初始接线 + WeightFoundationTests，7/7 PASS、exit0；以原始包计数为准 |
| Domain1 | 24/24 Unit PASS、exit0，10睡眠+原共享提醒14 |
| UICompile1 | 10/10 Unit PASS、exit0；名字不代表已跑UI |
| Data1 | 8/8 Unit PASS、exit0；另一个拼错 selector 执行0项，不作为WAL证据；后面正确补验 |
| MorningUI1 | 0/1 UI、exit65，Section 内 sheet 消失；移到稳定 Today 父层后闭合 |
| ReviewRed1 | 0/3 Unit、5断言FAIL、exit65；真实复现回拨目标、跨记录回拨、DST部分记录 |
| ReviewGreen1 | 25/25 Unit PASS、exit0，含正确alias/WAL、睡眠/提醒/迁移/审查回归 |
| MorningUI2 | 0/1 UI、exit65，主记录/重开/编辑/回跳/删除完成，删除后覆盖摘要在列表上方未滚动；保留原断言并补正常滚动 |
| SleepUI3 | 1/3 UI PASS、exit65，主晨间+体重路径通过；Record键盘遮挡Tab导致测试点击无效、AX表单等待了屏幕外save |
| Transfer1 | 66/66 Unit PASS、exit0，完整54备份+8重要日子+4睡眠持久化 |
| EdgesUI4 | 7/7 Unit + 1/2 UI PASS、exit65，中文AX通过（截图实际浅色）；原Record键盘Tab测试仍失败，后续改为真实路由保护草稿 |
| RouteUI5（固定a153） | 11/11 Unit + 3/4 UI PASS、exit65，过期路由/Recovery/两类草稿通过；唯一设置状态在保存目标新增规则后被推到屏外，下一次正常滚动补验 |

初期 Unit host 在原合成模拟器打开了开发中已变化的未发布 V13 形状，出现 unknown-model 启动日志；正式 V11/V12 fixture 升级测试均通过。没有清库掩盖问题，最终门禁改用新合成模拟器。unsigned App Group Widget projection 日志、既有平台提示与真实 runtime warning 将按最终包分别记录，不宣称零警告。

隔离低空间卷命令：`hdiutil create -size 32m -fs HFS+ -volname PGOSSleepLowSpace /tmp/pgos-sleep-evidence/low-space.dmg`，attach 至 `/private/tmp/pgos-p1-low-space`，写入 `RUN_LOW_SPACE_TEST` 标记。只允许现有测试填充该32MB卷，不填主磁盘。


## 收敛门禁与限定补验

最终专用模拟器 `834EED0E-6AA2-4A4E-A81A-97F4F556DFCB`（PGOS-Sleep-Final / iPhone18Pro / iOS27.0）；旧开发模拟器只 shutdown、保留数据。macOS27.0.1。所有原 `.xcresult`、失败视频/导出附件、`*-summary.json` 与 `run-index.json` 留在证据根，不将补验拼成整组全绿。

| Run / 固定输入 | 实际结果及原因 |
| --- | --- |
| FullUnit1 / 3e09a54 | 全部406/406 Unit PASS，0 FAIL/SKIP，exit0 |
| ReviewRed2 / a153生产 | 0/3 PASS，4断言FAIL，exit65；时区民用日回退改写目标、DST所有解释仍全逆序、提前取消台账阻止删除后重排 |
| ReviewGreen2 / 33b0257 | 96/96 Unit PASS，exit0 |
| FullUnit2 / 33b0257 | 全部410/410 Unit PASS，0 FAIL/SKIP、runtime warning=0，exit0；目标新增持久化激活/观察时区字段与v9往返，风险扩大，故第二次完整运行。含真实32MB低空间卷，不跳过 |
| ReviewRed3 / 33b0257生产 | 0/1 PASS，exit65；下一日add期间generation变化导致提前取消证据未确认 |
| ReviewGreen3 / 4928209 | 44/44 Unit PASS，0 FAIL/SKIP/warning，exit0；取消pending复查不再被generation提前截断，旧Todo/日子提醒同验 |
| CombinedUI1 / clean4928209 | 集中关键UI **15/17 PASS、2 FAIL、0 SKIP，exit65**。重要日子三项R3b、关联/草稿、实际Widget URL路由、Record/Todo/体重/Files及睡眠主路径/Recovery通过。Safari首次键盘教学失败；睡眠设置开关中心点击未切换。保留2条旧 Invalid frame dimension，均在打开体重路径 |
| SupplementUI1 / clean55e192e | **2/3 UI PASS、1 FAIL、0 SKIP，exit65**。仅测试修正常规教学/开关操作并保留全部事实断言。睡眠真实目标开启/隐藏/拒权独立与真正系统Dark/中文最大AX通过，warning=0；Safari进入扩展后因unsigned App Group无entitlement失败，详见下段 |
| ChartFinal1 / clean47f3d95 | 23/23 Unit + 1/1 UI PASS，exit0。补晚起23:30＋60图表末端24.5与次日00:00语义；原晨间编辑/重开/回跳/删除/体重保持。1条旧体重Invalid frame |
| ChartVisible2 / cleanb6bf72d | 0/1 UI PASS，exit65；新增Chart容器AX查询不可见，录像证明图已显示，同时发现横轴标签重叠；不改写这轮失败 |
| ChartVisible3 / clean138616c | 11/11 Unit + 1/1 UI PASS，0 FAIL/SKIP，exit0；改三日期刻度/日期时间分行，实际绘图来源入口→原记录→原路径删除/体重全通过。1条旧体重Invalid frame |

`CombinedUI1` 由证据根 `run_combined_ui.py`（只调整既有route驱动的DerivedData路径）执行，按真实测试marker调用 `simctl openurl`，交付2次warm Widget URL。命令与响应见 `CombinedUI1-driver.log`；没有模拟直接改界面状态。两个完整Unit与红绿轮次均按依赖顺序执行，没有并发Xcode测试队列。

Safari 限定根因：`SafariExtension-system.log:219–221` 为 `client is not entitled`；实际测试扩展仅linker ad-hoc，无App Group entitlement，`ShareInbox.shared()` 在provider读取前失败（`SafariFailure.png`）。ShareExtension/SharedCapture及原签名/App Group配置相对基线未变。本轮Safari仍FAIL，未弱化断言或增加绕过容器fallback。按Goal不执行签名；复用未触及路径的历史有效 `1415a5b` / SafariMenu2 证据（原外部分享执行计划），不冒充当前候选PASS。当前签名/真实共享容器和系统分享仍是Owner设备Gate；独立Reviewer确认此环境边界不单独阻塞睡眠S14。

截图按像素核验而非附件名：CombinedUI1 `BAF1BE9F-3AF6-40AD-AE3E-C78AEEE84F17.png` 为英文浅色单屏；其标为Dark的中文图实际浅色，不作深色证据。SupplementUI1 `55E628CD-F1CE-4D79-BE21-ECA31D9A8E87.png` 与 `E6AE6A80-D19F-48BE-897E-E2BB6FEFFA20.png` 为真实系统Dark中文最大AX输入/设置。ChartFinal1英文附件虽旧名含light，实际Dark；首次review附件只拍上方分母，不当作可见图。最终可见图来源 `ChartVisible3-attachments/manifest.json`，人工核验分行日期/时间不重叠。完整时间区间始终在下方原记录文本可查。

## 实包、远端与边界

固定clean最终SHA，Debug Simulator复用相同SHA的最终UI测试构建；Release命令 `xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /tmp/pgos-sleep-release-derived build CODE_SIGNING_ALLOWED=NO`。两构建均PASS/exit0；初次Release.log保留既有未采用AppIntents提取提示，ReleaseFinal无编译警告/错误。最终ReleaseFinal为已有Release缓存的必要增量，不Archive；之前47f3d95 Release成功也原样保留，不冒充最终SHA。两App provenance精确为clean138616c。

构建目录：Debug `/tmp/pgos-sleep-derived/Build/Products/Debug-iphonesimulator/PersonalGrowthOS.app`；Release `/tmp/pgos-sleep-release-derived/Build/Products/Release-iphoneos/PersonalGrowthOS.app`。`final-bundle-proof.json` 核对App+Share+Widget×2的原Bundle身份、1.0(7)、App clean provenance及120新增中英编译键；appex无独立provenance文件，来自同一构建图。`static-proof.json` 核对冻结V1–V12逐字不变、批准两规格不变、817原catalog条目保留；工程构建配置未改。

独立远端CI **NOT_RUN**：GitHub API确认workflows=0，没有可触发验证流。真实iPhone/私人库/签名/桌面Widget/系统通知递送/Photos/VoiceOver/TestFlight均NOT_RUN。旧source=nil来源备份限制及既有Goal回拨边界不扩修。原workspace project/catalog/xcodecloud dirty原样保留；只普通推送本任务分支、一个新Draft PR；原PR#8/#9/#10保持head/base/OPEN Draft；未merge/tag/Archive/发布。
