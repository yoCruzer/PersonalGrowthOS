# 2026-11-08 CK_4 真实失败与责任复盘

本次a72befa固定窗口失败，未通过P0，不重跑。交付入口已停用，原始探针与系统日志私存；没有切换用户、修改网络设置或触发额外云调用。代码未因猜测原因而修改，未重复全量测试。

## 实际证据

run3254C900… exit1，唯一新run只读导出exit0。56份文件（23 run＋33 ledger）全部SHA匹配。三次账户wrapper调用成功；首个zone-probe通过入队门禁后由SDK aggregate callback返回CKErrorDomain4。createZone与save阶段均未进入，不能把wrapper计数当作真实HTTP请求数，也不由此宣称所有操作系统活动为零。

同一probe进程、CloudKit operation、后台task与Connection496的日志关联确认：NSURLErrorDomain -1001，约10987ms超时；HTTP统计request/response 0字节、response_status=-1、cache_hit=false。连接经过utun10；六个子连接进入TLS read_server_hello后停滞。同时存在指向本探针Bundle ID的Network Delegation Failure和LaunchServices无法找到bundle记录的日志。原始URL/IP与账户标识不公开。

因此可以确定失败位于本次CloudKit zone读取的连接/TLS阶段；**不能认定VPN或Apple服务是根因，也不能排除临时.app直接执行的启动/注册兼容问题**。warning后仍进入TLS，故同样不能把warning直接定为失败原因。签名/entitlement通过不等于LaunchServices身份可解析；账户返回成功可能使用缓存或不同服务路径，不能证明数据请求通路正常。

账本seq32已有remoteOutcomeUnknown terminal，seq33绑定failed-report；所有permit都有终态，不需要再次closeout。独立审查完成19项结构/链接/引用检查；仅结构完整性，不冒称读取并认证过当前Keychain/HMAC。实际失败和未知结果不改成成功。

## 明确应承担的实现和验证责任

1. 最初跨用户二进制权限未充分验证，Owner遇到PermissionError。
2. 引入system_profiler作为运行时依赖，但同步离线通过未覆盖真实异步入口的硬件报告超时。
3. 原始顶层异常缺少原因，导致多轮人工诊断；a72befa已移除该依赖、增加异步检查与白名单顶层原因，本机和haha均通过。
4. 当前仍有诊断缺口：错误证据只保留外层域/码，丢弃underlying chain与retry-after；账本对CK transport错误使用笼统validationFailed，虽然实际failed report保留CK_4与回调阶段。本次依靠原始系统日志才细化到TLS超时。
5. 未验证LaunchServices识别和网络委托身份，不能将离线/CI通过表达成整个真实链路可用。启动方式兼容风险需要在本机进一步隔离验证，不能让Owner继续用云批次试错。

前几轮存在可避免的工程失误，不能用Apple环境复杂解释。最新失败虽已有真实连接超时证据，责任归因仍未完成；不使用模型名称、VPN猜测或CI数量替代根因分析。完整产品同步仍未交付。

## 后续边界

本次不发新的试跑脚本或授权请求，不重复旧收口，不调整Owner VPN/iCloud/系统用户。后续优先独立验证启动/注册方式及补足有限、脱敏的错误链；在形成可验证结论前不安排下一轮真实云尝试。P0/P1/P2仍未通过，不能把本次失败或此前G1 CK_2例外改写成正式容器成功。原项目未提交工作不动。

[脱敏结果与原件hash](Evidence/iCloudSyncFoundation/20261108/execution-guard/runtime-fix/ck4-window/result.json) · [独立审查](Evidence/iCloudSyncFoundation/20261108/execution-guard/runtime-fix/ck4-window/independent-review.json)。公开语义依据：[Apple CKError.networkFailure](https://developer.apple.com/documentation/cloudkit/ckerror/code/networkfailure)、[Launch Services应用注册](https://developer.apple.com/library/archive/documentation/Carbon/Conceptual/LaunchServicesConcepts/LSCConcepts/LSCConcepts.html)。官方定义不替代本机实际因果证据。
