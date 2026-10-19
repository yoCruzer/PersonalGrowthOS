# 使用反馈统一整改执行记录

状态：**READY_FOR_OWNER_DEVICE_GATE**。本地实现、受影响补验、最终双构建/实包、独立review、普通push及唯一新Draft PR #13已完成。下文是原始分轮历史，最终矩阵见ACCEPTANCE末段；不代表原生/签名/真机/CI全部通过。

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


`final-debug6` clean`1bfceef60b5849b3004f5b96854cbdb8e7d230a7` PASS；`affected-d7`完整InvestmentFoundationTests **31PASS0FAIL0SKIP / exit0、runtimeWarnings=[]**，含R7两个范围和既有F1保护。Debug实际三包proof=`debug-bundle-proof-1bfceef.json`，完整clean SHA/localGit/Tag空、1.0(7)/min17；额外hash真正debug/preview实现库，不只相同stub可执行文件。`debug-implementation-mach-o-1bfceef.txt`直接核对真实App.debug.dylib的AlarmKit LC_LOAD_WEAK_DYLIB/min17。

`ui-d6`Public再次到原生App Group错误，扩展内粘贴诊断的编辑菜单也不可触达，原FAIL保留；该临时探查逻辑已移除，恢复50e9原严格分享成功测试，不加环境跳过、不改变生产共享/签名边界。原始失败ui-d5/ui-d6及主动复制后通过simctl取得的真实报告保留；签名分享正向仍NOT_RUN，不重复在已确认的unsigned环境探查。其余五项收口UI继续运行。最终test-only回归恢复与1bfceef产品源码相同证明另留。


ui-d6中QFiveSources与原WeeklyReview多字段/收键盘/保存/冷启动均PASS（64.213s/31.008s），未再出现对应frame warning；RunningCold手工草稿54.058s PASS，实际0场/0秒且空态可滚动，保留草稿不计入历史。mixed英文默认含真实running/activeGoal通过；中文最大AX完成七张滚动截图后在页底断言早先Goal仍exists失败（最大字号List有限实例化），原失败保留。仅改测试向下滚回实际Goal/Investment、断言isHittable再截图；未改生产/减少断言。最后月份/自然日/跨日UI仍在执行，完成后只补mixed一项，不再重跑其余。


`ui-d6`完整 **6项=4PASS2FAIL0SKIP / exit65、runtimeWarnings=[]**：QFiveSources、WeeklyReview原多字段保存/冷启动、RunningCold手工草稿0/0/空态、History自然窗口/月份/分页/精确crossday全部通过。两FAIL为已确认unsigned public share环境和mixed页底早先行检查。root实际查看`ui-d6-attachments/4D906F23-4D6A-473F-B779-A931E361F1CD.png`，真实active Goal在Today2中，证明未丢失；但也确实看见共享图标随AX放大超出24列，target图标叠到active文字。R5相关新布局缺陷需处理：仅将AX hidden的装饰图标固定20pt于24列，正文/副标题仍完整缩放，触控范围不变；补跑mixed并由独立reviewer看实图，不将旧图冒称无遮挡。


`ui-d7`单mixed **FAIL / exit65**，并非滚回Goal阶段：在中文Growth点击Goals中央后仍留成长页，`new-goal-title`不存在。实际树`ui-d7-attachments/2FEA3B5C-F8CE-43A2-AABE-485B368EC883.txt`明确navigationBar=成长且growth-goals仍在；原生log点击坐标目标正确。共享ModuleEntryRow标签的空白未定义整行命中区，与前清单/回顾已证实接缝一致；补`.contentShape(.rect)`到共享行完整frame，保持原NavigationLink/action；测试增加真实Goals目的导航断言，不以点文字坐标绕过问题。与图标20pt一起仅补mixed实际路径。


## 最终本地收口

最终产品/测试`9601ff211fbdafc954e32f9e25206a38479e972b`，工作树clean。final-debug8 PASS，ui-d8单mixed1/1PASS且runtimeWarnings=[]，final-release1 unsigned generic iOS PASS，均exit0。实际六包原Bundle IDs、1.0(7)/min17，两App provenance clean同完整9601/localGit/Tag空；实际Debug实现库与Release Mach-O的AlarmKit弱链接、中英权限说明及哈希已核验。Release仅ShareExtension无AppIntents依赖metadata warning，原log不抹去。

真正独立只读reviewer `/root/usage_remediation_independent_review` 已直接核对源码/红绿反例/原始测试和截图/实包，R1–R8关闭，无范围内仍未关闭的已确认P0/P1/P2。原文完整写入REVIEW。未证实的主context缓存假设撤回，未冒称缺陷。review明确完整原生/签名/真机/CI尚有缺口，详见ACCEPTANCE末段具体D1–D4清单。

最终证据索引native-run-index.json（143 log）、full-unit-reuse-proof-final.json、final-ui-coverage.json，以及debug/release-bundle-proof-9601ff2.json；不同轮次不拼新全绿全量。全Unit原517=512/4/1，四个旧fixture修正后受影响完整两类60PASS，后续35/31完整受影响类通过；Public环境FAIL/AlarmKit SKIP及旧Safari FAIL/低空间SKIP/CI NOT_RUN始终保留。最终仅文档交付提交不重建相同产品，普通push/唯一Draft PR完成后记录远端身份，停Owner设备门禁。


## 实际交付与停止边界

普通push成功；`gh pr list --head ... --state all`确认此前为空后，仅创建一次[OPEN Draft PR #13](https://github.com/yoCruzer/PersonalGrowthOS/pull/13)，base=codex/time-investment-v1/baseRefOid=固定BASE，head=codex/usage-remediation-20261017。已调用attach_artifact附到本任务。没有更改旧PR。

创建后回读isDraft=true/state=OPEN/statusCheckRollup=[]；最终文档更新再普通push同分支，实际远端SHA及仅Markdown差异记`final-delivery-proof.json`。最终code/test及六实包仍9601ff2；所有后续交付仅五份Markdown，按验收契约复用双构建，不为了文档再重建。当前停READY_FOR_OWNER_DEVICE_GATE；此状态只表示本地授权批次和Draft交付完成，完整原生/签名/真机/CI门没有全部通过。具体D1–D4与环境FAIL/SKIP/NOT_RUN保持，下一步由Owner另行授权。


## PR #13 2026-10-18 独立复核修复批次（F1–F5 / UX1–UX2）

固定规格 `2add10b0c67d064b7e77478fb18a11479d3c94dc`；最终产品/测试 `597552a020eab22673feed108d8676359efd8822`（其中生产及Unit与f946相同，最后一提交仅UI驱动/补验）。原已审交付 f1b52b5 / 产品9601仅作历史，不作为本轮通过证明。沿同一原worktree和分支续接；2add相对f1仅六份Markdown，原BASE和FIX_GOAL均为本候选祖先；主工作区未知三项dirty保持，未reset/clean/stash/重建/新建PR。远端base仍5a70f01，PR #13 Draft/base原分支未变。

| 编号 | 本地实现与有区分力证据 |
| --- | --- |
| F1 | 仅successorWithdrawn重新启用的后继在applyTemplate换代，期次身份保持。真实磁盘两渠道协调器、确认取消与取消失败再完成、重复reconcile和重开通过；主动停止/已消费负例保持。fake不是AlarmKit原生正向证明。 |
| F2 | 单次覆盖前在同一事务冻结真旧nil系列偏移，普通单实例编辑同样保护。V11.0真实Schema创建单一open实例与原created事件，升级后nil；实际v7 ZIP恢复后同样nil，无早期完成线索。0/-1、短期/800天、同分钟/改分钟、complete/skip参数化；失败全部回滚，无设备账本；重开、新v11实际导出恢复与原事件bytes通过。 |
| F3 | accepted普通通知继续参加共享时间/类别规划；预算取消待确认与capacityWaiting区别于retired/stopped。实际查队确认后释放名额，legacy与新Todo/ImportantDay/Sleep共存。59保留项+L→E置换/完成E恢复L、跨类别、取消失败/恢复、停止项早/晚E都通过。Alarm/prepared读取失败仍confirmationRequired。 |
| F4 | shared WeightMeasurementLoader持有当前query/generation和任务；初始/更多/重试同一归属。可控reader挂起A第二页/重试，让B先返回再放A，B不改写；refresh/返回A及表头再出现保留页通过。 |
| F5 / 原T7 | typed process-local invalidation仅保存版本/ID；草稿与计时事件只读相关operation；正式变更/导入允许一次必要重建。每256条新context临时解码，workspace不常驻完整Session/已保存Operation；真实20条页和ID详情，重复候选同有界reader；保留必要业务冲突/重叠/完整性扫描。错误保持且显式重试；R1同时清values/重复候选baseline/待确认精确区间，R2失败输入与最后成功草稿可恢复。 |
| UX1 | 窗口外inspect自动全部累计，保留日/月/活动；主动期间切换才清日。固定2026-10-18/9-1的45分钟1条、窗口内/无记录/活动/清除语义Unit和中文Dark最大AX原生路径通过。 |
| UX2 | 主页面最近5条上界endExclusive且recordedAt<=snapshot.now，不强加趋势下界，日期选择<=asOf；历史截止标题中英。独立AllRecords仍全历史；10-10截止只显示10-1、AllRecords可查10-17，50→60分页/切日返回通过。 |

### 最终受影响验证

环境：macOS27.0.1/26A434；Xcode27.1/27A9275，SDK27.1；专用iPhone18Pro Simulator42609456-859D-41F8-8977-4B2D85A74082、iOS27.0/24A434。未操作其他模拟器数据或私人库。新原始证据 `/tmp/pgos-pr13-review-fix-evidence`；完整命令/SHA/dirty/exit/elapsed见各run JSON和native-run-index.json，原log/xcresult保留。

- final-unit2，同clean 597552a（final-unit1在clean f946相同241/0/1）：242=241PASS/0FAIL/1SKIP、exit0，runtimeWarnings=[]。九完整类：TodoFoundation48、TodoReminder29、SleepReminder4、ImportantDayReminder7、Weight19、InvestmentFoundation32、InvestmentPersistence29、ImportExportRecovery56、AppComposition18。SKIP为隔离32MB HFS+物理低空间环境，未改标。不是重跑全仓517。原始CoreData负例/Widget projection failed code0/Xcode版本解析诊断和两次构建的AppIntents metadata extraction skipped warning保留，不以warnings=[]抹去原日志。
- F5真实落盘10,000 Session与成对Operation，100条含长备注和两段。初始0.317755103秒，Session/Operation各40批fetch、各10000次decode；真实Service→带sequence通知→与AppShell共用Workspace.receive连续4次草稿、checkpoint(含草稿)/pause/resume后仍40/40与10000/10000，仅9条按ID operation decode。不是helper/generation反证；后台发布调度用同receive(on:RunLoop.main)。第二页与第一页共40decode，单ID详情1decode；正式edit/delete、实际ZIP import、读取故障、失败后草稿无隐式重扫和显式Retry恢复通过。Darwin ru_maxrss前后553107456 bytes（包括10k夹具和整个test host，不能解释为workspace峰值或节省比例）；不另做任意硬件阈值或Instruments批次。
- final-ui1：clean f946为10=8PASS2FAIL，未改写为整套通过；final-ui-supp1：clean597552a为4/4PASS（中文Weight最大AX截止、mixed默认/中文Dark最大AX整行导航、旧Weight编辑删除刷新、duplicate候选修改后清除/保存46分钟）。前轮8个PASS方法和生产/Unit源码与597完全不变，逐方法与blob复用证明见ui-evidence-reuse-proof.json；原失败与新补验分开记录。截图及manifest在final-ui1-attachments、final-ui-supp1-attachments，对应map列出名字/绝对路径。
- final-debug2：clean 597552a Debug build-for-testing exit0，App provenance与三包IDs/1.0(7)/min17及真实debug dylib哈希/AlarmKit弱链接核对；final-release1同clean597552a unsigned generic iOS Release exit0；两配置实际App/Share/Widget均保持原Bundle IDs、1.0(7)/minOS17，App provenance Commit=597552a、Dirty=false、Source=localGit、Tag为空。真实Debug dylib和Release executable均有LC_LOAD_WEAK_DYLIB AlarmKit.framework；中英usage描述均存在。精确哈希和原始otool在final-debug2/final-release1-bundle-proof.json与-mach-o.txt。

### 真实失败与补验（分轮保留）

| 运行 | 真实结果与后续 |
| --- | --- |
| red-a / red-a2 | 首次fixture有区分力不足：F1时区变化走另一换代路径而通过，F2提醒不晚于测试clock而invalidReminder；F3确证不能置换。修夹具后再红测，不把夹具错误冒称产品反例。 |
| red-a3 | 原Todo产品源码来自固定2add；同区/正确future后F1退役代次与F2偏移污染红测成立，原始assertions全部保留。 |
| green-ab | 30/30PASS：当时TodoReminder27+F2一项+Weight两项；工作树候选，非最终gate。 |
| focused-c1 | 4/4PASS：真V11.0/v7、停止负例/跨类别、10k真实链首轮；未包含后续review修复。 |
| focused-ui1 / ui2 | 各0PASS2FAIL：虚拟可见行5误当50、计数标签未在viewport、最大AX滚动落入wheel或详情未滚动。修实际same-query表头重现重载问题，并修正常视口驱动；原图树与失败保留。 |
| focused-ui3 | 2PASS1FAIL：Weight与UX1通过，新重复用例系统popover不提供Cancel仅Save anyway，改为原生外点取消。原始AX树保留，候选含驱动补验。 |
| candidate-unit1 / c2ddf18 | 242=240PASS1FAIL1SKIP；三条失败断言在同一个native read failure用例，修预检只针对accepted普通通知，保留Alarm/prepared语义，不改旧断言。 |
| review-fix-unit1 | 109=108PASS1FAIL；新增故障链test expectation被此前queued通知多fulfill，按每条通知sequence精确配对，所有通知仍送生产receive。计attempt先append再注入失败，使失败后无重扫断言有区分力。 |
| review-fix-unit2 | 109/109PASS；工作树候选。最终f946/597552a集中final-unit1/2均含全部后续assertions和补验。 |
| final-ui1 / f946 | 10=8PASS2FAIL。Weight cutoff/50→60/切日返回、UX1中文Dark最大AX、自然期间/跨日事实、手工编辑删除、R2失败关闭重试冷启、R3显式替换、Record独立草稿、running冷启均通过。mixed失败时目标整行被底栏覆盖；duplicate已验证候选45分钟和ID详情，返回后输入框在导航栏下未聚焦。原截图/AX树与失败保留；597552a仅改驱动可见性/键盘断言并新增中文体重用例，不改生产/Unit。 |
| final-ui-supp1 / 597552a | 4/4PASS exit0，原两个失败项以完整视口/键盘断言补验闭环；另补中文Weight Dark最大AX与旧Weight编辑删除刷新。不是同一轮10项全绿。 |

### 独立复核、兼容与设备门

Reviewer `/root/pr13_fix_independent_reviewer` 没有编写本轮代码，读取固定规格/源码diff/生产路径/测试及原始证据，提出并复核：预算停止/空位边界、查队不确定语义、重复候选伪零/排序/过期、所有Editor内容副本清除、中文截止标题和失败重试可达性。原始终审结论见REVIEW本轮追加章节，不由作者代写独立通过。

持久Schema V1–V15、V11.0/11.1历史模型、v11备份wire与工程/身份/签名/minOS均未改变；设备账本仅新增本地取消原因phase，不进备份。兼容路径blob与祖先/原工作区保全在source-compatibility-proof.json（changedCompatibilityPaths=[]，四条checked路径blob全部相同）；实际迁移/ZIP和回滚由最终相关完整类复验。

本轮不授权D1–D4/私人设备与库/签名安装/merge/force/tag/Archive/TestFlight。原AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、签名/真机/远端CI NOT_RUN继续保留。全部本地门通过才恢复READY_FOR_OWNER_DEVICE_GATE，设备门本身不因此通过。

本轮交付提交在固定产品597552a之后只更新五份Markdown；交付SHA以本次交付commit/PR head和外部final-delivery-proof.json核对，避免文件自引用。普通push后核对Draft/base/head和workflows=0、checks=[]；远端CI仍NOT_RUN。


## PR #13 第二轮限定补修本地交付（2026-10-19）

固定 FIX2_GOAL_SHA `41ef47c384464823f9456e9816d574ba7edff563`；产品/测试 `c296a3691d53ce7f5b5bff36fbf7de525d86510f`；前轮产品597552a / 交付e75ac561保留为历史。原worktree从e75干净fast-forward到41ef，六份Markdown增量；未从BASE重建。主工作区三项未知改动保持，固定规格/原交付/base为候选祖先，原PR #13 Draft / base不变。CR-01～06与前轮F1～F5/UX1～UX2、原R1～R8及时间投入历史T编号分别记录，不重新编号或覆盖历史。

| 项目 | 生产处理及可区分证据 |
| --- | --- |
| CR-01 | retire入口独立处理capacityCancellationPending，native真实缺失确认后未来继续capacityWaiting、过期退役/elapsed；普通通知过期先于selected预算判断，正常ringing Alarm不动。可推进时钟跨fireAt，native已消失/仍失败后取消、重开/重复Recheck、不排过去时间；原F3未来恢复在同候选完整Reminder类通过。 |
| CR-02 | 容量原因pending可靠落盘/精确读回前不移除native；主动取消继续原best-effort语义。mode0 pending真未保存即止，native/accepted保持，不尝试waiting写；mode1 pending已保存但waiting真失败，磁盘pending可恢复；mode2实际save后仅报错以精确读回确认，waiting落盘。冷coordinator恢复L，原generation不变、59保留项与预算/停止负例保持。不是AlarmKit容量证明。 |
| CR-03 | 显式规则offset优先；缺值从经过完整sequence/before/after末端验证的第0期created/converted源恢复，在业务事务中冻结。真V11.0单一open→迁移→旧f1等价事务已覆盖nil→V15/v11实际ZIP恢复，含覆盖前无关标题edit；覆盖后当前版本metadata/title、跨时区刷新、删除清单（含task已单次换清单而rule仍指旧清单）在添事件/改rule时间前冻结；0/-1、短/800天、同/改分钟、complete/skip/再次改期、重开/导出恢复、保存失败回滚，所有既有事件/快照字节保持。独立reviewer逐段比对旧f1 happy path；没有运行旧二进制。真实4625602原V11夹具证明派生后继曾丢lead，不参与原始规则投票；旧断言保留并补验。 |
| CR-04 | 正式facts版本变化仅清草稿候选IDs/baseline/展示与旧duplicate提示，保留输入、最后成功草稿和真实写入错误，不让草稿按键扫历史。修改/删除B后不变A候选失效；仍匹配负例仍触发正常重复确认。UI覆盖默认编辑B、中文Dark最大字号删除B，再保存A。 |
| CR-05 | 内层save成功回调标记完成，外层Timer在内层onDismiss后关闭到有效Hub；不把终态payload放回缓存。首次保存注入未提交错误保留备注/时长，重试成功退出两层，稳定Hub按钮可用、History恰好一条3分钟并有正确详情。原Confirm later/冷启动用例保持。 |
| CR-06 | 仅DEBUG+UITesting可注入的WeightReviewClock同供页面/夹具，固定2026-10-18；native日期弹窗核对完整2026/10月再选10日。Unit的live日期对照为2026-11/2027-10，注入后固定日不变；无UITesting正常使用live。未修改主机时间或声称已在未来真实主机日期执行。中英截止、50→60/切日返回/全历史17日断言保留。 |
| OBS-01 | 同一预热Workspace经pause实际save后抛错，对照未save错误，普通refresh/Retry、resume/checkpoint及关联正式delete缓存清理通过。仅commit真正开始后的错误发布原scope失效，仍抛原错，由canonical reader区分结果；body重复/业务拒绝不发布facts失效。真实RunLoop延迟通知链验证刚显示的候选不被误清。不是原生SwiftData自然必现P2。 |
| OBS-02 | load只处理共享当前query，切换权属于initial/select；正常首载/更多/重试/显式切日及旧reader晚返回保持。有界顺序调用真实loader验证旧A按钮入口不能重选B后的A；未证明该启动顺序实际SwiftUI可达，原观察保持UNCONFIRMED，不重开原F4。 |

CR-03恢复边界：技术时间相等本身不证明未编辑。没有第0期、规则曾变化但没有可识别policy，或多次/无法区分的旧墙钟编辑时拒绝编造offset，原事实与事务回滚保持；可显式改系列规则提供policy。f1/当前正式futureSeries编辑有提醒时会显式写offset，优先使用该值；测试含同分钟正式改-1与converted同now正例，以及nil/sameTimestamp歧义拒绝后显式纠正负例。未宣称任意旧nil都可自动恢复。

### 实际环境与最终本地门

macOS27.0.1/26A434，Xcode27.1/27A9275，SDK27.1；专用iPhone18Pro模拟器42609456-859D-41F8-8977-4B2D85A74082 / iOS27.0(24A434)。Xcode串行，隔离合成库；未操作私人库/设备、其他模拟器数据。原始日志、xcresult、截图manifest、实包proof和完整命令/SHA/dirty/exit在 `/tmp/pgos-pr13-fix2-evidence`。本机独立reviewer实际读取，未声称远端reviewer已取得这些开发机产物；下方小型摘要/哈希供远端核对，CI仍NOT_RUN。

- `final-debug6`：clean c296a36，Debug Simulator `build-for-testing` exit0；`final-unit4` 同候选九类252=251PASS/0FAIL/1SKIP，exit0，34.165秒（测试31.015秒）。AppComposition18、ImportExportRecovery57、ImportantDayReminder7、InvestmentFoundation32、InvestmentPersistence32、SleepReminder4、TodoFoundation50（含1SKIP）、TodoReminder31、WeightFoundation21。不是全仓全套重跑。唯一SKIP为隔离32MB HFS+物理低空间环境未具备；不得填满主盘。
- `final-ui-cr05` 同clean c296a36，完整1/1PASS，exit0；中英两分支共124.619秒（命令128.068秒）。`final-ui-regression` 同候选八项结果：8/8PASS，exit0，594.713秒测试体。原fixtureWeight两项在cec的完整PASS、duplicate在302完整PASS、CR04在b45完整PASS按精确生产路径/方法/helper blob复用；并非把变化路径的旧PASS当新候选，未声称一次13/13。
- `final-release1`：clean c296a36，unsigned generic iOS Release PASS，exit0，41.502秒。实包实际proof含App `com.yocruzer.PersonalGrowthOS`、Share `com.yocruzer.PersonalGrowthOS.ShareExtension`、Widget `com.yocruzer.PersonalGrowthOS.ImportantDaysWidget`，均1.0(7)/minOS17.0；App provenance Commit=c296a3691d53ce7f5b5bff36fbf7de525d86510f、Dirty=false、Source=localGit、Tag为空。Debug实际承载dylib与Release主可执行的AlarmKit `LC_LOAD_WEAK_DYLIB`、中英NSAlarmKitUsageDescription核对。App Group等entitlement/工程源码blob不变；unsigned实包不等于签名安装或设备正向证明。
- F5真实10k磁盘链：`testUsageFiveYearSnapshotReusesStatisticsAndBoundsRealDiskPageThenRefreshesChanges` 首次refresh0.3196220397949219秒，40 fact批次/40 operation批次、10000/10000解码；Service草稿和计时命令→真实事件→同一个Workspace后仍40/40与10000 fact解码，9次operation按ID解码，未靠generation不变推断读取。两页20条详情合计解码40、按ID详情1，初始已保存操作正文保留0。全host peakRSS before/after均552763392 bytes，含夹具与测试host，不能声称Workspace独立峰值或节省量。强制正式变更仍进行必要业务完整性检查。
- 预期故障日志保留：腐坏库CoreData259、注入调度/授权/写入错误、Widget projection code0及Xcode runtime invalidDigitCount诊断；没有把这些原始日志删除或冒称自然设备故障。每项测试真实退出与断言以原始xcresult为准。


### 真实失败、补验与中止

| 轮次 | 真实结果与处置 |
| --- | --- |
| red-a | 2FAIL：跨期pending不收敛；两phase真未落盘却移除native并误retired。新路径pending失败即保留native，不伪称两次抛错但实际保存。 |
| red-cr03 / red-b | 首次与修正intent existing分支后存量红例均FAIL；red-b 4FAIL另含候选成员变化、同Workspace陈旧revision/conflict、旧按钮入口。真实V11/旧f1等价事务来源经校验，非新服务首次覆盖。 |
| red-b-build / green-core-build / recovery-build2 | 新测试缺excluding参数、onSaved参数顺序、收紧root后遗留continue分别编译失败；修正后构建成功，不算产品业务红例。 |
| green-core / diagnostic-cr02 | 12项为11PASS1FAIL；单项诊断仍FAIL。native/journal已恢复，测试错误引用旧coordinator；改断言为实际cold实例，三模式精确phase和等待写尝试另加强。原业务断言保持。 |
| green-scope | 10/10PASS；当时候选dirty，不替代最终门。 |
| red-ui-cr05 | 1FAIL，临时仅将自有Timer段替为固定41ef旧段；真实失败准确为保存后外层Timer未退出，故障输入保留先通过。finally恢复当前源码，有来源hash；未重置未知改动。 |
| final-unit1 / 395 | 251=249PASS1FAIL1SKIP；原4625602 V11实包fixture被新“后继一致性”错误拒绝。保留原断言，改为独立原始root证据；recovery-green 5/5PASS。 |
| final-unit2 / cec | 251=250PASS0FAIL1SKIP；尚未含后来新增的业务错误事件反例，不当最终新候选全通过。 |
| final-ui1 / cec | 13项计划在确认新事件回归后主动中止；summary实际3 collected=2PASS/1FAIL（Testing was canceled），exit75。两Weight完整PASS 85.472/50.531秒，mixed被取消；保留SIGINT记录与Xcode取消堆栈，不把它当产品崩溃或13通过。 |
| red-event-scope / scope2 | 各1FAIL，真实延迟通知会清掉刚显示候选。首轮version对象别名对照偏弱但候选失败有效；改独立int快照后6断言红测成立。仅commitAttempted后错失效修复；event-green 4/4PASS同时覆盖OBS两方向、CR04和10k。 |
| final-ui-core1 / 302 | 3=1PASS2FAIL：原duplicate UI完整PASS37.745秒；CR04/CR05中文最大字号读取duration失败。保留断言，局部gutter视口校准。 |
| final-ui-core2 / c98 | 2=1PASS1FAIL：CR04默认编辑/中文Dark最大字号删除完整PASS118.047秒；CR05辅助函数误用普通表单nav标题失败，修为实际确认标题。 |
| final-ui-core3 / b45 | 2=1PASS1FAIL：CR04再次完整PASS117.560秒；CR05中文已返回Hub，但后置查找上方History驱动方向错误，仍记整项FAIL132.412秒。过渡截图不当稳定落点证明。 |
| red-cr03-continuation | 1FAIL（2断言）：新metadata edit导致nil未冻结及后续invalidReminderOffset；先红后修。 |
| continuation-green | 1测试崩溃：新增fixture捕获旧TodoList跨container销毁；改只传UUID，非忽略生产异常。continuation-green2完整1/1PASS，覆盖三种合法后续命令及回滚。 |
| final-ui-cr05 / c296 | 完整1/1PASS：默认与中文Dark最大字号的失败保留、重试退出两层、稳定Hub可操作、历史1条3分钟、按ID详情备注均断言通过。 |
| final-ui-regression / c296 | 8/8PASS，exit0；594.713秒测试体；完整串行结果，无新增失败。 |

### 独立复核与停止边界

Reviewer `/root/pr13_fix2_reviewer` 未编写本轮代码、未运行Xcode/操作模拟器或push，独立核对固定规格/完整diff/旧等价事务/原实包来源/测试与本机原始证据。原文终审追加REVIEW，作者不代写独立通过。历史Schema V1–V15、TransferModels、ZIPArchive及工程blob保持，兼容由实际恢复/回滚补验。

只有六项收尾、OBS限定工作和必要本地门全部有效才恢复READY_FOR_OWNER_DEVICE_GATE。D1–D4未通过；AlarmKit原生正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、签名/私人设备/私人库与远端CI NOT_RUN保持。本轮不签名安装、merge、force push、tag、Archive或TestFlight。交付在产品之后仅文档，SHA以交付commit/PR head和外部final-delivery-proof.json核对，避免文件自引用。


### 可供远端核对的小型结果摘要

| 原始运行 | 候选SHA / dirty | exit | 结果（xcresult） | log SHA-256 |
| --- | --- | --- | --- | --- |
| red-a | 41ef47c38446 / dirty | 65 | 2 total / 0 PASS / 2 FAIL / 0 SKIP | `b0a6ba6e8d4ad1b0a8387ec2981ccc6d584f46cbcc7815cd22eb0685c273116a` |
| red-b | 41ef47c38446 / dirty | 65 | 4 total / 0 PASS / 4 FAIL / 0 SKIP | `d93aa7ac3de694a4ebbc6de3b39031673a0159faabdfadd28436c31984b2825e` |
| red-cr03 | 41ef47c38446 / dirty | 65 | 1 total / 0 PASS / 1 FAIL / 0 SKIP | `959332255d7de88a7bebcf03cce66fc6029e0da115c58821763def96e3e0211e` |
| red-ui-cr05 | 41ef47c38446 / dirty | 65 | 1 total / 0 PASS / 1 FAIL / 0 SKIP | `16596f9c25e578fb4605eebf24dbbac2e03b3f71782dd098ecfdea5784a0c55a` |
| red-event-scope2 | cec2e4d4cc9e / dirty | 65 | 1 total / 0 PASS / 1 FAIL / 0 SKIP | `9e60a1d5a7aab97802ea0f4f52474115d4efd19d8f9fc0718f7ad2893bfe157d` |
| red-cr03-continuation | b45ce36f4332 / dirty | 65 | 1 total / 0 PASS / 1 FAIL / 0 SKIP | `046483886226dc7902e8e2b104bd2663fd8890fdf5d3e7800f9f75bf253d87a1` |
| continuation-green | b45ce36f4332 / dirty | 65 | 1 total / 0 PASS / 1 FAIL / 0 SKIP | `60d3f0d57698b6e977da1d242cfc57b86b8eccb0ad3910df45830ff043b162fc` |
| continuation-green2 | b45ce36f4332 / dirty | 0 | 1 total / 1 PASS / 0 FAIL / 0 SKIP | `94391f68e00438de4d993681b5750ebb914e77fe7a02c6a351a94d9819ee6043` |
| final-unit1 | 395f3bf5dd35 / clean | 65 | 251 total / 249 PASS / 1 FAIL / 1 SKIP | `ad741e339578925b2d82d75f133cb65ebd80a004166fcb286914b86b514bf43d` |
| final-unit2 | cec2e4d4cc9e / clean | 0 | 251 total / 250 PASS / 0 FAIL / 1 SKIP | `00226dc37be74a95c55a7362bf9e36e7d3a9e995fbea0af0be5c7fbc70760707` |
| final-unit3 | 302e3109c8e0 / clean | 0 | 252 total / 251 PASS / 0 FAIL / 1 SKIP | `5d130c61fd51805512488b4bfca30124ead1b0e1ef03b055ad1e7156c327903f` |
| final-unit4 | c296a3691d53 / clean | 0 | 252 total / 251 PASS / 0 FAIL / 1 SKIP | `67ddc2e5fa3bc31b6f40dd28d6db9fcfb01adc620ae76fb0453ff48a825f45d1` |
| final-ui1 | cec2e4d4cc9e / clean | 75 | 3 total / 2 PASS / 1 FAIL / 0 SKIP | `9bd1095ef5a7dcdfc8c1556dff4c4edf6318f9b0957afc50ca9c0814a26f251b` |
| final-ui-core1 | 302e3109c8e0 / clean | 65 | 3 total / 1 PASS / 2 FAIL / 0 SKIP | `abfbdbe233a52b0b83c196761d43497e69d4883fca11ff4e077056b58a960285` |
| final-ui-core2 | c98e3e2100e3 / clean | 65 | 2 total / 1 PASS / 1 FAIL / 0 SKIP | `360a01e739b54b91b6b4d65338d1f4edaa20eaec3e05d97bdf8deb59ff33bec6` |
| final-ui-core3 | b45ce36f4332 / clean | 65 | 2 total / 1 PASS / 1 FAIL / 0 SKIP | `557817651da526394b1a58f9beded56c91258c2f1c3ecc854e26e70824af88cc` |
| final-ui-cr05 | c296a3691d53 / clean | 0 | 1 total / 1 PASS / 0 FAIL / 0 SKIP | `d721430949ae47bebb9c4c9945714f6cb3ff10351132d735324997a00c0206b9` |
| final-ui-regression | c296a3691d53 / clean | 0 | 8 total / 8 PASS / 0 FAIL / 0 SKIP | `96759dacb258662c28a540d4cc48044ff08bf649c838209f64c884c35a17225f` |
| final-debug6 | c296a3691d53 / clean | 0 | 0 total / 0 PASS / 0 FAIL / 0 SKIP | `ec3a18797fa72f62ccec84b64ddb4555fdc50288499c2d66f3577af024138769` |
| final-release1 | c296a3691d53 / clean | 0 | 0 total / 0 PASS / 0 FAIL / 0 SKIP | `88e1e6e721462ced3397dc686b945de73804834fdf4703d46d67416d82062599` |

日志的实际命令、SHA、dirty、退出码和计数来自同名JSON/xcresult，不将计划数作为执行数；原始大产物只在本机证据根。`—`表示无该项摘要，不代表0。

- `native-run-index.json` SHA-256 `0d5ee45465a89d26bf3fb376bdd746ee6201150178cf5a87160df2e1e3c2fa8b`
- `final-evidence-reuse-proof.json` SHA-256 `63266359547d453ee5632537581c498dfe32a317229788fef0cc94114091d6c9`
- `continuity-proof.json` SHA-256 `6874a6413fba1bc65f95fb79e1219d31ab62c30271005bfbb591f499890fd9a4`
- `final-debug6-bundle-proof.json` SHA-256 `45814a0e9d2e9e489a3718947961d561611c3e9b8357124967ad7a968d018afd`
- `final-release1-bundle-proof.json` SHA-256 `01d280514280f3a30d36d304450a17268263f6d12acca95960ab02d7d780f765`
- `final-debug6-mach-o.txt` SHA-256 `ca49ddfd4cdbb2bab060d8ec9fc392132bca50f8dd1bdc9a185bedf7173b252b`
- `final-release1-mach-o.txt` SHA-256 `2da619a9e252e9c7c63d997f72f7f6bc539483c23a5e6732b945d720753eb0b2`
- `final-bundle-assertions.json` SHA-256 `79668d659e18d9cbda57a62c5f7ab881258c10c6fe2a3ed6f9d46467ad3df96c`
- `screenshot-map.json` SHA-256 `287f54a3a27e0a37842cf551f5041f042d55e82564a99dfd47d493054facaf38`
- `original-v11-immutable-sqlite.json` SHA-256 `e56cb03a5c90aba891aae0ad32e47dc0e32eb2ac06ed703e5a9d7f45b26d64d1`
- `red-source-hashes.json` SHA-256 `a7a91c169cb5222d4b8db4b0e7f2feaf7ab8c9eed3fedbf2be3b3a2f8ae16fb1`
- `red-ui-timer-source.json` SHA-256 `fc80db48a21a56646e5b17dba57df26b68a1becac164ed65f5718b451458f6b1`
- `final-ui-cr05-attachments/manifest.json` SHA-256 `0854e417d548ce5584368fe6ebb59c082b420b78169986b652c3f26d4d41bce6`
- `final-ui-regression-attachments/manifest.json` SHA-256 `eeafceb129354aaccd97f0b2751d07ed3b8cad855c1e43df3044afc1c099bd1e`
- final-debug6 `com.yocruzer.PersonalGrowthOS` v1.0(7) minOS17.0 executableSHA256 `43303593fe3bac299ec83fc15424c5ce48c4e4fa9e4dea8585d16bbc729578f9`；provenance `{'Commit': 'c296a3691d53ce7f5b5bff36fbf7de525d86510f', 'Dirty': False, 'Source': 'localGit', 'Tag': ''}`
- final-debug6 `com.yocruzer.PersonalGrowthOS.ImportantDaysWidget` v1.0(7) minOS17.0 executableSHA256 `15dac98175aa7582e720fd6dca4cd2e9eee1ba9946a78c53ea9695b7f7cf5dd5`
- final-debug6 `com.yocruzer.PersonalGrowthOS.ShareExtension` v1.0(7) minOS17.0 executableSHA256 `42841fffbef5b7cf7db4268d0cf41c40243d50c2abbe9ff6a6b51464b2d4df85`
- final-release1 `com.yocruzer.PersonalGrowthOS` v1.0(7) minOS17.0 executableSHA256 `350819f01ff4035a9fe2d64a437ccd851316335fd59540bc2bde6aa71c6329cc`；provenance `{'Commit': 'c296a3691d53ce7f5b5bff36fbf7de525d86510f', 'Dirty': False, 'Source': 'localGit', 'Tag': ''}`
- final-release1 `com.yocruzer.PersonalGrowthOS.ImportantDaysWidget` v1.0(7) minOS17.0 executableSHA256 `e5af21c4a3ffe0136711933f7d8a1269f02f02b5bd3bdc658317117294705637`
- final-release1 `com.yocruzer.PersonalGrowthOS.ShareExtension` v1.0(7) minOS17.0 executableSHA256 `aa3f9e979eb8d847f3f8b20743b671b8779b4098b4b68feb7fd3608c991d54a7`

### final-debug6

```sh
xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -sdk iphonesimulator -arch arm64 -derivedDataPath /tmp/pgos-pr13-fix-derived -resultBundlePath /tmp/pgos-pr13-fix2-evidence/final-debug6.xcresult CODE_SIGNING_ALLOWED=NO build-for-testing
```
### final-unit4

```sh
xcodebuild test-without-building -xctestrun /tmp/pgos-pr13-fix-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=42609456-859D-41F8-8977-4B2D85A74082' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-pr13-fix2-evidence/final-unit4.xcresult -only-testing:PersonalGrowthOSTests/TodoFoundationTests -only-testing:PersonalGrowthOSTests/TodoReminderTests -only-testing:PersonalGrowthOSTests/SleepReminderTests -only-testing:PersonalGrowthOSTests/ImportantDayReminderTests -only-testing:PersonalGrowthOSTests/WeightFoundationTests -only-testing:PersonalGrowthOSTests/InvestmentFoundationTests -only-testing:PersonalGrowthOSTests/InvestmentPersistenceTests -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests -only-testing:PersonalGrowthOSTests/AppCompositionTests
```
### final-ui-cr05

```sh
xcodebuild test-without-building -xctestrun /tmp/pgos-pr13-fix-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=42609456-859D-41F8-8977-4B2D85A74082' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-pr13-fix2-evidence/final-ui-cr05.xcresult -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testFix2CR05TimerSaveReturnsToHubDefaultAndChineseDarkMaximumText
```
### final-ui-regression

```sh
xcodebuild test-without-building -xctestrun /tmp/pgos-pr13-fix-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=42609456-859D-41F8-8977-4B2D85A74082' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-pr13-fix2-evidence/final-ui-regression.xcresult -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testUsageMixedTodayAndGrowthDefaultAndChineseMaximumText -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testUsageWeightDailyMeansRangesAndDateHistoryEditDeleteRefresh -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testReviewFixUX1OutsideWindowDateSwitchRetainsDateMonthAndDetailChineseDarkAX -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testManualSaveHistoryNilFeelingEditAndDeleteRefreshSameReview -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testExternalR2FailedCloseKeepsEditorAndRetrySurvivesColdLaunch -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testExternalR3ChineseDarkAXConfirmationPreservesOrExplicitlyReplacesSegments -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testRecordDraftSurvivesManualActivitySaveAndChineseDarkAX -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testTimerForegroundBackgroundFrozenConfirmationAndColdRelaunch
```
### final-release1

```sh
xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination generic/platform=iOS -derivedDataPath /tmp/pgos-pr13-fix-release -resultBundlePath /tmp/pgos-pr13-fix2-evidence/final-release1.xcresult CODE_SIGNING_ALLOWED=NO build
```


## 2026-10-19 系统整改 — FIXES_IN_PROGRESS

SYSTEM_FIX_GOAL_SHA=3dad3b04e3ff703c2e799899035285f64a5976a4。原任务干净62210d9仅快进到固定规格；远端head=3dad3b0、base=5a70f01、PR13 OPEN Draft。主工作区未知project.pbxproj/Localizable.xcstrings/xcodecloud改动不触碰。当前未运行本轮原生门，不复用旧PASS关闭SR。

### 实施前不变量、全部相关生产消费者与合法后续操作

| 项 | 不变量 | 生产调用者/消费者 | 代表状态与验证边界 |
| --- | --- | --- | --- |
| SR01 | 终止/清理不依赖未来策略；未知策略仅局部失败 | TodoTaskService.preserveLegacyReminderOffset→rescheduleReminder/edit；reminderOffset→applyReminder/applyTemplate/generateNext/deleteList/refreshRepeatingReminderTimes；stopSeries/delete/transition；TodoReminderCoordinator→intentScheduling及Todo/ImportantDay/Sleep预算 | 真V11/旧f1 nil，stopped有根/无根/兄弟期；Stop→切区/默认编辑/关提醒/删清单；active可恢复/歧义，0/-1；回滚/重开/ZIP恢复。未来生成仍要求可信原offset |
| SR02 | 编辑文本无分组且Double无损往返；展示精度独立 | WeightEditorView初值→WeightRules.kilograms→WeightRecordService；WeightReviewReader/Trend/BMI/History/Today/Growth/Weekly | en_US/zh_CN/de_DE；1000/72.345/普通值，no-op/日期-only/真改值/混合错误 |
| SR03 | Entry/Habit/Weight共同asOf；Habit用保存业务日 | WeeklySummaryService.make全部派生、WeeklyReviewView；HabitLogDayResolver/analytics/QuietWins；Weight/Today/Growth截止与全历史 | 洛杉矶周日晚→上海、同业务日两次、跨年/DST/旧缺元数据/撤销；未来三事实推进时钟；历史选周与统计时钟分离；编辑删除刷新 |
| SR04 | MainActor不等待发布锁且最终checkpoint可靠；备份媒体一致 | StorePublication所有使用方：InvestmentService全mutation/Workspace.checkpoint/AppShell.scenePhase；ImportantDay save/createEntry/delete；ExternalCaptureImporter、ImportExportService worker | 真export持锁barrier→生命周期checkpoint→主probe；释放后落盘；pause/finish/revision、paused对照、草稿/取消/失败/重试/合并 |
| SR05 | 旧success/cancel/普通error不写最新设置 | AppShell daily/weekly设置onChange→ReminderScheduler→NotificationMutationGate→结果回流 | A进入addRepeating→B→A普通失败/成功；B明确off；当前真失败；授权显示/时间/weekday保持 |
| SR06 | 仅成功结束编辑器释放；持久saved证据保留 | InvestmentWorkspace.editor/refresh/finished；新manual/timer确认/正式edit/draft/稍后/失败/删除；Editor保存落点 | 连续新manual/timer成功缓存不累计；失败/保留/稍后保留输入；幂等、CR05双层关闭/F5计数 |
| SR07 | 同动作/同入口使用相同语义 | Today daily once/multiple及HabitOverviewRow weekly/monthly；Sleep/ImportantDay反馈；Weight截止连贯性；mixed UI fixture | 默认与中文真Dark最大AX，图标/标题列、44pt动作和自然行高；只收反馈不改事实；Record独立草稿 |
| BV01 | 只对生产实际读取定性 | GrowthView didSave→GrowthEntryCounts、Weight/Sleep/活动；真实InvestmentService事件及挂载生命周期 | 约10k混合数据，可见/切离；实际fetch/模型读取与主probe；正式事实/import/日期/时区/错误刷新保护 |
| BV02 | 非有限quantity不可悄悄破坏完整备份 | Habit输入Double→HabitCheckInService→磁盘→TransferSnapshot→实际export | inf/NaN/指数溢出/finite正例；如确认则有限数校验及明确可恢复处理，不删旧事实 |

新原始证据根：/tmp/pgos-pr13-system-evidence。所有阶段定向测试和最终完整Unit/关键UI、固定干净SHA双构建、独立审查均待完成。


### 系统整改阶段证据（尚未集中交付）

当前所有产品/测试改动仍是固定3dad3b0后的dirty候选；不得把本节阶段结果冒称最终干净SHA的完整门。原始逐轮命令、退出码、xcresult摘要及日志SHA256由 `/tmp/pgos-pr13-system-evidence/system-runs.json` 记录，最终小型摘要将随交付入Git。

- red-a：3项=1PASS/2FAIL。真V11停止后默认编辑抛invalidReminderOffset；Weight实际编辑表达→解析→Service→重开复现1000→1及72.345舍入。此轮coordinator夹具与模拟器同区，未触发切区，不能把该1PASS当切区证明；随后夹具显式选择不同于.current的原区并补健康三类别、歧义active和真实多期兄弟删除。
- red-b：4项=2PASS/2FAIL。SR01/02局部已绿，Weekly三事实未来截止与LA周日→上海业务日仍红；仅先追加asOf/metadata参数以便编译，红候选未使用它们，旧算法主体保留于本机red-WeeklyReviewFoundation.swift。
- green-a：新增六项6/6PASS；daily/weekly真实LocalReminderScheduler→addRepeating挂起→B→A普通错/成功/取消，每日/每周、B off/on和当前真失败通过生产结果归属边界验证，不是系统原生晚错捕获。
- red-c：真实export已取得同一发布锁后悬停，生命周期checkpoint使主执行器直到独立5秒fail-safe释放才返回，1FAIL。green-c随后2/2PASS，主probe先于释放、最终120秒而导出原cutoff60秒；同时完成BV02原始有界探针。
- BV02原探针：inf和1e999能正式落盘为inf并阻断JSON导出；NaN被SQLite归一成nil、导出成功；finite2.5落盘/导出成功。新输入在普通/带心得Service写入前均拒绝非有限数；已有inf普通备份明确失败，不改值/删日志，单独提供原始保留数据支持恢复包，明确不能当普通备份导入。不能声称恢复过去已被SQLite丢掉的NaN或旧体重精度。
- BV01原探针：UIHostingController真实挂载Growth与Tab切离、10k Weight+10k Sleep，经实际Service草稿+正常checkpoint，两个状态各发生2次真实fetch，各读Weight20000/Sleep20000模型；主probe均可运行，未声称实测卡顿。限定过滤已明确识别的InvestmentOperation/Session标识；未知、批量失效、活动/参与者、正式Growth事实继续保守刷新。
- green-d：5/5PASS。包括BV01两状态实际历史读取0；BV02有限数拒绝/finite ZIP恢复/旧inf原始SQLite恢复保留ID、bitPattern、unit/result；导出排队合并后明确pause/finish不被晚checkpoint覆写；新manual/timer各连续3次成功缓存释放，keep/失败/持久saved幂等证据保持。
- green-e：5项=4PASS/1crash，exit65，绝非全绿。原始ips已确认新Growth过滤器对延迟通知发送方ModelContext.container的访问触发SwiftData断言；非XCTest/环境豁免。已去除发送方活对象访问，仅检查稳定PersistentIdentifier值。focused-green随后原组合与加强Weekly共7/7PASS；focused-green2新导出完成/取消/失败、纯paused/保留编辑器和正式编辑正文清理、源Entry保留/过期局部提示共4/4PASS。
- 原生UI分轮：focused-ui=1PASS/2FAIL（Weekly当前/历史通过；Weight保存后列表重载返回顶部，mixed新44pt几何为43.99999999999997）。focused-ui2=1PASS/1FAIL（mixed默认/真实中文Dark最大AX通过；Weight返回列表后一部分可见行的tap被滚动消费）。focused-ui3=2PASS/2FAIL：Weight no-op/日期-only/1000/重启精度85.585秒PASS、Sleep反馈收起+原CRUD57.208秒PASS；mixed中文Growth手势在滚动条区域往返未收敛；ImportantDay默认未开启提醒，不应期待提醒反馈。业务断言保留，进一步修正手势/实际合法起点，不将失败抹成产品PASS。
- 编译失败也保留：red-c-build参数顺序；green-c-build首轮类型推断诊断，拆出既有Picker绑定后暴露保存路径提取时取消分支可见性误改，已恢复原discard语义；BV01 instrumentation需明确MainActor；focused-green-build2补强测试遗漏try。相应后续build分别成功，未混称首轮通过。

Weekly加强回归已覆盖2026-10-18、跨年2027-01-03、春/秋DST周日，正式CheckIn→重开→Weekly/Habit analytics/QuietWins同源1日2次、Undo及缺metadata既有回退；三类未来事实同asOf、真实带图Entry/Tag、时间推进纳入、实际编辑删除刷新及只读不写。View显式所选周ID不随切区重选，使用环境时区与实际当前截止，闲置页面亦推进截止。所有旧schema/transfer版本保持。

SR01～07、BV01/02均有实现候选与区分证据，但最终完整Unit、关键UI组合、固定干净SHA Debug/unsigned Release/实包、独立未写实现reviewer及普通push仍未完成，因此保持FIXES_IN_PROGRESS。D1–D4、AlarmKit正向、Share/Safari、物理低空间、CI旧未通过状态不变。


### 收敛候选与集中门入口

pre-final-unit新增五项5/5PASS：局部规则问题+真实旧native请求取消未确认仍保留global重查，确认后才回局部待纠正；真正损坏事件证据仍阻止安排（仅明确注入的负向保护，不声称合法操作造坏库）；显式0/-1/7/366完整override/skip/reopen/generation/Stop/list；偏好已变而onChange尚未提交时旧结果仍不回写；Growth批量失效保守刷新。pre-final-ui扩展mixed默认/中文真Dark最大AX完整行、直接打卡、周/月真实导航1/1PASS（142.271秒）。ImportantDay反馈按More settings实际开启提醒后，focused-ui5该方法PASS；默认无提醒不显示该反馈的旧前提错误不改产品。

focused-ui4=1PASS/2FAIL：最新Weekly当前/历史15秒内组合PASS，mixed周行未移入视口、ImportantDay未展开More settings；focused-ui5=1PASS/1FAIL：ImportantDay40.825秒PASS，mixed细拖仍未移动离屏行。pre-final-ui采用标准滚动先移入离屏目标、再微调已可见部分，保留完整可见/44pt/计数与导航断言，实际通过。全部失败仍在原始xcresult与机器摘要。

最终集中门从下一个干净产品/测试提交开始：一次完整PersonalGrowthOSTests、一组有范围的关键UI、有效Debug build-for-testing、unsigned generic iOS Release与App/Share/Widget/provenance/AlarmKit实包；然后未编写本轮实现的reviewer独立先列反例再核对本机证据。当前仅候选提交，不标READY，不以阶段结果替代集中门。最后追加的每日/每周设置明确off/relaunch原生UI将纳入该组合；系统授权/晚错仍按Unit协议和设备门分层说明。


## 2026-10-19 系统整改最终交付 — READY_FOR_OWNER_DEVICE_GATE

SYSTEM_FIX_GOAL_SHA `3dad3b04e3ff703c2e799899035285f64a5976a4`；最终干净产品/测试 SHA `c55dc10fde79f1fe4dec18b03195119c2049830f`；完整Unit与首轮关键UI在干净 `00b65b70d988ef26455d719ccf35eda61233120a` 执行。c55相对00b只改三个UI方法的驱动，全部生产/Unit blob与18个复用UI方法逐项相同。本节记录本地处置、集中门和独立终审后的最终证据。SR01～07关闭、BV01/02完成有界处置，必要本地门和未写实现reviewer终审通过，恢复READY_FOR_OWNER_DEVICE_GATE。旧失败轮次和SYSTEM_REVIEW原文保留。

### 最终消费者与合法状态覆盖

| 项/结论 | 最终不变量与同因处理 | 实际消费者/状态及证据 |
| --- | --- | --- |
| SR-01 CLOSED | stopped 不再推导未来策略；delete/stop/list/default Edit 不受旧 nil 阻断。active 不可恢复仅局部待纠正，真实结构错误仍全局保守；未确认取消优先保留重查 | TodoTaskService 所有 offset 调用者、完整 TodoReminderCoordinator/intent/shared budget。真实原始V11、旧f1覆盖nil、根删除/多期兄弟/源Entry、Stop→切区→默认改标题/备注/关提醒/清单解绑、回滚/磁盘重开/ZIP恢复；显式0/-1/7/366代次、skip/reopen/Stop；ImportExportRecoveryTests 的5个 testSystemSR01* 与 TodoFoundationTests/testSystemSR01ExplicitZeroLeadAndLargerOffsetsKeepOverrideGenerationAndTermination；UI Stop/restart、清单delete/default编辑、过期future reset保护 |
| SR-02 CLOSED | 编辑表达无分组且Double往返，展示精度独立；不修写历史值 | WeightEditorView→WeightRules→WeightRecordService→磁盘；en_US/zh_CN/de_DE、1000/72.345/65.2、no-op/日期-only/实际改值/混合拒绝；WeightFoundationTests/testSystemSR02EditorRoundTripPreservesExactWeightAcrossLocalesAndDisk + 实际UI冷启重开 |
| SR-03 CLOSED | 同一实际asOf截 Entry/Habit/Weight；Habit按保存业务日；所选周与截止时钟分离 | WeeklySummary 全派生/RecentEntries/TopTags/详情；Habit analytics/QuietWins 的保存metadata；真实Service跨LA周日→上海、跨年/DST、1日2次、Undo、缺metadata沿既有fallback且只读不写；未来带图Tag Entry/五分钟容差Habit/Weight时钟推进、编辑删除；WeeklyReviewFoundationTests/testSystemSR03* 两项 + 本周/历史周UI。QuietWins对缺metadata的原信任边界不被外推成新相同回退 |
| SR-04 CLOSED | MainActor不阻塞等发布锁；保留源库/媒体互斥；排队最终checkpoint读最新权威状态 | StorePublication同锁：Investment全mutation、Workspace.scenePhase checkpoint、ImportantDay save/createEntry/delete；import/export/share worker可等待。真实export barrier→MainActor probe先于release→最终120秒/导出60秒；pause/finish晚请求不覆写；完成/取消/失败/paused/保留editor重试与无关context草稿；InvestmentPersistenceTests/testSystemSR04* 三项 + 全类原计时/进程/回滚保护 |
| SR-05 CLOSED | 被替代或取消的旧success/CancellationError/普通error均不回写；当前真失败仍反馈 | AppShell每日/每周实际快照→ReminderSettingsUpdate→LocalReminderScheduler共享gate→结果回流；A addRepeating挂起→B off/on及M2/weekday→A所有晚返回，onChange未提交的新偏好亦保护；ImportantDayReminderTests/testSystemSR05* 两项；正常明确off/relaunch UI。不冒称系统原生晚错已捕获 |
| SR-06 CLOSED | 仅成功保存移除Workspace finished editor；持久saved操作幂等证据保留 | 新manual/timer均连续3次、正式edit擦临时正文、Keep draft/失败/其他草稿保留；InvestmentPersistenceTests/testSystemSR06SuccessfulEditorsReleaseWithoutErasingDurableEvidenceOrOtherDrafts；timer双层退出Hub、manual/edit/delete、失败/重试、CR04/Record独立草稿/外部多段UI与F5真实读取保护 |
| SR-07 CLOSED | 同语义图标/文字列、44pt动作及自然行高；反馈收起不改事实；体重文案用所选截止日 | Today四习惯变体直接打卡/周月详情；mixed Today/Growth默认及真实中文Dark最大AX；Sleep/ImportantDay Got it后原CRUD/related Entry；Weight历史截止UI与本地en/zh资源核对。实际VoiceOver仍属D4 |
| BV-01 CONFIRMED_AND_FIXED | 仅跳过明确InvestmentOperation/Session持久标识写入；未知/批量/活动/正式事实保守失效 | Growth真实UIHostingController+Tab挂载，10k Weight+10k Sleep，实际Service草稿/正常checkpoint，可见/切离原各2次fetch、读Weight20000/Sleep20000；修复后两状态0。真实Weight新增删除/活动metadata及批量事件继续刷新；AppCompositionTests/testSystemBV01MountedGrowthActualReadsOnInvestmentSavesVisibleAndHiddenProbe。未以任意耗时阈值声称卡顿 |
| BV-02 CONFIRMED_AND_FIXED | 普通/带心得Service写入前拒绝非有限quantity；旧异常不删改、不漏事实伪称完整备份 | 原探针inf/1e999落盘inf并使JSON失败，NaN被SQLite归一为nil，finite成功；输入Double→Service→磁盘→实际ZIP恢复，旧inf普通export明确typed失败→单独raw支持恢复包提取SQLite保留ID/bitPattern/unit/result。ImportExportRecoveryTests/testSystemBV02* 两项。raw包不是普通备份，不能恢复过去已丢NaN或weight精度 |

所有新增测试通过实际生产Service/Workspace/reader/设置结果边界；主库、历史Schema V1–V15与既有v11传输版本保持，不传活ModelContext跨actor。旧R/F/CR中适合Unit的取消/满队列/停止负例/真实旧nil/媒体失败/恢复/计时/F5保护由本轮完整Unit执行；原生环境项目继续按未通过边界记录。

### 集中门真实分轮与复用

- final-debug1：00b65b70 / clean，Debug Simulator build-for-testing，exit0；final-unit1：同SHA一次完整PersonalGrowthOSTests，557=556PASS/0FAIL/1SKIP，exit0，49.545秒。唯一SKIP为TodoFoundationTests/testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure（需要独立32MB HFS+镜像；不填满主盘）。runtimeWarnings=[]。
- final-ui1：同00b clean，实际21=18PASS/3FAIL/0SKIP，exit65，1325.8秒。Todo行被未收起反馈栏覆盖；ImportantDay开关被导航栏覆盖，坐标点击误命中Save（录屏19秒和21秒帧/实际AX层级证明）；中文Investment历史寻找session时居中滑动拨动DatePicker，选到六月而无当前期记录。不是以预期数量或事后解释改写成绿。两轮合计95张PNG及原始失败视频/层级等179项附件均有路径/命名与SHA256映射。
- c55dc10只修三个UI方法：显式收起Todo反馈后进入详情并等待、ImportantDay整行避开导航/键盘后切换并保留value=1断言、Investment寻找历史行采用既有避开滚轮的侧边手势；没有削弱完成/skip/Stop/重启计数、reminder启用/反馈/关联Entry、分段保留/交互取消/显式替换/冷启统计等原断言。
- final-debug2：c55 clean，Debug build-for-testing PASS/exit0。final-ui2：同c55，三个失败方法完整补验+相邻拒绝授权反馈收起，4/4PASS，exit0；各体43.505、16.631、41.187、169.945秒，runtimeWarnings=[]。不能把两轮拼称一次21项全绿。
- final-evidence-reuse-proof.json：00b→c55仅三个UI文件变化；生产和Unit全部源码blob未变，首轮18个PASS方法原文哈希相同。完整Unit和这18个UI结果按同源复用；未为测试驱动或Markdown重复完整Unit。最终Debug/Release仍固定完整c55 provenance。

环境：macOS27.0.1(26A434)，Xcode27.1(27A9275)、iOS SDK27.1；专用iPhone18Pro模拟器PGOS-UsageRemediation-20261017 / 42609456-859D-41F8-8977-4B2D85A74082 / iOS27.0(24A434)。Xcode/模拟器操作串行；中文Dark通过simctl实际appearance驱动与截图同时核对。各case的en_US/zh_CN与Weight Unit的de_DE、固定业务时钟/区由测试源码和日志核对，未换host日期。

本机原始根 `/tmp/pgos-pr13-system-evidence`；同名.log/.json/.xcresult和-summary.json保留真实命令、完整SHA、dirty、退出码、计数、原错与hash。最终截图人工抽查默认Growth全列表、周/月/多次习惯中文Dark最大AX、CR05 Hub、历史周日、ImportantDay完整开关与分段两选择/重开统计；查看的是实际像素，最大AX按自然滚动多屏检查。未声称看过全部95张或实际VoiceOver。原始文件本机可读不等于远端CI/reviewer已读；独立reviewer实际访问范围另由其原文说明。

### 最终实包

c55干净候选的final-debug2/unsigned generic iOS final-release1均exit0；Release42.500秒。实际App `com.yocruzer.PersonalGrowthOS`、Share `.ShareExtension`、Widget `.ImportantDaysWidget`均1.0(7)/minOS17.0；Debug和Release App provenance完整c55/Dirty=false/Source=localGit/Tag空。两个实际Mach-O确认LC_LOAD_WEAK_DYLIB AlarmKit，中英文InfoPlist用途说明均存在。Release App executable SHA256 `aab2e40436080a78176068fe99c84113f8f959cf5964945071db712719c55be8`，Debug实际业务dylib `07be5c9f6284a93ef06ec288f3e33fac189977c4f3cd7d7a8bfb28227a70e3de`；完整三包各SHA见机器摘要及本机proof。

历史Schema/PersistenceFoundation、TransferModels、ZIPArchive、project.pbxproj与固定Goal blob一致。没有新增schema/依赖/备份版本/发行流程；后续只有文档与机器证据摘要时不重建该产品。

### 本轮实际测试运行索引（不是单一合并结果）

| 运行 | source HEAD/dirty | exit | 实际 total/PASS/FAIL/SKIP | log SHA256 |
| --- | --- | --- | --- | --- |
| red-a | 3dad3b04e3ff/dirty | 65 | 3/1/2/0 | `780742164199f051d5d1be5b2e903b4bdd58f6486de52c37456e39d08807196c` |
| red-b | 3dad3b04e3ff/dirty | 65 | 4/2/2/0 | `68b8832a0f5cbea763251c2e820851e82badd23fa3a09b882c7a7732cece34c8` |
| green-a | 3dad3b04e3ff/dirty | 0 | 6/6/0/0 | `4cf0a201cac5848887fa7c7c3a6a7de4ca147b8e695be1bf208e9fa07c1f5ef5` |
| red-c | 3dad3b04e3ff/dirty | 65 | 1/0/1/0 | `a430ba580cd9bc90ef5a7d1e95ed976e006486e137862f0d66f515d5f8f65ac1` |
| green-c | 3dad3b04e3ff/dirty | 0 | 2/2/0/0 | `fc035e07f64c72afd082afc47fd173cc790e07384c19a9a1bd4525fb0f4dfbd5` |
| bv01-probe | 3dad3b04e3ff/dirty | 0 | 1/1/0/0 | `2d7c38c84a0d7b3d43014ca48892639ffc581898b4f34c6132d166fdaaf0d485` |
| green-d | 3dad3b04e3ff/dirty | 0 | 5/5/0/0 | `33bc03fa394ec1296c4e86b468f86bf472b1374e84e678892e8559a4f4c23ac6` |
| green-e | 3dad3b04e3ff/dirty | 65 | 5/4/1/0 | `147e64826d55e1894ce8e4909f182f6e96bbe55f337a4a6408a530d797caff71` |
| focused-ui | 3dad3b04e3ff/dirty | 65 | 3/1/2/0 | `c589b713a3f637efdffd81897efbf69bed496534e715fe8680f6d7d44cf1dbb9` |
| focused-green | 3dad3b04e3ff/dirty | 0 | 7/7/0/0 | `c2fb9e758704ed45098b1c564031ad54cb09385c0f5c2644d7ba1789a296683a` |
| focused-ui2 | 3dad3b04e3ff/dirty | 65 | 2/1/1/0 | `a5b9437686f8e3ac0cb9484b90c3e0fc60e9c2853e587ffaffe63c6cb7de6c82` |
| focused-green2 | 3dad3b04e3ff/dirty | 0 | 4/4/0/0 | `b11a1f6d64f558d3b38a3fbeff597be5784903b09c9baa3661cb7f35967e48fd` |
| focused-ui3 | 3dad3b04e3ff/dirty | 65 | 4/2/2/0 | `b851bd28e9dd18696435119d8d69a029c987023a842b86fb8ce5fa9506638767` |
| focused-ui4 | 3dad3b04e3ff/dirty | 65 | 3/1/2/0 | `fe4b63bb9f5a477211c41a7451c9dab4d838e60ebd1eab670d12ac34251c9a4d` |
| focused-ui5 | 3dad3b04e3ff/dirty | 65 | 2/1/1/0 | `bd7ce88d6f30a01ca0362b34c40a4745f4d1c0ab9b5e4317fea5c93a3ea3a620` |
| pre-final-unit | 3dad3b04e3ff/dirty | 0 | 5/5/0/0 | `90d855b64bc9a0f11a99e4f6c2f9728e6682d8621d0333e1ebda24465258256a` |
| pre-final-ui | 3dad3b04e3ff/dirty | 0 | 1/1/0/0 | `b91ae52df8d1758c5dcfee8ad139e28d54da705253cd8beaf72c5711283e9737` |
| final-unit1 | 00b65b70d988/clean | 0 | 557/556/0/1 | `66f23b9ec16027b807c6ebdb45e15e5e0aa8e731e3b8ff7c4f78c931aad99400` |
| final-ui1 | 00b65b70d988/clean | 65 | 21/18/3/0 | `bdf2e73c4c221a76c8d242e6c5408c5757238e312cbae7a61769d53008461c6f` |
| final-ui2 | c55dc10fde79/clean | 0 | 4/4/0/0 | `f5b10a9cc7aca004ba08e62345c3f2c1931b1a9a254273412e8e2d2a97e8161c` |

所有build失败也保留于机器摘要；没有测试体的编译失败不伪造测试FAIL数。green-e的1FAIL为真实host crash；原始ips在green-e-crash.ips，诊断导出green-e-diagnostics，修复后的受影响组合与完整Unit才作为通过依据。

### 独立终审、完成审计与交付边界

Reviewer `/root/pr13_system_independent_reviewer` 未写本轮实现，先独立反例再读实现者说明，实际核对完整相关链、108个record/log/summary哈希、179个附件哈希、直接xcresult摘要、19代表图/原失败帧、Debug/Release实际plist/Mach-O/各executable+dylib。预登记和终审原文已完整追加REVIEW，SHA256分别 `785a144529913ed867f71a6d888d9e5cbbf6f13b84f902c6adc2cd66bcba9404` / `97a2b772840552d3ae5f56d34f2017c5332f10d4d4ebd5ddf5a124897ca5f469`。审查未发现本轮范围内未关闭confirmed P0/P1/P2，明确P3 SR06/07收尾完成；没有新增需要Xcode反证的confirmed问题，因此不重复扩大测试。

SR01～07及BV01/02逐项处置、全部相关消费者/代表合法状态、真旧数据/回滚/重开/ZIP、集中完整Unit/关键UI、固定干净产品SHA双构建/实包及独立终审均已有证据。恢复READY_FOR_OWNER_DEVICE_GATE仅代表本地批次完成；原D1–D4 NOT_PASSED、AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、远端CI NOT_RUN保持。未签名安装、不卸载升级、私人设备/库、merge/force push/tag/Archive/TestFlight均不在本批执行。

交付前fetch确认远端仍3dad3b04、base5a70f011、PR13 OPEN Draft、statusCheckRollup=[]，没有后续并发提交被覆盖。沿原分支普通push，不发PR外部评论/消息，不改base或另开PR。最终产品/测试c55dc10与之后仅文档交付SHA分开，交付SHA以实际commit/PR head和本机final-delivery-proof.json确认；主工作区d72c016及原三项未知改动保留。文档变化无需重建同产品。
