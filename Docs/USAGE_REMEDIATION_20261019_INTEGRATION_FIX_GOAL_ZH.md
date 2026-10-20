# PR #13 集成边界修复 Goal

| 项目 | 内容 |
| --- | --- |
| 版本／日期 | 1.0；2026-10-19，Asia/Shanghai |
| 仓库 | yoCruzer/PersonalGrowthOS |
| 唯一实施分支／PR | codex/usage-remediation-20261017；[Draft PR #13](https://github.com/yoCruzer/PersonalGrowthOS/pull/13) |
| base | codex/time-investment-v1；5a70f0110b151f8a45ac7c33d3f443823b1cff24 |
| 已审产品／交付 | c55dc10fde79f1fe4dec18b03195119c2049830f／c1fe56477f2573930a65a95c46d4b7ab7296d6af |
| 固定规格提交 | INTEGRATION_FIX_GOAL_SHA 由 Owner 的短引导 prompt 提供，本文不自引用尚未产生的提交 SHA |
| 配套依据 | [集成边界独立审查](USAGE_REMEDIATION_20261019_INTEGRATION_REVIEW_ZH.md) |
| 当前状态 | FIX_GOAL_READY / LOCAL_REVIEW_FIX_REQUIRED；规格准备不代表实施或原生验证通过 |

## 1. 目标、授权和停止条件

在当前时间投入 V1 与使用反馈整改成果上，完成 IR-01～IR-04 四项 P2、IR-05 一项 P3 测试收尾，以及 V-01 原始恢复导出的有界并发验证；一并处理有证据的同因邻接回归。O-01 仅保留非阻断原生观察。保持已认可修复，不重做 A–D 或新增产品功能。

Owner 短 prompt 下达后，IF-A～IF-D 属于同一连续授权：本地核实、实现、定向测试、集成验证、独立复核、范围内修复、必要最终门、文档和原分支普通 commit/push。内部阶段、一次 reviewer 返回或某次定向通过都不是停止点，不重复申请“是否继续”。旧 CURRENT 历史中的 READY／下一步仅设备门由本 Goal 替代；设备未授权不能阻止本地可完成工作。

仅完成必要本地事项后恢复 READY_FOR_OWNER_DEVICE_GATE；真实能力阻塞则完成其它工作，写明具体未验证项及原因。保持原 Draft/base，不 merge、force push、另开产品 PR、tag、Archive、TestFlight、签名安装或操作私人库/设备。D1–D4 属于后续 Owner 设备任务。本任务不包含发送 PR 外部评论或其它人员消息；普通推送自然更新原 PR。

全程中文沟通和交付。技术标识保留原文，不把短引导或附件包装转为英文工作目标。

## 2. 轻量续接

按 AGENTS 和既有上下文读取 INDEX/现有 Foundation、Development Contract、CURRENT_STATE、CURRENT_TASK，再完整读固定 SHA 的本 Goal 和配套 Review。前轮已读且逐项确认未变的长期文档可以复用，不反复全文消耗。

核实原工作树 /private/tmp/PersonalGrowthOS-usage-remediation-20261017 是否仍适用、实际 branch/head/upstream、git status、PR head/base 和祖先关系。保留主工作区与其它任务的未知改动；不假定报告的 clean 仍成立，不自动 stash/reset/clean，不从老 BASE 重建候选。安全 fast-forward 接收规格；若有有效后续提交，比较本轮范围并保留，必要时在隔离空间协调。不能覆盖并发远端提交或用强推接收文档。

只接收 Markdown 规格不跑全量基线、不构建。先确认源码和本轮反例的现状，有实际风险的变更才做相应验证。已审 c55、完整 Unit 候选00b、旧 SYSTEM_FIX_RUNS 的证据仅按实际 blob/selector/配置关系复用，不用数量代替覆盖。

## 3. 完成证明必须跨越的边界

实施前先登记本轮消费者/状态矩阵，审实现时持续补齐。每项记录：合法起点、真实入口、持久/内存权威、共享服务、事件或异步结果、所有相关消费者、成功/失败/关闭/重开/冷启动后的状态、实际 test selector 和证据来源。

| 项目 | 必须跨越的生产边界 | 不能用来替代的局部证据 |
| --- | --- | --- |
| IR-01 | Service无变化→事件订阅→根页面reconcile→generation/gate→健康类别和等待者 | 单次直接调用coordinator后断言通过 |
| IR-02 | 真实旧行为→已有native ownership→两渠道局部隔离→取消确认→重开/纠正 | 只有Notification任务但传入AlarmStub |
| IR-03 | Settings A→关闭/重建→B意图→旧A结果→共享偏好和界面 | 同一个owner的两次submit |
| IR-04 | 前台真实import持锁→编辑提交→busy/普通失败→重入/重试/保存 | 只断言Service抛busy、私有State暂存 |
| IR-05 | 可控seed/clock/calendar→正式保存/事件→真实reader/界面 | helper去重或硬编码期望，不经生产读取 |
| V-01 | live raw SQLite写事务→独立自动对账→真实SwiftData保存→主响应/恢复 | 普通export的NSLock测试或手写SQLite替代SwiftData |

优先用足以区别故障类的代表序列，不做机械全组合。未改文件中的调用方同样是审查范围。不要复制一份正确算法或 UI 闭包到测试里只证明副本；需要可注入接缝时，从实际生产接线提取最小结构并验证 AppShell/实际界面确实使用它。

## 4. 内部阶段

| 阶段 | 内容 | 结束产物 |
| --- | --- | --- |
| IF-A 提醒集成 | IR-01、IR-02、IR-03 | 事件回路有限收敛、双渠道既有请求、跨sheet结果所有权 |
| IF-B 输入与时间 | IR-04、IR-05 | 失败后可达重试、确定性真实日期夹具 |
| IF-C 新导出补验 | V-01；按确认证据最小修复；O-01可顺带观察 | 有界原生结论、源数据/状态/恢复证明 |
| IF-D 集中交付 | 组合验证、独立异议审查、范围内收敛、文档/普通push | 固定产品/测试SHA、准确复用和设备门边界 |

可按依赖安排或并行只读分析；同一文件写入、Xcode/模拟器和共享证据目录由一个协调者串行控制。阶段切换不向 Owner 再申请继续。

## 5. IR-01：实际事件桥下的无变化对账收敛

修复条件：stopped 不进入需更新时间的候选；active unresolved 可保留并返回局部状态，但零事实变化不 save/post 事实变更事件。真实健康跨区更新仍原子保存并发出必要通知；混合数据第一次真实变化后，后续只剩 stopped/unresolved 时必须退出。

不要改写 stopped 的原提醒字段来消掉候选，不删除历史，不猜offset，不禁用整个事件订阅，不 catch-all 把存储/结构错误当普通局部策略问题。外部真实 mutation 必须仍能使正在运行的旧代次失效。

最低回归序列：

1. 当前版本显式 offset 系列创建→Stop→切区；原始 V11 nil→Stop→切区；旧行为产生的 active unresolved→切区，三类分别确认。
2. 通过生产事件订阅连接实际 coordinator，包含健康 Todo、ImportantDay、Sleep；权限/系统查询用可控 async barrier 让反馈任务真实有执行机会。
3. 断言发布/对账次数有界、静默后不再自行增加、健康状态最终可发布；同时提交 daily 或 weekly 的共享 gate 等待任务并确认能完成。
4. 混合健康跨区变更正对照，事务失败回滚和恢复正对照。只在无修改时抑制事件，真实变化不能漏通知。

无限循环红例要可控结束：独立 fail-safe、清理观察者和挂起任务、归还共享gate，避免污染后续测试。不得靠任意 sleep 或“总耗时<N毫秒”替代因果断言。

## 6. IR-02：局部规则隔离处理两个渠道的存量未来请求

使用真实 V11 模型/既有可追溯旧 f1 保存逻辑构造合法 nil+多次当前覆盖，覆盖 Notification 与 Alarm；给同一真实调度器/客户端建立 accepted future ownership，再更改时区进入当前隔离流程。不得仅直接拼一个损坏设备记录。

必须满足：

- 未来被隔离请求需要两渠道对应的取消/退役确认，不只阻止新增；健康三类继续调度。
- 系统取消或本地确认失败时，持久身份与 cancellationPending 保留，局部规则说明不得掩盖取消未确认。
- 选取取消前journal写失败、native取消失败和取消后确认落盘失败的代表序列，检查最终实际存在性与durable身份；不能仅用cancel抛错代表全部失败阶段。
- 冷重开后仍能复查；确认不存在后才单纯显示待纠正规则。
- 用户明确 futureSeries 纠正规则后，验证实际新请求和持久状态恢复；仅断言offset变了不够。
- 普通元数据编辑、普通刷新不能让系统 Stop/已retired请求自动复活；一代一身份、旧native未确认取消阻止替代的保护保持。
- 正常已到点仍ringing的Alarm不被此次未来隔离误取消；到点/停止/已消费是原保护对照。
- 隔离原因不能误写成用户主动关闭，也不能滥用容量等待理由导致后续错误重排；优先最小复用现有合法状态。

最低矩阵：两渠道 accepted future→隔离→cancel失败→冷重开→确认→明确纠正恢复；再选系统Stop/retired、正常ringing、健康同队列、原满队列容量取消的代表对照。全部通过真实scheduler和持久化，可以本地用系统客户端桩；D1原生正向仍不标PASS。

## 7. IR-03：稳定的每渠道设置意图所有权

把结果所有权放在 sheet 之上的稳定生命周期或等效共享per-channel票据中，明确业务偏好与页面显示的归属。必须实际接入 MediaStorageView，而不是仅新增未使用 helper。daily/weekly相互独立，共享系统 mutation gate 和预算边界保持。

所有旧success、ordinary error、CancellationError均在统一结果出口检查当前意图；值相同不能证明仍是同一意图。旧请求不得修改新enabled/minutes/weekday、权限显示和错误提示；当前真实失败仍可反馈。

确定性序列：A已进入真实scheduler.addRepeating barrier→关闭/重建设置owner→B off/on并回到A相同参数→A普通错误/成功/取消返回→确认B意图及最终系统请求保持。另测B明确off、B当前真实失败和无新B时A仍合法完成。参数变更而新onChange尚未提交的既有保护保留。

至少有生产所有权组件的真实双实例/共享票据测试和一条实际设置页关闭/重开的接线证明；允许同一已挂载集成测试承担两者，不要求重复跑同路径两套UI。关闭时只cancel不是完成证明，必须避免偏好已开而合法请求无故丢失。异步测试以明确barrier顺序反证，不假定Task启动乱序。

## 8. IR-04：重命名失败后的可达草稿

活动ID与名称草稿有明确寿命，busy/普通失败后用户能在当前表单或明确重试入口看到原输入；成功和明确取消才结束编辑。系统alert的按钮/呈现绑定都有关闭效果，不能只移动清nil；可复用已有Todo清单可重试sheet模式或等效最小结构，不新增通用编辑框架。

用真实 ExternalCaptureImporter.scan/consume 的持锁 checkpoint 形成自然前台导入竞争：A名称输入B→提交busy→主响应先于释放、正式仍A、失败草稿B可见可重试→释放后重试成功仅一次。覆盖普通保存失败、取消、成功关闭，以及切换活动不串稿。红例和绿例经过实际界面保存/重入路径；不以service抛错测试代替。

保留create/start/正式记录editor已有成功后清理，SR06的成功缓存释放和持久saved幂等证据、Record独立草稿、F5读数边界。避免为了重命名失败保留而恢复所有已完成editor。

## 9. IR-05：确定性日期夹具

这是一项合并的P3测试收尾，产品统计主体已认可。

- BV-01：按明确calendar的自然日建立10000个不同日；生产Growth读日口径和夹具一致。测试仍真实挂载Growth、真实Service写入→didSave→实际Weight/Sleep读取计数；可见/切离均保留，正式Weight增删/活动变化正对照仍执行。不要改成只验证构造函数。
- Weekly：seed、实际截止reader和明确所选周共享受控测试时钟；保留本周/历史周后半段/未来排除，并用可控推进验证未来纳入。生产默认仍使用实际时钟，测试注入不得冻结普通App。
- 以LA午夜跨DST、周一首分钟等确定参数证明原反例，避免任意等待120秒。不能修改宿主日期/时区、缩短滚动次数以碰运气、放宽断言或用UI文字硬编码替代真实摘要。
- c55旧实际PASS和BV01 actualFetches=0原证据不改写；新增稳定性验证另记实际分轮。

## 10. V-01与O-01的限定处置

### V-01：必须完成一次真实原生有界验证

候选仅为新的live raw capture SQLite writer事务与Todo MainActor保存竞争。旧原值保留、正常备份有限数检查已认可，不重做全部备份或预设新并发架构。

在真实 exportRetainedQuantityData→StartupRetainedData.capture 的writer事务已取得后设可注入barrier，触发独立significantTimeChange/实际Alarm状态路径→生产reconcile→真实SwiftData保存；投递MainActor probe并设置独立fail-safe。源于有效跨区刷新或真实accepted请求消失的journal写，不能用手写SQLite连接替代。普通.active先await importShares，不可单独用作绕过发布锁的证据。

必须以可观察的生产保存入口证明：raw writer仍持有时，该路径已尝试实际SwiftData.save。probe由独立执行器投递，不以等待save/reconcile完成为前置；记录写入尝试、probe、锁释放和保存结果的因果顺序。probe在前置权限查询期间先跑不证明安全，先await保存完成才投递probe不证明阻塞。未命中真实竞争保存，不得登记VERIFIED_SAFE/DISPROVED。

若probe只能在释放/内部timeout后执行，确认阻塞并同批做最小一致修复，再重复同一反例。若快速失败，核对无数据丢失/误报成功、原始恢复包仍保留原值、提醒状态诚实、释放后重试/重新对账能够恢复。保护SQLite快照/媒体发布、取消/清理的已有合同，不通过删除互斥换响应；不把同步save外面包一个仍在MainActor的Task冒称解决。

最终登记：VERIFIED_SAFE或DISPROVED要说明否定的是哪一个影响假设和实际证据；CONFIRMED_AND_FIXED需有前后因果及原保护；本地能力确实不足则VALIDATION_BLOCKED并说明缺少什么。NOT_RUN/推测不能关闭此项。新raw不是普通可导入备份，不自动修正或丢弃旧异常事实。

### O-01：非阻断观察

Weekly已打开页在跨周/切区、父状态刷新时是否保持所选周及未保存输入，目前UNCONFIRMED。可在IR05已需的原生验证中顺带检查。未获原生证据不先改产品、不升级confirmed，不因为该观察未证明就单独阻止本地放行或新增大套UI。若得到明确合法反例，按范围内事实/输入问题同批修复并记录新证据；否则保留观察和局限。

## 11. 保护范围

已认可的SR02无损编辑、SR03三事实/业务日主体、SR06成功释放、SR07共同布局、BV01限定失效、BV02原值保留继续有效；原R/F/CR/UX的有效回归继续保留。重点回查受本轮修改实际影响的共享提醒取消/容量/停止、legacy nil/回滚/ZIP、MainActor checkpoint/晚pause-finish、F5 Service→事件→同Workspace实际读取、计时保存落点/独立草稿。

不机械统一Habit所有消费者：日粒度进度与实际时刻证据的既有边界保持；不改未来原始事实、缺metadata回退或旧事件字节。排队checkpoint取最新clock supplier并在重试时采样，不能用冻结采样去修无证据的问题。保持五Tab、现有Schema历史、备份兼容、身份/版本/容器和原产品边界。

优先不新增Schema、通用状态机平台或依赖。若确认必须追加持久状态，按既有合同做最小追加与真实迁移/恢复证明，不修改历史Schema或旧事件解释。AI、云同步、多用户、HealthKit、时间投入Alarm/Live Activities、新模块和发行工程不在本轮。

## 12. 验证与独立复核

### 阶段内

先保留有区分力的原反例，再定向修复和验证；不能伪造修前native红测。旧源码因API不同无法直接编译新增测试时，保留原生产触发证据并明确差异。barrier须有界、失败后清理任务/订阅/锁，模拟器写操作串行，不使用私人数据。

不每阶段全量Unit/UI或重复双构建。若失败是测试驱动问题，保留原FAIL与实际证据，修驱动后重跑受影响完整测试方法，不能只补最后断言就算原路径通过。

### IF-D最终集中门

在整合候选安排一次完整Unit，加一组按最终diff选取的必要关键UI/集成。IR01实际事件桥、IR02真实两渠道持久链、IR03跨sheet、IR04失败重入、IR05真实日期读取、V01原生写竞争均要有直接证据；同一测试满足多个条目无需复制运行。

已通过且生产路径/测试体/依赖配置未受影响的旧UI可按blob/方法/配置明确复用；全Unit已有的旧保护不再逐类重复。最终review后如有产品变化，按实际影响补跑完整受影响类/方法并重新绑定构建，不能把旧全量结果冒称新SHA一次全绿；只有出现新的广泛风险才再扩大测试。

固定干净产品/测试SHA，沿既有设施完成Debug Simulator（有效同候选build-for-testing可计入）和unsigned generic iOS Release，核对实际App/Share/Widget身份、版本1.0(7)、minOS17、完整SHA/Dirty=false、AlarmKit弱链接和用途说明。纯文档交付不重建产品，不为新规格先重复基线构建。

### 独立终审

至少一名未编写本轮产品修复的reviewer审固定候选，先按第3节列跨边界合法反例，再读实现者关闭表。检查完整diff、未改调用者、实际AppShell/界面接线、失败后重新操作、旧保护和测试区分力；直接读取本机可用原始日志/xcresult/代表图/实包，并说明实际读取层级。

逐项回答：无变化事件是否静默；两渠道已有future请求是否收敛且ringing/Stop保持；跨sheet同值新意图是否隔离旧结果；失败后草稿是否可达；固定日期是否进入真实reader；raw写竞争是否由真实SwiftData证明。不能只审helper或复述PASS数量。原文审查意见追加记录，实施者不得代写独立全通过。

有证据的范围内问题连续修复并补验，不在首次终审后提前交接。充分验证后停止无目的扩大测试，不为凑“没有风险”重跑所有原生环境门。

## 13. 交付、状态和证据

持续更新CURRENT_STATE/CURRENT_TASK和既有EXECUTION/ACCEPTANCE/REVIEW最新章节；保留旧失败、取消、补验、SR/BV关闭证据和本次固定Review。可新增小型INTEGRATION_FIX_RUNS.json，记录每条IR/V的起点、入口/消费者、权威/相反操作、selector、SHA、clock/locale、命令、退出码、PASS/FAIL/SKIP/NOT_RUN、原始产物哈希、复用依据。原始大产物留合成测试的本机证据目录，不将私人数据或实包入Git。

普通commit/push原分支，保留有效后续提交和未知工作区改动，PR13仍Draft/base不变。交付给出INTEGRATION_FIX_GOAL_SHA、最终产品/测试SHA、纯文档交付SHA、实际工作树状态和逐项关闭证据；规格提交的SHA通过Owner短prompt固定，避免文档自引用循环。准备本Goal本身不执行产品/原生验证，不能制造新PASS。

| 最终状态 | 必须满足 |
| --- | --- |
| FIXES_IN_PROGRESS | 正在本地实现、验证或审查 |
| REVIEW_BLOCKED | 仍有范围内confirmed问题未关闭，列出真实剩余问题 |
| VALIDATION_BLOCKED | 必要本地验证确实受能力限制，完成其它工作并明确缺少的证据；不以UNKNOWN冒称安全 |
| READY_FOR_OWNER_DEVICE_GATE | IR01～05有关闭证据或严格生产反证；V01为VERIFIED_SAFE / DISPROVED / CONFIRMED_AND_FIXED且有对应原生证据，VALIDATION_BLOCKED不满足此条件；必要集中门/固定候选双构建和独立复核完成；无范围内未关闭confirmed P0/P1/P2及本轮明确P3。O01单独UNCONFIRMED不阻断 |

D1–D4仍NOT_PASSED；AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、远端CI NOT_RUN是当前既有记录。只有确实执行且有相应证据才可更新，不用桩/unsigned包替代，不把设备验证混成本地需要申请新权限才能继续的停点。

最终中文交接应说明修复的真实集成不变量、相邻保护、实际分轮与复用、V01的结论和限度、设备门未通过事项。完成到本地停点后交接，不进入未授权设备或发布操作。
