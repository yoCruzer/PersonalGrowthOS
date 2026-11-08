# iCloud正式App开发版交付

Owner最新顺序为先完成正式App代码与可安装Development版本，再安排真实云/生产验收；本轮停止Mac双用户/tmp探针排障。该决定改变开发依赖顺序，不改变数据完整性或发布权限。

## 已实现

- SwiftData V17只增加本地同步表，保留V16及历史迁移链、迁移前原件保护和显式CloudKit `.none`。
- 38个同步实体→23个业务聚合；全部真实写入入口通过同context一次保存事实、不可变mutation/outbox/head。按受影响kind捕获，普通记录编辑不序列化整份净资产账本。
- current-head因果投影、删除防复活、缺件等待、冲突版本保留和用户显式全parents解决；严格领域重建/归属校验，保留UUID、冻结值和本机专属授权/设备日志。
- 独立不可变原图副本、payload分块、hash/size验证；持久inbox先于CKSyncEngine checkpoint，exact revision与全部资产ACK。
- 账户/容器/环境/dataset/generation隔离，停用保留本地/队列；zone创建意图单次消耗，不对已知丢失或未知结果自动重建。
- 设置内默认关闭、现有数据上传确认、同步状态/不完整提示、可读冲突预览；显式启用后本地保存/前台恢复驱动同步并接入CloudKit静默推送桥。真实推送未验证。
- Development签名构建使用正式App bundle与既有正式容器，profile能力及签名/运行环境一致性须回读。Release暂无启用环境pin，保持生产门禁未通过。

## 使用与人工边界

交付的是开发签名构建，不是TestFlight或商店发布。**未替用户安装、覆盖或迁移日常手机App**，也未启用云上传。现有SyncLab build7不改动；正式产品构建号8。

可安装包完成后用Xcode → Window → Devices and Simulators → 选择已登记iPhone → Installed Apps 的“+”选择解压后的PersonalGrowthOS.app；这一步会替换相同bundle的已装正式App，故须Owner在计划使用前先导出个人备份并明确选择安装。预计2–5分钟，数据线2–5分钟；不卸载现有App、不删除旧数据。若尚不准备手机验证，保留包即可，无需执行。

正式App“设置 → iCloud sync”默认关闭；点击Enable后的确认才允许当前iCloud账户的私有数据库收发。不要为了测试退出日常iCloud。使用前先理解本轮真实云验收未完成，个人数据不作为自动测试输入。

TestFlight之前仍需单独授权并集中处理：
1. Development用合成记录完成实际收发/冲突/照片验证，导出实际schema，确认候选3类型/11字段和权限/索引。
2. 对照Production只读导出确认差异；Owner批准后再部署schema，启用Production签名/运行配置并实际核验。
3. 通过上述门禁后另行批准Archive/TestFlight；测试期覆盖真实账户、离线重试和后台路径，通过后再考虑公开上架。

这三步存在先后依赖，不能仅凭编译通过跳过schema与云验收。当前不要求再执行Mac探针命令或占用手机完成已有G1测试。

验证计数、例外和容量边界见[本轮证据](Evidence/iCloudProduct/20261108/README.md)。最终源码、PR、CI和签名产物摘要在收口后写入该证据；未记录项保持未验证。
