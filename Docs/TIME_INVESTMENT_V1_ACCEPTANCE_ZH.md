# 时间投入 V1 F1/P1 — READY_FOR_OWNER_DEVICE_GATE（2026-10-18）

沿原 `codex/time-investment-v1` / [OPEN Draft PR #12](https://github.com/yoCruzer/PersonalGrowthOS/pull/12) 续接；固定审查输入 `b55da139642a174e71d3ce79c34fd2c55eaa4d39` 的[外部 F1/P1](https://github.com/yoCruzer/PersonalGrowthOS/pull/12#pullrequestreview-5558558045)已完成反例、限定修复和真正独立只读复核。原外部 R1–R3 已关闭，本轮仅回归。BASE `ad0720ad743f495ac6f2ee3e97b16577266351db`、Goal1.1 `72ee8bdf954a5628806db867682a6b021e63545b` 不变。

最终产品/测试与最后生产 **`4d59a5909ec4314d82c9f9af12c203503ffde98b`**。生产 `current()` 改用包含设备睡眠的 `ContinuousClock` 进程相对秒数，经同一采样接缝进入实际服务；新 `continuous-v1:` 随机进程标识隔离旧 awake 锚点，旧 `anchorUptime` 编码键不改。50ms/18h保护、暂停不累计、倒计时封顶与显式继续、真实壁钟跳变、跨进程/重启待确认及备份只保留可信检查点均保持。Workspace 只加默认 current 的测试注入，AppShell 真实调用不变；无后台常驻、Schema或签名变更。

修复前 clean `0eea42a` 十项原生反例 **1 PASS / 9 FAIL / 0 SKIP，exit65**；暂停对照通过，服务、落盘和实际 ZIP 复现旧120秒而非1920秒或1500秒。九个失败方法不等于九个纯睡眠反例：也含新 token、来源/非有限/回退读数断言；原log有58条断言/抛错失败，含微漂移恢复后零值验证的1个unexpected invalid，全部保留。GREEN clean `4d59a59` 核心29＋磁盘24 **53/53 PASS**；另一轮正确 ImportExport55 **55/55 PASS**；四项真实前后台/冷启动/R2/R3 UI **4/4 PASS**，各exit0，分轮不拼为一次全绿。Unit两轮无runtime warning，UI保留3条 Invalid frame warning。

复用历史完整 Unit：`d5db223` 实际467项 **466 PASS / 0 FAIL / 1 SKIP**；当轮额外AX UI使总468项仍FAIL。没有宣称本轮重跑完整Unit。40份其他旧Unit/fixture blob相同，两份Investment测试扩展且整类重跑；本轮全部受影响消费者及真实ZIP/回滚、历史V14迁移、跨日/DST已补验，独立Reviewer认可影响矩阵。旧中文Dark最大AX/相邻Record/Files ZIP等未改路径证据按下方固定提交复用。

Debug build-for-testing `compile2`、unsigned generic iOS Release `release1` **PASS/exit0**；六实际App/Share/Widget包保留原身份1.0(7)，两App provenance均clean同完整4d59 SHA/localGit/Tag空。Xcode27.1/27A9275只读首检exit0，既有专用模拟器/iOS27.0可用；首次受限沙箱simctl访问失败与获准只读服务检查区分记录，无系统配置操作。新证据根 `/tmp/pgos-time-investment-f1-evidence`；`native-run-index.json` 保存完整命令、SHA、退出码、实际计数和日志哈希，原红测/旧证据不覆盖。

独立 Reviewer `/root/time_investment_reviewer` 只读核对固定红绿源码、生产链、原始日志/xcresult、实际截图和实包；范围内无尚未关闭 confirmed P0/P1/P2。**READY_FOR_OWNER_DEVICE_GATE 只表示本地批次完成，设备Gate未通过。** 真实iPhone锁屏/硬件睡眠、私人库覆盖、签名/安装、实际通知/桌面Widget/Photos/VoiceOver/飞行模式及远端独立CI（workflows=0）均 **NOT_RUN**；Safari unsigned **FAIL**、专用HFS+物理低空间 **SKIP/NOT_RUN**保持。不能用合成三读数或Simulator home/relaunch替代硬件睡眠。

最终产品/测试后交付仅五份交接Markdown变化，delivery SHA以原PR head和 `final-delivery-proof.json` 核对；普通push原分支/原Draft PR，旧PR与原workspace三项未知dirty保留。下一边界仅Owner另行授权设备验收：先独立备份和旧数据核对，再不卸载覆盖安装、锁屏/使用其他App后结束、晚返回倒计时、待确认重开、手工/跨日/回顾及相邻模块组合。未merge/force/tag/Archive/TestFlight，不进入新模块。

## F1 受影响验收矩阵

| 路径/对照 | 本轮真实证据 | 状态 |
| --- | --- | --- |
| T1/T2 正计时/倒计时睡眠 | 独立wall/continuous各+1800或3000，awake仅+30；1920/1500秒，显式继续再60=1560 | PASS，合成读数经生产sampler/service |
| 暂停、真实壁钟前跳/回拨、连续读数回退/非有限、进程/重启 | 保留120检查点，异常清锚点；暂停不累计；微漂移相邻span及18h边界 | PASS |
| T4/T10 磁盘检查点/故障/外部草稿 | Workspace真实事务→重开1920→保存两次只有一事实；beforeSave/actualSave后throw重试无重复，外部Entry不被保存 | PASS |
| T12 真实ZIP检查点 | 正/倒计时导出1920/1500，源完整snapshot不变；7天后导入仅可信值、待确认，显式继续才+60；落盘重开 | PASS |
| 旧awake锚点 | 真实旧裸UUID/awake320，与新进程域隔离；恢复120，显式resume才建立continuous200000；再睡眠后1920 | PASS |
| R1–R3、T6/T7/T14及相邻备份 | 整类29核心/24磁盘含原八持久反例、五历史schema与V13→V14、跨日/DST；另55导入导出 | PASS，分两轮 |
| 计时前后台/冷重开及R2/R3 UI | 原默认current；恢复待确认、冻结、草稿不入统计、R3重开25分钟/1条 | PASS，4项；3条warning |
| 历史完整Unit及中文Dark/AX/相邻Record/Files | 按下方固定SHA复用；本轮40其他Unit/fixture blob不变 | REUSED，不写本轮PASS计数 |
| 真实iPhone锁屏/硬件睡眠 | 没有设备运行/签名安装授权或实测 | NOT_RUN / OWNER_DEVICE_GATE |

本轮截图原图与manifest见 `ui1-attachments`；可见恢复仅建议可信检查点、冻结确认与重开统计25分钟/1条。冻结页native标题的省略显示未改变；未将其当F1新修复。Simulator前后台与合成读数覆盖各自层级，不能证明硬件深睡行为。

下方为先前交接原始历史，不覆盖上方当前结论。

---

# 时间投入 V1 F1/P1 — FIXES_IN_PROGRESS（2026-10-18）

本轮沿原 `codex/time-investment-v1` / [Draft PR #12](https://github.com/yoCruzer/PersonalGrowthOS/pull/12) 处理固定 `b55da139642a174e71d3ce79c34fd2c55eaa4d39` 的[完整外部复审 F1](https://github.com/yoCruzer/PersonalGrowthOS/pull/12#pullrequestreview-5558558045)。外部已关闭 R1–R3，本轮不重新扩修。`systemUptime` 不含设备睡眠，而当前 `projected` 将其与 wallDelta 比较后会持久化异常恢复状态；F1 关闭及本地门禁完成前，不能沿用下方历史 READY 结论。

只读基线确认任务树 clean b55da13、原 branch/upstream/PR base，原工作区三项未知 dirty 保留；Xcode27.1 首检及既有隔离模拟器可用。新证据根 `/tmp/pgos-time-investment-f1-evidence`，指定 review 原文已保存并完整读取。下一步是区分 wall/连续经过时间/awake uptime 的生产反例、限定连续时钟修复及核心/磁盘/导出/R1–R3回归、独立固定SHA复核。保留50ms异常保护、暂停/倒计时/跨进程及旧锚点/备份边界；不新增后台常驻或Schema。真实iPhone锁屏/硬件睡眠 NOT_RUN；Safari unsigned FAIL、物理低空间 SKIP、签名/私人库/远端CI NOT_RUN保持。不merge/force/tag/Archive/TestFlight。

下方是原始历史，原样保留。

---

# 时间投入 V1 外部 Review 修复 — READY_FOR_OWNER_DEVICE_GATE（2026-10-17）

固定外部审查 `92dc10a`，最终产品/测试 `2c5b4c52edbf69c1562ff9eae491616335b97472`，最后生产 `c91866e6abfef0241ae4ae266ee8f02f51f76393`。Goal1.1/BASE与原S1–S10/T1–T14产品边界不变。下方旧验收记录原样保留，本节是本轮限定修复验收；不混用同编号旧R1–R3。

| 外部问题 | 实际验收证据 | 当前结论 |
| --- | --- | --- |
| R1/P1 删除/丢弃仍留用户内容 | 真实磁盘独立container重开；新ZIP原始data.json负向标记＋decode；合法旧v10 ZIP导入/重导出；startup先原始完整性校验再清理；两linked draft的save前失败整快照不变、save后throw全部canonical/0fact；正常草稿/正式保存事实/其他参与者保留；原ID/新UUID旧编辑不能复活 | PASS，独立复核关闭；逻辑模型/新ZIP清除，技术tombstone保留；不声称取证擦除、不删除旧备份 |
| R2/P2 失败仍关闭导致输入丢失 | 实际Editor＋service注入beforeSave/actualSave后throw，输入与错误保留，完整身份/values/raw duration/编辑指针一致才幂等重试，不改既存revision/时间；更改输入仍冲突；真实UI后台返回/外层滑动不关闭/显式关闭失败仍在/重试后冷启动同备注 | PASS，最终Light同产物复验内层false未削弱外层；未落盘输入不承诺强杀存活 |
| R3/P2 多段20分钟被默认改25分钟 | 原20分钟两有效段＋5分钟暂停；request/取消/备注保存/磁盘重开/真实ZIP仍原段与20；baseline改变确认拒绝；明确确认才25/一段/corrected。真实中文Dark最大AX全文及两按钮可滚动，Keep与抓手关闭都20，再确认保存/冷启动统计25分钟1条；英文Light同路径往返 | PASS，独立复核关闭；原prototype系统框截字和各驱动失败保留 |

完整Unit在clean d5db223实际 **466 PASS / 0 FAIL / 1 SKIP（467项）**；同轮额外AXUI失败使整轮468项 **466 PASS/1 FAIL/1 SKIP**，保持FAIL。之后仅确认UI及驱动变化，42份Unit源/fixture相同、确认块外生产逐字同源，复用并补a722fe9核心23＋磁盘20 **43/43 PASS**。a722fe9相邻中文Record独立草稿AX **1/1 PASS**；最终f077598中文Dark最大AX **1/1 PASS**、英文Light R2/R3 **2/2 PASS**；不同轮次不相加成一次全绿。最终warning分别Dark 1、Light 2条Invalid frame，保留原始记录。原计时生命周期、后台/冷重开、统计、Files真实ZIP、历史五磁盘schema升级及相邻模块证据复用，见[执行](TIME_INVESTMENT_V1_EXECUTION.md)。

clean 2c5b4c5 Debug compile10、unsigned generic iOS release2 **PASS/exit0**；六实包原Bundle身份/1.0(7)、两App fullSHA clean localGit provenance核对；V14/v10、旧schema/原文案/项目与签名配置不变。独立Reviewer未发现范围内未关闭confirmed P0/P1/P2。最后仅五份交接Markdown，原Draft PR12普通push；delivery SHA见Git/PR与新证据根final-delivery-proof.json。

Safari unsigned **FAIL**；HFS+物理低空间 **SKIP/NOT_RUN**；真实设备/私人库/签名、实际通知/桌面Widget/Photos/VoiceOver/飞行模式及独立远端CI **NOT_RUN**。状态仅 **READY_FOR_OWNER_DEVICE_GATE**，设备Gate尚未通过。下一步只允许Owner另行授权的不卸载签名覆盖安装与组合设备验收；不merge/force/tag/Archive/TestFlight，不进入新产品范围。

最终 test-only `2c5b4c5` 另以 R3 已成功的同一顶部区域 `(.5,.09)→(.5,.95)` 补跑 R2（`final-dismiss1`）**1/1 PASS/exit0**，外层仍在、失败后输入/错误保留、重试关闭并真正冷启动同草稿；产品与 `c91866e` 完全相同。该补验另保留 1 条 Invalid frame，不把旧导航条拖动当作抓手保护实证。

---

# 时间投入 V1 外部 Review — FIXES_IN_PROGRESS（2026-10-17）

本轮按 Owner 新授权处理固定 `92dc10a47add519604546e597672af9afb87d10e` 的[外部 Review](https://github.com/yoCruzer/PersonalGrowthOS/pull/12#issuecomment-6234984209)，仅 R1/P1、R2/P2、R3/P2 及关联数据安全/可靠性。原 `codex/time-investment-v1` / Draft PR #12 与固定 Goal1.1/BASE 保持；真实独立只读 Reviewer 已确认三项。当前不能沿用旧 READY 结论，先补修复前反例，再限定修复、原生磁盘/ZIP/UI及独立复核。旧失败/警告/Safari unsigned FAIL、物理低空间 SKIP、真实设备/签名/CI NOT_RUN 保持。

新证据根 `/tmp/pgos-time-investment-review-fixes-evidence`；指定评论原文已完整读取并保存独立副本。原工作区三项未知dirty保留，任务工作树从clean92dc续接；不重建分支，不操作真实私人数据，不合并/tag/Archive/TestFlight。下方为前轮交付与历史原始记录，不代表本轮三项已关闭。

---

# 时间投入 V1 — READY_FOR_OWNER_DEVICE_GATE（2026-10-17）

固定 Goal 1.1：`72ee8bdf954a5628806db867682a6b021e63545b`；BASE：`ad0720ad743f495ac6f2ee3e97b16577266351db`。沿原 `codex/time-investment-v1` / [Draft PR #12](https://github.com/yoCruzer/PersonalGrowthOS/pull/12) 续接，base 保持 `codex/sleep-routine-v1`。最终产品/测试与最后生产提交均为 **`2ae01f3d2af2117a3f957ee6cd275d50e19b892d`**；之后交付只改六份Markdown（五份交接文档及INDEX一句状态指引）。delivery SHA 以 Git、远端 PR head 与本地 final-delivery-proof.json 为准，避免自引用。

本机 Xcode 27.1/27A9275、CoreSimulator 1174.9.2 已恢复；checkFirstLaunchStatus、可用设备和运行时列表 exit0。使用既有任务专用模拟器 `540825BC-D0D4-4D71-B8DF-D73B243C3726` / iOS 27.0，单一 Xcode 队列，仅合成数据。未执行 sudo、系统修复或删除模拟器。

## 当前原生证据

| Run / 固定编译提交 | 结果 | 覆盖及限制 |
| --- | --- | --- |
| native-affected2 / c84a680 | 98 PASS / 0 FAIL / 0 SKIP，exit0 | 完整 ImportExport55、新核心22/持久8、Sleep/ImportantDay/原始V11相邻迁移 |
| native-fullunit2 / 47fc0b2 | 454 PASS / 0 FAIL / 1 SKIP（455项），exit0 | 旧迁移收据 oracle 及真实 v7/v10 配对闭环；不是最终提交全测 |
| native-concentrated-ui1 / 47fc0b2 | 12 PASS / 2 FAIL / 0 SKIP（14项），exit65 | 五Tab、Record、Habit、Goal、Todo/Library、QuietWins、实际Files恢复、ImportantDay、Sleep/Weight、计时/统计；Safari URL提交交互失败，Widget缺外部driver失败均保留 |
| native-targeted-final1 / 473f456 | 12 PASS / 1 FAIL / 0 SKIP（13项），exit65 | 持久化10、真实running冷重开/手工草稿、实际两次URL路由通过；Safari进入扩展后缺App Group entitlement失败 |
| native-final-scope1 / af377f2 | 36 PASS / 0 FAIL / 0 SKIP，exit0 | 核心22/持久10/四UI；中文Dark最大AX按日与原时区贡献截图可读 |
| native-revision-red1 / 05f2c4a | 1 PASS / 1 FAIL / 0 SKIP，exit65 | T4真实磁盘提交前后故障通过；非法session/op Int.max包被接受，6断言失败，作为修复前红测保留 |
| **native-fullunit3 / 2ae01f3** | **458 PASS / 0 FAIL / 1 SKIP（459项），exit0** | 最终完整Unit；核心23、持久12、20类坏ZIP，revision所有写路径及显式双参与者汇总 |
| **native-final-ui1 / 2ae01f3** | **4 PASS / 0 FAIL / 0 SKIP，exit0** | 四项最终时间投入UI，覆盖计时/后台与两类冷重开、手工统计编辑删除、Record草稿、中文Dark最大AX |
| **native-light-final1 / 2ae01f3** | **1 PASS / 0 FAIL / 0 SKIP，exit0；1条duration聚焦Invalid frame** | 单独受控Light英文手工记录/统计/编辑删除UI，实际白底截图核验；不依据外观启动参数推定Light |
| testcompile23 / release3 / 2ae01f3 | PASS / exit0 | Debug Simulator及unsigned generic iOS；六实包原身份1.0(7)，两App clean同SHA provenance |

每轮准确命令、selector、原始.log/.xcresult及对应SHA见[执行记录](TIME_INVESTMENT_V1_EXECUTION.md)和 `/tmp/pgos-time-investment-evidence/native-run-index.json`。不将不同轮通过数累加成一次全绿。原环境exit70、迁移oracle失败、UI交互失败、R8按钮串触发、AX视觉失败和revision红测均保留。

## S1–S10 当前映射

| 门槛 | 真实生产路径 / 本地结论 | 保留边界 |
| --- | --- | --- |
| S1 | Growth/条件Today→Hub/Timer，start/command/saveTimer；最终四UI及23核心 PASS | 真实iPhone锁屏/硬件后台 NOT_RUN |
| S2 | AppShell生命周期checkpoint、不同process/单调时钟异常→复核；固定时钟原生及真实Home/kill/relaunch PASS | 所有系统回收、旅行/硬件重启 NOT_RUN |
| S3 | 目标封顶、显式继续、冻结pendingSave、幂等终态；核心/磁盘故障/四状态ZIP/冷启动确认 PASS | 真机倒计时晚返回留Owner |
| S4 | 独立EditorState/持久草稿，手工/可选反馈/区间降级/确认删除；原生磁盘、ZIP和UI PASS | 私人库真实输入 NOT_RUN |
| S5 | 惰性Participant、独立recorderID、显式participantID汇总；双参与者90/60秒、各1次/不同明细、未知ID空、越界活动拒绝 PASS | 本期无家庭UI；不由记录者代替参与者 |
| S6 | 原时区自然日分摊、Session去重、全部/7/30天、同页编辑30分钟/删除0刷新；Unit和UI PASS | 真实长期个人样本 NOT_RUN |
| S7 | 同库V14/v10、五历史磁盘直升、原收据/媒体、真实ZIP、回滚/竞态/20类坏包、Files入口 PASS | 专用HFS+真实低空间 SKIP；注入低空间已执行 |
| S8 | 五Tab/Record与相邻模块集中UI、外部导入27Unit、Widget真实URL路由 PASS；六实包原身份保持 | 当前 unsigned Safari **FAIL**；实际签名分享/桌面Widget/通知 NOT_RUN |
| S9 | 95新双语键、937旧键值不变；英文Light、中文Dark最大AX、日期轮/起止/回顾/贡献/详情截图及语义控件 PASS | 真实VoiceOver/单手硬件/飞行模式 NOT_RUN；计时无网络或通知授权依赖，无新增后台通知 |
| S10 | 最终Debug/unsigned Release与实包同源、真正独立只读复核、原Draft PR普通推送 | Owner设备Gate尚未通过；远端CI NOT_RUN（workflows=0） |

## T1–T14 当前映射

| 反例 | 原生真实路径 / 结果 |
| --- | --- |
| T1 | testT1PauseExcludesFiveMinutesAndDoesNotDependOnTicks：30分钟含暂停5分钟→有效1500秒 PASS；Home/activate暂停继续UI PASS；硬件锁屏 NOT_RUN |
| T2 | CountdownCapsAtTargetAndExplicitContinueOmitsLateGap / EarlyEndDoesNotFillTargetAndPausedTargetDoesNotRun PASS；固定时钟25分钟目标/50分钟晚返回，继续不补空白 |
| T3 | FinishRemainsFrozenAcrossConfirmationDelayAndNewService +真实关闭确认/继续再结束/冷启动保存 PASS |
| T4 | RepeatedStartFinishSaveAndDeletedCallbacksNeverResurrect、CommitBeforeAndAfterFailure、DiskCommitFailuresReopenAsPendingOrExactlyOneFactAndNeverSaveForeignDraft PASS；磁盘新container独立重开0或1事实、幂等重试、删除墓碑、不提交或撤销外部草稿 |
| T5 | DurationCorrectionDropsIntervalsButPreservesTimerOrigin 原生 PASS；手工45→30分钟UI及精确起止控件展开截图 PASS |
| T6 | CrossDayPauseAllocationAndCountUseOriginalZone：5/15分钟、总次数1 PASS；真实按日下钻、回顾切换/编辑刷新UI PASS |
| T7 | DST/闰日/自然窗、壁钟跳变/回拨/重启/跨process、原时区详情、零秒跨日均原生 PASS；真实设备旅行/回拨/硬件重启 NOT_RUN |
| T8 | TwoParticipantsAreIsolatedAndSameParticipantCannotDoubleStart 及显式participantID汇总 PASS；两个计时、90/60秒、各一次/独立明细、记录者仍“我”、无第三人事实 |
| T9 | NilFeedbackArchiveLongTermAndSameSnapshotEdits +真实同页45→30分钟/全部7/30天/删除0 PASS |
| T10 | TimerTransactionsNeitherSaveNorRollbackForeignDraft、T4真实磁盘外部草稿、raw无效手工草稿ZIP/冷重开、实际Record草稿与Sleep相邻UI PASS |
| T11 | BrowsingDoesNotCreateParticipantAndActualCreationIsIdempotent +实际Settings Files导出/预览取消/浏览时间投入后空目标恢复 PASS；新包稳定身份在磁盘ZIP中验证 |
| T12 | AllUnfinishedStatesExportRestoreReopenWithoutAdvancingOriginal PASS：running/paused/targetReached/pendingSave，7天后只恢复720秒检查点、无正式事实、显式继续新增60秒；源快照不变 |
| T13 | PreviewThenTimerCreationAndRepeatImportRejectWithoutMutation / PublicationFailureLeavesEmptyStoreAndRetry / 20类MalformedPackages PASS；非法revision拒绝，合法max-1包可恢复，实际变更受控报错且每次独立磁盘重开快照不变，不崩溃或丢事实 |
| T14 | FiveHistoricalDiskSchemasDirectStartupUpgradeKeepsOriginalFactsAndMedia / V13DiskUpgrade及完整Unit相邻迁移 PASS；V10/OriginalV11=11.0/V11=11.1/V12/V13真实磁盘/媒体/关联/收据保全；V1–V13定义逐字冻结 |

## FAIL、SKIP、NOT_RUN 与旧数据边界

当前 Safari 补验真实进入扩展后仍 **FAIL**。系统日志19:00:56.657明确 ShareExtension client is not entitled，实际unsigned包无App Group entitlement；先打开ShareInbox失败导致编辑器为空/保存禁用，后续取消/保存/导入未通过。Share源码、App Group/身份/签名配置相对BASE不变；本轮V14外部导入Unit已执行。依据Goal第99行的既有unsigned边界，系统签名路径留Owner，未绕过容器或更改签名。最初URL提交交互失败是另一条失败，不冒充entitlement根因。

完整Unit唯一 **SKIP**：TodoFoundationTests/testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure，要求未挂载的专用32MB HFS+卷/marker；物理低空间场景 **NOT_RUN**。注入低空间、保护/迁移/回滚通过；未挂载卷或填满主盘。远端workflows=0，独立CI **NOT_RUN**，空checks不算PASS。

原始运行警告保留：fullunit2旧GoalFixture PGOS-S7 SQLite unlink/invalidated，集中UI三条Invalid frame，targeted一条；最终轮实际警告见执行文档。正常磁盘写失败不承诺未落盘输入跨强杀零丢失。合法但耗尽的max-1 revision保持可验证/可导出，实际变更提示受控错误、原事实不变；不会wrap或生成无效Int.max。

原V1–V13、主库路径、五Tab/Record、原Bundle/Share/Widget/AppGroup、版本1.0(7)、签名及发行配置保持；project仅新增六个生产/测试文件引用及membership。默认参与者仅实际写入时惰性初始化，旧v1–v9没有的收据不伪造。原工作区未知dirty、旧PR#8/#9/#10/#11保留。

## Owner设备清单（需后续另行签名/安装授权）

- 先保留独立备份，不卸载覆盖升级；核对旧Entry/图片、Habit/Goal/Weight/Todo/重要日子/Sleep/来源/收据，重开再核对。
- 正计时锁屏/切其他App→暂停/继续/结束；确认等待不增长，关闭/强退重开仍待处理。
- 25分钟倒计时晚返回默认25分钟；显式继续只算点击后的新段，提前结束不补满目标。
- 手工日期时长/后补反馈/精确与修正精度、跨日暂停、30天前旧事实、全部累计与日贡献下钻。
- Record草稿、睡眠编辑、重要日子、实际签名Safari分享、桌面Widget及通知组合；中文/英文/深浅色/大字体/VoiceOver/单手/飞行模式。
- 用主动备份在明确空目标验证未完成检查点不自动补入设备间间隔；不把私人库当夹具。

真实iPhone/私人库/签名、实际系统通知/桌面Widget、Photos/VoiceOver与发行均 **NOT_RUN**。停点只表示可进入Owner设备验收；未merge、force push、tag、Archive或TestFlight，不继续下一模块。

---
## 以下为续接前验收历史

下方旧NOT_RUN/状态是当时原始记录，由上方逐项原生结果更新；保留历史失败，不作为当前待执行指令。

# 时间投入 V1 验收与设备门禁

当前状态：**RUNNING_NATIVE_GATES（2026-10-17，环境已恢复）**，尚未达到READY_FOR_OWNER_DEVICE_GATE。规格固定GOAL_SHA `72ee8bdf954a5628806db867682a6b021e63545b`，BASE `ad0720ad743f495ac6f2ee3e97b16577266351db`；产品工作树 `codex/time-investment-v1`，唯一新 [Draft PR #12](https://github.com/yoCruzer/PersonalGrowthOS/pull/12)，base为 `codex/sleep-routine-v1`。固定产品/测试检查点及对应实际命令见[执行记录](TIME_INVESTMENT_V1_EXECUTION.md)，真实独立Reviewer报告见[独立审查](TIME_INVESTMENT_V1_REVIEW_ZH.md)。

`PASS_MAC`只表示未改写的生产核心及相同XCTest在临时macOS内存Schema中的补充运行，不代表iOS V14、历史磁盘升级、ZIP/UI或真机通过。`COMPILED`只证明编译。以下未执行项不写成PASS，旧模块历史证据不当作新代码全测。

原生续接：固定 c84a680 的受影响门禁 **98/98 PASS、0FAIL/0SKIP**，包括核心22、持久8、完整ImportExport55与相邻迁移。历史首轮90项88PASS/2FAIL及SQLite警告保留；独立固定夹具收据oracle与清理生命周期修正后绿。固定b091/cc09计时真实Home/activate/冷启动UI通过，R8同row按钮串触发P1已独立确认修复。其他UI仍在补验，不把中间轮整体写PASS；各行旧NOT_RUN为本次续接前状态，将在最终门禁汇总逐行更新。

## S1–S10

| 门槛 | 实际接线与测试 | 当前证据 |
| --- | --- | --- |
| S1 | Growth/Today→InvestmentHub/TimerView；InvestmentService.start/command/saveTimer；InvestmentUITests计时前后台/冷启动 | 核心PASS_MAC；实际iOS UI NOT_RUN |
| S2 | AppShell前后台checkpoint、跨进程待复核、壁钟/uptime校验，InvestmentFoundationTests T7 | 固定时钟核心PASS_MAC；真实iOS回收/锁屏/设备NOT_RUN |
| S3 | targetReached/pendingSave/幂等终态；T2/T3/T4、R2/R3/R4；R5 Workspace继续确认 | 核心及Workspace PASS_MAC，固定0abe补充共24/24；原生ZIP/冷启动NOT_RUN |
| S4 | EditorState/storeDraft独立草稿、saveManual、可选反馈/区间降级、确认删除 | 核心草稿/错误/幂等PASS_MAC；真实UI/睡眠组合NOT_RUN |
| S5 | 惰性Participant、独立recorderID、服务显式participantID、Activity归档改名 | 双参与者与ID核心PASS_MAC；实际设置恢复稳定身份NOT_RUN |
| S6 | InvestmentReview原时区自然日、Session去重、History/Detail共享Workspace快照 | 纯/服务反例PASS_MAC；同页编辑/删除UI与视觉NOT_RUN |
| S7 | V14/v10；TransferSnapshot/Validator/materialize/verifySnapshot/空库复核/StorePublication/Startup保护 | 全链代码与原生测试COMPILED；iOS磁盘/包/真实入口NOT_RUN |
| S8 | 五Tab/Record/Today原路径；新增仅Growth/条件状态；无签名/身份配置变化 | Debug实包静态核验；联合运行/Share/Widget系统行为NOT_RUN |
| S9 | 94新双语键、937原键值不变；原生语义控件与44pt主要目标、Light/Dark/AX UI测试 | 静态PASS，实际语言/大字号/VoiceOver/离线操作NOT_RUN |
| S10 | 干净固定提交Debug及unsigned Release、独立只读复审、普通推送新Draft PR | 固定0abe Debug/unsigned Release实包通过，R1–R7代码层独立闭环；原生运行未完成，最终通过尚未成立 |

## T1–T14

| 反例 | 真实生产路径/测试名 | 当前结果 |
| --- | --- | --- |
| T1 | testT1PauseExcludesFiveMinutesAndDoesNotDependOnTicks | PASS_MAC；锁屏硬件NOT_RUN |
| T2 | testT2CountdownCapsAtTargetAndExplicitContinueOmitsLateGap / EarlyEndDoesNotFillTargetAndPausedTargetDoesNotRun | PASS_MAC；实际后台晚返回NOT_RUN |
| T3 | testT3FinishRemainsFrozenAcrossConfirmationDelayAndNewService / InvestmentUITests冷启动确认 | 核心PASS_MAC；App重开NOT_RUN |
| T4 | testT4RepeatedStartFinishSaveAndDeletedCallbacksNeverResurrect / CommitBeforeAndAfterFailureHasOneRecoverableOutcome / ManualAfterCommitRetryAndNoOp | PASS_MAC；实际进程强退及磁盘故障重开NOT_RUN |
| T5 | testT5DurationCorrectionDropsIntervalsButPreservesTimerOrigin / Editor exact interval | 核心PASS_MAC；原生编辑NOT_RUN |
| T6 | testT6CrossDayPauseAllocationAndCountUseOriginalZone，按日Contribution详情 | 核心5/15分钟与记录数1 PASS_MAC；UI下钻NOT_RUN |
| T7 | ClockJumpRebootAndProcessChange / DSTLeapDayAndNaturalWindow / ClockRollbackNoteEdit / R6原时区显示 | 核心PASS_MAC；真实设备旅行/回拨/重启NOT_RUN |
| T8 | testT8TwoParticipantsAreIsolatedAndSameParticipantCannotDoubleStart，独立recorderID | PASS_MAC；无家庭UI |
| T9 | testT9NilFeedbackArchiveLongTermAndSameSnapshotEdits / ManualSaveHistoryNilFeelingEditAndDeleteRefreshSameReview | 核心PASS_MAC；同页真实刷新UI NOT_RUN |
| T10 | testT10TimerTransactionsNeitherSaveNorRollbackForeignDraft / ManualDraftPersistsRawInputFailure / RecordDraftSurvivesManualActivitySaveAndChineseDarkAX | 核心PASS_MAC；Record/睡眠实际组合NOT_RUN |
| T11 | testT11BrowsingDoesNotCreateParticipant / testPR6FilesPreviewCancelAndRestore已增加新装时间投入浏览 | 裸容器PASS_MAC；真实设置Files路径/旧包组合NOT_RUN |
| T12 | testT12AllUnfinishedStatesExportRestoreReopenWithoutAdvancingOriginal，四状态真实ZIP；R3核心恢复继续 | 核心恢复模型PASS_MAC；实际完整包/七日后恢复iOS NOT_RUN |
| T13 | PreviewThenTimerCreationAndRepeatImportRejectWithoutMutation / PublicationFailureLeavesEmptyStoreAndRetry / InvestmentV10MalformedPackagesRejectWithoutChangingTarget（16类） | 原生代码COMPILED，实际磁盘/ZIP NOT_RUN；R7核心技术上界配对PASS_MAC |
| T14 | FiveHistoricalDiskSchemasDirectStartupUpgradeKeepsOriginalFactsAndMedia / V13DiskUpgrade，沿用原V10/OriginalV11/11.1历史fixture测试 | 全部iOS运行NOT_RUN，不以Mac适配器替代原Schema保护 |

## 旧数据与身份边界

旧V1–V13持久模型定义和V11Original=11.0/V11=11.1版本保持，追加V14；主库路径、主Bundle、Share/Widget/AppGroup及签名/发布配置保持。v10必需新增数组、严格引用/时长/身份校验，恢复未完成检查点必须转待确认，默认参与者在实际写入时才产生。v10保存原CaptureImportReceipt，旧包原来缺失的收据不会伪造补出。原工作区未知dirty和旧PR#8/#9/#10/#11均保留。

这些是实现约束及静态审查结论。原生迁移/备份失败保护的必选运行还缺证据，不能将它们移到Owner才可解决的产品缺口。

## 环境恢复后本地必跑

1. 单一Xcode测试队列：新核心、Workspace/持久化、ImportExport完整类、原历史迁移与数据保护相邻路径；保留每轮真实退出码/数量/运行警告。
2. 运行三项新InvestmentUITests、真实设置Files恢复、Record/睡眠/体重/Todo/QuietWins/重要日子/Share/Widget联合冒烟；签名系统限制分开保留。
3. 收敛发现后一次完整Unit、集中关键UI；固定干净产品/测试SHA的Debug与unsigned Release实包身份/provenance核验；最终独立只读Reviewer复核。
4. 只有本地可执行门禁与范围内审查闭环后，才能标READY_FOR_OWNER_DEVICE_GATE。

## Owner设备清单（需后续另行签名/安装授权）

- 先保留独立备份，不卸载覆盖升级；核对旧Entry/图片、Habit/Goal/Weight/Todo/重要日子/Sleep/来源/收据，重开再核对。
- 正计时锁屏/使用其他App→暂停/继续/结束，确认等待不增长，关闭/强退重开仍待处理。
- 25分钟倒计时晚返回默认25分钟，显式继续只算点击后新段；提前结束不补满目标。
- 手工日期时长/后补反馈/精确与修正精度、跨日暂停、30天前旧事实、全部累计及回顾来源下钻。
- Record草稿、睡眠编辑、重要日子、外部分享、桌面Widget与通知路径组合；中文/英文/深浅色/大字体/VoiceOver/单手操作。
- 用主动导出备份在明确空目标验证未完成检查点不自动补入设备间间隔；不把私人库当测试夹具。

真实设备、签名/系统通知/桌面Widget、Photos/VoiceOver、发行均NOT_RUN。无merge、强推、tag、Archive或TestFlight授权。
