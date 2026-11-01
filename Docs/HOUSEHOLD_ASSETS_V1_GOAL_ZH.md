# Codex Goal — 随心 log 家庭资产快照 V1

- 授权版本：1.0（2026-11-01）。状态：GOAL_READY / IMPLEMENTATION_NOT_STARTED。
- 仓库：`yoCruzer/PersonalGrowthOS`。
- 固定产品基线 BASE：`5827c657095945aff30b2250b20bae104c7b0357`。
- 规划分支：`plan/household-assets-v1-goal`；执行输入 GOAL_SHA 以 Owner 引导 prompt 中的完整提交号为准。
- 产品分支：`codex/household-assets-v1`。
- 新 Draft PR base：`codex/usage-remediation-20261017`，基线时 head 为 BASE、对应旧 Draft PR #13。保持现有叠加路线，不从过期 main 开始。
- 同一 GOAL_SHA 下必须全文读取：[产品与数据](HOUSEHOLD_ASSETS_V1_DESIGN_ZH.md)、[界面与交互](HOUSEHOLD_ASSETS_V1_UI_ZH.md)、[验收](HOUSEHOLD_ASSETS_V1_ACCEPTANCE_ZH.md)；均为 1.0。

## 1. 目标与连续授权

Owner 已认可：“定期用几分钟确认家庭资产与负债，留下一张可追溯的快照，并看清长期变化。”并要求与现有界面和习惯统一、有设计感、达到正式产品质量。

本 Goal 覆盖：完整 V1 实现、必要验证、真实独立只读审查与范围内修复、合理阶段提交、普通推送及本功能唯一的新 Draft PR；完成后停在 Owner 真机验收。A→B→C 是**同一连续授权批次内的阶段**，不在计划、每次 commit、阶段完成或首次 Review 后等待重复批准。

旧 CURRENT 中“等待 Owner Gate”的停点已被本次新开发授权向前推进；历史设备结论、失败和未运行项目保持原状，不因此变成 PASS。本 Goal 不授权发布、操作私人库或进入下一个功能模块。

## 2. 启动与固定输入

1. 按 `AGENTS.md` 读 INDEX 及 Foundation、`DEVELOPMENT_CONTRACT.md`、CURRENT，再读本组四份文档全文和实际相关代码。Foundation 已追加本次批准范围，不需要另行改长期 Contract 才能实施。
2. 只读核对仓库、分支、upstream、worktree、dirty、现有 PR。保留所有未知未提交/未跟踪工作；不要 stash/reset/restore/clean 或吸收它们。从固定 GOAL_SHA 创建本功能独立 worktree。
3. 验证 BASE 是 GOAL_SHA 的祖先，累计差异只有本节下列十份 Docs；产品、工程、测试和 workflow 未变。执行使用固定 SHA，不追随浮动规划分支。
4. 从 GOAL_SHA 创建 `codex/household-assets-v1`。同名分支/worktree/PR 已存在时先核对来源和未完成工作再安全续接，不删除重建、不强推、不盲目 pull/rebase。规划分支只放计划，不提交产品代码。
5. 旧 PR #13 和其他分支的 base/head/状态保持。若 PR base 后来前进，记录差异，继续固定输入下的安全工作；真正影响本功能集成时再处理，不能悄悄切到 main 或把无关改动计入本功能。

允许的规划差异：

- `Docs/HOUSEHOLD_ASSETS_V1_DESIGN_ZH.md`
- `Docs/HOUSEHOLD_ASSETS_V1_UI_ZH.md`
- `Docs/HOUSEHOLD_ASSETS_V1_GOAL_ZH.md`
- `Docs/HOUSEHOLD_ASSETS_V1_ACCEPTANCE_ZH.md`
- `Docs/INDEX.md`
- `Docs/CORE_MODEL.md`
- `Docs/INFORMATION_ARCHITECTURE.md`
- `Docs/V1_SCOPE.md`
- `Docs/CURRENT_STATE.md`
- `Docs/CURRENT_TASK.md`

不要要求最终 GOAL_SHA 必须是 BASE 的直接子提交；文档修订可追加，但祖先与累计范围必须成立。

## 3. 固定基线已核实的接入点

| 接入点 | 已核实事实与本期要求 |
| --- | --- |
| `Persistence/PersistenceFoundation.swift` | 当前 `PersonalGrowthSchemaV15`/15.0.0；保留 `V11Original` 11.0 与 `V11` 11.1 等历史迁移。追加 V16，不修改历史复用模型的字段或校验和。 |
| `App/AppContainer.swift` | 同一 `PersonalGrowthOS.sqlite`；`StartupStoreProtection.isCurrentStore` 还有 V15 显式引用，和 current schema/factory 一并更新，保留启动保护副本路线。 |
| `ImportExport/TransferModels.swift` | 当前包 v11、支持 1...11；顺延 v12，完整接入 DTO、计数、版本条件、引用与领域验证。 |
| `ImportExport/ImportExportService.swift` | 原始 JSON 必填检查、导出快照、隔离重建、磁盘重开比对、发布前再次空库检查、事务发布与刷新必须覆盖新模型。 |
| `TimeInvestment/InvestmentFoundation.swift`、`ExternalCapture/ExternalCaptureImport.swift` | 复用 fresh ModelContext + `StorePublication.perform` 隔离写入；主线程 try-lock/busy、临界区不 await。不要复制计时 Operation 状态机。 |
| `Growth/HabitViews.swift`、`AppShell.swift` | GrowthView 与现有五 Tab；复用 ModuleEntryRow/空态动作，不动 Record 主编辑路径。 |
| `Weight/WeightViews.swift` | 借鉴 Swift Charts、日期与历史编辑交互，不把体重的 Double 直接用于金额。 |
| 认证、同步、金额 | 目前无 LocalAuthentication、通用货币服务或 iCloud 同步；两处 ModelConfiguration 均 cloudKitDatabase:.none。认证和金额值层是本期的小新增，不能声称已有。 |
| 工程文件与本地化 | 显式 pbxproj target membership；新文件加主 App/Test，不能误入 Share/Widget；中英文 String Catalog 和认证用途说明一起完成。 |

不得新建独立主库，改变 App Group、主 Bundle ID、库路径、Share/ImportantDaysWidget 身份或签名/发布设置。使用 Apple 系统能力即可，不引入付费/外部 SDK。

### 备份接缝

- 新模型进入真实空库判定：只有项目、只有草稿或只有正式盘点也不是空库；首次浏览及默认分类不写库。
- v12 缺少必需新数组/字段必须拒绝；旧 v1...11 按原规则读取，新模块为空。不要用无条件 `decodeIfPresent ?? []` 掩盖新包缺失模块，不能允许新字段伪装旧版本。
- 导出包含冻结明细、草稿、原日期/ID/确认状态和关联；正式记录严格校验金额/日期/枚举，拒绝重复 ID、非法业务引用、同日重复正式盘点和多草稿。合理限制 payload 明细数。
- 草稿可保留输入中/非法的原始金额文本，备份只按草稿结构、长度、状态与必要引用校验，不套用正式金额规则；冷启动和 ZIP 恢复后输入保留，正式保存仍须校验通过。
- 草稿编辑目标 ID/基准 revision 是冲突信息；目标已删/已变化仍允许草稿备份恢复，但不能直接覆盖。项目 ID 与非空 relatedEntryID 才按业务引用规则检查，Entry 永久删除时清空后者。
- 预览与发布之间创建资产数据时，恢复必须拒绝覆盖；busy/失败不损失输入，不破坏其他模块未保存编辑。
- 合法的未知、沿用或没有首次盘点都不是坏库，不能使整个 App 启动失败。
- 可选 Entry 引用放在新快照；永久删除 Entry 清空引用，不动被旧 schema 复用的 Entry 模型。删除盘点不删用户 Entry。
- 整包导出仍未加密；更新现有说明，并在启用模块认证时覆盖含资产的整包导出/删除路径。还须覆盖 `PersonalGrowthOSApp.swift` 启动失败页 `retained.archive` 及 `ImportExportService.exportRetainedQuantityData` 的原始恢复包生成与分享；库打不开/数量未知不能跳过已启用认证。保留内部保护副本及原恢复格式，不扩成通用加密备份改造。

## 4. 连续实施顺序

### 阶段 A：可运行的纵向路径与视觉定调

目标：从成长进入、建项目、记录一次盘点、保存并看到可信总览；同时解决最易导致后期返工的迁移和视觉。

- 建小金额值层、项目/快照/typed 明细、草稿与正式隔离、日期和确认状态；明确整数分/Decimal 与规范导出表示。
- 完成单草稿、首次盘点、明确空范围、已知/未知/估算/沿用、原子提交和基本读取；至少用银行转投资、未知房贷两例证明计算口径。
- 接入 V16/v12 的最小完整往返链，尽早验证真实 V15 磁盘升级、空库可恢复和资产-only 非空保护；不要留到最后才发现无法备份。
- 实现真实原生的成长入口、总览、盘点编辑；用合成数据取得默认浅/深色总览和键盘输入画面，与相邻页面并排检查层级、间距、状态和控件习惯。
- 先修主布局问题，再扩展历史状态；不交付 HTML/静态图作为原生完成。完成阶段提交后直接进入 B。

### 阶段 B：完整产品体验与数据接入

- 历史补录、更正/删除、同日唯一、范围变化、改名/归档、草稿冷启动、冲突/失败保留；总览与所有图表同源。
- 净资产/负债趋势、资产结构、选择点与历史/分类下钻、空/单点/零/负值/缺测；项目最近金额注明真实日期。
- 备注、主动关联 Entry；中性引用卡、删除关系和备份恢复闭环。
- 完成金额隐藏、可选设备认证、后台遮挡、无障碍泄露防护及 CSV/整包导出入口的一致权限。
- 完成 v12 严格验证/恢复重开、旧包兼容、资产-only 非空和 publication 竞态；保留旧模块数据/媒体/关联。
- 中英文、窄屏、大字体、深色与数字键盘完整处理；保存失败和读取失败不是最后补的一条 toast。

### 阶段 C：集中验收、独立审查和交付

- 按验收表完成受影响数据/磁盘/UI 验证和约 8–10 张真实截图，不扩为全 App 重新设计或全部组合截图。
- 固定产品/测试候选；让真正不同的只读 agent/会话检查 diff、生产路径、测试结果和原始截图，修复本范围内确认问题，再复核受影响部分。
- 完成必要本地验证，普通推送产品分支，创建/更新本功能唯一 Draft PR，跟踪现有 CI 至真实结果，base 保持本文件指定。必要失败限定修复；更新 CURRENT 和精简交付记录，结束在 Owner 设备验收。

## 5. 测试与审查节奏

开始开发不重跑旧完整测试。改动时运行直接相关的金额、持久化、恢复和 UI 测试；共享 schema/导入/删除链的变更才扩大相邻回归。测试调用真实生产服务/磁盘/页面，避免另写一套只用于通过的计算实现。

基线 CI 已有 Release/Unit/smoke 证据；它能说明未改基线，不能冒充新产品通过。新模块的指定核心路径必须有新证据。真实 V15 升级应由固定 BASE 生成/冻结历史磁盘夹具，不能仅用当前修改后的旧类型临时造库声称等价。

现有 `.github/workflows/ios-regression.yml` 对 Draft PR 的 opened/synchronize 也跑三条常规 lane，没有 Docs 路径过滤。**本地按阶段 commit，集中一次有意义的 push/开 PR，让最终 CI 自然完成 Release、完整 Unit、5 条 smoke。** 不为了阶段留痕反复触发全套。CI 失败后的必要修复正常推送并复验，不禁止合理重试。

同一任务仅一个活跃本地 Xcode 测试队列。无具体风险不叠加完整本地 Unit + 完整 CI + 多轮全 UI；可以用定向本地验证与最终现有 CI 组合完成门禁，不修改 workflow 以回避必选项。

独立审查范围：数据语义、原子保存/恢复、历史稳定、隐私入口、现有 UI 一致性、关键错误状态。确认的本期 P0/P1 和影响必选行为/数据/隐私/可用性的 P2 应修复；无关旧债或个人风格偏好记录，不开无限治理任务。不要靠主 agent 自称换角色冒充独立 Review。

修复后只重跑受影响集合；改动涉及共享模型/恢复机制时按真实影响扩大。失败、SKIP、NOT_RUN 和环境限制保留，不删断言、不弱化校验、不拼接不同轮结果声称全绿。

没有 Xcode、CI 认证或独立 reviewer 时先完成不依赖它的安全工作，再精确报告 BLOCKED_ENVIRONMENT / BLOCKED_AUTH / REVIEW_BLOCKED；不可把缺失核心实现、缺少本地可执行验证改名为“等 Owner 真机”。

## 6. 证据、环境与边界

所有开发和验证用合成数据、任务自己的隔离模拟器/临时磁盘库。不得读取、导出、安装覆盖、清空或迁移 Owner 的真实私人数据，也不扫描私人目录找夹具。不得清理其他工作树、进程或无关产物。

每个关键 run 简记：产品/测试 SHA、选择器/命令、结果及原始证据位置；标明单元、真实磁盘、模拟器 UI、设备的不同证明范围。证据里的金额和名称均为合成，不提交私人数据。没有真实运行的内容保留 NOT_RUN。

最终 Release 按现有 CI 核对 App/Share/Widget 三包、身份、版本和构建来源；无签名构建不称为可安装 IPA。纯 Docs 收尾可复用前一相同产品树的测试并说明，避免只为改交接文字再构建。

旧 D1–D4、真实 VoiceOver/相机、AlarmKit 正向、Safari/Share 签名环境和低空间的 FAIL/SKIP/NOT_RUN 按旧证据保留；不受本轮影响的旧环境问题不重复烧测试，但新增 schema 对共享消费者的实际影响须评估。

## 7. 交付与唯一停止边界

交付至少包括：

- 完整可用的本期代码、必要测试和本地化；四份规划文档的实现偏差如有须如实解释，不悄悄删掉已定必选项。
- `Docs/HOUSEHOLD_ASSETS_V1_EXECUTION_ZH.md`：简明阶段、实际 schema/包版本、固定输入、命令/结果/限制、最终 branch/base/head 与证据索引。
- `Docs/HOUSEHOLD_ASSETS_V1_REVIEW_ZH.md`：独立 reviewer 身份/会话、审查提交、必须修项和关闭证据；真实视觉评审结论。
- 本组 `ACCEPTANCE` 将 NOT_RUN 改成有依据的实际状态；约 8–10 张截图和合成数据说明集中在 `Docs/Evidence/HouseholdAssetsV1/`。
- CURRENT 顶部更新实际状态和下一边界，历史文字与旧失败证据保留。

授权在本功能分支合理 commit、普通 push、创建/更新该功能 Draft PR。保持旧 PR；不 merge、不 force push、不 tag、不 Archive/TestFlight/发布，不擅自换 Bundle ID/签名，不操作真实设备或私人库。

完成必选实现、可执行验证、现有必选 CI 和独立审查，且无本范围阻断问题后，状态为 `READY_FOR_OWNER_DEVICE_GATE`。Owner 下一步只需按验收文档完成真实使用、设备认证/后台预览和既有设备项目；规划完成本身只能标 GOAL_READY。

最终用中文报告完成情况、固定 GOAL_SHA、实际产品/交付 SHA、新 Draft PR、验证依据和少量真实限制。普通可逆细节自主决定；真正阻塞说明证据和最小缺口，不在每阶段向 Owner 重复请求确认。完成本 Goal 后不开下一模块。

## 8. 本规划的独立审查记录（实现前）

2026-11-01，由三个独立只读 agent 分别审查数据口径、实际 UI 组件/截图和技术接入：`china_asset_apps`、`global_asset_apps`、`home_inventory_apps`。已按审查修正新草稿项目/元数据来源、范围变化断线、总览/历史日期归属、单摘要行与模块认证边界、草稿原始输入、缺失编辑目标的冲突语义及原始恢复包认证；补充零明细 CSV 保留。

UI 与技术 reviewer 对上述改动做限定复核，均确认可冻结、无剩余必须修项。此结论只证明规划契约已收敛；执行后仍需真实独立实现审查和本文件规定的运行证据，不能拿本节代替。
