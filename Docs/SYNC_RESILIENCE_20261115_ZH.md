# 同步剩余风险修复（2026-11-15）

输入：已发布 1.0 (21) / `321219f`，承接审计分支 `aa3aa20`。Owner 本轮授权处理 K1/K2/K3，并要求保留原始数据、回归通过后提交。继续使用隔离工作树 `/private/tmp/PersonalGrowthOS-release21-audit` 与现有分支 `codex/release-21-risk-audit`，不增加分支，原开发工作树不动。

**当前：`FIX_COMPLETE / CANDIDATE_VERIFIED / NOT_RELEASED`。产品修复 `440197d` 在本机回归后提交；验证摘要维护 `776cc4c` 已通过两套独立 CI，官方产物和源码身份核验完成。后续仅提交交付证据。** 未合并、未签名发行、未发布，未访问真实 CloudKit 账户或日常私库。

## 按风险排序的结果

### P1：跨 UUID 自然键冲突的处理闭环

原触发：两台设备分别创建相同名称/日期的不同 UUID 对象。因果图完整，但全领域重建违反唯一性，导致同步整体暂停且没有可操作的冲突入口。

- 在发布前识别同名标签、同周复盘、同日睡眠、同日起效睡眠规则、重复记录连接/纪念日关联、多个默认参与人、同日净资产快照/多个草稿。把身份冲突状态持久化并在设置中展示候选原文。
- 标签通过明确改名保留双方 UUID 及全部关系；默认参与人只切换默认角色，保留两个人及各自活动/记录。其他重复事实必须逐项确认保留者，才对其他 UUID 写入正常 tombstone；历史载荷与原图不清理，不自动按时间/UUID 选赢家。
- 对保留者也创建后继修订。两端同时选择相反记录时，产生可审查的普通并发版本，而不是把双方都静默删除。
- 核对全部候选 head、当前 dataset/generation、未保存草稿及原始资产，拒绝过期选择；拒绝移除仍被引用的记录，例如净资产编辑草稿所指向的历史快照。
- 所有选择先成为同一事务的 mutation/outbox；完整领域通过校验后才发布。多个冲突逐个处理期间重启/关闭再启用，不从旧本地视图伪造删除或撤销已记录的选择。

本轮仍保留全工作区的完整发布门：存在尚未处理的身份/因果冲突时，保持本地原貌并提示处理，处理完成后继续同步。固定 UUID 的身体参考设置沿用已有同 UUID 冲突机制，不将非法异 UUID 设置当成合法候选。

### P1：恢复工作区再发现与安全连接

原触发：ZIP 恢复有意创建随机 dataset，重装默认指向固定 dataset，云端仍在的恢复工作区无法发现。

- 增加显式“查找已有工作区”，只读取当前构建环境、当前账户的 private database zones，严格匹配 `PGSyncV2-<canonical UUID>` 与当前 owner。展示本机标识，供另一台空白安装核对选择；不猜测最新或第一个 zone。
- 发现不更改 selection、不启动传输。选择前后重新检查账户、请求 token、当前 selection/generation 和 zone 存在性；取消/账户变化/迟到结果不得恢复已撤销的授权。
- 最终存储事务再次检查本地为空、无未保存草稿、无 mutation/inbox/object-state/outbox 历史；有内容或待处理历史时拒绝替换。保留旧 dataset 头，拒绝误激活已有归档身份。
- 选择已有 zone 后仍保持同步关闭，沿既有明确 Enable 同意流程下载。标记 zone 已存在，之后缺失时不能把它当作首次创建授权。
- 合成端到端实际经过 restore commit → 随机 dataset → 发现/选择 → Enable/transport/apply：原文、原图字节一致，无回声 outbox，源端旧工作区与原图保留。

依赖 Apple 既有只读 [allRecordZones](https://developer.apple.com/documentation/cloudkit/ckdatabase/allrecordzones()) / recordZone API，不新增 CloudKit schema。多工作区需通过保有数据的设备标识核对；本轮未实现云端内容预览或将非空本地库直接切换到其他工作区。

### P2：历史容量与反复全历史处理

- 当前 App 使用明确的工作集预算：100,000 修订、128 MiB 编码清单、8,000,000 图遍历步；当前待验证载荷合计最多 256 MiB。基础库默认小预算不变，单修订 wire/资产上限不变。
- 先验证有界历史结构，再验证当前 head / 冲突预览所需载荷与原图。历史清单、已收原始载荷/原图继续保留，缺失的已过时原图不会阻挡更新后的完整 head。`propertiesToFetch` 避免预取历史载荷，入箱投影不加载所有历史原图 BLOB。
- 将阻塞依赖图的逐对象可达性搜索改为迭代强连通分量；共同祖先利用祖先闭包只移除直接父节点，避免深历史分叉的平方级重复遍历。用独立小图可达性真值检验，而非复写实现作为测试答案。
- 真实 10,001 条磁盘回放发现入箱批内 fetch 扫描未保存行的平方级开销。改为持久化查询排除 pending changes、批内显式映射验证重复/身份碰撞；错误批次整体回滚。
- 发送器从持久 outbox 构建受 binding 约束的来源索引，上传时再次核对来源、manifest hash 与 outbox，避免全历史查找及误命中无内联载荷的历史版本。实际验证了编辑后复用旧载荷哈希、发送各记录、ACK 完整闭合。
- 循环检查取消；历史数据先核对身份/摘要及字节预算。没有删除历史或放宽完整性检查来换取通过。

同机合成磁盘用例：旧批内扫描流程 **68.744 s**；优化后相同流程 **4.339 s**；最终增加复用历史载荷的实际发送/ACK 后 **4.912 s**。这是本机合成持久化/投影/发送接缝耗时，不是实际 CloudKit 网络吞吐或所有用户数据规模的保证。

## 本机验证

环境：macOS 27.0.1 (26A434), arm64；Xcode 27.2 (27B52)；iOS 27.0 / iPhone 18 Pro 专用模拟器 `502D3BAF-454D-430F-85FE-A3D0FCFBFE38`。全部是隔离合成库。

| 证据前缀 `/private/tmp/pgos-sync-resilience-` | 实际结果 |
| --- | --- |
| identity1 | 编译失败：SwiftData predicate 捕获模型属性；改为捕获 UUID 值 |
| identity2 | 宿主停在 dyld，未开始测试；中断并重启专用模拟器，保留采样 |
| focused3 | 编译失败：合成 Entry fixture 缺 createdAt；修正必需参数 |
| focused4 | 45/45 通过，身份冲突及工作区连接第一轮 |
| focused5 | 88/88 通过；暴露 68.744 s 批量入箱瓶颈，保留采样；停止命令发出前该轮已正常完成 |
| capacity6 | 31/31 通过；相同容量用例 4.339 s |
| finalFocused7 | 51 原生＋3 中英/暂停导航 UI = 54/54，0 skip，runtimeWarnings=[]；截图已逐图检查新增中文入口/布局 |
| core3.log | SyncFoundation 三个测试 bundle 49＋17＋21 = 87/87 通过，含超旧上限、深分叉、缺依赖、独立循环真值与超新预算拒绝 |
| fullUnit8 | 完整原生 **735/735**，0 skip，runtimeWarnings=[]；实际叶子计数与 summary 一致。低空间在隔离 32MB HFS+ 镜像实跑 |
| restore9 | 此后只补充的恢复原文/原图端到端测试 **1/1** 通过，runtimeWarnings=[]；生产代码与 fullUnit8 相同 |
| release.log | unsigned Release 三 Bundle BUILD SUCCEEDED，主 App production pin；保留既有编译 warning，不声称零 warning |

原生命令：`xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -jobs 3 -derivedDataPath /private/tmp/pgos-release21-dd -destination 'platform=iOS Simulator,id=502D3BAF-454D-430F-85FE-A3D0FCFBFE38' -parallel-testing-enabled NO -collect-test-diagnostics never <only-testing 选择> -resultBundlePath /private/tmp/pgos-sync-resilience-<轮次>.xcresult CODE_SIGNING_ALLOWED=NO test`。选择分别为 SyncProductIntegrationTests/SyncCoordinatorTests（focused4、finalFocused7）、另外含 DomainCodec/Installer/CommitBoundary/Persistence（focused5）、Coordinator＋超万条单例（capacity6）、整个 PersonalGrowthOSTests（fullUnit8）、新恢复单例（restore9）。finalFocused7 的三个 UI 为 AppLaunchSmokeTests 中 ChineseConsentCompletionAndProgress、SettingsStartOffAndRequireExplicitConsent、PausedSyncKeepsEveryTabAndSettingsOperable。

基础包：`swift test --package-path Packages/SyncFoundation --scratch-path /private/tmp/pgos-release21-swift -j 3`。Release 命令与产物摘要见 [local-release-verification.json](Evidence/SyncResilience20261115/local-release-verification.json)。摘要、原始结果树摘要/路径、逐类计数和输入文件 SHA256 见 [证据目录](Evidence/SyncResilience20261115)。

## 剩余边界（不包装为全部消除）

- 历史整理/安全 GC **未实现**；100,000 是显式工作集预算，不是无限历史或十万条真机性能验收。旧客户端仍受其 10,000 上限约束，超过旧限需升级相关设备；没有改写旧客户端或删除历史来适配。
- 单聚合仍受既有 1,024 dependencies、64 KiB manifest 等 wire 上限约束；合法超大净资产聚合仍会保留本地事实并保护性暂停。这需要单独版本化协议方案，不通过破坏关系校验解决；现有正反用例继续通过。
- 有引用的重复事实不能直接丢弃；未处理冲突期间保持完整发布门。云端内容预览、非空本地跨工作区合流未实现。
- 真实双设备/不同客户端版本互操作、真实 CloudKit zone 发现、后台/通知、真机大规模内存、发布包签名验收为 **NOT_RUN**。本轮没有真实云操作、Production schema 部署、Archive、TestFlight/App Store 发布。
- 没有启动子代理；依据当前禁止主动委派的指令，以独立真值测试、人工代码复核与后续 CI 作为本批验证。


## 首次 CI 的真实失败与修正

[基础包 CI 43701959742](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/43701959742) 的 native、保留分块/SDK/schema/目录等独立回归步骤成功，最后 locked-host packaging 因 `UNREVIEWED_SWIFT_SOURCE` 拒绝。官方 artifact SHA256/ZIP CRC 已核对，不能把整轮称为通过。

复核 `Scripts/FormalDevelopmentHost/README.md` 要求后，确认白名单差异**恰好两项**：本轮修改的 `CausalProjection.swift` 及其测试。实际源码与独立真值/回归均已审阅，只更新这两项摘要；其余文件、Package.swift 固定摘要、权限/路径/签名/live 阻断逻辑均未改变。不是取消校验或盲目刷新全清单。

本机 `package_locked_host.py` 未签名打包通过；`verify_packaging.py` **32/32**，包括未审查源码/清单、符号链接、live 参数拒绝、真实缺 profile/identity 的 NOT_READY。无开发签名、无 CloudKit 调用。初次验证因假定旧 SwiftPM 可执行文件目录失败；改用实际 `out/Products/Debug/FormalDevelopmentProbe` 后通过，原失败保留。详见 [精确变更与验证](Evidence/SyncResilience20261115/locked-host-pin-review.json)。

App 生产代码及测试与已通过的本机回归一致；干净 Release 绑定 `440197d` / Dirty=false，见 [干净构建证据](Evidence/SyncResilience20261115/local-clean-release-verification.json)。`776cc4c` 仅更新上述两项验证摘要与文档，App/基础包生产源码及测试与 `440197d` 一致。新 CI 已独立完成，详见下节。


## 最终独立 CI 与交付边界

验证候选 `776cc4c36ef5c82d66ebf546edadc07f33d581a4`：

- [iOS regression 43702571587](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/43702571587) **SUCCESS**：unsigned Release 三 Bundle；Unit **735 PASS / 0 FAIL / 1 SKIP（共 736）**；Smoke **8/8**。Unit/Smoke 的 `runtimeWarnings=[]`，原始测试树的叶子计数与 summary 一致。
- CI 唯一跳过 `testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure`，本机 fullUnit8 已在隔离 32 MB HFS+ 卷执行通过，未用跳过替代验证。本机共覆盖最终 736 个不同原生用例（完整 735＋后补恢复 1）。可选扩展 UI 按工作流条件未运行。
- [Sync foundation candidate 43702571928](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/43702571928) **SUCCESS**：87 个测试、32 项 locked-host 打包防护检查通过，相关离线独立回归步骤成功。
- CI iOS 环境：arm64、Xcode 27.0 (27A266a)、iOS 27.2 模拟器 / iPhone 13 mini。跨 UUID 原文/关系保留、相反选择、恢复原图无回声及超万条历史用例均通过；超万条用例在该远端环境约 11 s，不能与本机耗时直接视为相同硬件对照。
- 四份官方 ZIP 已核对 API 公布的 SHA256、字节数与 ZIP CRC；三个 iOS 环境文件及基础包 `checkout-sha.txt` 均绑定实际 merge checkout `be621a04672d4e5ca27502d5e89bf5257d0daccf`。读取实际 Git 对象后，完整 tree 与候选一致：`7ea6ed214896e3cd61d70974909ede34e2b9b9e3`。216 项输入 SHA256 再次核对无漂移。
- 首轮源码 `440197d` 的基础包失败及旧 iOS 被新提交替代取消的记录保留；不用它们声称最终通过。最终结论来自上面的新运行。

完整摘要、产物 ID/摘要、测试源文件摘要及源码树证明见 [ci-final-verification.json](Evidence/SyncResilience20261115/ci-final-verification.json)，Unit/Smoke 原始 summary 同目录保留。原始日志、官方 ZIP 和结果树保留于 `/private/tmp/pgos-sync-resilience-evidence`；本机 xcresult 仍保留。专用测试模拟器已关闭，低空间镜像已卸载，合成库不删除。

[Draft PR21](https://github.com/yoCruzer/PersonalGrowthOS/pull/21) 承载本批交付，继续使用原审计分支。原主工作区四项未提交路径保持，未增加清理或触碰真实数据。停在代码审阅/发行验收边界；真实双设备与签名发布等 NOT_RUN 项仍按上节保留，不将模拟器与离线接缝测试包装成真实云验收。
