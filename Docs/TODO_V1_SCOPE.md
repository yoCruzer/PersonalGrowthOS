# Todo V1 范围与验收

2026-10-09 Owner 批准，依据完整 Goal Pack Rev2（01 产品、02 架构验收、03 Goal、04 构建溯源）。本轮是一个整体 Goal，内部工作单元连续执行，最终停止于 READY_FOR_INDEPENDENT_REVIEW。

## 基线与边界

远端重新 fetch：main 为 dd09975d3a3736b24f8646fa4f197cc883ab1796；annotated tag testflight-external-capture-c5a3c0a 与 origin/codex/external-capture-v1 同源 c5a3c0ac859efc3ffa4e5d9f77909ec43565c871；PR #7 OPEN Draft，base feature/build9-today-entry-followups。Owner 确认当前真机 Build 12，失败的 Build 10/11 只是编号递增。本轮分支 codex/todo-v1-personal-actions，独立 Draft PR #8 base codex/external-capture-v1（https://github.com/yoCruzer/PersonalGrowthOS/pull/8）。

保留五 Tab、原始 Entry/图片/习惯/体重/目标/周回顾/分享来源与导入事务；不改历史 schema 属性、不强制清库、不改 Version/Build、无新 SDK/后端/CloudKit/第六 Tab/复杂规则/子任务/AI。禁止 merge、close、tag、Archive、TestFlight。

## 必做能力

- 独立 TodoTask / TodoTaskEvent，标题唯一必填，备注/重要/计划日/独立硬截止/单次提醒可选；连续快速新增、编辑、完成撤销、取消重开、确认删除。
- Today 紧凑入口与直接新增；Hub 今天/即将到来/全部/已完成/已取消，稳定排序、局部与全局搜索。
- 可选单层 TodoList 新建/改名/过滤/确认删除；删除仅解除归属。
- 固定每日/周/月/年日历系列，稳定系列与期次身份，锚点不漂移；跳过一次与停止系列明确分开。
- Entry 主动生成独立任务、可导航来源；原文及时间不改变，删除任一方不误删另一方。
- 今天完成、本周完成、Open 和硬逾期数量可点入同一筛选的明细；以当前最终状态/最后完成时间为真相。
- additive SwiftData V11；备份 v7 包含任务、事件、清单、系列、来源，兼容合法 v1–v6，完整保留安全恢复边界。
- 独立 Todo 提醒协调器；只在用户设提醒时请求权限，状态诚实，替换/移除/冷启动/前台/导入协调，有界队列，不影响已有每日/周提醒。
- 关于页 Version / Build / Git SHA 分列，短 SHA 与完整复制，真实标签可选。编译前注入 CI_COMMIT 优先、本地 HEAD/dirty 次之、缺失未知；无运行时 Git/网络。
- 简中/英文、离线、深色、VoiceOver、大字体与实际使用流程验证。

## 固定语义

计划/截止持久化公历 YYYY-MM-DD，不因时区转换改变。Today 收 Open 且计划或截止 <= 今天；Upcoming 收未来已安排且不属于 Today；无日期留 All。只有 deadline < 今天是硬逾期，计划过期标“计划未处理”。技术更新时间单调，业务发生时间保留真实时钟。

重复以首次原始锚点计算：短月取月底，后续回到原日；2/29 非闰年取 2/28，闰年恢复 2/29。关闭/跳过时生成首个晚于当前日的后继，错过中间期次不批量补建，保留下一期与跳过策略说明。每个系列最多一个 Open 期次；撤销旧完成会暂时撤回未完成后继（保留事件与身份），重新完成复用适合的后继，不重复创建。停止系列保留当前期次和历史，只停止后续生成。编辑明确仅这次/今后系列，不重写历史或原始锚点；规则变更通过停止后新建系列处理。

单次提醒保留选定的绝对时刻；重复后继按本地日与原定钟点解析。DST 缺失时刻顺延至当天下一有效时间，重叠时刻取首次。期次保存原定本地日/分钟和解析时区，防止缺失时刻已顺延后跨时区产生钟点漂移。编辑仅标题/备注不改变钟点；系统显著时间变化、启动、前台和导入成功均重新协调。权限仅来自当次显式设置/重试提醒，不把旧的权限请求意图留给以后启动。

v7 的五个 Todo 数组全部必需；v1–v6 不得包含任何 Todo 数组键（即使为空）。旧领域时间编码维持 1970 秒；新增 Todo 传输时间使用 Date 原生 2001-01-01 reference epoch 秒，与事件快照相同，精确保留 Double，不通过 epoch 转换引入一位精度差。所有身份、事件链、日期、状态、系列和来源引用严格校验，导入只允许空库；更早 App 不支持新 v7 包。

## 工作单元与门禁

S0 基线/权威文档 → S1 领域/持久化/真实旧库迁移 → S2 UI/搜索/统计/来源 → S3 重复/提醒/provenance → S4 备份/集中回归/候选 → S5 普通提交推送与 Draft PR。

开发以受影响定向测试为主，候选尾端一次完整 Unit 与适当完整/关键 UI，Debug/Release 产物验证。A1–A25、P1–P8 必须逐项有真实证据；不以 mock 独立测试替代贯通流程、真实 V10 或 App bundle。失败原样记录，修复后只重跑受影响范围。

Owner 真机门禁：私人库覆盖升级、硬件/通知实际送达、签名与实际 Xcode Cloud 发布验证；给出十分钟中文清单，不冒称已通过。
