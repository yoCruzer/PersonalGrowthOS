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
