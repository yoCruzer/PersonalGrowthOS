# Todo V1 执行记录

## S0 基线

2026-10-09：完整读取 Goal Pack Rev2 五文件，按 AGENTS 顺序读取 Foundation/Contract/Current；git status 起始干净 main/dd09975。实际 git fetch 成功；PR 栈 #1–#7 均 OPEN Draft。annotated tag 与 origin/codex/external-capture-v1 均 c5a3c0ac859efc3ffa4e5d9f77909ec43565c871。创建 codex/todo-v1-personal-actions，未改旧 PR/标签/编号/签名。Owner 当前安装 Build 12 的事实与仓库 App 1.0(7) 分开。

## S1 定向门禁

环境 Xcode 27.0 (27A266a)，iPhone 18 Pro Simulator iOS 27.0，UDID FD666264-A2DF-445C-A77D-534B9E8ED595。所有证据在 `/tmp/pgos-todo-evidence/`。

命令公共参数：`xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO`；每次独立 resultBundlePath，对应日志同名。

- domain-1 / domain-2：exit 65，分别是新 SwiftData 谓词捕获/throwing while 与新测试缺少 try 的编译错误；没有执行测试，未声称通过。
- domain-3：exit 0，7/7 PASS，0 FAIL/SKIP。无日期、多行中文、真实时钟回拨、状态/统计、计划与硬截止、时区、固定四种重复、短月/闰年、DST、幂等撤销/跳过/停止、来源/清单删除、保存失败回滚、重启。
- 精确源码归档 fixture：baseline-fixture 初次 exit 65（生成测试使用错误 StoredMediaFile 字段和私有 snapshot）；修正仅生成测试后 baseline-fixture-2 exit 0，生成真实 V10 sqlite、原始图片与 v6 备份。源码来源与复现方法见 Scripts/Fixtures/README.md；不修改历史 fixture，不接触私人数据。
- domain-migration-1：exit 0，11/11 PASS，0 FAIL/SKIP。9 Todo 测试加原 exact-V7/exact-V8 测试；真实 V10 两次打开、完整旧数据逐字段 equality、图片字节、receipt 及迁移后新增/来源/reopen 验证。TodoIntegrity 拒绝未知状态、错误最终事件、悬挂事件。

## 构建溯源（提前接入）

官方依据：[CI 环境变量](https://developer.apple.com/documentation/xcode/environment-variable-reference)、[自定义构建脚本](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)。App target 的 Generate Build Provenance 阶段位于 Sources/Resources 之前，每次执行，输出 DERIVED_FILE_DIR/BuildProvenance.plist，正常资源拷贝进入最终 App 后由 Bundle 读取，签名后不写 bundle。CI_COMMIT 完整 40 位优先；若存在但格式无效或与可核对 HEAD 不符，构建失败。真实 CI_TAG 可选、受长度/字符校验；本地读取对应 SRCROOT HEAD + dirty，无 Git 未知。Version/Build 仍取 Bundle 原字段。

- `python3 Scripts/verify-build-provenance.py` exit 0：实际脚本的合成 clean/dirty、CI tag/非 tag、无 Git、非法/过期 SHA、不安全 tag 全部通过。
- provenance-1：exit 0，2/2 PASS，0 FAIL/SKIP；实际 Debug App 包资源存在、完整 SHA/短 SHA/组合复制行为通过。产物 `/tmp/pgos-todo-derived/Build/Products/Debug-iphonesimulator/PersonalGrowthOS.app/BuildProvenance.plist` 此次 Commit=c5a3c0ac859efc3ffa4e5d9f77909ec43565c871，Source=localGit，Dirty=true（当时尚未提交新源码），Tag 空；不是硬编码输出。
- Release、模拟 CI 编译产物、实际 About UI/粘贴、双语大字体深色等仍待候选验证，不能用 helper/脚本测试替代。

## S2–S4 功能与失败审计

已接入 Hub/连续录入/详情/清单/Entry 来源/局部与全局搜索/四项统计；固定锚点重复和稳定期次；独立 opt-in 通知协调（启动/前台/时间变化/成功导入重建）；v7 五实体完整 DTO、计数、严格校验、空库保护与取消回滚。通知变更只在持久化成功后发生，Todo 前缀不取消旧每日/每周提醒。

重要修复：
- 事件内 Date 使用 2001 epoch，旧外层备份使用 1970 epoch 会引入一 ULP 精度差。Todo v7 DTO 使用明确 reference epoch，保持精确事件链比较；未弱化校验，未改旧实体 wire。
- 保存关闭由父 sheet 回调统一负责，避免重复 dismiss；连续保存维持标题焦点；键盘关闭按钮可见。清单重命名改为原生 sheet，确认删除只解除归属。
- 重复提醒保留原本的日/墙钟分钟，DST 缺时按 nextTime 解析，换时区不把缺时补偿后的 03:00 当成原 02:30。并发通知 pass 重读；权限请求只源于显式提醒操作。
- About Version/Build 添加语义标签；短 SHA 单独一行，真实最大字体仍完整显示。大字号系统字符串先前无效，改用 UIKit rawValue 并用渲染高度证明生效。
- 旧 synthetic v4/v5 测试移除 v7 空 keys，保持它们真实历史 wire；旧 fixture 字节未改。新增并发预检测试为合成目录显式注入容量，消除目录未创建导致的无关 I/O 错误。

各轮结果（独立 resultBundle/log，不把失败整组重标全绿）：

| Result bundle 前缀 | PASS | FAIL | 结论 |
| --- | ---: | ---: | --- |
| ui-reminders-compile-2 | 4 | 0 | 通知替身定向通过；前一轮 catch shadow 编译失败。 |
| ui-reminders-3 | 8 | 1 | Entry UI 使用旧 capture ID，未进入预期路径；修正正确 ID 后补验。 |
| backup-todo-1 | 62 | 2 | 旧 wire synthetic 与新往返精度各失败；来源 UI 已通过。 |
| backup-todo-2 | 1 | 1 | 旧 wire 修复通过，Todo 精度仍失败。 |
| backup-todo-3 | 0 | 1 | 精确定位到 todo integrity；随后修正 epoch。 |
| backup-todo-4 | 14 | 0 | 13 领域与完整 Todo 往返通过。 |
| todo-integration-2 | 23 | 3 | 23 Unit 通过；3 UI 键盘/rename/中文标签路径失败。 |
| todo-integration-3 | 6 | 3 | 6 Unit 通过；3 UI rename、Toggle 点击位置、Version 语义失败。 |
| todo-ui-4 | 1 | 1 | 清单/统计贯通通过；重复 Toggle outer row 点击无效。 |
| todo-daily-ui-5 | 1 | 0 | 系统权限交互、重复完成/跳过/停止/重启贯通通过。 |
| todo-chinese-real-dark-5 | 1 | 0 | 中文深色语义通过，但截图字号普通，不能算最大字体。 |
| todo-chinese-actual-size-6 | 0 | 1 | 真实最大字体编辑/高度通过；任务位于 lazy List 下方未滚动，断言失败。 |
| todo-chinese-actual-size-7 | 1 | 0 | 正常滚动后，真实最大字体编辑/Hub/About 语义及截图通过。 |
| todo-concurrency-perf-1 | 16 | 1 | 15 领域/性能与导出截止点通过；并发预检合成容量设置遗漏。 |
| todo-concurrency-2 | 1 | 0 | 容量注入后，预检并发拒绝且重开保留 Todo 通过。 |

另 `todo-integration-1` 是新测试参数顺序编译失败，未运行测试。UI 系统诊断曾额外等待约 600 秒，后续公共命令加 `-collect-test-diagnostics never`；并非测试断言被跳过。

有界性能 `testBoundedThousandTodoIntegritySearchAndStatisticsPerformance`：1000 个 Todo/1100 事件，3 次完整性校验、搜索、最终统计和稳定排序；0.091714458 / 0.091158908 / 0.094870064 秒，峰值 physical 28985.888 kB（XCTest metric，不是 App 总内存承诺）。源事实与独立预期核对，未为节省时长跳过持久化/完整性。

中文实际最大字体证据：`todo-chinese-actual-size-7.xcresult` 的 Editor/Hub/About 三张 keepAlways 截图。设置为 Dark + accessibilityExtraExtraExtraLarge，标题渲染高度 >150pt；语义检查 elementDetection/hitRegion/sufficientElementDescription/trait，通过不等于已运行真机 VoiceOver 朗读。

## 候选尾端门禁（执行前计划；结果见下文）

只在功能冻结后运行一次完整 Unit 与一次关键 UI 集中 gate；实际 counts/命令/源码 SHA 后续记录。Release/模拟 CI 产物与普通 push/Draft PR 尚未完成，当前不标 READY。远端没有配置 GitHub Actions workflow；普通 push 后只读检查 checks/statuses，实际 Xcode Cloud 发行未触发。Owner 真机与私人数据门禁保留。

## 候选首轮与数据审查闭合

功能候选 fb63f58420c68f4cadb0ab31d01bc7cbac2c9854：candidate-full-unit-1 exit0，283/283 Unit PASS，0 FAIL/SKIP。candidate-key-ui-1 exit65，17/22 UI PASS，5 FAIL：两个 CaptureFixtureHost 未安装；Safari 页面未加载预期 fixture；Entry 编辑后的正文与预期不一致；follow-up 删除后仍存在。没有将这些归为已通过，继续定向定位。

最后审查补上首个事件必须 created、seriesStopped 对应系列必须停止的校验；新增正负配对与12种坏 Todo 包的精确 invalidObject 断言（包括清单/系列/期次/来源身份）。复验包括领域、提醒、完整备份、启动组合与历史迁移相邻路径；不重复全量。

本地 Release app/appex 编译 exit0，均1.0(7)，localGit/clean/SHA=fb63f58420c68f4cadb0ab31d01bc7cbac2c9854。模拟 CI 标签编译、随后同 DerivedData 无标签编译 exit0，真实资源同 SHA/Source=xcodeCloud，Tag 从 todo-v1-ci-verification 清为空；未创建标签。脚本完整矩阵再次 exit0。远端普通 push成功，workflows=0、check-runs=0、statuses=[]；API aggregate pending 不代表有 CI 正在运行，远端 CI NOT_RUN。

candidate-integrity-closure-1（d0c41e88b0f1e9c444fa3a14a5cb23ce22d389c3）exit0：123/123 Unit PASS，0 FAIL/SKIP，包含 Todo/提醒/ImportExportRecovery/AppComposition/PersistenceMediaFoundation。审查再补 revision=Int.max 的无溢出拒绝，13种坏包断言保持精确，不通过 +1 的溢出崩溃处理输入。

candidate-failed-ui-2 exit65：0/5 PASS，5 FAIL。新增诊断独立证明 Entry TextEditor tap 把光标放开头，实际内容为“ editedA restart-safe memory”；改为 UI 选全文并输入完整预期，原编辑/保存/重启断言保留。补充确认删除代码不再从随 dismiss 清空的 optional 读取目标，使用 confirmationDialog presenting 捕获目标。Safari 未离开 start page，地址栏增加实际屏幕内中心点击、键盘与 Go 按钮断言，保持真实页面/选中文字/分享/取消/导入断言。Host 安装后在 iOS27 因 NoSceneLifecycleAdoption 崩溃，按 Apple TN3187 增加 UIScene，仅合成测试 Host 变化（App/ShareExtension 不改生命周期）。
官方依据：https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle 。Crash 堆栈为 UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption，来源是本轮合成 Host，不是产品 App 崩溃。

后续只复验新增校验相关 Unit、Entry 删除相邻路径和五个失败 UI，不将前两轮失败重标通过。


## 最终定向收口与真实产物

candidate-final-closure-3：提交 1286a8ff1ea61f7da277bf6803930c7d6984dadc，exit65；83 Unit + 4 UI PASS，2 UI FAIL，0 SKIP。Unit 为 TodoFoundation 16、TodoReminder 5、ImportExportRecovery 52、EntryDomain 10；覆盖 Int.max revision 无溢出拒绝、13种非法 Todo 包、完整恢复/回滚/相邻 Entry。两个合成 Host 已实际运行，编辑全文保存→重启和 Todo Entry 来源通过；Safari 与 follow-up UI 仍失败，不改写本次整组结论。

| 后续 resultBundle 前缀 | PASS | FAIL | 结论 |
| --- | ---: | ---: | --- |
| candidate-last-ui-4 | 0 | 2 | Safari 地址栏/Go 未正确定位；补充详情误选背景搜索片段，未进入确认。 |
| candidate-last-ui-5 | 0 | 2 | Safari 编辑层级证明 Keyboard Focused URL 输入字段与底层 capsule 不同；补充 alpha 删除与刷新已成功，beta 结果贴近底部搜索栏未进入详情。 |
| candidate-last-ui-6 | 1 | 1 | 可见结果 row、详情限定 follow-up、确认限定 sheet 后，补充双删除/返回保留 query/无结果通过；Safari XCTest typing 后编辑字段消失。 |
| candidate-safari-ui-7 | 0 | 1 | 对已聚焦 App typing 同样关闭 Safari 编辑层，未到扩展。 |
| candidate-safari-ui-8 | 0 | 1 | 系统 Paste 菜单已出现，但错误查询 Button；实际 AX 为 MenuItem。 |
| candidate-safari-ui-9 | 0 | 1 | URL正确、网页/选中文字/分享/取消/保存/搜索导入均通过；来源是 Link，旧 Button 查询失败。 |
| candidate-safari-ui-10 | 1 | 0 | 按 identifier 查询实际 Link 后，完整 Safari 来源打开与重启保留通过，exit0。 |

全部范围断言保留：合成 URL 在 Safari 系统编辑器通过真实 Paste/Go 输入（不是绕过 Safari 或 mock 导入），真实 localhost HTML、选中文字、Share Extension、取消回到选择器、保存、搜索刷新、View Original、重启；补充两个匹配均删除且回到无结果。录屏/AX 诊断表明失败涉及 SDK UI 定位与输入，不把所有失败反推为产品缺陷。confirmationDialog presenting 的稳定目标捕获作为相邻 UI 加固保留。

最终产品/测试提交 **837b619e5f2d6a0367aa31d61e3829acf731b4e4**：TodoEditor 保存重试沿用 submissionID，Save and Add Another 成功后才换新 ID；领域已有 create retry/稳定身份正负证据。final-todo-ci-ui-1 连续输入明确 Open=2，验证两条任务不复用 ID。该轮在干净提交上注入 CI_COMMIT=837b619e5f2d6a0367aa31d61e3829acf731b4e4 / CI_TAG=todo-v1-ci-verification，五项 Todo UI 的结果见下方最终门禁记录。此 CI 标签仅合成输入，没有创建 Git tag。About keepAlways 截图、真实完整 SHA 复制→Todo 粘贴；实际 Debug bundle Commit/Source/Tag 与输入精确一致。

Release：final-code-release-local / final-code-release-ci-tag / final-code-release-ci-untagged 三次 exit0，源码 1286a8ff1ea61f7da277bf6803930c7d6984dadc；真实 plist 分别 localGit/无标签、xcodeCloud/测试标签、同 DerivedData xcodeCloud/空标签。最终产品 837b619e5f2d6a0367aa31d61e3829acf731b4e4 的 final-product-release-local exit0，实际 App/唯一 appex 可执行文件存在，均1.0(7)，Commit=837b619e5f2d6a0367aa31d61e3829acf731b4e4 / Source=localGit / Dirty=false / Tag空。同一最终产品的 Debug CI 资源逐字段核对，保存 bundle.json；不把旧产物标为新提交。

final-provenance-script-matrix.log：实际 Scripts/verify-build-provenance.py 再次 exit0。final-static-audit.json：原511字符串逐项不变、615条均 en/zh-Hans；冻结历史模型/旧 V7/V8 fixture、ShareExtension、原 Info/entitlements/scheme、Contract、V1_SCOPE 无变更；project 只新增文件/资源/编译前阶段，Version/Build/签名/AppGroup/bundleID 配置保持。少数长文本 UI 的 xcresult 记录 Invalid frame dimension 框架运行警告；不宣称已定位警告根因，不通过删除断言处理。

### 可复查命令

环境：主力本机 macOS27.0.1 / Xcode27.0(27A266a)，iPhone18Pro iOS27.0(24A434) 专用 Simulator。以下为实际门禁参数；resultBundle/log 位于 /tmp/pgos-todo-evidence，重复执行需换新的 resultBundlePath。没有再跑第二次完整 Unit/22项关键 UI gate。

```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-todo-evidence/candidate-full-unit-1.xcresult -only-testing:PersonalGrowthOSTests > /tmp/pgos-todo-evidence/candidate-full-unit-1.log 2>&1
```

关键 UI 首轮实际命令（17/22 PASS，exit65；失败点分别由上文补验收口）：

```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-todo-evidence/candidate-key-ui-1.xcresult -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testStartupDiagnosticCopiesAndSafeRetryPreservesExistingEntry -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTextCaptureAppearsInTimelineAndSurvivesRelaunch -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPermanentDeleteRemovesEntryFromTimeline -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testArchivedEntryCanBeRestored -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTagLinkAndGlobalSearchFindEntry -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testRepeatableHabitCounterIncrementsDecrementsAndPersists -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testGoalAndFlagOpenEditAndPersistAcrossRelaunch -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testWeightEntryIsAccessiblePersistsAndShowsLatestValue -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testWeeklyReviewSavesMultipleFieldsAfterKeyboardDismissalAndPersistsAcrossRelaunch -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testLibraryHistoryAndSearchReopenTheSavedWeeklyReview -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testBuild9TodayFirstScreenAndPeriodActions -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPR6SearchRefreshesAfterDeletingMatchedFollowUps -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPR6FilesPreviewCancelAndRestore -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPublicMixedProviderHostShowsExtensionAndImports -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testExternalCaptureSafariShareAndImport -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testReadyShareCancellationReturnsToSystemPicker -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testBackupDisclosesPendingExclusionAndCancelKeepsShares -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoQuickContinuousInputCompletionStatisticsSearchAndRestart -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoEntrySourceKeepsOriginalRecord -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testAboutContainsRealCommitAndCopiesFullSHAIntoTodoInput -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoListCreateRenameFilterAndConfirmedDeleteKeepsTask -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoDailyRepeatCompletionSkipStopAndRestartKeepsOneOpenOccurrence > /tmp/pgos-todo-evidence/candidate-key-ui-1.log 2>&1
```

```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-todo-evidence/candidate-integrity-closure-1.xcresult -only-testing:PersonalGrowthOSTests/TodoFoundationTests -only-testing:PersonalGrowthOSTests/TodoReminderTests -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests -only-testing:PersonalGrowthOSTests/AppCompositionTests -only-testing:PersonalGrowthOSTests/PersistenceMediaFoundationTests > /tmp/pgos-todo-evidence/candidate-integrity-closure-1.log 2>&1
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-todo-evidence/candidate-final-closure-3.xcresult -only-testing:PersonalGrowthOSTests/TodoFoundationTests -only-testing:PersonalGrowthOSTests/TodoReminderTests -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests -only-testing:PersonalGrowthOSTests/EntryDomainTests -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testExternalCaptureSafariShareAndImport -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPR6SearchRefreshesAfterDeletingMatchedFollowUps -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPublicMixedProviderHostShowsExtensionAndImports -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testReadyShareCancellationReturnsToSystemPicker -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTextCaptureAppearsInTimelineAndSurvivesRelaunch -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoEntrySourceKeepsOriginalRecord > /tmp/pgos-todo-evidence/candidate-final-closure-3.log 2>&1
CI_COMMIT=837b619e5f2d6a0367aa31d61e3829acf731b4e4 CI_TAG=todo-v1-ci-verification xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-todo-evidence/final-todo-ci-ui-1.xcresult -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoQuickContinuousInputCompletionStatisticsSearchAndRestart -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoEntrySourceKeepsOriginalRecord -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testAboutContainsRealCommitAndCopiesFullSHAIntoTodoInput -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoListCreateRenameFilterAndConfirmedDeleteKeepsTask -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoDailyRepeatCompletionSkipStopAndRestartKeepsOneOpenOccurrence > /tmp/pgos-todo-evidence/final-todo-ci-ui-1.log 2>&1
xcodebuild build -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pgos-todo-release-derived CODE_SIGNING_ALLOWED=NO > /tmp/pgos-todo-evidence/final-product-release-local.log 2>&1
python3 Scripts/verify-build-provenance.py > /tmp/pgos-todo-evidence/final-provenance-script-matrix.log 2>&1
```

Safari 最终单项使用同一公共命令，resultBundlePath=candidate-safari-ui-10.xcresult、only-testing=PersonalGrowthOSUITests/AppLaunchSmokeTests/testExternalCaptureSafariShareAndImport。补充单项在 candidate-last-ui-6 与 Safari 联跑。测试 Host 需先用 Scripts/build_capture_fixture_host.sh 构建，再 xcrun simctl install 到上述专用 UDID；默认合成 App 路径 /tmp/PGOSCaptureFixtureHost.app。真实 V10 fixture 独立源码归档/生成命令见 Scripts/Fixtures/README.md。

实际 JSON/PNG 来自 xcresulttool，而非聊天手写 counts：
```sh
xcrun xcresulttool get test-results summary --path /tmp/pgos-todo-evidence/final-todo-ci-ui-1.xcresult --format json
xcrun xcresulttool export attachments --path /tmp/pgos-todo-evidence/final-todo-ci-ui-1.xcresult --output-path /tmp/pgos-todo-evidence/final-todo-ci-ui-1-attachments
```

### NOT_RUN 与下一边界

Owner 私人 Build12 库保留数据覆盖安装、真机签名/AppGroup、真实通知送达/拒绝设置、硬件/飞行模式/旅行/VoiceOver 朗读、实际 Xcode Cloud/Archive/TestFlight NOT_RUN。无 Git 整 App UI 未另跑（实际脚本与 Bundle reader 未知分支已覆盖）。没有重跑所有历史 UI；本轮一次22项关键 UI gate覆盖旧核心，再按失败范围补验。远端 GitHub Actions workflows=0，没有可运行的独立 CI；最终普通 push 后只读检查 checks/statuses，不触发分发 CI，不把 aggregate pending 写成运行中或成功。Owner 十分钟清单及 A1–A25/P1–P8 对应证据见 TODO_V1_ACCEPTANCE.md。


### 最终门禁结果

final-todo-ci-ui-1：837b619e5f2d6a0367aa31d61e3829acf731b4e4 干净提交，exit0，5/5 UI PASS，0 FAIL/SKIP（About、连续输入/状态/统计/搜索/重启、Entry来源、清单、每日重复/跳过/停止）。实际 About 截图 1BA44044-D54C-48B3-8498-9F069A7F56E3.png 已视觉核对：Version1.0 / Build7 / SHA837b619e5 / Xcode Cloud / Release Tag todo-v1-ci-verification 全部可见；完整40位实际复制→粘贴通过。前述首轮17/22与所有失败原样保留；五个失败点各有随后通过证据，未重新把22项整组改标全绿。

当前自动门禁与 A1–A25/P1–P8 文档收口完成，下一步仅普通 push、新 Draft PR 与交接；尚未把未创建的 PR 当作已交付。


## S5 交付与停止边界

普通 git push origin codex/todo-v1-personal-actions 成功，独立 Draft PR #8 已创建并附加到本任务：https://github.com/yoCruzer/PersonalGrowthOS/pull/8 。base=codex/external-capture-v1；远端该分支、annotated tag和实际 merge-base 均 c5a3c0ac859efc3ffa4e5d9f77909ec43565c871。旧 #1–#7 状态仍 OPEN Draft，未改base/close/merge。后续交接提交只更新文档；最终HEAD以PR head为准，已验证产品/测试仍837b619e5f2d6a0367aa31d61e3829acf731b4e4。

最后文档提交后执行实际命令：xcodebuild build -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pgos-todo-derived CODE_SIGNING_ALLOWED=NO > /tmp/pgos-todo-evidence/final-handoff-debug.log 2>&1。证据 final-handoff-debug.log / final-handoff-debug-bundle.json：核对当前真实HEAD、localGit、Dirty=false、Tag空，Version1.0/Build7不变；不将文档提交冒称重跑完整测试。最终 git status、PR head/远端分支、本地HEAD和checks/statuses另做只读核对。远端 workflows=0，因此独立CI NOT_RUN，不能冒称通过。

**READY_FOR_INDEPENDENT_REVIEW**。停止当前整体开发Goal，下一边界仅独立Review与Owner设备门禁；本轮无merge/close/tag/改分发编号/Archive/TestFlight/私人库清理。

## ReviewFix + Usability 统一 Goal — 2026-10-09

本轮唯一目标为 Owner 附件 `PersonalGrowthOS_TodoV1_ReviewFix_Usability_Goal.zip/CODEX_GOAL_ZH.md`，完整解压阅读，连续 S0→S4，不按阶段请求确认。实际 `git fetch origin` 与 `gh pr view 8 --json ...`：local/upstream/PR head 均 `4625602b27d8b4e4df4f6da20b7f11bf30b21d8c`，clean，OPEN Draft；base 仍 `codex/external-capture-v1`。初次沙箱 fetch/网络读未获环境访问，常规提权后成功；不是远端异常。

S0 代码确认 S1-A/B/C/D、S2/S3 均成立。S1 正负设计：同日提醒 vs 前一日提醒，this-only vs future-template，Open后继 vs Completed/Canceled，保存失败回滚 vs 保存成功；S2 保留UUID/createdAt/来源/历史、关闭态拒绝/重开接受、日期缺失拒绝、幂等/存储重开/备份；S3 组合状态/日期/清单/关键词与统计钻取严格等价。前期不跑全量 Unit/UI/Clean。

本轮证据目录 `/tmp/pgos-review-evidence`；环境与原轮相同：macOS27.0.1 / Xcode27.0(27A266a)、专用 iPhone18Pro / iOS27 Simulator `FD666264-A2DF-445C-A77D-534B9E8ED595`。公共命令 `xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-review-evidence/<run>.xcresult <only-testing参数> > /tmp/pgos-review-evidence/<run>.log 2>&1`。

- `s1-red` exit65：两个P1新回归按预期 FAIL，原V11合成库生成 PASS（1 PASS / 2 FAIL / 0 SKIP）。A：2/28 错提醒而非2/27；B：后继仍 Individually edited 而非 Future。断言未减弱。生成库只用原产品源码，checkpoint后WAL=0，复制到 `Fixtures/OriginalV11Fixture`，生成代码和来源随库保存；未触碰私人库。
- `s1-target-1` exit0：TodoFoundationTests + TodoReminderTests，23/23 PASS。尚不等于完整 S1 Gate。
- `s1-target-2` exit65：新恢复测试误用 ZIPArchiveReader 参数，编译失败未运行。
- `s1-target-3` exit65：新通知测试 async 非throwing闭包中直接try，编译失败未运行。
- `s1-target-4`：定向 Foundation/Reminder/ImportExport + 保存拒绝反馈/损坏恢复两项 UI，结果待实际完成提取。

实现选择：提醒以固定原始 plannedAnchorDay（否则deadlineAnchorDay）为锚点、civil day offset支持±366、保持墙钟分钟/DST首次与缺时顺延；新增可选series字段和v7 DTO字段。冻结旧V11 11.0.0 TodoSeries，新V11为11.1.0轻量迁移，V1–V10不动；legacy nil policy从首个匹配墙钟期次恢复，不重写事件。future编辑覆盖已有Open后继的标题/备注/重要/清单/提醒（明确覆盖单独模板编辑），不改后继日期/身份；withdrawn复用时应用当前模板，deliberately Canceled/Completed不复活。保存后共享反馈在editor连续输入和shell关闭后显示，checking不冒报排队成功，可重试/系统设置。Todo启动校验先于media修复/bootstrap：先冻结pre-open SQLite/WAL，完整性异常只提供诊断与raw retained ZIP，正常写入暂停；raw包不是正常v7恢复包，不自动修复/清库。

- `s1-target-4` exit65：80 Unit + 启动恢复1 UI PASS / 提醒拒绝反馈1 UI FAIL，0 SKIP。完整导入导出与非法包、原Build12V10迁移和冻结候选V11迁移均通过。失败准确为新banner按钮标识被app-shell覆盖；看到saved/denied/settings不是排队成功，随后调整标识层级。
- `s1-supplement-5` exit65：2 Unit（提前1日v7精确往返、15种非法包含367日/无分钟偏移）+提醒拒绝反馈1 UI PASS / 原每日重复1 UI FAIL。截图/AX直接证实TabView top inset反馈与Today导航栏重叠，Hub点击未发生；是产品布局缺陷，不归因权限弹窗。修复移至五页面底部，关闭按钮>=44pt。
- `s1-ui-6`：只补验提醒拒绝与原每日重复路径，结果待提取。附加防并发：准备rawZIP时禁Retry，防止恢复文件读取中进入正常启动修复。

S1 Gate：`s1-ui-6` exit0，2/2 UI PASS（拒绝提醒保存反馈 + 原每日重复完成/skip/stop/restart）；结合前述80 Unit/损坏恢复UI及2项偏移备份补验，四项修复闭合，自主进入S2。依然保留首轮与补验失败，未全量重跑。

S2：已有Open单次编辑频率建立series与index0/key，保留原task/createdAt/source/旧event bytes，追加convertedToSeries事实；在同save事务中，失败全回滚。已有series只允许精确的已提交转换重试，不允许任意频率变更；关闭态先重开，无日期明确拒绝。复用S1相对日提醒。

- `s2-target-1` exit65：27 Unit PASS / 新转换1 UI FAIL。四种频率、身份/历史/来源/清单/重要/提醒保留、关闭态和缺日拒绝、回滚/幂等、磁盘两次重开、完整v7往返与15类非法包均PASS。UI成功选周重复并看到需首日说明，点击保存后error位于lazy Form下方未显示；不删除拒绝断言，改为底部固定可见保存错误提示。
- `s2-ui-2`：只定向补验普通任务保存→重开编辑→周重复→缺日拒绝→显式选计划日→完成→重启后继，结果待提取。

S2 Gate：`s2-ui-2` exit0，1/1 UI PASS，保留原UUID行识别、缺首日明确拒绝、显式选择日期、周重复、完成后重启单后继/统计断言。结合27 Unit，S2闭合，自主进入S3。

S3：主View只保留Today/Upcoming/All；All下直接Task Status菜单显示当前状态（默认未完成），四种状态一层可选，不重复设置Completed/Canceled范围选择。TodoQuery统一组合list/unclassified/normalized keyword；状态仅作用于All，统计专用scope不受All默认状态影响，钻取新view不继承父list/query。回到已打开Hub保留选择，切换回All和重新打开默认Open。空态提示说明当前筛选。

- `s3-target-1` exit65：领域1 PASS / UI1 FAIL。UI默认Open/allStates/completed/canceled/list均通过；原系统searchable收起时无SearchField，后续明确navigationBarDrawer always可见并正常滚动定位。
- `s3-ui-2` exit65：0/1 UI，新增搜索栏将部分lazy行置于视野下方，allStates下Filter Done未被创建，测试改为正常滚动reveal与可见filter选择，保留全部正负断言。
- `s3-ui-3` exit65：0/1 UI。关键词/列表组合、搜索结果完成→重开和返回结果均已走通；新SDK搜索关闭控件实际为Close而非Cancel，AX证据有Clear text和Close。仅测试改为实际Clear text/Close，统计精确行数断言仍保留。
- `s3-ui-4` exit65：0/1 UI。统计按钮存在但位于导航栏后的区域，isHittable仍返回true；按实际frame需位于导航栏下方再点击，保留统计精确数量断言。

- `s3-ui-5` exit0：2/2 UI PASS，状态/清单/搜索/完成撤销/4统计1、1、3、1精确明细/重启通过；中文最大字号菜单语义通过。截图核实该轮实际为浅色，启动参数未改变真实外观，不能算深色证据。
- `s4-polish-dark-1` exit0：33 Unit + 2 UI PASS，0 FAIL/SKIP。实际 `xcrun simctl ui FD666264-A2DF-445C-A77D-534B9E8ED595 appearance dark` 后，最大字号中文四状态截图黑色背景/白色文字完整可读。追加已物化后继通知替换独立预期、孤立event引用损坏原字节恢复；新建与转换共用makeSeries；错误页可滚动。未重跑全量。

S3 Gate闭合，S4候选冻结：完整diff自查（模型/迁移、事件链/幂等/回滚、相对日策略、原字节恢复、共享查询/统计、通知类别与真实反馈、双语/五Tab）通过。项目设置仅新增原V11 fixture资源4行，无版本/签名/AppGroup漂移；原V1–V10 schema前缀与原615条翻译精确不变。随后仅执行一次完整Unit、一次关键UI集中门禁与真实Debug/unsignedRelease产物。未完成交付之前不标READY。

S4完整Unit首轮 `s4-full-unit-1` 在c5cc4117c61d1e05fd5e25318545441813b89c1b干净候选上exit0，296/296 PASS，0 FAIL/SKIP；真实unsignedRelease `s4-release-local` exit0，App/唯一appex均1.0(7)，localGit clean/40位SHA精确等于该HEAD、Tag空。provenance脚本矩阵exit0。Host初次直接执行exit126（脚本未设可执行）；用 `sh Scripts/build_capture_fixture_host.sh /tmp/PGOSCaptureFixtureHost.app` exit0，simctl install成功，未重设产品数据。

尾端自查发现已完成前一期的未来模板编辑仍被旧UI“新提醒必须未来时间”限制：历史提醒日作为固定anchor偏移参照时，应允许改变时分/日期。限定修正为仅既有series+futureSeries允许过去参照；普通新提醒/本期改成过去仍拒绝，不变历史时间可保留。增加独立正负日期测试；这是实际产品边界缺陷，非为了重复测试。集中UI首轮仍继续使用此前已构建c5cc411，不把其结果冒充修正后构建。修正后再执行完整Unit最终gate，以及受影响原重复/转换/About UI补验。

同一边界补齐反馈：从Completed前一期保存future模板时，共享反馈指向本次实际更新的Open后继，故其权限/排队/失败及时可见；候选必须同系列/Open/有提醒，Canceled或无提醒不误报。原已物化后继通知替换mock增加对应正负反馈断言。

限定修正提交fc37594747d639fe12b05c99b4b9c4aa961f11d2，`s4-final-release-local` exit0，新的真实unsignedRelease App/唯一appex仍1.0(7)，BuildProvenance=该完整40位SHA/localGit/Dirty=false/Tag空；源码与签名设置未漂移。原c5cc411与修正后产物记录分开保留。

### 本轮命令选择范围（配合上方公共命令逐项复现）

所有test使用同一公共命令、对应run名称的log/xcresult；以下名称均为实际`-only-testing:`后缀，类前缀Unit=`PersonalGrowthOSTests/`、UI=`PersonalGrowthOSUITests/AppLaunchSmokeTests/`。编译失败轮同样记录，不推测执行了测试。

| run | 实际选择 |
| --- | --- |
| s1-red | Unit TodoFoundationTests/testReviewReminderKeepsOneDayLeadAcrossShortMonthAndLeapYear、testReviewFutureTemplateUpdatesMaterializedOpenButKeepsHistory、testGenerateOriginalV11CandidateFixture（仅在原源码临时生成时存在） |
| s1-target-1 | Unit TodoFoundationTests、TodoReminderTests |
| s1-target-2/3/4 | Unit TodoFoundationTests、TodoReminderTests、ImportExportRecoveryTests；UI testTodoDeniedReminderFeedbackSurvivesEditorDismissalAndOffersSettings、testTodoIntegrityFailureRetainsDataAndOffersDiagnosticAndRawExport |
| s1-supplement-5 | Unit ImportExportRecoveryTests/testTodoV7RoundTripPreservesOccurrencesEventsListsSourcesAndOriginalMedia、testTodoCorruptStateDateEventReferenceDuplicateAndSeriesPackagesAreRejected；UI testTodoDeniedReminderFeedbackSurvivesEditorDismissalAndOffersSettings、testTodoDailyRepeatCompletionSkipStopAndRestartKeepsOneOpenOccurrence |
| s1-ui-6 | 上述2项UI，无Unit |
| s2-target-1 | Unit TodoFoundationTests、上述2项ImportExportRecoveryTests；UI testExistingOrdinaryTodoConvertsToWeeklyKeepsIdentityAndRestartsWithSuccessor |
| s2-ui-2 | 上述转换UI，无Unit |
| s3-target-1 | Unit TodoFoundationTests/testAllStatusDateListKeywordCompositionAndStatisticsRemainExact；UI testAllTodoStatusFiltersCombineListSearchAndFourStatistics |
| s3-ui-2/3/4 | 上述状态组合UI，无Unit |
| s3-ui-5 | 上述状态组合UI + testAllTodoStatusMenuChineseDarkLargestTextIsAccessible |
| s4-polish-dark-1 | Unit TodoFoundationTests、TodoReminderTests；UI testAllTodoStatusMenuChineseDarkLargestTextIsAccessible、testTodoIntegrityFailureRetainsDataAndOffersDiagnosticAndRawExport |
| s4-full-unit-1 | Unit PersonalGrowthOSTests全target |

集中UI实际命令：
```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-review-evidence/s4-key-ui-1.xcresult -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoDeniedReminderFeedbackSurvivesEditorDismissalAndOffersSettings -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoIntegrityFailureRetainsDataAndOffersDiagnosticAndRawExport -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testExistingOrdinaryTodoConvertsToWeeklyKeepsIdentityAndRestartsWithSuccessor -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testAllTodoStatusFiltersCombineListSearchAndFourStatistics -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoQuickContinuousInputCompletionStatisticsSearchAndRestart -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoEntrySourceKeepsOriginalRecord -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testAboutContainsRealCommitAndCopiesFullSHAIntoTodoInput -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoListCreateRenameFilterAndConfirmedDeleteKeepsTask -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoDailyRepeatCompletionSkipStopAndRestartKeepsOneOpenOccurrence -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTextCaptureAppearsInTimelineAndSurvivesRelaunch -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPermanentDeleteRemovesEntryFromTimeline -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testArchivedEntryCanBeRestored -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testRepeatableHabitCounterIncrementsDecrementsAndPersists -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testGoalAndFlagOpenEditAndPersistAcrossRelaunch -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testWeightEntryIsAccessiblePersistsAndShowsLatestValue -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testWeeklyReviewSavesMultipleFieldsAfterKeyboardDismissalAndPersistsAcrossRelaunch -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testLibraryHistoryAndSearchReopenTheSavedWeeklyReview -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testBuild9TodayFirstScreenAndPeriodActions -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPR6FilesPreviewCancelAndRestore -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPublicMixedProviderHostShowsExtensionAndImports -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testExternalCaptureSafariShareAndImport -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testReadyShareCancellationReturnsToSystemPicker > /tmp/pgos-review-evidence/s4-key-ui-1.log 2>&1
```

真实Release实际命令（两轮分别用s4-release-local、s4-final-release-local日志）：
```sh
xcodebuild build -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pgos-review-release-derived CODE_SIGNING_ALLOWED=NO > /tmp/pgos-review-evidence/s4-final-release-local.log 2>&1
python3 Scripts/verify-build-provenance.py > /tmp/pgos-review-evidence/s4-provenance-matrix.log 2>&1
sh Scripts/build_capture_fixture_host.sh /tmp/PGOSCaptureFixtureHost.app > /tmp/pgos-review-evidence/s4-capture-host-build-2.log 2>&1
xcrun simctl install FD666264-A2DF-445C-A77D-534B9E8ED595 /tmp/PGOSCaptureFixtureHost.app
xcrun simctl ui FD666264-A2DF-445C-A77D-534B9E8ED595 appearance light
```

完整Unit首轮1000任务/1100事件有界测量：Clock 0.091795433 / 0.090898107 / 0.091430164秒，physical_peak 53365.304 / 53348.920 / 53348.920kB。XCTest进程测量不等于真实App整体内存承诺；完整性/搜索独立needle/统计900与100/重要排序断言保留。数据/性能指标来自xcresulttool metrics，非手工估计。

`s4-key-ui-1` exit65：21/22 UI PASS，1 FAIL，0 SKIP，真实运行产物SHA=c5cc4117c61d1e05fd5e25318545441813b89c1b。新增转换/筛选、四统计精确、About完整SHA复制、Entry/Habit/Goal/Weight/WeeklyReview、Safari真实分享导入/Host/取消与Files恢复均通过；唯一FAIL为旧连续录入Save and Add Another后的todo-saved-another提示，AX证明Form增长后提示位于lazy视野下方。产品修正移至按钮旁bottom inset，不减弱原断言；随后补验连续录入/编辑器相关路径。整组首轮仍记exit65，不改写21/22。该轮另有4条SwiftUI invalid frame与1条background publication运行警告，保留原始结果并定位来源，不能说零运行警告。

最终产品提交2065065e87863de5a452ade8609bac561a0bd096。`s4-final-full-unit-2` exit0：**297/297 Unit PASS，0 FAIL/SKIP、runtimeWarnings=[]**，包括新增过去模板日期保存正负例、后继反馈/请求替换，原Build12V10与旧V11迁移/重开、旧合法wire/v7精确恢复/15类坏包、并发/取消/回滚与1000任务有界性能。因首轮之后发现两项真实产品边界缺陷，按Goal允许在最终候选再执行完整Unit；没有按阶段重复全量，首轮296/296保留。

`s4-final-feedback-release` exit0；Debug测试实际产物与该真实unsignedRelease均核对完整SHA=2065065e87863de5a452ade8609bac561a0bd096、localGit/Dirty=false/Tag空，App及唯一ShareExtension.appex可执行文件存在、均1.0(7)。后续仅文档交接；最终文档HEAD另做Debug产物核对，不冒称文档提交后再跑全量。

运行警告审计：xcresult diagnostics/legacy issue定位4条invalid frame分别在旧Review打开、Todo每日保存关闭键盘、旧Review多字段、旧Weight；前一整体Goal集中UI已有5条同类，s1-ui-6也已有1条。背景publication在Weight键盘输入动画阶段（00:00:00.405，Save于随后10.23s发生），未给产品源位置；现有WeightRecordService为@MainActor，真实保存→重启与完整Unit通过。没有证据证明其为本轮数据写入回归，也不冒称已消除或完全归因SDK；保留给独立Review，未关闭的运行警告风险与断言失败区分。

`s4-final-affected-ui-2` exit0：6/6 UI PASS，0 FAIL/SKIP，1条invalid-frame警告，真实构建SHA2065065e87863de5a452ade8609bac561a0bd096；连续录入/2个不同UUID/保存提示/完成重开取消/统计/全局搜索/重启、每日重复/skip/stop、权限拒绝反馈、普通任务周转换、About复制、真实Dark中文AX最大编辑/Hub/About均通过。没有重新跑22项；首轮唯一失败在本轮闭合。随后再加强连续保存断言为isHittable并保存keepAlways截图，只做该UI、About与一次Weight警告定位补验，不改产品实现、不重跑全量Unit。

最终完整Unit实际命令：
```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-review-evidence/s4-final-full-unit-2.xcresult -only-testing:PersonalGrowthOSTests > /tmp/pgos-review-evidence/s4-final-full-unit-2.log 2>&1
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-review-evidence/s4-final-affected-ui-2.xcresult -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoQuickContinuousInputCompletionStatisticsSearchAndRestart -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoDailyRepeatCompletionSkipStopAndRestartKeepsOneOpenOccurrence -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoDeniedReminderFeedbackSurvivesEditorDismissalAndOffersSettings -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testExistingOrdinaryTodoConvertsToWeeklyKeepsIdentityAndRestartsWithSuccessor -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testAboutContainsRealCommitAndCopiesFullSHAIntoTodoInput -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoChineseDarkLargestTextAndAboutPassSemanticAccessibilityAudit > /tmp/pgos-review-evidence/s4-final-affected-ui-2.log 2>&1
```


### 最终交接 — 2026-10-10

`s4-visible-feedback-ui-3` exit0：3/3 UI PASS、0 FAIL/SKIP；候选HEAD678e47b4816b9ae92ab1768b4603159a3af3863b。保存提示isHittable与keepAlways截图F7799171-2C18-4B05-B283-701EB52E4AD4.png视觉证明文字完整位于键盘上方，连续两个独立任务/完成撤销取消/搜索重启原断言通过。About实测该SHA完整复制；Weight保存/最新值/重启再次通过，后台publication未复现（仍有1条invalid-frame，未说零警告）。中文真实Dark编辑/Hub/About及新四状态菜单截图已逐张核实；s3-ui-5只有浅色证据的纠正保留。

最终1000任务/1100事件有界性能：Clock0.095734467 / 0.095000526 / 0.096871520秒、physical_peak61393.488 / 61377.104 / 61377.104kB，独立查询/统计/完整性断言全保留，指标来自最终xcresult。完整Unit297/297而不是累加多轮PASS；集中22项首轮21/22不重标全绿，唯一失败经6项与3项补验闭合。

3项补验实际命令：
```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-review-evidence/s4-visible-feedback-ui-3.xcresult -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testTodoQuickContinuousInputCompletionStatisticsSearchAndRestart -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testAboutContainsRealCommitAndCopiesFullSHAIntoTodoInput -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testWeightEntryIsAccessiblePersistsAndShowsLatestValue > /tmp/pgos-review-evidence/s4-visible-feedback-ui-3.log 2>&1
```

最终完整diff再次自查：模型/旧节点与合法旧包、转换身份/来源/createdAt/事件链/重复重试/回滚、相对日/后继覆盖/历史、通知延迟/权限/容量/旧请求类别、raw原字节恢复/正常写入隔离、统一状态查询/四统计、双语/可访问性、五Tab及原核心全部在批准边界。静态audit=PASS：V1–V10前缀字节相同，615条原catalog值不变、14条en/zh新增；project仅4行fixture资源引用，版本/签名/AppGroup无变化；原V10/V7/V8 fixture无diff。没有扩大Foundation、云/依赖/AI/RRULE/额外Tab范围。

普通 `git push origin codex/todo-v1-personal-actions` exit0，4625602→678e47b，local/upstream均678e47b4816b9ae92ab1768b4603159a3af3863b，原Draft PR #8/base保留；随后仅本交接文档commit与普通push同分支，不另建PR。最终仓库HEAD以PR head为准；最终文档SHA与真实Debug/Release产物核对日志为s4-handoff-debug.log、s4-handoff-release.log、s4-handoff-bundles.json。

最终文档HEAD产物命令（每项退出码与bundle结果以实际日志为准）：
```sh
xcodebuild build -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pgos-todo-derived CODE_SIGNING_ALLOWED=NO > /tmp/pgos-review-evidence/s4-handoff-debug.log 2>&1
xcodebuild build -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pgos-review-release-derived CODE_SIGNING_ALLOWED=NO > /tmp/pgos-review-evidence/s4-handoff-release.log 2>&1
```

最终普通push后只读核查git local/upstream/远端与PR head、OPEN Draft、base、clean，以及workflows/check-runs/statuses。无workflows的远端独立CI为NOT_RUN，aggregate pending不表示有CI运行；实际Xcode Cloud/Archive/TestFlight未触发。Owner私人Build12覆盖、签名/AppGroup、真机通知/设置/旅行/飞行模式、VoiceOver及隔离raw故障复现见验收增量清单，全部NOT_RUN/OWNER_DEVICE_GATE；未触碰、删除或恢复Owner私人数据库。未关闭运行警告和已保存旧候选错误期次不静默修复的策略明确交给独立Review。

**READY_FOR_INDEPENDENT_REVIEW**。本轮S0→S4停止，下一边界仅原Draft PR #8独立Review与Owner设备门禁，不自行merge/tag/改号/发布。


## 最后一轮限定P1数据保全 — 2026-10-10

基线8be670cd7375c0c7f0352d7749bf8a7ff3114767；实现/最终验证候选70f37908dc87b00afe7b71025568b7ef8b1143ac。只关闭启动全库copy依赖和临时UUID恢复快照生命周期，不新增Todo功能。权威S0→S3实际commands/counts/首次失败、低空间image与WAL/PASSIVE checkpoint/raw ZIP正负证据及明确创建/复用/导出/清理/失败策略见 [本轮记录](TODO_P1_DATA_PRESERVATION.md)。

最终完整Unit305/305、固定候选启动UI2/2与此前Build12/集成6/6 PASS；均0SKIP、runtimeWarnings=[]，一次完整门禁，没有按阶段重复全量。真实Debug/unsignedRelease App/唯一appex1.0(7)，schema V11.1/backupv7不变。重要副本不因ZIP/分享完成自动删除；不同故障长期保留空间代价与真机/CI未运行明确列出。普通push原分支更新原Draft PR #8，停READY_FOR_INDEPENDENT_REVIEW；不merge/tag/改号/Archive/TestFlight，不清私人库。
