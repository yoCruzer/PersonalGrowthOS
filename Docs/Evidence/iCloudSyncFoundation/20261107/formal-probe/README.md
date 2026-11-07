# 正式 Development 批次准备器证据

范围为同包的 `FormalProbeCore` / `FormalDevelopmentProbe`，不链接正式 App、不包含 CKContainer 或网络发送；正式容器、Development、候选独立客户端身份与 v2 schema 固定。完整用途见[执行说明](../../../../ICLOUD_SYNC_FORMAL_PROBE_PREPARATION_ZH.md)。

- `implementation/`：完整包34/34（既有24项+新增10项）、iOS17共享核心target编译、真实CLI三命令与完整合成计划，原两轮路径误拒绝失败不覆盖。实际未配置profile的二进制preflight为NOT_READY、exit2；注入元数据正例不是实际签名通过。
- `review/`：独立构建快照、自包含CLI黑盒与签名产物替换负例，详见该目录独立审查说明。不同维度的用例数不叠加成一份原生测试数量。
- 相邻 `formal-probe-root/`：初稿损坏PNG的独立CRC原始失败；修复后PNG的独立CRC检查，以及从真实workflow提取的三命令步骤实跑。六条SDK检查、报告的OFFLINE_ONLY/P0 false及实际签名拒绝均按输出核验。

计划和输出均为新临时目录中的合成数据，输入及旧报告不覆盖。根代理的早期CI-step源码快照可能早于独立脚本接入workflow，按每份source-sha256及后续提交/CI记录识别，不能重标为同一源码。当前真实签名客户端、Development服务验证、服务器schema逐字段读回及P0/P1/P2均未完成。
