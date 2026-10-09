# Todo V1 执行记录

## S0 基线

2026-10-09：完整读取 Goal Pack Rev2 五文件，按 AGENTS 顺序读取 Foundation/Contract/Current；git status 起始干净 main/dd09975。实际 git fetch 成功；PR 栈 #1–#7 均 OPEN Draft。annotated tag 与 origin/codex/external-capture-v1 均 c5a3c0ac859efc3ffa4e5d9f77909ec43565c871。创建 codex/todo-v1-personal-actions，未改旧 PR/标签/编号/签名。Owner 当前安装 Build 12 的事实与仓库 App 1.0(7) 分开。

## S1 定向门禁

环境 Xcode 27.0 (27A266a)，iPhone 18 Pro Simulator iOS 27.0，UDID FD666264-A2DF-445C-A77D-534B9E8ED595。所有证据在 `/tmp/pgos-todo-evidence/`。

命令公共参数：`xcodebuild test -quiet -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=FD666264-A2DF-445C-A77D-534B9E8ED595' -derivedDataPath /tmp/pgos-todo-derived -parallel-testing-enabled NO`；每次独立 resultBundlePath，对应日志同名。

- domain-1 / domain-2：exit 65，分别是新 SwiftData 谓词捕获/throwing while 与新测试缺少 try 的编译错误；没有执行测试，未声称通过。
- domain-3：exit 0，7/7 PASS，0 FAIL/SKIP。无日期、多行中文、真实时钟回拨、状态/统计、计划与硬截止、时区、固定四种重复、短月/闰年、DST、幂等撤销/跳过/停止、来源/清单删除、保存失败回滚、重启。
- 精确源码归档 fixture：baseline-fixture 初次 exit 65（生成测试使用错误 StoredMediaFile 字段和私有 snapshot）；修正仅生成测试后 baseline-fixture-2 exit 0，生成真实 V10 sqlite、原始图片与 v6 备份。源码来源与复现方法见 Scripts/Fixtures/README.md；不修改历史 fixture，不接触私人数据。
- domain-migration-1：exit 0，11/11 PASS，0 FAIL/SKIP。9 Todo 测试加原 exact-V7/exact-V8 测试；真实 V10 两次打开、完整旧数据逐字段 equality、图片字节、receipt 及迁移后新增/来源/reopen 验证。TodoIntegrity 拒绝未知状态、错误最终事件、悬挂事件。

## 构建溯源（提前接入）

官方依据：[CI 环境变量](https://developer.apple.com/documentation/xcode/environment-variable-reference)、[自定义构建脚本](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)。App target 的 Generate Build Provenance 阶段位于 Sources/Resources 之前，每次执行，输出 DERIVED_FILE_DIR/BuildProvenance.plist，正常资源拷贝进入最终 App 后由 Bundle 读取，签名后不写 bundle。CI_COMMIT 完整 40 位优先；若存在但格式无效或与可核对 HEAD 不符，构建失败。真实 CI_TAG 可选、受长度/字符校验；本地读取对应 SRCROOT HEAD + dirty，无 Git 未知。Version/Build 仍取 Bundle 原字段。

- `python3 Scripts/verify-build-provenance.py` exit 0：实际脚本的合成 clean/dirty、CI tag/非 tag、无 Git、非法/过期 SHA、不安全 tag 全部通过。
- provenance-1：exit 0，2/2 PASS，0 FAIL/SKIP；实际 Debug App 包资源存在、完整 SHA/短 SHA/组合复制行为通过。产物 `/tmp/pgos-todo-derived/Build/Products/Debug-iphonesimulator/PersonalGrowthOS.app/BuildProvenance.plist` 此次 Commit=c5a3c0ac859efc3ffa4e5d9f77909ec43565c871，Source=localGit，Dirty=true（当时尚未提交新源码），Tag 空；不是硬编码输出。
- Release、模拟 CI 编译产物、实际 About UI/粘贴、双语大字体深色等仍待候选验证，不能用 helper/脚本测试替代。

## S2–S4 功能与失败审计

已接入 Hub/连续录入/详情/清单/Entry 来源/局部与全局搜索/四项统计；固定锚点重复和稳定期次；独立 opt-in 通知协调（启动/前台/时间变化/成功导入重建）；v7 五实体完整 DTO、计数、严格校验、空库保护与取消回滚。通知变更只在持久化成功后发生，Todo 前缀不取消旧每日/每周提醒。

重要修复：
- 事件内 Date 使用 2001 epoch，旧外层备份使用 1970 epoch 会引入一 ULP 精度差。Todo v7 DTO 使用明确 reference epoch，保持精确事件链比较；未弱化校验，未改旧实体 wire。
- 保存关闭由父 sheet 回调统一负责，避免重复 dismiss；连续保存维持标题焦点；键盘关闭按钮可见。清单重命名改为原生 sheet，确认删除只解除归属。
- 重复提醒保留原本的日/墙钟分钟，DST 缺时按 nextTime 解析，换时区不把缺时补偿后的 03:00 当成原 02:30。并发通知 pass 重读；权限请求只源于显式提醒操作。
- About Version/Build 添加语义标签；短 SHA 单独一行，真实最大字体仍完整显示。大字号系统字符串先前无效，改用 UIKit rawValue 并用渲染高度证明生效。
- 旧 synthetic v4/v5 测试移除 v7 空 keys，保持它们真实历史 wire；旧 fixture 字节未改。新增并发预检测试为合成目录显式注入容量，消除目录未创建导致的无关 I/O 错误。

各轮结果（独立 resultBundle/log，不把失败整组重标全绿）：

| Result bundle 前缀 | PASS | FAIL | 结论 |
| --- | ---: | ---: | --- |
| ui-reminders-compile-2 | 4 | 0 | 通知替身定向通过；前一轮 catch shadow 编译失败。 |
| ui-reminders-3 | 8 | 1 | Entry UI 使用旧 capture ID，未进入预期路径；修正正确 ID 后补验。 |
| backup-todo-1 | 62 | 2 | 旧 wire synthetic 与新往返精度各失败；来源 UI 已通过。 |
| backup-todo-2 | 1 | 1 | 旧 wire 修复通过，Todo 精度仍失败。 |
| backup-todo-3 | 0 | 1 | 精确定位到 todo integrity；随后修正 epoch。 |
| backup-todo-4 | 14 | 0 | 13 领域与完整 Todo 往返通过。 |
| todo-integration-2 | 23 | 3 | 23 Unit 通过；3 UI 键盘/rename/中文标签路径失败。 |
| todo-integration-3 | 6 | 3 | 6 Unit 通过；3 UI rename、Toggle 点击位置、Version 语义失败。 |
| todo-ui-4 | 1 | 1 | 清单/统计贯通通过；重复 Toggle outer row 点击无效。 |
| todo-daily-ui-5 | 1 | 0 | 系统权限交互、重复完成/跳过/停止/重启贯通通过。 |
| todo-chinese-real-dark-5 | 1 | 0 | 中文深色语义通过，但截图字号普通，不能算最大字体。 |
| todo-chinese-actual-size-6 | 0 | 1 | 真实最大字体编辑/高度通过；任务位于 lazy List 下方未滚动，断言失败。 |
| todo-chinese-actual-size-7 | 1 | 0 | 正常滚动后，真实最大字体编辑/Hub/About 语义及截图通过。 |
| todo-concurrency-perf-1 | 16 | 1 | 15 领域/性能与导出截止点通过；并发预检合成容量设置遗漏。 |
| todo-concurrency-2 | 1 | 0 | 容量注入后，预检并发拒绝且重开保留 Todo 通过。 |

另 `todo-integration-1` 是新测试参数顺序编译失败，未运行测试。UI 系统诊断曾额外等待约 600 秒，后续公共命令加 `-collect-test-diagnostics never`；并非测试断言被跳过。

有界性能 `testBoundedThousandTodoIntegritySearchAndStatisticsPerformance`：1000 个 Todo/1100 事件，3 次完整性校验、搜索、最终统计和稳定排序；0.091714458 / 0.091158908 / 0.094870064 秒，峰值 physical 28985.888 kB（XCTest metric，不是 App 总内存承诺）。源事实与独立预期核对，未为节省时长跳过持久化/完整性。

中文实际最大字体证据：`todo-chinese-actual-size-7.xcresult` 的 Editor/Hub/About 三张 keepAlways 截图。设置为 Dark + accessibilityExtraExtraExtraLarge，标题渲染高度 >150pt；语义检查 elementDetection/hitRegion/sufficientElementDescription/trait，通过不等于已运行真机 VoiceOver 朗读。

## 候选尾端门禁（待执行）

只在功能冻结后运行一次完整 Unit 与一次关键 UI 集中 gate；实际 counts/命令/源码 SHA 后续记录。Release/模拟 CI 产物与普通 push/Draft PR 尚未完成，当前不标 READY。远端没有配置 GitHub Actions workflow；普通 push 后只读检查 checks/statuses，实际 Xcode Cloud 发行未触发。Owner 真机与私人数据门禁保留。

## 候选首轮与数据审查闭合

功能候选 fb63f58420c68f4cadb0ab31d01bc7cbac2c9854：candidate-full-unit-1 exit0，283/283 Unit PASS，0 FAIL/SKIP。candidate-key-ui-1 exit65，17/22 UI PASS，5 FAIL：两个 CaptureFixtureHost 未安装；Safari 页面未加载预期 fixture；Entry 编辑后的正文与预期不一致；follow-up 删除后仍存在。没有将这些归为已通过，继续定向定位。

最后审查补上首个事件必须 created、seriesStopped 对应系列必须停止的校验；新增正负配对与12种坏 Todo 包的精确 invalidObject 断言（包括清单/系列/期次/来源身份）。复验包括领域、提醒、完整备份、启动组合与历史迁移相邻路径；不重复全量。

本地 Release app/appex 编译 exit0，均1.0(7)，localGit/clean/SHA=fb63f58420c68f4cadb0ab31d01bc7cbac2c9854。模拟 CI 标签编译、随后同 DerivedData 无标签编译 exit0，真实资源同 SHA/Source=xcodeCloud，Tag 从 todo-v1-ci-verification 清为空；未创建标签。脚本完整矩阵再次 exit0。远端普通 push成功，workflows=0、check-runs=0、statuses=[]；API aggregate pending 不代表有 CI 正在运行，远端 CI NOT_RUN。

candidate-integrity-closure-1（d0c41e88b0f1e9c444fa3a14a5cb23ce22d389c3）exit0：123/123 Unit PASS，0 FAIL/SKIP，包含 Todo/提醒/ImportExportRecovery/AppComposition/PersistenceMediaFoundation。审查再补 revision=Int.max 的无溢出拒绝，13种坏包断言保持精确，不通过 +1 的溢出崩溃处理输入。

candidate-failed-ui-2 exit65：0/5 PASS，5 FAIL。新增诊断独立证明 Entry TextEditor tap 把光标放开头，实际内容为“ editedA restart-safe memory”；改为 UI 选全文并输入完整预期，原编辑/保存/重启断言保留。补充确认删除代码不再从随 dismiss 清空的 optional 读取目标，使用 confirmationDialog presenting 捕获目标。Safari 未离开 start page，地址栏增加实际屏幕内中心点击、键盘与 Go 按钮断言，保持真实页面/选中文字/分享/取消/导入断言。Host 安装后在 iOS27 因 NoSceneLifecycleAdoption 崩溃，按 Apple TN3187 增加 UIScene，仅合成测试 Host 变化（App/ShareExtension 不改生命周期）。
官方依据：https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle 。Crash 堆栈为 UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption，来源是本轮合成 Host，不是产品 App 崩溃。

后续只复验新增校验相关 Unit、Entry 删除相邻路径和五个失败 UI，不将前两轮失败重标通过。
