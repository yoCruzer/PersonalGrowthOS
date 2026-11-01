# 家庭净资产 V1.1 执行记录

## 固定输入与工作区

- BASE：`5827c657095945aff30b2250b20bae104c7b0357`；GOAL_SHA：`fb9cb83dc29b02897183d90c84c84055a037f957`。
- 本地 merge-base 与 GitHub compare 一致：BASE 是祖先，ahead 18 / behind 0，实际差异仅 13 份 Docs。规划分支指向固定 GOAL_SHA；指定 PR base `codex/usage-remediation-20261017` 指向 BASE。启动时无本功能产品远端分支或 PR；旧 #1–#13 保持。
- 从固定 GOAL_SHA 建立 `/private/tmp/PersonalGrowthOS-net-worth-v1`、`codex/household-net-worth-v1`。原主目录仍在 Todo 分支，project/catalog/xcodecloud 三项未知改动原样保留；未 stash/reset/clean。
- 已读 AGENTS、INDEX、全部现存 Foundation、Contract、CURRENT 全文（TASK 与 STATE 相同段落逐字去重核验），再读三份 V1.1 固定规格。旧家庭资产 1.0 不参与实现。
- 实际基线 V15 / backup v11；追加 V16 / v12，不改历史模型、Bundle ID、App Group、签名、版本号和五 Tab。

## 环境与证据

本机 Xcode 27.2 (27B52)，任务专用 iPhone 13 mini / iOS 27.0 (24A434)，UDID `83B81BAE-2074-4763-8D51-4F9E2C130389`。iOS 27.1 拒绝该旧机型（403），改用已安装27.0；沙盒首次 simctl/xcresulttool 访问失败后使用正常授权的系统工具。未修改系统配置或访问真实设备/私人库。

所有日志与 xcresult 保存在 `/tmp/pgos-net-worth-evidence`；DerivedData 分别 `/tmp/pgos-net-worth-base-derived` 与 `/tmp/pgos-net-worth-derived`，单一 Xcode 队列。测试均为合成数据。运行期间工作树有正常进行中修改，早期结果是分阶段证据，不冒充最终固定 SHA 验收。

共同命令：`xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=83B81BAE-2074-4763-8D51-4F9E2C130389' -derivedDataPath <上述目录> -resultBundlePath /tmp/pgos-net-worth-evidence/<轮次>.xcresult -parallel-testing-enabled NO <selector> test CODE_SIGNING_ALLOWED=NO`，完整 stdout/stderr 在同名 `.log`。

| 轮次 | selector / 内容 | 实际结果 |
|---|---|---|
| baseline1 | 固定 BASE archive，仅追加 NetWorthBaselineFixtureGenerationTests | FAIL/65；空 SleepValues 合成夹具被原校验拒绝 |
| baseline2 | 同上，合法合成睡眠备注；路径 Fixture2 | 1 PASS/0 FAIL；真实 V15 SQLite、媒体、v11 ZIP 生成 |
| focused1 | NetWorthTests | 编译 FAIL/65：恢复 worker 的 static read actor 边界 |
| focused2 | NetWorthTests | 编译 FAIL/65：测试缺 try |
| focused3 | NetWorthTests | 编译 FAIL/65：ZIPArchiveReader 参数名 |
| focused4 | NetWorthTests | 12 PASS/0 FAIL/0 SKIP；真实旧库迁移保护/重开、ZIP、金额和领域规则 |
| ui-a1 | 首次盘点 + 中文12次盘点/历史/隐私/键盘/冷重开 | 1 PASS/1 FAIL；中文路径通过，首次测试点击范围容器后未确认，保存显示 Incomplete；保留原视频与断言 |
| ui-a2 | 首次 UI 原生 Switch 子控件与确认值断言 + 最新 NetWorthTests | 12 Unit PASS；UI主值/范围已通过，列表精确label定位 FAIL，AX证实名称/金额/日期组合标签完整 |

baseline2 夹具由精确 BASE 源码生成；仅生成测试追加，产品源码不变。生成源见 `Scripts/Fixtures/CreateNetWorthBaselineFixture.swift`；资源 `PersonalGrowthOSTests/Fixtures/NetWorthBaselineV15Fixture` 包含 SOURCE 与 SHA256 manifest。旧版 fixture 不用新 schema 伪造。baseline 两轮已有 Widget projection code=0 宿主日志，未把它归为新财务功能成功或删除。

## A：原生闭环与迁移接入

统一 NetWorthItem + NetWorthSnapshot，typed Codable 冻结明细。整数分解析与受检求和，未知/零、两边范围、沿用保留原日、单草稿/同日唯一/修订冲突、历史更正、零后归档。独立上下文 + 现有 StorePublication 锁保障事务与回滚。非法中间文本保存在草稿。

已接 Growth、原生总览/项目/盘点及早期图表与历史页面，采用现有 ModuleEntryRow、系统分组/语义字体、主金额单一焦点。ui-a1 已导出并实际查看 Growth、总览、键盘、历史与隐藏原图；没有使用 Preview/HTML 代替。正式大字/深色/失败重试审查仍待完成。

迁移前保护、只读/写开完整性、完整备份计数/版本/验证/物化/重开比对/非空保护都含新实体。严格拒绝旧包携带新版字段及新版缺数组。原有兼容测试构造旧格式时去除新增空数组，保留非空新版数据拒绝逻辑；不改旧业务断言。

| ui-a3 | 首次UI修正组合label + 最大辅助字号 | 首次盘点 PASS；大字号失败在等候屏外懒加载按钮；已按AX改为等候实际导航页，大字复验待B |

## 待完成

B 完整体验及相邻回归、C 真实截图与固定候选独立只读审查、普通 push/唯一 Draft PR/现有 CI。当前不得标记 READY_FOR_OWNER_DEVICE_GATE。独立 reviewer `/root/net_worth_independent_reviewer` 已只读预审接缝并登记反例，未参与实现；正式结论尚未产生。历史设备 FAIL/SKIP/NOT_RUN 原样保留。

## B：补充验证与审查修复（进行中）

- A 本地提交 `f58746fd6f7f40b564e46a65091be1396f0134e3`。独立 A 审查与三项发现见 REVIEW_ZH；不得将阶段审查等同最终通过。
- b1：指定 NetWorthTests/ImportExportRecoveryTests/PersistenceMediaFoundationTests/ImportantDayPersistenceTests/SleepPersistenceTests/InvestmentPersistenceTests/AppCompositionTests，199 项，197 PASS / 2 FAIL / 0 SKIP。失败仅两项独立预期计数未加新空模型；不改旧业务断言。
- b2：NetWorthTests 16/16 +上述两个失败方法 2/2 PASS；UI 最大部分盘点/完整大字负值长名/错误重试三方法 2 PASS / 1 FAIL。失败为专用新文案未写入 catalog；锚点错误已修正。真实金额/数据库保存重试与回前台隐藏 PASS。系统截图只是桌面，不用它宣称切换卡片遮挡通过。
- b3：16 Unit +四项 UI 定向复验（大字部分、完整大字负值长名、失败重试+切换卡片、图表分类下钻+相邻模块），16 Unit PASS，UI 3 PASS/1 FAIL（中文AX分类标签用顿号，旧测试按逗号定位失败；实际历史点已通过）。新增稳定分类标识和明确完成按钮。
- b4：NetWorthTests 16/16 +图表/分类实际下钻 1/1 PASS；合计17 PASS/0 FAIL/0 SKIP。
- B 加强同一主库发布锁、取消、晚到独立写入、实际 ZIP 负金额/日期/枚举/重复 ID/重复日期/非法归档反例；故障前正式数据与草稿精确比较，恢复故障后重开为空且可重试。
- 修复归档零余额不变量、历史更正冲突、时区篡改、项目备注冻结；趋势范围变化有形状/文字标记，比较只表述增加/减少，未知分类不显示假零。

B 已完成代码与针对性验证。`V1–V15` 原始 schema 声明逐字相同；所有原本地化条目逐键相同，新增100个。b3 系统切换卡片原图实际看到遮挡标签，大字小数完整分行；未据桌面截图推断隐私通过。下一步 C 固定候选集中截图、Release、完整 Unit 单次集中门禁、独立复核和最终远端 CI。
