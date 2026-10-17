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
