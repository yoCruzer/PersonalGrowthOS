# PR #9 限定 Review Fix — READY_FOR_INDEPENDENT_REVIEW（2026-10-14）

本轮读取附件 `REVIEW_ZH.md` 与 `CODEX_REVIEW_FIX_ZH.md`，继续原 OPEN Draft [PR #9](https://github.com/yoCruzer/PersonalGrowthOS/pull/9)。审查起点 `2c9e4ab16bd4ed5f9c69c8a479047b198c1da4af`；固定产品/测试修复提交 **`69ad37fc12ddf6fbf15853f0a0174d6f5e5d9218`**。后续仅三份交接文档；最终完整 SHA 以原 PR head、本地 Git 和 `/tmp/pgos-quiet-wins-review-evidence/final-head-build-proof.json` 的同源核对为准，不在文档中制造自引用 SHA。

原 worktree 属于另一任务，未改变其归属或内容；本任务从同一 HEAD 创建 Codex 管理工作树 `/Users/himini/.codex/worktrees/quiet-wins-review-fix/PersonalGrowthOS`。普通推送目标仍为 `codex/quiet-wins-on-d72`，PR base 仍为 `codex/todo-v1-personal-actions`，没有另建 PR、强推或重置。原工作区的 project、xcstrings、xcodecloud 未提交改动保留。只读核对 PR #8 仍 OPEN Draft、head=`d72c016dd34c8114cf44744d0e061b95bd312091`、base=`codex/external-capture-v1`。

## R1 / R2 实际结论

**R1 成立（P1），现有来源证据的本地漏用已修复。** 真实 `ShareInbox.publish` → `ExternalCaptureImporter` → 临时磁盘 SwiftData 库证明，无 URL 纯文字/纯图片有同 Entry ID 的收据，却没有 `EntryExternalSource`，旧投影仍把两者计入生活记录。修复只在 Reader 合并当前窗口 Entry ID 对应的两种外部来源证据；不以 `importedAt` 的窗口筛选收据，不改 importer 或补造来源。合成收据时间在读取的历史窗口之外，仍应排除。

正负对照包括 source=nil 文字/图片、有 URL 分享、App 内直接文字/图片；调用真实 `EntryDeletionService` 删除导入后保留收据，再发布同一分享不复活 Entry/卡片。原内容/时间/身份/图片 metadata 完整 v7 导出前后相等、图片原字节不变；读取各阶段 `willSave=0`、无保存副作用。

**v7 恢复限制经 Owner 明确接受，未冒称全部恢复口径保持。** 首轮修复测试在导出→空库恢复→重开时仍失败：现行 `TransferData` 不序列化 `CaptureImportReceipt`，恢复也不构造它。URL 来源恢复后仍排除；source=nil 外部文字/图片恢复后失去唯一可辨认来源，会按普通记录进入投影。独立 Agent 核对了 `TransferData`、导出/恢复源码与实际失败 xcresult。Owner 明确选择“保持冻结范围，明确记录恢复限制”；随后回归精确断言收据为空、URL 仍排除、直接内容保留及两份 source=nil 内容重新进入，而不是悄悄将原失败重标为通过。不改 v7 格式、恢复流程或原记录，不靠正文/时间猜来源。没有任何来源元数据的手动粘贴也不在可辨认范围内。

**R2 成立（P2），以局部投影修复。** 首页 `cards` 仍最多五张，新增内存 `evidenceCards` 保留同一窗口内所有当前有效候选；明细以生成的类型/稳定 ID 查找该集合。仍每次真实重读，不缓存旧卡、不增加持久化实体或导航平台。五类型齐全时，习惯 A 昨天+今天两天、B 只有今天；撤销 A 今天后首页推荐 B，但 A 明细继续显示昨天一条/一天。A 最后事实删除后正确降级。引擎同时配对验证 Goal 被更近完成事实挤出首页后仍有效，重新激活后才失效。

后台真实导入 UI 首次复现 `Publishing changes from background threads…` 运行警告；没有观察到崩溃。两个 Quiet Wins 页面的 `didSave` publisher 改用主队列交付，仍接收同一容器其他 context 的成功保存，未只过滤 mainContext。相同后台导入/排名 UI 补跑不再出现该警告；不扩大为全应用线程问题已解决。

## 本轮实际门禁、失败与未执行

macOS 27.0.1 / Xcode 27.0 (27A266a)，iPhone 18 Pro / iOS 27.0 (24A434) Simulator，UDID `FD666264-A2DF-445C-A77D-534B9E8ED595`。仅公开合成临时库、图片、分享和专用 UI 测试数据；证据目录 `/tmp/pgos-quiet-wins-review-evidence`，DerivedData `/tmp/pgos-quiet-wins-review-derived`。

| Run | 实际结果与边界 |
| --- | --- |
| r1-red | 沙箱无法连接 CoreSimulator，exit70，未执行 App 测试；不算产品红测。 |
| review-red-2 | 正式权限运行，exit65，0/2 Unit PASS，2 FAIL，0 SKIP/warnings：真实 source=nil 导入错误来源 ID、排名更替后明细 nil。附件的 Foundation 探针没有复制进 App，也未冒称 App 测试。 |
| focused-green-1 | exit65，15/16 Unit PASS，1 FAIL，0 SKIP/warnings；R2 与本地 R1 通过，唯一失败为上述现行 v7 恢复来源丢失，原结果保留。 |
| affected-gate-1 | exit0，**44/44 Unit + 3/3 UI PASS**，0 FAIL/SKIP。Unit 为全部 16 Quiet Wins、全部 27 ExternalCapture、1 完整 Todo v7 往返；UI 为五来源/撤销/重启、A/B 排名/最后来源删除、首页和明细保持打开时后台真实导入/快速范围切换/源导航。两条运行警告分别为旧五来源周回顾 invalid-frame，以及新后台导入 publication；不称零警告。 |
| ui-main-delivery-1 | 只改两个保存通知的交付队列后，exit0，**2/2 UI PASS**，0 FAIL/SKIP，`runtimeWarnings=[]`；配对排名与真实后台导入仍通过。Unit/存储源码与上一组字节相同，没有重新跑或冒称“最终49项全量”。 |

真实 UI 截图已导出并查看：A 明细标题为 1 天，来源仅昨天；后台导入后原 Entry 正文仍为合成原值。两项新 UI 测试使用 DEBUG + 专用 UI-testing 参数下的夹具/读值标记/触发按钮：实际调用生产 importer 并观察新的读取时间，普通启动无入口，Release 不编译。范围切换是轻量集成用例，不是强制乱序的取消压力证明。

实际命令（均在本任务 worktree；每个 run 的独立 log/xcresult 保留）：

```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-quiet-wins-review-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-quiet-wins-review-evidence/affected-gate-1.xcresult -only-testing:PersonalGrowthOSTests/QuietWinsTests -only-testing:PersonalGrowthOSTests/QuietWinsReaderTests -only-testing:PersonalGrowthOSTests/ExternalCaptureTests -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests/testTodoV7RoundTripPreservesOccurrencesEventsListsSourcesAndOriginalMedia -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testQuietWinsHabitRankingKeepsSurvivingEvidenceAndDeletionInvalidatesIt -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testQuietWinsOpenPagesRefreshAfterRealBackgroundImportAndRapidRanges -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testQuietWinsFiveSourcesRangeAndTodoUndoRefresh > /tmp/pgos-quiet-wins-review-evidence/affected-gate-1.log 2>&1
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-quiet-wins-review-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-quiet-wins-review-evidence/ui-main-delivery-1.xcresult -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testQuietWinsHabitRankingKeepsSurvivingEvidenceAndDeletionInvalidatesIt -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testQuietWinsOpenPagesRefreshAfterRealBackgroundImportAndRapidRanges > /tmp/pgos-quiet-wins-review-evidence/ui-main-delivery-1.log 2>&1
xcrun xcresulttool get test-results summary --path /tmp/pgos-quiet-wins-review-evidence/affected-gate-1.xcresult
xcrun xcresulttool get test-results tests --path /tmp/pgos-quiet-wins-review-evidence/affected-gate-1.xcresult
xcrun xcresulttool get object --legacy --path /tmp/pgos-quiet-wins-review-evidence/affected-gate-1.xcresult --format json
xcrun xcresulttool export attachments --path /tmp/pgos-quiet-wins-review-evidence/affected-gate-1.xcresult --output-path /tmp/pgos-quiet-wins-review-evidence/affected-gate-1-attachments
```

红测与首轮修复使用同一通用命令：review-red-2 只选 `QuietWinsReaderTests/testSourceNilRealImportsAreExcludedAndDirectRecordsSurviveRestoreReopen`（当时的原测试名）与 `QuietWinsTests/testHabitAndGoalEvidenceSurvivesHomepageRankingButNotRealInvalidation`；focused-green-1 选全部 QuietWinsTests + QuietWinsReaderTests。Owner 接受限制后，恢复测试改名为 `testSourceNilRealImportsAreExcludedAndFrozenV7RestoreBoundaryIsExplicit`。

最终交接 HEAD 的 Debug / unsigned Simulator Release 与 App/唯一 appex 的完整 SHA、Dirty、Tag、Bundle ID、版本核对记录在 `final-head-build-proof.json`；对应 `final-head-debug.log` 与 `final-head-release.log`。构建命令为 `xcodebuild build -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pgos-quiet-wins-review-derived CODE_SIGNING_ALLOWED=NO`，Release 使用 `-configuration Release` 和 `/tmp/pgos-quiet-wins-review-release-derived`，分别重定向到上述日志。`git diff --check` 通过；产品修复仅三个 Quiet Wins 文件，测试仅两个现有文件，交接仅本文和两份 CURRENT 文档。

## 独立复审与停止边界

未参与实现的 `independent_review` Agent 对固定 `69ad37fc12ddf6fbf15853f0a0174d6f5e5d9218` 的五文件完整 diff、保护文件零差异、真实红测/恢复失败/47项门禁/主队列2UI补跑 xcresult 和排名截图逐项核验：**没有新的 confirmed P0/P1/P2**，可交接。该 Agent 没有修改代码或启动竞争测试；独立读取结果不冒称独立重新执行全部测试。

保留已披露 **Goal 时钟回拨 P2**、Owner 接受的 **source=nil 分享 v7 恢复来源缺失限制**，以及旧周回顾 invalid-frame 警告。完整300+ Unit 本轮 **NOT_RUN**，因只读查询/投影/通知交付局部变化，已执行全部受影响模块及关键 UI；不复用历史324/324冒称新候选全量。只读 GitHub workflows 数量仍为0，独立远端CI **NOT_RUN**；真实设备/私人库/签名/AppGroup/实际Cloud/VoiceOver与发行 **NOT_RUN/OWNER_DEVICE_GATE**。

Schema/迁移、v1–v7备份、ExternalCapture/ShareInbox、Todo/提醒/Recovery、工程/签名、Bundle ID/AppGroup/版本全部相对本轮起点零生产差异。只普通 push 更新原 Draft PR #9，停在 **READY_FOR_INDEPENDENT_REVIEW**；不修改 PR #8、不 merge/tag/Archive/TestFlight、不访问真实手机或私人数据。下方为原交付历史，不再指挥本轮进入发行。

---

# Quiet Wins V0 — Todo-first / d72c016

日期：2026-10-13。Owner 唯一 Goal：附件 `GOAL_QUIET_WINS_TODO_FIRST_ZH.md`（2026-10-13 ZIP，替代旧 ZIP）。连续 R0→R1→跳过 R2→Q1→Q2→Q3→Q4。**READY_FOR_OWNER_REVIEW_AND_TESTFLIGHT_GATE**。实现、独立审查、针对性闭环与本机门禁完成，已普通push并创建新 [Draft PR #9](https://github.com/yoCruzer/PersonalGrowthOS/pull/9)。不进入发行。

## 基线、数据与交付边界

- 精确父提交：`d72c016dd34c8114cf44744d0e061b95bd312091`。Owner 已安装对应版本，是用户提供的事实；本轮未访问其真实数据或独立验证安装二进制。
- 原工作区保留未提交 project、xcstrings、xcodecloud 配置。使用 Codex 管理的工作树 `/Users/himini/.codex/worktrees/quiet-wins-on-d72/PersonalGrowthOS`，正常新分支 `codex/quiet-wins-on-d72`；没有覆盖、stash/reset/rebase 原工作区。
- 2026-10-13 只读 `gh pr view 8 --json headRefOid,headRefName,baseRefName,state,isDraft,url`：PR #8 OPEN Draft，head=d72c016，base=`codex/external-capture-v1`。原 PR/分支不修改；新 Draft PR #9 的 base 为 `codex/todo-v1-personal-actions`。最终交接仅补本文和两份当前上下文；最终完整HEAD以本地git/PR远端一致性核对为准。
- Bundle ID `com.yocruzer.PersonalGrowthOS`、App Group、Team、版本/构建号、容器、五 Tab 不改。V1–V11.1 模型/迁移、v1–v7 备份、Todo/通知/启动保全/ShareInbox 的生产文件与基线字节相同。App 的唯一额外启动代码是既有 UI-test 模式且 reset+显式 synthetic flag 下的 DEBUG fixture；Release 无该路径。
- 无私人 ZIP/数据库/照片读取，无真实设备连接/安装/重置。Quiet Wins 生产路径不联网、不用AI、不申请权限、不创建持久 QuietWin 实体；GitHub交付与原Safari本机合成服务器测试另属已授权验证。只操作本轮合成临时目录与 UI 测试模拟器。不 merge、tag、Archive、TestFlight、不修改 PR #8。

## R1 独立 Todo Review

实现者之外的 `todo_review` Agent 对精确干净 d72c016 完成只读审查：**No confirmed P0/P1 from scoped review**；P0=0，P1=0，无新确证 P2。因此跳过 R2，无 Todo 修复或空修复 commit。

| 主题 | 核对符号与证据范围 |
| --- | --- |
| 启动保全 | `AppContainer.make`、`StartupRetainedData.capture/storeSignature/withFrozenStore`；路径规范化、内部 symlink 拒绝、WAL、完整副本身份、失败停写与保留。读取 alias/EIO/ENOSPC/Retry/并发测试和历史 259 报告。 |
| Todo 事实 | `TodoTaskService.transition/generateNext/edit`、`TodoIntegrity.validate`；完成使用当前状态/真实 completedAt，reopen/cancel 清除，撤回复用不复活主动取消，稳定系列/期次身份。 |
| 提醒/来源 | `TodoEditorView.save`、`TodoReminderCoordinator`、`deleteContinuations`；保存与排队区分，权限失败保留任务，不误删其它提醒；删除只解除来源。 |
| 数据往返 | `TodoTransferInstant`、v7 五数组/精度/引用与历史版本拒绝规则；合法 v1–v6、完整 v7 原媒体与身份往返、坏包/取消/回滚测试。 |
| 核心 UI | Today toolbar、Todo Hub 统计同 predicate、详情 reopen 与局部/全局检索；读取已有连续输入/统计严格明细/中文 AX 等测试。 |

以上是独立代码审查与既有覆盖读取，**不是 R1 新执行测试**。原 311/311 历史门禁不冒称本轮结果。历史真实 259 现场归因/私人库/设备通知/签名仍保留原 UNKNOWN/OWNER_DEVICE_GATE。

## 实现与事实规则

`QuietWinsEngine` 接受轻量值快照和冻结 `asOf/timeZone`，只返回内存投影。自然日含今天，截止真实 asOf，排除今天未来时刻；使用既有公历政策和 `HabitLocalDay`，不按 N×24 小时。

- Goal/Flag：当前 completed、真实 completedAt 在范围；存在生命周期时保守核对日期最新的事件。归档/重激活不算；不拿 updatedAt 代替完成时刻。
- Todo：当前 completed + completedAt；期次按 task ID，不读取历史完成事件造卡，排除未来/取消/跳过/撤销。
- Habit：正向日志，只接受合法的已有持久本地日；多次同日只算一个活跃日，所有实际log ID留作来源。缺失/非法元数据均保守排除，不从occurredAt与当前时区猜原日，不写入/删除/补元数据。合法legacyBootstrap日仍保留，它是原项目持久历史日期政策，不冒称可证明原写入时区。只说“有打卡”，不计算达标/遵守率/连胜/趋势，不依赖计划或生命周期去推断成就。
- Entry：以 occurredAt 选范围，仅合法 quickNote 内容（正文或图片）；排除 Review、空技术行、EntryExternalSource。置顶/后续附记不增加来源数；不做正文语义分类。
- WeeklyReview：仅完成记录，用 canonical weekIdentifier 选择与范围重叠周次；界面明确“重叠周次，不推断完成时刻”，不用 updatedAt。
- 同 ID 完全重复压成一项；矛盾重复输入保守隐藏。稳定日期/ID tie-breaker。优先 Goal、Todo、Habit，再中性记录/复盘，每类先一项，不足再填 Goal/Habit，最多五卡，没有总成长分。

`QuietWinsReader` 在 detached task 内创建独立 ModelActor，关闭其 autosave，按最大90天有界查询，不在 SwiftUI body 重做历史全表聚合。Habit只以范围内持久civil metadata批量取正向日志与ID映射，不再补抓无法证明原本地日的legacy instant，没有每卡 N×M 查询。过滤与聚合均后台；取消传递给 worker、各查询组检查 cancellation，旧请求不发布结果。无 insert/save/bootstrap/通知/网络。

Growth 增加“成长回顾”，Today 和原五 Tab 不增加常驻内容。7/30/90天菜单、具体日期、空态、最多五事实卡；卡→类型化明细→稳定源 ID 的现有 Goal/Todo/Habit/Entry/WeeklyReview 详情。图片原文仍在原 Entry；Habit 明细列每个真实日志日，并到所属 Habit 的原详情/历史。返回、保存通知、前台、显著时间改变重读；来源消失或不再完成时安全降级。

## Q4 独立 Review 与残余 P2

`quiet_wins_review` Agent 两次因 model capacity 失败，**没有产生审查，不计作通过**。随后由未参与实现的 `todo_review` Agent 实际独立读取全部新增源、测试、工程/导航/翻译 diff 和既有详情，核对真实 xcresult 和 Dark PNG：**没有 confirmed P0/P1 阻塞项**。

最终固定候选复审：`todo_review` 实际重新审查完整 `a4a716df5f674b2add1e6cb1071902bd11cb93f9` 生产diff/13项测试，并对 `d88585a0613f60bc27075ea6fbd6c059b713b86f` 的两项测试交互做终端核验；结论：没有 confirmed、范围内的 P0/P1 阻塞项。直接核验324/324完整Unit、干净Release资源、7/8原UI失败及补跑Safari1/1。没有让实现者自审冒充独立审查。

提交分类：`a4a716d` 为Quiet Wins产品/测试/初始报告，父提交精确d72；`2f803cb0b456bf1d6673e7618033179c270a0f0f`、`d88585a0613f60bc27075ea6fbd6c059b713b86f` 仅修正既有Safari测试键盘Search/Go的屏幕外AX点击为已聚焦字段的原生Return。产品及Unit源码/工程与a4字节相同，所有分享/取消/来源/重启内容断言保留。无Todo修复commit；其后 `3174b0e` 只改交接文档。最终D3审计收紧另有 `4c13d9f746238305c91fd6faa4321dd3ff6a0c61`：仅新引擎/Reader不再猜未知Habit日期，加跨时区正负和跨周边界断言；旧生产存储与Todo未改。最后一次独立Agent终审直接核验该提交和21Unit+2集成结果，无剩余confirmed范围内P0/P1。

一项 P2：`QuietWinsReader.read` 中 Goal 生命周期按最大 occurredAt 保守验证；创建后时钟回拨再完成时，当前 completedAt 虽在窗口内，较晚日期的 created/resumed 事件会使卡片漏显。无虚假成就/写入/数据丢失。`testGoalClockRollbackRemainsConservativeAndReadOnly` 固定这种保守行为，不为它改模型或扩展事件顺序协议。旧 WeeklyReview 导航与原Todo重复详情的 `Invalid frame dimension` 运行警告在集中 UI 组各复现一次，记录为原相邻页面风险，未声称根因消除。

## 实际验证与失败保留

环境：macOS27.0.1、Xcode27.0(27A266a)，iPhone18Pro/iOS27.0(24A434) Simulator，UDID `FD666264-A2DF-445C-A77D-534B9E8ED595`。日志、xcresult、截图位于 `/tmp/pgos-quiet-wins-evidence`；DerivedData=/tmp/pgos-quiet-wins-derived。所有素材公开合成。

| Run | 实际结论 |
| --- | --- |
| engine-1 | exit65，测试编译失败：负载 map 遗漏 `_ in`；未执行测试。保留原 log。 |
| engine-2 | exit0，10/10 Unit，0FAIL/SKIP/runtimeWarnings；事实正负、时区/DST/闰日、去重稳定、只读保存观察与刷新。 |
| ui-1 | exit65，1/2 UI；中文最大字号/空态通过，五来源在周回顾使用错误 TextView 选择器失败。真实字段是 TextField，未放宽内容断言。含原 WeeklyReview invalid-frame warning。此时截图为 Light，不称 Dark 通过。 |
| ui-2 | exit0，1性能Unit+1五来源UI=2/2；修正周回顾字段定位/滚动，原值断言保留，撤销/重启完整；有同一 invalid-frame warning。 |
| dark-1 | exit0，1/1 UI，外观设置命令因 Simulator Shutdown 失败，不用作真实Dark证据。 |
| dark-2 | 显式 boot→bootstatus→`simctl ui … appearance dark` 返回 dark；exit0，1/1 中文最大AX/空态与语义audit，0warnings；导出PNG并实际查看，Dark、多行无文字裁切。 |
| d72-baseline-build | exit0，精确 `git archive d72c016` 的原 Debug Simulator App。归档无.git首产物Commit未知，不冒称来源已注入。 |
| d72-provenance-build | exit0，本地控制输入 CI_COMMIT=完整d72SHA、无CI_TAG；实际plist一致，Source=xcodeCloud只是脚本字段，**不是实际Cloud运行**。 |
| d72-overlay-1 | 将原App安装并用其既有 `-PGOSTodoFiltersTest` 产生5个合成任务；候选覆盖同Bundle ID，测试无reset/seed，exit0，1/1 UI、0warnings；Open3/完成1/FilterDone来源/重开保持。仅证明该合成Todo样本覆盖。 |
| facts-1 | exit0，2/2 Unit、0warnings；真实纯图片/补录/外部/Review/附记/置顶及完整导出前后精确相等，willSave=0；保守Goal回拨配对。 |
| final-unit（a4a716d） | exit0，**324/324 Unit PASS**、0FAIL/SKIP/warnings；测试树内新增13项全部Passed。含既有原V10/原V11/V7/V8、v7及旧合法包/坏包、媒体、WAL/并发/取消/回滚/提醒和本轮32MBHFS+真实低空间门禁。卷已正常卸载。 |
| final-release（a4a716d） | exit0，unsigned Simulator Release App/唯一appex均1.0(7)，原Bundle IDs；实际Commit=完整a4SHA、Source=localGit、Dirty=false、Tag空；Debug实包同样通过。 |
| final-ui（a4a716d） | **INTERRUPTED / exit UNKNOWN**：续跑核验时原session handle失效，ps无xcodebuild进程、xcresult缺Info.plist；不计完成、不推算8项通过。原日志/不完整包保留。 |
| final-ui-2（a4a716d） | exit65，**7/8 UI PASS、1FAIL**、0SKIP、两条invalid-frame warnings；唯一失败为App搜索键盘Search AX屏幕外点击，尚未启动Safari/扩展。七项为QuietWins五来源/撤销/重启、Todo核心/重复/来源、Files备份预览取消恢复、启动安全Retry、Record。 |
| safari-final-1（2f803cb） | exit65，0/1 UI，0warnings；App Search原生Return通过，下一失败为Safari Go AX屏幕外点击，尚未进入扩展。保留原失败，不当作分享代码缺陷。 |
| safari-final-2（d88585a） | exit0，**1/1 UI PASS**、0FAIL/SKIP/warnings；App search与Safari Go均原生Return，其余网页/真实扩展/取消重开/保存/来源重开/重启断言完整。所有八条关键路径各有通过证据，**不是原整组重新全绿**；无新production/Unit代码，不重复全量。 |
| day-guard-red | exit65，0/1 Unit、1FAIL；旧引擎在UTC/Shanghai/LosAngeles对无持久日日志猜日期，保留红测。正常d72 AppContainer启动、import发布和check-in均已有成对bootstrap/元数据，不把此纯投影边界证明为Owner数据或Todo故障。 |
| day-guard-green（4c13d9f同源工作树） | exit0，**21/21 Unit PASS**、0FAIL/SKIP/warnings，14QuietWins+7相邻bootstrap/旧数据路径。原命令v7 selector误放TodoFoundationTests，未执行该项，不写22/22。 |
| day-guard-integration（同源工作树） | exit0，正确ImportExportRecoveryTests类的完整v7往返1Unit + 受影响五来源/撤销/重启1UI=**2/2 PASS**，一条已有WeeklyReview invalid-frame warning。D3后总22项定向Unit及1UI有通过证据，不重跑/重标旧324为最终325全量。 |

初始定向性能真实指标（D3收紧前）：pure projection（4000Todo/4000Entry/20000Log/25Habit）0.240077916s；磁盘reader（4000Entry/4000Todo/20000Log，半数为400天前数据）0.464396209s，main heartbeat0.013036875s，进程peakRSS读取前/后均516145152bytes。RSS含fixture构建与测试进程，不称功能占用516MB或“零内存分配”；90天投影只保留2000Todo/2000Entry/10000Log。单设备Debug合成指标不是真机性能承诺。 最后D3源码的day-guard-green同规模实测：projection=0.220890417s、reader=0.245807s、main heartbeat=0.012273084s；进程peakRSS前/后均541278208bytes。所有读写保护/计数断言保持。

可复现通用命令（每次真实run有独立日志/结果包）：

```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-quiet-wins-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-quiet-wins-evidence/<run>.xcresult <selectors> > /tmp/pgos-quiet-wins-evidence/<run>.log 2>&1
xcrun xcresulttool get test-results summary --path /tmp/pgos-quiet-wins-evidence/<run>.xcresult
xcrun xcresulttool export diagnostics --path /tmp/pgos-quiet-wins-evidence/<run>.xcresult --output-path /tmp/pgos-quiet-wins-evidence/<run>-diagnostics
xcrun xcresulttool export attachments --path /tmp/pgos-quiet-wins-evidence/<run>.xcresult --output-path /tmp/pgos-quiet-wins-evidence/<run>-attachments
```

Selectors：engine-1/2=QuietWinsTests+QuietWinsReaderTests；ui-1=两个QuietWins UI；ui-2=五来源UI+磁盘性能Unit；dark-1/2=中文Dark/AX/空态UI；d72-overlay-1=精确旧版本覆盖UI；facts-1=图片/完整导出和Goal回拨两个ReaderTests。类前缀 `PersonalGrowthOSTests/` 或 `PersonalGrowthOSUITests/AppLaunchSmokeTests/`。final-unit选`-only-testing:PersonalGrowthOSTests`；final-ui/final-ui-2选八个方法：`testQuietWinsFiveSourcesRangeAndTodoUndoRefresh`、`testTodoQuickContinuousInputCompletionStatisticsSearchAndRestart`、`testTodoDailyRepeatCompletionSkipStopAndRestartKeepsOneOpenOccurrence`、`testTodoEntrySourceKeepsOriginalRecord`、`testExternalCaptureSafariShareAndImport`、`testPR6FilesPreviewCancelAndRestore`、`testStartupDiagnosticCopiesAndSafeRetryPreservesExistingEntry`、`testRecordTabIsTheNativeCaptureDestination`。safari-final-1/2只选Safari方法。

```sh
xcodebuild build -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pgos-quiet-wins-release-derived CODE_SIGNING_ALLOWED=NO > /tmp/pgos-quiet-wins-evidence/final-release.log 2>&1
hdiutil create -size 32m -fs HFS+ -volname PGOS_QuietWins_Test /tmp/pgos-quiet-wins-evidence/low-space.dmg
hdiutil attach /tmp/pgos-quiet-wins-evidence/low-space.dmg -mountpoint /tmp/pgos-p1-low-space -nobrowse
touch /tmp/pgos-p1-low-space/RUN_LOW_SPACE_TEST
hdiutil detach /tmp/pgos-p1-low-space
```

最后D3产品修订为4c13d9f；其后的交接文档HEAD只改变文档，不改变最后定向验证源码。最终本地Debug/unsignedRelease资源会按该HEAD再构建核对；实际命令输出与完整SHA保存到 `/tmp/pgos-quiet-wins-evidence/final-head-build-proof.json`，源/测试门禁仍准确归属于上述固定提交，不制造文档自引用SHA。

day-guard-green selectors为全部QuietWinsTests+QuietWinsReaderTests，以及HabitFoundationTests的`testAnalyticsBootstrapFreezesLegacyLocalDaysAndStartsConservativeCoverage`、`testV7StoreMigratesAndBootstrapsHabitAnalyticsWithoutChangingHistory`、`testExactBuild7V7FixtureMigratesBootstrapsAndReopensWithoutDataLoss`、`testPersistedLocalDayControlsOncePerDayDuplicateAndTodayProgress`、`testRepeatableCounterDecrementUsesPersistedLocalDayAndSkipsFalseLogs`，TodoFoundationTests的`testExactBuild12V10FixtureMigratesAndReopensPreservingAllOldFactsAndMedia`、`testOriginalV11CandidateMigratesWithoutLosingTaskEventBytesAndInfersReminderLead`。误类名v7选择器未执行；day-guard-integration以`ImportExportRecoveryTests/testTodoV7RoundTripPreservesOccurrencesEventsListsSourcesAndOriginalMedia`与五来源UI补齐。

其它已执行：git diff --check、project plutil PASS；原629条字符串值与基线逐条相等，新增23键全部en/zh-Hans完备；保护生产文件字节不变。最初注册工程脚本找错Sources phase、工具沙箱读取xcresult TestReport需权限、console日志不可用、Dark设置Shutdown等命令失败已保留到实际工具记录；均未当功能通过，已用真实工程phase、结果诊断和明确boot纠正。

## 验收对应与最终边界

| 案例 | 直接证据 |
| --- | --- |
| A1 | 空输入/未完成/外部正负Unit；中文空态实际UI。 |
| A2 | completedAt/当前状态/lifecycle/归档/重新激活纯Unit；真实Goal详情导航；回拨保守读取Unit。 |
| A3 | 期次ID去重/撤销/取消/未来Unit；真实Todo详情撤销、首页消失、重启UI；全量原Todo系列测试。 |
| A4 | 正向/false/同日次数/持久日旅行/孤儿Unit与Reader；D3三时区未知日红→绿、合法持久日配对与磁盘未知日零写入排除；旧bootstrap日保留，仅有打卡文案。 |
| A5 | occurredAt/内容/Review/external/去重Unit；真实图片关系与完整原数据导出前后相等Reader；Entry正文UI。 |
| A6 | 合法周次重叠/未完成/非法/未来Unit，以及7天窗口从周三起、前一周周一来源正确纳入的部分重叠断言；原WeeklyReview精确文本UI；不使用更新时间。 |
| A7 | 7/30/90/跨年/闰日/DST/asOf未来Unit；范围切换实际UI。 |
| A8 | 五来源现有详情UI；Todo撤销后的源降级与卡消失、重启UI；删除源读取Unit。 |
| A9 | 英文Light/中文实际Dark最大AX截图与语义audit；五Tab断言，原Today未改。 |
| A10 | Reader willSave=0、hasChanges=false、源时间/事件不变、完整v7原数据及图片不变；生产保护文件零diff；精确d72模拟Todo覆盖。不等同私人手机验证。 |
| A11 | 公开合成load真正磁盘查询+main heartbeat+peakRSS，真实规模/耗时见上。 |

## 后续原 App 覆盖升级准备（本轮不发行）

只读 `gh api repos/yoCruzer/PersonalGrowthOS/actions/workflows` 返回total_count=0；独立远端CI **NOT_RUN**，不把空checks当成功。原工作区未提交的Cloud manifest仅含product/target标识，没有trigger规则，未修改。实际Xcode Cloud工作流/tag触发分支规则在本轮未访问服务器，仍 **OWNER_REQUIRED**。Apple官方说明工作流由Start Conditions决定分支/tag等触发，历史标签不能代替服务器配置核对：[Xcode Cloud workflow说明](https://developer.apple.com/videos/play/wwdc2023/10278/)。历史 `testflight-` 标签只是既有发行记录，不能证明当前Cloud规则；不得复用旧tag。

Owner审查完成并另行授权发行后：核对实际Cloud工作流接受新候选commit及`testflight-`前缀/分支；App+Extension构建SHA同源、签名/Team/AppGroup一致；按[Apple构建号要求](https://help.apple.com/xcode/mac/current/en.lproj/devba7f53ad4.html)，新发行前递增CFBundleVersion，并与AppStoreConnect当前已上传最高号核对（仓库基线仍1.0(7)，Owner已装本地Build16的历史记录不是新的发行号授权）。保持原Bundle ID/容器，采用原App TestFlight覆盖升级，保全现有数据与可恢复备份，不卸载或清库。本轮不打tag、不改号、不归档、不上传、不安装真机。

未来5–10分钟设备检查：

1. 升级前由Owner确认可用备份/保全；核对候选来源完整SHA和递增build。
2. 从原App正常覆盖升级，抽样旧Entry原文/图片、Habit历史、Weight、Goal、Todo清单/状态及提醒，重启仍在。
3. Growth→成长回顾，切7/30/90天，核对具体日期与少量真实证据，不出现收藏伪成就或总分。
4. 打开Goal/Todo/Habit/Entry/周回顾来源，日期/周次/数量与真实事实相符。
5. 撤销一次Todo完成，返回卡片与明细更新；重新完成、编辑或删除来源后不留幽灵卡。
6. 验证纯图片/补录记录、同日多打卡不同日数、旅行后的既有Habit本地日稳定。
7. 简中、英文，以及繁中系统语言下的实际回退效果；真实Dark/Light、较大字号/VoiceOver触达，Today及原录入操作仍流畅。V0翻译范围为en/zh-Hans，繁中设备体验本轮NOT_RUN，不宣称繁体本地化完整。
8. Owner自行按正常路径确认v7备份可用与真机通知实际送达；这两项不由只读功能或模拟器合成验证替代。

真实Owner数据、相机/通知硬件、签名/AppGroup配置、私人覆盖升级、真机VoiceOver/性能、实际Cloud/TestFlight全部 **NOT_RUN/OWNER_DEVICE_GATE**。原259及原PR#8历史证据保留。
