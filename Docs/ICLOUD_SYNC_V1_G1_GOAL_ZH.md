> 2026-11-07 Owner最新调整：本轮以手机侧已核验项目作为收口依据；Mac的CK_2作为Owner接受的非阻塞例外。VPN归因为Owner判断，未独立证实。原始失败保留，未运行场景继续标NOT_RUN；不以本轮收口宣称原最低真实服务矩阵全PASS。剩余可独立手机步骤集中完成后记录OWNER_ACCEPTED_PHONE_SCOPE；若其他失败出现则保留并处理。此调整覆盖下文旧的G1本轮阻塞/状态限制，未扩大merge、Production或正式产品接入权限。详见Evidence/iCloudSyncG1/fault-window-20261107/owner-scope-amendment.json。

# /goal — iCloud Sync G1：环境先行的隔离纵向验证

## 授权与固定起点

Owner 将本文件的引导 prompt 发给 Codex 时，授权执行本轮隔离实验、定向测试、文档、普通推送及新 Draft PR；不是授权正式产品同步开发、真实用户库操作或发布。

从 PR #15 修订后的远端 HEAD（引导 prompt 指定SHA）创建 `codex/icloud-sync-g1`；核对祖先含 `e036b01e971de9a9f0538d9a5dedfefc099bfc65`，产品基线为 PR #14 `96f72339a1a3082c43018e06d6115dd93df1df97`。不要从落后的 main 开工；发现远端前进先读取差异，不重置未知改动。保留 PR #15 Draft/base；新 G1 Draft PR 以其分支为 base。

先读 AGENTS.md、DEVELOPMENT_CONTRACT.md、修订版 ICLOUD_SYNC_V1_AUDIT_ZH.md、ICLOUD_SYNC_V1_REVIEW_FIX_ZH.md、ICLOUD_SYNC_V1_APPLE_READINESS_ZH.md。本 Goal 与修订报告优先于初次报告中被修正的语义及历史 CURRENT 记录。

## Goal 1：先消除环境盲区，不以代码编译代替云端可用

检查本机Xcode/SDK/签名权限/测试设备，实际Team/App ID/container关联，CloudKit Development/Production的已知状态；无证据填 UNKNOWN，不从源文件推断门户已配置。先完成Apple门禁E0的只读预检，并生成 `Docs/ICLOUD_SYNC_G1_ENVIRONMENT_ZH.md`，区分实验与正式容器。

建议实验身份：`com.yocruzer.PersonalGrowthOS.SyncLab` / `iCloud.com.yocruzer.PersonalGrowthOS.SyncLab`；正式产品Bundle ID保持不变，正式容器以实际核验为准。需要新注册永久Identifier、变更正式App ID、访问私人内容、退出系统账户或Production部署时，列出精确对象、风险和最小Owner操作清单，不擅自执行。现有已获Owner确认的隔离实验资源可用于合成数据测试。

预检缺条件时，可继续完成独立实验工程、故障注入及部署清单，但不得扩展39实体产品接入。报告 `BLOCKED_ENV` 和一次最小缺项清单；不重复尝试无权限操作，不把阻断改名为成功。

## Goal 2：一个真实纵向闭环，而不是所有模块同时开发

在 `Experiments/iCloudSyncG1/` 建独立可签名实验工程和独立合成store。不得修改正式产品目标、Bundle ID、App Group、现有数据库、业务源码或发布工作流；不得读取Owner照片/日记/财务数据。iOS实验优先；确需Mac作为第二签名客户端可建最小伴随目标，准确标明覆盖平台，不能冒称两台iOS。

采用真实 SwiftData 本地事实/outbox/inbox + CKSyncEngine/private zone + CKAsset，仅实现 Entry-like 文字、一个原图、关联依赖和显式冲突选择。保存不依赖网络；同store事务提交事实与outbox；网络事务外。CloudKit wire编码、state及账户隔离要可审计，不能将Python模拟直接当成SDK实现。

先重跑34项协议定向检查，不重复全量产品测试；保留原始四项失败证据。明确这些只验证实验规则，不是生产领域合并器。

最低真实服务实验：

1. 同一测试Apple Account两个客户端：新增文字/原图、修改、删除、重开、断网后恢复；逐ID/字节/hash核对，不以数量相等为唯一oracle。
2. 真实服务器changeTag/CAS和serverRecordChanged：并发双方输入保留；稳定候选+因果基线的确定性投影；无基线时待处理；冲突预览不进入已确认统计。
3. R1四反例及乱序依赖：已删除、缺祖先、传递缺失、因果环不进入业务表；当前新head不可发布时不回退旧活行；依赖补齐后可继续。
4. 旧上传在途时创建新修改：旧ACK只能确认旧mutation；CKSyncEngine成功移除待发送项后，持久outbox须重新调度新版本，并证明另一端真的收到新内容。
5. fetched内容/state事件落盘及退出点：独立进程恢复不跳过未持久变更；串行/原子顺序明确；不能将模拟整数token的max当作真实state算法。
6. A→退出→B→A及冷启动：未上传A内容可恢复/导出；不上传给B；发送/下载/安装/ACK晚回调受epoch约束；引擎账户变化重置后的队列可以重建。需Owner同意的隔离账户/设备，不能自动退出日常主账号。
7. 图片独立staging、hash校验、持久引用和上传lease；进程退出/缺图/截断后可恢复，不被通用GC清掉；缺图不能称完整备份。
8. 恢复发布门与远端到达竞争：使用小型实验快照验证隔离/epoch；明确它不等于真实v12 ZIP验收。当前V16/v12升级在后续G2，不扩充更早兼容矩阵。

真实服务无法稳定诱发的quota/partialFailure/token等故障，使用明确标为模拟的注入；不能包装成真实云证据。先Dev跑通，不先做完整UI或全App重构。

## Goal 3：把Production问题放在大规模接入前暴露

按 Apple 就绪门禁记录E0/E1/E2及P0–P4，部署清单含稳定wire types/字段/必要索引、版本/hash、每项证据。使用实际codec生成合成覆盖，不能仅看到0条记录或无部署差异就通过；不是自动导出39个本地实体。

Development通过后，在正式核心wire稳定时准备正式容器Production部署差异和精确Owner步骤。**本 Goal 不授权Production部署/写入**；需要该步骤时停在 `DEV_PROBE_PASSED_PRODUCTION_GATE_PENDING`，提交可执行清单。Owner明确授权后才进行P1/P2，且须使用合成dataset/测试账户，不读取现有私人数据。试验容器Production即使通过也不能代替正式P1/P2。

正式P1/P2未完成前，不建议/启动G2/G3的大规模领域接入。不要求先上架App Store；TestFlight使用Production，首次TestFlight前须P3通过，实际发布仍需另行授权；发布后P4才可能通过。后续wire变化重复检查，不能一次勾选永久有效。

## 验收、证据与停点

交付 `Docs/ICLOUD_SYNC_G1_EXECUTION_ZH.md`、环境台账、wire schema清单、复现步骤、独立审查记录和原始精简日志。记录SHA/dirty、设备/OS/Xcode、命令/退出码、测试实际覆盖、云环境、未运行项；公仓日志禁止正文、私人金额、账户ID、令牌或签名私钥。合成样本明确标识。

让真正独立的reviewer检查实验代码与故障路径；不能由实现者自称独立终审。优先定向测试，稳定候选再集中相关检查；不跑无因果关系的完整App UI/Unit。网络、签名或Owner步骤缺失仍完成可做交付，但准确标为BLOCKED/PENDING，禁止以mock替代。

状态只用：`BLOCKED_ENV`、`DEV_PROBE_PASSED_PRODUCTION_GATE_PENDING`，或在另获授权且实际完成正式P1/P2之后的 `G1_READY_FOR_IMPLEMENTATION_REVIEW`。最后一个仍不是生产可发布。不得merge/force push/rebase历史/tag/Archive/TestFlight/部署Production/重置云环境。保留原工作区未知改动；仅普通push到新G1分支并创建Draft PR后停止。
