# iCloud 正式产品开发：Owner调整后的连续执行范围

2026-11-08。Owner明确要求不再被双用户Mac临时探针卡住，先按架构和逻辑完成正式App代码并提供可安装版本，真实服务验证后移。这一最新决定取代旧P1/P2必须先于G2代码接入的顺序，以及G1仅实验/批次停止限制；不将未知门禁改为通过。

工作树：`/Users/himini/Development/Projects/PersonalGrowthOS-icloud-product`，分支`codex/icloud-product`，从PR17的07c1bcf基础继续，与PR18故障探针分开。原项目未提交工作不动；不再运行Mac探针。

连续目标：追加V17同步持久模型及V16迁移保护 → 全部业务保存入口同事务mutation/outbox → 严格领域聚合codec、因果投影和冲突候选 → 持久inbox/引擎state、账户epoch、原图lease及CloudKit/CKSyncEngine → 正式App设置/状态/显式启用 → 本机合成数据验证、独立审查和可安装iPhone Development构建。不能以空UI、全库覆盖或只实现示例Entry替代已批准领域范围。

同步默认关闭；本机正常记录可用，不自动上传已有数据。明确启用及初始合流、账户变化、恢复隔离必须有可理解的状态。保持本地SwiftData `.none`，不把V16直接开启自动镜像；不改历史schema、不关闭完整性检查。验证使用隔离合成库与既有固定V16/v12副本，不打开日常私库。

P0/P1/P2保留NOT_PASSED，后移为真实云启用/验收及生产就绪门，不阻塞隔离代码实现。本机mock/原生/迁移/进程恢复证据与真实Development/Production/TestFlight分列。TestFlight可承接真实服务验收；App Store公开发布前应完成相应验收，不能将公开上架当成首次数据安全测试。

本授权允许必要可逆代码、构建、测试、独立分支/Draft PR与普通push；不授权自动安装覆盖日常App、读取私库、真实云批次、Production部署/写入、Archive、TestFlight、App Store发布、merge或强推。需要这些动作时先完成具体可评审产物和集中操作清单。常规工程步骤不逐项询问；不在每个小阶段停止。
