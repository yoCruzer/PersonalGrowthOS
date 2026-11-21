# Build 21 分支整理与风险审计（2026-11-15）

审计产品基线：`321219f61fd2dedf3be69d6f49c3af23896cccd4`（已发布 1.0 (21)）。工作分支 `codex/release-21-risk-audit` 从发布交付 `a58848f` 创建；其与产品基线仅存在文档、证据及 Xcode Cloud manifest 差异。原主目录未提交修改保留。

## 分支整理

已将本地/远端 main 从 dd09975 快进至 a58848f；无重写历史。清理前完整引用备份：`/private/tmp/pgos-release21-evidence/branches-before.bundle`。以下34条远端分支均经 merge-base 验证为 main 祖先，删除不会丢失提交；名称和SHA可用于重建。首次远端批量删除/关闭19个历史PR/PR18换base请求被自动审批拒绝；Owner随后明确确认完整范围。已原子删除以下34条远端分支，关闭PR #1–#17、#19、#20；独立PR #18保留并改base至main。远端40→6条（尚不含新审计分支）；本地原15条＋新审计分支→8条，删除8条已吸收分支、清理失效worktree登记，3个干净旧工作树转detached并保留文件，5个脏工作树原样保留。

| 已删除远端分支 | 原SHA |
| --- | --- |
| `codex/app-store-free-release-20261110` | `a58848f68484cf3bd85af8bf78c388cf0ce4b6ce` |
| `codex/external-capture-v1` | `c5a3c0ac859efc3ffa4e5d9f77909ec43565c871` |
| `codex/household-net-worth-v1` | `96f72339a1a3082c43018e06d6115dd93df1df97` |
| `codex/icloud-product` | `4ec39f7435812f0ad891b846f527e6d55c497409` |
| `codex/icloud-sync-foundation` | `07c1bcff2d2fae1f1a2d17271e36266aadb97d6a` |
| `codex/icloud-sync-g1` | `e57fe3503995771a89754fbc4077ea16627c15be` |
| `codex/icloud-sync-v1-audit` | `304a91984f17efc2c61b179f0a9e85a14ba87d95` |
| `codex/important-days-v1` | `5614246f98ae63732ccd4fd8a6b66f4a425336f2` |
| `codex/quiet-wins-on-d72` | `20d315a62179ad29a6cbcf76c33c11638412e54e` |
| `codex/sleep-routine-v1` | `ad0720ad743f495ac6f2ee3e97b16577266351db` |
| `codex/time-investment-v1` | `5a70f0110b151f8a45ac7c33d3f443823b1cff24` |
| `codex/todo-v1-personal-actions` | `d72c016dd34c8114cf44744d0e061b95bd312091` |
| `codex/usage-remediation-20261017` | `5827c657095945aff30b2250b20bae104c7b0357` |
| `docs/foundation-consistency-v0.2` | `ce18ed36ce4a4866e36ab15d4b55eab4a0d410dd` |
| `docs/v1-autonomous-governance` | `a750d00ac914cdab16fc9418a39771c9bfb27676` |
| `feat/s0a-project-bootstrap` | `2bf1be85c01d8d96af035a12684bd2d98c7f183e` |
| `feat/v1-autonomous-build` | `2e31e8a753005f8bb40bce348820529775aa2e9d` |
| `feature/build8-habit-analytics-dashboard` | `ae8f7cb6577f2d1bc479471bcd98d6f437670210` |
| `feature/build9-today-entry-followups` | `ae14f107f7eebb89a1549e00de3d941e6a996281` |
| `feature/usability-s2-review-loop` | `1a1f6bb6d4b95470a7add37d15c5cfdbc5edd0ed` |
| `feature/v1-completion-push` | `19475fe0830d9a2c8ceff4f27adc63ed4ecab7a7` |
| `fix/build6-owner-feedback-round1` | `c15513f2389d01f28c12ba351933580b37afe4b7` |
| `fix/build7-owner-feedback-round2` | `95076bf5c2a86122fbd327903d80bccdfb8c768d` |
| `fix/v1-device-smoke-round1` | `dd09975d3a3736b24f8646fa4f197cc883ab1796` |
| `plan/household-assets-v1-goal` | `86c1f4e8d645ea865db1281cca0290ee99128ffa` |
| `plan/household-net-worth-v1-goal` | `fb9cb83dc29b02897183d90c84c84055a037f957` |
| `plan/important-days-v1-goal` | `3365561c5888701ce662ac6c8655ad1629ded6d0` |
| `plan/s0-execution-foundation` | `1eed293a4860bf08ea2105bed076c3db956db642` |
| `plan/s0a-task-definition` | `b14bde742a187a29cc8e511c375fb0d25e07941e` |
| `plan/sleep-routine-v1-goal` | `1bed2f46b08c547d52e1ca2f28d74ac0f6696003` |
| `plan/time-investment-v1-goal` | `72ee8bdf954a5628806db867682a6b021e63545b` |
| `plan/usage-remediation-20261017-goal` | `68373d4edf10cff8ca3e212b9ff10a28e6da9c73` |
| `plan/v1-implementation-foundation` | `c8d82d27e546f9fa3297d70c10efaef94fca990e` |
| `test/v1-device-validation-round1` | `2ea01741f4fd36462ed3f2d36c06558958d47b1c` |

保留：main、gh-pages、codex/icloud-formal-execution-guard、plan/icloud-production-incident-20261109、plan/important-days-v1-review-fix-goal、plan/sleep-routine-v1-review-fix，以及本次审计分支。关闭已吸收的PR #1–#17、#19、#20；独立PR #18保留并改base至main。存在未提交改动的本地工作树保留；不清空或删除私人数据库。

## 本轮审计边界与验收

围绕持久化/迁移、备份与媒体完整性、同步因果与身份、并发/取消/草稿保存、提醒/Widget消费者、时间语义、隐私与性能进行代码追踪和风险驱动回归。已确认缺陷须有红测和修复后正负例；最终完成相关集成、完整Unit、关键UI、Release构建并记录实际命令和未执行限制。修复不改历史Schema、备份格式或发布标签，不触发商店发行。

## 已复现与修复

### A1 / P1：界面值草稿覆盖后台同步后的新内容

EntryEditorView/TodoEditorView把用户输入保存在SwiftUI @State，`mainContext.hasChanges`仍为false。远端投影可成功提交新正文/任务；用户随后保存旧草稿，会把远端变化变成新本地后继版本，因果图本身没有冲突，因此不能依靠云冲突界面挽救。磁盘双库红测已复现Entry正文丢失（含技术时间完全相同）及Todo标题回退；产生了错误的本地outbox。

修复：Entry编辑时保存独立值快照；保存前在发布锁内用新ModelContext核对，变更/删除拒绝且保留草稿，不触碰媒体。Todo编辑时保存完整TaskTransfer，保存前及事务内核对持久值，编辑用新context；已有staleTask文案沿用。Habit/Goal/Weight/WeeklyReview/ImportantDay五个旧式表单补`SyncEditorBaseline`，随草稿读取同步发布指纹，Save在MainActor上先核对再同步执行服务，无await间隙；远端删除/同钟变更可检测，无关对象变更不误拦截。并按对象ID读取持久值，直接核对初始化草稿的实际对象，避免旧缓存被绑定到新指纹（查询可返回新值而原对象仍旧；因此不能用同context再查询代替对象比对）；周复盘远端删除不清空未保存文字。两种新增提示均有中英文。Sleep/Investment/NetWorth已具revision/fresh-context保护，本轮不重写其规则。

验证包括：旧草稿拒绝、远端新正文保持、无错误outbox、远端因果删除不复活、无关远端编辑仍可正常保存；Todo重新读取并人工合并原草稿后可成功保存。不是自动内容合并，不改时间戳或Schema。

### A2 / P2：远端提交绕过业务消费者，提醒/Widget/缓存滞后

`SyncDomainInstaller`刻意不产生副作用；原coordinator保存后没有调用模块发布。用户在另一设备修改/完成待办后，本机已排提醒可能持续存在；重要日子的Widget可能展示旧内容；睡眠和时间投入的显式缓存可能长时间不刷新。红测证明已成功落库的远端Todo不会发送提醒消费者实际订阅的事件。

修复：只对真正提交且发生业务变化的聚合发布Todo、ImportantDay、Sleep事件及InvestmentChanges `.all`。发布发生在数据库事务成功且释放StorePublication锁之后。Widget接收路径改为新context，避免读取缓存实例。缺件/冲突/失败/精确重放不发布。既有消费者继续负责权限与设备提醒，不把云端数据写入当作新授权。

验证：磁盘写入先于事件；事件回调可重新获取同一发布锁；缺件不发、完整后只发一次、重复重放无回声；时间投入缓存版本增加并实际读到新参与者，重放不重复刷新。完整提醒回归另行运行。

### A3 / P2：媒体预检与实际复制之间变化，导致完整性元数据错误

MediaStore原先在复制前读取源大小，复制后计算图片哈希/尺寸，却把旧大小保存到ImageMetadata。文件提供者替换/扩展源文件会使byteCount与真实原图不一致，后续导出/同步校验失败；复制前的小文件还可在复制后超过25MiB限制。两项红测分别复现4096字节图片使用旧长度和超过25MiB仍发布。

修复：复制后从App私有staging核对普通文件类型和上限，最终长度与哈希都取同一已复制数据。非法文件沿既有回滚清理，不发布原图。使用独立读取原图字节作为断言，不以实现返回值自证。

## 多维审计覆盖与边界

| 维度 | 检查与证据 | 结论/限制 |
| --- | --- | --- |
| 数据持久化/迁移 | AppContainer、PersistenceFoundation；历史V7/V8/V10/V11/V16 fixtures、保留副本/WAL/低空间/失败重试测试 | 历史schema与主库身份未改；不读取私人库 |
| 备份与媒体 | ImportExportService、TransferModels、ZIPArchive、MediaStore；格式/CRC/路径/重复ID/事务回滚/取消测试 | A3已修；全量覆盖旧包及媒体往返，真实外部文件提供者未验 |
| 同步身份/因果/重放 | SyncPersistence/Coordinator/CloudTransport、SyncFoundation；双磁盘库、精确ACK、缺件/依赖/冲突/账号代际检查 | A1/A2已修；无真实CloudKit网络或账户操作 |
| 并发/取消/消费者 | StorePublication与PhotoInputSession、ShareInbox；陈旧回调、编辑、恢复/导出互斥和通知发布时间 | 新Entry编辑媒体过程纳入发布锁；既有取消/共享导入回归保留 |
| 时间/重复/数字边界 | TodoRecurrence、SleepRange、Habit/WeeklyReview/Weight、NetWorthMoney | 全量包含DST、民用日、时钟回拨、金额溢出/CSV转义；不改变产品日历语义 |
| 隐私/本机授权 | 同步opt-in与realm隔离、脱敏诊断、Widget本机desktopVisible、通知/AlarmKit权限路径、NetWorth遮挡/CSV | 不增加外部网络、权限或数据上传；gh-pages网站分支保留 |
| 性能/资源 | 因果图步数/大小上限、40MiB分块、五年时间投入、QuietWins有界读取；native suite | 已有限额依旧是限制，未声称长期无限规模支持 |
| 发布/版本溯源 | 321219f、发布tag、a58848f差异、main快进与完整bundle | 只修源码，不移动发布tag、不改号、不上传新包 |

## 保留的架构风险（不冒称本轮消除）

- **同步历史容量**：当前因果投影默认最多10,000 manifests/32MiB编码/2,000,000步。历史不可变且保留所有revision及原图lease，达到阈值会保护性暂停；复制/验证历史原图也会增加长期磁盘和CPU成本。现有`testLegalInventoryBeyondDependencyLimitRemainsDurableAndBlocksSender`验证本地内容仍保存，但不是长期压缩/恢复方案。需要独立设计兼容的历史压缩/分区和可恢复协调，不能简单取消资源上限。
- **跨UUID自然键冲突**：两设备独立创建同一标签/民用日等可能被唯一性/全图校验保护性拒绝，停止正常同步而不是静默合并。原始数据保留，但当前UI不能解决所有此类冲突；自动去重会涉及用户身份与关系重写，未在本轮猜测处理。
- **ZIP恢复新工作区再发现**：恢复故意建立随机独立dataset，防止旧云工作区覆盖恢复内容；重装后的默认dataset发现机制不能保证自动找到该恢复工作区。现有K1保留，需显式工作区目录/选择协议。
- 新表单校验主要覆盖后台同步与本轮两个已复现数据丢失入口，并不构成所有未来写入者的通用MVCC。真实双设备、后台系统调度、设备通知/AlarmKit/Widget、发行签名/商店包安装均NOT_RUN；不把合成测试当这些门禁通过。

## 实际验证

环境：本机arm64、macOS27.0.1(26A434)、Xcode27.2(27B52)、iOS27.0隔离模拟器`502D3BAF-454D-430F-85FE-A3D0FCFBFE38`。日志/xcresult位于 `/private/tmp/pgos-release21-evidence/`；摘要及源码hash保存在本目录Evidence/Release21Audit20261115。首次沙箱内simctl/远端读取不可用，获执行权限后正常；没有破坏性恢复。

| 运行 | 实际结果 |
| --- | --- |
| baseline-sync | 原产品双库集成6/6 PASS |
| red-media-events | 3测试均FAIL，5断言：媒体长度/上限及Todo事件缺失 |
| red-stale-draft | 1 FAIL/3断言：正文被旧草稿覆盖、产生错误outbox |
| red-todo-draft | 1 FAIL/3断言：任务标题被旧草稿覆盖、产生错误outbox |
| green-initial | 编译失败：新增测试actor闭包的throws推断，已改显式do/catch，未改产品断言 |
| green-expanded | 99执行：97PASS/1FAIL/1SKIP；唯一失败为新增Sleep空值非法夹具；SKIP为隔离低空间卷当时未挂载 |
| green-publication | 修正合法Sleep夹具后1/1 PASS，未改标前轮全绿 |
| sync-foundation | SwiftPM三个测试bundle合计82/82 PASS；含40MiB分块和因果/身份边界 |
| full-unit | 724/724 PASS，0SKIP，runtimeWarnings=[]；含独立32MB HFS+真实低空间卷（已卸载）。后续缓存打开/周复盘UI边界改动由最终回归另行覆盖 |
| release | 首轮unsigned Release BUILD SUCCEEDED；最终补充边界后需增量核验 |
| affected-ui | 11执行：10PASS/1FAIL，runtimeWarnings=[]；Todo重复转换提示在展开后的Form下方，补有限滚动，原断言保留，滚动前截图证实位于视口下方，定向复验通过。其余10项含真实Files恢复通过 |
| final-unit | 724执行：723PASS/1FAIL/0SKIP；新增“已持有旧对象再打开编辑器”断言复现查询指纹与原对象脱节，已改按ID核对原对象并定向通过；A保存不重发旧B通过 |
| cache-and-ui | 14/14 PASS：13双库集成（含旧对象/删除/重开正例）＋原失败Todo UI；原断言不变 |
| verified-regression | 729/729 PASS = 724 Unit + 5 UI; 0 SKIP; runtimeWarnings=[] |
| release-verified | 最终产品源码unsigned Release成功，App/ShareExtension/Widget三个Bundle完整；本机默认1.0(12)，与云发行1.0(21)按既有台账区分，无改号 |
| provenance-test | 现有版本溯源脚本的clean/dirty、CI SHA及不合法输入测试PASS |\n| remote-ci | Xcode27.0 / iOS27.2 / iPhone13mini：Release成功；Unit723PASS+1SKIP；Smoke8/8；全部必需门禁SUCCESS |

源码候选已提交并普通推送：`d1f8c76865548ce23a41231863dd83f6fcf24f17`，新 [Draft PR #21](https://github.com/yoCruzer/PersonalGrowthOS/pull/21) 基于main。远端现在7条（含审计分支），历史独立PR18与新PR21共2个打开的PR。独立 [CI 43695200124](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/43695200124) 整体SUCCESS：Release成功、Unit723PASS/0FAIL/1SKIP、Smoke8/8，runtimeWarnings均为空。CI低空间跳过由本机真实卷覆盖；optional extended UI按工作流条件未跑。三个官方ZIP摘要/CRC、测试叶子计数及checkout 615a9d6完整tree与候选一致均已核验。本批门禁完成，后续提交仅文档/证据，不重跑未变源码。没有新版本发行授权或执行。


## 证据阅读与下一批边界

- [最终本机摘要](Evidence/Release21Audit20261115/verified-regression-summary.json)、[命令与日志哈希](Evidence/Release21Audit20261115/local-runs.json)、[源码哈希](Evidence/Release21Audit20261115/final-source-sha256.json)、[CI源树对齐](Evidence/Release21Audit20261115/ci-source.json)。
- [Todo提示滚动前截图](Evidence/Release21Audit20261115/todo-warning-below-viewport.png)说明测试为何需要滚动；提示、非法保存、转换身份与唯一后继的断言全部保留。
- [本机Release三个Bundle](Evidence/Release21Audit20261115/release-bundles.json)未签名且构建在提交前启动，嵌入Git元信息为a58848f/dirty；产品输入与d1f8c76的改动哈希完全一致。该构建不等同已签名发行包。
- 后续发布验收包括真实双设备传播、系统后台调度、通知/AlarmKit/Widget及实际发行包。历史容量、身份冲突、恢复工作区发现另立协议设计批次。本轮没有上传、送审或发布新版本。
