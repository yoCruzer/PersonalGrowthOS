# 家庭净资产 V1.1 — 本地验收与独立 Review 完成，CI_PENDING

最终产品代码：`01ffedc45a4c99c3576ae65ab249b77a8496336f`。主库追加V16、备份v12；两个统一实体，五Tab、Bundle ID、App Group及旧模块保留。未接入旧1.0物品管理、Entry关联、Face ID、银行/云同步等范围。

- 独立只读Reviewer已确认 AR-01/02/03、BR-01/02、CR-01全部关闭；代码、数据安全、备份及五项视觉问题通过本地模拟器证据范围。见[审查记录](HOUSEHOLD_NET_WORTH_V1_REVIEW_ZH.md)。
- 本地NetWorth领域/磁盘/实际ZIP 16项已通过；8条本功能UI场景最终分别通过，包含真实图表更正/删除回总览。深色及最终对比度复验各1PASS；早期失败未删除。
- 集中完整Unit原轮599：597PASS/1FAIL/1既有SKIP；QuietWins旧v7夹具失败修复后全类5/5通过。集中本功能浅色UI原轮7：5PASS/2FAIL，两个定位失败随后分别复验通过。不能把原轮改称全绿。
- 未签名Release `generic/platform=iOS` BUILD SUCCEEDED，主App、ShareExtension、ImportantDaysWidget三包均存在且无_CodeSignature；产品文件与上述SHA一致，构建时文档/截图收口中。
- [十个主要场景与补充原始截图](Evidence/HouseholdNetWorthV11/README.md)、[截图源SHA/环境/哈希](Evidence/HouseholdNetWorthV11/screenshots.json)、[原始测试计数与日志哈希](Evidence/HouseholdNetWorthV11/local-runs.json)。CR-01旧失败图单独保留，最终图片未改绘。
- 原始xcresult与完整日志：`/tmp/pgos-net-worth-evidence`。每轮selector与环境在下方；最后仅按失败/影响范围补验，没有重复整套本地Unit/UI。

## N1–N13本地可执行验收

| 验收 | 生产路径证据 | 本地结果 |
|---|---|---|
| N1/N2 | 整数分、独立240万/101万/139万真值、转账/还贷反例、未知/零/负值/溢出/中英文 | PASS |
| N3/N4 | 首次/重复/批量沿用原日期、非法草稿磁盘重开、保存故障/重试、并发忙碌/取消 | PASS |
| N5/N6 | 日期/补录/同日唯一/更正ID/冻结备注、归档最终零不变量、账户新增与明确范围标记 | PASS |
| N7 | 真实图表点与分类下钻、负债切换、历史更正删除后总览同步；CSV读取同一ledger | PASS |
| N8 | 精确BASE原代码生成V15磁盘与v11 ZIP；保护原库字节、升级V16重开和旧模块/媒体比对 | PASS |
| N9/N10 | 实际v12 ZIP历史+非法中间草稿往返；仅项目/仅草稿非空保护；九类非法wire、恢复故障重开重试、晚写入冲突 | PASS |
| N11 | UTF-8 BOM、精确金额、未知/零、注入防护、零明细记录、恢复后CSV一致 | PASS |
| N12 | root/历史AX树无隐藏金额、图形移除、真实系统切换卡片遮挡、回前台继续隐藏；无新增全局搜索/通知/Widget财务路径 | PASS（实际VoiceOver听读待Owner） |
| N13 | 原生五Tab、Growth/Weight/Habit邻页，浅/深、375pt窄屏、最大辅助字号、键盘、长名、单点、负值、部分、失败重试 | PASS（真机待Owner） |

## 保留的限制与Owner真机门禁

- `TodoFoundationTests/testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure`既有SKIP：未挂载独立32MB HFS+测试卷；没有填满主卷。新财务恢复的故障注入/取消回滚已通过，但不等同真实低空间设备测试。
- iOS27.1不支持所选旧mini型号的本机403及历史设备FAIL/SKIP/NOT_RUN保留；本次运行已安装iOS27.0专用模拟器。
- 原始日志中的Widget projection、debugger noURL、SwiftUI `Invalid frame dimension`等运行警告保留；实际截图/断言未见对应本范围阻断。不把警告改称新功能失败，也不抹去。
- 未操作真实私人库、账户或设备；真实VoiceOver听读、真机后台动画/键盘触控和长期使用时长仍为NOT_RUN。
- Owner清单：首次添加几项资产负债并识别估算/未知；10项目重复盘点只改2–3项其余沿用并检查原日期；核对负值/范围调整及历史下钻；更正/删除后确认总览；隐藏与后台/VoiceOver；自行在安全环境检查CSV及完整备份恢复。记录耗时与困惑，不声称完成私人数据/真机验收。

## 提交与交付边界

- BASE `5827c657095945aff30b2250b20bae104c7b0357`
- GOAL_SHA `fb9cb83dc29b02897183d90c84c84055a037f957`
- A `f58746fd6f7f40b564e46a65091be1396f0134e3`
- B `9a8d77dd73e427c248844cefcad137d43327491b`
- C数据交互修复 `a45a910c7cb8b0070114db97850dc9d9cf1bc1f0`
- C夹具/定位 `9a3966e964bf4edd02aa043b1485619e771ef30a`、`839941aaf33eb8cff186d12f8e88c1592369aca8`
- C视觉 `22d9d82f3aa078977532071da79ee2739b4f4047`、`01ffedc45a4c99c3576ae65ab249b77a8496336f`

当前尚未标记READY：下一步普通push并创建唯一Draft PR，base为`codex/usage-remediation-20261017`，运行现有release/unit/smoke。禁止merge、force push、tag、Archive、TestFlight或发布。原主目录仍在`d72c016dd34c8114cf44744d0e061b95bd312091`，其project/catalog/xcodecloud三项未知改动原样保留。

---

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

## C 固定候选集中验收（进行中）

B提交 `9a8d77dd73e427c248844cefcad137d43327491b`：c-dark 深色UI 1 PASS/0 FAIL，实际系统appearance dark；首次simctl因Shutdown返回405，Xcode启动后应用成功，截图须以原图核实。独立B复核三项A问题关闭，新增BR-01/02已修；新UI和领域反例待集中执行。

集中命令采用共同xcodebuild模板：`-only-testing:PersonalGrowthOSTests -only-testing:PersonalGrowthOSUITests/NetWorthUITests -skip-testing:PersonalGrowthOSUITests/NetWorthUITests/testChineseDarkOverview`，c-final轮次，预期完整Unit只此集中一次。最终结果、Release、Review和CI仍待填实。

### c-final 原始结果与定位

固定产品/测试候选 `a45a910c7cb8b0070114db97850dc9d9cf1bc1f0`。完整Unit实际599：597 PASS / 1 FAIL / 1既有SKIP；本功能浅色UI实际7：5 PASS / 2 FAIL。不是整轮通过。

- QuietWinsReaderTests 的旧v7 wire构造漏删新版两个空数组，正式恢复正确拒绝corruptData。补入新数组的“应为空”独立断言后去除，保持全部旧来源/媒体/重开断言。
- 首次UI失败为隐藏模式下root眼睛和编辑器“显示金额”同名；查询限定排除root标识，不改变产品隐私。
- 图表更正UI点x=330.56位于9/30与10/31间近中点，实际选择9/30；原始视频末帧和触控事件已核对。改点真实末点x≈341，日期断言仍严格为10/31，未放宽数据断言。
- 既有SKIP：TodoFoundationTests/testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure，缺独立32MB HFS+卷；不填满主卷、不删skip、不冒称本轮验证。

下一轮 c-retry 仅QuietWinsReaderTests全类与上述两项UI；其余通过项目不重复整套本地Unit/UI。

c-retry（9a3966e964bf4edd02aa043b1485619e771ef30a）：QuietWins 5/5与首次盘点UI PASS；图表已准确进入10/31并输入112000，但键盘“完成”与背后图表详情“完成”同名匹配失败。测试改为直接点生产顶部保存（其本身收起键盘），保留更正/删除金额与日期严格断言。下一轮c-chart仅复验这1条。

c-chart（839941aaf33eb8cff186d12f8e88c1592369aca8）图表更正/删除真实UI 1 PASS/0 FAIL/0 SKIP。随后独立视觉CR-01修复项目行语义对比度及整行点击，c-visual-light/ c-visual-dark待真实复验；域模型与备份代码未改变。

c-visual-light（22d9d82f3aa078977532071da79ee2739b4f4047）2UI PASS；c-visual-dark同候选1UI PASS含项目行编辑。plain已消除浅蓝，但最终项目行小字进一步使用系统primary色，层级靠caption/subheadline与间距表达；为更严格可读性再补两张最终浅/深原图，不重跑领域/恢复测试。
