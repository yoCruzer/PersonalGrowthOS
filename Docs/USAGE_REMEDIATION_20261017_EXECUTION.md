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

## B2 成长回顾日聚合与精确事实

只改只读聚合/导航，无新持久字段。习惯摘要分别显示不同记录日与真实打卡总次；按保存LocalDay形成稳定日汇总，可展开原始条目，身份不按相同值合并。每条直达该HabitLog的业务日/数量/结果/可选关联Entry；没有精度契约时只写当天记录，不造不同钟点。另设“查看习惯”进入原管理页，避免以习惯首页冒充原事实详情。不新增达标率/今日目标倒算，不把时间投入加入Quiet Wins。来源撤销/删除后原始事实失效，父页重读当前事实，展开状态按card+LocalDay保持。

- `compile-q1` 同前述build-for-testing前缀，exit65：SwiftData #Predicate不能直接用UUID与可选UUID比较；改为准确linkedID集合（nil为空集合，不造替代身份）。`compile-q2/q3/q4/q5/q6/q7/q8` 各exit0。
- `affected-q1` 同串行test前缀，selectors=`PersonalGrowthOSTests/QuietWinsTests`、`PersonalGrowthOSUITests/AppLaunchSmokeTests/testUsageHabitDailyFourAndTwoFactsExpandAndOpenExactOriginal`、`.../testQuietWinsHabitRankingKeepsSurvivingEvidenceAndDeletionInvalidatesIt`：**12 Unit PASS / 2 UI FAIL / 0 SKIP，exit65，runtimeWarnings=[]**。全文件有多个测试类，此selector只跑QuietWinsTests的12项，未冒称ReaderTests另5项已跑。stdout保留unsigned App Group/Widget projection诊断，不称其系统能力通过。
- 初次原生失败为展开后找不到原始条目ID；`ui-q2` 仅同新4+2 selector，0PASS1FAIL/exit65，额外保存实际图/树。已看 `ui-q2-attachments/CCCB7AD2-5386-404C-AE8F-09E03053682B.png` 和 `F853A444-90E2-4E3B-B291-A63604E1C1CB.txt`：原始条目确实显示，DisclosureGroup父ID却覆盖各子NavigationLink ID，不是丢数据。改独立展开按钮和只供定位的UUID后缀ID，不让VoiceOver朗读技术UUID。
- `ui-q3` 两UI仍0PASS2FAIL/exit65；`ui-q4` 单新UI诊断0PASS1FAIL/exit65，原生树显示中心点击后仍Collapsed。plain按钮标签左右分布，中间空白未定义contentShape；在标签内部明确44pt矩形命中区，而不是把测试改为点文字坐标。
- `ui-q5` 两原selector **2PASS0FAIL0SKIP / exit0，runtimeWarnings=[]**。原生按日分别展开4/2条，读取互不相交的原始身份集合且并集6，再进入精确当天记录与Synthetic check-in 1；撤销今天后昨日仍有证据、删除后原来源失效、卡片转为另一有效习惯也通过。用每日4/2身份并集验证6条，符合List有限实现，不要求离屏6条同一时刻全部实例化。原失败不覆盖。
- 真图/层级在 `ui-q5-attachments`：已看原始详情 `DB4DECD1-B2F2-4571-9F5D-925BACE02D1E.png`；还有稳定展开与昨日来源截图、两份实际树。
- q8 只补Query.fetchError与来源失效的区别，按本机公开SDK接口检查并编译；未额外重跑纯Unit或同一成功UI，D集中组合将覆盖最终source。精确差异 `candidate-q8-product.patch` / `candidate-q8-source.json`。没有把q7 UI冒称q8干净实包门禁。

B2内部检查点已收敛，不表示完整B或Goal完成。Q1的4+2/去重边界与Q3保存LocalDay/失效路径有本轮证据；不同历史计划/追踪模式不显示虚假分母，数量只在原事实显示，不把数量当次数。跨时区实际页面、补记/导入/更广关联及双语大字在D集中补足，未改源事实/计划。

远端只读 `git ls-remote --heads origin refs/heads/codex/usage-remediation-20261017 refs/heads/plan/usage-remediation-20261017-goal refs/heads/codex/time-investment-v1`：新整改远端分支不存在；规划仍GOAL_SHA，时间投入仍BASE。尚未push/建PR。

下一步仍在同一Goal：时间投入快照复用/明确7/30自然日与全部预览月份/有界明细/失败态，再完成BMI和C联合持久化与系统渠道，最后D。考虑提醒设计时必须把用户意图、设备本地排程账本和授权分离；取消未确认不新增冲突请求，含糊排程后缺失请求不能冷启动自动重响；停响不完成任务；这是后续实现注意项，不是已完成证据。

## B3 时间投入统计复用与有界日期历史（进行中）

在同一正式事实快照中只拆分一次原时区贡献，按活动缓存累计和稳定原始身份顺序；活动行不再各自全量contributions。没有改计时/检查点、正式写入事务或历史模型。刷新仍用四次新context查询读取参与者/活动/正式事实/操作，事实和当前参与者未变化则复用统计；这不是数据库增量引擎，也没有声称全量读取被完全消除。统计失败明确错误/重试，不再try?默认零；原已消费编辑器清除在更新统计前执行，保留R1。

全部累计继续覆盖全历史，图表默认明确最近30自然日预览、可切指定月份/前后月；7/30日严格同自然日窗口。月份最多31个日汇总，原始正式明细每页20个身份，按这些身份真正查询最多20条完整记录；跨日Session按贡献可从任一日期到同一事实，期间计数仍唯一Session。无记录选日不自动跳其他日期。大字日期输入复用已有自适应DateField；午夜/显著时钟变化更新评价日，不重写原保存时区。

本节同前环境与串行测试前缀，derivedData仍`/tmp/pgos-usage-remediation-derived`，result/log均在`/tmp/pgos-usage-remediation-evidence`，源码是f2d02fa后dirty候选，不是clean门禁：

- `compile-t1`、`compile-t2`：同Debug simulator arm64 build-for-testing命令，均exit0。t2加入跨日/参与者/无记录日/无效事实Unit及五年一万条真实磁盘负载，双语新文案。
- `affected-t1.xcresult`：`-only-testing:PersonalGrowthOSTests/InvestmentFoundationTests -only-testing:PersonalGrowthOSTests/InvestmentPersistenceTests/testUsageFiveYearSnapshotReusesStatisticsAndBoundsRealDiskPageThenRefreshesChanges -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testManualSaveHistoryNilFeelingEditAndDeleteRefreshSameReview`；**31 Unit + 1 UI = 32PASS/0FAIL/0SKIP，exit0**。保留**1条Invalid frame dimension运行warning**，发生在编辑器聚焦时，未改标无警告。全部核心30包含新增快照1，磁盘1；未重跑原磁盘整类或旧全量。
- 磁盘负载实际`USAGE_INVESTMENT_10000_DISK_REFRESH_SECONDS=0.11898493766784668`；1826不同保存业务日、累计600000秒，重复refresh不换统计generation，两页20/20身份不交，实际按ID磁盘查询20条；归档活动历史保留，实际服务编辑后600060/删除后599940及9999条，损坏payload使review=nil/error非空，修复后重试恢复599940。纯Unit另验5/15分钟跨日仍1场、各日同一源ID、当前参与者隔离、未知/无样本日期不伪造记录。未测Instruments/RSS，非性能承诺。
- t2对应`candidate-t2.patch` / `candidate-t2-source.json`。`compile-t3`：编辑器键盘Done改为导航44pt键盘收起按钮（保留可访问Done及失败关闭门禁），增加50自然日+跨日原生合成fixture和月份前后按钮；exit0。
- `ui-t2.xcresult`：三个selector为`InvestmentUITests/testExternalR2FailedCloseKeepsEditorAndRetrySurvivesColdLaunch`、`.../testManualSaveHistoryNilFeelingEditAndDeleteRefreshSameReview`、`.../testUsageHistoryNaturalWindowMonthPagingAndExactCrossDayFact`；**2PASS/1FAIL/0SKIP，exit65，runtimeWarnings=[]**。R2与编辑删除通过，月份测试查找上一月失败。真实录屏`ui-t2-attachments/83A7825F-495E-4B45-9B20-89B17F3872F8.mp4`通过系统AVFoundation取9/11/13秒帧（仅临时诊断脚本有deprecated copyCGImage编译提示，不是App运行warning）；已看`ui-t2-frame-11.png`开关仍关闭，中间点击未切换。改操作实际原生开关区域并断言value=1，没有放宽功能断言。
- `compile-t4` exit0，加入评价日更新与选日16分钟/2场、清选择27分钟/8场断言。`ui-t3`只复测新月份selector，**0PASS/1FAIL/0SKIP，exit65**；开关value=1通过，但先reveal范围文字的上滑使上一月按钮到视口上方，单向向下找再次失败。已看`ui-t3-attachments/18F83E4B-5DF4-4288-873D-BD57C7AB1311.png`，绿色开关、上一月、下一月和10月1→31范围真实存在，不是日期数据丢失。改按页面顺序先定位上一月，再读取范围，保留全部功能断言。原失败/图/树不覆盖。
- `compile-t5` exit0；只读发布四个源数组以保护缓存失效边界，调整上述测试滚动顺序；`candidate-t5.patch` / `candidate-t5-source.json`留底。`ui-t4`同单一新selector正在运行，结果随后追加。

B3尚未最终确认；之后继续BMI与C联合追加持久模型/备份，不能把本小节或模拟器性能当完整Goal/真机门禁。最终完整Unit、迁移ZIP/回滚、集中UI、unsigned Release实包和真正独立审查仍在D。


### B3 收敛结果

`ui-t4` 为0PASS/1FAIL/exit65：月份前后、第二页、7日27分钟8场、选日16分钟2场/清选择已通过，最后原始5分钟仅因查询独立Text失败。真实原生树在log的561/569行明确为合并的`2026-10-17, 0:05:00` / `2026-10-18, 0:15:00`；不是分摊丢失。为原贡献行加稳定日期标识，按该行身份＋值验证，未改期望时长。已看`ui-t4-attachments/CA38E2C4-CD84-4EB7-92D0-2655EEE82CDE.png`月份和`4A200253-9140-4C70-AF3B-2206E0A5FD4A.png`第二页实图。

`compile-t6`同前命令exit0；最终合成fixture补齐每条Session对应同身份的saved Operation，保存后调用实际`InvestmentIntegrity.validate`。此前t1的0.119秒是未配对操作负载，只作阶段诊断，不能冒称最终正式完整性负载。`affected-t2`同串行测试前缀，selectors=`PersonalGrowthOSTests/InvestmentPersistenceTests/testUsageFiveYearSnapshotReusesStatisticsAndBoundsRealDiskPageThenRefreshesChanges`及`PersonalGrowthOSUITests/InvestmentUITests/testUsageHistoryNaturalWindowMonthPagingAndExactCrossDayFact`，**2PASS/0FAIL/0SKIP、exit0、runtimeWarnings=[]**。完整1万Session＋1万Operation磁盘首次refresh实际**0.22427403926849365秒**，测试2.558秒；原生UI103.234秒，包括完整范围/月份/第二页/选日与清选择/原始5+15分钟下钻。`affected-t2-summary.json`与附件保持，源码精确记录`candidate-t6-product.patch` / `candidate-t6-source.json`。不是同轮重跑全核心，也不将分轮计数拼成一次全量绿。

下一步B BMI与C共同追加需要的设置/规则/用户提醒意图及独立设备账本，必要V15/v11将真实迁移/快照/旧包缺省/严格新包/空库恢复/失败回滚一起验；尚未改这些版本。预查官方来源：NHC2024指导原则及核心知识PDF搜索缓存、WHO NLiS、CDC BMI解释已核对；NHC直接open的412/timeout保留，不宣称该抓取成功。AlarmKit官方示例与WWDC25目前搜索可读，确认用途说明和实际授权需求；本机27.1公开SDK可编译接口仍是实现依据。系统集成/物理响铃仍未实现/NOT_RUN。

## B4/C 联合持久化与 BMI（进行中）

从 clean4ec5d18 继续，C 尚未提交。追加V15四类元数据：系列ISO星期/渠道、本次提醒意图、设备请求恢复账本、可选BMI设置。统一备份v11只保全三组用户设置；设备账本不入包，不复制授权或已排程结论。新数组进snapshot/materialize/发布前校验/空库/回滚；v11必须有数组，旧版本不能夹带。历史模型布局保持。

compile-c1 exit65：误把工作context的Usage校验/插入标MainActor，与原非隔离导入链冲突；按既有context归属修正。compile-c2 exit65：脚本重复串接取消检查导致三处语法错误；修正。compile-c3 exit0。旧包夹具只剥离空的新字段，不剥离非空新设置；R1明确重建真正v10包，两个“当前导出版本”断言随当前改11，历史固定版本不改。candidate-c3.patch/source.json留底。

`affected-c1`同本轮串行test前缀，五个PersonalGrowthOSTests selector：InvestmentPersistenceTests/testUsageV14StartupMigrationKeepsLatestProtectionAndAddsNoDefaultSettings、testUsageV11ActualZIPSettingsRoundTripRollbackEmptyGuardAndDeviceJournalExclusion、testExternalR1LegacyDiskStartupAndLegacyZIPRestoreEraseOnlyConsumedContent；WeightFoundationTests/testUsageBMIUnroundedBoundariesInvalidInputsAndExplicitRoundingHint；ImportExportRecoveryTests/testLegacyV1ThroughV6PackagesImportAndFrozenBuild12V6RestoresOriginalFacts。5PASS/0FAIL/0SKIP、exit0、runtimeWarnings=[]。真实字面V14磁盘的最新保护副本不同于更早副本，实际AppContainer升级保留最新Entry/Todo/Weight/Sleep/匹配Session+Operation，无新默认设置，保护副本仍按V14只读打开，冷重开一致。真实v11 ZIP保全175.5cm/WHO、日重复系列闹钟渠道/实例意图，设备accepted账本不入包/恢复；beforeSave失败后库空、重试往返一致，仅设置非空目标被拒，原值保留。BMI未舍入阈值及邻值、非有限/零/范围和舍入跨界提示配对成立。

BMI只由显式保存落盘，独立context不提交其他Entry草稿。清除身高后WHO参照可保留；中国默认且无身高时移除可选行。主页面使用真实测量日期，历史说明使用当前身高，给互斥成人参照范围与NHC2024/WHO/CDC来源。输入50–300cm是输入保护范围，不是成人身高标准。纯浏览不落默认值。NHC直接open的412/timeout保留，后经官方PDF搜索缓存核对；WHO/CDC正文可读，不宣称失败抓取成功。

compile-c4 exit65：新UI局部reveal误传第二参数，修正；compile-c5 exit0并补中英文。`affected-c2`的2 BMI Unit＋原体重均值/历史编辑删除UI通过，新BMI入口UI失败，整体3PASS/1FAIL/exit65、runtimeWarnings=[]。实际层级`affected-c2-attachments/056907CA-5A72-4564-A05E-0F1C84A6E7B1.txt`仍停在Weight，BMI编辑按钮存在但未呈现编辑页；改为原生NavigationLink详情，增加导航断言。compile-c6 exit0，ui-c3只复测BMI全路径1PASS/0FAIL/0SKIP、exit0、runtimeWarnings=[]：0身高失败保留输入、175cm/24.5中国超重参照、WHO常用正常参照、冷启动保留、清身高保留WHO均成立。截图ui-c3-attachments/7906A5CE-A2F5-4CC4-8C17-769D057CFF66.png。candidate-c5/c6各有patch/source.json，原失败保留。

星期规则接线中：ISO稳定身份，当前期次保留显式日期，后续只生成选定星期的第一个未来期次；计划/截止按原锚点民用日差保留，不分别重套星期集合。compile-c7 exit0；affected-c3九项TodoFoundationTests（两新UsageWeekdayPolicy/UsageCustomWeekdayService，原RecurrenceCompleteRetryUndoSkipAndStop、ReviewReminderKeepsOneDayLead、ReminderLeadMonthlyTenthLeapYearDSTAndTravel、FutureEditRollbackAndWithdrawnReuse、ConversionRejects、RepeatingReminderKeepsChosenLocalDayAndClock、TaskPersistsAcrossReopen）9PASS/0FAIL/0SKIP、exit0。覆盖实际自选星期、来源/截止偏移、只一未来期次、跳过/停止、空集合拒绝及相邻月末/闰年/DST/时区/撤销身份。UI选择/摘要/下次日期代码刚接上，尚未编译/原生验证。candidate-c7留底是该UI接线之前。

仍需严格新包缺失/旧版本夹带的真实ZIP反例、新规则ZIP往返、提醒本次覆盖和真实AlarmKit协调/取消/迟到回调/授权/nativeAPI验证。模型或DTO通过不代表N1–N6功能完成；设备与最终组合门禁、独立review/PR仍未完成。


### C 后续生命周期与本次提醒收敛（2026-10-18）

追加 V15/v11 只承载新用户设置与设备本地所有权；V1–V14 模型字段未改。Todo 的提醒意图与任务同事务提交，系统调用前先持久 ready→prepared 账本，再以真实 pending 身份确认 accepted。设备账本不进备份。prepared 在进程中断后没有系统存在证明时不自动重排；旧取消未确认时保留身份并阻挡同任务/同系列后继，显式新意图才再次设置。权限撤销无静默普通通知降级。普通通知新意图仍参与原 Todo/ImportantDays/Sleep 共享公平额度，日/周提醒及外来请求保留。

本次重设使用独立 ModelContext 写入，保留长期过期系列原计划/截止/锚点/后续模板，保留普通编辑 ±366 限制；expectedRevision 防止旧页面覆盖新设置。不提交另一编辑器的未保存 Entry。详情和保存反馈共用真实当前状态/重新设定/取消核查；屏幕跨过提醒时刻后动作重新判断。Stop Intent 只调用 AlarmManager.stop；Open Intent 调用精确任务路由，Record 草稿继续挂载，已有 modal 时排队可见，用户自行结束编辑后再打开。

- compile-c17 PASS；affected-c8 实际15项为11PASS/4FAIL、6断言，原因是原模型缓存修订导致状态停留 checking；没有降低预期。compile-c18 因 catch error 遮蔽 UI 状态变量编译失败，c19/c20 修复后 PASS。affected-c9=15 Unit＋过期/拒绝反馈2 UI，共17PASS；包含2020系列在2026重设本次10分钟、冷启动仍旧计划和截止。各次原始日志保留。
- compile-c21 PASS；affected-c10 的 Todo14、Sleep4、ImportantDays7 共25项为24PASS/1FAIL，ImportantDay 同轮释放名额3断言失败。取消原生旧请求移到共享额度计算之前，避免直到下次刷新才补位。c22之前脚本语法错误，没有落地修复，该轮编译是未改源码；c23才实际修复。c24因新增测试使用[]而非空字典[:]编译失败；c25修正 PASS。
- affected-c11：同串行 test-without-building 前缀，selectors 整类 TodoReminderTests/SleepReminderTests/ImportantDayReminderTests，**31PASS0FAIL0SKIP、runtimeWarnings=[]**。新增6项覆盖调用前写盘失败/独立草稿、系统读取失败且仍存在/已停止、旧成功与旧transport失败撞上新渠道、权限等待期间完成、同系列取消失败阻挡后继、CancellationError中断保留prepared且不继续增加请求。旧14项与相邻11项一并通过。
- compile-c26/c27/c28 PASS。ui-c6 实际原生授权正向测试0PASS1FAIL；卸载重装仅本轮专用模拟器合成App后 affected-c12=3PASS1FAIL（DST/旧修订/Record Intent通过，原生授权仍失败），不是未运行。实际 App Info.plist 含 NSAlarmKitUsageDescription；系统日志 native-alarm-system-c12.log 的 mobiletimerd 明确记录两次 Requesting permission→Denial，无授权弹窗。未伪造权限/注入系统队列或改系统服务；不据此断言真机或签名包一定失败。
- affected-c13（c28）：**4PASS0FAIL1SKIP，runtimeWarnings=[]**。3 Unit为实际v11 ZIP（生产创建Alarm渠道和本次覆盖→导出→失败回滚→空库恢复→重开→精确相等，设备账本0）、DST自然日/缺时顺延/重复第一次/跨年、旧修订拒绝且不提交外部草稿。1 UI为生产 OpenTodoAlarmIntent.perform→Record原文保留→已有Todo编辑器时排队、标题输入保留→主动取消后打开指定旧任务→Record仍原文。此证据不是系统闹钟按钮的实际触发。原生授权 UI 确认真实拒绝、Settings动作和已保存任务可达后SKIP正向schedule/cold/cancel段；**正向原生队列接受/取消/响铃/Stop/Open系统触发仍NOT_RUN**，绝非AlarmKit全组PASS。首两次失败保留。
- BMI界值/持久设置及星期证据见前文；c29仅新增混合入口和中文Dark最大字号代表UI，待运行。Localizable只追加78键，既有所有键/值语义逐一相等，未重排历史资源；新 InfoPlist资源双语。c29源码清单及新文件副本在candidate-c29-source.json / patch / untracked副本，不是假称clean提交。

每次 compile 均复用本文原始 xcodebuild build-for-testing 前缀，仅 result/log 改 compile-cXX；每次 affected/UI 同串行xctestrun/专用simulator前缀，仅改相应上述selectors和xcresult/log。初始/最终及每轮warning原样保留。现阶段尚未完整Unit/组合UI/Release/实包与独立实现审查，不标READY；无push/新PR。

Apple原生行为依据：[requestAuthorization](https://developer.apple.com/documentation/alarmkit/alarmmanager/requestauthorization%28%29)、[WWDC25 AlarmKit](https://developer.apple.com/videos/play/wwdc2025/230/)，实际接口以本机27.1 SDK交叉核对。BMI成人来源沿页面NHC2024/WHO/CDC，不声称2026最新医疗指南。


## D 集中验收与独立审查进行中

实现检查点 `266c9cab7b3745fd8d217793e7acf7a9cfbbb715`，32文件/3491增100删。真正独立只读 reviewer `/root/usage_remediation_independent_review` 使用 fork_turns=none，重新从固定规格和BASE→实现差异开始，不编辑、不占Xcode队列。首轮确认三项P2：只改标题时accepted系统请求保留旧文字；weekday UI按地区而非固定周一开始；V14旧通知取消失败未阻挡新账本后继。无P0/P1，最终闭环待修复实测和D门禁，不以初审等于完成。

- `compile-c29` 因新UI测试for循环使用$0编译失败，c30改显式index后PASS。`ui-d1`=1PASS1FAIL、runtimeWarnings=[]：混合Today/Growth默认及最大字号遍历通过；中文最大字号BMI175cm→24.5通过，重复菜单第8项在滚动区外，测试未滚动菜单就失败；按实际菜单内已可见周末项滚动再选，不降低原保存/触达断言。
- **截图外观校正**：ui-d1和更早仅凭`-AppleInterfaceStyle Dark`标注的图实际为Light。已查看ui-d1 BMI/Growth实际像素，不能称其Dark通过。后续外部driver只切本轮专用Simulator的`simctl ui ... appearance dark/light`，实际结果保留AppearanceDriver日志并结束恢复原外观；mixed UI在两轮启动前输出明确标记。新的真Dark图待查看。不是更改真机或系统私有授权。
- `compile-d1/d2/d3`均PASS。review-d1-red名字只是反例轮：保留原main对象/不手工refresh，生产独立重设后同context完成/取消，真实磁盘重开/事件[0,1,2]/revision2/新提醒/完整性，**1PASS**；未复现缓存损坏，reviewer撤回该假设。
- review-d2-red=1个方法FAIL、2断言：notification和alarm只改标题都留下Before。review-d3-red=1PASS(两个渠道停止后标题改动不重排的对照)、1FAIL(legacy取消未确认仍排后继)，3断言。原失败保留。
- 限定修复不盲目更新用户generation：在本任务尚未发布的新V15设备账本保存requestedTitle，真正native存在且未来时才确认取消并替换；不存在/retired维持stopped；排程异步回来时比较最新标题，旧回调清理所有权。取消未确认阻挡，恢复确认后只有一个新请求。该设备字段不进ZIP。V1–V14定义未改。legacy旧ID实际仍在confirmed集合时扩展同系列阻挡，下一轮确认旧ID消失再允许后继。星期UI固定ISO1...7，名称仍本地化。
- `compile-d4` PASS；`review-d4-green`=TodoReminder23＋Sleep4＋ImportantDays7＋真实磁盘反例1，**35PASS0FAIL0SKIP**（summary待提取）。又补原生读取/排程暂停期间改标题，以及文字替换取消失败→恢复成对测试，尚未运行；最终集中Unit会包含。

外部原生UI driver保存`/tmp/pgos-usage-remediation-evidence/run_usage_ui.py`，调用`python3 .../run_usage_ui.py RUN_NAME selector...`，底层仍本文串行test-without-building和同一专用Simulator；记录外观切换exit，finally恢复原外观。最终门禁尚未执行，未push/新PR。


### 集中 Unit 首轮实际结果与范围内测试夹具修正

`final-debug1`在clean `c909821b498492e133c726fd4e36f2191920e026` build-for-testing PASS，实际App BuildProvenance=同完整SHA/localGit/Dirty=false/Tag空。`final-unit1`同原test前缀、仅`-only-testing:PersonalGrowthOSTests`，实际 **517项：512PASS/4FAIL/1SKIP、runtimeWarnings=[]，exit65**。1SKIP为既有独立32MB HFS+低空间项目，不填满主卷。35秒。所有新标题并发/取消负例、各版升级/重开、F1/R1–R3及其余通过原始证据在xcresult/log；没有把首轮改标全绿。

4失败均在旧测试假设/旧包构造：FullRoundTrip和LegacyV1的手工expectedCounts缺新v11三项0值；TodoV7RoundTrip误期待新设备请求仍为旧固定taskID而非本轮设备UUID；QuietWinsReader旧v7 wire从当前编码构造时未去除三项新空数组，被严格原v7校验正确拒绝。只修测试夹具：补精确三个0键；断言单个native请求的taskID/title/fireAt和实际accepted设备账本UUID一致；构造旧v7时仅移除已经断言为空的新数组，不放松生产兼容校验。产品代码保持c909821不变。下一轮只跑受影响完整ImportExportRecoveryTests及QuietWinsReaderTests，并保存全部其他产品/测试blob相等证明，不重复完整517。

首轮Unit Host默认根在专用模拟器保留早期本任务未发布V15合成库，新增title字段后启动有unknown model version诊断；没有私人数据，该诊断不在测试夹具路径。后续仅卸载本轮专用Simulator的合成App重新安装，保留原日志，不修改历史schema/原工作区/其他Simulator。

### D 第二轮修复与真实 UI 证据（仍进行中）

`50e9cfa190637feb022569ff793a9f360032b781`仅修两份测试夹具和三份交接文档；79个生产文件与c909完全相同。`final-unit-fix1`受影响完整ImportExportRecoveryTests+QuietWinsReaderTests **60PASS0FAIL0SKIP / exit0、runtimeWarnings=[]**。`full-unit-reuse-proof.json`保留blob对照，原517首轮仍512/4/1，不冒称重新全绿。`final-debug2` clean50e9 build-for-testing PASS；Debug三实包身份/1.0(7)/minOS17、App完整SHA/localGit/Dirty=false/Tag空和AlarmKit弱链接核对在`debug-bundle-proof-50e9.json`、`debug-mach-o-50e9.txt`。

实际外观driver的`final-ui1` **27项=21PASS5FAIL1SKIP / exit65**。原生权限请求到mobiletimerd后真实拒绝，正向AlarmKit例SKIP；并非模拟授权。中文BMI最大AX的175cm/24.5截图为实际黑色外观。五FAIL：中文重复弹出菜单第8项在裁剪滚动区外；清单行中间空白点击未打开；两项计时例“Confirm later”标签命中被sheet遮盖的底层按钮；public share进入扩展后无法读取，未获quote。原视频/树/截图保留。没有将成功断言或测试驱动问题改标通过。

独立只读reviewer继续发现两项P2：体重所选日的旧时区午夜在切时区后成为新时区09:00，可能漏当天早间事实；Today once/day习惯最大AX将右侧状态挤成竖排。限定修复：日期选择记录上次发布时区，换区清除旧日选择/完整历史回到新asOfDay，保留同区完整日；大字习惯状态放到同文字列下一行，保留正常布局/动作/disabled/ID并补AX状态值。另两条后台导入warning追到Growth新didSave订阅未切回主线程，补receive(on:RunLoop.main)。第三条Invalid frame具体发生在打开周回顾，继续查证。

`compile-d5`测试局部变量add遮盖XCTestCase.add导致编译FAIL；更名addGoal后`compile-d6` PASS。`affected-d5`完整WeightFoundationTests+AppCompositionTests **35PASS0FAIL0SKIP / exit0、runtimeWarnings=[]**，包含上海→洛杉矶两个真实读数落入完整自然日的独立反例。精确未提交源码/哈希为`candidate-d6.patch`/`candidate-d6-source.json`；`ui-d5`仅补十项实际受影响UI，结果待收集。最终clean Debug/Release、实包、独立review closure、push/唯一Draft PR尚未完成。


`ui-d5`实际10项 **7PASS3FAIL0SKIP / exit65、1条Invalid frame warning**。Files预览取消恢复、后台QImport刷新、中文实际Dark最大AX BMI/星期菜单、清单新建管理保留草稿、Weight日期编辑删除、计时前后台/冷启动均PASS。两条Publishing changes from background警告不再出现，Growth主线程接收有配对结果。QFiveSources业务通过但同打开WeeklyReview接缝仍有frame warning，限定将原keyboard ToolbarItemGroup改为focused时导航栏44pt收键盘动作，保存逻辑不变。

三FAIL保留：Public扩展主动复制报告后Runner读剪贴板遭PBError13；随后只读专用Simulator主动复制报告确认category=appGroup（文件`ui-d5-public-copied-diagnostic.txt`），新测试改为扩展自己原生粘贴报告再验证。mixed新增today-investment断言失败：SegmentReview夹具是finish+saveTimer后的已保存事实，没有unfinished，生产正确隐藏；改为真实Start→Collapse再拍混合页面。RunningCold走过恢复/取消确认/丢弃/手工草稿冷重开，最后空态在新增图表下方未实例化；保留原空态断言并正常滚动，同时先断言真实总数/时长为0，不修改事实代码。后续仅五项受影响UI补验（含原WeeklyReview保存），其余通过证据复用。


独立R7/P2：InvestmentHistory的评价日跨午夜/前台变化时，总计重算而SessionPage加载key未含评价日，原records可能保留已移出7/30天窗口的事实。最小修复给既有page scope key增加民用today.identifier，同步触发offset归零与任务重查，不按每秒Date重读。新增冻结同一正式事实快照、评价日10-17→10-18的7日/30日成对反例，All time保留且旧评价日不变作对照；不冒称Unit执行了真实午夜UI。final-debug3 clean6db49ab已PASS，R7追加后另建干净包并定向运行完整InvestmentFoundationTests和相关历史UI，不重复517全量。

`final-debug4`在新反例误用不存在的durationOnly枚举编译FAIL；改用现有dateDuration，失败保留，下一干净构建final-debug5。

`final-debug5`继续指出新测试fixture的抛错初始化缺try，编译FAIL；仅补try，下一轮final-debug6，产品无新变化。
