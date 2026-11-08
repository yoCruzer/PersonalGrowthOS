# 固定本地收口与下一次 Development 验证窗口

状态：代码`b3cd013`已实现、签名候选及独立审查完成，最终定向CI42474881433成功并核验178原生/35独立/40打包及47源指纹。真实收口和新云窗口尚未获批、尚未执行。旧单次授权不被重复使用。

此前 enrollment 成功；首个 account-status 在 enqueue 前失败，原始代码未保存拒绝原因。已完整导出15份私人探针证据，独立核对显式账户API/transport调用均0。随后haha的4次离线签名、会话与目录检查全部通过，未复现原拒绝；这不将原批次改成成功。旧 ledger 的未结束记录必须保留，不能用删除、重新初始化或重跑旧计划绕过。

## 具体候选与固定范围

- 签名二进制 SHA256：`27dfec3681e64e8b9cc76aaaa9904dea245a47032c5e956a9b384861c45145e7`；同一既有独立 App ID/profile/开发证书。47份Swift源码/测试指纹固定，实际自身离线资格通过。
- 第一步仅本地追加：旧 run `F2300A35-3533-43CF-8254-B674557ED5F0`，旧 dataset `6389FCC2-BEE5-43CE-88EC-B7C7842A94C9`，旧 plan `30f1fef8a9d1431f7817d49647bd0bb99621854802eabcdeeca2bfd1a6fe2f74`。
- 旧 head 必须精确为第5条，文件 SHA256 `ccb00b67ff7af483dfb8341a1664fa31acb213eff0f26f0aed14706eb0b254b2`。验证现有 Keychain anchor/HMAC 与锁后，仅追加一条含本次审批摘要的 `ownerClosedUnknown`，同步更新既有 anchor；原始文件不改、不删除、不重新 enrollment。
- 第二步为新计划：run `B6AC6D45-A83E-4DF3-8DDA-71B9CC5EA2C1`，dataset `F9CFBE52-E357-4B4D-A845-E99BEE6875C1`，plan SHA256 `d8754dc081af6aa56719f5c85b7845da698643b22d99280c4846062c7d24d17a`。
- 正式容器 Development：新合成zone，3条asset/chunk与3条mutation，精确读回6条；最多12次账户API与5次transport调用，可能新增候选3类型/11字段。没有业务query、物理删除、Production操作或发布。

## 完成前置检查后的一次人工操作

前置：对应代码的最终本机验证、独立审查、定向CI完成；既有haha会话仍为已确认测试iCloud且执行期间不切换账户；Owner明确批准以上本地追加与一个新固定窗口。旧代码的CI不能替代新代码，审批未到时交付脚本会直接拒绝。

Owner在haha终端启动一个脚本：先closeout，成功后才run。共用最长15分钟的执行窗口，正常预计2–5分钟；随后本地只读证据导出最多再1分钟。手机前台/数据线占用均0。任何一步失败即停，不重试、不重新初始化；导出由探针自身读取sandbox，避免再次要求终端直接读取容器。

完成判据：closeout报告绑定旧head与新terminal摘要；新run精确读回全部合成字节、各阶段证据与ledger一致；最后私人原件独立复核。返回成功仍不自动宣布P0冻结。若新批次实际成功，才需要导出更新后的Development schema复核类型/字段；这一步依赖真实写入结果，不能用当前旧schema提前完成。Production仍不部署、不写入。

closeout成功不表示历史远端结果已查明，也不允许旧run/plan重放。旧版本二进制可能因不认识新terminal而拒绝读取；这是保守兼容行为，不能以此删除历史。私有原始approval/profile/ledger/回调不进入Git。
