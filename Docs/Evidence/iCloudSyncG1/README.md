# G1 新增原始证据

本目录仅包含合成数据及脱敏环境摘要。原`Evidence/iCloudSyncV1/`字节不改写。

- `offline-20261106/environment.json`：非沙箱只读签名身份数量、缓存profile能力、设备/门户限制；不含账户ID、设备UDID、证书姓名、token或私钥。
- `protocol-runs.json`及三日志：新执行34项；不是原审计失败日志的替换。
- `native-first.log`：沙箱编译失败；`native-build-02.log`：库构建成功但当时无测试，exit1。
- `native-tests-03/04.log`：23项；`review-red-05.log` 2FAIL、`review-red-06.log` 3FAIL；`review-green-07.log`28PASS；后续08/09/10/11分别29/31/32/33PASS。新增覆盖或修复后重跑，未重标旧失败。
- `process-replay*.json`：独立进程命令/实际退出码，73/74是有意退出；`*-final.log`对应最终源码。占位checkpoint不是SDK state。
- `codec-schema.json`：真实本地codec生成的所有CKRecord字段/type，`schema-final.log`复核同一清单。P0仍未冻结；没有服务器schema证据。
- `ios-*.log` / `mac-*.log`：原始构建日志；`device-signing-check.log`退出65，缺SyncLab iCloud/Push profile；`unsigned-signing-negative.json`退出1为预期拒绝。
- `independent-review/`：独立临时Swift package反例源码/日志、初审与最终hash；早期probe逐次扩展，保存最终superset，详见其manifest；`final-review.txt`是独立reviewer最终结论的归档。
- `commands.json`：本机命令与退出码索引；`manifest.json`：证据与最终源文件SHA256。原生日志来自实现过程，工作树dirty=true、parent HEAD为304a919；最终源码hash可与后续实现commit/CI核对，不能冒称所有早期日志对应最终源码。

实际Development/Production/TestFlight证据均不存在，不能从本目录推导云端通过。完整状态见[中文报告](../../ICLOUD_SYNC_G1_EXECUTION_ZH.md)。
