# iCloud Sync V1：审计用实验（Review修订）

仅合成数据，不属于App target，不是生产同步实现；无账号读取或真实库/云上传操作。

从仓库根运行：

```sh
python3 Docs/PoC/iCloudSyncV1/protocol_probe.py
python3 Docs/PoC/iCloudSyncV1/reviewer_regressions.py
python3 Docs/PoC/iCloudSyncV1/review_projection_tests.py
```

三个脚本分别16、4、14项，共34项。`protocol_rules.py`新增当前head依赖检查及确定性投影；共同祖先仅作不完整预览，不能直接用于生产统计。保守拒绝依赖环不是所有业务聚合的通用算法。

`reviewer_regressions.py`保留原四个失败期望，原e036b01上应失败，修订后应通过。初次失败与修订日志分别保留；不要修改旧Evidence日志冒充新结果。

原生实验仍可在Mac隔离执行：

```sh
python3 Docs/PoC/iCloudSyncV1/inventory.py /tmp/pgos-sync-inventory-new
python3 Docs/PoC/iCloudSyncV1/run_native.py /tmp/pgos-sync-native-new
python3 Docs/PoC/iCloudSyncV1/verify_evidence.py
```

新输出目录不可覆盖旧证据。`verify_evidence.py`核对的是初次固定原生记录及其16项协议日志，不是当前34项回归的执行器。宏插件需Xcode允许；原CloudKit负例134060后未打包CLI exit -6仅保留为负例，不是成功云连接。

`native.swift`仍仅测试本地存储/编码，未初始化真实CKSyncEngine。协议中的整数cursor是模拟；固定epoch拒绝不是账户重绑定；旧mutation重放不是ZIP恢复；候选保留不是统计不双计。没有真实CAS/changeTag、生产领域reducer、容量、GC或Production证明。

当前规范：[修订审计](../../ICLOUD_SYNC_V1_AUDIT_ZH.md)、[补正记录](../../ICLOUD_SYNC_V1_REVIEW_FIX_ZH.md)、[G1 Goal](../../ICLOUD_SYNC_V1_G1_GOAL_ZH.md)、[Apple门禁](../../ICLOUD_SYNC_V1_APPLE_READINESS_ZH.md)。
