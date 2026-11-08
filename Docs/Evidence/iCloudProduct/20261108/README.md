# 正式产品同步实现：本机证据（2026-11-08）

范围：PR17 / `07c1bcf` 上的 `codex/icloud-product`，独立持久工作树。原项目三项未提交工作未修改。PR18 / `290bfc0` 的 Mac 探针 CK_4 原始失败仍有效；本轮不重跑探针、不调用真实账户/CloudKit，不把纯代码测试称为云验收。

## 实际验证

环境：本机 Xcode 27.1 / macOS 27.0.1，iOS 27.0 专用模拟器；Swift 纯协议测试不构建/运行真实云容器。所有领域/媒体测试为合成数据，协调器测试显式 `automaticSync: false`。

- 协议/因果图相邻测试：`swift test --package-path Packages/SyncFoundation --scratch-path /private/tmp/pgos-causal-product-build --filter SyncFoundationTests`，44 PASS，包括20个因果图反例/排列/循环/预算测试。
- 第一轮产品同步：46 tests = 39 PASS / 7 FAIL。原始 `/private/tmp/PGOS-Product-Sync-1.xcresult`、`/private/tmp/pgos-product-sync-tests-1.log` 保留。失败分别为资产写选项不支持的崩溃、CoreData保留字段名 `objectID` 冲突、测试临时container提前释放、测试空正文违反既有领域规则；没有把它们归咎于网络环境。
- 修复及资产/容量边界：`PGOS-Product-Sync-2.xcresult` 54/54 PASS。资产改为目录FD/no-follow/原子不覆写发布；状态字段改 `businessID`；两个fixture修正保持原断言及新增反例。
- 全量产品 Unit：`PGOS-Product-Unit-1.xcresult` 656执行 = **655 PASS / 0 FAIL / 1 SKIP**。跳过既有“真实32MB低空间HFS+镜像”测试，未填满主卷。该节点包括20个最终transport测试、6个独立store测试；后续UI预览与桥接变更由定向测试/最终CI补验。
- 双设备产品链路：`PGOS-Product-Integration-1.xcresult` 10/10 PASS（4端到端 + 6 store），两个独立磁盘库、同account/dataset不同generation；乱序/重复、并发全parents解决、真实合成PNG闭合、tombstone依赖与旧版本防复活、草稿阻投影后的重放。不是两台真实设备云测试。
- 冲突可读预览：9/9 codec PASS，包含23聚合无传输ID/hash/raw JSON、正文差异与资产冻结金额，不以当前资产名称改写历史。
- UI smoke：`PGOS-Product-Smoke-1.xcresult` 6/6 PASS（既有5项全部通过，新增默认关闭/启用确认后取消不上传）；同轮codec9/9 PASS。
- 最终CI和最终签名产物绑定：交付收口时补充，不预先判通过。

原始本机日志和xcresult只保留本地；公开摘要不包含账户ID、设备UDID、签名profile或私人证据。编译中的既有warning不隐藏。各测试套件是不同阶段快照，不能把计数相加声称所有最终源码都受同一轮验证。

## 独立审查与修复

- 因果图独立复核：current head先于依赖、删除不等待解除的依赖、唯一最近共同祖先仅作不完整预览，预算整体拒绝。
- 核心持久化/身份/ACK：完整container/environment/account/dataset/generation校验、每次await后的session fence、旧ACK不吞新版本，所有原图/chunk ACK完成才收口；inbox先持久再checkpoint。
- serverRecordChanged幂等：同ID同内容的服务端重放先持久后精确ACK；CKAsset在冲突返回中不带URL时只读取得精确record，前后核对同容器账户；不同内容不当普通LWW覆盖。前后采样不声称证明未发生不可观察的A→B→A。
- 所有真实业务save入口、fresh context、restore baseline、`.none`、历史V16定义、工程引用经独立检查。device reminder journal与验证库不进入同步wire。

## 明确未验证/限制

真实CloudKit双向收发、真实账号切换/后台推送、完整故障矩阵、Production schema/容器实际写读、TestFlight及App Store均 NOT_RUN。G1手机验收和Mac CK_2非阻塞例外保持原范围。

协议仍有有界容量：单manifest64KiB、payload128MiB、原图25MiB、直接依赖1024、因果图默认10000 manifests等。超过限制的合法本地事实保留并持久暂停发送（1025行合法净资产快照有正反测试），**不宣称该数据已同步**；更大数据的协议扩展/历史整理尚未交付。跨UUID自然键冲突及不可读/缺失版本采取整体不发布并保留本地，不能把“保留”描述成已自动解决。恢复仍创建隔离dataset，不复用旧账户/token/ACK。
