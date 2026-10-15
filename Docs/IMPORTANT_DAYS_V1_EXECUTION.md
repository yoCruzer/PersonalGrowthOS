# PR #10 R3b — IMPLEMENTING

本轮从干净80cf5b71ba5421d2b38e3a5b206ead847c07cbef续接，原Draft/base与未知主workspace改动保持。只处理未确认历法往返隐藏无效字段；生产状态两项反例已真实失败（公历回程isLeapMonth残留/校验invalidDate、反向Gregorian-only规则残留）。正在补真实UI和局部规范化，保持年月日/标题/说明/有效编辑、严格校验/首次加载/perspective/取消。证据根 `/private/tmp/pgos-important-days-r3b-evidence/`；尚未交付，最终停READY_FOR_INDEPENDENT_REVIEW。下方上轮R1–R5交付为历史。

---

# PR #10 限定 Review Fix — READY_FOR_INDEPENDENT_REVIEW

固定输入 `d98306f219ed5929d38856216cd9af52fa5c7744`，直接父4e407591，增量仅五份Docs；已逐文件原样复制，当前bytes再次核验，历史探针不改、不注册target。启动HEAD4e407591；最后生产7b4704f，最终产品/测试 **`6e242128db6edeedff40da59f02e505ae57cc127`**。交付commit只改本节及另外四份约定交接文档；delivery SHA由Git/PR head和外部proof核对，不自引用。

工作树 `/private/tmp/PersonalGrowthOS-important-days-v1`，分支/upstream `codex/important-days-v1` / `origin/codex/important-days-v1`，[原PR #10](https://github.com/yoCruzer/PersonalGrowthOS/pull/10)保持OPEN Draft，base `codex/quiet-wins-on-d72`=`20d315a62179ad29a6cbcf76c33c11638412e54e`。已授权普通push原分支和更新PR正文；最后读取远端核对，完整proof位于下述证据根。旧PR#8/#9和原主workspace的project/catalog/xcodecloud未知改动不变。

## R1–R5关闭映射

| 项 | 生产实现与实际证据 |
| --- | --- |
| R1 | `ImportantDayInteraction.swift`的瞬态选择在开关开启时物化默认年份；操作结构固定dayID、rule、year、date/nil，写记录/关联记录/Todo实际入口都使用它。保存重查目标存在/未归档/日期语义，装饰或perspective不误报；真实规则改动保留草稿并显式重确认。稳定Group sheet宿主保留被删目标的Capture草稿；底部240pt滚动确认区避免最大AX遮导航。12项新生产状态/实际SwiftData测试覆盖三入口明确/普通nil保存重开、农历2023年末→2024-02-09、取消重开、历史期次不改、元数据正对照、archive/delete拒绝；实际UI证明三个入口跨合成午夜仍存2026-10-15、规则变更保草稿后确认新期次、删除后不丢草稿，中文最大AX确认2026-10-16并保存。Entry occurredAt仍按原记录当下，不回填纪念日。 |
| R2 | 生产`ImportantDayEntryFilter`+有效Picker binding+关联变化reconcile；最后具体期次消失退回all，保留有效/general。实际unlink/Entry删除、其他期次、零关联正反单测及同页解除后General A/B立即可见UI，不重插Entry。 |
| R3 | 只在用户明确确认历法时`confirmCalendar`清理不兼容闰月/特殊规则，数字不转换或钳制；首次加载保护与elapsed保留。实际闰月农历→公历确认/取消/保存/重开UI、无隐藏闰月，31号与必需2/29规则仍拒绝单测，旧preset复位UI继续通过。 |
| R4 | 非空归一化搜索禁拖并给清除搜索提示；实际服务把可见排列合回完整favorites（含隐藏归档）原槽位，统一dense rank并单次提交/回滚。完整/子集A,B,D,C、隐藏B归档恢复、磁盘重开、失败回滚、重复/缺失/非favorite拒绝均真实服务测试；搜索UI证明提示/隐藏/清除恢复。 |
| R5 | 额外预览复用explicitPeriod，按原年/1901–2100/真实例外规则有界取最多3个。未来2030原年、2100边界与无下一有效期次单测通过，无反转闭区间或第二份历法算法。 |

无Schema、迁移、备份校验、通知协调、Widget隐私、原身份或通用QuickCapture/AppShell/路由实现改动。Todo编辑器只在新增关联操作时调用验证上下文；原普通Todo路径保持。工程仅注册新生产状态/Unit/UI三个文件，历史探针不进target。DEBUG参考时钟/改规则/删除注入仅在隔离合成fixture双flag及额外删除flag下可用，Release不编入注入控件；真实系统时间和Entry时钟不改。

## 本轮实际运行（不同SHA/批次不拼成一次全绿）

环境：macOS27.0.1 / Xcode27.0(27A266a) / iOS Simulator27.0(24A434)，专用合成iPhone18Pro `EC7758DB-5D1B-4D1C-AA4D-900A9E11B66A`。测试DD `/private/tmp/pgos-important-days-data-build`；最终构建DD `/private/tmp/pgos-important-days-review-fix-final-build`。证据根 **`/private/tmp/pgos-important-days-review-fix-evidence/`**，实际命令还从各log头提取到`actual-test-build-commands.json`。

| 运行 | 实际结果与处理 |
| --- | --- |
| Red1，修复前生产接线工作树 | 5项新反例 **0/5 PASS、9断言FAIL，exit65**。生产View已接实际局部状态，但保持旧表达式，排序仍调用旧实际SwiftData服务；保存red1-production-diff.patch及两份测试/状态源。历史逻辑探针不算产品测试。 |
| Green1 / Green2 | 编译FAIL，零测试执行。依次补测试Entry.createdAt参数、将moveDisabled放每个row以保留ForEach.onMove类型、修正catch中self.error。日志/xcresult保留。 |
| Green3，9538前工作树 | **21PASS/3FAIL/0SKIP，exit65**。lunar年末fixture宿主退出1；未获得native crash根因栈，保留容器生命周期后后续同测试通过，不冒称已证明底层crash根因。另2UI真实顶部提示遮Save，截图保留；改底部safeAreaInset并保留草稿断言。 |
| Focused1，精确9538ec7 | **31Unit+14UI=45/45 PASS，0FAIL/SKIP，exit0，runtimeWarnings=[]**；driver delivered=4。Date11+Persistence8+ReviewFix12；新5UI+原ImportantDay7+默认Record与TodoQuick2。包括原往年农历、preset复位、最短创建重开、中文Dark/AX、真实冷热URL/启动失败Retry与保草稿。 |
| RedEdge1，9538+仅DEBUG/新测试工作树 | **0/2UI PASS、2FAIL，exit65**：目标删除后capture-body不存在；中文最大AX Save不可点。修复前patch、原始bundle/录屏保留。默认failure diagnostics耗600秒后正常结束，不重标环境失败。7b局部稳定sheet宿主并限制确认区。 |
| EdgeFocused1，精确7b4704f | **12Unit+7UI PASS，2UI FAIL（19/21），0SKIP，exit65**，runtimeWarnings=[]；driver delivered=2，热路由/Record草稿/最短创建重开通过。删除目标保草稿、普通确认、三入口均通过。余2失败：中文AX拖动没到Confirm；历法测试固定3次下滑关闭了本已可见的编辑sheet。 |
| EdgeUI2，精确fb35428 | **1/2UI PASS，1FAIL，exit65**。历法改控件已可见就不滑后，取消/保存/重开完整通过；中文按AX scroll.frame边缘拖仍在键盘，失败保留。7b之后只改测试导航，产品无delta。 |
| EdgeUI3，精确9b5fbdf | **0/1UI PASS，exit65**。录屏/六组frame与year=2026表明预测词栏延伸在keyboard AX范围上方，手势仍在预测词区；未移动确认区，不能认作wheel改变年份或产品规则失败。保留截图与失败。 |
| EdgeUI4，精确6e24212 | **1/1UI PASS，0FAIL/SKIP，exit0，runtimeWarnings=[]**。只按实际可见上半部发拖动，日志Confirm y1245→949→652，wheel始终2026；原中文精确提示、Save可点、草稿不变、Confirm可点、新期次2026-10-16与实际保存全部保留并通过。成功PNG已目视，非离屏mock。 |
| 最终两构建，精确clean6e24212 | Debug generic iOS Simulator / unsigned Release generic iOS均 **BUILD SUCCEEDED、exit0**。实包App+Share+Widget×2共6身份与1.0(7)正确，两App BuildProvenance为6e/localGit/Dirty=false/Tag空；四appex无独立provenance文件，来源为同一构建图，不伪称各有plist。`final-product-build-proof.json`及命令/log留证；7b/fb较早构建另加前缀保留。 |

集中命令（项目根，完整原样命令也在log头）：

```sh
python3 Scripts/run_important_day_route_ui.py --simulator EC7758DB-5D1B-4D1C-AA4D-900A9E11B66A --result /private/tmp/pgos-important-days-review-fix-evidence/Focused1.xcresult --log /private/tmp/pgos-important-days-review-fix-evidence/focused1.log -only-testing:PersonalGrowthOSTests/ImportantDayDateTests -only-testing:PersonalGrowthOSTests/ImportantDayPersistenceTests -only-testing:PersonalGrowthOSTests/ImportantDayReviewFixTests -only-testing:PersonalGrowthOSUITests/ImportantDayReviewFixUITests -only-testing:PersonalGrowthOSUITests/ImportantDayUITests -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testRecordTabIsTheNativeCaptureDestination -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoQuickContinuousInputCompletionStatisticsSearchAndRestart
```

EdgeFocused1复用driver，selectors为完整ReviewFixTests/ReviewFixUITests及原ImportantDayUITests的`testMinimalCreateWriteRelatedEntryAndRelaunch`、`testWidgetRoutePreservesRecordDraftAndQueuesBehindAnExistingEditor`。EdgeUI2只中文最大AX与历法取消保存两项；EdgeUI3/4只中文最大AX一项，名字均在`ImportantDayReviewFixUITests.swift`。driver实际添加`-collect-test-diagnostics never -parallel-testing-enabled NO test CODE_SIGNING_ALLOWED=NO`；RedEdge1为直接xcodebuild Debug选择两个边界UI、未关闭diagnostics，完整命令见red-edge1.log。Red1/Green1–3完整命令见相应log与JSON，不覆盖旧日志。

最终构建命令：`xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug|Release -destination 'generic/platform=iOS Simulator'|'generic/platform=iOS' -derivedDataPath /private/tmp/pgos-important-days-review-fix-final-build build CODE_SIGNING_ALLOWED=NO`，Debug仅sim、Release仅generic iOS，不Archive/签名。

## 独立复审、交付与停点

唯一实际独立只读agent `/root/review_fix_limited`：初审9538核对固定Goal/旧报告、真实Red1接线和45/45；提示删除条件宿主边界，主实现者复现并7b修复；7b代码delta与删除/大字号红测复审通过；最终固定6e审查确认7b后只UI导航变化，直接读EdgeUI4原xcresult、真实PNG/坐标日志及6实包/两App provenance。最终结论 **R1–R4关闭、R5修复，无未关闭confirmed范围内P0/P1/P2**。实现者未冒充reviewer。详细见REVIEW。

NOT_RUN：本轮全仓Unit/全套UI（按风险集中，不重跑旧358/362基线）；独立远端CI（实际workflows=0）；真实iPhone/私人库/签名/实际桌面或通知递送/VoiceOver/Cloud/发行。旧v7/v8 CaptureImportReceipt恢复限制、Goal时钟回拨P2和既有布局警告仍按原边界保留，未扩修或冒称消失。旧验证数字见下方历史，不计入本轮。

正常最终停 **READY_FOR_INDEPENDENT_REVIEW**，下一步只外部限定复审；没有进入旧Owner设备Gate或下个功能。普通commit/push原分支、更新原Draft PR10后核对remote/local/upstream/base/Draft及PR8/9未变，外部proof记录完整delivery SHA；纯交接文档不重复编译。

---

# 以下为上一轮A/B交付与开发历史

# 重要日子 V1 执行断点

状态：**READY_FOR_OWNER_DEVICE_GATE**。A/B必选实现、集中验证/构建与实际独立修复复审已收敛；产品/测试b3已普通推送，新PR保持Draft，不进入发行。

- 产品基线 `20d315a62179ad29a6cbcf76c33c11638412e54e`；固定Goal/设计 `3365561c5888701ce662ac6c8655ad1629ded6d0` 已完整读取，祖先/diff仅两份Markdown核验。
- 工作树 `/private/tmp/PersonalGrowthOS-important-days-v1`；分支/upstream `codex/important-days-v1` / `origin/codex/important-days-v1`；产品/测试固定HEAD **b3cc408d323e5828e9550decac72ae534f1b0b20**。最后交付为本文件所在的文档commit：完整delivery SHA由 `git rev-parse HEAD` / PR head及本地 `final-delivery-proof.json`核对，不自引用hash。最后生产代码9f34034357ea9329730ab18bfbf6d4b6e426b4b4；b3只改测试。
- 新Draft [PR #10](https://github.com/yoCruzer/PersonalGrowthOS/pull/10)，base `codex/quiet-wins-on-d72` 固定20d315a；产品/测试b3已普通push成功；最后文档提交后再核对delivery head。原工作区project/catalog/xcodecloud未知改动保留。
- 已完成：日期/Today、V12/v8与历史保全、封面/多对多引用、管理/详情/搜索、共享提醒、两Widget/三表达、授权快照/撤销/隐私、外部稳定ID路由、双语与真实视图预览；多轮独立审查关闭P1照片、P2期次与P3文案，无未关闭confirmed范围内P0/P1/P2。
- 最后验证：全量9f 362项中358PASS/4fixtureFAIL/0SKIP，b3备份整类53/53补验PASS；Debug sim/Release sim/Release generic iOS三构建PASS，实包9bundle干净b3同源。集中17/17 UI PASS（合计70/70、0失败/跳过、exit0），保留4条布局运行警告。
- 最后集中命令：`python3 Scripts/run_important_day_route_ui.py --simulator EC7758DB-5D1B-4D1C-AA4D-900A9E11B66A --result /private/tmp/pgos-important-days-evidence/FinalFocused1.xcresult --log /private/tmp/pgos-important-days-evidence/final-focused1.log`，selectors为ImportExportRecoveryTests、完整ImportantDayUITests、原App十条关键UI（详下），已exit0，delivered=4，无活测试进程。
- 环境Xcode27.0(27A266a)/macOS27.0.1/iOS27.0；仅合成专用模拟器；真实32MB HFS+ `/private/tmp/pgos-p1-low-space`在全量前挂载、低空间测试PASS，收尾已正常卸载disk6；DMG保留证据目录。日志/xcresult根 `/private/tmp/pgos-important-days-evidence/`。
- 外部阻塞：无。远端workflows实际0，独立CI NOT_RUN；实际桌面/通知/VoiceOver/签名/手机/私库均Owner Gate，不称PASS。
- 下一边界：Owner按验收报告的四个日子决定设备验证；本批次不继续产品/发行。文档交付后核对远端SHA/PR Draft/base并停止；不盲目重跑或换分支。

## 收敛阶段真实记录（不同SHA不混算）

| 运行/提交 | 结果与根因 |
| --- | --- |
| WidgetRenderRoute1，58355 | 7WidgetUnit+1真实热路由UI PASS exit0；Record草稿/当前编辑器原值和失效ID降级均断言，delivered=2。实际SwiftUI PNG目视长名/大数/AX/照片遮罩。 |
| ReviewFix1，修复工作树 | 8WidgetUnit PASS；往年期次UI FAIL，已成功写入/重开，后段把含当前值的Picker查成仅标签且先滚过头。新增稳定filterID并先执行General负/2024正筛选。 |
| ReviewFix2，06ce32a | 9WidgetUnit PASS（含privacy实际像素正负/实际provider35午夜DST）；往年农历2024-02-10期次UI PASS，coldRoute UI FAIL：无参数标准冷启动为中文且有unsigned AppGroup收件箱提示，截图cold-route-wait.png显示pending正确未绕过。测试处理提示/locale/pending，不放宽产品路由。 |
| ReviewFix3，9017a2c | 日期11+新提醒7+旧Todo提醒7=25/25 Unit PASS；cold启动/启动失败不绕过→Retry后交付UI PASS；编辑preset UI FAIL，真实Chinese hydration误触calendar确认导致Save禁用。9f修复加载/用户编辑区分并保留perspective，独立双审通过。 |
| FinalUnit1，9f34034 | 一次全量362：358PASS/4FAIL/0SKIP exit65，runtimeWarnings=[]；真实低空间PASS。三个旧wire fixture错误携带v8新增空keys被拒，一个expectedCounts漏4新零项。原始失败不删除。 |
| FinalFocused1，b3cc408 | 仅测试修订后整备份类53/53 PASS；新v8八种missing/null反例、v7新keys反例+合法v7正例通过；集中17/17 UI PASS，合计70/70、0失败/跳过、exit0，四次系统URL送达。4条Invalid frame dimension分别归于QuietWins五来源、每日重复Todo、WeeklyReview、Weight测试（不是根因证明）。没有为test-only修正机械重跑全部旧Unit。 |
| 三构建，b3cc408 clean | `debug-final.log`、`release-simulator.log`、`release-device.log`，exit0；`final-product-build-proof.json`：App/Share/Widget×3配置均原版本1.0(7)，SHA=b3且Dirty=false；源entitlements同原AppGroup，URL suixinlog；未Archive/签名。 |

构建命令：`xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug|Release -destination 'generic/platform=iOS Simulator'|'generic/platform=iOS' -derivedDataPath /private/tmp/pgos-important-days-final-build build CODE_SIGNING_ALLOWED=NO`（Debug仅sim，Release两目标）。

全量命令使用下方统一test前缀，selector `-only-testing:PersonalGrowthOSTests`，result FinalUnit1。集中使用driver，selectors：完整ImportExportRecoveryTests、完整ImportantDayUITests、AppLaunchSmokeTests下 `testRecordTabIsTheNativeCaptureDestination`、`testBuild9TodayFirstScreenAndPeriodActions`、`testWeightEntryIsAccessiblePersistsAndShowsLatestValue`、`testWeeklyReviewSavesMultipleFieldsAfterKeyboardDismissalAndPersistsAcrossRelaunch`、`testPR6FilesPreviewCancelAndRestore`、`testTodoQuickContinuousInputCompletionStatisticsSearchAndRestart`、`testTodoDailyRepeatCompletionSkipStopAndRestartKeepsOneOpenOccurrence`、`testQuietWinsFiveSourcesRangeAndTodoUndoRefresh`、`testQuietWinsOpenPagesRefreshAfterRealBackgroundImportAndRapidRanges`、`testStartupDiagnosticCopiesAndSafeRetryPreservesExistingEntry`。17条UI，不称全套UI。

以下为原始开发历史，所述“下一步/尚未”只对当时checkpoint有效；当前接续以上方断点为准。

## 2026-10-15 数据/规则 checkpoint

已实现：共享纯日期模块（1901–2100；上海农历，原始事实与派生值分开）、V12 追加四实体、v8 备份（旧 v1–v7 读取路径保留）、独立封面复制/回滚、Entry/Todo 类型引用及原记录删除清理、创建/列表/详情/搜索/Today 初步集成。提醒在原 Todo coordinator 内统一日子和 Todo 候选与实际 pending，daily/weekly 共用串行 gate；保守总预算 60，日子最多预排两个期次并显示实际覆盖。仍需组件、路由、双语、交互收口与完整验收，不能称 A/B 已完成。

实际命令统一前缀：`xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=EC7758DB-5D1B-4D1C-AA4D-900A9E11B66A' -derivedDataPath /private/tmp/pgos-important-days-data-build -collect-test-diagnostics never -parallel-testing-enabled NO … test CODE_SIGNING_ALLOWED=NO`。Xcode 27.0 / iOS 27.0，专用合成模拟器，无私人数据。

| 运行 | 选择器/结论 | 原始证据（`/private/tmp/pgos-important-days-evidence/`） |
| --- | --- | --- |
| Date1 | 新日期10项，9 PASS/1 FAIL，exit65；误选2023正月三十正例，HKO显示该月廿九。修正为HKO 2025-02-27=正月三十；未删反例。此run使用初始FD666…模拟器；后续专用模拟器。失败后系统diagnose长等待，进程最终自然结束。 | date1.log / Date1.xcresult |
| Data build1 | V12/v8 Debug 编译 PASS exit0，代码尚未固定提交 | data-build1.log |
| Data1 | 日期/数据15项，14 PASS/1 FAIL exit65；精确备份比较暴露Date epoch转换精度。新增v8时间戳复用参考epoch原语；Entry旧格式边界不扩修。 | data1.log / Data1.xcresult |
| Data2 | 同15项全PASS，exit0。fixture teardown前仍持有SQLite导致unlink warning；已改为XCTest teardown，Integration1未再出现该警告。 | data2.log / Data2.xcresult |
| UI build1 | 初步管理/详情/表单/关联与入口 Debug 编译 PASS exit0 | ui-build1.log |
| BaselineFixture | 精确20d315a归档，只追加生成测试，1/1 PASS exit0；生成V11.1磁盘/Media/v7，WAL=0，未复制SHM；脚本及小fixture提交。不是旧全量基线。 | baseline-fixture.log / BaselineFixture.xcresult |
| Reminder build1 | FAIL exit65；复杂compactMap Swift类型推断超时，拆为显式循环，行为不变 | reminder-build1.log |
| Integration1 | 日期10+数据6+重要日子提醒5+旧Todo提醒7+旧迁移保护2 = **30/30 PASS，0失败/跳过，exit0**。选择器为三个ImportantDay测试类、TodoReminderTests、TodoFoundationTests/testOriginalV11CandidateMigratesWithoutLosingTaskEventBytesAndInfersReminderLead、testBuild12V10ContainerAliasMigratesWithoutFalseMissingStore259。保留旧alias路径SQLite诊断；模拟失败通知日志符合测试。 | integration1.log / Integration1.xcresult |

上述为开发中工作树证据，固定checkpoint提交随后由Git产生；不得将其当成最终产品全量验证。尚未全量Unit/集中UI/Release/device构建、Widget、远端CI或独立审查。

农历独立真值：香港天文台 [2023](https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2023e.pdf)、[2024](https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2024e.pdf)、[2025](https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2025e.pdf)。覆盖新年、闰二月、年末和缺三十；全1901–2100年初一遍历为内部一致性测试，不冒充200年逐日独立天文核验。范围外拒绝，不猜测。

当前下一步：固定 checkpoint 并启动独立数据/规则审查；继续Widget target/三种表达/最小授权快照和安全路由，不停在A。

## B 开发中的恢复点

已加入实际 Widget target/scheme/embed、同一 App Group、数字/照片/清单与 AppIntent 配置、原子授权快照/小图、35天时间线、稳定URL与通知路由、恢复后重建、连续裁切预览、实际提醒反馈、组件说明及159个提取键中英翻译。尚未最终审查/完整回归，不能视为完成。

- R1独立数据审查针对固定cbd2075无confirmed新P0/P1/P2，见REVIEW；新差异仍需复审。1cfa漏暂存project注册已追加cbd2075修复并推送。
- Draft PR #10已建立并附在当前会话。首次gh因正文文件未写入而失败（无PR）；写入后查询无重复再创建。
- Widget build1/build2 Debug PASS（App/Share/Widget，无签名）；Widget1 **6/6 PASS exit0**。缺图框架输出路径后已补fileExists，避免此日志。
- ImportantUI1 **2/4 PASS exit65**。最短创建/相关记录重开与中文最大字号通过；确认开关点击落在标签而未切换，录屏明确off。XCTest open(URL)重启进程99226到99234，不能证明热草稿。截图发现紧凑日期控件在最大字号裁切，已改为原生wheel和换行日期；原Dark启动参数无效，不能将原截图当Dark。
- ImportantUI2 **2/3 PASS exit65**。右侧开关点击和值=1后，日期确认流程PASS；启动专用模拟器并实际simctl appearance dark后，大字号wheel截图PASS。系统openurl已提交，但iOS中文“打开”确认尚未点击，路由未送达；保留route-warm-wait.png。已补系统确认交互，AffectedB1进行中。
- 当前命令为 `python3 Scripts/run_important_day_route_ui.py --simulator EC7758DB-5D1B-4D1C-AA4D-900A9E11B66A --result /private/tmp/pgos-important-days-evidence/AffectedB1.xcresult --log /private/tmp/pgos-important-days-evidence/affected-b1.log`，选择ImportantDayPersistenceTests、ImportantDayReminderTests、TodoReminderTests、ImportantDayWidgetTests及一项热路由UI。脚本读取XCTest readiness后发真实simctl openurl，测试确认系统弹窗，不用自造router状态代替外部事件。单独Xcode运行热路由测试缺driver会等待失败；集中UI须使用此脚本。
- 新低空间/收藏排序回滚、QuietWins关联正反对照，以及可注入daily/weekly实际调度适配的共享容量/串行验证已补入，待本轮结果。

下一步：处理AffectedB1实际失败，核验中文Dark截图与桌面实际呈现；固定B SHA，独立产品/集成审查与数据增量复审；之后一次全量Unit/集中关键UI及最终无签名构建。

- AffectedB1：受影响Unit **27/27 PASS**，其中含实际daily/weekly适配共享容量与串行验证。1项热路由UI后段FAIL，真实同进程草稿值断言已经通过；返回后键盘恢复覆盖Tab，导致Growth点击失败。已仅在外部路由呈现前明确结束键盘焦点，不改草稿/Tab。
- RouteUI3：真实系统URL两次均送达，Record原值及当前编辑器未保存文本断言通过、排队通知通过；末段FAIL因测试把实际StaticText“Day unavailable”查成Other。原始层级1508E875附件证明降级已呈现；已改为精确标题和描述断言，不改产品降级逻辑。
- Widget真实视图已共享到App帮助页，不再仅用列表行预览；照片裁切、遮罩、数字语义使用同一代码。AX尺寸减少副信息/清单行，固定物理尺寸内将文字缩放上界设为xxxLarge，数字最小缩放0.8，完整名称/距离提供语音标签；不以微小字号塞入全部信息。待真实SwiftUI渲染与人工目视检查。
