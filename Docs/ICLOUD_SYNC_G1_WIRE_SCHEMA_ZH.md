# G1 wire 候选与 Production 前置清单

状态：**CANDIDATE_NOT_FROZEN / P0未通过**。实际Swift codec已生成[字段清单](Evidence/iCloudSyncG1/offline-20261106/codec-schema.json)，但没有检查任何服务器schema。本文件提前定义门禁，不是部署指令，不授权写入正式Production。

| Record type | 字段 | CloudKit类型 |
|---|---|---|
| G1ObjectV1 | wireVersion | INT64，固定1 |
| G1ObjectV1 | objectID | STRING，稳定实验对象ID |
| G1ObjectV1 | payload | BYTES，最多262144字节的canonical JSON envelope |
| G1ObjectV1 | sha256 | STRING，payload SHA256 |
| G1ImageV1 | wireVersion | INT64，固定1 |
| G1ImageV1 | sha256 | STRING，原图SHA256 |
| G1ImageV1 | byteCount | INT64，1～8388608 |
| G1ImageV1 | original | ASSET，校验原图 |

zone为`G1-<dataset>`，private database。recordName分别为`object-<objectID>`、`image-<sha256>`。CKSyncEngine按zone变化和recordID工作，不使用自定义query，**当前额外自定义索引为空**；系统change tracking、recordName、changeTag由CloudKit管理，不自行造服务器token。若将来增加查询，须重做索引审查。

payload v1包含外层version/object/mutations，mutation含id/object/parents/requires/text/deleted/version，以及可选imageHash/imageBytes。使用实际codec的图片/依赖样本、删除/因果/未知版本测试覆盖，不能把JSON内字段误当成单独CKRecord字段。system fields含服务器changeTag，仅在本机保存，用于SDK CAS；不写入备份或业务payload。

每个object上传完整有界历史以便并发集合合并；这是G1微型协议，512 mutation上限/有界图片保留均不满足完整产品容量需求。不能直接将这两个实验type灌进正式Production作为最终产品schema。正式wire命名/版本、聚合manifest、容量策略应在真实Dev证据之后再冻结。

## 稳定版本和差异的生成

1. 固定候选代码SHA、dirty=false、`Cloud.swift`/`Protocol.swift` SHA256；使用`LabReplay schema <新合成根>`重新生成清单并计算文件SHA256（本轮哈希见证据manifest）。
2. 在**实验容器 Development**使用实际codec签名客户端保存覆盖所有字段的合成记录，读回每个recordType/字段/类型/值/hash。当前本地编码成功不能替代此步骤。
3. 有权限者导出准确容器/环境的当前schema，逐项与候选清单对照，保存原schema、拟变更schema和精确diff；确认权限仍为private database、没有公共记录开放。无待部署差异/0记录都不能作为P0通过。
4. 正式wire稳定后，在正式容器Development准备仅合成覆盖（须相应授权），形成**正式容器**P1部署差异。实验容器的结果不能复用成正式结果。

## 需要 Owner 批准时应呈现的具体操作单

当前缺少真实schema导出，因此以下槽位保持UNKNOWN，不能给Owner虚构“可直接批准”的差异：

- Team：预期`83SKX2PM7B`，门户角色核验待完成。
- 目标：`iCloud.com.yocruzer.PersonalGrowthOS`，Development→Production；仅schema，不复制Development记录。
- 固定代码SHA、正式wire版本/hash、旧schema/hash、新schema/hash、types/fields/indexes/permissions逐项diff：**待Dev通过及正式wire冻结后填入**。
- 操作：Owner在CloudKit Console准确Team/正式容器的Deploy Schema Changes审核差异；Prod type/字段不可像Dev任意删除，因此禁止提前部署实验模型。
- 部署后：再次导出正式Production schema逐项核对（P1），使用经批准、Production签名的隔离客户端在正式容器执行合成新增/读回/修改/删除意图/原图hash/双端重开（P2）。仅部署按钮成功不能代替P2。
- 不满足P1/P2：停止G2/G3大规模接入。后续任何wire变化重新审查；P3/P4仍需正式候选/另行TestFlight授权。

参考：[Apple schema部署](https://developer.apple.com/documentation/cloudkit/deploying-an-icloud-container-s-schema)、[Apple CKSyncEngine示例](https://github.com/apple/sample-cloudkit-sync-engine)。本地SDK `CKSyncEngine.h`的delegate串行契约及真实类型签名已核验；服务器语义仍须实测。
