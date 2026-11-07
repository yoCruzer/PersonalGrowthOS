# 独立手动计划入口审查

2026-11-07；独立审查代理 g1_independent_review。复核对象为 `/private/tmp/PersonalGrowthOS-icloud-g1/Experiments/iCloudSyncG1` 尚未部署的 Debug 手动计划候选。最后核对工作树的 10 个目标文件与 `final-source-sha256.json` 完全一致。原代码未被审查者修改；所有测试、源码副本与报告在 `/private/tmp/g1-manual-review`。

**结论：已报告的五项必须修复问题均已关闭；最终限定快照未发现剩余 must-fix。仅通过离线入口/证据/并发门禁，不代表真实 iPhone 或双端 CloudKit 验收。**

## 原始反例与修复关闭

| 问题 | 原始可验证反例 | 最终关闭证据 |
|---|---|---|
| 共享 Documents 被当作权威 journal | 导入公开身份/摘要匹配的伪造 completed report，runManualPlan 无任何命令执行即返回完成 | 逐命令及计划权威记录位于 base/Application Support；共享伪结果和旧目录 symlink 被忽略；新执行进入受控执行器，结果为真实执行器的失败而非伪 PASS；UI直接使用 execution.report |
| 跨计划复用旧快照破坏顺序 | 第二计划在新 save 后复用旧 snapshot ID，报告仍验证完成 | 私有逐命令 journal 按 plan.id 分区，ProbeResult.planID 与上下文及整计划匹配；第二计划独立 claim，旧结果拒绝 |
| 共享输出目录 symlink 重定向写入 | Documents/SyncLab-Manual-Results symlink 使 request 写到外部合成目录 | 手动出口为固定平坦文件名，旧嵌套目录不再使用；已有目标必须是 regular file 且与私有原件逐字节相同；symlink/FIFO/directory 及异字节拒绝 |
| 已取消任务仍进入执行器 | 预取消 Task 到达 connect 入口 1 次 | 开始前和每条命令前检查取消；预取消零入口/不创建文稿；中途取消保留首个结果、CANCELLED 报告，第二命令连 claim 都未发生 |
| 同一实例重入释放首个活跃锁 | 第一个计划停在异步入口时，第二调用被 claim 拒绝但 cleanup 释放首锁，第三个进程锁可成功获取 | 实例 manualPlanRunning 在任何 await 前拒绝重入；第二调用不清理首任务；暂停期间第三方 ProbeProcessLock 仍被拒绝；收尾后释放 |

原始完整日志：`red-tests-02.log`（3 tests，4 个失败断言）、`red-control-flow.log`（2 tests，2 个失败断言）。这些红例原样保留；`red-tests.log` 是首轮 sandbox 模块缓存写入受限，未运行测试，不能计作产品失败。

## 最终独立验证

环境：macOS 27.0.1，arm64；Apple Swift 6.4.2。全部是本机合成目录测试，未访问云、设备、账户、实际 App Documents 或私有签名日志。

- **原样实现，11/11 PASS**：`green-tests.log`。包含 3 个独立测试和候选中的 8 个 ManualProbeTests。验证 1–16 指令界限、身份/白名单/体积约束、不可覆盖 journal、未完成计划阻断、跨计划结果拒绝、失败必须终止结果序列、regular-file 导入、FIFO/symlink/目录拒绝、导出相同字节重试及异字节拒绝、局部授权不改变环境、默认关闭及预取消不触及存储。
- **明确带测试接缝的控制流，4/4 PASS**：`green-control-flow-final.log`。在复制候选的 connect 顶部加计数/暂停并立即抛 blocked，确保无法访问 CloudKit；中途取消用标记为 TEST_ONLY_INJECTED 的合成 perform 返回值。原授权、计划循环、claim、发布、清理、取消与互斥逻辑不改。验证共享伪完成不被接受、私有原件重读标 reusedOriginal、导出篡改不重执行、预取消、同实例重入锁保留、执行中途取消。此组只证明控制流与证据保存，绝非真实云或实际执行器成功路径。
- **真正 Release 编译，1/1 PASS**：`release-test.log`。未修改实现；即使环境 SYNCLAB_ENABLE_DEVELOPMENT=YES，DevelopmentAuthorization 仍 false，CloudDriver.start 在任何 CloudKit 路径前 blocked，无事件。
- **工程生成/文件共享边界 PASS**：`project-check.log` 与 `verify_project.py`。在新临时目录实际运行生成器，pbxproj 逐字节匹配候选。Debug 使用 InfoDebug 并启用文件共享；Release 使用普通 Info.plist，无 sharing、无 DEBUG 编译条件；新 Swift 文件包含在工程中。

命令：

```
swift test --package-path /private/tmp/g1-manual-review/green-candidate --scratch-path /private/tmp/g1-manual-review/green-build
swift test --package-path /private/tmp/g1-manual-review/green-control-flow --scratch-path /private/tmp/g1-manual-review/green-control-build
swift test -c release --package-path /private/tmp/g1-manual-review/release-candidate --scratch-path /private/tmp/g1-manual-review/release-build
python3 /private/tmp/g1-manual-review/verify_project.py
```

## 最终源码审查要点

- ManualProbePlan 整批 decode/validate 在执行前完成，固定导入文件、最大 262144 字节、最多 16 条既有白名单指令；O_NOFOLLOW/O_NONBLOCK + fstat regular file 消除最终文件 symlink 竞态与 FIFO 阻塞。
- DevelopmentAuthorization 非 Codable，手动授权只由明确按钮构造并局部传入；不写环境、defaults 或文档。Release 编译时始终 false，手动计划与按钮位于 DEBUG 条件内。
- 整计划原始 bytes 与 plan digest 不可替换；逐命令 canonical digest、planID、run、dataset、id 绑定；异常、中断与未完成 claim 不自动重放。完整报告只表示指令序列完成，不表示云收敛。
- 权威 journal 私有，Documents 仅输出副本；普通 bridge/runOnce 也改用私有 journal，拒绝静默提升旧共享 request 为可信历史。实际继续验证应按迁移约定使用新的 run 身份并保留旧数据。
- UI 用可信 execution.report 显示状态，ShareLink 只拿导出 URL；缓存报告明确提示“此前原始结果，未重新执行”。按钮 guard、实例重入 guard、dataset 进程锁与 await shutdown 分层保护；手动入口拒绝环境授权模式及已有普通 driver，防止两套入口并行。

## NOT_RUN 与结论边界

未执行新包签名/安装、Apple Configurator 真正导入导出、手机点击按钮、真实 CloudKit、两端一致性、App 进程崩溃或设备重启恢复。父任务报告的签名构建及已有手机安装未被算作本审查的独立验证。本报告也不改变此前真实 Mac 13 条指令证据的适用版本与范围。

Documents 仍是可修改的传输副本；它不会被 App 重新当作权威历史，但外部审阅取回的文件仍必须核对计划身份、原始摘要、账户一致性与预期 mutation/图片原字节，不能只看 completedAllCommands 或 PASS。未完成的私有 claim 会明确阻断；不得把阻断解释成未发生过云写入。

`final-source/` 保存最终准确源码；`initial-source/` 与 `red-candidate/` 保存原始问题版本；`final-source-sha256.json` 绑定最终 10 个目标文件。带接缝的副本与测试均独立保存在 green-control-flow，其源差异可直接与 green-candidate 比较。所有原始红/绿日志均保留。
