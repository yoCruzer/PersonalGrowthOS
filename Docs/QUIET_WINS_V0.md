# Quiet Wins V0 — Todo-first / d72c016

日期：2026-10-13。Owner 唯一 Goal：附件 `GOAL_QUIET_WINS_TODO_FIRST_ZH.md`（2026-10-13 ZIP，替代旧 ZIP）。连续 R0→R1→跳过 R2→Q1→Q2→Q3→Q4。当前实施完成，集中固定候选门禁及最终交付尚在进行；不提前标 READY。

## 基线、数据与交付边界

- 精确父提交：`d72c016dd34c8114cf44744d0e061b95bd312091`。Owner 已安装对应版本，是用户提供的事实；本轮未访问其真实数据或独立验证安装二进制。
- 原工作区保留未提交 project、xcstrings、xcodecloud 配置。使用 Codex 管理的工作树 `/Users/himini/.codex/worktrees/quiet-wins-on-d72/PersonalGrowthOS`，正常新分支 `codex/quiet-wins-on-d72`；没有覆盖、stash/reset/rebase 原工作区。
- 2026-10-13 只读 `gh pr view 8 --json headRefOid,headRefName,baseRefName,state,isDraft,url`：PR #8 OPEN Draft，head=d72c016，base=`codex/external-capture-v1`。原 PR/分支不修改；新 Draft PR 的 base 计划为 `codex/todo-v1-personal-actions`。
- Bundle ID `com.yocruzer.PersonalGrowthOS`、App Group、Team、版本/构建号、容器、五 Tab 不改。V1–V11.1 模型/迁移、v1–v7 备份、Todo/通知/启动保全/ShareInbox 的生产文件与基线字节相同。App 的唯一额外启动代码是既有 UI-test 模式且 reset+显式 synthetic flag 下的 DEBUG fixture；Release 无该路径。
- 无私人 ZIP/数据库/照片读取，无真实设备连接/安装/重置，无网络/AI/权限/持久 QuietWin 实体。只操作本轮合成临时目录与 UI 测试模拟器。不 merge、tag、Archive、TestFlight、不修改 PR #8。

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
- Habit：正向日志，存储本地日优先；多次同日只算一个活跃日，所有实际 log ID 留作来源。缺元数据沿用既有 occurredAt/当前时区回退，非法元数据直接排除。只说“有打卡”，不计算达标/遵守率/连胜/趋势，不依赖计划或生命周期去推断成就。
- Entry：以 occurredAt 选范围，仅合法 quickNote 内容（正文或图片）；排除 Review、空技术行、EntryExternalSource。置顶/后续附记不增加来源数；不做正文语义分类。
- WeeklyReview：仅完成记录，用 canonical weekIdentifier 选择与范围重叠周次；界面明确“重叠周次，不推断完成时刻”，不用 updatedAt。
- 同 ID 完全重复压成一项；矛盾重复输入保守隐藏。稳定日期/ID tie-breaker。优先 Goal、Todo、Habit，再中性记录/复盘，每类先一项，不足再填 Goal/Habit，最多五卡，没有总成长分。

`QuietWinsReader` 在 detached task 内创建独立 ModelActor，关闭其 autosave，按最大90天有界查询，不在 SwiftUI body 重做历史全表聚合。Habit 以范围内 civil metadata 取日志并补已存在的合法 legacy instant 范围，批量 ID 映射，没有每卡 N×M 查询。过滤与聚合均后台；取消传递给 worker、各查询组检查 cancellation，旧请求不发布结果。无 insert/save/bootstrap/通知/网络。

Growth 增加“成长回顾”，Today 和原五 Tab 不增加常驻内容。7/30/90天菜单、具体日期、空态、最多五事实卡；卡→类型化明细→稳定源 ID 的现有 Goal/Todo/Habit/Entry/WeeklyReview 详情。图片原文仍在原 Entry；Habit 明细列每个真实日志日，并到所属 Habit 的原详情/历史。返回、保存通知、前台、显著时间改变重读；来源消失或不再完成时安全降级。

## Q4 独立 Review 与残余 P2

`quiet_wins_review` Agent 两次因 model capacity 失败，**没有产生审查，不计作通过**。随后由未参与实现的 `todo_review` Agent 实际独立读取全部新增源、测试、工程/导航/翻译 diff 和既有详情，核对真实 xcresult 和 Dark PNG：**没有 confirmed P0/P1 阻塞项**。

一项 P2：`QuietWinsReader.read` 中 Goal 生命周期按最大 occurredAt 保守验证；创建后时钟回拨再完成时，当前 completedAt 虽在窗口内，较晚日期的 created/resumed 事件会使卡片漏显。无虚假成就/写入/数据丢失。`testGoalClockRollbackRemainsConservativeAndReadOnly` 固定这种保守行为，不为它改模型或扩展事件顺序协议。旧 WeeklyReview 导航 `Invalid frame dimension` 运行警告在 UI 组复现，记录为原相邻页面风险，未声称根因消除。

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
| 固定候选全量与关键集成 | 待执行/记录，不把上述定向计数替代最终门禁。 |

性能真实指标：pure projection（4000Todo/4000Entry/20000Log/25Habit）0.240077916s；磁盘reader（4000Entry/4000Todo/20000Log，半数为400天前数据）0.464396209s，main heartbeat0.013036875s，进程peakRSS读取前/后均516145152bytes。RSS含fixture构建与测试进程，不称功能占用516MB或“零内存分配”；90天投影只保留2000Todo/2000Entry/10000Log。单设备Debug合成指标不是真机性能承诺。

可复现通用命令（每次真实run有独立日志/结果包）：

```sh
xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-quiet-wins-derived -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-quiet-wins-evidence/<run>.xcresult <selectors> > /tmp/pgos-quiet-wins-evidence/<run>.log 2>&1
xcrun xcresulttool get test-results summary --path /tmp/pgos-quiet-wins-evidence/<run>.xcresult
xcrun xcresulttool export diagnostics --path /tmp/pgos-quiet-wins-evidence/<run>.xcresult --output-path /tmp/pgos-quiet-wins-evidence/<run>-diagnostics
xcrun xcresulttool export attachments --path /tmp/pgos-quiet-wins-evidence/<run>.xcresult --output-path /tmp/pgos-quiet-wins-evidence/<run>-attachments
```

Selectors：engine-1/2=QuietWinsTests+QuietWinsReaderTests；ui-1=两个QuietWins UI；ui-2=五来源UI+磁盘性能Unit；dark-1/2=中文Dark/AX/空态UI；d72-overlay-1=精确旧版本覆盖UI；facts-1=图片/完整导出和Goal回拨两个ReaderTests。类前缀 `PersonalGrowthOSTests/` 或 `PersonalGrowthOSUITests/AppLaunchSmokeTests/`。

其它已执行：git diff --check、project plutil PASS；原629条字符串值与基线逐条相等，新增23键全部en/zh-Hans完备；保护生产文件字节不变。最初注册工程脚本找错Sources phase、工具沙箱读取xcresult TestReport需权限、console日志不可用、Dark设置Shutdown等命令失败已保留到实际工具记录；均未当功能通过，已用真实工程phase、结果诊断和明确boot纠正。

## 验收对应与最终边界

| 案例 | 直接证据 |
| --- | --- |
| A1 | 空输入/未完成/外部正负Unit；中文空态实际UI。 |
| A2 | completedAt/当前状态/lifecycle/归档/重新激活纯Unit；真实Goal详情导航；回拨保守读取Unit。 |
| A3 | 期次ID去重/撤销/取消/未来Unit；真实Todo详情撤销、首页消失、重启UI；全量原Todo系列测试。 |
| A4 | 正向/false/同日次数/持久日旅行/孤儿Unit与Reader；仅有打卡文案，不声称达标。 |
| A5 | occurredAt/内容/Review/external/去重Unit；真实图片关系与完整原数据导出前后相等Reader；Entry正文UI。 |
| A6 | 合法周次重叠/未完成/非法/未来Unit；原WeeklyReview精确文本UI；不使用更新时间。 |
| A7 | 7/30/90/跨年/闰日/DST/asOf未来Unit；范围切换实际UI。 |
| A8 | 五来源现有详情UI；Todo撤销后的源降级与卡消失、重启UI；删除源读取Unit。 |
| A9 | 英文Light/中文实际Dark最大AX截图与语义audit；五Tab断言，原Today未改。 |
| A10 | Reader willSave=0、hasChanges=false、源时间/事件不变、完整v7原数据及图片不变；生产保护文件零diff；精确d72模拟Todo覆盖。不等同私人手机验证。 |
| A11 | 公开合成load真正磁盘查询+main heartbeat+peakRSS，真实规模/耗时见上。 |

## 后续原 App 覆盖升级准备（本轮不发行）

只读 `gh api repos/yoCruzer/PersonalGrowthOS/actions/workflows` 返回total_count=0；独立远端CI **NOT_RUN**，不把空checks当成功。实际Xcode Cloud工作流/tag触发分支规则在本轮未访问服务器，仍 **OWNER_REQUIRED**。历史 `testflight-` 标签只是既有发行记录，不能证明当前Cloud规则；不得复用旧tag。

Owner审查完成并另行授权发行后：核对实际Cloud工作流接受新候选commit及`testflight-`前缀/分支；App+Extension构建SHA同源、签名/Team/AppGroup一致；CFBundleVersion须高于AppStoreConnect当前已上传最高号（仓库基线仍1.0(7)，Owner已装本地Build16的历史记录不是新的发行号授权）。保持原Bundle ID/容器，采用原App TestFlight覆盖升级，保全现有数据与可恢复备份，不卸载或清库。本轮不打tag、不改号、不归档、不上传、不安装真机。

未来5–10分钟设备检查：

1. 升级前由Owner确认可用备份/保全；核对候选来源完整SHA和递增build。
2. 从原App正常覆盖升级，抽样旧Entry原文/图片、Habit历史、Weight、Goal、Todo清单/状态及提醒，重启仍在。
3. Growth→成长回顾，切7/30/90天，核对具体日期与少量真实证据，不出现收藏伪成就或总分。
4. 打开Goal/Todo/Habit/Entry/周回顾来源，日期/周次/数量与真实事实相符。
5. 撤销一次Todo完成，返回卡片与明细更新；重新完成、编辑或删除来源后不留幽灵卡。
6. 验证纯图片/补录记录、同日多打卡不同日数、旅行后的既有Habit本地日稳定。
7. 中文/英文、真实Dark/Light、较大字号/VoiceOver触达，Today及原录入操作仍流畅。
8. Owner自行按正常路径确认v7备份可用与真机通知实际送达；这两项不由只读功能或模拟器合成验证替代。

真实Owner数据、相机/通知硬件、签名/AppGroup配置、私人覆盖升级、真机VoiceOver/性能、实际Cloud/TestFlight全部 **NOT_RUN/OWNER_DEVICE_GATE**。原259及原PR#8历史证据保留。
