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

## B1 体重统计与有界历史（进行中）

未增加 Schema/持久字段。WeightReviewBuilder 冻结 now、当前公历时区及截至日，枚举时排除未来/截止后测量；仅保留每日 sum/count、原始最新两条和派生窗口。7/30天和日历3月/1年分别取 endExclusive 回溯；区间均值对有记录日等权；累计覆盖/跨度/当前截至昨天与最长连续段取全历史。坐标包含开启参考线，缺口分段，原始极端合法值保留。四均值有各自文字/颜色/虚线与样本日/次。

WeightReviewReader 是 detached ModelActor 的只读生产读取，SwiftData enumerate batchSize256；页面不再 @Query 全量历史并在每次渲染排序。主页面最近5条，完整历史日期/月选择并以最多50条分页取原始测量；快速编辑器的前次值只读1条。图点/日期选择独立于趋势/均值截至日，有清除选择；保存/改日期/删除/返回/日期切换重读，任务取消不发表旧快照。原 WeightRecord recordedAt/身份和原保存服务不改。Today 实际数值 Text 继续保留原 accessibilityIdentifier。

- `compile-b1`：同 A 构建前缀，resultBundlePath=`/tmp/pgos-usage-remediation-evidence/compile-b1.xcresult`，exit0。`affected-b1`：同串行 test-without-building 前缀，selector `PersonalGrowthOSTests/WeightFoundationTests`，**12PASS0FAIL0SKIP / exit0**，含原读写/旧库与五个新增日期/均值/坐标/覆盖/时区反例。
- `compile-b2` exit0；此前一次翻译插入 Python 输入报 Non-UTF-8 SyntaxError，未写入资源；随后修正插入35键，实际新中文资源直到 b3 才编译。没有将该脚本失败冒称产品构建错误或隐藏。
- `affected-b2`：同 test 前缀与整个 WeightFoundationTests，**13PASS0FAIL0SKIP / exit0**。增加真实磁盘五年 10,000 条/1,826 日期的生产 reader：快照 **0.054145125秒**，最近查询5条，50+50两页不重叠；改到更早日期后1,827日，再删除回到1,826日/9,999条。附件 `affected-b2-attachments/4C429159-927D-4162-9399-215710A639AA.txt`，已读取。这里只测该次聚合与分页，不是整页性能改善百分比；未用 Instruments，未测RSS/峰值内存。
- `ui-b1`：同 test 前缀，selector `PersonalGrowthOSUITests/AppLaunchSmokeTests/testWeightEntryIsAccessiblePersistsAndShowsLatestValue`，**1PASS0FAIL / exit0**。Today进入→空态→快速录入72.5→最新值→冷启动Today值保留。实际用 b2 英文包，后加中文资源不作为该轮证据。
- `compile-b3` exit0，包含新双语资源和仅 DEBUG+uiTesting+reset 可用的确定性四条 Weight fixture（昨日70/72、今天75、60天前65）。`ui-b2` selector `PersonalGrowthOSUITests/AppLaunchSmokeTests/testUsageWeightDailyMeansRangesAndDateHistoryEditDeleteRefresh`，**0PASS1FAIL / exit65**。已走过75.0最新、7天73.0均值/2日3次、开启年均值、完整历史和昨日按钮；失败在找原始记录行。失败 hierarchy 明确日期 Oct17、2 measurements，而 Selected day 后无明细/空态/加载子树。测试终止后的simctl图只有主屏，不当作失败页证据。
- 最小修复 `compile-b4` exit0：原 Group.task 会转发给条件子行，loading切换会取消自己的读取；改为稳定“Newest first”行承载任务，同查询重现复用已加载页，换查询隐藏旧行。生产查询、原始断言和编辑/删除步骤不变。`ui-b3` 同原 selector 复验中，结果待收集。

本阶段工作树精确差异/文件哈希见 `candidate-b4-source.json` / `candidate-b4.patch`，HEAD为A1提交，不冒称当前已是干净最终构建。B1尚未独立审查，BMI、成长回顾聚合、时间投入历史/缓存及C/D仍未完成。需继续核查中文大字/空选日/图点/未来记录可纠错路径与日期前台更新。

### B1 原生失败闭环与后续补验

- `ui-b3`：**0PASS1FAIL / exit65**；Group任务修复后，原始昨日两条和编辑保存73kg已可见，失败转到完整历史的删除确认。确认曾挂在已离开的趋势页，改由可见完整历史页持有删除ID、确认并用独立上下文执行原服务删除，保留单独错误态。
- `compile-b5` exit0；`ui-b4` **0PASS1FAIL / exit65**：删除确认和删除后70kg断言已通过，最后寻找均值失败。原始 hierarchy 显示已回到趋势顶部（Latest Weight、range可见），测试却向下拖动页面直到顶部仍继续同方向；改为从顶部向上滑动正常阅读下方均值，最终值断言不变。事后simctl图仍为测试退出后主屏，不能冒称失败现场截图。
- `compile-b6` exit0：也补全前/后日按钮的44pt路径、无记录日不跳转与恢复原日断言；前台/午夜/时区刷新快照接线。`ui-b5` **1PASS0FAIL0SKIP / exit0**：75最新→7天均值73/2日3次→开启年均值→按日2条→编辑72为73→明确删除→剩70→前日无记录且没有原始行→回原日70→返回均值72.5/2日2次。保留1条 frame warning。
- `compile-b7` exit0：图横轴显式使用所选自然日期窗口，避免暗中只拉伸记录日区间；文字使用正文对比，颜色/虚线由线段图例提供。`ui-b6` 同原selector **1PASS0FAIL0SKIP / exit0**，仍1条frame warning。已看实际截图 `ui-b6-attachments/C6EEB20B-F4A9-4CBF-BC62-23E2050E7D93.png`，72.5/2日2次及3个月/1年70/3日3次、四种图例可读。
- 原生log明确 warning 出现在编辑页 t≈26.8s 点击 weight-editor-value 打开键盘，而不是画图或保存。`weight-frame-events.json` 也保留 SwiftUICore runtime issue时间/回溯；xcresult原始issue无源码url，console log不可用。没有将这些新直接关联警告归到旧历史。
- `compile-b8` exit0：收键盘动作移到导航栏（44pt并保留Done语义），不再使用导致该原生接缝告警的 `.keyboard` 工具栏；仍须按后续运行结果证明，不能仅由推断宣称关闭。
- 自查发现午夜DST自然日缺口的真实算法边界：从01:00的startOfDay直接加一天会保留01:00，导致历史截至日多包含次日一小时、前后日可能误断段。`compile-b9` exit0：所有窗口端点/明细次日边界再取startOfDay，连续段按下一民用日比较，跨度用Gregorian民用日ordinal差。新增巴西2018-11-04午夜跳时反例：Nov5 00:30不能落入Nov4，三日仍连续/跨度3，7日起点零时。`affected-b3` 同前缀，selectors=整个WeightFoundationTests+上述两项Weight原生UI，结果待收集。

各轮产品/测试仍为A1后的未提交B工作树；并未进行本Goal最终全量/Release/实包或独立review。后续B1提交前记最终结果和源码哈希。所有失败保留，不按通过的断言数将失败方法重标为PASS。

### B1 内部检查点结果

`affected-b3` **exit0 / 16PASS0FAIL0SKIP = 14 Unit + 2 UI，runtimeWarnings=[]**。同一实际运行包含午夜DST/窗口/均值/覆盖/磁盘/分页/旧Weight持久化回归，及快速新建保存冷启动和完整日期历史编辑/确认删除/无记录日/返回72.5kg两个原生UI。该路径下键盘toolbar调整后不再出现frame警告；仅关闭此有配对证据的Weight接缝，不宣称其他页面3条历史/本轮warning全部解决。

最新生产磁盘reader样本 **0.054404458秒 / 10,000条 / 1,826日**，附件 `affected-b3-attachments/1F3A113A-50FE-4379-BB6C-2CE5EFD30A81.txt` 已读；不是全App性能百分比，未测RSS/峰值或Instruments。正常最终截图 `92E94C30-6953-4B2A-8066-78E22EE86185.png` 在同目录。

精确产品/测试工作差异与哈希：`candidate-b9-product.patch`、`candidate-b9-source.json`，随后提交B1；当前没有新Schema/备份/版本/签名改动。当前B1是内部检查点，不是整个B阶段或Goal完成。

**接续顺序**：完成成长回顾日聚合及具体原始事实下钻（不要只跳Habit首页）；时间投入同一事实快照统计复用、明确自然日图窗/月份及有限明细/失败态；BMI与星期重复/本次提醒覆盖/AlarmKit联合设计必要追加模型及v11备份后，真实迁移/恢复/空库/失败回滚一次完成。过期提醒不能放宽旧系列±366校验。之后才做D集中全量/组合原生/UI双语大字/实包/独立只读review与push/唯一Draft PR。未完成项保留NOT_RUN，继续自主推进，无阶段批准停点。

提示：时间投入原R2/R3所见键盘frame warning仍须按接缝查因，不能借本次Weight零warning抹去。主工作区2026-10-18尾检仍为原三项未知dirty，未碰私人库/真实手机或旧PR。固定GOAL_SHA相对原主工作区Foundation追加的ImportantDay/Sleep/TimeInvestment段已另行核读，版本职责/身份与独立事实约束保持。

B1 后续UI核查明确保留：历史截至日期无样本时，空态应说明截至所选日期，不能误称全库为空；新加入的当前时区/前台/午夜刷新、图点选择、中文最大字号与多年份实际页面仍在D组合验收。当前“历史期间无样本”标题细节与完整历史可选日期范围需随该路径核验收口，未标全部W5通过。
