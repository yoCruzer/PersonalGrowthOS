# 使用反馈统一整改执行记录

状态：**IN_PROGRESS**。本文件记录实际工作，不替代固定 1.0 规格，不代表集中门禁或设备通过。

## 固定输入与隔离

- BASE `5a70f0110b151f8a45ac7c33d3f443823b1cff24`，GOAL_SHA `68373d4edf10cff8ca3e212b9ff10a28e6da9c73`。
- `git merge-base --is-ancestor BASE GOAL_SHA` exit 0。`git diff --name-status BASE GOAL_SHA` 恰好七份 Markdown：三份 USAGE 规格与 INDEX、V1_SCOPE、CURRENT_STATE、CURRENT_TASK；无产品/工程/测试改动。
- 从 GOAL_SHA 创建 `codex/usage-remediation-20261017`，独立 worktree `/private/tmp/PersonalGrowthOS-usage-remediation-20261017`。没有同名现存任务工作。
- `git fetch origin plan/usage-remediation-20261017-goal codex/time-investment-v1` 后远端规划为 GOAL_SHA，时间投入分支仍为 BASE；新 PR base 固定 `codex/time-investment-v1`。
- 启动只读 `gh pr list --state all --json number,headRefName,baseRefName,isDraft,state,headRefOid,url`：旧 #1–#12 均 OPEN Draft；#12 head=BASE/base=codex/sleep-routine-v1；没有整改 PR。未改旧 PR。
- 原工作区 `codex/todo-v1-personal-actions` / d72c016 保留三项未知 dirty：project.pbxproj、Localizable.xcstrings、xcshareddata/xcodecloud/。无 stash/reset/restore/clean。
- 已按 bootstrap 读取 Foundation、Contract、Current，全文读取固定 GOAL_SHA 三份规格。ROADMAP 不存在。

## 影响矩阵与实施安排

| 范围 | 实际接点及风险 | 验证策略 |
| --- | --- | --- |
| A：统一行 | AppShell、Growth/HabitViews、SleepToday、ImportantDayRow、InvestmentToday | 少量共用图标/文字容器；默认 List 总行高与大字实际 UI；独立 44pt 控件；不改事实事务 |
| A：清单/提示 | TodoEditor、既有 List service、TodoReminderFeedback | 草稿仍由原编辑器持有；嵌套选择/新建/管理不保存待办；真实编辑器往返验证 |
| A/C：提醒 | TodoReminderCoordinator、TodoTaskService、TodoTransfer | 现行 edit 对重复提醒做 ±366 天锚点校验；长期过期本次覆盖须与 C 的新持久意图一起做，不删除校验或重写系列 |
| B：体重 | WeightRecord 只有 recordedAt；无旧原始时区 | 冻结 now/当前公历时区快照，等权日均值；范围/全历史覆盖复用；有限明细与可访问日期选择；纯算法反例及真实视图 |
| B：成长回顾 | QuietWinsReader/Engine/Views、Habit LocalDay 与历史计划 | 只聚合来源事实，不去重真实多次或改变成果口径；按日下钻到原始记录 |
| B：时间投入 | Workspace.refresh 全量读取；活动卡逐行 contributions；History suffix(30) | 同一事实快照复用贡献与活动总量，显式自然日窗口和有限详情；失败态不伪零；F1/R1–R3生产链定向回归 |
| B/C：新持久字段 | 当前 V14/v10；历史模型共享且不可回写 | 优先追加独立模型承载星期集合、每实例提醒覆盖/渠道与协调账本、可选 BMI 设置；统一必要新版本、严格传输、空库与回滚一起完成，真实磁盘升级后再称通过 |
| C：系统闹钟 | 既有唯一普通通知协调边界共用 Todo/Sleep/ImportantDays，daily/weekly 保留 | AlarmKit 仅 iOS26+ 适配器，单次当前期次，稳定请求身份与修订；取消确认/旧回调/系统停止/恢复测试；实际递送列 Owner Gate |
| D：组合收口 | 完整 Unit、关键 UI、旧库/新包、Debug/unsigned generic Release、实包来源 | 功能收敛后一次集中执行；独立只读 reviewer 固定提交和原始证据；修复后按真实依赖补验，不逐阶段旧全量 |

## 环境与证据

- 本机 macOS 27.0.1 / 26A434，Xcode 27.1 / 27A9275；`xcodebuild -checkFirstLaunchStatus` exit 0。
- 最初受限沙箱 `git fetch` 不能写 .git/FETCH_HEAD，默认 gh 网络失败、simctl 无权访问服务；经授权执行同项 fetch/gh/只读 simctl 后均正常。不是产品测试失败，没有修复系统配置。
- 专用证据根 `/tmp/pgos-usage-remediation-evidence`，DerivedData `/tmp/pgos-usage-remediation-derived`。后续每轮保留独立 log/xcresult，原失败不覆盖。
- 不在启动重跑旧完整测试。旧时间投入 F1 核心/磁盘/ZIP/UI、历史 FAIL/SKIP 只作影响分析，不能冒称本轮通过。

## 当前实施

A 已开始：共用 ModuleEntryRow、Growth 带口径的只读统计和读取失败重试、Today 图标/文字对齐、独立体重动作、清单选择中新建/管理、知道了仅收起反馈、时间投入真实投影状态/收起与草稿文案/累计自然单位。未新增持久模型；过期提醒覆盖将在 A/C 联合接缝完成。B/C/D 尚未完成，全部验收待真实证据。

### 原生命令（阶段内）

1. `xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -sdk iphonesimulator -arch arm64 -derivedDataPath /tmp/pgos-usage-remediation-derived -resultBundlePath /tmp/pgos-usage-remediation-evidence/compile-a1.xcresult CODE_SIGNING_ALLOWED=NO build-for-testing`，日志 `compile-a1.log`；exit 0 / TEST BUILD SUCCEEDED。构建对象为 GOAL_SHA 后本轮未提交 A 工作树，不是干净最终门禁。

## 未完成与禁止越界

U01–U09 / N1–N6 / Q1–Q3 / W1–W6 / B1–B3 / T1–T8 最终结论均待实现/验收。尚无本轮独立审查、push 或新 Draft PR；不得标 READY。D1–D4 真实设备门禁全部 NOT_RUN，未操作真实手机/私人库，未 merge/force/tag/Archive/TestFlight。

2. 同上 compile 命令，resultBundlePath 分别改 `compile-a2.xcresult`、`compile-a3.xcresult`，两轮 exit 0。a2 添加统计/提醒边界测试与原生清单往返；a3 仅清单顺序关闭、计时 toolbar 投影文案和查看待办翻译。a2 提取提示 `Metadata extraction skipped, no AppIntents.framework dependency found` 保留；不是本轮 AlarmKit 接入通过。
3. `xcodebuild test-without-building -xctestrun /tmp/pgos-usage-remediation-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=42609456-859D-41F8-8977-4B2D85A74082' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-usage-remediation-evidence/affected-a1.xcresult -only-testing:PersonalGrowthOSTests/AppCompositionTests/testGrowthCountsAreReadOnlyAndMatchActiveDaysAndParticipantScopes -only-testing:PersonalGrowthOSTests/TodoReminderTests -only-testing:PersonalGrowthOSTests/InvestmentPersistenceTests/testExternalR2DraftFailuresRetainInputAndAmbiguousCommitCanRetry -only-testing:PersonalGrowthOSTests/InvestmentPersistenceTests/testExternalR3UnconfirmedContinuousEnvelopePreservesSegmentsAcrossSaveReopenAndZIP`：exit 0，**11 PASS / 0 FAIL / 0 SKIP**；同名 log。未运行旧全量。
4. 同 test-without-building 前缀，result=`ui-a1.xcresult`，selectors=`AppLaunchSmokeTests/testUsageEditorListCreationManagementAndCancellationPreserveDraft`、`AppLaunchSmokeTests/testTodoDeniedReminderFeedbackSurvivesEditorDismissalAndOffersSettings`、`InvestmentUITests/testExternalR2FailedCloseKeepsEditorAndRetrySurvivesColdLaunch`、`InvestmentUITests/testExternalR3ChineseDarkAXConfirmationPreservesOrExplicitlyReplacesSegments`（均 PersonalGrowthOSUITests）：exit 65，**3 PASS / 1 FAIL / 0 SKIP**。失败为新建清单后原编辑器 title 不存在（第33行）；同时关闭两层 sheet 改为新建 sheet onDismiss 后关闭选择页；首轮缺少失败截图，不能据字段不存在直接证明导航未返回。R3 20→25、两次取消、保存重开断言通过。xcresult summary **3 条 Invalid frame dimension warning** 原样保留，需后续关联归因，不能借旧 warning 直接免责。日志有 Xcode IDESchemeActionSDKRecord `invalidDigitCount(94232)` 与 debugger 元数据提示，不当作运行全绿无警告。
5. a3 后仅上述失败的清单 UI 同前缀定向复测，result=`ui-a2.xcresult`，结果待收集。首轮失败不覆盖。

专用模拟器由 `xcrun simctl create PGOS-UsageRemediation-20261017 com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro com.apple.CoreSimulator.SimRuntime.iOS-27-0` 创建并启动；没有擦除既有设备。默认受限 `xcresulttool` 无权写其内部 TestReport 临时目录，授权同项只读提取后正常；summary 已核对，only-failures 无匹配附件，不能宣称看过失败截图。后续正常截图在 xcresult 中保留。

6. `ui-a2`：compile-a3 后原清单 selector，仍在 title 存在检查失败，exit65 / 0PASS1FAIL。该时刻没有导航/视口断言，不能将其单独归因到关闭顺序。事后 simctl 截图仅为测试终止后的主屏，不能当作失败页证据。
7. `compile-a4` 同构建前缀 exit0；只增强清单测试：先断言 Add Todo 导航确实回来，保留截图，再正常向上滚动到标题，所有原草稿/列表/保存断言保留。`ui-a3` 同 test 前缀与清单 selector，**exit0 / 1PASS0FAIL0SKIP**（55.107秒）。从真实编辑器的标题/备注/重要/计划日/提醒/每周重复输入出发，新建取消→新建自动选中→管理改名→删除→未分类→保存→查看待办→编辑重开通过。

已读取 `ui-a3-attachments/26A2BB0B-E0CC-4696-A514-E40847BB362B.png`：Add Todo 导航已显示，滚动位置在 Schedule/Repeat，标题实际位于屏幕上方。当前通过证据支持视口原因，不支持先前“未返回”推断；顺序关闭仍作为明确生命周期实现保留。另一截图 `54FFBD30-810E-4B06-9122-66EC9319EE33.png` 保留最终重开输入。**不将 a1/a2 原失败改标全绿**，也不凭此声明 BASE 原实现有此关闭 bug（BASE 原无新增页）。

阶段内源码以 `candidate-a4-source.json` / `candidate-a4.patch` 记录 HEAD+dirty diff 与文件哈希；不是最终 clean product SHA。Unit11 的 xcresult summary runtimeWarnings=[]；UI a1 的3条 frame warning仍需 D 阶段关联核查。

### A1 内部检查点（不是整体完成）

编译与上述受影响验证完成。U01 清单新增路径已有本轮真实通过；U03 保存反馈已有拒绝/查看/仅收起路径，U06/T1 统计有只读/范围 Unit；T3/T8 的 R2/R3 接缝原生通过。U09 混合布局、T2/T4、最终双语/大字组合仍待 D；U04 过期动作与独立本次覆盖随 C 联合完成，不能提前标 A 全部 PASS。继续 B/C/D，无逐阶段确认请求。

AlarmKit 预核查：已读本机 iPhoneSimulator27.1 SDK AlarmKit.swiftinterface，确认 iOS26 availability、fixed(Date)、schedule/cancel/stop、alarms 抛错读取、alarmUpdates/authorizationUpdates 和 LiveActivityIntent 接口。官方网页 JavaScript/markdown 抓取受工具格式限制，仅以 SDK 作当前接口依据；接入和系统验收尚 NOT_RUN。
