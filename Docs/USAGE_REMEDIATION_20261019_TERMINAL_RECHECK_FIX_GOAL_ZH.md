# PR #13 终态复核限定修复 Goal（TC-01～03）

## 0. 固定输入、授权与边界

仓库 `yoCruzer/PersonalGrowthOS`；唯一OPEN Draft PR #13；原分支 `codex/usage-remediation-20261017`；base保持 `codex/time-investment-v1`（`5a70f0110b151f8a45ac7c33d3f443823b1cff24`）。已审产品/测试 `744e7729f103549184574e99e311ce5c380a4a16`，交付 `d04fbf7f39a6ce77e995202118a0ca78f0d0ccf6`；前Goal `6430a8570ce2d3528c37d491c1252f97066e8da9`。本文件及[配套独立审查](USAGE_REMEDIATION_20261019_TERMINAL_RECHECK_REVIEW_ZH.md)由手机prompt中的 `RECHECK_GOAL_SHA` 固定。

Owner已要求：独立审查提出必要修复时同步提供可执行prompt，并允许较长内容先入GitHub。本Goal只收敛TC-01/P2、TC-02/P2与同组TC-03/P3，不重新开发A–D、不改变产品方向。启动后连续执行核实→修复→定向/集中验证→独立终审→普通commit/push，不在每个内部阶段等待Owner再说继续。

这是规格与新审查交付；尚无本Goal原生测试或产品修复PASS。既有CURRENT顶部READY和PR描述是上轮结论，不能代表本轮通过。接收后先在CURRENT_STATE/CURRENT_TASK顶部追加本轮LOCAL_REVIEW_FIX_REQUIRED/FIXES_IN_PROGRESS及规格指针，保留旧历史；更新INDEX关联，不搬运/删改巨大历史正文。

按AGENTS、Foundation和Development Contract续接原worktree。先轻量核实远端/HEAD/base/祖先和未知改动；有后续有效提交先核对保留，不回退重建、不创建重复PR。文档接收不重跑全量基线。

## 1. 编号与实施原则

TC-01只补RR-01的非open来源；TC-02/03只补IC-02的跨进程责任和成功终态，合并一组实现。前RR-02已认可，不再建立新的raw写者大扫描。O-01仍非阻断UNCONFIRMED。

每组在编码前登记：合法起点、操作来源与真正受影响对象、持久事实/临时UI状态、异步系统边界、重试/重开及相反操作。把主审反例转为真实生产路径测试并尝试反证；若后续提交已经修复或合法前提确实不成立，保存足够明确的源码和原生反证后关闭，不机械照改。不得通过限制原合法输入、改宿主时钟、猜测数据或放松校验“修复”。

## 2. TC-01：从终止祖先应用未来，恢复开放后继

### 反例

复用真V11 nil每日08:00夹具，经过旧f1完成/跳过根A生成B、旧deleteList保留nil但改系列updatedAt；为B建立真实accepted未来notification/alarm。两种等UTC偏移但不同identifier时区（例2026-10-20的Asia/Shanghai和Asia/Hong_Kong）触发当前隔离，B成为retired/native0。保持时刻、渠道、模板值，从已completed/canceled的A实际编辑器应用未来。

当前correctingPolicy只看来源A是否open，导致B接收reactivating=false；等偏移保证applyTemplate不偶然改fireAt/换代。新规则写好，B仍旧G且stopped。

### 修复约束

区分“执行纠正的入口对象”和“应恢复的开放期次”。仅对本次明确恢复所影响的合法开放对象建立有效意图，不能复活来源A，也不能让普通metadata、健康规则futureSeries编辑或已Stop系列复活。原计划/截止、历史事件、源Entry及关联不被改写。取消未确认仍持旧ownership并阻止并行新请求；事务失败保留规则/代次/事件原值；同次成功后的重复提交不反复换代。

### 必要验收

1. 来源open/completed/canceled与相应开放后继边界；completed/canceled分别经真实状态迁移产生，不仅篡改state。
2. 两渠道均覆盖同值/同渠道、等偏移时区；改值/不等偏移对照按影响复用。至少一个终止来源经实际TodoEditorView保存入口，断言B实际native唯一新ID，A状态不变。
3. 取消未确认→纠正→确认恢复，保存失败回滚，磁盘重开，幂等；原RR01主入口和SystemStop普通编辑不复活负例保持。
4. 若需要界面提示，以保留已有“应用未来”合同为先，不要求用户额外改分钟或寻找另一个入口才能完成已明确确认的恢复。

## 3. TC-02/03：失败清理跨冷启动可靠，成功重试反馈一致

### 反例

合法旧08:00→改09:00失败→清理两次仍未确认，当前偏好off持久、Scope中pending/error可见。销毁全部AppShell/Scope（真正模拟进程层次，而非保留同一intents重开sheet），保留UserDefaults和native系统请求，重新启动。当前Scope默认false/nil，根/设置没有恢复清理，形成off但旧请求仍存在且无提示。

同进程另一个问题：pending清理后重试成功返回removed，cleanupPending=false，但failureMessage保留“未确认”，Try Again消失。

### 修复约束

优先最小方案：启动/前台按持久off偏好及两个固定native identifier安全对账，或保存最小device-local清理责任。不能只持久化一条错误字符串，不需要为UI错误自动引入SwiftData Schema/完整通知账本。任何方案必须最终能发现、确认及恢复，且未确认保持可见/可重试；旧请求实际已消失时也能诚实收敛。原操作更新失败可保留历史说明，但清理成功后不能仍显示“目前未确认”。

后台/启动清理必须使用稳定的每渠道意图所有权与同一NotificationMutationGate。每次await后检查最新意图，不能删新B；不得为了清理而请求权限或自动打开提醒，不取消其他类别或未知请求。持久化失败本身要诚实处理，不虚称责任已保存。数据备份不自动迁移此设备的未完成系统清理责任。

### 必要验收

1. daily/weekly：旧native存在、修改失败、实际清理未确认→持久off→销毁整个根owner→保留同一偏好和外部请求构建新App根→自动/明确可达重试→确认无native、正确反馈。不可只新建wrapper共用旧Scope。
2. 冷开时native已无请求/仍存在/首次再次清理失败三分支；观察实际原生客户端替身请求ID和完整启动/挂载调用链。
3. 冷启动清理query挂起时用户新B为同值、异值、明确off；不能误删最新B。当前成功/当前失败、权限已拒绝/未申请、两渠道独立及原共享预算保护。
4. 同Scope与重建后的“清理失败→成功重试”：native0、pending=false、没有当前未确认文案、无死重试入口；历史失败提示如保留应能明确理解/消除，不要求用户重新开启提醒来清错误。
5. 用已有UserDefaults隔离suite/合成测试容器，不碰私人系统通知或用户真实偏好；不增加无界轮询。

## 4. 收敛、证据与独立复核

阶段S-A完成TC-01；S-B合并完成TC-02/03；S-C集中验证与独立终审。顺序可按明确依赖微调，仍是一批授权。

每项先执行有区分力反例，原生红例与夹具/驱动错误分开；修后整方法补验。已有测试和实际源码保持一致，不能让helper结论替代UI入口/最终native/冷重开。不要每个阶段跑全套。收敛后在同一干净产品SHA做一次完整Unit、必要关键UI、Debug与unsigned Release、既有实包provenance/AlarmKit弱链接/用途检查；其余不受影响旧UI按方法/依赖blob说明复用。若之后只改Markdown不重建；如果只改测试需清楚说明哪些证据能复用，不机械重复整套。

由未写本轮实现的reviewer在看到实现者关闭表之前登记自己的反例，审固定diff和未改消费者、原始xcresult/日志及必要真实页面。重点检查来源对象vs受影响对象、sheet寿命vs进程寿命、失败状态vs已确认终态三个边界，不再泛化探索新功能。范围内confirmed问题连续闭环。

保留RR-02二次busy/观察fence/回拨、V01原量/原图、Investment checkpoint/pause/finish/F5、旧迁移/恢复、IR01事件收敛、两渠道取消/Stop/ringing/容量等既有保护，不重做。Linux主审探针只有状态/日期前提验证，不能写入本轮原生PASS。TC新原生反例尚未在主审环境运行。

## 5. 完成与交付

TC-01/02修复或有明确生产反证；TC-03反馈收尾完成；必要原生验证和独立终审通过、无本轮范围未关闭confirmed P0/P1/P2，才恢复READY_FOR_OWNER_DEVICE_GATE。本Goal不要求证明整个App永远没有任何缺陷；未证实、范围外且不阻断的观察应明确记录，而非无限延期。

更新两份CURRENT、INDEX、既有EXECUTION/ACCEPTANCE/REVIEW及PR描述；分别记录最终产品/测试SHA和纯文档交付SHA、实际运行分轮和复用依据。普通commit/push原分支，原Draft/base保持。保留旧19轮/38轮、真实FAIL/SKIP、黑图和新补验，不拼称历史全绿；本机原始证据路径和hash可定位。

D1–D4 NOT_PASSED、AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、CI NOT_RUN保持。不操作私人设备/库，不签名安装、merge、force push、tag、Archive或TestFlight。遇账号/权限、产品变更或真实不可逆风险按Contract升级，其余无需反复问继续。
