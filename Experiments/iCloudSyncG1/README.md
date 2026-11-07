# SyncLab G1（独立实验）

状态：**BLOCKED_ENV**。2026-11-07 Owner解锁后已恢复门户核验，iOS签名实包校验通过；Mac设备登记与两端账户/连接条件待确认，真实Development双客户端尚未执行。工程不引用正式产品源码、App Group、数据库或用户图片。SwiftData `.none`，仅 `G1ObjectV1` / `G1ImageV1` 两个实验 wire types。它不是39实体同步实现。

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
