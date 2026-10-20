# 本轮执行范围更新（2026-10-20）

以Owner最新指令为准：连续完成计数器P2、真实Actions、完整只读分支清点。本轮不执行下文旧G2真机验收或G3删除阶段；清点完成即交付，不以等待删除批准视为未完成。实际进展、精确候选和尚未运行门见 [EXECUTION](CI_DEVICE_BRANCH_CLEANUP_20261020_EXECUTION_ZH.md)。Owner直接批准后已普通推送，真实run39387986862必选检查通过，固定产品/测试3ee3cb6；本授权批次完成，停READY_FOR_OWNER_DEVICE_GATE。授权等待为历史，本轮不执行旧G2/删除门。

---

# 随心log — GitHub Actions、系统真机验收与分支安全收口 Goal（2026-10-20）

## 0. 已核实身份和执行原则

- 仓库 `yoCruzer/PersonalGrowthOS`，公开，默认分支 `main`。
- 规划时唯一最新集成候选：Draft [PR #13](https://github.com/yoCruzer/PersonalGrowthOS/pull/13)，head `codex/usage-remediation-20261017`，base `codex/time-investment-v1`。核对时交付 `c7f5a3836140a27801fa0a9f1bacbfb73c0d7e5c`，最近干净产品/测试 `1b150068e76f4d7e7a6defcd51f10622951f4b4b`。开始前以实时 Git 为准，保留后续有效提交，不从 `main` 直接替换当前完整产品。
- Owner 反馈：最新 Xcode Cloud workflow 已正常成功；**未取得该 workflow 的 build commit / TestFlight build 号 / 最终 iPhone 安装产物证据**，必须匹配候选 SHA 才能用于本次设备门。
- 规划时搜索到 29 个远端分支，PR #8–#13 至少 6 个开放 Draft；最新开发 head 不存在 `.github/workflows`。详见分支台账。
- GitHub 于 2026-10-15 宣布 `xcode-27` 标准 arm64 runner GA（https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/）；公开仓库标准 hosted runner 使用免费，**large/xlarge runner 及 artifact/cache 存储另行遵守政策**。不得以“免费”作为运行无界工作流或积累大型附件的理由。
- Owner 同意连续推进 CI 配置、合成/非破坏性准备与分支清点。**真实私人 iPhone 覆盖安装、读取/迁移/恢复个人数据库、签名或向外上传数据，都仍有单独的人和数据安全门；不得仅凭本 Goal 自动执行。**清理分支仅先生成经过验证的建议清单，真正删除须 Owner 按 branch/ref 明确批准。
- 遵守 `AGENTS.md` → Foundation → `DEVELOPMENT_CONTRACT.md` → 两份 CURRENT → 当前代码与测试，保护已完成且独立审查的提醒、时间投入、迁移/备份、Widget、Share 等功能，不重做产品开发。
- 整体按 **G1 CI → G2 设备验收 → G3 分支清理规划/获批后分批清理**。G1可独立完成，G2的Owner操作可以明确暂停并交付可执行检查清单；**即使 G2 因等待 Owner 未完成，仍做 G3 的只读清点，不执行删除**。

## 1. G1：增加 GitHub Actions 的真实远端 CI

### 1.1 工作流及安全边界

1. 先查整个仓库及默认分支 `.github/workflows`、Xcode Cloud配置、`Scripts/`、`.xcodeproj` schemes、实际 target/Unit/UI 测试、Simulator runtime 与 `git` 状态。已有等效 workflow 必须复用/完善，不重复增设；不得修改现有 Xcode Cloud 的 tag→TestFlight 逻辑或签名。
2. 优先使用标准 `runs-on: xcode-27`（Apple Silicon，Xcode 27 GA），不可默认使用付费 `xcode-27-xlarge`、自托管 Mac mini 或私人 Runner。使用 checkout 的受支持稳定版本，根/作业权限 `contents: read`，`pull_request` 与必要的 `push`（`main`及当前正在开发的整合分支），不使用 `pull_request_target`，不触发 tag、发布、上传商店。可按需求对 default branch 添加 `workflow_dispatch`，但其在默认分支尚无工作流时不能依赖 UI 手动触发作首次验收。
3. 一条明确有名字的基础 CI：先 `xcodebuild -version`、列 scheme/Simulator，动态或按实际可用 simulator 选择目的地；无签名构建所有相关 targets（App/Share/Widget）、Unit 测试，增加小规模可靠关键 UI smoke（如启动/重要导航），复杂 UI 放独立受控/手动/夜间任务并明确原因。最小功能门需要实际编译和实际 iOS XCTest，不接受仅 YAML lint 冒称 CI。UI/Unit 如果本机合成 fixture 在 runner 的磁盘/权限不满足，记录并分层，不删业务断言/改 SKIP 冒充全部 PASS。
4. 使用 `CODE_SIGNING_ALLOWED=NO` 及合理 DerivedData、timeout、concurrency；区分构建、全量 Unit、关键 UI 的结果。轻量静态/文档检查如有可复用 scripts 可加一项 Linux job，但不得用它替代 iOS 测试。优化实际跑时、并行与 cache 时注意标准 arm64 runner 内存/磁盘资源。
5. 公开 CI 不获取或上传 iPhone 私人库、照片、token、签名证书、API key、`.p12`、App Store Connect 凭据等；不得运行数据恢复于私人路径。合成数据和公开固定测试夹具才可进入 GitHub logs/artifacts。只有确有诊断必要才保存受控的 `xcresult` 或简化摘要，短保留期、大小界限、失败时隐私检查；排除高敏文本/路径。
6. 先本地 YAML/工具语法校验和必要定向演练，再普通 commit/push **原集成 PR #13** 或经确认的不破坏叠加 PR 的独立 CI PR（需清楚交代 base 关系），确保 Actions 真正由 GitHub hosted runner 执行，检查实际 run id、URL、job/step、Xcode/runtime、exit、PASS/FAIL/SKIP，直至约定必选 CI 全绿或出现明确非项目原因。不要以本机 PASS 代替 Actions。需要仓库 Actions 开关/权限时，指出精确 UI 步骤交 Owner；勿修改管理权限。
7. 先不要启用强制 branch protection，也不默认把 CI 变成合并门禁；待远端稳定、叠加链理顺再提候选规则。避免重复跑同一 push+PR 的完整昂贵矩阵；`concurrency` 不能误取消其他 PR 的独立运行。文档记录已运行哪些、没运行哪些及 Xcode Cloud vs GitHub Actions 的职责。

### 1.2 验收

- `.github/workflows` 源文件已提交，合适的 trigger 能针对 PR #13 实际运行；hosted runner 真实编译 App/Share/Widget 并运行 Unit；UI smoke 真实执行或按明确原因单独记录；
- 告警/日志不泄漏私人数据，不需要签名或 TestFlight 凭据；状态可定位、失败不吞；
- 一次稳定远端 PASS / 已知外部条件阻断的诚实记录，附 run URL/SHA/runner/version/test counts；没有偷偷改变 Project/Bundle/Schema/签名/Xcode Cloud tag 触发。

## 2. G2：系统性真机验收（而不是模拟器推断）

以 [DEVICE_GATE](CI_DEVICE_BRANCH_CLEANUP_20261020_DEVICE_GATE_ZH.md) 为逐项操作清单，编排 D0–D5：

- **D0 候选和数据安全门**：核实最新 Xcode Cloud/TestFlight 成功构建的 commit、实际安装 Build、Bundle、签名与 Git 源码；未与 PR #13 目标产品对齐不得宣称验收。Owner **先自主独立备份并确认可恢复**；不得通过卸载重装验证，不碰私人库/导出到公开 CI。尚无明确授权则停在 `WAITING_OWNER_DEVICE_ACTION`，给出精确下一步。
- **D1 通知和 AlarmKit**：真机授权、锁屏、静音、Focus、系统 Stop/Open、过期、改期、撤销/取消、重开及双渠道；实际行为逐项记录，不将 stub/Simulator 视为 native。
- **D2 时间投入**：真实锁屏与硬件睡眠、倒计时晚返回、暂停/继续/完成/恢复、草稿中断与修正，比较真实可信的耗时，不无端累计系统睡眠；合成时钟通过不等于此项通过。
- **D3 不卸载覆盖升级／备份恢复**：Owner 独立备份（含原图）完成后，经 Owner 认可再覆盖安装；升级前后核对主要对象/媒体/关联/时区，无清库；“导入恢复”仅在明确隔离的**空库测试环境**演练，绝不覆盖真实主库。
- **D4 公共能力**：实际 Safari 页面共享/选中文字来源、Photos、文件共享、Widget 刷新和深链、VoiceOver、中文/英文、Dark/大字号、离线组合；系统限制或环境 FAIL 记录真实原因，不降级为 PASS。
- **D5 日常核心流程**：Today/Timeline/Record/Growth/Library、Todo、Habit、Goal、Weight/趋势/BMI、ImportantDays、Sleep、Investment、QuietWins、Weekly Review 和备份，针对新增功能与相邻流程做覆盖矩阵；保留日常数据与操作结果证据。
- Owner 在设备上能直接完成的部分由其操作；Codex 可提供逐屏步骤、无敏感自动化、受控采集/诊断，但无新的明确授权不能代其执行安装、私人导入/恢复或任何不可逆操作。
- 每个项目标记 `PASS/FAIL/BLOCKED/NOT_RUN`，写设备型号、iOS、build/provenance、日期、前提、操作、预期/实际、证据说明，发现缺陷使用一个批次修复/补验，最终由 Owner 对 D0–D5 明确确认。不能因为 Xcode Cloud 或 Actions 全绿自动宣布设备门通过。

## 3. G3：分支清点与延后分批清理

根据 [BRANCH_INVENTORY](CI_DEVICE_BRANCH_CLEANUP_20261020_BRANCH_INVENTORY_ZH.md) 的初始29分支快照，使用实时 `git ls-remote --heads` + GitHub PR open/closed/merged + `git merge-base --is-ancestor` + 远端保护/默认分支/关联 tag（必要时 `git log --cherry`）建立带完整 SHA 的分支依赖图，特别记录 Draft PR #8→#13 的祖先/base/子分支，不能只按年龄或 `git branch --merged main` 删除。

将每条分为 `KEEP_ACTIVE/STACK_BASE/KEEP_HISTORY/CANDIDATE_AFTER_MERGE/UNKNOWN`，输出可排序 Markdown/JSON 清单：branch、head sha、最后提交、当前/历史 PR、base、是否已被安全包含、关联文档/发布tag、建议动作与理由。仍开放、仍作 base、没有上游保全、无法归因的分支禁止删除。**先做清点，即使 D0–D5 尚待 Owner。**

验收通过、叠加 PR 合入目标线且Owner逐条批准时才分批删除明确 SHA 的 `SAFE_CANDIDATE`；删除前重新 fetch、检查 ref 未移动和所有依赖，备份恢复引用方案，经Owner明确批准列表（批次和 SHA）方可实际远端删除；不可 force-push、自动合并 PR、自动批量删本地/远端，禁止 CI job 带 delete 权限。清理后重新核查开放PR的base/head仍存在、tag和需保留历史可追溯，输出删除前后审计记录。若尚无批准，完成清单即止，标 `WAITING_OWNER_BRANCH_DELETE_APPROVAL`。

## 4. 节奏与交付

- 本次授予 G1 CI开发、G2非破坏性准备及Owner可开展的指导验收、G3完整只读清点和建议；不授权自动合并/删分支/写私人库。内部同授权的可执行部分连续推进，遇真正 Owner 数据/设备/删除权限门再停相应动作，其他工作继续。
- G1 不必等真实设备；G3 只读不必等 D1–D5。先完成可执行项，不要为了一个无法由Codex完成的手动门使整个批次空转。
- 实现中仅做受影响验证；首次CI完成后保留工作流和真实run证据，必要时迭代直至收敛；不让1个大型压力测试挡住其他已可执行工作。独立 reviewer 审 workflow 的权限/供应链安全、运行日志与完整 diff，并审分支建议未误判叠加关系。
- 更新两份CURRENT、INDEX、CI执行报告、DEVICE_GATE/BRANCH_INVENTORY实际状态；普通 push，PR保持Draft/base（如必要单独CI PR需保证不会重复合并/丢掉原链，说明原因）。交付给Owner：CI真实链接和用量范围、精确候选SHA、可执行真机清单/已完成项、分支保留/候选列表、需要的 Owner 动作和明确安全停点。
- 无 tag、无 TestFlight再次发布、无商店签名、无生产数据删除、无自动 merge、无 branch force/update 到旧版本。
