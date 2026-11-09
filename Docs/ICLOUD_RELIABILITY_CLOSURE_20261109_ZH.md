# iCloud定向可靠性收尾（2026-11-09）

当前：R1–R5修复、独立复核与新源码CI已完成；Xcode Cloud TestFlight Archive进行中。最终非skip源码`59104222b0ca654ca5cffa8faed3e2f208e91b2e`，原分支/原Draft PR19保持。

- 独立只读审查发现最长retry-after丢失P2，已修复批内/跨callback及外层throw三出口，永久错误与诊断首因保护不变；复核无其余must-fix。实际本机61/61与最终28/28通过，干净Release三Bundle/production pin/中文/源码绑定通过。
- [产品CI42630679905](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42630679905)：Unit715=714PASS/0FAIL/1SKIP，Smoke8/8，Release三个unsigned Bundle成功；runtimeWarnings空。[定向CI42630679938](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42630679938)SUCCESS，完整检查计数见JSON。
- 四份官方ZIP SHA256/CRC匹配；实际checkout280327a包含5910422，生产/测试/工程/包/脚本/CI输入一致，24个package源码摘要匹配。Unit树计数与摘要逐项核对，新聚合测试确实PASS；聚合策略测试不冒称SDK callback E2E。
- 唯一SKIP需要隔离32MB HFS+镜像；optional extended UI未跑；远端独立分块未跑旧49MB最大案例，其本机历史证据保留。所有旧红测/编译/数值桥接失败保留，不能称零编译warning。
- Owner明确授权后普通推送新源码；新annotated tag`testflight-icloud-reliability-20261109`远端对象031e8eb3678b37ffb89fa02a46aa8073297b776c，解引用精确5910422。标签不指向文档提交，旧标签未改。实际Xcode Cloud Archive已启动，尚未观察TestFlight可用/安装。

[证据索引](Evidence/iCloudReliability20261109/README.md) · [独立审查](Evidence/iCloudReliability20261109/independent-review.md) · [新包一次验收清单](Evidence/iCloudReliability20261109/owner-acceptance.md)。以下为保留的执行历史，旧待授权/旧候选/未完成门均由上方最新节点替代。

---

## 历史执行记录


输入：[固定交接报告](https://github.com/yoCruzer/PersonalGrowthOS/blob/47fe200e515a82ddad9ba16f5666ceb4329ee108/Docs/ICLOUD_POST_SUCCESS_REVIEW_20261109_ZH.md)。基线为原产品分支`codex/icloud-product` / Draft PR #19，`ddc5af8b91fcf9d3cde7434bb7bda074d859ad4a`，远端与本地均已核对，产品工作树起始干净。主项目待办分支三项改动未动。

Owner已手动部署Production schema；现有Build19 / `4d4fc812739fb51394364f4c5e629ff7cd42ea4f`手动同步成功，删除App和本地数据、重装后观察到云端数据返回。记录为`OWNER_REPORTED_SUCCESS` / `OWNER_REPORTED_RECOVERY_OBSERVED`，不把它扩写为数量、全量内容、关系、原图或双设备/后台传播全部通过。本轮不重新部署schema，不要求重复删装，不建Mac探针，不清任何业务库、队列、ACK/token，不改工作区身份、不删云端数据。

## 修复与不变量

- R1：本地capture缺席仅能从实际发布过的fingerprint推导删除；`unpublished`远端对象不能生成本地tombstone或阻断同kind的无关保存。真正被编辑的多head/pending对象仍由`prepare`保护。指定缺原图集成用例先实跑红测，再补新增/编辑/关闭同步写入、磁盘重开后真实enable→initialize→transport→apply恢复。补原图走受控transport，不直接绕过启动入口。
- R2：CloudKit明确暂时性错误与完整性/身份错误区分；同engine保留checkpoint和精确ACK，使用单任务退避与持久retry-after截止时间。缺父版本/原图/未保存草稿为等待，前台、网络恢复或计时器可续跑；不支持版本、损坏/隔离输入、结构循环及真实冲突仍需处理。
- R3：busy期间合并待唤醒请求，收尾串行补一轮；send完成、fetch暂停时保存新增/修改均由持久outbox续发，没有并行transport。
- R4：SDK解析后的database通知核对正式container/private scope；兼容recordZone时还核对当前zone。无关容器、公有/共享数据库、其他zone、关闭同步与旧generation不推进当前状态。通知只触发同一串行获取入口。
- R5：设置页复制诊断，记录时间、源码SHA/dirty、环境、阶段、domain/code与允许公开的原因、recordType、成功/失败数、有界underlying/partial摘要、待上传/应用/历史规模及接近10,000修订限制提示。只序列化白名单，不复制正文/原图/CKRecord、账户/业务UUID、路径或底层description。独立本地sidecar最多8个事件并保留当前错误链首因，不改变业务schema或ACK；新文案解释双向连接与仍需验收的范围。

保留单zone、显式启用、账户/environment/dataset/generation及统一应用边界；V17/V18实体声明不变。K1 ZIP恢复独立工作区再发现、K2跨UUID自然键冲突闭环、K3安全历史整理继续后置，不擅自合并或清理历史。

## 本机实跑记录

环境：Xcode27.2 / 27B52，本机macOS，iOS27.0隔离模拟器`83B81BAE-2074-4763-8D51-4F9E2C130389`。测试仅用原创合成/隔离库，无真实CloudKit调用。

通用命令：`xcodebuild test -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -destination 'platform=iOS Simulator,id=83B81BAE-2074-4763-8D51-4F9E2C130389' -derivedDataPath /private/tmp/PGOS-ICloud-Reliability-DD -resultBundlePath <下面路径> <测试选择> CODE_SIGNING_ALLOWED=NO`，stdout/stderr保存同名`.log`。

| 轮次/结果包（/private/tmp） | 范围与实际结果 |
| --- | --- |
| PGOS-ICloud-R1-Red.xcresult | 原缺原图用例补无关新增；1FAIL，`unresolvedConflict`，exit65；失败在修复前实证 |
| PGOS-ICloud-R1-Green.xcresult | 集成+持久化23/23PASS，exit0；后续关闭/重启断言另补 |
| PGOS-ICloud-R234-Compile.xcresult | 新factory默认表达式actor隔离编译失败，exit65；修为在主actor初始化factory，未放宽检查 |
| PGOS-ICloud-R234-Compile2.xcresult | coordinator/transport/集成48/48PASS，exit0 |
| PGOS-ICloud-R234-Behavior.xcresult | 70执行=68PASS/2FAIL，exit65；同一retry-after用例Int返回值桥接失败，已修为兼容NSNumber；原失败保留 |
| PGOS-ICloud-R5-Compile.xcresult | coordinator/集成25/25PASS，exit0，包含retry-after修复与实际冷启补原图 |
| PGOS-ICloud-Reliability-Focused1.xcresult | 同步核心/事务/资产/领域codec与installer100/100PASS，exit0；缺父自动续传、诊断首因/隐私/部分ACK已覆盖 |
| PGOS-ICloud-Reliability-UnitUI1.xcresult | 完整Unit709执行=708PASS/0FAIL/1SKIP + 中英同步/暂停导航UI3/3PASS，exit0；runtimeWarnings为空。此后仅对应路径收紧由Focused2覆盖 |
| PGOS-ICloud-Reliability-Focused2.xcresult | 最终定向104/104PASS，exit0，runtimeWarnings为空；增加独立本地提交/独立busy推送、冷启账户网络重试及关闭取消计时器；源码hash清单与结果摘要见Evidence/iCloudReliability20261109 |
| PGOS-ICloud-Reliability-CompletionWake.xcresult | coordinator/集成32/32PASS，busy推送排队期间不推进lastSuccess |
| PGOS-ICloud-Reliability-ProtectivePause.xcresult | coordinator/集成33/33PASS；增加不可重试应用错误刷新/重开仍保护性暂停 |

额外系统SDK通知字典解析：`met`→CKDatabaseNotification、`fet`→CKRecordZoneNotification；wire dbs1/2/3分别解析为private/public/shared。首个原创探查错误ce4触发SDK异常，随后使用有效ce2独立核对三种scope，未访问CloudKit。生产代码始终使用SDK对象的scope，不依赖wire数字。


唯一Unit跳过为缺少隔离32MB HFS+镜像的低空间测试。日志中合成坏库/非法升级错误是负例输出，不列为测试失败；既有编译warning保留，不称零编译警告。

## 尚未完成的交付门

最终受影响构建、完整Unit/UI结果核验、独立复核、必要CI、普通提交/推送、原PR更新与精确非skip源码TestFlight标签待完成。真实后台时延/设备耗时、原图全量一致与双设备冲突未验；不以合成或CI代替。完成后集中给Owner一次新包覆盖安装验收清单，不要求删除重装。


## 本地候选与远端审批状态

普通非skip候选`09493137b29e8e8967ccd5f76972a300578fbbb8`已提交但未推送。其干净来源的Release普通unsigned build成功，三Bundle待核对；随后补的完成/持久暂停保护另有33/33定向通过。新修复将继续普通提交，不改已提交历史。原Release日志`/private/tmp/PGOS-ICloud-Reliability-Release-0949313.log`，不是签名或TestFlight可用证明。

对原`git@github.com:yoCruzer/PersonalGrowthOS.git` / `codex/icloud-product`普通push被自动审批拒绝两次。已只读核实remote与原Draft PR19完全匹配，使用本轮明确指令重新提交同一动作仍被拒；理由为未识别到可信用户内容明确授权此精确私有目的地与push。没有改用其他通道。已集中请求精确目的地/原PR/TestFlight标签确认；独立只读审查子代理也按当前执行限制请求明确授权，均待回复。该输入不阻止本机验证，但远端CI尚无本次run，标签未创建；不得把旧CI用于本次修复。


## 最终本机节点（远端交付仍未完成）

最终非skip修复源码`04b516f534e644fcf4080776fb3177da01b3f24f`干净状态复验：完整Unit714执行=713PASS/0FAIL/1SKIP（低空间隔离镜像缺失），runtimeWarnings为空；Release普通unsigned build成功。三个Bundle均1.0(12)，BuildProvenance精确04b516f/Dirty=false，主Appproduction runtime pin与新中文诊断/双向连接资源逐值核验，三个二进制hash已保留。源码本地Build12不等于未来XcodeCloud/TestFlight构建号。此前UI3/3截图逐张视觉检查正常；后续状态保护未改UI/字符串/相应测试，Git对象一致。详见[本机证据索引](Evidence/iCloudReliability20261109/README.md)。

命令：完整Unit沿上述通用命令仅选择`-only-testing:PersonalGrowthOSTests`，结果`/private/tmp/PGOS-ICloud-Reliability-FinalUnit.xcresult`；Release为`xcodebuild build -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/PGOS-ICloud-Reliability-DD CODE_SIGNING_ALLOWED=NO`，日志`/private/tmp/PGOS-ICloud-Reliability-FinalRelease.log`。两个命令顺序执行且exit0。没有Archive、发行签名、上传或安装。编译warning保留，不称零warning。

远端普通push两次被拒后没有重试或替代通道；原PR远端head仍`ddc5af8`。需要Owner明确回复精确原仓库push/原PR更新/修复后non-skip标签，以及只读独立审查子代理授权。请求均已发出；完整目标保持active，不能声明R1–R5独立复核/必要CI/新包交付全部完成。最终收口文档提交不是发行源码；以后标签必须选通过剩余门的非skip修复源码，不能标文档提交。

新包可用后再集中给一次覆盖安装清单：带图新增/修改后的自动收尾，离线保存/重开/网络恢复后的自动收尾，抽查旧内容与原图；无需再次删除App。忙碌、缺件与冷启时序由以上自动测试承担。K1–K3、真实双设备/后台传播、完整内容/关系/原图对照继续保留。


## 授权后固定发布顺序（未执行）

再次只读核实原PR19仍OPEN/Draft、base为`codex/icloud-sync-foundation`，远端head仍`ddc5af8b91fcf9d3cde7434bb7bda074d859ad4a`，本次新CI不存在。本地修复源码`04b516f534e644fcf4080776fb3177da01b3f24f`是远端head的后代；其后的本地差异只有Docs，且最新文档提交带`[skip ci]`。因此不能直接把最新文档HEAD作为第一次推送的验证候选。

1. 收到明确授权并完成只读独立复核后，再核对remote及PR head；若远端变化，先检查新差异，绝不force。
2. 若源码没有再改，首先普通快进推送**非skip源码**到原分支：`git push origin 04b516f534e644fcf4080776fb3177da01b3f24f:refs/heads/codex/icloud-product`。这是原分支快进，不建立替代分支。若独立审查要求修复，则先完成修复/相关本机门，使用新的非skip源码，而非沿用04b516f。
3. 等待并核验本次实际CI run、head SHA、实际checkout与产物/计数；旧绿灯和本机结果不能替代。不要在验证期间先推`[skip ci]`文档让候选变化。
4. 验证通过后再普通快进推送文档收口、更新原Draft PR19；沿既有TestFlight机制新建不可移动的`testflight-*`标签，只指向已经独立复核和CI通过的**非skip修复源码**。本地文档HEAD不得作为发行tag目标。
5. 追踪真实标签/构建结果，并给Owner一次新包验收清单；标签触发或unsigned构建本身不证明TestFlight可用或设备验收。

本节仅修正后续操作顺序，没有执行push/PR写入/tag/CI触发，也没有借替代通道绕过两次审批拒绝。当前缺少精确远端写入授权和只读独立子代理授权，目标继续active；上一目标轮为实际实现/验证/提交的progress，本次续接完成远端/源码边界复核与发布顺序纠正，不重跑无变化的测试。


## 连续阻塞审计：待明确回复

原始执行轮及随后两次自动续接均因同一明确授权条件未满足而无法完成远端/独立门。第三轮只读复核：工作树干净，产品源码保持04b516f，原PR19仍OPEN Draft/head ddc5af8、statusCheckRollup为空。本机证据不变，不重跑测试，不再新增外围工作。达到三轮阈值，目标标记blocked而非complete/paused。

恢复所需：明确允许原`git@github.com:yoCruzer/PersonalGrowthOS.git` / `codex/icloud-product`普通快进、原PR19更新及通过独立/CI门后的non-skip源码TestFlight标签；明确允许只读独立审查子代理。两项请求已经发出，不新增第三项许可。本次没有推送、改PR、创建标签、启动CI或子代理；没有绕过原两次自动审批拒绝。收到明确回复后重新读取实际head，按上一节顺序继续，保留原目标全部范围。


## 明确授权后的恢复与独立发现（进行中）

Owner明确回复“明确授权”，上述两个授权请求均已满足；旧blocked记录保留为历史。只读复核原PR19仍ddc5af8/OPEN Draft，未改变base。已启动独立只读审查。

独立审查发现：failedRecordSaves只保留第一个暂时错误时，后续较长retry-after丢失；handleFailure跨回调也有相同首错选择。修复将调度错误归并与诊断首因分开：永久错误优先，否则保留最大服务等待。补三种顺序、600秒/高attempt、永久错误前后混合及诊断首因用例，正在运行实际三个同步测试类。新候选将替代04b516f作为首次推送和标签候选，尚未发布。

独立复核最终结论：一项P2已关闭，无其他must-fix，详见[审查记录](Evidence/iCloudReliability20261109/independent-review.md)。三个同步类61/61PASS；随后outer catch最终修改后transport类28/28PASS，runtimeWarnings均为空。命令沿通用xcodebuild分别only-testing三类及transport类，原件`PGOS-ICloud-Reliability-ReviewRetry[Final].xcresult`/`.log`；聚合测试为生产策略接缝测试，未称SDK回调E2E。最终源码将普通非skip提交，完整Unit和Smoke由新CI执行；无新证据前不重复本机完整套件。
