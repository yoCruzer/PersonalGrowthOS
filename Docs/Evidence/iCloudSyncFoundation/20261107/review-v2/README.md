# SyncFoundation v2 独立终审

日期：2026-11-07。审查者 `/root/readiness`，独立于包实现者。范围：分块payload协议、manifest/CKRecord codec、SyncSchema/SyncPayloadProbe及有界内存。v1历史8项独立测试保留在相邻`review/`，**不计作v2测试通过**；已闭合的V16/v12冻结夹具本轮没有重跑。

## 结论及关闭问题

最终v2离线候选在当前范围没有剩余must-fix。独立12项native测试全部通过；真实V16合成payload 49,190,297字节、12块的SDK编码/解码、流式完整hash和逐字节重组通过；schema三类型完整字段/hash独立比对通过；两组独立进程内存对照及CLI正负例通过。正式云服务/部署、持久outbox、领域投影及P0–P4仍未验证。

本轮发现并修复两个问题，原失败不覆盖：

1. 初稿`prepare`在emit期间源文件被截短或增长仍可能返回成功。独立原样红例8项中6 PASS / 2 FAIL。最终强制调用者传入编码完成时的expected hash/size；同一个文件描述符前后size/mtime/ctime一致，并验证最终完整hash与长度。截短、增长、同长度改写及准备前被换内容均拒绝。源仍需调用者持有不可变lease；失败部分输出不可发布，由调用者保留源并管理临时输出。
2. 流式API实际受Foundation自动释放对象累积影响。排除审查测试自身oracle读取后，128MiB流式prepare/verify测试进程峰值RSS170,606,592字节，约随payload增长。逐chunk读取/emit/hash、verify及CLI最终读取增加autoreleasepool后，同一128MiB测试RSS40,058,880字节；4MiB对照44,236,800字节。该本机有界样本已不随输入线性保留内存，不宣称任何设备上固定RSS或整个App内存预算通过。

## 原生命令及证据

本机Apple silicon、macOS27.0.1、Xcode27.2(27B52)。独立复制快照：`/private/tmp/PGOS-SyncV2Review.slpcjH/Candidate`，与最终工作树所有package Sources及Package.swift逐字节核对，见`final-source-sha256.json`。旧源快照保留为`red-source/`、`pre-memory-source/`与`pre-memory-source-sha256.json`。

```sh
swift test --package-path /private/tmp/PGOS-SyncV2Review.slpcjH/Candidate --scratch-path /private/tmp/PGOS-SyncV2Review.slpcjH/build --filter IndependentChunkTests
```

| 轮次 | 实际结果 | 证据 |
| --- | --- | --- |
| red-01 | exit1，6 PASS / 2 FAIL | 截短、增长未拒绝；`red-01.log`、`red-tests.swift` |
| green-02 | exit1，0 tests | 复制中间版本已含expected新签名，而独立测试仍旧调用；编译失败，不是新的产品失败或通过 |
| final-03 | exit0，12/12 PASS | 功能通过，但当时尚有独立测得内存问题，不称最终READY |
| final-04-memory-fixed | exit0，12/12 PASS | 源绑定及逐块释放最终版；`IndependentChunkTests.swift`为实际测试源码 |

独立覆盖：顺序/乱序/缺块/重复索引/多块/负索引；相同内容允许重复出现在不同位置；各块hash正确而整体hash错误拒绝；总长0/负值/Int.max/超128MiB、错误边界长度、空块表/33块拒绝；chunk CKRecord跨dataset、bool版本、长度篡改、额外字段拒绝；源文件准备前/期间变化；4MiB与128MiB真正流式准备/验证；最大样本使用Python预先计算固定SHA256（`5a3575e72eb2283ba32069397852008f571119c98e9ce9973ff12e50b0ff7cdb`）。

12为不同测试数；内存定向重复与两轮通过不相加成新的测试数量。

## 内存原始测量

使用已编译xctest，每个样本独立进程，干净环境，仅合成临时文件：

```sh
env -i PATH=/usr/bin:/bin /usr/bin/time -l /Applications/Xcode.app/Contents/Developer/usr/bin/xctest -XCTest 'SyncFoundationTests.IndependentChunkTests/testStreamPreparesMaximumPayloadWithoutAssemblingIt' /private/tmp/PGOS-SyncV2Review.slpcjH/build/out/Products/Debug/SyncFoundationTests.xctest
```

4MiB使用`testStreamingOneChunkMemoryBaseline`。日志、完整命令和RSS见`final-cli-memory-verification.json`及`memory-*-pool-fixed.log`。

保留测量过程：最初普通沙箱测试1/1成功但`time`不能读sysctl，exit1，没有RSS；首次128MiB测量包含审查辅助oracle扫描，RSS304,185,344，不归为纯库开销。改用固定Python oracle后RSS170,606,592才作为修复前库路径对照（`memory-128mib-fixed-oracle.log`）。修复后使用相同固定oracle，RSS40,058,880。没有截断输入或降低128MiB样本大小。

## 实际V16容量及CLI

输入来自精确V16产品源码的NetWorthSnapshotValue合法性检查及JSONEncoder，路径`/private/tmp/pgos-sync-v16-capacity-20261107/actual-v16-payload.json`；大小49,190,297、SHA256 `9e97f46caef1fb89babb217a5cb7e25ee223beec74d6ce71408f211672fb9b13`。大输入和临时chunks不提交仓库。

独立XCTest将文件流式prepare为12块，每块使用真实CKRecord encode/decode并逐字节核对；完整verify后只在测试临时路径拼接，再按4MiB逐段与原文件比较（末尾也必须同时结束）。expected总长/hash固定于独立断言；不是用被测返回值当oracle。

独立执行SyncPayloadProbe：正确expected exit0；错误expected hash exit1；复用已有输出目录exit1。源文件在所有调用前后以Python流式hash核对不变；正例summary/manifest复制到`actual-v16-probe-summary.json`、`actual-v16-manifest.json`，错误输出留临时路径，不发布为成功证据。CLI日志保留，只有实际正例标`OFFLINE_CODEC_PASS`。

SyncSchema两次新目录生成逐字节相同，已有目录exit1且未改原输出。Python独立expected字段严格为：PGMutationV2（wireVersion/manifest/sha256）、PGOriginalV2（wireVersion/sha256/byteCount/original）、PGPayloadChunkV2（wireVersion/sha256/byteCount/chunk）；数据类型、wireVersion2、4MiB/32块/128MiB、no-network/no-server-check标记均核对。schema SHA256 `6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003`，见`schema-v2-review.json`与`schema.json`。

## 剩余边界

128MiB是候选总payload上限，最大实际净资产输入验证只证明本次精确合法样本；其余领域还需各自上限与聚合策略。分块manifest只闭合字节，不批准因果图或业务发布；未知payloadVersion/kind须领域接入明确隔离。原图lease/SDK完成前文件不变、持久outbox/inbox、下载落盘/checkpoint、崩溃/取消/真实账户切换、迁移/备份/39实体统计和正式云均不由本轮离线包证明。全部测试仅在合成输入和隔离临时根运行。
