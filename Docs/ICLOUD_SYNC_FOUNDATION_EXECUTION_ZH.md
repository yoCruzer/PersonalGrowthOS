# 2026-11-08 接续：正式导出核验与隔离SDK准备

Owner已提供Development/Production导出和相应截图，本机核验仅Users7字段、候选缺3类型/11字段；不再等待重复导出。原件保存在仓库外私有目录，公开来源摘要和结构结论。正式App能力关联仍待只读确认。新增严格schema审计、带证据绑定的内部Development SDK适配准备和无网络入口的锁定host，已完成本机实现与独立复核；固定候选远端验证进行中，详见[本轮结构审查](ICLOUD_SYNC_FORMAL_SCHEMA_REVIEW_ZH.md)和[证据](Evidence/iCloudSyncFoundation/20261108/README.md)。P0/P1/P2仍未通过，真实容器操作与发布边界不变。下文是既有交付历史，其中“尚待导出”状态已被本段替代。

---

# iCloud 后续连续开发交付

2026-11-07，Asia/Shanghai。工作树 `/private/tmp/PersonalGrowthOS-icloud-foundation`，分支 `codex/icloud-sync-foundation`，Draft PR [#17](https://github.com/yoCruzer/PersonalGrowthOS/pull/17)，base 为 `codex/icloud-sync-g1`。原项目未提交的工程、本地化与xcodecloud文件不动；未改写G1历史。

## 授权与当前位置

Owner新授权允许后续完整开发、独立子代理、普通推送与Draft PR；取代旧G1仅实验/批次停止的开发限制。G1仍按手机侧验收范围收口，Mac CK_2是接受的非阻塞例外，原失败和未覆盖故障矩阵保留。此次没有要求手机重跑、卸载或清空SyncLab，没有切换系统账户或读取日常私人数据。

依赖顺序是：正式wire/容量/身份准备 → 正式Development/P0真实核验 → 精确Production差异与另行批准后的P1/P2 → G2追加schema与所有写入口同事务outbox → G3/G4领域、媒体和系统验收 → 另行发布授权。此次完成不依赖外部门禁的实现与验证，**不是产品同步已完成**；不能因为包测试通过就绕过正式P1/P2接入全部39实体。

## 实现和修复

- 新增独立 `Packages/SyncFoundation`，不链接正式App：不可变逐mutation记录、typed对象和dataset身份、canonical manifest、逻辑删除、媒体清单、局部分区身份及epoch栅栏、实际CloudKit CKRecord/CKAsset codec。
- 初版每mutation单payload候选16MiB经真实领域容量反证后继续修订为有序分块。每块4MiB、整体128MiB候选预算，完整manifest绑定所有块顺序、长度、逐块hash及整体hash；源descriptor在准备前确定，原件变化时拒绝返回可发布manifest。原图保持25MiB上限，支持9图清单，不压缩或截断原件。源文件、staging lease和持久化仍由后续集成实现。
- 实际V16合法万行Unicode净资产快照编码49,190,297字节，通过领域validator及完整decode等值；初版16MiB确实无法承载。大payload必须分块，不能靠简单小JSON万行样本证明产品极值通过。候选预算不是所有任意Unicode输入都能同步的无限承诺，超限必须保留本地已保存事实并明确报告。
- `SyncSchema` 从实际SDK记录枚举候选types/fields；重复输出稳定、已有目录拒绝覆盖。输出不是服务器导出或部署差异，不授权写入。
- 生成精确96f产品V16/v12冻结夹具，保存SQLite+WAL+原图、真实ZIP与完整期望值；实际磁盘副本重开/ZIP恢复、2份分享receipt（含已删来源）、净资产历史与草稿逐字段核对。原冻结目录前后hash不变，独立审查只打开拷贝。
- 正式产品窄屏回归修复：HabitOverviewRow省略重复装饰图标，给标题增加36pt宽度。ModuleEntryRow仅支持可选图标，其他模块保持原参数；无字体缩小、测试阈值放宽或业务行为变更。
- 写入接缝按实际服务/save/rollback/恢复/设备日志/Debug夹具区分，见 [G2写入接缝](ICLOUD_SYNC_G2_WRITE_SEAMS_ZH.md)。尚未新增正式schema、迁移或outbox；没有把进程内StorePublication锁冒称数据库事务。

## 验证与证据

证据入口：[本轮证据](Evidence/iCloudSyncFoundation/20261107/README.md)。本机macOS27.0.1 arm64、Xcode27.2(27B52)；产品合成模拟器iOS27.0，远端产品runtime另行记录。

初版提交 `2e68ab2` 原生18/18、独立8/8、iOS17 target编译与CLI正负检查通过；分块候选另记录新源码hash、测试与独立负例，不沿用旧计数。V16冻结生成最终1/1、实际容量probe最终1/1通过。产品修复后本机完整smoke5/5通过，含中英默认/XXXL、最大辅助字号shell、按钮尺寸、计数/导航和重启持久化；本机修复前英文1/1已PASS，未冒称复现CI27.2差异。

失败原样保留：原0e1f747及e57fe35远端smoke均3PASS/2FAIL（短标题42.333>25），release/unit成功；本机生成器首轮错误排除v12receipt、次轮缺import，容量probe错误cwd取消/后续build锁失败；包及独立测试的cache权限/负例SDK类型问题。所有失败与修复后通过分开，测试断言没有削弱。

本轮没有重跑G1真实故障矩阵或占用手机。最终代码的远端结果、精确计数和检查SHA在追加交付节及CURRENT中记录；不能用初版包CI成功表示后续分块版本通过。

## 外部门禁与人工交接

只读核验正式Team `83SKX2PM7B`、容器 `iCloud.com.yocruzer.PersonalGrowthOS` 存在；Development Record Types只显示Users 7 fields。没有查询Records、变更能力、导出schema或打开Production；浏览器并发切换时停止控制。Owner明确选择稍后按清单导出。

[集中只读清单](ICLOUD_SYNC_NEXT_READINESS_ZH.md)：预计5–10分钟，手机前台0分钟、数据线0分钟；核对既有正式App关联，导出Development与Production schema及hash，只读取不Save/Deploy/Import/Reset。不要求第二台iPhone或haha账户切换。没有真实两环境schema，不给出虚构的Production部署批准单。

获得结构导出后先比对已审候选、准备必要正式Development覆盖与签名客户端；P0、P1、P2仍分别保留实际外部门禁。Production部署/写入必须另行基于固定代码和精确差异授权，不能和本次只读动作混为一次默认许可；P3/P4、Archive、TestFlight及发布均未授权/未执行。

## 仍未完成

正式App V16→新同步schema迁移、持久账号/epoch分区、业务+outbox同事务、下载/inbox/checkpoint/ACK调度、asset持久lease及GC、39实体领域合并与自然键去重、冲突UI、实际同步备份恢复与通知/Widget副作用仍未实现。本次codec和内存fence是后续依赖基础；不冒称这些路径已经覆盖，也不把门户未知状态当作通过。

## 最终本机候选复核

分块最终源码：24项包原生测试、12项独立测试全部通过，iOS17 Simulator target编译通过（iOS17运行仍NOT_RUN）。schema升级为独立PGMutationV2/PGOriginalV2/PGPayloadChunkV2、PGSyncV2 zone命名；初版未部署，无服务端旧格式需要迁移，初版代码及证据通过Git/单独目录保留。实际schema hash `6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003`。

源截短/增长的独立6PASS/2FAIL红例已关闭；源码hash在独立快照和最终包之间一致。真实V16 49MB经12块SDK编解码并逐字节重组、整体摘要验证，原文件不变。修复每块Foundation临时对象滞留后，128MiB流式prepare/verify测试进程峰值RSS从170,606,592降到40,058,880字节，4MiB对照44,236,800；完整49MB SDK/CLI为116,523,008字节，分层报告，不把一次本机测量当作所有设备性能承诺。11项自包含独立chunk回归已纳入定向CI，真实V16大输入的第12项保留本机证据。

## 继续推进的正式Development批次准备

在首轮远端验证期间，独立终审指出正式Development批次准备仍可安全推进，故继续完成，未停在小阶段等待Owner。新增同包FormalProbeCore与FormalDevelopmentProbe，实际plan/replay/preflight三命令、固定合成内容和schema绑定、六条SDK检查、失败阶段/命令报告、fd相对目录访问和签名前后产物一致性检查。无CKContainer/网络，独立客户端标识只是候选，未注册/关联/签名。详见[批次准备器](ICLOUD_SYNC_FORMAL_PROBE_PREPARATION_ZH.md)。

完整包34/34（原24+新增10）、iOS17共享核心编译、独立22条CLI正负例及本机并发签名产物替换负例通过，无剩余must-fix。注入签名元数据正例不算真实签名通过；实际SwiftPM产物虽可能有ad-hoc签名，仍因正式身份/能力/profile缺失得到NOT_READY、exit2。初稿损坏PNG、路径误拒绝及构建权限失败原样留证；修复后ImageIO/独立CRC/像素解压均通过。稳定22条黑盒和实际三命令已加入定向CI，时序相关并发用例只保留本机。

源码99ef002的远端定向24+11、产品Release/Unit/Smoke全部成功；原始产物保存在ci-foundation-99ef002、ci-product-99ef002，前一源码2e68也独立保留。新增准备器最终候选的CI结果单列在下一节，没有用99ef002替代。

## 固定候选72f5d3d的远端收口

最终代码 `72f5d3d5950a552068f8cb5d2da88b819a2b3318`，实际PR合并checkout `0af3599c12ec71ba2106c0f287707ed3c59684f0`。定向CI [42388380286](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42388380286) SUCCESS：原生34/34、独立分块11/11、准备器独立22条CLI，实际六条SDK回放与未配置profile产物的拒绝预检均符合预期。原始完整artifact ZIP已保存并与GitHub digest核对，见[最终定向证据](Evidence/iCloudSyncFoundation/20261107/ci-foundation-72f5d3d/README.md)。原生两target分别24+10，独立filter在不匹配target显示0不能抹掉实际11项。

产品CI [42388380258](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42388380258) 已SUCCESS：Release三个unsigned bundle检查通过，Unit599=598PASS/0FAIL/1SKIP，Smoke在iPhone13mini/iOS27.2为5/5PASS，两个测试lane的runtimeWarnings均为空。唯一Unit跳过需隔离32MB HFS+低空间镜像，未向主卷填满数据；Optional extended UI按workflow条件SKIPPED，未冒称通过。完整证据见[最终产品验证](Evidence/iCloudSyncFoundation/20261107/ci-product-72f5d3d/README.md)。此次由仓库PR工作流自动触发，无手动重跑旧失败；产品/测试/工程/产品CI与99ef002逐Git对象相同，但仍按本次实际结果留证。最后只更新文档及证据，不改变已验证源码，不作为TestFlight或发布候选。


2026-11-08（Asia/Shanghai）最终交付：本轮合成证据继续归入开始于20261107的批次目录。独立审查确认没有剩余must-fix，公开证据隐私复核未发现凭据或私人业务数据；原项目三项未提交改动未动。最后提交只含Docs/证据，标记`[skip ci]`，经验证的代码与工作流仍为72f5d3d，未merge或发布。下一实际外部输入为Owner已选择稍后导出的两环境schema与正式App关联；清单不新增手机/数据线操作，也不提前申请不具体的Production权限。
