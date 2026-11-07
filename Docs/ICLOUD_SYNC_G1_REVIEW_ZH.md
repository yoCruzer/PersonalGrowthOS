# G1 独立审查记录

独立reviewer `/root/g1_independent_review` 未参与实现，读取固定起点规范后只读审查，并在独立临时Swift package中调用当前真实SyncLab源码完成反例/复验。仅使用合成数据，未连接云。

| ID | 原始问题 | 修复与验证 |
|---|---|---|
| R1 P1 | 已有截断图片阻止正确原图修复 | 先quarantine保存坏件，再原子安装；独立`REPAIR_BLOCKED`转`REPAIR_SUCCEEDED` |
| R2 P1 | 实际SDK入口在留证前拒绝未知wire | 原始CKRecord及asset先持久化，随后codec；实际CKRecord入口红测转绿 |
| R3 P1 | 恢复仅内存epoch，重开可能上传旧dataset | 持久restore-gate，冷启动仍禁网络；允许本地编辑导出，无自动映射接口 |
| R4 P2 | 缺图父对象仍满足关联依赖 | 媒体可用性纳入递归闭合；独立parent缺图→child staged，补图后均ready |
| R5 P2 | 所有账户事件都halt且封死本地编辑 | 同账户signIn重建zone+record；其他事件fence+cancel；本地save独立，UI重开/导出；实际账户事件仍待真机 |
| R6 P2 | 共享祖先DAG指数遍历 | ancestry/head/readiness缓存；独立26节点由约0.484秒降至0.000257秒，160节点约0.00788秒；有界测试 |

后续复核补充：签名脚本检查profile到期；导出限制与恢复的128对象/4096 mutation/32MB一致；用启动环境`SYNCLAB_DATASET`选择合成dataset，避免说明与禁用的UI输入不一致。新增边界配对测试，不放宽旧断言。

[独立原始证据与manifest](Evidence/iCloudSyncG1/independent-review/)保留首轮失败反例、DAG性能及三次复核原始输出。probe源码逐次扩展，manifest明确最终保存的是superset源码，未冒称每个早期日志对应相同源码快照。

Review仅可放行**离线实验工程交付**。SDK头文件保证delegate事件串行，代码content→state顺序合理；这不证明真实CAS、账户切换、SDK token恢复或旧ACK后另一端收到新内容。独立Reviewer要求保留BLOCKED_ENV，不能写G1全部完成或生产可用。最终源码hash与补充核对结论随证据manifest归档。

## 2026-11-07 签名门禁限定复核

独立reviewer复核本轮Apple profile allowlist修复，发现并关闭旧container字符串子串误匹配。最终完整脚本合成集成30/30、仓库helper8/8，无剩余必须修复项；真实服务仍NOT_RUN。独立测试使用mock codesign/security，不冒称密码学签名/设备验证。实际iOS实包的本机严格签名PASS另见环境台账。

[独立报告](Evidence/iCloudSyncG1/resume-20261107/independent-review/review-final.md) · [命令、源码及证据SHA](Evidence/iCloudSyncG1/resume-20261107/independent-review/manifest-final.json)。初版24/24、7/7和容器负例原始结果原样保留。

## 2026-11-07 专用测试用户的受限Debug探针

独立reviewer检查运行隔离、结果身份/重放、进程互斥、文件模式与token传递，发现的问题均补修。最终独立原生3/3、真实loopback5/5及启动器mock正反例通过，无剩余必须修复项；实际跨用户启动/真实签名/CloudKit未由reviewer执行。

[独立报告及原始红绿证据](Evidence/iCloudSyncG1/probe-engineering-20261107/independent-review/review-final.md) · [源码哈希](Evidence/iCloudSyncG1/probe-engineering-20261107/independent-review/final-source-sha256.json)。本机39项原生、13项工具、两端签名及Release隔离检查另见[工程证据](Evidence/iCloudSyncG1/probe-engineering-20261107/README.md)。不能将命令PASS替代双端云验收。
