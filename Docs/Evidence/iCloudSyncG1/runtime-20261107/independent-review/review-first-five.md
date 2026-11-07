# 单 Mac 真实运行证据独立复核

日期：2026-11-07。工程 HEAD：`5a19fbdf61c97415c958b843ff760fd010028f3c`，复核时工作树干净。固定范围为 `synthetic-g1-20261107-r4` / `probe-run-20261107-r4` 的 probe-001 至 probe-005。后续队列命令不属于本报告结论。

结论：提供的五组运行结果通过独立断言，支持单 Mac 的真实 CloudKit SDK 发送确认、持久状态写入、同进程 Store/Engine 重开及随后同步。本审查未发现该范围内证据矛盾或数据丢失。它不构成双端验收，也不是服务端独立查询或加密远程证明。

## 已核验

- 每个结果的 ID、dataset、runID、platform 和原始请求 SHA256 绑定匹配；固定动作依次为 connect、save、sync、reopen、sync。五个状态均 PASS、未 halted、无 errorCode。账户指纹格式有效且五次相等；仅在内存比较，未输出或保存指纹。
- 初始快照为空。save 请求的唯一 mutation 与后续四份快照逐字段完全相同，包括 ID、object、版本、删除标记、文本、parents、requires、图片 hash 与 byte count；无新增、缺失或重复 mutation。
- 图片与独立固定参考 PNG 的全部 68 个原字节一致，SHA256 与声明一致；四份快照图片集合一致。不是仅比较缩略图或投影。
- 投影始终 ready、complete，候选与 preview 精确匹配请求。pending 数量依次为 0、2、0、0、0；save 的两项恰为图片记录和对象记录。
- probe-003 包含 ACK_EXACT_AND_RESCHEDULED、FETCH_CONTENT_DURABLE、STATE_DURABLE，未出现失败、fence 或错误事件。源码 Cloud.swift:152–159 仅在 CKSyncEngine sentRecordZoneChanges 处理时标记 ACK；Store.swift:126–134 按准确 sent payload 清 pending。这与真实 SDK 发送确认且本地队列清空一致。
- probe-003 与 probe-004 的 checkpoint hash 相同。reopen 创建新 LabStore 与新 CloudDriver，Cloud.swift:76 将已持久 checkpoint 解码为 CKSyncEngine.State.Serialization 并用于初始化；probe-004 只有新引擎启动事件，数据与图片保留。probe-005 再同步产生持久状态事件、仍无 pending、快照保持相同。

## 独立验证器与负控

执行：`python3 /private/tmp/g1-runtime-review-20261107/verify_runtime.py --self-test`。

五组真实输入断言通过；12 个仅在内存构造的篡改负控均被拒绝：错误摘要、dataset、run、账户指纹、mutation 文本、图片原字节、pending、重开 checkpoint、缺失 ACK、错误投影、重复 mutation、halted。没有改动原始输入；没有排队命令、访问设备或执行任何云写入。验证日志保存在 `verification.log`，其中记录每份原始 request/result 的 SHA256 而不复制私有原件。脚本只使用 Python 标准库，可原地重跑。

## 明确未验证

- probe-004 是同进程内部的 Store 与 CKSyncEngine 重开，不是 App 进程终止重启、系统重启或断电恢复。
- FETCH_CONTENT_DURABLE 事件不包含每个 fetched record 的来源/数量；现有本地内容也未清空，所以不能据此声称从空白客户端或纯云独立重建了内容/图片。
- 没有第二客户端的结果，不能证明 Mac/iPhone 同账户、跨客户端记录传播、冲突合并、离线编辑或完整 G1 门禁。iPhone 安装阻断由父任务报告，本审查未访问安装日志/设备，故不独立验证其错误码。
- 本次审核以父任务提供的签名真实运行产物为证据输入；未重新检查运行二进制签名、有效 entitlement/profile、实际 OS 用户启动过程或服务端数据库。命令 PASS 本身不是云验收；本报告结论来自身份绑定、原字节、状态转换与对应源码路径的组合核验。

源码哈希在 `source-sha256.json`；断言源码在 `verify_runtime.py`。所有新增审查文件均脱敏；未输出或提交账户指纹。
