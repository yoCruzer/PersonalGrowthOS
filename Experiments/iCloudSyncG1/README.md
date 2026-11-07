# SyncLab G1（独立实验）

状态：**G1部分真实服务已验证，双端验收未完成**。Mac13组实际Development命令通过，手机已通过Owner授权的Apple Configurator安装既有SyncLab，但DDI仍失败；新增Debug手动文稿入口已完成工程门禁，待手机实际执行。正式产品、App Group和私人库未接入。

## 离线复现

```sh
python3 Docs/PoC/iCloudSyncV1/protocol_probe.py
python3 Docs/PoC/iCloudSyncV1/reviewer_regressions.py
python3 Docs/PoC/iCloudSyncV1/review_projection_tests.py
swift test --package-path Experiments/iCloudSyncG1 --scratch-path /tmp/pgos-g1-swift-build
xcodebuild -project Experiments/iCloudSyncG1/SyncLab.xcodeproj -scheme SyncLab -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/pgos-g1-ios-build CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Experiments/iCloudSyncG1/SyncLab.xcodeproj -scheme SyncLab -configuration Debug -sdk macosx -destination 'platform=macOS' -derivedDataPath /tmp/pgos-g1-mac-build CODE_SIGNING_ALLOWED=NO build
```

`Tools/generate_project.py` 可确定性重建本实验的 Xcode 工程/plist/entitlements，不需要第三方依赖。默认运行只打开合成离线分区，不初始化 CKContainer/CKSyncEngine，不自动访问云。按钮保存一条 Entry-like 文字与内置可解码的 1×1 PNG，不申请照片权限。App 可显式解决冲突、保存删除意图、本地重开与导出合成快照。普通保存遇多候选会要求显式解决。

独立进程重放（ROOT 必须是新建临时目录；不得使用产品目录）：

```sh
ROOT=$(mktemp -d /tmp/SyncLab-Replay.XXXXXX)
/tmp/pgos-g1-swift-build/debug/LabReplay seed-crash "$ROOT" # 预期退出73
/tmp/pgos-g1-swift-build/debug/LabReplay verify-crash "$ROOT"
/tmp/pgos-g1-swift-build/debug/LabReplay receive-exit "$ROOT" # 预期退出74
/tmp/pgos-g1-swift-build/debug/LabReplay verify-receive "$ROOT"
SCHEMA_ROOT=$(mktemp -d /tmp/SyncLab-Schema.XXXXXX)
/tmp/pgos-g1-swift-build/debug/LabReplay schema "$SCHEMA_ROOT"
```

CLI 的 PRE-FETCH-CHECKPOINT 是本地退出顺序占位字节，不是真实 CKSyncEngine state；CloudDriver 使用 SDK `State.Serialization` 的 Codable 数据。上述退出实验只证明 SwiftData 持久边界，不证明 SDK 真实 token 重放。

## 真实 Development 恢复执行入口

**仅在下列签名与账户门禁满足后执行云步骤。** 先完成[环境台账](../../Docs/ICLOUD_SYNC_G1_ENVIRONMENT_ZH.md)的一次性最小准备，使用已注册 SyncLab 身份与同一测试账户的两客户端。不得退出日常主账号。真实 iOS+Mac 组合须注明平台，不能写成两台 iOS。

1. 在 Xcode 打开独立 `SyncLab.xcodeproj`，核验 Team `83SKX2PM7B`、独立 App ID 与容器；由 Owner 提供/刷新对应 Development profile。工程的 entitlement 不是门户关联证据。
2. Debug 签名构建后执行 `python3 Experiments/iCloudSyncG1/Tools/verify_signing.py /实际/SyncLab.app`。记录最终源码SHA、dirty、OS、profile到期及脱敏结果。脚本检查签名/profile字段匹配；PASS仍不代表设备包含在profile、账户资格或服务可用。没有匹配profile则停止，不使用ad-hoc签名冒充。
3. 仅验证通过的 Development 构建，在 Xcode Run scheme 的环境变量中显式设置 `SYNCLAB_ENABLE_DEVELOPMENT=YES`。默认scheme不设置它；Release 的driver拒绝start。禁止把此变量用于未经核验或Production签名的构建。
4. 两端启动前在Xcode Run环境变量设置同一个全新`SYNCLAB_DATASET`（只用字母、数字、下划线或连字符，最多80字节），再启动；默认离线dataset为`synthetic-g1-001`，运行中不能编辑。“打开当前测试账户分区”只读取账户身份的哈希并打开专属分区；不把离线未绑定分区的内容自动上传。原分区保留，可重新打开和导出。
5. A保存文字+PNG→手动发送/获取→B手动发送/获取，导出两端快照逐object/mutation/原始字节hash比较。B编辑→A、删除、重开、真实断网恢复都分别留证；不能只看待发送数为0。
6. 并发编辑应真实诱发 `serverRecordChanged`，验证候选/基线及显式解决。暂停上传再编辑的旧ACK场景需调试器/受控延迟，随后证明另一端收到新内容；本地ACK测试不能替代它。
7. 在独立测试系统账户/设备完成A→退出→B→A及冷启动。切换由Owner执行。确认A未上传输入可导出、不进入B，晚回调受epoch拒绝，重建zone+record队列。后台/推送尚未实现验证，本实验只手动sync。
8. 逐项执行G1 Goal八项真实矩阵。token过期、zone删除、后台唤醒及真实quota无法稳定诱发时分列NOT_RUN或注入，不猜测通过。

## 持久化及边界

- 每个object保留不可变mutation历史，父版本/依赖构成保守因果图；云上同object envelope通过CAS冲突合并完整集合。不同同ID字节拒绝并保留入站记录。512条/对象、256KiB envelope、32KiB文字、8MiB原图是实验上限，超限显式失败，不丢弃历史；这不是生产容量方案。
- envelope事实与pending字段同一SwiftData save。SDK检查点独立持久化；delegate串行、处理content无await后才保存state，失败则fence。原始CKRecord及asset在codec前留存。恢复后的重复接收幂等。
- 精确payload ACK不能清掉更新payload；sent事件及didSend之后重排持久pending。CKAsset指向实验目录的校验原件；保留引用、冲突、outbox和入站副本，无GC，因此上传lease生命周期覆盖整个实验。截断旧件先quarantine保全，再原子安装正确件。
- 身份绑定container/Development/accountHash/dataset，切换新建driver；旧engine callbacks不能改新分区。网络fence不阻止本地编辑。真实账户切换尚未验证。
- 恢复快照无token/ACK/system fields，落盘`restore-gate`在冷启动仍禁止发云；本地编辑/导出继续。当前没有映射/解锁接口，不能删除gate绕过。上限128对象/4096 mutation/32MB编码包，过限不宣称可恢复的完整备份。这不是产品v12 ZIP验证。
- 只消费当前dataset zone；不物理删除云记录，删除是tombstone。云物理删除/缺失区不静默转逻辑删除，停止网络并保全本地。自动重建/全量修复策略须在真实服务阶段补验。

[执行证据与未测矩阵](../../Docs/ICLOUD_SYNC_G1_EXECUTION_ZH.md) · [wire候选与Production门禁](../../Docs/ICLOUD_SYNC_G1_WIRE_SCHEMA_ZH.md)。

## 专用Mac用户的受限Debug探针（2026-11-07）

Owner已创建haha普通用户并报告登录手机同一iCloud。原控制会话无法直接操作新用户，使用`Tools/probe_bridge.py`在127.0.0.1建立一次性本机通道；`Tools/prepare_probe_package.py`把已通过严格签名检查的App复制到临时启动包。Owner在haha启动一次并保持登录即可，工具不会登录或退出系统账户，不包含私钥。

桥固定dataset/runID，使用随机token；token文件mode600且仅指定测试用户有读取ACL，启动时只通过环境传递。App拒绝非loopback URL和重定向；只接受connect/save/sync/snapshot/reopen/stop，不接受容器、账户、路径或Shell参数。save只准probe-标识、SYNTHETIC文字及内置PNG。App数据库仍在各自沙箱中，正式库和App Group不参与。

`SYNCLAB_PROBE_RUN` + `SYNCLAB_ENABLE_DEVELOPMENT=YES`必须显式设置，Release不编入探针。Mac另需`SYNCLAB_PROBE_BRIDGE`/`SYNCLAB_PROBE_TOKEN`；iPhone用`SYNCLAB_PROBE_COMMAND`传递base64 JSON单次指令。每个客户端对dataset持有flock，重复实例拒绝；journal按run/dataset隔离、先保存原始指令再执行，结果硬链接发布不可覆盖。已记录请求但无结果视为中断，不能同ID静默重放。

新版本权威journal位于非共享Application Support；单命令导出副本位于本App Documents/SyncLab-<runID>-<commandID>.json，Mac桥另接收同一结果。旧Documents内request不会自动晋升可信或重放，使用新runID继续。其中账户指纹仅用于私下比较，同步快照只有实验数据；公开证据必须去除账户指纹，保留run/dataset/指令摘要及逐mutation/图片字节判定。**status=PASS只代表命令完成，仍须检查pending/events并独立比对双端内容，不是G1/云验收PASS。**启动桥不会自行发送命令。

当前真实CloudKit八项仍待执行；工具没有把本地故障注入冒充真实SDK/server行为。实际账户切换、真实离线/锁屏等场景仍单列，需相应Owner操作和证据。

## 无开发镜像时的手动文稿入口

仅Debug使用InfoDebug.plist开放实验App文件共享，Release无入口、无共享、CloudDriver始终拒绝启动。已验签Debug IPA可以通过官方Configurator添加；只操作SyncLab，不准备、监督、恢复或抹除设备。

使用cfgutil的指定设备参数和install-doc com.yocruzer.PersonalGrowthOS.SyncLab <文件>导入固定文件名SyncLab-Probe-Plan.json（不使用sync删除选项）。文件包含version=1、probe-前缀id/runID、synthetic-g1-前缀dataset和1–16条既有ProbeCommand；最大256KiB，整批验证后才可能执行。文件本身不授权云访问。Owner在手机点“启动导入的合成Development测试”；仅局部Debug授权，不写环境或持久设置，普通环境授权模式不能同时进入手动模式。

整计划与逐指令权威journal位于私有base，先claim再执行、原件不可覆盖；计划内命令按planID隔离并写入结果上下文。未完成claim显式阻断，取消停止后续指令，实例重入与dataset flock保护并发。完整报告只表示命令执行，仍须逐ID、原图、pending、events和账户核验；App状态只使用私有原件派生的report。

完成后用Configurator“操作→导出→文稿”选择SyncLab导出，或使用App内“导出测试结果”。平坦副本名SyncLab-Manual-<planID>.json。副本不是权威历史，App不会把导入的伪结果当缓存；已有副本须与私有结果字节相同，否则拒绝覆盖。第一次手机计划只connect，实际两端指纹匹配后再进行save/sync。所有原件私留，公开证据移除账户指纹。


## 批次准备：异常依赖与手机新图片（仅Debug，真实运行尚待安排）

`swift run --package-path Experiments/iCloudSyncG1 LabReplay prepare-batch NEW_OUTPUT_DIRECTORY synthetic-g1-UNUSED_DATASET probe-NEW_RUN` 仅在本机生成固定计划，不启动App、不授权云访问、不连接设备。输出目录必须全新；已有目录/符号链接拒绝，不覆盖旧证据。Release不包含此模式或批次实现。

按顺序执行，不能并发跑三个阶段：

计划ID为`probe-阶段编号-完整SHA256(dataset|run|stage)`，使新一轮导出不会撞上旧结果；以下阶段名对应命令ID，导出目录使用生成的计划ID。

1. `01-mac-seed`：Mac一次启动桥后由控制端依次执行16条命令。先确认connect初始快照/队列为空。保存删除依赖、缺祖先、传递缺失、依赖环、因果环，以及旧head原本ready而新head因缺依赖变staged的事实；同步后导出证据。
2. `02-ios-repair`：仅在Mac前阶段结果核验后导入手机，Owner只需点击一次，连续执行10条命令。先fetch+snapshot，核验未修复状态与Mac一致；之后补齐祖先/传递依赖/当前head依赖，并保存第二个固定PNG，最后同步、取快照。
3. `03-mac-fetch`：控制端执行4条命令，核验修复后的完整mutation集合/原图字节与手机一致；删除依赖、两类环仍应staged，不误报全部ready。

手机before快照在同一次连续执行中保留，并不是暂停点或自动前置断言；完成后必须核对该快照与Mac种入结果。不匹配时该场景不能验收，不能仅凭completedAllCommands填PASS。

整个批次只使用从未运行过的新合成dataset/zone，执行前保留生成计划和身份记录。不能在旧dataset中重复同样ID并称新实验。新图片必须在seed/手机before快照中不存在，手机save新增`image-<secondPNG hash>`与对象pending，后续实际ACK清空，再由Mac实际下载逐字节核验。空本地快照不能证明远端没有未引用asset；若新zone前提无法证明，停止并标UNVERIFIED，不把复用既有asset算全新上传。

生成器和51项原生测试只证明离线计划/投影/持久队列；不证明CloudKit真实依赖到达时序、新CKAsset上传、物理断网、独立进程崩溃、账户切换或完整G1。不得提前填PASS。剩余故障入口需另补齐后统一安排设备窗口，不要求Owner为本工程准备阶段持续连线。
