# 睡眠与作息 V1 验收映射

状态：READY_FOR_OWNER_DEVICE_GATE。固定规格 1bed2f4，产品基线 5614246；本分支包含重要日子全部修复。未操作真机或私人库，不能假定 Owner 安装版本是 V12。

| 要求 | 真实实现 / 自动化证据位置 |
| --- | --- |
| S01 部分输入/原精度/编辑删除/重开 | SleepFoundation/SleepService；SleepFoundationTests、SleepUITests 主路径 |
| S02 跨午夜/月年末/晚起/白天 | SleepRange 绑定实际民用日；MidnightMonthYearLateAndDaytime、DaytimeMainSleep 对照 |
| S03 区间上下界/间隔/未来/重叠 | IntervalsPreserveOriginalBounds、FutureBucketsOverlapMissingAndInverse；原始区间与日期显示 |
| S04 目标边界和历史规则 | GoalVersionsBoundary、RollbackCannotOverwriteAlreadyEffectiveGoal、TimezoneCivilDayRollback；日期生效规则与设置预览 |
| S05 字段实际填写属性 | FieldTimingLateCorrectionsNoteNoopClearRefillAndRollback、KnownCrossRecordRollback；备注不重置时间/评分 |
| S06 7/30 自然日、独立分母和来源 | SleepReviewSnapshot、ReviewIndependentDenominatorsCivilWindowAndCrossNightAxis；实际跨夜区间图、晚起范围末端/次日标签；ChartVisible3绘图来源及原记录回跳 |
| S07 防重/冲突/失败草稿/跨日编辑 | 独立事务 context、revision 检查；TwoContextsStaleRevisionAndDateCollision、PartialNoteOnlyEmptyUnknownAndServiceFailureRetry；UI 草稿与比较入口 |
| S08 时区/DST/回拨 | 保存 zone/civil/offset 与 observedAt；DSTGapRepeatExplicitOffset、EarlierDSTOccurrence、AmbiguousCivilRange、WallClockPickerRoundTrips |
| S09 睡眠提醒状态与删除恢复 | 实际 TodoReminderCoordinator/client/gate；SleepReminderTests 全类与 ElapsedMorningCannotBeMovedLater、CancelledBeforeDelivery与真实generation交错回归 |
| S10 通知交错/过期路由/Recovery草稿 | 共享预算与 generation；原 ImportantDayReminderTests、TodoReminderTests；SleepUITests 过期日/冷路由/草稿 |
| S11 V11/V12 实际磁盘升级和保护 | SleepPersistenceTests 的 V11 冻结 fixture、真正 V12 schema 创建的含封面/关系库；原 alias/WAL/低空间测试 |
| S12 旧包/v8/v9 往返、非法原子拒绝 | 整个 ImportExportRecoveryTests；SleepV9MalformedPackages、V9BothModulesExportEmptyRestoreReopen；保持来源收据不进入备份的旧限制 |
| S13 Today/Growth/Weight/Record/显示偏好/双语 | SleepUITests、既有体重/Record UI；实际浅深/中文最大 AX 截图；入口隐藏与提醒独立 |
| S14 五Tab/实包与重要日子相邻回归 | 固定候选两实包identity/provenance；CombinedUI1中R3b三项、关联/草稿、真实Widget URL路由通过；组件privacy Unit在FullUnit2通过。当前unsigned Safari FAIL，根因App Group无entitlement，历史有效分享证据按原SHA复用，当前签名分享留设备Gate |

## Owner 最小组合清单（安装仍须另行授权）

1. 先保留可用备份，不卸载旧 App；核对实际候选 SHA，查看旧记录/照片/体重/习惯/Todo/重要日子正常。
2. 从 Today 记录真实一晚，备注可空；保存并重开检查日期、完整时间区间和感受，回顾能回到原记录，体重仍直接聚焦。
3. 可选开启就寝目标与晨间提醒，核对生效日、实际下一次及覆盖期；真实系统递送/专注模式/锁屏必须实机观察。
4. 重要日子单独做历法往返保存重开、相关记录冒烟；另观察原 Widget 隐私/路由与提醒，完整边界仍沿用原验收清单。

真实签名/安装、iPhone 私库升级、桌面 Widget、系统通知递送、Photos、VoiceOver、TestFlight 未执行。无签名 generic-iOS 产物用于构建核验，不是可直接安装 IPA。

## 候选与自动化边界

最终产品/测试及最后生产 `138616cd0970b0f4fba9d0c7d7d44f6ca7d30b53`；交付commit仅更新五份交接Markdown，精确交付SHA见Git/PR head及本地 `final-delivery-proof.json`。独立worktree `/Users/himini/.codex/worktrees/sleep-routine-v1/PersonalGrowthOS`，分支 `codex/sleep-routine-v1`，[Draft PR #11](https://github.com/yoCruzer/PersonalGrowthOS/pull/11)（Draft/base `codex/important-days-v1`）。原workspace dirty与原PR#8/#9/#10不动。

自动化：FullUnit1 406/406；新增目标持久证据后FullUnit2 410/410，0跳过；随后共享取消44/44与图表23/23及最终11/11仅补受影响项，不宣称最终411全量。集中UI15/17保留FAIL，睡眠设置/中文真实Dark补验2/2；Safari本轮仍FAIL且明确环境边界；图表补验结果和警告按执行文档分轮列出。唯一独立只读Reviewer已核对固定实现、反例和真实证据，范围内无未关闭confirmed P0/P1/P2。

构建用 `PersonalGrowthOS.xcodeproj` / scheme `PersonalGrowthOS`；Debug模拟器app `/tmp/pgos-sleep-derived/Build/Products/Debug-iphonesimulator/PersonalGrowthOS.app`，unsigned generic-iOS Release `/tmp/pgos-sleep-release-derived/Build/Products/Release-iphoneos/PersonalGrowthOS.app`。两者含Share/Widget，原1.0(7)，同clean候选SHA。Release不是可直接安装IPA；请勿以旧机版本为V12、勿卸载旧App以绕过升级。

保留限制：2条集中UI旧体重Invalid frame警告，后续每次打开体重补验各1条；无SwiftData迁移失败/空库fallback。真实设备私库、签名与App Group、锁屏/专注递送、桌面Widget、Photos、VoiceOver未验证；CI workflows=0，独立远端CI NOT_RUN。备份来源收据旧限制与本次无关，不把恢复后的source=nil记录来源判断说成完整。

详细分轮结果、失败根因及原证据路径见[执行断点](SLEEP_ROUTINE_V1_EXECUTION.md)，独立关闭依据见[审查记录](SLEEP_ROUTINE_V1_REVIEW_ZH.md)。
