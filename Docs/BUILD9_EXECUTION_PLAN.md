# Build 9 Execution Plan — 今日体验优化与记录延续

## Authority and baseline

Owner 于 2026-09-16 批准完整 Build 9 Goal（`PersonalGrowthOS_Build9_Codex_Goal.md`），包括实现、验证、提交、普通推送和独立 Draft PR；结束边界为独立 Review。

- 起始分支：`feature/build8-habit-analytics-dashboard`，干净 HEAD `ae8f7cb6577f2d1bc479471bcd98d6f437670210`，与 upstream 一致。
- 只读 GitHub 核验：PR #5 OPEN / Draft / 未合并，head 同上，base `fix/build7-owner-feedback-round2`。
- 本轮分支：`feature/build9-today-entry-followups`，从上述 HEAD 创建；本轮 PR base 使用 Build 8 分支以隔离 diff。`main` 的祖先仍为 `dd09975`，不作为起点。
- 实际存储 V8、备份 v4、营销版本 1.0、Debug/Release build 7；本轮不修改 App 版本号。
- Owner 表示已在使用 Build 8；此前文档的真机验收未完成结论保留，不据此推断全部设备用例通过。

## Scope and implementation map

六项交付：真实 Bundle 版本；体重直接录入与一次聚焦；Today 紧凑首屏；周/月共享习惯操作；Entry 置顶；单层文字后续补充。

- `AppShell.swift`：Today、Timeline、Settings，当前 Today 有重复 Quick Capture；周/月操作将复用 `HabitFoundation.swift` 与 `Growth/HabitViews.swift` 的解析、snapshot 与服务。
- `Weight/WeightViews.swift`：复用现有 editor/校验，保留新建空值、加入参考与焦点/键盘关闭。
- `Persistence/PersistenceFoundation.swift`：V8 历史 Entry 保持形状，增量 V9 EntryPin/EntryFollowUp；共享 CRUD 与删除事务。
- `Capture/EntryDetailView.swift`、`Organization/OrganizationFoundation.swift`、`Search/SearchView.swift`：详情操作、补充定位、原 Entry 去重与筛选。
- `ImportExport/TransferModels.swift`、`ImportExportService.swift`：v5 完整载荷、计数、预检、恢复、回滚、空库保护。
- 相关 Unit/UI、合成旧库 fixture、`Localizable.xcstrings` 与必要 Foundation 范围说明。

不做 AI、云同步、社交评论、Todo、新导航架构、统计重做、发布、build number 提升或真实用户库操作。

## Milestones / Progress

- [x] 读取权威上下文，核实实际 Git/PR/版本和可用设备；建立独立分支。
- [x] 基于当前代码建立本执行计划。
- [x] 从确切未修改 Build 8 源码生成合成 V8 fixture，最小 V9 增量迁移/重开证明。
- [x] Today/版本/体重及共享周/月动作实现与定向验证。
- [x] Entry 置顶/补充 CRUD、搜索定位、清理与 v5 备份闭环实现和验证。
- [x] 定向 UI、双语/首屏/大字号/深浅色检查；一次最终全量 Unit 与失败点定向闭环，可追溯 Debug 候选。
- [x] 收尾文档、diff 审查、提交、普通 push、一个 Draft PR；独立 Review 交接。

## Decisions

1. 采用增量附属模型，以 Entry UUID 关联，不修改历史共享 Entry 形状；Build 8 的真实 checksum 失败证明此约束必要。
2. 迁移证明提前完成；fixture 仅在隔离临时目录以合成数据生成，不访问或上传真实数据库。
3. 不重新跑全量基线；复用已记录 Build 8 证据。最终全量 Unit 一次，开发中按变更风险运行定向测试。
4. 环境限制使用正式 `require_escalated`；远端只读查询和 simctl 清单已获准成功。

## Risks / acceptance evidence

最高风险：历史 schema checksum、附属记录原子清理、备份非空库保护/非法包预检、周/月进度与当天撤销区别、搜索命中定位。

可用 iPhone 16 Simulator：iOS 26.5，`5F04DE28-8329-4774-9488-076D6DDC5230`。每项测试记录命令、退出状态、结果路径及对应源码 checkpoint；未执行项明确标注。迁移需验证 Entry/图片、Habit 计划/日志/生命周期、Goal/关系、Weight、WeeklyReview 保留，以及新数据落盘重开。最终 UI 重点 3 个今日习惯+2 个目标首屏、8+习惯/长名称/大字号、键盘、补充、搜索、置顶；不要求所有组合全量重测。

## Checkpoint / resume

六项功能实现、自动验证和独立 Draft PR #6 交付完成，停止于独立 Review。全量 Unit 一次 208/209 通过，唯一新测试的同时间 UUID 排序假设修正后定向 1/1 通过，209 项均有对应通过证据；未将有失败的初次运行描述为全绿。所有本轮 UI 场景均取得通过证据。产品实现提交 `7c65413`，其后只有测试与文档收尾，产品摘要保持不变。

## Final result

COMPLETE：本轮实现、必要自动验证、普通推送和独立 Draft PR 已交付。真机验收未执行；版本仍1.0 (7)，不表示可以发布。下一动作仅为独立 Review，随后由 Owner 决定真机验证/修复/发布准备。

## Checkpoint evidence — data foundation

- 确切 Build8 fixture 生成：`/tmp/PGOS-Build9-V8Generate.xcresult`，testGenerateExactBuild8Fixture PASS（exit 0）。测试源码、命令、来源与合成数据说明保留在 `PersonalGrowthOSTests/Fixtures/Build8V8Fixture`。
- V8→V9/重开/幂等/补充/归档限制/永久删除清理：`/tmp/PGOS-Build9-V9Migration.xcresult`，testBuild9ExactV8MigrationAndContinuationReopen PASS（exit 0）。对应增量模型与服务初次实现，随后未改持久化字段。
- UI/备份主接入增量 build-for-testing：`/tmp/PGOS-Build9-Integration.log`，exit 0。
- 当前定向数据测试 `/tmp/PGOS-Build9-TargetedData.xcresult` 发现原“未来格式拒绝”用例硬编码 5；v5 成为合法版本后须改为 current+1，保留拒绝断言。重跑失败点后再做候选全量。
- 搜索现状检查：基线 Global Search 本来包含归档 Entry，且没有日期/标签筛选 UI；本轮保留既有搜索范围，不因补充额外注入置顶或改变原记录日期。Library 既有筛选保持原 Entry 口径。

### UI and risk-driven follow-up

- `PGOS-Build9-FirstUI.xcresult`：未来格式拒绝修正与体重/置顶/补充/搜索重启定向 UI PASS；截图 `/tmp/PGOS-Build9-FirstUI-Shots` 已视觉检查，体重 Save 和键盘 Done 可达。
- 初次 Today 测试没有收起 Goal 键盘；第二次发现系统中文键盘标识为 `Return` 而非 `return`。改用大小写无关的实际标识，保留全部首屏断言，不更改 Goal 产品实现。
- 精确实时时间在秒数 JSON 编码往返中产生亚微秒浮点误差。新备份 fixture 改为固定 Unix 时间 1730000000，保留 createdAt/updatedAt 完全相等断言；未改变备份编码政策。
- 测试宿主默认模拟器库的 unknown-model-version 启动日志在**确切未修改 Build8 源码**生成 fixture 的运行中已经存在（V8Generate.log），并非本轮新增；未清除或回退该库。本轮迁移测试复制可信 fixture 至独立临时存储，UI 使用既有专用 UITesting 存储。

### Candidate convergence

- iPhone 16 正常字号首屏截图通过：3 个今日习惯的动作、体重状态/直接入口、2 个活跃目标均可见；周/月共享行显示各自周期进度且打卡后按 once/day 禁止同日重复（FinalTargetedUI 中该场景 PASS）。
- 新备份 v5 只读预览展示对象数及置顶/补充数量；正式导入再次预检和确认空库，避免预览之后的文件/存储变化绕过保护。
- 中文设置真实版本复制已通过。长文本 UI 查询改用 NSPredicate，避免 XCTest 的 128 字符标识限制，未缩短测试长文。
- 中文补充退出暴露键盘与 confirmationDialog 的保留操作呈现问题；改为先关闭焦点后显示明确的 Alert（放弃/继续编辑）。该失败点正在重测。
- 启动参数不能证明系统深色/大字号，旧命名截图实际为浅色正常字号，不计入该项验收。将用 `simctl ui appearance dark` 与 `content_size accessibility-extra-large` 的真实设置单独运行 9 个长名称习惯场景，并恢复原设置。
- 首次外发前只读检查：本地没有 `.github` 或发布脚本，GitHub Actions workflows 为 0；远端 Build8 仍为 `ae8f7cb`，Build9 远端分支尚不存在。普通任务分支推送未发现自动归档/分发触发规则。

### Final candidate and permission checkpoint

- `/tmp/PGOS-Build9-FinalCandidate.xcresult`（exit 65）：全量 Unit 209 项，208 通过、1 失败；定向 UI 2 项，既有体重路径通过、中文补充路径失败。没有重跑全量基线，也没有删除或放宽失败断言。
- Unit 失败点：两条补充采用相同固定时间但随机 UUID；搜索按稳定 UUID 兜底，断言却要求第一条。修正 fixture 为固定顺序 UUID，仍验证准确命中第一条与去重/失败回滚/父统计。
- UI 失败点：中文 Alert 已正确显示“继续编辑”，XCTest 将父子无障碍按钮都匹配到同一 identifier。查询限定到 Alert 的 firstMatch；完整正文保持与后续编辑/删除断言不变。
- 待执行命令：`xcodebuild test -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=5F04DE28-8329-4774-9488-076D6DDC5230' -derivedDataPath /tmp/PGOS-Build9-Derived -only-testing:PersonalGrowthOSTests/PersistenceMediaFoundationTests/testBuild9ContinuationFailureRollbackSearchAndParentStatistics -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testBuild9ChineseThoughtEditingDiscardDeletionAndVersion -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testBuild9ManyHabitsExpandAndScroll -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testBuild9PinnedPreviewAndAllPinnedList -resultBundlePath /tmp/PGOS-Build9-Accessibility.xcresult`。
- 在上述命令前读取系统原值为 `appearance light` / `content_size large`；计划设置 dark / accessibility-extra-large 并在验证后恢复。设置及测试组合命令尚未启动：自动审批明确拒绝，原因 `Automatic approval review failed: Selected model is at capacity. Please try a different model.` 已向 Owner 说明并请求继续批准，未换工具/协议绕过，未循环重试。
- 产品工作树内容 SHA256：`0353355b47cfd2e55644953577ed163465d1606f19edd3742a0ddba0ff97bf34`。算法：按路径排序全部 `PersonalGrowthOS/**/*.swift`，再 catalog 与 pbxproj，依次散列路径及文件字节。FinalCandidate 后只改测试和文档，产品代码相同。产品实现提交为 `7c65413`，其后仅文档提交。
- 静态检查：`git diff --check` PASS；461 个本地化键均有 en / zh-Hans；Debug/Release 均仍 1.0 (7)；新增 fixture 文件仅合成 store、图片、来源说明与生成测试，未包含真实私人数据。

## Independent Review focus and Owner iPhone 16 checklist

Review 重点：`AppShell.swift` 与共享 HabitOverviewRow 的周/月 snapshot 和当天撤销；`PersistenceFoundation.swift` 附属模型/删除事务；`OrganizationFoundation.swift` 与 `SearchView.swift` 命中定位；`TransferModels.swift` / `ImportExportService.swift` v5 非空库保护、非法载荷与回滚。

Owner 真机待验：3 个习惯+2 个目标首屏；体重空值/参考/小数键盘/收起/取消重入；日/周/月打卡及当天撤销；置顶3条预览和全部列表；中文补充新增/编辑/放弃/删除；搜索定位与重启保持。恢复与破坏性场景仅用隔离测试数据，不清空手机真实库。

未增加 build number、未合并、未 Archive、未上传 TestFlight。补齐受限验收与独立 Draft PR 后，唯一下一边界是独立 Review。

### Remote delivery checkpoint

本地实现提交 `7c65413`，普通推送成功；独立 Draft PR [#6](https://github.com/yoCruzer/PersonalGrowthOS/pull/6)，base `feature/build8-habit-analytics-dashboard`，head `feature/build9-today-entry-followups`。未修改 PR #5 范围。正文明确必要验收待补齐，不将远端交付成功当作 Goal COMPLETE。自动审批问题仅剩模拟器验收，提交/推送/创建 Draft 均通过各自正式环境审批。

### Permission recovery and final targeted closure

Owner 明确回复“确认允许”后，重新走正式审批并成功运行；未绕过原拒绝。产品源码摘要仍为 `0353355b47cfd2e55644953577ed163465d1606f19edd3742a0ddba0ff97bf34`，只改 UI 测试定位与断言。

- `/tmp/PGOS-Build9-Accessibility.xcresult`：排序/回滚/父统计 Unit 1/1 PASS，九个长名称习惯展开滚动与四条置顶 UI 2/2 PASS；中文流程最初因无障碍标识查询失败，整组 exit 65，不能称整组通过。
- 深色大字号由真实 `simctl ui appearance dark` / `content_size accessibility-extra-large` 设置；已视觉检查截图目录 `/tmp/PGOS-Build9-Accessibility-Shots`。Today 长名称换行自然、动作不重叠，展开后第九项与体重可达；全部置顶列表可滚动，时间轴仍保留原记录。
- `/tmp/PGOS-Build9-ChineseClosure.xcresult`：只补滚动仍失败，随后检查导出的实际 UI 层级确认 SwiftUI 将补充行 identifier 传给内部按钮。测试改为行 identifier + 本地化按钮名，不改产品或弱化 CRUD 断言。
- `/tmp/PGOS-Build9-ChineseVerified.xcresult`：中文完整流程 1/1 PASS（exit 0），包括版本复制、长原文、换行补充、退出保留、未改动 Save 禁用、编辑标记、删除与原文保留。截图 `/tmp/PGOS-Build9-ChineseVerified-Shots` 已视觉检查。最终审查补强删除断言为操作按钮消失，避免依赖输入光标位置；最终 `/tmp/PGOS-Build9-DeletionClosure.xcresult` 1/1 PASS（exit 0），补强断言通过。
- 原模拟器设置已恢复并读回确认 `light` / `large`。没有 clean build、重跑全量基线或全量 UI，也没有发布构建。

## Final acceptance map

| 范围 | 当前证据 |
| --- | --- |
| Bundle 版本/未知值/复制 | AppComposition 定向及全量 Unit；中文版本复制 UI |
| 体重空值/键盘/解析/日期 | Weight Unit；FinalTargetedUI 直接入口/重启；FinalCandidate 既有体重 UI |
| Today 3习惯+2目标/多习惯 | FinalTargetedUI 正常首屏截图；Accessibility 9长名称深色大字号 UI/截图 |
| 日/周/月共享规则 | HabitFoundation 新周期/边界测试与既有全量；Today 周/月打卡 UI |
| 置顶与补充 | Persistence 迁移/回滚/幂等/排序/归档恢复/删除；Accessibility 全部置顶；ChineseVerified 与 DeletionClosure CRUD |
| 搜索/重启/父时间统计 | FinalTargetedUI 命中定位重启；Persistence Unit |
| V9/v5/历史兼容/拒绝回滚 | 确切 V8 fixture 迁移重开；FinalCandidate 中 ImportExport 32项通过 |
| 语言与构建 | 461键 en/zh-Hans 完整；上述 test 命令包含成功 Debug 编译；无重复 Archive/build |
| Git/交付 | 从 ae8f7cb 独立分支；Draft #6 base Build8；普通推送，无强推/合并/发布 |

Review 应重点核对本表映射代码、执行证据及历史默认库警告的来源说明。测试/文档收尾未更改产品、模型或工程配置，因此不机械重跑全量 Unit。此前 PARTIAL/审批拒绝条目为历史过程，已由 Owner 重新确认与成功正式审批解除。

## PR #6 Review Closure — R1 / R2 / R3 (2026-09-16)

当前批次从干净 `7843641f6d977ffe13e6e78e837c561709e83f71` 接续同一 Build9 分支。已完整读取 `/Users/hanghang/Documents/PersonalGrowthOS_PR6_Review_Closure_Codex_Goal.md`。上文 COMPLETE 仅表示前轮交付，不代表 Review/发布通过。

核实三项均成立：预览由 fileImporter 直达 service 外部读取，只有正式导入获取 scope；搜索值快照仅随 query 刷新；补充编辑写 now() 可低于 createdAt，与 v5 validator 冲突。

计划：
1. R1：给 UI 实际调用的预览/恢复共享轻量异步 scope 边界，各自获取/释放，确认等待期间不持有；验证成功/错误/取消/沙盒 false 返回，并走系统 Files 合成包预览/取消/空库恢复。
2. R2：在实际搜索结果列表重新出现时用保留 query 刷新；验证唯一命中删除、多补充切换、原文仍匹配，长原文 UI 验证返回刷新与再次定位可见。
3. R3：更新时间取 now、原 updatedAt、createdAt+1秒的最大值。保证不倒退且真正编辑始终可显示 Edited，1秒不会被 v5 时间往返舍掉；不变正文仍不改时间。注入回拨时钟，验证真实导出/导入/重开及父时间不变。
4. 仅相关 Unit/UI 与编译，保留旧测试历史；更新本计划和两份当前上下文、提交普通推送并更新同一 Draft PR #6，再次独立 Review。不改变 App/schema/backup 版本。

进度：R1/R2/R3 均核实成立并修复；定向验证完成，普通推送更新同一 Draft PR #6，停止于再次独立 Review。

### Review Closure evidence checkpoint

- 当前远端只读核验：PR #6 OPEN/Draft，base/head 与附件一致，起始 SHA `7843641f6d977ffe13e6e78e837c561709e83f71`；初始工作树干净。
- 产品修复：`AppShell.swift` 的预览/正式恢复都调用 `SecurityScopedFileAccess.perform`，异步操作结束即释放，UI 只在成功且未取消时发布 pending URL/preview；`SearchView.swift` 的实际 SearchResultsList.onAppear 重算保留查询；`EntryContinuationService.edit` 使用 `max(now, updatedAt, createdAt+1秒)`。
- `/tmp/PGOS-PR6-Targeted.xcresult`：5/5 定向 Unit PASS（scope配对/取消/沙盒false、回拨真实服务/导出/隔离恢复重开、搜索三种结果语义、非法载荷拒绝、非空库拒绝）。该组 UI 最初因重复系统返回节点失败，整组 exit65；未描述成全绿。
- `/tmp/PGOS-PR6-UI2.xcresult`：R2 长原文+三条补充 UI PASS（固定查询、目标实际可见、删除后片段/ID切换、再次定位、最后结果移除）；Files 部分当时仅探索保存入口，虽 XCTest 报通过，不计为完整 Files 验收。
- UI 测试按实际层级修正系统重复返回按钮与 `No Results for “Needle”` 文案；不更改产品规则或弱化成员/片段/可见定位断言。
- 系统 Files 保存入口为中文 actionGroupCell，保存选择器为英文 On My iPhone。`FilesRestore.xcresult` 已实证系统选择器返回的外部 ZIP 可进入1对象预览，但因系统旧选择器节点滞留和 popover 无显式Cancel造成测试失败。最终用“外部文件再次选中及恢复内容”证明保存，用实际 PopoverDismissRegion 取消，并保留空时间轴+再次空库预检+恢复内容断言。
- 仅复用 `/tmp/PGOS-Build9-Derived`、iPhone16 iOS26.5 指定 UDID 运行相关 test；本轮无全量基线、全量Unit/UI、clean或Archive。旧默认模拟器库的既有未知版本警告继续保留，未清理标准库；所有写操作在专用 UITesting 或独立临时存储。

### Review Closure final result

**R1/R2/R3：已修复。** 产品与回归测试提交 `967dc01bc127d5dc27a4dfd1b1ebe8108b248237`；之后只更新文档。原 Build9 自动验证记录保留为历史，不充作本轮证明。

| 检查 | 结果与证据 |
| --- | --- |
| 访问生命周期及相关数据保护 | Targeted 的5项 Unit 全通过；UI/编排实际使用同一 SecurityScopedFileAccess 边界，获取→异步读取→释放，错误/取消均配对，未获取scope时仍允许合法沙盒读取 |
| 搜索返回刷新 | UI2 的 `testPR6SearchRefreshesAfterDeletingMatchedFollowUps` PASS；长原文+多个补充、同一查询、目标实际可见、切换至下一补充、最后移除；Unit 另覆盖编辑移除匹配与原文仍匹配 |
| 回拨时钟 | `testPR6RollbackClockEditSurvivesV5RestoreAndReopen` PASS；正常/相等/回拨/早于已有更新时间/无正文变化、创建时间和父时间保持、真实v5导出→空库恢复→重开、“已编辑”往返成立 |
| 系统 Files | `/tmp/PGOS-PR6-FilesFinal.xcresult` 1/1 PASS，exit0；通过系统保存选择器及 Files 本地提供者重新选中合成ZIP，正确数量预览，popover取消后空时间轴和再次空库预检成功，确认恢复后合成Entry可见 |
| 可追溯 Debug | Targeted / UI2 / FilesVerified 的 test 已编译同一产品源码；最终 FilesFinal 复用相同产物 test-without-building，没有重复 clean/build |
| 静态与版本 | diff whitespace检查通过；461键en/zh-Hans完整，本轮没有新文案；App1.0(7)、schemaV9、backupv5均未变 |

`/tmp/PGOS-PR6-FilesVerified.xcresult` 为明确中断的环境异常运行（exit73），不算通过：XCTest 连续收不到动画空闲通知。截图证明应用界面稳定后对特定 xcodebuild 发 SIGINT，确认进程退出，再 shutdown/boot 同一模拟器（不erase），随后 FilesFinal 通过。没有并行启动重复测试，没有清理标准存储。

系统 Files 成功截图：`/tmp/PGOS-PR6-FilesFinal-Shots/4B3A1ABD-C15B-44C8-AF84-BDB312CA0D17.png`。早期分享入口探索、系统控件定位失败和中断记录仍在各 xcresult，未删除或冒充完整通过。后续测试改动只修正系统实际控件定位，不放宽恢复、空库、搜索定位或时间约束。

**未执行：**真实 iPhone 恢复、iCloud/第三方文件提供者矩阵。已完成的系统选择器证据仅为 iPhone16 模拟器本地 Files 提供者；不宣称真机恢复通过。所有测试记录均合成，未操作真实私人数据库。无merge/Ready/Archive/TestFlight/发布tag/版本提升。

### Review Closure actual commands

以下是本轮关键运行日志中的实际命令（日志同名 `.log`，具体子测试结果见上表；Targeted整组因初次UI定位失败exit65，UI2及FilesFinal exit0）：

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination "platform=iOS Simulator,id=5F04DE28-8329-4774-9488-076D6DDC5230" -derivedDataPath /tmp/PGOS-Build9-Derived "-only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests/testPR6SecurityScopeBoundaryPairsSuccessFailureAndCancellation" "-only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests/testPR6RollbackClockEditSurvivesV5RestoreAndReopen" "-only-testing:PersonalGrowthOSTests/PersistenceMediaFoundationTests/testPR6SearchRecomputesMembershipSnippetAndTargetAfterFollowUpChanges" "-only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests/testNonEmptyTargetRejectsImportWithoutMutation" "-only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests/testBuild9InvalidContinuationPayloadsRejectedBeforeWriting" "-only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPR6SearchRefreshesAfterDeletingMatchedFollowUps" -resultBundlePath /tmp/PGOS-PR6-Targeted.xcresult
```

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination "platform=iOS Simulator,id=5F04DE28-8329-4774-9488-076D6DDC5230" -derivedDataPath /tmp/PGOS-Build9-Derived "-only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPR6FilesPreviewCancelAndRestore" "-only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPR6SearchRefreshesAfterDeletingMatchedFollowUps" -resultBundlePath /tmp/PGOS-PR6-UI2.xcresult
```

```sh
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild test-without-building -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination "platform=iOS Simulator,id=5F04DE28-8329-4774-9488-076D6DDC5230" -derivedDataPath /tmp/PGOS-Build9-Derived "-only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testPR6FilesPreviewCancelAndRestore" -resultBundlePath /tmp/PGOS-PR6-FilesFinal.xcresult
```
