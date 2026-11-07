# SyncFoundation 独立审查

日期：2026-11-07。审查者：独立子代理 `/root/readiness`（非包实现者）。范围：`Packages/SyncFoundation` 的本机原生codec、schema CLI、identity/fence；另检查合成V16夹具生成器的冻结边界。审查未访问云端、私人数据库、设备账户或Apple凭证。

## 结论

包在当前**离线候选、未接产品**范围没有剩余must-fix。独立新编写8项native测试最终8/8 PASS；schema CLI 5组调用与独立字段/hash oracle通过。实际源文件摘要见 `source-sha256.json`，测试前后的快照源与工作树逐字节一致。

发现并处理：

- API旧名 `verifyComplete` 易误导接入方把资产闭合当业务可发布；实现者改为 `verifyAssetsComplete` 并明确只校验资产，因果/领域/自然键/当前依赖仍需接入层验证。
- `CreateSyncV16BaselineFixture.swift` 初稿直接打开frozen SQLite，可能改写WAL/SHM/metadata。已向主代理报告，要求独立副本重开并前后核对冻结目录全文件hash；该项由主代理修复/重跑，**此包测试不作为夹具修复通过证据**。

## 独立测试及实际结果

环境：本机Apple silicon；Xcode27.2/27B52，macOS27.0.1；Swift package最低macOS14/iOS17。隔离快照与合成输出：`/private/tmp/PGOS-SyncReview.gHBAkm`。各次命令同为：

```sh
swift test --package-path /private/tmp/PGOS-SyncReview.gHBAkm/Candidate --scratch-path /private/tmp/PGOS-SyncReview.gHBAkm/build --filter IndependentBoundaryTests
```

| 轮次 | 实际结果 | 说明 |
| --- | --- | --- |
| independent-01 | exit1，0 tests | 沙箱不能写编译器模块缓存；不是代码失败 |
| independent-02 | exit1，0 tests | 正常缓存权限后编译；独立测试缺两处try，未开始执行 |
| independent-03 | exit1，7 PASS / 1 FAIL | 负例向CKRecord赋UInt64.max时SDK抛NSInvalidArgumentException，未进入codec；保留原日志，不改为PASS |
| independent-04 | exit0，8 PASS / 0 FAIL | 改为SDK可表示的Int64.max、负数及integral Double边界；独立codec正负测试通过 |

独立断言覆盖：Python `hashlib`/UTF8计算的固定28字节/hash oracle；同dataset+mutation但typed object不同拒绝；父列表顺序规范化但payload原字节不变；相同dataset/name而zone owner不同拒绝；稀疏超限文件实际长度优先于伪造描述符；FIFO不会挂起且非file URL拒绝；数字版本Int64最大值/负数/Double拒绝；嵌套未知字段与boolean版本拒绝；逐container/environment/account/dataset/generation及新实例nonce栅栏拒绝，原实例正例与invalidate负例配对。

`IndependentBoundaryTests.swift`为最终源码。`independent-initial.swift`和`independent-03.swift`保留独立测试准备过程；最初人工字节计数37也在首次执行前由独立Python计算纠正为28，最终hash不是调用被测实现得到。日志公开副本仅将本机用户路径替为`<LOCAL_USER>`；原始日志仍在上述私有临时根，未覆盖原失败。

## CLI独立检查

使用独立构建的 `/private/tmp/PGOS-SyncReview.gHBAkm/build/out/Products/Debug/SyncSchema`：新目录a/b均exit0；既有目录、无参数、额外参数均exit1。两次schema逐字节一致；重复调用未改变a（与独立b对照）。Python独立比对两record types的完整字段集合/类型、`networkOperations=0`、`serverSchemaChecked=false`及SHA256。

结果：`schema-review.json`，实际输出 `schema.json`；SHA256 `a22407cceb196508c4b199a3f0cc4759d542dc02ee9945e25020a14e4c2f0083`。这只是本地期望schema，不是服务器schema导出/P0冻结。

## 必须保留的边界

- `SyncBinding`是非Codable局部路由值，fence是内存nonce；不是持久分区、冷启动身份恢复或真正取消SDK操作的实现。
- `readAsset`通过同一regular-file descriptor有界读取、拒绝叶子symlink/FIFO；未声称父路径symlink不可达。CKAsset最终仍引用URL；调用者必须拥有不可变staging lease直至SDK完成。codec不能阻止外部在验证后改写/替换文件；真实上传TOCTOU、lease/GC、进程恢复仍为接入门禁。
- opaque payload不代表合法领域事实；当前manifest不解决跨对象因果/合法业务环/自然键冲突/统计。16MiB候选payload上限必须再用真实领域最大合法编码验证。
- 没有SDK云操作、正式Development/Production、真实账户切换、persisted outbox/inbox/ACK、V16迁移、备份恢复或39实体接入验证；P0–P4不得标PASS。
