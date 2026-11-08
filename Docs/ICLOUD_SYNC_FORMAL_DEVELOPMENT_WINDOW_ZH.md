# 正式 Development 首次固定窗口：Owner 集中清单

状态：**代码、测试与最终签名候选已完成；尚未取得真实执行授权，不得执行 enrollment 或 run 命令。** 固定输入见[审阅请求](Evidence/iCloudSyncFoundation/20261108/execution-guard/owner-window-proposal.json)。签名二进制 SHA256：`9291c390e9dbbf8b6999dbe06b87f45769be53f4e76744e7f5139298c867577e`；plan SHA256：`30f1fef8a9d1431f7817d49647bd0bb99621854802eabcdeeca2bfd1a6fe2f74`。已有独立 App ID/profile/签名权限和正式 App 关联/schema 导出均已完成，不需要重复配置或导出。

## 目的和精确范围

仅在一台已登记 Mac 的专用测试 OS/iCloud 会话，验证正式容器 Development 的固定合成数据路径。首次本地 enrollment 在该用户专用 Application Support 创建 guard，并新增该探针的一个 Keychain anchor；不读取或修改产品业务库，不重置已有 guard。

一次批次最多 12 次账户资格/身份 API 调用和 5 次数据 transport 调用：精确检查新合成 zone 不存在，保存该 zone，保存 1 原图+2 payload chunk，再保存 create/edit/tombstone 三条不可变 mutation，最后按六个精确 ID 读回并核对完整字节。tombstone 是新增记录，不是删除已有数据。首次 Development 保存可能生成候选 3 类型/11 字段。这些是 API 调用数，不是 SDK 内部 HTTP 请求数量。

当前没有 CloudKit 业务查询、枚举、删除、自动补偿或失败重试路径。失败/取消/崩溃后保留本地原始证据及可能已经产生的远端部分结果；同批次不能重新消费。后续补读/补写须按实际缺口另列，不重跑整套 G1。

## Owner 需要完成的前置操作

1. 在 Mac mini 手动进入已有专用测试用户 `haha`。不要退出日常 iCloud，也不要清空或卸载 iPhone SyncLab。密码或验证码在 Apple/系统界面自行输入。
2. 只读确认该用户当前登录的是预期测试 iCloud；无需发送邮箱、账户原始标识或密码。确认会话稳定，并在实际窗口期间不切换 iCloud/OS 用户，不在另一台 Mac 同时运行同一批次。
3. 确认愿意执行上文的本地 guard enrollment 与正式 Development 合成写入后，再生成绑定最终产物、OS 用户、15 分钟以内实际时间窗和全新 run/dataset 的批准输入。离线清单、模板或签名成功报告均不能自动变成批准输入。

2026-11-08 的只读会话观察为：当前 console 和 agent 均不是 `haha`；当前 iCloud 状态没有查询。不能沿用此前登录状态，也不能将当前日常用户下的离线签名成功当作测试账户资格。用户切换后的实际会话观察、输入中的 UID 和有效时间窗依赖上一步完成，因此无法提前伪造为同一条已通过命令。

## 执行和完成判据

最终本机产物位于 `/private/tmp/PGOS-FormalSigning-20261108-cfpay1lu/runtime-guard-completion/FormalSyncProbe.app`，该私人构建目录不假定其他 OS 用户可访问。获批并确认测试会话后，才向该用户提供同 hash 的隔离副本和有效期输入。命令形状为 `FormalDevelopmentHost enroll-guard BASE64_APPROVAL EXPECTED_SHA` 和 `FormalDevelopmentHost run-approved BASE64_APPROVAL EXPECTED_SHA`，每个独立进程只允许一次尝试；不得用审阅模板替代批准输入。生成准确 UID、决定引用、开始/结束时间及编码命令依赖 Owner 到位，当前不会提前制造过期或伪批准输入。受审入口必须先校验 Owner 输入、自身签名/profile/设备、OS 会话和持久消费，再构造固定容器。每次阶段前后复核账户，账户变化或窗口到期立即停止后续阶段。账户 convenience API 取消只停止本地等待，不保证服务器未执行；晚到回调归属原 run。

预计 Owner 会话确认约 2–5 分钟；实际窗口上限 15 分钟，网络异常可能提前终止。手机前台及数据线占用均 **0 分钟**。若触发系统登录或 Keychain 界面，等待 Owner 输入不视为已经通过，也不延长原批准窗口。

完成判据为六条固定记录和原始字节精确读回、无证据 fatal、账户与会话稳定、持久链完整，以及后续只读 Development schema 导出与候选结构独立比较。后者依赖实际保存完成，不能与本轮已有的空 schema 原件混为一份证据；没有成功保存时不要求重复导出。

该窗口不包含 Production 部署/写入、PR 合并、强推、Archive、TestFlight、正式发布或私人业务数据操作。即使合成批次成功，也不自动宣称 P0/P1/P2 或完整产品同步通过。
