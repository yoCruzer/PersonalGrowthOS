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
- [x] Entry 置顶/补充 CRUD、搜索定位、清理与 v5 备份闭环实现；中文编辑/删除 UI 收尾待重测。
- [ ] 定向 UI、双语/首屏/大字号/深浅色检查；一次最终全量 Unit 与可追溯 Debug 候选。
- [ ] 收尾文档、diff 审查、提交、普通 push、一个 Draft PR；独立 Review 交接。

## Decisions

1. 采用增量附属模型，以 Entry UUID 关联，不修改历史共享 Entry 形状；Build 8 的真实 checksum 失败证明此约束必要。
2. 迁移证明提前完成；fixture 仅在隔离临时目录以合成数据生成，不访问或上传真实数据库。
3. 不重新跑全量基线；复用已记录 Build 8 证据。最终全量 Unit 一次，开发中按变更风险运行定向测试。
4. 环境限制使用正式 `require_escalated`；远端只读查询和 simctl 清单已获准成功。

## Risks / acceptance evidence

最高风险：历史 schema checksum、附属记录原子清理、备份非空库保护/非法包预检、周/月进度与当天撤销区别、搜索命中定位。

可用 iPhone 16 Simulator：iOS 26.5，`5F04DE28-8329-4774-9488-076D6DDC5230`。每项测试记录命令、退出状态、结果路径及对应源码 checkpoint；未执行项明确标注。迁移需验证 Entry/图片、Habit 计划/日志/生命周期、Goal/关系、Weight、WeeklyReview 保留，以及新数据落盘重开。最终 UI 重点 3 个今日习惯+2 个目标首屏、8+习惯/长名称/大字号、键盘、补充、搜索、置顶；不要求所有组合全量重测。

## Checkpoint / resume

六项功能已实现，产品源码未再改变。候选全量 Unit 已执行一次，208/209 通过；唯一失败为新测试在相同创建时间下错误假定 UUID 顺序，已固定测试 UUID，待定向重测。中文退出按钮重复无障碍节点的查询已修正，待重测。真实深色大字号、多置顶 UI 尚未执行。模拟器命令自动审批因服务容量拒绝，等待 Owner 对受限操作回应；不得绕过。实现已提交为 `7c65413`，普通推送成功，独立 Draft PR [#6](https://github.com/yoCruzer/PersonalGrowthOS/pull/6) 已创建；base 为 Build8 分支。

## Final result

PARTIAL checkpoint：实现完成；必要自动验证尚有未确认项；本地实现提交、普通推送、Draft PR #6 已完成；真机及发布未执行。此状态不能视为完成 Goal 或进入发布。

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
