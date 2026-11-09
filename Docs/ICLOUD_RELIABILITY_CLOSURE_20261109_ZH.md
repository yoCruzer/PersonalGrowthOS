# iCloud定向可靠性收尾（2026-11-09，进行中）

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
