# 正式容器两环境结构收取与候选差异

2026-11-08。Owner提供刚导出的两份原始CKDB文件及对应Console截图，原样保存在仓库外本机私有目录；[公开证据](Evidence/iCloudSyncFoundation/20261108/formal-schema-intake/)仅含来源摘要、哈希与结构审计结果，不含CKDB或截图原件。未查询Records，未导入、初始化、部署或写入云数据。

## 已确认的输入

Development和Production文件均为356字节，SHA256均为`60fec48392126eab598a05dbe0f7f9557494a992df8fb62295ccd3752a7768db`，逐字节一致。仅定义Users共7字段，原有系统字段与权限保留；公开材料不转录完整声明。

截图分别显示`iCloud.com.yocruzer.PersonalGrowthOS`的Development和Production、Users及7 fields。截图不显示Team或正式App关联，CKDB本身不内嵌环境、容器、Team、账号或服务端导出时间。来源绑定来自Owner说明和相应截图，记录于receipt.json；不将本地文件名或文件时间冒称独立服务器身份凭证。两个原件及截图在复制后再次校验，下载原文件没有改动。

这仅证明提供的两份结构相同，不能据此推断无业务记录、数据库已清空、签名资格可用或环境已就绪。

## 与实际SDK候选的差异

代码候选为72f5d3d的SyncFoundation v2，实际SDK生成的schema SHA256为`6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003`。两环境均缺少以下3种业务类型、11个业务字段：

| 新增业务类型 | 候选业务字段 |
| --- | --- |
| PGMutationV2 | manifest BYTES；sha256 STRING；wireVersion INT64 |
| PGPayloadChunkV2 | byteCount INT64；chunk ASSET；sha256 STRING；wireVersion INT64 |
| PGOriginalV2 | byteCount INT64；original ASSET；sha256 STRING；wireVersion INT64 |

没有现有业务字段需要删除、改类型或迁移；Users及其既有定义保留。当前候选使用private database和按recordID/zone变化的访问方式，没有自定义query索引。系统字段、默认索引和业务类型的权限仍须在正式Development实际覆盖后读回审查；**不从Users复制_world READ或其他GRANT作为业务权限模板**。

本表是候选相对于提供结构的差异，尚不是可部署DDL或Production批准单。当前Development也没有这三个类型，所以直接把现状部署到Production不能建立所需协议。P0不能在正式Development覆盖/读回前冻结，P1也不能由两环境相同而填PASS。

## 本轮代码侧工作

严格离线schema比较器负责绑定三份输入的原字节摘要、完整解析其支持的导出语法并报告字段/类型/权限差异；未知语法及重复定义必须拒绝，不能忽略后输出“相同”。输出标为REVIEW_ONLY_NOT_DEPLOYABLE，不生成或执行导入/部署文件。

隔离Development适配器复用固定合成计划与v2 codec，准备真实SDK的精确zone、保存及recordID读回调用；当前只编译和通过合成transport验证，host保持外部门禁锁定，不创建CKContainer、不提供live开关。测试ticket不是实际Apple授权，CKDatabase注入也不能证明账号或Development身份。签名/账号/环境认证factory与真实窗口未完成时，不开放网络入口。zone存在探测与创建不是原子的跨进程排他保证，不能据此声称解决全局并发。

## 下一项Owner输入及外部边界

两份结构导出已收到，不要求重复。Owner随后确认正式App `com.yocruzer.PersonalGrowthOS` 的iCloud/CloudKit support/Push均启用，关联正式容器，见[文字核对来源](Evidence/iCloudSyncFoundation/20261108/formal-app-association-owner.json)。此项不再缺失；签名产物/profile及独立客户端资格另行检查。

关联确认后已完成隔离Mac未配置开发签名产物及本机/远端验证；现有开发身份可复用，精确候选profile缺失，下一项为[限定配置及签名预检授权](ICLOUD_SYNC_FORMAL_HOST_PROVISIONING_ZH.md)。真实Development执行窗口仍须另行完成实际资格与执行控制。新增Apple永久Identifier、变更正式App能力及实际云写入不因收到schema文件自动获批；Production部署/写入、merge、Archive、TestFlight及发布边界继续保持。G1手机侧接受范围与Mac CK_2例外不变，不借本轮只读材料重启整套G1。


## 本机实现与独立复核结果

`Scripts/SyncSchemaAudit`已完成严格离线比较；实现16项自测和独立20项检查通过。实际Owner输入的完整比较报告仅本机保留，公开其[审计摘要](Evidence/iCloudSyncFoundation/20261108/formal-schema-intake/audit-result.json)，原件再次摘要一致；独立发现的输出父目录被替换仍误报成功问题已修复，红例源码/结果与修复后证据分开保留。比较器只支持明确语法子集，不是CloudKit服务器schema合法性验证器。

`FormalDevelopmentSDK`已编译实际CloudKit保存/精确ID读回API；批次runner的17项本机测试及11项独立异步反例通过。完整包在初次冻结点为51/51（既有34+新增17）；随后两个末尾路径绑定强化以17项定向、11项独立和iOS17 target编译复验，未沿用旧源码hash。独立测试使用真实Continuation暂停全部五个await边界，验证过期epoch、task取消、并发与重放、源/lease/目录变化、partial失败、错误ID/字段/完整字节及日志脱敏。当前scope无剩余must-fix。

Host真实CLI检查：合法计划仍exit2/NOT_READY；错hash exit1；live参数exit64。没有CKContainer构造或真实授权factory，代码无法从当前入口启动云操作。内部CKDatabase adapter仅编译，未实例化或调用；模拟transport成功不等于Apple服务成功。zone探测后save非原子，持久单次执行、跨进程排他、真实签名/账户/环境资格仍未实现；后续不得直接绕过这些缺项。

本轮只运行与新增工具/SDK隔离模块相称的定向本机检查。新独立回归已接入定向CI，CI仅使用独立合成schema；Owner原件的比较仅在本机完成，远端不重新读取原件；固定d508ae4的定向与产品CI均已成功，未使用上一提交的成功替代新代码，精确计数与限制见[本轮证据](Evidence/iCloudSyncFoundation/20261108/README.md)。正式产品源码、工程和既有G1工具未改，原项目其他未提交工作保持。

原件发布边界：自动审批拒绝将Owner四份原件提交并推送到GitHub，因尚无这些具体原件的远端传输授权。该提交/推送命令未执行。采用更小范围交付：保留本机原件，公开结构摘要及独立合成测试；没有将原件改名、编码或封装后上传。
