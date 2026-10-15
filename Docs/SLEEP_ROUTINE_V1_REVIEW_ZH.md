# PR #11 R1–R3 限定修复 — READY_FOR_INDEPENDENT_REVIEW（2026-10-15）

批准输入 `9e9e29564565a3b6396dc51bb179c29f71bdc726`，起始交付 `5f7dc3eeba4d159d72e03029f487cf67bf77ab1a`。沿原worktree、`codex/sleep-routine-v1` 与[原Open Draft PR #11](https://github.com/yoCruzer/PersonalGrowthOS/pull/11)，base保持 `codex/important-days-v1`。五份输入原样导入，manifest三个SHA-256逐项核对；探针/旧输出未修改、未执行，不是App测试。

最终产品/测试 **`9da1ce8758d868145e9b5690611634ccd292e469`**；最后生产 `f235d9210bf2bb2a9226fda6156d803c4010cc36`，后续仅R1 UI查询歧义修正与更强分布断言。本批交付只再更新五份交接Markdown，精确delivery SHA见Git/远端PR head及 `/tmp/pgos-sleep-r1-r3-evidence/final-delivery-proof.json`，不写自引用hash。

R1：Workspace先完整读取局部records/goals，再同一MainActor回合发布事实与同一真实评价时刻；回顾与绘图/评分来源统一从最新snapshot按筛选意图重算，返回/前台/跨日推进真实时钟。未钳制FilledAt、未删未来/回拨保护。实际UI在原回顾内修改两时间和感受立即保持1/1/1及评分1；评分来源改为很好后原较差分组即时为空、新分布1；绘图来源清起床立即变1/0/0，切30天保持归属。晚补/回忆、备注/no-op、回拨与字段证据对照保留。

R2：真实SleepService仅在rules空且cutoff=nil时no-op。三次初始关闭保存仍零规则，首次开启今日生效并磁盘重开；UI关闭保存→开启今日→重启保持通过。已有真实nil规则不清洗；后续修改/关闭、未来待生效规则、回拨/跨时区原测试保持。

R3：每次add成功即保留接受元数据，generation只门禁UI状态；成功接受后到期不以末pending缺失误报失败，elapsed不声称系统已显示。明确取消与失败remove尽早pending复核，防止后续批次跨旧fire锁住真正提前取消日期；未来missing仍failed并移除未到期台账。旧plannedFires键及Double格式未改，重启兼容。替换在旧fire前成功确认可更新；成功返回已跨旧fire时保守保留旧elapsed并撤销较晚新pending，防止重复，不伪造准确接受/实际递送时刻。聚合仅统计真正未来scheduled，全部到期时elapsed/0/nilcoverage；真实失败、拒权、容量优先级保留。

唯一独立只读Reviewer为本轮新session `/root/sleep_r1_r3_reviewer`，未继承实现者历史，不改代码/文件/PR、不运行测试或构建。先独立读取固定Goal、归档报告/探针/输出/manifest与必要上下文，区分旧Linux移录探针与本机生产证据。主实现者执行所有测试；Reviewer直接核对diff、原日志/导出摘要/截图与实际bundle plist。

独立发现的额外R3同类时序：失败remove仅末尾确认，别的add跨旧fire时锁住真正提前取消。Red2实际0/1、2断言红，f235d92仅失败remove后立即pending查询修复；Green2全部41Unit通过。R1的两次扩展UI失败分别经真实层级确认Tab遮挡与Unknown查询歧义，仅正常滚动/限定查询，断言未弱化；初次直接编辑的真实红与绿色样本结果均保留。

独立Reviewer固定9da1ce8758d868145e9b5690611634ccd292e469完成代码/原始反例/分轮日志与关键PNG、两实包plist终审，R1–R3关闭，无未关闭已确认范围内P0/P1/P2。其本人未运行测试或改实现。 原始run与固定SHA/失败/警告及未执行边界见[本轮执行](SLEEP_ROUTINE_V1_EXECUTION.md)，不是把旧审查“当时无发现”改写为发现过这三项。归档四文件及新Goal逐字不变，不计为App测试。

下一边界是外部限定复审；内部审查完成不等于设备门禁通过。后续历史原样如下。

---

# 睡眠与作息 V1 独立审查

Reviewer：真正独立只读 Agent `/root/sleep_reviewer`，同一 Reviewer 分阶段复审。Reviewer 未修改实现，未运行构建/测试；主实现者运行，Reviewer 核对原始 diff、日志及可读的 xcresult/截图。没有第二个实现者，也没有并行 Xcode 队列。

## 首轮：04b34ba4416cf4065c1c5c3cb68958cb9284f8e5

Reviewer 完整读取固定 Goal/设计及权威项目上下文，独立检查生产路径，确认无 P0/P1，提出五项必选路径 P2：

| 项目 | 具体反例 | 限定修复与反例 |
| --- | --- | --- |
| R1 历史目标 | 15 日设目标，回拨到 14 日时覆盖已有 15 日规则 | 实际观察时间证据阻止已知回拨修改目标；正常未来规则仍原 ID 更新 |
| R2 跨记录回拨 | 18 日记录后回拨新建 15 日，被算作当日 | 本模块跨记录/规则 observedAt 判断，新字段时刻未知，事实仍可保存 |
| R3 DST 设置 | 当天午夜加秒数造成 09:00 显示为 10:00 | 稳定民用日期组件构造 picker，墙钟分钟往返 |
| R4 当日重复提醒 | 09:00 已递送后改为 11:00 又排当天 | 本设备实际排期元数据抑制已过时日期，提前修改仍替换；重开保持 |
| R5 DST 部分记录 | 不确定重复 01:30 时整条评分/起床无法保存 | 保留合法民用区间，绝对时刻不确定时不算间隔/目标；严格拒绝格式错误 |

ReviewRed1：真实服务 3 项测试全部失败，5 处断言；ReviewGreen1：25/25 通过。后续补 DST 偏移/回拨次序、白天主睡眠的正负对照。所有证据在 `/tmp/pgos-sleep-evidence`，原失败保留。

首轮还指出标题跨日说明、趋势未绘制、中文覆盖待完成；已改为实际区间日期预览、跨夜区间图与来源列表，补实际编译键的中英文。以上修复仍须固定 SHA 独立复审，不以自评声明关闭。

## 第二轮：a1530d14276325af50aa25393904e15a1da42d1a

首轮五项均关闭。追加三个必选P2：NY→LA时民用日回退改写已生效目标；DST不确定分支未拒绝所有可能解释都逆序；提前取消后仍留下未消费排期台账。ReviewRed2真实3项/4断言红，33b0257加入原观察时区、持久激活证据/跨日目标提案、全部DST解释排序、已确认提前取消移除台账。ReviewGreen2 96/96与FullUnit2 410/410通过。

## 第三轮：33b0257 → 4928209

前两项关闭，Reviewer用实际共享协调器控制流发现提前取消修复的重入缺口：下一日add触发generation变化，末尾guard跳过pending复查和台账确认。真实生产stub交错反例ReviewRed3 0/1红；4928209仅移动失效generation的状态发布门禁，取消事实仍实际复查。ReviewGreen3 44/44通过。Reviewer固定4928209复审确认全部已报告P0/P1/P2关闭。

## 产品与证据收敛

Reviewer核对集中UI原始摘要15/17、两个失败及2条体重路径旧Invalid frame warning，没有改称一次全绿。55e192e仅修测试中Safari教学和原生开关触点，保留原事实断言；SupplementUI1睡眠2项通过，Safari仍失败。独立核查系统日志、ShareInbox调用顺序及基线diff，确认unsigned缺entitlement在provider前失败；允许复用未触及分享路径的历史有效证据，当前候选真实签名/系统分享必须留Owner Gate，不单独阻塞S14。

主实现者发现固定轴裁晚起区间，Reviewer确认P2，要求一并修24刻度日期。47f3d95按实际区间端点扩domain并标次日，实际SleepService反例与23/23 Unit通过，P2关闭。后续ChartVisible2新增AX query失败，视频证明图存在但长日期标签重叠；Reviewer确认限定改三刻度/日期时间分行、用可操作绘图来源入口验证合理，无需扩大设计或重跑全量。

最终固定产品/测试与最后生产SHA `138616cd0970b0f4fba9d0c7d7d44f6ca7d30b53`：保留原晨间区间、保存重开、原记录回跳、删除及体重断言，并实际从“Open plotted nights”进入来源、打开原表单。独立Reviewer最终读取fixed138616c真实diff、ChartVisible3摘要与可见PNG、中文真实Dark/AX、V11/V12及恢复/低空间原证据，并直接读Debug/Release实包plist，确认产品与自动化证据终审通过，无未关闭的已确认范围内P0/P1/P2；Git交付随后单独核对。

主实现者运行所有测试/构建；唯一独立Reviewer只读审查固定diff和导出的原始证据，未写代码、未自己跑测试。首轮xcresult工具内部TestReport写入受权限限制，后续核对主实现者导出的结构化摘要、日志、视频帧与PNG；不把访问限制隐藏或称作亲自运行。最终Docs-only交付不重建，无自引用hash。
