最新真机首次启用失败及build9修复见[后续证据](first-activation-fix.md)。以下为原build8交付证据，不把已发现问题改写为通过。

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
- 最终源码CI及签名安装包已核验，见下方收口记录；各本机阶段计数不重复累加。

原始本机日志和xcresult只保留本地；公开摘要不包含账户ID、设备UDID、签名profile或私人证据。编译中的既有warning不隐藏。各测试套件是不同阶段快照，不能把计数相加声称所有最终源码都受同一轮验证。

## 独立审查与修复

- 因果图独立复核：current head先于依赖、删除不等待解除的依赖、唯一最近共同祖先仅作不完整预览，预算整体拒绝。
- 核心持久化/身份/ACK：完整container/environment/account/dataset/generation校验、每次await后的session fence、旧ACK不吞新版本，所有原图/chunk ACK完成才收口；inbox先持久再checkpoint。
- serverRecordChanged幂等：同ID同内容的服务端重放先持久后精确ACK；CKAsset在冲突返回中不带URL时只读取得精确record，前后核对同容器账户；不同内容不当普通LWW覆盖。前后采样不声称证明未发生不可观察的A→B→A。
- 所有真实业务save入口、fresh context、restore baseline、`.none`、历史V16定义、工程引用经独立检查。device reminder journal与验证库不进入同步wire。

## 明确未验证/限制

真实CloudKit双向收发、真实账号切换/后台推送、完整故障矩阵、Production schema/容器实际写读、TestFlight及App Store均 NOT_RUN。G1手机验收和Mac CK_2非阻塞例外保持原范围。

协议仍有有界容量：单manifest64KiB、payload128MiB、原图25MiB、直接依赖1024、因果图默认10000 manifests等。超过限制的合法本地事实保留并持久暂停发送（1025行合法净资产快照有正反测试），**不宣称该数据已同步**；更大数据的协议扩展/历史整理尚未交付。跨UUID自然键冲突及不可读/缺失版本采取整体不发布并保留本地，不能把“保留”描述成已自动解决。恢复仍创建隔离dataset，不复用旧账户/token/ACK。

## 最终离线收口修复

最终产物检查发现Apple真实profile的环境是允许集合 `[Production, Development]`、服务是`*`；初版运行资格解析错误地只接受单字符串/数组，虽签名构建成功却会拒绝启用。已修正允许集合解析，保持Debug真机Development编译门，Release/simulator恒拒绝，并用Security API另行核对实际签名是精确Development/CloudKit/正式容器/正式App ID/开发push/get-task-allow。profile允许值没有被当作实际签名环境。实际profile纯只读解析验证通过，未运行云请求。

统一push、前台恢复、本地保存的自动唤醒门；暂停后不会被静默push绕过，用户手动同步仍可重试。启动失败后重试成功重绑push协调器。定向`PGOS-Product-Activation-Fix.xcresult` 17/17 PASS（配置6、store/自动门7、双设备集成4）；纯profile harness 7/7（含仅本地真实profile解析）。

首个远端定向CI [42491119740](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42491119740) 在离线打包步骤失败 `UNREVIEWED_SWIFT_SOURCE`：新因果图源/测试已独立审查但未加入旧打包器的整包hash锁。精确增加这两个已审查hash，原22项未变，实际snapshot24项逐项匹配；未删门禁、未宽化未知源码规则、未重跑Mac云探针。此失败保留；修复后的最终CI另记。

## 签名安装交付（本机私有）

正式App Development build8已由Xcode普通build生成并验签，无Archive、安装或发布。`BuildProvenance.plist`回读源码`a52e24b166cd2c4969dbecf45955924ad6a35b81`、Dirty=false。主App和两个扩展均为build8；有效签名精确包含正式容器、CloudKit、Development、开发push、get-task-allow。profile有效期至2027-11-08（实际安装仍受已登记设备/系统开发者模式约束）；不是实际iPhone安装/启动验收。

- 安装ZIP：`PersonalGrowthOS-iCloud-Dev8-a52e24b.app.zip`，11989852 bytes。
- ZIP SHA256：`347e494f637ec24e7406a6a959dce2f7de35a06dd59b2dda697e77c18d3d9fc9`。
- 主程序SHA256：`dff36d28917ed9fd491cb59a54c51dde0395e0f1f0cc65c7da693ab086893f9b`。
- ZIP解包后：三个二进制摘要一致，`codesign --verify --strict --deep`通过。

包、内嵌profile、完整本机receipt与安装步骤位于Owner本机Development/Builds的`PersonalGrowthOS-iCloud-Dev8-a52e24b`目录，不上传公开仓库。安装会更新同bundle正式App，未自动执行；原SyncLab不改。已查看合成UI截图：同步默认关闭、确认取消后仍关闭，未显示业务数据。

## 最终远端验证（完成）

[Draft PR #19](https://github.com/yoCruzer/PersonalGrowthOS/pull/19)，base PR17，代码`a52e24b`。[定向CI42491840398](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42491840398) SUCCESS：44协议/图、17准备器、21SDK/host原生测试；保留的独立测试和32离线打包检查通过。下载原ZIP的SHA256 `ba1e70c6d905356c00269cdce9b90dc24cfce23c0bb0303fcc23075958d3fd8d`与GitHub官方digest一致，307成员CRC检查通过，24源码pins逐项匹配该提交Git对象。

[产品CI42491840354](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42491840354) SUCCESS：Release三个unsigned bundle；全量Unit **669执行 = 668 PASS / 0 FAIL / 1 SKIP**；Smoke **6/6 PASS**，包括既有5项和新增启用确认取消。Xcode27.0 / iOS27.2 / iPhone13mini模拟器，实际PR合并checkout `384ad041dca4119118d44df00b7e2097cb1ef60c`，三个lane的head均绑定完整`a52e24b166cd2c4969dbecf45955924ad6a35b81`。两个测试lane的runtimeWarnings均为空，不代表没有编译warning。

唯一Unit跳过为`TodoFoundationTests/testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure`：未提供隔离32MB HFS+镜像；没有填满主卷。Optional extended UI按条件SKIPPED，不计入通过。下载三个官方ZIP并逐一核对digest、CRC、environment及测试摘要；完整原件保留本机`/private/tmp/pgos-product-final-{release,unit,smoke}.zip`。

| CI产物 | SHA256 |
| --- | --- |
| ios-release-1 | `d9784ec4153e9c1baa845c8c1a64e03cc909f4d491747baf69b52b30df14a348` |
| ios-unit-1 | `33b876268a0efdcc9328fe141ff7b92107c496f3dae7589d429f6924e5bce073` |
| ios-smoke-1 | `88b4f1e1362b84c87d28362f7178e56707b0d196324d789fe51cc4b23b214f60` |

本轮代码和可安装Development产物已交付。最后收口仅修改文档，使用`[skip ci]`；安装包与验证仍精确绑定a52e24b，不以文档提交冒充重新构建。PR保持Draft且未合并，真实云与Production仍未验收，不再要求Mac探针操作。
