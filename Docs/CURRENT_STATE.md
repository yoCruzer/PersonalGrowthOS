# Todo V1 ReviewFix + Usability — IN_PROGRESS（2026-10-09）

Owner 新附件 `CODEX_GOAL_ZH.md` 授权在原 Draft PR #8 连续执行 S0→S4：先关闭提醒偏移、未来Open后继同步、及时通知失败反馈、启动完整性恢复四项问题，再完成Open单次任务转换重复与全部任务状态筛选，最终集中验证、普通push，停在READY_FOR_INDEPENDENT_REVIEW。

本轮起点/local/upstream/PR head均 `4625602b27d8b4e4df4f6da20b7f11bf30b21d8c`，原分支/base不变。S0与两个P1可失败回归、S1/S2/S3定向门禁完成；实现已冻结，自查通过，S4完整Unit/集中UI/真实产物与交付门禁待执行。原轮下方READY状态只属于历史，不代表本轮完成。不得merge/tag/改号/Archive/TestFlight；未触碰Owner私人数据库。新增候选模型11.1.0保留旧11.0.0迁移节点，备份仍v7。实际每轮结果见 [执行记录](TODO_V1_EXECUTION_LOG.md#reviewfix--usability-统一-goal--2026-10-09进行中)。

---

以下为上一轮交接与历史记录。

# Todo V1 — READY_FOR_INDEPENDENT_REVIEW（2026-10-09）

Owner Goal Pack Rev2 整体范围已实现并验证。分支 codex/todo-v1-personal-actions，从 Build12 同源 c5a3c0ac859efc3ffa4e5d9f77909ec43565c871 派生；远端 base codex/external-capture-v1、旧 annotated tag 均再次核对为该提交，旧 PR #1–#7 仍 OPEN Draft。最终产品/测试提交 837b619e5f2d6a0367aa31d61e3829acf731b4e4；后续交接只有文档，最终仓库 HEAD 以新 PR head 为准。

Todo Hub/连续录入、清单、四种固定重复、Entry主动来源、全局/局部搜索、四项可点统计、独立一次通知、完整备份均已实现。SwiftData **V11**、备份 **v7**（合法 v1–v6可读），五 Tab、App/Extension **1.0(7)** 保持；Owner手机 Build12 是独立已安装事实。

一次完整 Unit **283/283 PASS**；新增完整性/恢复/相邻路径 **123/123 Unit PASS**，随后 **83 Unit + 4 UI PASS / 2 UI FAIL**。一次关键 UI **17/22 PASS / 5 FAIL**；五个失败点分别完成定向补验，全部有通过证据，最终五项 Todo UI **5/5 PASS**。失败记录不重标全绿。真实 V10/V7/V8、备份精度/回滚/并发、提醒正负、中文深色真实 AX maximum、About完整SHA复制及Debug/Release/模拟CI资源验证已完成。

[A1–A25/P1–P8验收与十分钟真机清单](TODO_V1_ACCEPTANCE.md)；[真实命令、counts和失败审计](TODO_V1_EXECUTION_LOG.md)；[产品语义](TODO_V1_SCOPE.md)。

普通推送与独立 [Draft PR #8](https://github.com/yoCruzer/PersonalGrowthOS/pull/8) 已完成，base codex/external-capture-v1；**READY_FOR_INDEPENDENT_REVIEW**。下一步仅独立审查，不继续实现或发布。最终文档提交后本地 Debug 构建核对最终 HEAD（final-handoff-debug.log / final-handoff-debug-bundle.json）；源码与远端一致性以 PR head 为准。远端 workflows=0，独立CI **NOT_RUN**；Owner私人Build12库覆盖、真机通知/签名/AppGroup、VoiceOver朗读、实际Xcode Cloud发行 **OWNER_DEVICE_GATE**。未 merge/close/tag/改号/Archive/TestFlight，未清私人库。

---

以下为保留的历史交接，不指挥本轮 Todo Goal。


# PR #7 F1–F5 统一修复（2026-09-26）

**READY_FOR_INDEPENDENT_REVIEW — F1–F5 修复与受影响回归完成，Owner 真机门禁独立保留。**

沿用 `codex/external-capture-v1` / [Draft PR #7](https://github.com/yoCruzer/PersonalGrowthOS/pull/7)，base `feature/build9-today-entry-followups` 不变。起点 `04f1ee0abf70b0121b4261d7ceafc9dea2fbe0b0`；产品与回归实现 `404d1d939e7c49f000718939f71843fa3ba90cb3` 已普通推送；Safari 测试交互补验提交 `1415a5b55b1870736275d546719b389b6c1a7e45`，后续交接仅文档，不改产品代码。最终仓库 HEAD 以 PR head 为准。

- F1：按逻辑正文项合并 Retry 新恢复内容，保留用户编辑/删除；真实扩展验证备注与恢复正文进入同一 Entry、重开完整，重复保存不重复创建。
- F2：同 URL 补齐 title/canonical/显式 siteName，空值不擦除；两个 provider 顺序、真正多来源与 image+webURL 通过。
- F3：仅隔离解码损坏的辅助状态，保存原始字节并尽量保留正常 deferral；Pending/receipt 可用，未来包保留。I/O 错误不当坏 JSON；提交后的状态写入失败不误报内容未保存。
- F4：主 App 输入具有可取消任务、操作身份与临时文件归属；过期/取消/重复相机回调不污染新草稿，编辑仍追加，Record 跨 tab 保留草稿；最终 Entry 与图片字节断言通过。
- F5：相同技术字段采用 `max(now, createdAt, oldUpdatedAt)`；真实服务回拨后完整导出→空库恢复→重开通过，内容/图片/身份/业务日期保留，follow-up 规则及非法备份拒绝保持。

固定产品提交上的 `AffectedGate1`：**234/234 Unit、8/9 UI PASS，整体 exit 65**；唯一失败为 Safari 可见菜单按钮的 XCTest 无效点击位置，未进入扩展。仅测试改为核对屏幕内按钮中心点击后，`SafariMenu2` **1/1 UI PASS，exit 0**，全部内容断言保留；不把原整组改标全绿。unsigned Release App/唯一 appex **exit 0**，均 1.0(7)；schema V10、备份 v6 不变；511 中英字符串完整。原全量 240 Unit + 48/49 UI 的 exit 65 与历次失败记录继续保留。

完整命令、逐项复现/修复及未执行项见 [执行计划 F1–F5 最终交接](EXTERNAL_CAPTURE_EXECUTION_PLAN.md#f1f5-最终交接)。没有重开 R1–R9、清库、放宽断言、merge/close/retarget、tag、改号、Archive/TestFlight 或主动触发分发 CI。

下一步仅独立 Review。签名/App Group、Photos/微信、真实离线/慢网络、Owner 私人库覆盖升级、相机硬件及真机性能仍需 [Owner 验证](OWNER_MANUAL_VALIDATION_CHECKLIST.md)。历史 V8 hash 差异根因、云端实际 build/TestFlight 可用性仍 UNKNOWN/OWNER_REQUIRED。

---

以下为历史交接，旧完成状态不代表本轮 F1–F5 完成。

# 当前状态：External Capture v1 与项目遗留统一收口

**READY_FOR_INDEPENDENT_REVIEW — 代码与文档收口完成，Owner 真机门禁单独保留。**

本轮范围为 R1–R9、L1–L2，替代仅 R1–R3 的旧指令。唯一逐项结论与可复现证据见 [统一收口执行计划](EXTERNAL_CAPTURE_EXECUTION_PLAN.md#统一收口审计-2026-09-26)。

- 分支 `codex/external-capture-v1`；审计起点 `ab79c734f1f53a60484ba4bc5f6247cbe9b14b3b`；最终产品代码 `a0728d77d63e27af4ffeb9341105d62f4d4e5842` 已推送。后续交接提交仅补 Files 测试保存完成同步及文档；最终仓库 HEAD 以 PR head 为准。
- [PR #7](https://github.com/yoCruzer/PersonalGrowthOS/pull/7) 仍 OPEN Draft，base `feature/build9-today-entry-followups` 未变。未执行 merge/close/retarget、tag、改号、Archive/TestFlight 或新增 CI。
- R4 原分享图片丢失及新增普通图片安装竞争均已复现并修复；共享锁使用稳定路径身份，恢复仅删除空目录及本次拥有的图片。失败/取消/成功恢复、导出截止边界、草稿与排队分享验证通过。
- 统一门禁代码 `3b4cc3d4390f8e5e6a1e17206b9f9538b2227a4a`：Unit 240/240 PASS，UI 48/49 PASS，整体 exit 65。唯一 UI 失败为屏幕下方关系按钮未滚动；补正常滚动后定向 PASS，保留原断言和失败记录。
- R4 修复后 63/63 相关 Unit PASS（StableLock1，exit 0）；最终锁身份/排队 2 Unit 与 ManualReview UI PASS（FinalSupplement1）。同组 Files 点击系统 Save 后立即终止，随后选择器 No Recents，未选到备份而失败，整体 exit 65；增加保存完成同步后同设备 Files 预览→取消→恢复 1/1 PASS（FilesSaveCompletion1，exit 0）。没有将失败的原整组重标为 PASS。
- 最终 unsigned Release app/appex PASS（ReleaseStableLock1，exit 0）；SwiftData import warning 消失，仅未采用 AppIntents 的自动提取提示。project/plist/scheme、App Group、activation v2 与 509 个中英字符串静态检查通过。
- App/Extension 1.0(7)、schema V10、备份 v6（合法 v1–v6 可读）未变。原 V1 功能与 UX-01/02 已有交付，不重新列为未开发。

当前没有已确认而未处理的本轮代码缺陷。仍需 [Owner 集中真机验证](OWNER_MANUAL_VALIDATION_CHECKLIST.md)：签名/App Group、Photos/微信公开分享、实际离线/慢网络、Owner 旧库保留数据覆盖升级及交互性能。历史默认模拟器 V8 hash 差异原因、实际云端 build 与 TestFlight 可用性仍 UNKNOWN/OWNER_REQUIRED；没有清库或删除模拟器数据。

下一边界仅独立 Review 与经 Owner 授权的真机门禁。未来 PR 集成顺序及 #1 已包含于 #2 的证据见执行计划；本轮不自动进入合并、发布或全文抓取。

以下内容均为历史交接（superseded），旧状态及 Next Action 不再指挥当前工作。先前逐组进展、失败与反证保留在执行计划中。


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

# Build 9 Current State — 独立 Review

2026-09-16：本轮六项功能、自动验证、提交/普通推送与独立 [Draft PR #6](https://github.com/yoCruzer/PersonalGrowthOS/pull/6) 完成。执行分支 `feature/build9-today-entry-followups`，base 为 `feature/build8-habit-analytics-dashboard` 的实际 `ae8f7cb`；没有追加旧 PR #5。

实际 schema V9 / backup v5 / App 1.0 (7)。产品实现提交 `7c65413`，之后只收尾测试和文档。确切 V8 迁移/重开、v5 往返/非法包拒绝通过。候选全量 Unit 一次 208/209，测试排序假设修正后1/1通过；209项均有通过证据。新路径定向 UI 通过，包括中文 CRUD、真实深色大字号多习惯与全部置顶；最后强化删除断言1/1通过。命令、源码摘要和各次真实结果见 [Execution Plan](BUILD9_EXECUTION_PLAN.md)。

此前审批容量阻塞经 Owner 再次确认和正式审批解除，未绕过限制。模拟器已恢复 light / large。**Goal COMPLETE，下一边界独立 Review；真机体验待 Owner 验证，不代表发布批准。** 未提升 build、合并、Archive 或 TestFlight。

Owner 使用 Build8 的反馈与其历史真机待验结论分开记录。以下为 Build8 历史证据，不代表当前 Build9 验收。

# Current State

| Item | Verified value |
| --- | --- |
| Project | Personal Growth OS |
| Last verified | 2026-09-06 |
| Current branch | `feature/build8-habit-analytics-dashboard` |
| Current `main` baseline | `dd09975d3a3736b24f8646fa4f197cc883ab1796` |
| Current base | `95076bf5c2a86122fbd327903d80bccdfb8c768d` (Build 8 frozen baseline) |
| Governance status | Build 8 PR #5 review closure plus bounded lifecycle-detail presentation delta complete; automated gate passed and Owner device validation remains mandatory |
| Completed delivery | S0–S10, Completion Push C0–C5, Final Candidate C6, App icon refresh, Usability S2, Build 6 Round 1, and Build 7 Round 2 implementation |
| Final automated gate | Build 8 review closure: 196/196 Unit, 31/31 UI and Debug PASS; lifecycle-detail follow-up 2/2 targeted Unit, 1/1 targeted UI and Debug PASS; prior targeted, exact-V7 overlay/reopen and bilingual evidence remain green |
| Release gate | Build 8 Owner physical-device validation remains external; do not merge, archive or upload TestFlight automatically |
| Next checkpoint | Review Draft PR #5 and execute Owner physical-device validation; no merge, archive or TestFlight action before explicit approval |

## Build 8 Draft Review Foundation

Build 8 starts at exact SHA `95076bf5c2a86122fbd327903d80bccdfb8c768d` on a dedicated stacked branch. A fixture generated by the exact Build 7 source proved that adding Local Day fields directly to the shared `HabitLog` changed the V7 model checksum and made the real store an unknown staged-migration version. Stage 1 restores the exact V7 `HabitLog` shape and stores V8 civil-day facts additively. Stages 2–5 make Plan/history/runtime/segments coherent. Stages 6/7 validate Gregorian Local Days, preserve backdated recomputation, use a hidden migration baseline with known current status, start legacy Plan truth conservatively at migration, distinguish Resume/Restart/Restore, deterministically order same-day lifecycle events, and merge visible Journey items chronologically. Stage 8 makes Overview and Detail consume one authoritative analytics snapshot, leads Detail with current-period truth and actions, adds a full daily month calendar, and bounds Recent Activity with an all-history route. Stage 9 gives daily weekday patterns an eligible scheduled-day success-rate denominator while weekly/monthly/tracking-only patterns remain honest factual distributions. Stage 10 rejects v4-only Plan/lifecycle data in older packages, verifies the v4 recording-mode boundary, and completes English/Simplified Chinese Dashboard localization with compiled catalogs and live UI proof. Stage 11 gives overview controls unique Habit-scoped identities, proves adjacent 44-point hit targets, and moves actions below content at accessibility sizes so long names keep full-width readable layout. The bounded PR #5 review closure at implementation commit `41194b8` preserves same-period streak continuity while retaining historical best segments, validates achievable once/day Plans, distinguishes migration Plan provenance, rejects duplicate/legacy-schema Plan and LocalDay conflicts, separates inactive Habits from active schedule sections, surfaces Overview action errors, and aligns Month Calendar to Monday-first. The lifecycle-detail follow-up makes inactive Habit `Now` status-led, removes current progress/adherence/Current Streak and check-in guidance, and retains only a meaningful historical Best Streak when available; Active behavior and all later dashboard/history sections remain unchanged. The post-closure automated gate passed with 196 Unit tests, 31 UI tests and Debug build; the lifecycle-detail follow-up passed 2 targeted Unit tests, 1 targeted UI test and a Debug build. The 429-entry catalog remains complete in English and Simplified Chinese. Draft PR [#5](https://github.com/yoCruzer/PersonalGrowthOS/pull/5) continues to target the frozen Build 7 handoff. Owner physical-device validation is the remaining external gate; no merge, archive or TestFlight action has occurred. See `Docs/BUILD8_HABIT_ANALYTICS.md` for the full evidence.

## Build 8 PR #5 Review-Closure Gate

- Targeted Habit Foundation plus Import/Export Recovery: 98 passed, 0 failed, 0 skipped — `/tmp/PersonalGrowthOS-Build8-PR5-ReviewClosure-TargetedUnit2.xcresult`.
- Complete Unit suite: 196 passed, 0 failed, 0 skipped — `/tmp/PersonalGrowthOS-Build8-PR5-ReviewClosure-FinalUnit.xcresult`.
- Complete post-fix UI suite: 31 passed, 0 failed, 0 skipped — `/tmp/PersonalGrowthOS-Build8-PR5-ReviewClosure-FinalUI2.xcresult`. The first attempt was 30/31 because an existing Weekly Review assertion read immediately after keyboard dismissal; its bounded-wait correction passed targeted 1/1 before this final rerun.
- Exact Build 7 V7 overlay/bootstrap/reopen and v4 complete backup round trip: 2 passed — `/tmp/PersonalGrowthOS-Build8-FinalDataProofs.xcresult`.
- Post-closure Simulator Debug build: PASS; prior independent English and Simplified Chinese `build-for-testing` evidence remains valid.
- The 429-entry String Catalog is complete in both languages; catalog JSON and whitespace checks pass.
- Lifecycle-detail follow-up: 2/2 targeted Unit PASS — `/tmp/PersonalGrowthOS-Build8-PR5-LifecycleDetail-Unit.xcresult`; 1/1 targeted UI PASS — `/tmp/PersonalGrowthOS-Build8-PR5-LifecycleDetail-UI.xcresult`; Simulator Debug build PASS — `/tmp/PersonalGrowthOS-Build8-PR5-LifecycleDetail-Debug.xcresult`.

## Authoritative Product Baseline

The Foundation Documents in `Docs/INDEX.md` remain authoritative. `Docs/V1_IMPLEMENTATION_PLAN.md` defines the completed S1–S10 delivery. The Owner-approved 2026-07-31 Completion Push adds only lightweight manual Weight records to V1; it does not introduce a separate health product.

The previously verified `fix/v1-device-smoke-round1` commit `dd09975` passed Internal TestFlight installation and the first Owner-supplied iPhone smoke test. It was safely fast-forwarded to `main` before the isolated `feature/v1-completion-push` branch was created. `main` remains unchanged; the V1 distribution branch and the newer S2 branch remain unmerged.

## Build 6 Owner Feedback Round 1

Build 6 starts from the clean Build 5 handoff `1a1f6bb` and keeps SwiftData schema V7 and backup schema v3 unchanged. Implementation commit `48b324c` completes the bounded owner-feedback scope:

- Library now provides Weekly Review history and Search; history and search reopen the exact stored calendar week, and search covers all four WeeklyReview text fields including Chinese content.
- Weekly Review uses a persisted edit baseline: unchanged Save is disabled, edits show Unsaved changes, successful save briefly shows Saved, and a cancellable task prevents stale feedback from overwriting newer edits.
- The factual weekly summary uses a compact adaptive Your Week block. The exact adjacent week’s focus appears as Last Week’s Focus in the review and This Week’s Focus on Today.
- Full-screen Entry images are centered independently of the top-right Close overlay. The repeatable Habit control is one capsule with one count and 44-point decrement/increment targets.
- The draggable Search/Capture cluster and coordinate logic are removed. A fixed bottom-center Quick Capture action sits between the four native tabs, while Search is available from Library.
- Settings includes opt-in daily recording and weekly review local reminders. Stable identifiers replace pending requests deterministically; notification permission is requested only from an enable action, and denied authorization exposes an iOS Settings path.
- New user-visible strings have English and Simplified Chinese values.

Final simulator evidence on iPhone 16, iOS 26.5 (`5F04DE28-8329-4774-9488-076D6DDC5230`):

- Debug build: PASS — `/tmp/PersonalGrowthOS-Build6-FinalBuild2.xcresult`.
- Focused Unit tests: 39/39 — `/tmp/PersonalGrowthOS-Build6-Focused3.xcresult`.
- Full Unit suite: 146/146 — `/tmp/PersonalGrowthOS-Build6-FinalUnit.xcresult`.
- Focused changed-flow UI tests: 5/5 — `/tmp/PersonalGrowthOS-Build6-FinalUI2.xcresult`.
- JSON parsing, bilingual catalog completeness, conflict-marker scan and `git diff --check`: PASS.

Physical-device validation is still required for portrait/landscape image centering; bottom capture safe-area placement; Habit pill layout and tap comfort; notification permission allow/deny, rescheduling, relaunch and actual delivery; Chinese Weekly Review input/save/fade/relaunch; and focus visibility across a real calendar-week boundary. No Build 6 TestFlight, archive or device PASS is claimed.

## Build 7 Owner Feedback Round 2

Build 7 starts from the reviewed Build 6 head `c15513f` and keeps SwiftData schema V7 and backup schema v3 unchanged. Implementation commit `fde3ea8` closes the bounded UX and semantics feedback:

- Weekly Review now shows all four reflection prompts persistently above their editable answers, without changing the stored fields, search coverage or dirty/save behavior.
- The former global floating capture overlay is removed. `Record` is the third native tab; its draft survives a tab switch, resets after a successful save and then navigates to Timeline.
- Repeatable Habit rows retain 44-point +/- targets within their own row while using a lighter 34-point semantic capsule. Count text remains monospaced, can grow for larger numbers and is not capped by the daily target.
- New and edited multiple-per-day Habits require a positive daily target through the shared domain/service validation. The editor suggests 2 when appropriate; legacy targetless multiple Habits remain readable and check-in capable until edited.
- Archived Habits are hidden from the main Habits list, exposed through a counted Archived destination with an explanatory empty state, and retain their existing detail/Restore behavior and history.
- All new user-visible strings are localized in English and Simplified Chinese. Marketing version remains 1.0 and Debug/Release build number is 7.

Focused simulator evidence on iPhone 16, iOS 26.5 (`5F04DE28-8329-4774-9488-076D6DDC5230`):

- Habit Unit tests: 29/29 PASS — `/tmp/PersonalGrowthOS-Build7-Habit2.xcresult`.
- Record tab and repeatable-counter UI smoke: 2/2 PASS — `/tmp/PersonalGrowthOS-Build7-UI.xcresult`.
- Weekly Review persistent-prompt/save/relaunch UI smoke: 1/1 PASS — `/tmp/PersonalGrowthOS-Build7-WeeklyUI2.xcresult`.
- Final Simulator Debug build: PASS.
- `git diff --check` and String Catalog JSON parsing: PASS.

Owner physical-device validation is still required for native five-tab keyboard behavior, Record draft preservation, light/dark counter appearance and touch separation, Chinese Weekly Review prompt/input hierarchy, daily-target editing, and archive/restore navigation. No Archive, TestFlight upload or device PASS is claimed.

### P1 Independent Review Closure

Commit `839ce71` separates backup restore validation from the stricter Habit create/update rule. v3 import now preserves an explicit legacy multiple-per-day configuration with a nil target, still rejects explicit zero or negative targets, and normalizes once-per-day targets to nil. It does not migrate data, alter schema V7 or change backup schema v3. The Weekly Review answer fields also expose their already-visible persistent prompts as accessibility labels.

Focused simulator evidence: 5/5 PASS — the explicit legacy-configuration export/import round trip, non-positive target rejection, and the directly related Habit rule tests — `/tmp/PersonalGrowthOS-Build7-PR4-ImportCompatibility.xcresult`. `git diff --check` passed. No full suite, UI suite, Archive or TestFlight action was run for this review closure.

## Post-V1 Usability S2

The active branch starts from the formal App icon refresh at `c45c666`. It retains two committed but previously unpushed UX fixes: `53f2326` unifies the empty-state and toolbar add actions for Weight and Habits, and `06cc913` makes multiple-per-day Habit counters directly reversible. The current S2 candidate adds a manual weekly review/action loop; its scope and evidence are recorded in `Docs/USABILITY_S2_REVIEW_LOOP.md`.

S2 adds a V7 SwiftData schema containing one manually created `WeeklyReview` per natural calendar week. The week policy is Gregorian, Monday-first and four-day-first-week, while retaining the local device time zone for local-day semantics; Locale, Region and a non-Gregorian system calendar do not alter review identity. It does not alter `EntryKind.review`, generate reports, create tasks, add health advice, or widen the V1 product model. A user can explicitly begin a weekly review from Today, see a local summary of that week’s Entries, HabitLogs, Weight and Tags, write optional reflection/next-step/focus text, save it locally and reopen it after relaunch. Full backup schema v3 preserves these records while v1/v2 packages remain importable when they contain no weekly-review data.

The focused PR review fix keeps once-per-day Habit Undo unchanged. Multiple-per-day Habits instead use only the immediate +/- counter: minus removes today's latest structured `HabitLog` and never deletes a linked Entry or its explicit Entry-to-Habit relation. Detail and Insight check-ins in that mode no longer show the competing Undo bar.

Draft PR #2 has passed its first independent code review. The S2 device-validation candidate was Version 1.0 (Build 4), prepared from `bacb504afb30c582c869ae68f8558831c5067437` at `/tmp/PersonalGrowthOS-S2-Build4.xcarchive`. Local Archive inspection confirmed the Release arm64 app, bundle identifier `com.yocruzer.PersonalGrowthOS`, display name `随心log`, AppIcon, `ITSAppUsesNonExemptEncryption = NO`, and Team `83SKX2PM7B`. Build 4 was subsequently distributed through TestFlight and physically validated by the Owner.

Build 4 Owner iPhone overlay validation passed V5→V6→V7 migration; preservation/relaunch of original Entry, image, Habit, Goal and Review data; Weight persistence; repeatable-Habit `+++--`; Insight→`+`→`-` linked-Entry retention; explicit-only Weekly Review creation; and V7 export. It found a P0 Weekly Review closure failure: Chinese keyboard dismissal was unreliable and Save gave no visible confirmation or persistence proof. The post-`2084207` candidate now gives Review fields explicit focus and a keyboard Done action, yields before saving, refetches the stable current-week review rather than relying on a potentially stale query snapshot, and makes success/failure visible. It also clears stale success feedback when any editable field, including completion, changes or when a new save begins; a focused UI test covers completion-state save/relaunch persistence. It compacts the repeatable-Habit counter, makes the floating Search/Capture cluster keyboard-aware, draggable and locally persisted, and closes the two bounded Entry-media UX debts.

Version 1.0 (Build 5) was archived from source commit `6027d758c5d18183a3aacae75ef8e1b3f8dc6d0b` at `/tmp/PersonalGrowthOS-S2-Build5.xcarchive`. Inspection confirmed the Release arm64 app, bundle identifier `com.yocruzer.PersonalGrowthOS`, display name `随心log`, formal AppIcon resources, `ITSAppUsesNonExemptEncryption = NO`, Team `83SKX2PM7B`, and successful `codesign --verify --deep --strict`. The Archive is recognized as scheme `PersonalGrowthOS` by Organizer metadata. It has not been uploaded to App Store Connect/TestFlight, and Build 5 Owner device validation has not been executed; PR #2 remains Draft.

## V1 Final Candidate

The candidate provides:

- Rich local Entry capture with text, 0–9 original images, dates, editing, archive, restore and permanent delete.
- Today, Timeline, Growth and Library with global Quick Capture and Search.
- Inbox, All Entries, Tags and Archived organization.
- Structured Habit lifecycle and HabitLog check-ins.
- Goal and Flag lifecycle with bounded relationships.
- Lightweight manual Review Entries using the shared Entry lifecycle.
- Complete unencrypted ZIP export and safe empty-store import.
- English and Simplified Chinese interface.
- Lightweight Weight CRUD, dates, kilograms, latest value, previous-record change, simple chart, history, Today/Growth entry points and restart persistence.

No approved V1 capability remains unimplemented. UX-01 and UX-02 are resolved in the Build 5 candidate without expanding into a media-browser redesign.

## Persistence and Migration Safety

SwiftData schema V6 adds `WeightRecord`; schema V7 adds `WeeklyReview`. The explicit V5→V6 and V6→V7 lightweight migrations do not rename, remove or tighten fields on existing Entry, ImageMetadata, Tag, ObjectLink, Habit, HabitLog, HabitConfiguration, Goal, GoalLifecycleEvent or WeightRecord data.

Automated migration coverage creates an on-disk V5 store with representative Entry, Habit and Goal data, opens it through V6 and verifies identities and representative fields while Weight starts empty. Separate V6→V7 coverage verifies existing Entry, Habit and Weight records remain unchanged while WeeklyReview starts empty. Existing migration and recovery tests cover earlier schemas, relationship integrity and media boundaries.

Full backup package schema v3 includes Weight and WeeklyReview. The importer accepts valid schema-v1, v2 and v3 packages, rejects Weight in v1 and WeeklyReview in v1/v2, validates v3 weekly-review identity, timestamps and period ordering, and preserves all supported records through round trip. Original image bytes remain in the private media tree rather than SwiftData. There is no destructive store-rebuild or empty-store fallback after migration failure.

The Owner executed the V5→V6→V7 overlay against the existing iPhone store on Build 4 and confirmed preservation and restart recovery. The remaining physical-device gate is Build 5 revalidation of the Weekly Review Chinese input/save/relaunch closure and the new bounded interaction polish.

## Final Automated Validation

Executed on iPhone 16 Simulator, iOS 26.5 (`5F04DE28-8329-4774-9488-076D6DDC5230`):

- Simulator Debug Build: PASS.
- Full Unit Tests: 125/125 passed, 0 failed, 0 skipped.
- Full UI Tests: 22/22 passed, 0 failed, 0 skipped.
- Combined automated total: 147/147 passed.
- Import/export, recovery, media, migration and Weight tests are included in the full Unit suite.
- English build-for-testing: PASS.
- Simplified Chinese build-for-testing: PASS.
- String Catalog JSON and bilingual-value validation: PASS (285 keys).
- Xcode project parsing, target/scheme references and Release build settings: PASS.
- `git diff --check` and merge-conflict-marker scan: PASS.

Result bundles:

- Debug Build: `/tmp/PersonalGrowthOS-V1Final-Build3-Debug.xcresult`
- Unit: `/tmp/PersonalGrowthOS-V1Final-Build3-Unit.xcresult`
- UI: `/tmp/PersonalGrowthOS-V1Final-Build3-UI.xcresult`
- English: `/tmp/PersonalGrowthOS-V1Final-Build3-English.xcresult`
- Simplified Chinese: `/tmp/PersonalGrowthOS-V1Final-Build3-ZhHans.xcresult`

Xcode emitted environment-only warnings while copying signed XCTest support binaries and resolving the LLDB debugger version for UI launches. They produced no build or test failure.

## Formal App Icon Refresh

The App icon for the existing desktop display name `随心log` now uses a warm ivory Möbius band with two restrained terracotta record nodes on a low-saturation deep teal background. The existing universal iOS 1024×1024 `AppIcon` slot remains in use; the source PNG is RGB with no alpha channel, and no Bundle Identifier, signing, version, build number or display-name setting changed.

The refreshed asset passed Asset Catalog compilation and a Debug build on the iPhone 16 Simulator running iOS 26.5. Simulator inspection covered the Home Screen in light and dark appearance, App Library and Spotlight; the icon remained legible and showed no white edge, transparent edge, double rounding, stretching, clipping or visible blur. The existing focused app-shell UI launch smoke test also passed.

## Build 3 and Distribution

| Item | Result |
| --- | --- |
| Marketing Version | `1.0` |
| CFBundleVersion | `3` |
| Bundle Identifier | `com.yocruzer.PersonalGrowthOS` |
| Team | `83SKX2PM7B` |
| Signing style | Automatic |
| Export compliance | `ITSAppUsesNonExemptEncryption = NO` |
| Archive | PASS for the pre-icon candidate; regeneration required to include the formal icon |
| Archive path | `/tmp/PersonalGrowthOS-V1Final-Build3.xcarchive` |
| Local archive metadata inspection | PASS |
| App Store Connect export | BLOCKED — `No Accounts`; no `iOS Distribution` certificate |
| Server-side validation | NOT EXECUTED |
| Upload | NOT EXECUTED |
| App Store Connect processing | NOT STARTED |
| Internal Testing | NOT AVAILABLE FOR BUILD 3 |

The existing Archive is a normal Automatic Signing development-signed intermediate, but it predates the formal App icon refresh and must not be uploaded as the refreshed candidate. Regenerate Build 3 from the current branch tip, then use Xcode signed in to the correct Apple account to export it with App Store distribution signing and upload it. The in-app App Store Connect browser session was also unauthenticated.

## Quality State

- Known P0: none in the Build 6 simulator candidate.
- Known P1: none.
- Known new product P2: none.
- Open non-blocking P2: none from this feedback batch; UX-01 and UX-02 are resolved in `Docs/UX_DEBT.md`.
- Build 4 Owner-data overlay remains historically passed; Build 6 physical-device validation and any TestFlight distribution remain unclaimed.

## Next Action

Review [Draft PR #3](https://github.com/yoCruzer/PersonalGrowthOS/pull/3) against `feature/usability-s2-review-loop`. After review, the Owner decides whether to create a TestFlight build and perform the listed physical-device checks. Do not merge or publish automatically. The V1 Build 3 distribution handoff remains separate and Owner-only on `feature/v1-completion-push`.
