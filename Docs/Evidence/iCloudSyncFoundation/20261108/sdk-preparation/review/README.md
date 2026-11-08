# Formal Development SDK 准备：独立复核

2026-11-08，独立审查者 `/root/readiness`。在冻结源码副本`/private/tmp/PGOS-SchemaSDKReview.J9Wddi/Candidate`新增独立`IndependentSDKTests`，只注入本机合成transport，不创建CKContainer或CKDatabase、不调用真实服务、不打开业务库。

## 最终结果及归属

最终 **11/11 独立原生测试通过**，见`sdk-independent-02-final-binding.log`、`IndependentSDKTests.swift`及`verification.json`。此前10/10通过保留在`sdk-independent-01.log`；随后实现者在BatchRunner与LockedHost最后写报告后各追加一次路径绑定检查，独立快照更新这两文件并加上host报告检查，完成最终11项，不将10+11叠加。

`package-source-sha256.json`是首次冻结快照；`package-final-source-sha256.json`是两处最终修订后的快照，`pre-final-binding/`保留前版两文件。源码、测试与Package.swift已和工作树逐文件核对一致；README纯文档单独处理。此处11项独立测试不计入实现者51项包测试，亦不挪用旧分块和准备器的通过数量。

```sh
swift test --package-path /private/tmp/PGOS-SchemaSDKReview.J9Wddi/Candidate --scratch-path /private/tmp/PGOS-SchemaSDKReview.J9Wddi/build --filter IndependentSDKTests
```

## 独立验证重点

- 精确6条合成record与固定原始文字的正向回放；已有zone观察后不得写入。
- 使用`CheckedContinuation`令transport在全部5个异步边界真正暂停，再由独立task改变epoch，确认返回后不进入下一网络步骤或成功状态；不是在同一调用栈直接触发hook冒充并发。
- 不同ticket并发进入同一runner被single-flight拒绝；首个票据消耗后不能换输出目录重放。仅本实例/内存保证，不声称跨进程排他或持久授权。
- 真正暂停期间取消task、修改原计划文件或asset lease、移动并替换输出目录，返回后均拒绝；原fd中的失败证据保留，不在替换目录发布成功。
- 部分失败保留数值错误和已返回未验证状态；未知record ID、同recordName跨zone ID、错误中的敏感样式名称/zone/本地化字符串均不出公开journal。所有敏感样式内容都是独立生成的合成标记。
- 所有save返回之后，fetch缺记录或manifest字节改变仍失败；不能以ACK代替精确readback。
- 最终报告被预置sentinel时不得覆盖，也不得从`run`返回成功。报告写入/路径验证异常均沿抛错路径，不能把日志中的单步`RETURNED_SUCCESS_UNVERIFIED`当最终完成。
- LockedHost始终生成`NOT_READY`、`EXTERNAL_GATE_NOT_COMPLETE`、零网络、无授权、P0 false报告。

## 边界结论

当前准备范围无剩余must-fix。真实SDK adapter仅编译；内部注入CKDatabase不能证明环境/账户，正式factory尚不存在且host没有live入口。zone不存在检查与随后save不是原子create-if-absent，报告明确`zoneCreationAtomic=false`；没有新增跨进程唯一性承诺。真实签名、账户/环境资格、Owner执行窗口、CloudKit实际权限和Development读回仍未验证，P0/P1/P2不通过。
