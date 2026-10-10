# 真实 iPhone 259 — 诊断修复 READY_FOR_INDEPENDENT_REVIEW，原事故根因 UNKNOWN（2026-10-10）

Owner 明确授权在无法获取失败现场条件下继续。升级前ZIP仍在iPhone，当前失败容器未下载，未确认是否已清除；没有读取或操作真实私人数据，也没有安装授权。事故基线 `dc4bacc930f9490128896c4e6b66d67540a074ac`；原分支/原Draft PR #8/base保持。

合成V10已有保护副本签名不一致时，在 `StartupRetainedData.capture` 校验路径稳定复现 `storeOpen / Cocoa259`，早于SwiftData；连续Retry保留源与故障副本。健康同源V10含committed WAL保护/重试/迁移保留Entry与媒体；原V11迁移通过。非法metadata实验返回SwiftDataError，不能冒称另一条259。原手机实际错误路径尚无法证实。

本轮最小修复只解决诊断定位与硬编码Schema：新增固定startupStep，保留原始错误与定位；diagnostic v2明确Schema未采集；旧JSON兼容与隐私allowlist保持。未改Schema/迁移/校验/Recovery布局，未用清库或删除副本掩盖失败。**诊断改善不等于原手机启动故障已修复；事故继续保留UNKNOWN。**

最终完整Unit 307 PASS / 0 FAIL / 1 SKIP（总308，物理32MB低空间卷未挂载）；启动UI2/2、unsignedSimulator Release App/Extension通过，runtimeWarnings=[]。首轮误选诊断测试类、诊断red失败、metadata错误码假设失败均保留。详细中文根因边界、修复和真实命令见 [事故报告](TODO_IPHONE_STORE_OPEN_259.md)。真实Build12私库/ZIP、真机再安装/恢复与独立CI均NOT_RUN（远端workflows=0）。

停止在本轮诊断与合成证据独立审查边界。只普通推送原Draft PR #8，不改Ready状态、不合并、不打Tag、不触发TestFlight；未来真机操作仍需Owner明确授权。下方旧READY与旧测试为历史，不能证明本次手机恢复成功。

---

# 历史：Draft PR #8 — P1 数据保全修复 READY_FOR_INDEPENDENT_REVIEW（2026-10-10）

本轮Review基线8be670cd7375c0c7f0352d7749bf8a7ff3114767；产品/测试候选70f37908dc87b00afe7b71025568b7ef8b1143ac。后续仅文档，最终仓库HEAD以原Draft PR #8 head为准。原分支codex/todo-v1-personal-actions、base codex/external-capture-v1保持，普通push并更新原PR，不merge/tag/改号/Archive/TestFlight。

S0 EIO/ENOSPC负向风险成立；S1健康库只读预检无需完整copy、历史首次迁移前必须持久保护、Todo失败停止正常写入；S2持久内容身份快照复用、WAL/并发/PASSIVE checkpoint竞态、5次故障Retry、真正临时导出清理、导出I/O/ENOSPC/取消、原副本不删除与raw ZIP拒绝普通v7导入全部通过。32MB独立HFS+卷中完整copy真实ENOSPC而健康库打开/保存仍成功；历史copy失败原库未迁移，损坏copy失败仍停写，空间恢复后能建副本。

S3原Build12真实AppContainer迁移/第二次copy失败不影响打开、完整原事实/媒体/v7与重开，加4项集成UI共6/6通过。最终唯一一次完整Unit **305/305 PASS，0 FAIL/SKIP、零运行警告**；固定候选2/2启动UI通过（重启重导、健康Retry保留Entry）。真实Debug/unsignedRelease App及唯一appex **1.0(7)**，SHA/localGit/clean/Tag空已核对。V11.1/v7、五Tab、原Todo规则/UX、翻译/fixtures/版本/签名/AppGroup无变化。所有初次失败与编译失败保留，未重标全绿；详细命令及生命周期策略见 [限定修复证据](TODO_P1_DATA_PRESERVATION.md)。

重要副本位于Application Support/Recovery，创建ZIP或关闭ShareLink不代表安全外部导出；已完成副本不自动删除，只清未发布staging/partial。不同真实故障内容各自保留，可能占空间。Owner私人Build12实际覆盖、真机签名/AppGroup/通知、设备实际系统清理/VoiceOver、Cloud/TestFlight **NOT_RUN/OWNER_DEVICE_GATE**；远端workflows=0，独立CI **NOT_RUN**。旧UI运行警告历史风险与已保存旧候选错误提醒不在本轮范围，未冒称解决。没有清空、重建、静默修复私人库。

**停止实现，下一边界仅原Draft PR #8独立审查及Owner设备门禁。**

---

以下为本轮验证中的历史checkpoint，不再指挥下一步。

# Draft PR #8 — P1 数据保全限定修复进行中（2026-10-10）

Review 基线8be670cd7375c0c7f0352d7749bf8a7ff3114767，原分支/原Draft PR #8/base保持。S0 EIO/ENOSPC与临时副本负向证据成立；S1启动只读预检、迁移前保护、持久内容身份快照已实现；S2物理32MB低空间、WAL/并发/Retry/raw ZIP正负通过7/7，最终WAL补验5/5。S3集成与原Build12迁移6/6通过（2Unit+4UI，零运行警告），最终候选/提交/push/PR更新未完成，当前不标READY。权威命令、失败及保全/清理策略见 [限定修复记录](TODO_P1_DATA_PRESERVATION.md)。只处理两个P1，不新增Todo产品功能；V11.1/v7/五Tab/1.0(7)/原UX不变。

---

以下为上一轮独立审查交接，不代表本轮已经完成。

# Todo V1 ReviewFix + Usability — READY_FOR_INDEPENDENT_REVIEW（2026-10-10）

Owner 附件 `CODEX_GOAL_ZH.md` 的唯一整体Goal已连续完成S0→S4：两个P1先有真实失败回归，四项Review修复闭合，已有Open单次原身份转换重复、全部任务直接四状态筛选完成。重复提醒固定计划锚点优先/相对日±366/墙钟分钟；future模板同步已有Open后继并明确覆盖单独模板字段；保存与通知状态及时反馈；Todo完整性异常保留pre-open原字节、暂停正常写入并可导出raw支持恢复包，不自动修复/清库。

Repo `yoCruzer/PersonalGrowthOS`，原分支 `codex/todo-v1-personal-actions`、[Draft PR #8](https://github.com/yoCruzer/PersonalGrowthOS/pull/8)、base `codex/external-capture-v1` 均保持。起点 `4625602b27d8b4e4df4f6da20b7f11bf30b21d8c`；最终产品提交 `2065065e87863de5a452ade8609bac561a0bd096`；强化UI截图/断言候选 `678e47b4816b9ae92ab1768b4603159a3af3863b`（完整SHA以实际git/PR为准）。后续仅文档交接，最终仓库HEAD以PR head为准。候选已普通push；本次交接文档随后普通push同一PR，不merge/tag/改号/Archive/TestFlight。

最终完整Unit **297/297 PASS，0 FAIL/SKIP、零runtime warning**；首轮完整296/296因两项真实尾端缺陷修正后重跑，全部记录。集中关键UI首轮 **21/22 PASS、1 FAIL**（保存提示不在视野）；修复后 **6/6 UI PASS**，强化可触达/截图/About/Weight补验 **3/3 PASS**。不把首轮改标全绿。中文真实Dark与AX最大字号、五Tab、四统计1/1/3/1严格明细、连续录入/搜索/重启、真实Safari/Host分享和原功能贯通完成。

真实Simulator Debug/unsignedRelease App及唯一appex均1.0(7)，40位SHA自动注入/localGit/clean/Tag空；最终文档HEAD再核对真实Debug/Release资源。V11=11.1.0，冻结原11.0.0迁移节点；v7只增可选offset。原V1–V10 schema字节、615条原翻译、历史fixture、版本/签名/AppGroup设置不变；原Build12V10及原候选V11迁移/重开、v7精确往返与15类坏包通过。详见[验收与设备复现](TODO_V1_ACCEPTANCE.md)及[命令/退出码/失败审计](TODO_V1_EXECUTION_LOG.md#reviewfix--usability-统一-goal--2026-10-09)。

未关闭风险：旧候选已保存的错误提醒期次不自动改写，用户可显式编辑，新生成期次恢复正确偏移；raw ZIP只供支持恢复。UI仍有SwiftUI invalid-frame警告；集中Weight键盘输入阶段一次后台publication警告，在3项补验未复现，未声称根因已消除。真实私人Build12覆盖升级、真机签名/AppGroup/通知/设置、旅行/飞行模式、VoiceOver、实际Xcode Cloud/TestFlight均**NOT_RUN/OWNER_DEVICE_GATE**。远端workflows=0，独立CI NOT_RUN，不将空checks/statuses或aggregate pending当作CI通过。

下一边界仅独立Review和Owner设备门禁；停止当前实现，不继续合并或发布。

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

# 当前任务：External Capture v1 与项目遗留统一收口

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
