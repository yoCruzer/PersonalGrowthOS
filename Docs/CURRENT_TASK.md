# 当前任务：External Capture v1 与项目遗留统一收口

2026-09-26：Owner 新 Goal 替代此前停止实现及仅 R1–R3 的边界。状态 **IN_PROGRESS**，目标仍为完成 R1–R9、L1–L2 后交付 READY_FOR_INDEPENDENT_REVIEW。

起始分支 `codex/external-capture-v1`，完整 SHA `ab79c734f1f53a60484ba4bc5f6247cbe9b14b3b`；起始工作区干净。实时查询确认 [PR #7](https://github.com/yoCruzer/PersonalGrowthOS/pull/7) 为 OPEN Draft，head 与本地一致，base `feature/build9-today-entry-followups`。无后续修复需要回退或重复。

R4 已在合成隔离库确定性复现图片丢失，并完成首组修复：共享发布互斥、worker 导入、按拥有路径清理和主草稿保护。定向 8/8 + 取消/草稿 2/2 通过；R4 剩余检查点、R2 扩展 I/O 与其他收口项继续推进。验收与逐项证据统一记录于 [执行计划](EXTERNAL_CAPTURE_EXECUTION_PLAN.md#统一收口审计-2026-09-26)。普通实现、测试、commit/push 连续推进；不 merge/close/retarget、tag、改版本或 Archive/TestFlight。不删除用户数据或模拟器数据。

R6 UTF-8 可选 metadata 预算、R8 source 搜索/提交后刷新、L1 显式 SwiftData import 已实现；R6 2/2 Unit，R8 2 Unit + 2 UI（真实 Safari 保留空搜索刷新及 follow-up 删除返回）通过。首组修复完整提交 `b25c59d00726395622923cab9a9c11d0d1555ef5` 已推送并核实远端；第二组证据见计划。接下来继续 R1/R5 provider、R2 extension 重 I/O、R3/R7 生命周期、R9 诊断及 R4 剩余交错，不进入全文抓取或发布。

R1/R5 provider 语义化读取、30 秒 callback 边界、取消/generation、部分保存确认与扩展 worker 发布已实现。真实 Safari 及独立公开 API 混合 host 系统面板→extension→主 App 导入均通过；version 2 默认匹配通过，strict 匹配失败已据实记录。R7 staging 内核租约在 Unit 与真实合成子进程 SIGKILL 后回收验证通过；Pending/无归属旧目录保留。仍待 R3、R7 导入副本/备份边界、R9、R4 剩余交错与完整 final gate，继续按同一 Goal 推进。

R3 失败 Inbox 已实现，3 项定向 Unit + 1 项 UI 通过：持久稍后、版本重试、新故障/正常包不被屏蔽、receipt 区分、取消和逐条确认丢弃、重启不重复提醒；结果见执行计划。R3 提交 `c6b024656c8da28c97d4f8b6fcb244215b8754aa` 已推送，远端一致。R7 写前副本日志/逐文件补偿、真实测试进程 kill-before-save 恢复、低容量注入、导出先导入与 Pending 排除告知均定向通过；未知 Recovery 与用户 Pending 保留。第五组 `b0fbdc975cf8b26a02fbc79dc946d737e9d1ba61` 已推送且远端一致。R9 白名单诊断/安全重试已实现，2 Unit + 1 UI 定向通过，安全重试保留已有 Entry；历史默认模拟器主文件元数据与冻结 V8 仅 HabitPlanRevision hash 不同，根因/Owner 关联仍未验证，未修改该库。剩余 R4/R2/R1/R5、L2 与统一 final gate 继续推进。第三组 `a5cd018d23c9742f30280476761cb6b8cb83567a` 已推送且 PR #7 远端核实一致，仍为 OPEN Draft。

第七组进行中：R4 导出 cutoff 1/1 与安装后二次空库检查/成功恢复排队分享 2/2 定向通过；真实 host 部分保存确认 UI 通过，取消后同进程立即重开仍因 host 不可交互失败，真实 Safari 对照亦复现空白系统面板；取消通知已到达系统 teardown，显式 dismiss 试验无效且已撤回，仍在定位，不记为已解决。九图响应性测试 NineLarge1 已实际执行 1/1 通过（总量 >180 MiB、九次 MainActor 响应、草稿保留）。L2 当前清单入口已归一，最终门禁未执行，仍 IN_PROGRESS。详见执行计划第七组。

以下内容均为历史交接（superseded），其中旧状态及 Next Action 不再指挥当前工作；历史验证结果保留，不作为本轮修复通过证据。

---

# External Capture v1 — Independent Review handoff

2026-09-22: Owner authorized External Capture v1 and explicitly selected Build 9 `ae14f107f7eebb89a1549e00de3d941e6a996281` as its baseline. Active branch: `codex/external-capture-v1`; Draft PR base: `feature/build9-today-entry-followups`. The previous PR #6 handoff below is historical.

Implemented: public Share Extension + App Group atomic inbox, ordinary Entry import with optional source and durable receipt, Safari selected text/title/URL, nonblocking metadata, source reopening, privacy-safe diagnostics, additive schema V10 and backup v6 (v1–v5 readable). App and extension remain 1.0 (7).

Verified: full Unit 218/218 and key UI 3/3; bounded closure 6 Unit + 1 Safari UI; final unsigned Release app/extension build, all PASS. The closure covers partial post-commit cleanup and JSON publication-size bounds. See [EXTERNAL_CAPTURE_EXECUTION_PLAN.md](EXTERNAL_CAPTURE_EXECUTION_PLAN.md) for exact evidence, limitations and device checks. Historical default simulator-store warnings remain documented; no destructive fallback or private-data reset.

Delivery complete: implementation commit `068a27a` is pushed on `codex/external-capture-v1`; [Draft PR #7](https://github.com/yoCruzer/PersonalGrowthOS/pull/7) targets the Owner-selected Build 9 branch. **READY_FOR_INDEPENDENT_REVIEW** — stop implementation. Subsequent commits only record this handoff. Physical signing/App Group provisioning, Photos/WeChat host variations, actual offline metadata and Owner database overlay remain **Owner Device Verification**. No merge, tag, Archive, TestFlight or full article capture.

---

# PR #6 Review Closure — 再次独立 Review

2026-09-16：R1/R2/R3 均核实成立并完成定向修复。起始 `7843641f6d977ffe13e6e78e837c561709e83f71`，产品/回归测试提交 `967dc01bc127d5dc27a4dfd1b1ebe8108b248237`，沿用 `feature/build9-today-entry-followups`，只更新 [Draft PR #6](https://github.com/yoCruzer/PersonalGrowthOS/pull/6)。

R1：UI预览/正式导入各自获取与释放文件scope，失败/取消清除pending预览；R2：实际搜索列表重新出现时重查保留query，刷新成员/片段/定位；R3：更新时间取now、已有更新时间、createdAt+1秒最大值，不修改父Entry，不放宽v5校验。

本轮5项定向Unit通过；搜索长原文多补充返回刷新UI通过；系统Files合成ZIP预览→取消仍空→再次选择恢复UI通过。详细命令/真实退出状态/截图和环境中断原因见 [Execution Plan](BUILD9_EXECUTION_PLAN.md) Review Closure 节。未重跑全量基线，旧Build9验证不作为新代码通过证据。

App1.0(7) / schemaV9 / backupv5未变。仅模拟器本地Files提供者通过，真机与第三方提供者未验；未操作真实私人库。下一边界仅再次独立Review，不自动merge、Ready、Archive或TestFlight。以下Build9首轮及Build8内容保留为历史。

# Current Task — Build 9 独立 Review 交接

**本轮 Goal 完成，停止实现。** 六项交付、风险驱动测试、提交、普通推送及独立 Draft PR 均完成。当前分支 `feature/build9-today-entry-followups`；[Draft PR #6](https://github.com/yoCruzer/PersonalGrowthOS/pull/6) base `feature/build8-habit-analytics-dashboard`，起始 SHA `ae8f7cb6577f2d1bc479471bcd98d6f437670210`。

权威计划：[BUILD9_EXECUTION_PLAN.md](BUILD9_EXECUTION_PLAN.md)。候选全量 Unit 208/209 + 失败点修正后1/1通过；定向 UI、双语、真实深色大字号截图与强化删除断言完成。产品源码仍为实现提交 `7c65413`，后续只有测试/文档变化。此前审批阻塞已通过 Owner 明确确认及正式审批解除。

下一步仅独立 Review：重点 Today 周/月共享规则、附属模型删除事务、搜索定位、V9/v5 兼容与恢复边界。Owner iPhone16 清单见计划。真机未执行，无合并、build number 提升、Archive 或 TestFlight 授权。

下列 Build8 内容仅为历史交接证据，不是当前任务；其真机未验收结论仍保留。

# Current Task

| Item | Value |
| --- | --- |
| Current checkpoint | Build 8 Draft PR #5 — bounded lifecycle-detail review closure handoff |
| Status | AUTOMATED GATE PASSED — OWNER DEVICE VALIDATION REQUIRED |
| Execution branch | `feature/build8-habit-analytics-dashboard` |
| Base | `95076bf5c2a86122fbd327903d80bccdfb8c768d` |
| Implementation tip | Current branch tip adds the bounded inactive Habit Detail presentation closure after `41194b8` |
| Automated gate | 196/196 Unit and 31/31 UI PASS; lifecycle-detail 2/2 targeted Unit, 1/1 targeted UI and Debug PASS; prior targeted, bilingual, v4 backup and exact-V7 overlay/reopen evidence remains green |
| External status | Draft PR [#5](https://github.com/yoCruzer/PersonalGrowthOS/pull/5) open; no merge, archive or TestFlight action |

## Superseded Build 7 Boundary

- Weekly Review prompts remain visible with both empty and saved answers, while existing baseline-driven Save, Search and canonical-week behavior remain unchanged.
- Record is the third native tab. The AppShell floating capture overlay is removed; Record preserves an unsaved tab-switch draft, resets after save and routes the saved Entry to Timeline.
- Today repeatable Habit controls have a lighter 34-point visual capsule inside separate 44-point +/- targets, with uncapped `current / target` display.
- Multiple-per-day Habit create/update validation requires a positive Daily Target in the shared domain/service path. The editor suggests 2 for a new multiple mode; legacy targetless data remains readable and usable until edited.
- Archived Habits are excluded from the default main list, have a counted Archived destination and preserve existing Restore/detail/history behavior.
- SwiftData remains V7, backup remains v3, marketing version remains 1.0 and Debug/Release build number is 7.
- Backup import now preserves an explicit legacy multiple-per-day nil target while continuing to reject a provided non-positive target; Weekly Review persistent prompts are also exposed as matching accessibility labels.

## Build 8 Draft Review Boundary

- PR #5 review closure keeps Build 8 scope frozen: no Trend expansion, Portfolio analytics or Build 9 work was added.
- Current Streak now follows the current contiguous compatible period/lifecycle segment; same-period target and selected-weekday revisions stay continuous, while Best Streak retains the maximum historical same-unit segment without bridging lifecycle, period-kind or Tracking Only boundaries.
- Once/day Plans validate to exactly 1/day, 1–7/week or 1–28/month in both domain and backup paths. The editor hides ignored once/day targets for Every Day/Selected Days and gives weekly/monthly targets explicit labels and bounds.
- Only active Habits enter active schedule sections. Paused and Completed remain available in lower-priority status sections with history but without due/remaining controls; Archived behavior is unchanged.
- Migration-bootstrap Plan provenance is persisted and omitted from Journey; legacy coverage messaging appears only for an actual migration trust boundary. Duplicate Habit/effective-day revisions and v4 HabitLog LocalDay fields in schema v1–v3 packages are rejected, while resolver ties are deterministic.
- Overview action failures are visible, and Month Calendar now uses the Monday-first Weekly Review header/offset policy without changing persisted Foundation/Gregorian weekday identities.
- Inactive Habit Detail `Now` is status-led and omits current progress, adherence, Current Streak and check-in guidance; a meaningful historical Best Streak remains available, while Active Detail and all later dashboard/history sections are unchanged.

- V8 persistence models, Local Day write semantics, plan/lifecycle history, a pure analytics engine and v4 transfer fields are implemented in staged commits; the complete automated acceptance matrix and UI validation pass.
- The recovered Stage 0 batch makes positive persisted Local Day authoritative for once/day duplicate, Today completion and decrement behavior; false logs no longer block true completion, rest-day activity remains factual without becoming expected, and Sunday uses the documented weekday identity.
- The exact-`95076bf` V7 fixture rejected the direct-`HabitLog`-column design with an unknown model-version error. V8 now uses additive `HabitLogDayMetadata`; representative Entry/Image/Habit/HabitLog/Goal/links/Weight/WeeklyReview facts survive overlay, idempotent bootstrap and reopen.
- `HabitPlan` and `HabitPlanRevision` now persist explicit `recordingMode`; weekly once/day credits distinct LocalDays, weekly multiple/day may credit repeated same-day activity, Tracking Only retains its mode, and backup v4 validates and round-trips the field.
- Today, Habits Overview, Habit Detail and check-in validation now resolve settings from the Plan effective on the relevant Local Day. Legacy `HabitConfiguration` is consulted only if no effective Plan exists; contradictory configuration no longer changes V8 runtime behavior.
- Name-only saves carry no Plan change and preserve pending revision IDs. The editor loads and labels a pending Plan/effective date; an actual Plan edit removes the never-effective pending revision before inserting its replacement.
- Current adherence, consistency and streaks use only the current contiguous Plan/lifecycle segment. Day→week→day, week→month→week, Tracking Only→daily and pause/complete/archive restart boundaries no longer bridge metrics.
- Local Day parsing rejects impossible dates and preserves leap days; backdated positives recompute history. Migration uses a hidden baseline with known current status and a conservative Plan boundary. Resume, Restart and Restore are distinct, same-day lifecycle ordering is deterministic, and visible Plan/lifecycle Journey facts are merged chronologically.
- Overview and Detail now share one authoritative analytics snapshot. Overview reports daily/weekly/monthly/tracking-only progress without a fake denominator; Detail leads with current progress, state and check-in actions, then shows the dashboard, five recent facts and a complete history route.
- Daily Progress uses a full civil-month calendar with scheduled success/miss/open/rest, lifecycle-neutral, pre-coverage and future states. Weekly/monthly current activity remains period-scoped and Year Activity remains a separate 365-day view.
- Daily weekday patterns display achieved/eligible success rates using only strict scheduled outcomes. Weekly, monthly and Tracking Only patterns display factual activity counts by weekday and are explicitly labeled as a distribution.
- Backup validation rejects schema-v1/v2/v3 packages carrying v4-only Plan/lifecycle payloads, while supported old packages remain compatible and v4 recording modes remain validated. Dashboard strings, streak units and Journey events now have English and Simplified Chinese coverage verified in compiled catalogs and live UI.
- Overview counters use Habit-scoped accessibility identities. Normal rows retain compact side-by-side rhythm; accessibility sizes place the action below full-width content. Mixed once/day, target-based multiple, Tracking Only, adjacent multiple rows, over-target values and a long name pass enabled semantic accessibility audits with >=44-point +/- targets in Light and Dark.
- The exact Build 8 implementation state and remaining work are recorded in `Docs/BUILD8_HABIT_ANALYTICS.md`.
- This is a Draft review candidate: review-closure implementation and the complete automated gate are complete. Owner physical-device validation remains mandatory before approval, merge, archive or TestFlight distribution.

## Historical Build 7 Validation Evidence

- Habit Unit: 29/29 PASS — `/tmp/PersonalGrowthOS-Build7-Habit2.xcresult`.
- Record tab and repeatable-counter UI smoke: 2/2 PASS — `/tmp/PersonalGrowthOS-Build7-UI.xcresult`.
- Weekly Review persistent-prompt/save/relaunch UI smoke: 1/1 PASS — `/tmp/PersonalGrowthOS-Build7-WeeklyUI2.xcresult`.
- Final Simulator Debug build: PASS.
- `git diff --check` and String Catalog JSON parse: PASS.
- P1 import-compatibility closure: 5/5 focused Import/Export and Habit tests PASS — `/tmp/PersonalGrowthOS-Build7-PR4-ImportCompatibility.xcresult`.

## Remaining Owner Device Validation

- Five native tabs and no floating capture control during keyboard input.
- Record draft persistence across tab switches and clean state after save.
- Today once/multiple Habit visual row parity, long names, Dynamic Type, light/dark appearance and non-overlapping +/- touch regions.
- Daily Target editing, target overrun and legacy targetless Habit editing.
- Once/day Selected Days target hiding, weekly/monthly target limits, Paused/Completed low-priority history access, and Monday-first Month Calendar alignment.
- Representative pause/resume and same-period Plan-change histories showing Current and Best streak values without cross-boundary joining.
- Weekly Review Chinese prompt hierarchy, input, save confirmation and relaunch persistence.
- Habit Archive → Archived → Restore navigation with preserved history.

## Next Action

Review the updated Draft PR [#5](https://github.com/yoCruzer/PersonalGrowthOS/pull/5) and run the Build 8 Owner physical-device checklist against the new remote HEAD. Do not approve/merge, archive or publish TestFlight until that external validation is explicitly completed.
