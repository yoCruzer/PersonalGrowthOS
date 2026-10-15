# PR #11 R1–R3 限定修复 — READY_FOR_INDEPENDENT_REVIEW（2026-10-15）

批准输入 `9e9e29564565a3b6396dc51bb179c29f71bdc726`，起始交付 `5f7dc3eeba4d159d72e03029f487cf67bf77ab1a`。沿原worktree、`codex/sleep-routine-v1` 与[原Open Draft PR #11](https://github.com/yoCruzer/PersonalGrowthOS/pull/11)，base保持 `codex/important-days-v1`。五份输入原样导入，manifest三个SHA-256逐项核对；探针/旧输出未修改、未执行，不是App测试。

最终产品/测试 **`9da1ce8758d868145e9b5690611634ccd292e469`**；最后生产 `f235d9210bf2bb2a9226fda6156d803c4010cc36`，后续仅R1 UI查询歧义修正与更强分布断言。本批交付只再更新五份交接Markdown，精确delivery SHA见Git/远端PR head及 `/tmp/pgos-sleep-r1-r3-evidence/final-delivery-proof.json`，不写自引用hash。

| 本轮问题 | 新生产证据与关闭边界 |
| --- | --- |
| R1 | Red1真实回顾内编辑→unknown3/样本0；统一事实与评价时钟后直接编辑、评分来源改值、绘图来源清起床和30天窗口即时一致。真实未来/回拨与recalled仍排除，备注/no-op原字段证据保持 |
| R2 | Red1真实service与设置均红；初始关闭多次保存零规则，首次启用今日，磁盘重开/真实UI重启保持。已有目标禁用历史不清洗；下一日起效和跨时区/回拨保护原样 |
| R3 | Red1批末前到期不再failed且重启不重复；Red2失败提前取消跨期补红再修。成功接受、elapsed、未来missing/失败与真正取消分开；legacy键、generation、公平容量与实际pending状态有配对 |

| Run / 固定SHA | 真实结果与关闭依据 |
| --- | --- |
| Red1 / 500c9dc | 0/2 Unit（7断言FAIL）+0/2真实UI（2FAIL），exit65、0SKIP/warning；旧生产R1字段全部unknown、R2off落规则、R3末确认前到期丢台账均实际复现 |
| Focused1 / 64d5dc2 | 50/50相关Unit + 1/2 UI PASS，exit65、0SKIP/warning；R2 UI通过，R1直接保存1/1/1及评分1恢复；扩展来源测试因Poor行中心落TabBar，未导航。层级783–835、TabBar791起及录像证实，补正常滚动与完整frame断言，未删事实检查 |
| Red2 / 1a732fb | 0/1 Unit，2断言FAIL，exit65、0SKIP/warning；独立Reviewer指出add替换抛错后的remove未及时确认，下一日add跨旧fire后真正提前取消被锁 |
| Green2 / f235d92 | 41/41相关Unit + 0/1 UI，exit65、0SKIP/warning；取消缺口与全部通知/目标/交错对照通过。UI实际走完评分来源改值即时移出、返回与绘图来源打开，失败因Unknown同时匹配菜单与评分未知；限定排除后者，不删清起床与30天断言 |
| UI3 / clean9da1ce8 | 1/1真实UI PASS，exit0、0SKIP/warning；完整走原回顾编辑→评分来源成员即时移出/新分布1→绘图来源清起床→1/0/0→30天归属，无额外离开回顾或后台刷新 |

固定clean9da1ce8的Debug Simulator（复用UI3等效构建）与unsigned Release generic iOS均PASS/exit0，六实包身份/1.0(7)/两App provenance同源核验通过，Release仅保留既有AppIntents提取提示。 独立Reviewer固定9da1ce8758d868145e9b5690611634ccd292e469完成代码/原始反例/分轮日志与关键PNG、两实包plist终审，R1–R3关闭，无未关闭已确认范围内P0/P1/P2。其本人未运行测试或改实现。 原始证据、候选工程/scheme与两构建精确路径见[执行断点](SLEEP_ROUTINE_V1_EXECUTION.md)，无签名iOS app不是可直接安装IPA。原workspace未知dirty保留，分支普通推送原PR，旧PR不动；交付提交仅五文档，不重建。

本批停READY_FOR_INDEPENDENT_REVIEW供外部按新SHA限定关闭R1–R3。外部通过后组合设备项仍只需：保留备份/不卸载并核对旧数据；晨间记录/原回顾内编辑后重开；重要日子历法往返和关系冒烟；真实通知、Widget与签名Safari分享另行观察。真实手机版本未知，不假设已到V12/V13。当前未签名分享FAIL不因旧SHA成功证据而关闭；私库/签名/App Group/系统递送/桌面/Photos/VoiceOver与CI均未执行，不merge/tag/Archive/发布。

---

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
