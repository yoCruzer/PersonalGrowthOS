# iCloud Sync V1：审计用最小实验

这些脚本不属于 App target，不是待上线同步实现。仅标准库、系统 SwiftData/CloudKit SDK；无第三方依赖，无账号读取、真实库路径或云上传代码。

从仓库根目录运行：

```sh
python3 Docs/PoC/iCloudSyncV1/inventory.py /tmp/pgos-sync-inventory-new
python3 Docs/PoC/iCloudSyncV1/run_native.py /tmp/pgos-sync-native-new
python3 Docs/PoC/iCloudSyncV1/protocol_probe.py
python3 Docs/PoC/iCloudSyncV1/verify_evidence.py
```

每次原生复现使用新的输出目录；脚本另建唯一临时目录存放可执行文件和合成 SQLite，不打开应用目录。需要允许 Xcode Swift macro plugin 子进程，限制型嵌套沙箱可能使编译失败。证据校验器按本轮已保存的实际 macOS 结果校验；未来 SDK 的 CLI 异常变化应记录为新结果，不能覆盖本轮日志。

- `inventory.py`：针对当前源码的受限声明提取器，递归展开 V16，排除 V11Original 的历史 TodoSeries；保存每个存储字段、原文件位置和生产 Swift 源码 hash。不是通用 Swift parser。
- `run_native.py`：依据清单生成全部 39 个模型的存储字段/属性/关系，构造器仅赋合成值；因此验证的是存储形状，不是完整产品类、历史 checksum 或 iOS runtime。`generated-models.swift` 是实际输入，便于检查。CloudKit 负例用虚构 container ID；native preflight 拒绝后当前 macOS 未打包 CLI teardown 还会因 bundleIdentifier 缺失 abort，保留 exit -6 和诊断；这不是正常云端返回，更不是云端成功。
- `native.swift`：原生本地开库、去 unique 的重复身份反例、事实/outbox 同事务、rollback、未保存进程退出、独立进程重开、旧 ACK、新 CKRecord system fields 编码和 CKAsset 本地文件。没有初始化真实 CKSyncEngine，更没有测试后台传输。`_exit(73)` 是有意退出，不是硬件掉电。
- `protocol_probe.py`：16 个协议实验，用独立 SQLite 和因果 DAG 展示乱序/重复、并发分支、删除/恢复、自然键、依赖暂存、未知版本、账户 epoch、ACK、校验和/缺图备份。期望值是手写固定真值，6 个并发顺序逐个验证。没有完整领域 reducer、真实 CAS/changeTag、跨 zone 事务、容量/性能或 GC，不能直接搬入产品。
- `verify_evidence.py`：将 native 报错的字段/unique 集合逐项与清单比较，并核对生产源 hash、非 Docs Git 树及原始退出码。

完整设计、未验证项和下一阶段门禁见 [中文审计报告](../../ICLOUD_SYNC_V1_AUDIT_ZH.md)。
