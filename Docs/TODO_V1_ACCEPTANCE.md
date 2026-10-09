# Todo V1 验收与真机交接

本文件对应 Owner Goal Pack Rev2 的 A1–A25/P1–P8。自动验证环境：主力本机 macOS 27.0.1，Xcode 27.0 (27A266a)，iPhone 18 Pro / iOS 27.0 Simulator (24A434)，UDID FD666264-A2DF-445C-A77D-534B9E8ED595。只有合成 UI/测试库与只读冻结 fixture；未触碰 Owner 私人库。

最终产品/测试提交：837b619e5f2d6a0367aa31d61e3829acf731b4e4。最终 HEAD/PR、集中 counts 和完整命令见 TODO_V1_EXECUTION_LOG.md；后续仅文档变化不冒称重新执行全量测试。旧 511 中英字符串逐项保持，新增 104 条，总 615；冻结历史实体/fixture、五 Tab、Share Extension、签名/App Group、Version/Build 保持原样。SwiftData V11 / 备份 v7，旧 App 不能读新 v7 包。

## 验收矩阵

“自动通过”指表中明确范围，不代表 Owner 真机、发行或通知实际送达。F = TodoFoundationTests，R = TodoReminderTests，I = ImportExportRecoveryTests，UI = AppLaunchSmokeTests。

| 编号 | 结论与证据 |
| --- | --- |
| A1 | 自动通过：F.testUndatedMultilineInputIsPreservedAndStateHistoryUsesRealClock / testTaskPersistsAcrossReopenWithEventsAndSeries；UI.testTodoQuickContinuousInputCompletionStatisticsSearchAndRestart。无日期不进 Today，All 可见，重开保留。 |
| A2 | 自动通过：F 的原文/空输入校验，global search；中文实际最大字体 UI 保留长标题与 emoji，空标题禁存，连续保存不自动拆分。 |
| A3 | 自动通过：F.testCivilDayFiltersSeparatePlanFromHardDeadlineAcrossTimeZones；独立 plan/deadline，Today/Upcoming/硬逾期正负配对。 |
| A4 | 自动通过：F.testStatisticsAndStableImportantOrderUseFinalFactsAtDayAndWeekBoundaries + 持久化重开。排序 important→最早日期→创建时间→UUID。 |
| A5 | 自动通过：F 状态/真实回拨/事件链测试与 UI 完成→重开→取消→搜索→重启。同一次 save 保存状态和事件，保存失败 rollback。 |
| A6 | 自动通过：F.testGlobalSearchIncludesEveryTaskStateWithoutChangingEntryFollowUpResults；Todo UI 与旧 Entry/Tag/Review/补充搜索关键回归。 |
| A7 | 自动通过：R.testCreateReplaceCompleteReopenCancelDeleteAndNoOtherCategoryRemoval；稳定 Todo UUID 前缀替换/清除，绝不移除旧每日/每周请求。系统 pending 确认后才标 scheduled。实际送达 OWNER_REQUIRED。 |
| A8 | 自动通过：R 权限 notDetermined/denied/error/add failure/queue full 配对；持久化仍保留，UI 提示可重试。真实拒绝与系统设置 OWNER_REQUIRED。 |
| A9 | 自动通过：F 跨日、周一、时区、DST gap/overlap；R 冷启动/并发协调；重复 UI 重启。Todo 没有运行时网络依赖。真实飞行模式/旅行/系统时钟跳变 OWNER_REQUIRED。 |
| A10 | 自动通过：F 当前最终态与日/周统计配对；UI 连续输入明确 Open=2（两个不同任务）且 drill-down 对应；清单 count=1、重复测试重启 count=2。四项数字均进入同一 TodoQuery 筛选。 |
| A11 | 自动通过：精确 c5a3c0ac 源码生成真实 V10 sqlite/图片/v6 ZIP；F.testExactBuild12V10FixtureMigratesAndReopensPreservingAllOldFactsAndMedia 完整字段/ID/media 比对、两次打开及新增 Todo；原 exact V7/V8 回归。Owner 私人 Build 12 覆盖升级 NOT_RUN。 |
| A12 | 自动通过：I.testTodoV7RoundTripPreservesOccurrencesEventsListsSourcesAndOriginalMedia、合法 v1–v6/冻结 v6、缺键/空键/未知状态/坏日/悬挂/重复/坏锚点/错误最终事实拒绝；13种坏 Todo 包逐项精确 invalidObject 断言（含 Int.max revision，不溢出）。导出→预览→恢复→重开→重导 JSON equality/media 原字节。 |
| A13 | 自动通过：Todo-only/list-only 非空保护、afterPreflight 并发新增拒绝且重开保留；beforeSave failure/cancellation 五实体/图片回滚；export cutoff 后新增与完成不污染 immutable snapshot。保留原恢复/共享锁安全测试。 |
| A14 | 自动通过：五 Tab 断言与 Today 首屏、Habit/Weight/Goal/WeeklyReview/Record 关键 UI；Todo 仅导航栏 Hub/快捷新增，不增加首屏长清单。真机视野 OWNER_REQUIRED。 |
| A15 | 自动通过：中文 Dark + 真实 AX maximum 原生字号、title 高度独立断言、Editor/Hub/About keepAlways 截图与语义审计；英文常规流程。长标题可滚动，短 SHA 完整可点。真机 VoiceOver 实际朗读 NOT_RUN。 |
| A16 | 已明确分界：本机 Unit/UI/fixture/产物证据已记录；Owner 私人数据、硬件、真机通知和实际云端发行不冒称通过。 |
| A17 | 自动通过：F.testFixedAnchorsDoNotDriftAndDSTReminderIsExplicit / 重复墙钟时区测试；每日/周/月/年、31日短月恢复、2/29 非闰年与闰年恢复。每日原生 UI 贯通。 |
| A18 | 自动通过：F.testRecurrenceCompleteRetryUndoSkipAndStopPreserveOccurrenceIdentity；同身份 create retry、complete retry、undo 撤回/复用后继、skip retry、stop/reopen；UI 每日完成/skip/stop/restart。每系列最多一个 Open，已完成历史不复活。 |
| A19 | 自动通过：F 来源/清单安全删除与 UI 新建→改名 sheet→归属→筛选→确认删除→未分类仍在。默认可不选清单。 |
| A20 | 自动通过：UI.testTodoEntrySourceKeepsOriginalRecord 回到源 Entry；F 删除双方配对与原 Entry 文本/技术时间断言。旧分享扩展/UI/receipt 路径保持。 |
| A21 | 自动通过：Today/Hub 一触新增、实际键盘聚焦、Save and Add Another 连录；F future/undated 筛选；Hub 提供 Upcoming/All。 |
| A22 | 自动通过：真实编译前脚本与实际 Debug/Release plist；local HEAD/dirty、CI_COMMIT 优先、invalid/stale fail。模拟 CI 标签/非标签产物同 SHA；实际 Xcode Cloud NOT_RUN。 |
| A23 | 自动通过：实际 Bundle Version/Build 分列，9 位 SHA，完整 40 位复制后在 Todo 输入框实际 Paste；标签条件显示，缺失未知由 reader/script 正负矩阵覆盖。双语/深色/最大字体可读。 |
| A24 | 自动通过：真实可执行 Debug/Release app 与唯一 appex，Release 资源核对，不在签名后注入；运行 reader 只读 Bundle，无运行时 git/网络。尚未 Archive/TestFlight。 |
| A25 | 自动通过：连续输入→完成/撤销/取消→搜索→重启，Entry 来源回溯，清单筛选删除，重复/真实权限弹窗/跳过停止，完整持久化备份往返。Owner 十分钟实际日常门禁如下。 |

## 构建来源 P1–P8

| 编号 | 证据与结论 |
| --- | --- |
| P1 | 模拟 CI_COMMIT=1286a8ff1ea61f7da277bf6803930c7d6984dadc / CI_TAG=todo-v1-ci-verification 的真实 Release 编译资源记录 Source=xcodeCloud、同 40 位 SHA、该标签；最终产品 837b619e5 的真实 Debug UI 也显示同一测试标签并复制对应完整 SHA（final-todo-ci-ui-1）。这是测试输入，未创建 Git 标签/发行。真实 Cloud tag workflow NOT_RUN。 |
| P2 | 同一 DerivedData 改为未提供 CI_TAG 后重建 Release，资源 Tag 为空，不残留前次标签；Commit 未改变。 |
| P3 | 干净本地 Release 资源记录 837b619e5f2d6a0367aa31d61e3829acf731b4e4、localGit、Dirty=false（final-product-release-local）；最终文档提交后另建本地 Debug 核对最终 HEAD。 |
| P4 | 真实构建脚本 clean/dirty/noGit/invalid/stale SHA/unsafe tag 合成矩阵通过；早期实际 dirty Debug UI 明示未提交；reader 无资源/非法值返回未知，不填旧 commit。无 Git 环境未单独运行整 App UI。 |
| P5 | 实际 App/appex Info 为 1.0(7)，不是 Owner 手机已安装 Build 12；Version、Build、Commit 分别读取，测试 Build12 也不改变 SHA。 |
| P6 | 英文 About 实际完整复制→Todo 粘贴；中文深色 AX maximum About 按钮完整可读/可点、40位 accessibilityValue、语义审计通过。Version 复制体验继续存在。 |
| P7 | 本机真实 Debug（测试运行）和 Release（unsigned Simulator app/appex）成功，实际 plist 对比输入；最终本地 Debug 与最终 HEAD 再核对。不是只测 helper。 |
| P8 | 旧 annotated tag→c5a3c0ac、外部分享分支/PR base 核查；原扩展/entitlements/signing/version/workflow 配置未改。未 merge/close/tag/Archive/TestFlight。 |

注入在 App target 的 Generate Build Provenance 阶段（Sources/Resources 之前），资源进入 DERIVED_FILE_DIR 再经正常资源拷贝。CI_COMMIT 合法且与可读取 checkout HEAD 一致才采纳；本地次之，缺失明确未知。Bundle 中的 SHA 对应源码提交，文档中的旧发行 c5a3c0ac 不作为生成常量。旧 Build 12 不会被新代码回溯修改。

## Owner 十分钟真机门禁

只在独立审查通过、Owner 另行授权并拿到包含本功能的真实签名构建后执行。本轮没有生成 TestFlight 安装包。测试前保留现有备份，不删除或清空私人库；恢复只在另一个独立空测试库/设备执行。

1. **0–1 分钟**：覆盖安装后核对原 Entry/图片、习惯、体重、Goal、WeeklyReview、分享来源和五 Tab；设置→关于抄 Version/Build/短 SHA，复制完整 SHA 与本次发布源码比对，真实 Tag 有则显示。
2. **1–3 分钟**：Today 新增“买电池 🔋”，不选日期；连续再录一条带备注的任务。All 找到前者，设明天计划后 Upcoming 可见；独立截止设昨日时才显示硬逾期。编辑/重要/清单选择都可保存。
3. **3–4 分钟**：完成→撤销→取消→重开；今日/本周/Open/硬逾期数字点进明细一一核对。全局搜索已完成/取消任务及旧 Entry/补充。
4. **4–5 分钟**：建“生活”清单、改名、按清单查看；确认删除清单后任务仍在未分类。已有 Entry 主动生成 Todo 并回到来源，原文与时间不改变。
5. **5–7 分钟**：设每天或每月重复，完成后只有一个未来期次；撤销/再完成不重复建；跳过当期后仍有下一期，停止系列后保留历史。关闭 App 重开核对 ID/数量与状态。
6. **7–9 分钟**：给测试任务设置约一分钟后的提醒，首次权限交互；锁屏实际接收。改时/完成后旧通知不再待发。另核对拒绝权限时的真实提示与 iOS 设置返回后的协调；确认旧每日/每周提醒设置保持。
7. **9–10 分钟**：开飞行模式，新增/编辑/完成/搜索后退出重开；中文深色/最大字号能滚动并复制 SHA，VoiceOver 能读按钮含义。准备一次新 v7 备份；另在独立空库验证恢复（可作为额外的数据门禁，不在私人非空库执行）。

回报模板：真实 Version / Build / 完整 SHA / Tag；设备/iOS；哪个步骤失败与可复现操作。Owner 真实旧库、通知实际触达、签名/App Group、实际 Cloud 发布与 VoiceOver 均为 OWNER_DEVICE_GATE。模拟器通过不能代替这些结论。

## 剩余边界

已普通推送并创建独立 [Draft PR #8](https://github.com/yoCruzer/PersonalGrowthOS/pull/8)，停在 READY_FOR_INDEPENDENT_REVIEW，下一步需要独立 Review，重点 V11/事件真相、重复期次撤销、v7 时间精度/恢复与通知并发。远端没有配置 GitHub Actions；普通 push 后检查为空，不能写“远端 CI 通过”。没有新增云端服务、付费依赖、复杂 RRULE、子任务或自动从分享生成 Todo。


## 本轮 ReviewFix + Usability 验收（进行中）

本轮起点4625602…，Owner新批准六项统一Goal。历史矩阵仍为原轮证据，新增工作必须由本轮结果证明。

| 项目 | 当前可复查证据与边界 |
| --- | --- |
| S1-A | 原代码正负回归s1-red真实FAIL；修复后短月/每月10日/31日/闰年/年度/DST gap与overlap/纽约↔上海、候选原V11迁移重开通过，s1-target-4 Unit；相对日v7往返与±366非法包拒绝在s1-supplement-5通过。计划锚点优先，不因本期改日期漂移。 |
| S1-B | 原Open后继同步回归s1-red真实FAIL；s1-target-4证明future覆盖单独编辑模板、this-only不覆盖、身份/日期保留、失败回滚、withdrawn复用与Canceled历史不复活。同步字段标题/备注/重要/清单/提醒，UI明确覆盖策略。 |
| S1-C | s1-target-4通知mock证明延迟中checking与已保存事实分开、权限/队列/调度错误可见、旧类别请求不移除；拒绝提示真实UI在s1-supplement-5通过。布局导航修复补验进行中；真实通知送达仍Owner门禁。 |
| S1-D | s1-target-4损坏revision/事件链synthetic库：pre-open原SQLite byte equality、原始媒体byte equality、rawZIP提取后可开原库/原Entry但依然拒绝损坏Todo；启动UI复制诊断/准备ShareLink/retry/重启均通过，普通AppShell不加载。rawZIP是支持恢复包，不能当正常备份导入；不清库/修复。 |
| S2 | 尚未开始实现；须证明Open单次原身份转换、关闭态拒绝、首日必选、事件历史/保存回滚/幂等/重启/v7往返/真实UI。 |
| S3 | 尚未开始实现；须证明默认Open、三类全状态/各单态、清单/关键词/日期组合、四统计严格同数字、深色/大字体与双语。 |

新候选存储为V11 11.1.0，有冻结11.0.0节点和exact candidate fixture；备份仍v7新增optional offset。s1-target-4共80 Unit+1 UI PASS/1 UI FAIL（exit65）；后续补验不改写失败整组。完整Unit与集中UI/Debug/Release留到S4冻结候选一次执行。
