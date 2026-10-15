# PR #10 限定 Review Fix — IMPLEMENTING

本轮固定输入d98306f219ed5929d38856216cd9af52fa5c7744；外部独立审查确认R1–R4四项P2及R5预览P3，替代下方旧“范围内已收敛/设备Gate”结论。沿原PR10/分支续接，当前候选9538ec7已实现R1–R5并由唯一独立reviewer作代码层复审；集中测试与删除目标宿主边界仍验证中，不宣称最终通过。具体证据见EXECUTION，本轮最终停READY_FOR_INDEPENDENT_REVIEW。

---

# 以下为上一轮交付历史（不覆盖本轮发现）

# 重要日子 V1 验收与 Owner Gate

状态：**READY_FOR_OWNER_DEVICE_GATE**。A/B必选实现、可运行自动化/构建与独立审查已收敛；产品/测试提交已普通推送到新Draft PR。设备门禁仍需Owner决定，不进入发布。

## 固定身份与范围

- 仓库 `yoCruzer/PersonalGrowthOS`；产品基线 `20d315a62179ad29a6cbcf76c33c11638412e54e`。
- Goal/设计固定提交 `3365561c5888701ce662ac6c8655ad1629ded6d0`；该提交仅新增两份规格。
- 工作树 `/private/tmp/PersonalGrowthOS-important-days-v1`，分支/upstream `codex/important-days-v1` / `origin/codex/important-days-v1`。
- 最后生产代码 SHA `9f34034357ea9329730ab18bfbf6d4b6e426b4b4`；产品/测试固定提交 **`b3cc408d323e5828e9550decac72ae534f1b0b20`**（之后仅修备份测试夹具，无生产改动）。交付 SHA 由后续文档提交及 PR head 核对；不写自引用 hash。
- 新 [Draft PR #10](https://github.com/yoCruzer/PersonalGrowthOS/pull/10)，base `codex/quiet-wins-on-d72`，固定 base SHA 为上述产品基线。旧 PR #8/#9 不修改。
- 原工作区未知 project/catalog/xcodecloud 改动原样保留；未操作真机、私人库、账号或证书。

## 用户可见结果

Growth 在体重之后提供重要日子入口；Today 在目标后、周/月习惯前按条件显示至多两条。保持五 Tab 与 Record 主路径。管理、搜索、收藏手动顺序、详情、归档/删除、三预设、最短名称/日期保存、公历/农历及未知起始年均可用。相关记录默认今天；旧记录创建日子须确认实际发生日。Entry 可关联多个日子，明确年份可保存实际期次日期并筛选；相关 Todo 为独立一次性任务，日子改期不静默修改任务。

Widget 有“重要日子”和“日子清单”两类型：前者提供小/中尺寸数字或照片表达，后者中尺寸手动配置 1–3 个槽位。帮助页复用真实 Widget SwiftUI 视图，说明系统添加步骤；没有宣称 App 已自动添加。桌面授权默认关闭，Gallery 只用合成内容；缺失或失效 ID 不替换为其他私人日子。

## 需求 → 实现 → 证据

证据根均为 `/private/tmp/pgos-important-days-evidence/`；Xcode 27.0 (27A266a)，macOS 27.0.1，iOS Simulator 27.0，专用合成 iPhone 18 Pro `EC7758DB-5D1B-4D1C-AA4D-900A9E11B66A`。测试命令及所有早期失败见 [执行断点](IMPORTANT_DAYS_V1_EXECUTION.md)。下表的“通过”仅指对应自动化/代码证据，不代表系统桌面或真机已通过。

| 要求 | 实现位置与可核对证据 |
| --- | --- |
| 当天/次日、年末、过去意图、未知年份、二月29三策略 | `Shared/ImportantDays/ImportantDayDate.swift`；`ImportantDayDateTests` 在 FinalUnit1 全部通过，独立 HKO 样例不由被测函数生成 |
| 农历跨年、闰月、缺三十、原始事实、范围边界 | 相同纯模块；HKO 2023/2024/2025 固定样例；原始事实与年度 fallback 分离，范围 1901–2100，不以干支年冒充公历年 |
| 时区、DST、系统回拨 | Date/Reminder/Widget 单测：23/25 小时自然日、上海农历、2026→2027→回拨相同 nextFire 且原始规则字节/revision 不变；不改旧 Habit 日期证据 |
| Today 条件/隐藏/常看、>2条、同日平局 | `ImportantDayTodaySelector` 确定性排序/最多2条单测；AppShell 保持原模块顺序；集中旧 Today UI 验证原路径 |
| 创建、确认、重开、中文深色大字号 | `ImportantDayViews`；7/7条 ImportantDay UI 在集中运行通过；中文真实 simctl dark，原生 wheel 日期和换行；旧启动 Dark 参数无效的早期证据不算 Dark PASS |
| 关联/发生日/多对多/删除/期次 | `ImportantDayService`、EntryDetail、Detail/Picker；Persistence 单测、过去农历2024-02-10写入→重开→General负对照/指定期次正对照 UI；编辑规则重置期次并验证新输入 |
| Todo 独立、失败原子性、改期提示、重复历史 | 类型化 `ImportantDayTodoLink`，不伪造 Entry source；新 Persistence +旧 Todo/Foundation/Reminder 全量回归；集中一次性与每日重复 UI |
| Quiet Wins 证据与不重复计数 | 关联/封面不生成伪记录；本地 source=nil 收据与 URL 排除、直接文字/图片正对照单测；完整 QuietWinsReaderTests 全量通过；集中五来源/撤销/后台真实导入 UI |
| 提醒权限、容量、失败、并发、actual pending | 统一 coordinator + `NotificationMutationGate`；Todo/日子/每日/每周共用保守60预算，保留其他前缀；新旧提醒测试通过，实际适配注入、交错 generation、部分排期和覆盖状态；无下一支持期次独立文案 |
| 独立封面、裁切、取消/替换/低空间/删来源 | 复用 PhotoInputSession 生命周期；独立 MediaStore 拷贝/事务提交/失败清理；全量原媒体/输入会话测试、新封面保存/替换失败/低空间/删源/删日子测试；照片裁切和遮罩真实渲染。系统 Photos 选择 UI 的完整手工流程 NOT_RUN（界面工具无Simulator控制入口，未将尝试计为通过） |
| 追加升级/旧包/新包→空库→重开 | V12 四实体追加，不改旧模型定义；v8 四数组/媒体；精确基线 V11.1磁盘与独立 v7包对照，旧来源收据单独验证；新 v8 全关系/封面磁盘重开；真实32MB HFS+ ENOSPC 保护通过；备份53项补验通过 |
| Widget 最小快照/撤权/坏文件/缺图/恢复 | `ImportantDayWidgetPublisher` 同步重建，先撤旧 manifest/代际文件并刷新，再缩图/原子发布；Extension无SwiftData；版本/大小/路径/坏规则拒绝，错误不影响Record；Widget单测与独立审查通过。恢复通知触发排期与快照重建；真实桌面恢复显示属设备Gate |
| 数字/照片/清单/长名/大数/隐私 | `ImportantDayWidgetViews` 真实 ImageRenderer PNG，在 `widget-renders/`；已目视浅深/AX布局。两种不同私密标题/封面在 `.privacy` 下像素完全相同，正常图正对照不同。系统桌面/tint未运行，不以图片替代 |
| 非每日前台的未来日期 | 实际 provider 使用共享35个当地午夜序列，`.atEnd`；单测验证36 entries输入、连续日期、春秋DST23/25小时，未来日期重新计算不依赖快照中缓存天数。系统实际刷新时机由iOS控制 |
| 稳定ID、Record草稿、编辑器排队、失效/恢复 | 系统 simctl openurl 驱动，非 XCTest.open(URL) 重启替代热路由；热路由保留Record草稿和当前编辑器，未授权ID中性；冷启动先保留提示、恢复失败不挂详情，Retry成功后交付。实际通知递送/点击属Owner Gate |
| 打包/身份/双语 | Debug sim、Release sim、Release generic iOS 三种实际构建均通过；每包含App+Share+Widget，原版本1.0(7)、派生ID、原AppGroup/URL scheme；`final-product-build-proof.json` 记录干净b3 SHA。新增相关键中英，实际App编译catalog en/zh-Hans各810键，最后新增6键两语均已核对。未签名构建不是签名资格证明 |

独立农历真值来源：[HKO 2023](https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2023e.pdf)、[2024](https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2024e.pdf)、[2025](https://www.hko.gov.hk/en/gts/time/calendar/pdf/files/2025e.pdf)。全范围年初一遍历仅是内部一致性，不冒充200年逐日独立核验。

## 最终验证口径

- `FinalUnit1.xcresult` / `final-unit1.log`，精确9f34034：**358 PASS / 4 FAIL / 0 SKIP，362项，exit65**；runtimeWarnings=[]。真实低空间测试已挂32MB卷并通过。4失败均是旧格式 fixture 错带v8字段或预期计数漏新零项。
- b3cc408仅修上述测试夹具，并补八个v8 missing/null反例、旧v7带新key拒绝和合法v7正对照；`FinalFocused1.xcresult` / `final-focused1.log` 的 **53/53备份单测通过**，集中 **17/17 UI通过，合计70/70、0失败/跳过、exit0**，driver delivered=4。不得合并写成一次363项全量全绿。集中summary保留4条Invalid frame dimension：发生于QuietWins五来源、Todo每日重复、WeeklyReview和Weight测试；这些测试名不是警告根因证明。
- `debug-final.log`、`release-simulator.log`、`release-device.log`：b3cc408干净工作树三构建exit0；`final-product-build-proof.json`核对9个bundle与SHA/原版本/原组。源码entitlements核对不等于设备签名授权。
- 开发中重要运行：Integration1 30/30；WidgetRenderRoute1固定58355为7Unit+1UI PASS；ReviewFix2固定06ce为9Unit+1UI PASS/1UI FAIL；ReviewFix3固定9017为25Unit+1UI PASS/1UI FAIL。失败及修复原因完整保留，不互相覆盖。
- 独立reviewer为实际 `/root/important_days_data_review` 与 `/root/important_days_product_review`，多轮固定SHA只读审查；P1照片privacy、P2旧年份期次、P3Todo文案以及后续表单加载问题均修复并复审，无未关闭confirmed范围内P0/P1/P2。详见[独立审查](IMPORTANT_DAYS_V1_REVIEW_ZH.md)。

## 继承限制与未运行门禁

v8继承旧备份不保存 CaptureImportReceipt 的已接受边界：本地磁盘覆盖升级保留收据；备份恢复后的 source=nil 外部文字/图片不能再识别，会按普通记录计算 Quiet Wins；URL来源仍可排除。本次不伪造来源、不扩修该已接受范围。原 Goal 时钟回拨P2继续按原文保留。本轮4条布局警告按上述实际测试归属记录，未扩修无关布局问题。

提醒仅预排最多两个期次、每期最多两个offset；实际pending/容量/覆盖反馈可见，需App前台补充，递送/Focus受iOS控制。Widget一次提供35个未来午夜，iOS刷新和已渲染缓存时机不能保证；撤回时优先删除App可控共享文件，不能承诺远程立即抹去系统已渲染图片。AX物理尺寸有限，清单减到两项、文字上限xxxLarge，完整内容用语音标签，未以微小字号塞满。

NOT_RUN：远端独立CI（GitHub workflows实际数量0）、完整Photos选择界面、真实HomeScreen添加/编辑/长期刷新/着色、真实本地通知递送与点击/Focus、VoiceOver、真机签名/安装/原App覆盖及私库。可运行真实SwiftUI Preview/合成自动化已提供；设备项不是发布PASS。

## Owner 最小四日子清单（需另行授权真机操作）

1. **未来旅行**：仅填名称和日期保存，在Today/数字小组件查看方向；提醒选择后核对实际next和权限，真实收到后点击；打开已有Record草稿时确认原内容仍在。
2. **过去起点**：确认实际发生日，看到累计天数；写一条今天的相关记录，再建一次性Todo；改期日子，检查Todo仍按原安排且有差异提示。
3. **农历生日**：未知起始年可保存，无虚构年龄；按自己的特殊日期确认闰月/三十规则，实际桌面选择该日、核对换年。切换浅深/着色与较大文字，使用VoiceOver听标题/方向。
4. **已有图文周年**：从旧Entry创建并确认实际日；封面独立复制、调整裁切，尝试选图后取消/换图并确认旧封面保持，选往年期次回看；添加照片组件和清单并手动排序，再撤权检查中性降级。Owner决定原App覆盖安装前，先保全现有资料；本轮没有操作私库或安装。

未执行merge、force-push、tag、Archive、TestFlight、账号/协议/证书变更；最终停在Owner设备Gate，不自动进入发行。
