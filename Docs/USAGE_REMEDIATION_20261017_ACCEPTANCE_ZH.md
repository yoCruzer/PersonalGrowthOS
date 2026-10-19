> **2026-10-19 当前验收：LOCAL_REVIEW_FIX_REQUIRED / FIX_GOAL_READY。** 固定已审产品 c296a369、交付 62210d9；SR-01～07 OPEN，BV-01/02 NOT_RUN。完整矩阵见 [系统审查](USAGE_REMEDIATION_20261019_SYSTEM_REVIEW_ZH.md)，关闭要求见 [真机前修复 Goal](USAGE_REMEDIATION_20261019_PREDEVICE_FIX_GOAL_ZH.md)。本次文档提交未实施修复或产生新原生 PASS；251/0/1 等为旧开发端运行报告。本轮登记追加在文末。历史事实、旧有效修复和设备/环境未通过状态不改写。

---

> **2026-10-18 第二轮外部复核后：LOCAL_REVIEW_FIX_REQUIRED / FIX_GOAL_READY。** CR-01～06 均 OPEN，OBS-01/02 待限定补验；新矩阵见本文末尾，执行 [第二轮限定修复 Goal](USAGE_REMEDIATION_20261018_REVIEW_FIX2_GOAL_ZH.md)。本次只准备规格，新产品/测试 NOT_RUN。下方上一轮运行结果保留，其 READY 和“本地全部关闭”不作为当前状态。

---

> **2026-10-18 最新增量：F1–F5 / UX1–UX2 本地修复与独立复核完成，READY_FOR_OWNER_DEVICE_GATE。** 固定产品597552a；本轮最终证据见本文末尾。下方原A–D及“全部待执行”为历史基线，真实失败与设备遗留不改标。

---
# 随心log · 使用反馈整改验收与交付矩阵

- 规格版本：1.0；2026-10-18。
- 固定 BASE：`5a70f0110b151f8a45ac7c33d3f443823b1cff24`。
- 本次仅创建执行规格，以下状态全部为 **NOT_RUN / 待实现验收**。不得预填 PASS；既有基线结果不是本轮新实现结果。
- 必须与同一 GOAL_SHA 的 GOAL / DESIGN 全文一起执行。实际命令、SHA、证据路径写本目标 EXECUTION，独立审查写 REVIEW，表内关联到对应结果即可，不重复堆砌日志。

## 1. 原反馈与阶段追踪

| 验收 ID / 原反馈 | 阶段 | 用户可见的验收结果 | 最小有意义验证 |
| --- | --- | --- | --- |
| U01 / 1 清单入口 | A | 在新增待办选择清单时可新建/管理；新建后自动选中；取消/返回不丢原输入；删除清单保留任务并回未分类 | 从真实编辑器带完整草稿走新建、取消、改名、删除；保存重开核对选择和其余字段 |
| U02 / 2 重复与紧急 | C | 周一至周五、周末、自选星期可用；规则和下一期清楚；主动开启系统闹钟、权限/排程真实 | N1–N6 的服务/系统适配器/必要 UI；实际响铃留 D1 |
| U03 / 3 保存提示 | A | 任务保存与提醒结果分别表达；“知道了”只收起反馈 | 有提醒的任务保存后收起，任务状态和请求集合不变；失败态仍可找回和处理 |
| U04 / 4 过期重试 | A、C | 过期显示重新设置未来提醒，不再无效重试；不改原计划/截止/系列 | 屏幕停留跨过时间后点击；本次 10 分钟后/明天/自选；终态和旧回调对照 |
| U05 / 5 成长回顾来源 | B | 摘要、每日汇总、原始明细可下钻；真实多次保留，天数与次数分开 | Q1–Q3 合成事实，当前页增删/撤销/补记后刷新 |
| U06 / 6 Growth 数量/副标题 | A | Sleep/ImportantDays/TimeInvestment 等有对应副标题与带单位准确计数 | 空、非空、归档、恢复/删除；入口统计与默认目的页范围一致；仅浏览不落库 |
| U07 / 7 体重加强 | B | 5 种范围、4 种均值、动态轴、日期下钻、记录起点/覆盖/连续性和有限历史 | W1–W6 算法、真实视图和多年份数据 |
| U08 / 8 BMI | B | 可选身高自动计算；中国/WHO 参照和含义可查；清除/编辑有效 | B1–B3；不填身高仍能完整记录；最新体重/日期来源正确 |
| U09 / 9 Today 一致性 | A、D | 习惯与其他入口有统一总行高/图标/文字列；副标题在标题下，动作明确 | 同屏混合习惯、体重、睡眠、目标、重要日子、时间投入、本周回顾；紧凑默认和大字号各核验 |

## 2. 提醒与重复边界

| ID | 场景 | 预期 |
| --- | --- | --- |
| N1 | 周五完成工作日期次；周日完成周末期次；自选一/三/五；空/重复星期输入；星期显示从周一开始 | 下一期分别落合法未来日；沿原系列只开一个期次，不补堆历史；存储星期身份稳定，非法集合拒绝 |
| N2 | 月末、闰日、跨年、DST 不存在/重复时间、切时区；跳过/取消/结束系列；本次日期/提醒覆盖 | 沿现有明确日历规则，不用秒数当自然日；新规则不回归旧规则；本次覆盖不改变系列/截止/计划 |
| N3 | future→elapsed 的屏幕停留；过期很久的开放任务；终态后旧按钮/回调 | 点击时重新判断；能设置本次合法未来时间；终态不会重新排程；提示具体且无空操作 |
| N4 | 普通通知/闹钟切换；未决定/拒绝/已授权/系统不支持/队列满/排程错误 | 不自动开启强提醒；每次实例只有一个主渠道；失败与已保存区分，无静默降级或虚假“已设置” |
| N5 | 变更时间后旧异步完成；双击；系统接受后本地写入失败；取消失败；完成/跳过/删除；系统停止后回前台 | 稳定身份/修订幂等；只清理自己的请求、不复活终态；取消未确认则显示待处理/错误并保留重试对账，不新增冲突请求；确认取消后旧请求须消失。停止响铃不完成任务，也不因 refresh 重排旧到期请求 |
| N6 | 重复任务当前期次使用 AlarmKit；新包恢复未来/过期提醒，设备权限不同；与 Sleep/ImportantDays/每日/周提醒共存 | 只调度当前实例单次闹钟，下一期由任务服务生成；恢复意图不复制旧系统授权/队列成功；不无条件授权或响过期提醒；不移除其他模块请求 |

N4–N6 应有真实生产适配器接线和可注入的生命周期验证，不能只写返回成功的 fake。可用环境下验证原生 API 调用；实际静音/专注/锁屏递送需要 D1。仅桩通过不能把整个 AlarmKit 集成标 PASS。本组提醒验收使用 N 前缀；下文 R1–R3 专指时间投入 V1 原外部 review 编号，不能串号。

## 3. 成长回顾与体重统计反例

| ID | 合成数据 / 场景 | 预期 |
| --- | --- | --- |
| Q1 | 同习惯一天 4 次，另一天 2 次，其余无记录 | 有记录 2 天、6 次；每日 4/2 次；展开仍有全部真实明细，不按相同值去重 |
| Q2 | 历史目标从每日 4 次改 2 次；存在休息日、tracking-only、旧数据无可靠计划 | 按当日生效规则；没有可靠历史分母不显示伪达标率；天数/数量/次数不混算 |
| Q3 | 原 LocalDay 与当前设备时区日不同；补记、撤销、删除、导入后停在原回顾页 | 业务日不漂移，最新事实一致；原条目定位到具体日/记录；无精确时间不造时刻 |
| W1 | 2026-10-16 70/72 kg，10-17 75 kg | 两日均值 71/75，区间均值 73 kg，2 天/3 次；最新真实值 75，上次为 72，比较时刻明确 |
| W2 | 截至 2026-10-17 的 7/30/3月/1年；再测截至 2024-05-30、2024-02-28 的月末/闰年窗口 | 首例起点分别 10-11、09-18、07-18、2025-10-18；3月按 endExclusive 向前减月并钳制，2024-05-31→2024-02-29；1年 2024-02-29→2023-02-28；页面日期和查询同口径，不用90/365冒充 |
| W3 | 只 1 条、全部相同、缺失多日、某参考线在可见趋势外、极端合法值、无样本 | 合理稳定轴及完整范围；单点不造趋势、缺失不补零、极端不静默丢弃；参考线与样本图例准确；切点不改变窗口/均值/轴 |
| W4 | 同日多次、补更早一日、删除首日/最后日、跨年连续段、今天未记但昨天已记 | 最早日、累计记录日、跨度/覆盖、当前/最长连续性正确；“截至昨天”准确；Weight 当前时区快照一致，不声称拥有旧原始时区 |
| W5 | 选日期/图点/无记录日、查看某日多条、编辑/删/返回、切月份/清选择 | 选中状态清楚，原记录可到达；均值与窗口不暗变；统计即时刷新；图表手势有可访问替代入口 |
| W6 | 多年份、大量同日记录、反复范围切换/点选 | 主页面不出现无界历史；不每次渲染重复排序全量；无明显阻塞或随操作持续膨胀；记录实际规模、耗时/内存观察和环境，不凭空声称性能提升百分比 |

W6/T7 可使用 5 年约 1 万条记录的确定性合成数据，另配稀疏和高重复日案例；数量是负载样例，不是要求超大基准工程。先定位实际重复查询/计算，结果足以证明有界展示和可接受交互后停止额外压测。没有 Instruments 或对应工具时准确报告能观察到的范围。

## 4. BMI 验收

| ID | 场景 | 预期 |
| --- | --- | --- |
| B1 | 无身高/无体重/0/负数/非有限/合理上下界/小数；新增或改最新体重 | 不崩溃/除零；正常输入自动计算，体重记录不被 BMI 阻挡；日期和测量值可核对 |
| B2 | 中国 18.5、24、28，WHO 18.5、25、30 及界值两侧；显示 23.96 等 | 未舍入值正确归类；显示接近界值时不制造数字/分档矛盾；参照切换不改体重、身高或事实 |
| B3 | 编辑/清除身高，冷启动，当前新包导出/空库恢复；历史旧包无新字段 | 设置按契约保全；清除后不继续显示/导出旧值；旧包默认未填；原版本严格校验与空库规则保持 |

UI 提供中国/WHO 来源及成人一般参考说明，短建议中性，无儿童套用、诊断、自动减重目标或热量处方。文案审阅足以验证解释，无需为每个静态句子写测试。

## 5. 时间投入纳入项与保护回归

| ID | 本轮验收 | 必須保持的原行为 |
| --- | --- | --- |
| T1 | Growth 副标题及当前参与者未归档活动数准确 | 浏览不初始化“我”/示例，不影响实际空库恢复 |
| T2 | Today 呈现活动及真实未完成状态；到目标状态及时变化，无事项隐藏 | UI 刷新不自动入账、不切断计时、不新增后台响铃 |
| T3 | 收起计时/稍后确认/保留草稿的用语和结果分别正确 | 收起计时沿原 dismiss，不新增保存门禁、不暂停/结束/入账；手工编辑器和结束确认页保留草稿后离开仍须先成功持久化，R2 失败保留输入/错误/重试；生命周期检查点保持 |
| T4 | 活动累计自然单位、短记录不显示零、按钮和大字可用 | 正式累计与运行秒数区分，直接开始/手工入口保留 |
| T5 | 全部累计及7/30日模式下，图表和预览范围准确；超过30个记录日可查 | 全部累计仍全历史，缺失日无记录，不误写客观零投入 |
| T6 | 日期/月浏览、有限明细、选日与清选择清晰可访问 | 跨日暂停记录前日5分钟/次日15分钟/周期1条；下钻同一 Session，不漏边界来源 |
| T7 | 统计快照复用、少量查询/分页；计算失败不显示伪零；多年份数据交互可用 | 改名、归档、编辑、删除、导入后刷新；归档历史和参与者隔离、正式事实口径不变 |
| T8 | 时间精度/时区有可理解层级，完整替换说明在大字下可读 | R3 原20→新25分钟，取消/抓手关闭仍20，明确确认才25；不改回会截断的 alert |

保护 F1 的现行生产链（已有真实方法按影响矩阵复用/定向回归）：包含设备睡眠的 ContinuousClock、进程域隔离、50 ms/18 h 异常规则、暂停不累计、25分钟目标晚返回默认25、显式继续、结束后冻结、跨进程恢复待确认、导出检查点不计算离线间隔。不得退回 awake-only systemUptime 或以后台循环代替。

保护 R1：删除/丢弃/消费后的正文清除、旧回调与新操作不能复活旧事实；R2：失败输入/错误保留、成功落盘才离开；R3：多段替换必须明确确认。即使只调 UI，也验证改动涉及的服务/页面接缝；不要求再次制造 F1 的整套历史红测。旧失败证据原样保留。

## 6. 持久化、组合界面与最终本地门禁

若追加模型/版本：使用真实磁盘夹具验证当前 V14→新版本，以及受影响的 V10、V11Original=11.0、V11=11.1、V12、V13 直接升级与重开；保留既有更早支持链。旧字段默认行为不变，未知状态/非法引用/缺少必需数组拒绝。当前新包实际导出→空库恢复→重开、新装只浏览后从实际设置恢复、预览后新写入拒绝、失败回滚均走生产路径。

体重/BMI/新重复/提醒意图往返完整；时间投入记录、参与者、已消费终态与未完成检查点保持；Entry/图片/Habit/Goal/Todo/重要日子/Sleep/来源和收据不丢失。不能只增加 DTO 就把迁移备份标 PASS，不修改历史模型校验和，不以很旧保护副本冒充迁移前当前快照。

集中 UI 选择少量覆盖实际改动的代表路径：混合 Today/Growth、待办新建/清单/过期提醒、体重多范围和日期、成长回顾聚合、时间投入计时/确认/历史；相邻 Record 草稿、睡眠、重要日子、分享/Widget 路由依据影响做冒烟。中文/英文、Light/Dark、默认字号/大动态字体，有真实截图或运行结果支持布局结论；按钮触达、对比、单位与加载/空/错误态一致。本轮改动引入或直接关联的布局 warning 查因处理，原无关 warning 保留原状态。

最后一次集中全量 Unit＋关键组合 UI、干净产品/测试 SHA 的 Debug Simulator 与 unsigned generic iOS Release 构建及 App/Share/Widget 实包身份/provenance 检查；真实独立 review 闭环。后续只补受影响验证。最终文档独立提交可复用前一产品提交实包并列出仅文档 diff，不要求反复重建同一代码。

## 7. Owner 设备门禁（不阻挡其余整改实现）

| ID | 实际设备项目 | 尚未执行时 |
| --- | --- | --- |
| D1 | 闹钟权限允许/拒绝/撤回；锁屏、静音、专注时真实提醒；停止与打开任务；修改/完成/删除且取消已确认后旧闹钟不再响，取消失败则诚实呈现待处理及重试；旧系统普通通知路径 | NOT_RUN；不可用模拟桩宣称系统递送已验 |
| D2 | 时间投入真实硬件睡眠/锁屏、正常切其他App、倒计时晚返回、结束确认/重开 | 延续时间投入既有设备门禁，按组合清单验证 |
| D3 | 私人库先独立备份和核对，再签名、不卸载覆盖升级；历史数据/身高/重复/未完成事项/导出恢复核对 | Owner 另行授权；不得自动操作私人库或清数据 |
| D4 | 单手真实触控、VoiceOver 实际朗读、动态字体、Photos/分享/桌面Widget/飞行模式等组合 | 区分模拟器已有证据与设备未做部分 |

既有 Safari unsigned FAIL、物理低空间 SKIP/NOT_RUN、独立远端 CI NOT_RUN 等保持基线实际状态；本轮涉及相关路径则评估新增影响，不能用历史限制掩盖新回归。真实设备/签名未授权时仅提供具体待验清单，不将其扩大为全部编码暂停理由。

## 8. 交付结果模板

实际完成后在此追加：阶段 A–D 状态、U01–U09 / T1–T8 对应文件和真实证据、N/Q/W/B 反例结果、迁移/备份和相邻影响矩阵、集中运行的精确 SHA/计数/失败/警告、独立 reviewer 身份及发现闭环、实际分支/PR/远端 head、Owner D1–D4 清单。

当前文档准备状态：规划已形成；实现 **NOT_RUN**；本轮构建/测试/原生 UI/独立实现审查 **NOT_RUN**。规划的独立检查不替代后续实现审查。

## 实施检查点 A1（2026-10-18，整体仍 IN_PROGRESS）

固定输入/隔离与具体原生命令见 [EXECUTION](USAGE_REMEDIATION_20261017_EXECUTION.md)。compile-a1/a2/a3/a4 均 exit0；受影响 Unit11 PASS；ui-a1 为3PASS1FAIL、ui-a2为0PASS1FAIL，ui-a3定向清单1PASS。失败与 warning 不覆盖，阶段内为工作树候选，不代表最终集中门禁。

- U01：新增真实编辑器清单路径通过新建/取消/管理改名/删除/自动未分类/完整草稿保存重开；来源关联及旧任务删除清单保留最终组合仍待核查。
- U03：拒绝权限后事实仍已保存、知道了仅收起及查看待办可达；C 新渠道后再统一验证。
- U06/T1：空库只读、active/去重日期/参与者和归档范围 Unit 通过；完整双语入口运行在 D。
- T3/T8：R2 失败保留输入/重试/冷启动与 R3 中文 Dark 最大AX 20→25明确替换/取消原生通过。
- U04/N1–N6、Q1–Q3、W1–W6、B1–B3、T5–T7 尚待实现/验收；混合 Today/Growth/相邻路径与最终全量、实包、独立 review 未完成。

整体不标 READY；D1–D4 全部 NOT_RUN。

## 实施检查点 B1：体重（整体仍 IN_PROGRESS）

编译 b1–b9 均 exit0；各次原生失败和限定修复见 [EXECUTION](USAGE_REMEDIATION_20261017_EXECUTION.md)。最终受影响运行 `affected-b3` **14 Unit + 2 UI / 16PASS0FAIL0SKIP，runtimeWarnings=[]**；不是全Goal全量。工作树产品/测试哈希见 candidate-b9-source.json，干净最终产品/实包在D执行。

- W1/W2/W3/W4：日均值71/75与等权73、真实最新和上次、半开窗口/月末/闰年/未来排除、极端值与参考线轴、覆盖/连续段/时区快照及午夜DST反例已有本轮Unit通过。
- W5：原生UI完成窗口切换、两条日明细、编辑、明确删除、无记录日不跳转、回原日及返回均值72.5；图点手势、历史截至日期切换、月切换与大字组合仍在最终UI覆盖，不以Unit替代。
- W6：真实磁盘10,000条/1,826日，聚合0.054404458秒，最近5条、50+50两页不重叠、改日期/删除后重读有证据；未测Instruments/RSS，不宣称整页百分比改善。多年份实际UI/反复切换仍须结合D集中观察。
- BMI B1–B3、Q1–Q3、T5–T7、N1–N6、完整迁移/备份/集中全量/独立审查/PR均未完成，保持未验状态。D1–D4仍全部NOT_RUN。

## 实施检查点 B2：成长回顾（整体仍 IN_PROGRESS）

Q1/UI：摘要2天/6次，日汇总4/2，原始身份集合共6且互不重复，精确业务日/原始结果下钻有本轮真实证据。Q3：保存LocalDay跨时区纯Unit不漂移，撤销/删除后原始来源失效及当前回顾重新读取原生通过。新增字段/Schema为零，原内容不被摘要覆盖，时间投入不进入成果。

`affected-q1` **12 Unit PASS + 2 UI FAIL / exit65**；诊断ui-q2/q3/q4均失败原样保留。修复后`ui-q5` **2 UI PASS / runtimeWarnings=[]**；q8仅错误态守卫编译。完整命令/图树/实际source见EXECUTION；不将分轮拼为一次14全绿。Q2只显示事实不造当前目标倒算的历史分母；更广历史计划、补记/导入、多来源/双语大字与统一全量仍在D。整体Goal未完成，设备/独立review/PR仍NOT_RUN。


### B3 实际进展（内部检查点）

T5–T7已实现快照复用、全历史累计/明确自然日与可选月份预览、20条真正查询分页、选日/清选择及失败重试。affected-t1核心30＋磁盘1＋编辑删除UI1为32PASS，1条frame warning保留；修复键盘接缝后ui-t2的R2/编辑删除2PASS但月份1FAIL，零运行warning。新UI的开关命中、滚动和分日合并标签定位失败原样保留，最终compile-t6/affected-t2完整性校验后的1万正式配对事实磁盘＋月份/分页/跨日原始UI **2/2PASS、零运行warning**，首次refresh0.224274039秒。未测Instruments/RSS。B3不是整体A/B/C/D门禁；最终中文/英文、Dark/最大AX、导入刷新和相邻路径在D，BMI/新重复/AlarmKit/新迁移备份仍未完成。


### B4/C 内部检查点（整体 IN_PROGRESS）

BMI服务、未舍入两参照边界、可选身高与清除/重开已有本轮证据；ui-c3完整入口/非法0/175cm/中国24.5超重与WHO通常范围/清除通过。星期核心9项、ui-c5空集禁存/周二周日/下一期/跳过通过；真实v11 ZIP恢复custom mask并继续生成、真v10缺省和新版缺数组/旧版夹带新字段拒绝通过。

N3–N6生命周期及共享额度 affected-c11 **31PASS**；后续DST/旧修订/实际Alarm实例覆盖ZIP和生产Open Intent保留Record/modal草稿 affected-c13 **4PASS1SKIP**，均零runtime warning。精确失败/修复/命令见EXECUTION。真实授权API在当前Simulator两次立即拒绝，无弹窗；**原生正向schedule/cold/cancel、系统Stop/Open以及D1设备递送NOT_RUN**，原先2次正向UI失败未抹除。c29最大字/混合入口、D完整Unit/组合UI/Release/实包、独立review与新PR未完成；D1–D4仍全部NOT_RUN。


### D 集中门禁与修复中（2026-10-18）

完整Unit固定c909首轮517=512PASS4FAIL1SKIP，四项为旧测试夹具计数/设备ID/旧wire空数组假设；仅修测试后50e9受影响完整ImportExportRecoveryTests+QuietWinsReaderTests60/60PASS，生产79文件blob完全相同，不宣称重跑517全绿。1SKIP仍是既有独立低空间环境。真实外观UI首轮final-ui1为27=21PASS5FAIL1SKIP，五个原失败与3条warning均保留，继续按受影响项收口。

- 独立R1标题替换、R2周一顺序、R3旧通知取消未确认阻挡已代码修复及配对反例/并发验证；最终UI/实包审核仍待。
- 独立R4体重时区选择修复后affected-d5完整Weight17+AppComposition18=35PASS、runtimeWarnings=[]；R5最大AX习惯竖排与R6成长页后台导入订阅修复后，实际UI正在补验。
- Public host本轮能够打开真实Share Extension，但原生报告role=shareExtension/stage=providerRead/category=appGroup。SharedCapture/ShareExtension/原entitlements和签名设置均未改；unsigned Simulator无法读取共享Inbox，正向导入未通过。ui-d5中测试Runner跨进程读取刚复制的报告遭PBError13，该FAIL保留，随后仅在本轮专用Simulator读取主动复制报告作真实归因。签名分享正向列D4，不用合成单元或环境SKIP冒称通过。
- AlarmKit真实requestAuthorization进入系统后拒绝，权限拒绝/保存任务/设置反馈已验，正向schedule/stop/open及真实响铃仍D1 NOT_RUN；Debug弱链接存在不等于系统递送通过。

本段为过程证据，不是最终READY；仍须最终clean Debug、unsigned generic Release、六实包provenance/身份、独立review闭环、普通push和唯一新Draft PR。


## 最终本地实现验收（2026-10-18）

状态：**READY_FOR_OWNER_DEVICE_GATE**。最终产品/测试、独立审查及双构建固定 `9601ff211fbdafc954e32f9e25206a38479e972b`。这是本地实现完成、可提交设备门禁的结论，**完整Goal的原生/签名/真机/CI验收没有全部通过**。原失败/警告保留；下表“本地通过”不覆盖D1–D4。

| 项目 | 实际结果与主要实现 | 原始证据及限制 |
| --- | --- | --- |
| U01 | 本地通过。TodoViews清单新建/自动选中/取消/管理改名/删除回未分类，整行44pt命中，原草稿保存重开 | ui-a3、ui-d5真实编辑器往返PASS |
| U02、N1–N2 | 本地通过。TodoSeriesPreferences ISO星期、工作日/周末/自选；下一期/跳过/截止相对偏移/民用日DST保留 | TodoTask/Reminder/历史升级纯Unit与磁盘通过；ui-d5中文真Dark最大AX星期保存；实际响铃留D1 |
| U03 | 本地通过。保存事实与提醒结果分开，知道了只收起反馈，查看待办可回原事项 | AppComposition/TodoReminder及权限拒绝保存UI；无自动完成或重排 |
| U04、N3 | 本地通过。本次未来重设使用独立持久化事务/expectedRevision；旧系列±366天校验不放松，不改计划/截止/系列 | 长期过期、屏幕过期、冷启动及终态/旧回调反例；final-ui1过期UI PASS |
| U05、Q1–Q3 | 本地通过。QuietWins按保存LocalDay汇总真实2天6次、每日4/2次并下钻每条原始事实；撤销/删除/导入刷新 | ui-q5、final-ui1、ui-d5后台导入PASS；原身份不按相同值去重、不造时间/分母 |
| U06、T1 | 本地通过。Growth统计有单位、范围/参与者一致，失败不是0，浏览不初始化持久默认值 | affected-d5完整AppComposition18及Files新装浏览→预览取消/恢复；ui-d5后台保存主线程更新无警告 |
| U07、W1–W6 | 本地通过。五范围/四等权日均/动态轴与缺口、记录覆盖连续性、最近5/日50分页/编辑删除/时区选择 | Weight完整17＋AppComposition18=35PASS；ui-d5日期编辑删PASS；一万条/1826日0.054404458s；未测Instruments/RSS/峰值内存 |
| U08、B1–B3 | 本地通过。可选身高、中国/WHO阈值使用未舍入BMI、近界提示、来源/成人一般参考、编辑清除冷启动/新包恢复 | Unit边界和ZIP/迁移；final-ui1及ui-d5真实175cm→24.5/中文Dark maxAX；不是诊断或儿童建议 |
| U09、T2–T4 | 本地通过。共享文字列/20pt装饰图标与24pt列/完整行命中，Today混合真实习惯/Weight/running Investment/Sleep/active Goal/ImportantDay/WeeklyReview | ui-d8同clean9601 **1PASS、warnings=[]**，默认英文和中文真Dark最大AX；正文仍缩放、原动作/计时不变 |
| T5–T7 | 本地通过。全历史累计/明确7或30自然日与月预览、日期/20条原始分页、快照复用/失败态、评价日参与加载key | 完整InvestmentFoundation31PASS；ui-d6历史范围/月分页/5+15分钟同Session下钻PASS；一万Session＋一万Operation0.224274039s；未测Instruments/RSS |
| T8、F1/R1–R3 | 本地保护回归通过。ContinuousClock/进程域/50ms/18h/暂停/倒计时/检查点，已消费内容清除、成功落盘才关闭、多段显式替换保持 | full-unit1相关案例通过；31基础Unit；final-ui1 R2/R3真Dark AX和Record独立草稿PASS，ui-d5 Timer/冷重开、ui-d6手工草稿0场0秒PASS；硬件睡眠仍D2 |
| N4–N6 | 生产接线与可注入生命周期通过；原生正向 **NOT_RUN**。真实AlarmKit适配器/权限/普通通知共享容量/本机持久设备账本/取消确认/终态不复活/旧回调/停止不完成及打开待办路由 | 红绿双通道、并发、取消失败/恢复/共享预算和真实ZIP验证；原生requestAuthorization确到mobiletimerd后denied，final-ui1正向例SKIP；不能称真实schedule/stop/open/递送通过 |
| 迁移/备份 | 本地通过。仅新增未发布V15四模型；V1–V14不改；v11严格新数组、旧包严格拒绝越版字段，设备账本/权限/成功状态不进备份 | full-unit1各历史升级/重开通过；修正fixture后完整ImportExportRecoveryTests＋QuietWinsReaderTests60PASS；实际ZIP/空库恢复/预览失效/失败回滚/设置非空守卫保持 |
| 相邻组合 | 本地可执行路径通过：Record独立草稿、Sleep两路径、ImportantDay三路径、实际URL与生产intent路由、Files预览取消恢复、WeeklyReview多字段/冷重开 | final-ui1及ui-d5/ui-d6分轮原始结果；Public share为环境FAIL，原生Widget桌面/Photos/VoiceOver不冒称模拟器通过 |

### 集中运行与证据复用

证据根 `/tmp/pgos-usage-remediation-evidence`，本机macOS27.0.1/26A434、Xcode27.1/27A9275、SDK27.1、专用iPhone18Pro Simulator iOS27.0/24A434。

| 运行 | 实际结果 |
| --- | --- |
| final-unit1 / clean c909 | 517项：512PASS4FAIL1SKIP，exit65，runtimeWarnings=[]；四FAIL为旧测试夹具假设，未放松生产校验 |
| final-unit-fix1 / clean50e9 | 受影响完整ImportExportRecoveryTests＋QuietWinsReaderTests60PASS，exit0，warnings=[]；79生产文件与c909相同 |
| affected-d5 / 精确candidate-d6 dirty快照 | Weight17＋AppComposition18=35PASS，exit0，warnings=[] |
| affected-d7 / clean1bfceef | 完整InvestmentFoundation31PASS，exit0，warnings=[] |
| final-ui1 / clean50e9 | 27=21PASS5FAIL1SKIP，exit65、3条warnings；后续只补受影响项，不改写本轮 |
| ui-d5 / 精确candidate-d6 dirty快照 | 10=7PASS3FAIL，exit65、1条frame warning；两条后台State警告已消失 |
| ui-d6 / clean1bfceef | 6=4PASS2FAIL，exit65、warnings=[]；Public环境FAIL/mixed旧视口断言FAIL，业务四路径PASS |
| ui-d7 / clean531ccba | mixed1FAIL，真实共享行点击空白未导航，保留原树/图；并非已被放宽的测试 |
| ui-d8 / clean9601 | mixed1PASS0FAIL0SKIP，exit0、warnings=[]；共享图标/整行命中及严格Goals导航闭环 |
| final-debug8 / clean9601 | Debug Simulator build-for-testing PASS/exit0 |
| final-release1 / clean9601 | unsigned generic iOS Release build PASS/exit0；不是Archive/签名安装 |

`native-run-index.json`记录实际命令、主轮退出码、各log SHA256及分轮summary；`full-unit-reuse-proof-final.json`列完整Unit后七个生产文件的影响/补验，不冒称新全绿517；`final-ui-coverage.json`仅逐selector给最新原始轮次，不将其拼成一次全量运行。六实包身份/provenance/真实debug库与Release executable哈希在`debug-bundle-proof-9601ff2.json`、`release-bundle-proof-9601ff2.json`，实际Mach-O弱链接在对应文本。两App clean同完整SHA/localGit/Tag空、原IDs/1.0(7)/min17。Release的metadata warning明确仅ShareExtension无AppIntents依赖；Xcode SDK/debugger元数据和unsigned App Group/Widget诊断保留，不声称所有原始log无警告。

独立只读reviewer `/root/usage_remediation_independent_review` 的完整终审原文见 `USAGE_REMEDIATION_20261017_REVIEW_ZH.md`：R1–R8关闭，无范围内仍未关闭的已确认P0/P1/P2；未证实的主context缓存假设已撤回。该结论不等于完整原生/签名/真机验收通过。

### Owner下一步设备清单（全部NOT_RUN，须另行授权）

1. **D1 闹钟/通知**：签名设备允许/拒绝/撤回AlarmKit；只排当前期次。安排未来闹钟，在锁屏/静音/专注下真实递送；系统Stop不完成任务、不因回前台重排；Open在冷启动和已有Record草稿/modal上进入正确Todo。改标题/时间/切渠道、完成/跳过/删除后核对旧请求实际消失；取消失败应待处理且可重试，未确认前不出现冲突后继。若可用，iOS17普通通知fallback也需实机验证。
2. **D2 时间投入**：秒表实际锁屏/硬件睡眠后结束应包含睡眠；暂停锁屏不累计；25分钟倒计时晚返回封顶25，显式继续才累计新段；切其他App、结束冻结、强杀冷重开待确认、手工/跨日/回顾不影响Record草稿。模拟器home/relaunch和合成时钟不能替代此项。
3. **D3 私人库升级/恢复**：先独立备份并核对计数/图片/原记录，再授权签名、不卸载覆盖升级；核对旧Entry/Habit/Goal/Todo/ImportantDay/Sleep/Investment、未完成计时、星期与提醒意图、可选身高；在隔离目标验证新包导出/空库恢复，勿无备份覆盖私人库。本轮没有操作真实手机或私人数据。
4. **D4 实际交互组合**：单手44pt触控、VoiceOver真实朗读/状态值、默认及最大动态字体Light/Dark；签名后Safari/Public NSItemProvider文字/URL/照片分享并确认只导入一次、Photos、桌面Widget路由、飞行模式下Record/本地Files备份恢复及相邻模块组合。

**保留状态**：AlarmKit正向schedule/cancel/响铃/原生Stop/Open NOT_RUN（真实授权denied）；Public mixed provider **FAIL/environment**（实际copied diagnostic category=appGroup），unsigned Safari **FAIL**，签名Share/Safari正向NOT_RUN；独立32MB HFS+物理低空间 **SKIP/NOT_RUN**；远端workflows=0，独立CI **NOT_RUN**。本地实现完成不授权merge、force push、tag、Archive或TestFlight。


### 实际交付身份

已普通push `codex/usage-remediation-20261017`，唯一新[OPEN Draft PR #13](https://github.com/yoCruzer/PersonalGrowthOS/pull/13)，base=`codex/time-investment-v1`，baseRefOid仍固定BASE。最终产品/测试/实包/独立审查SHA仍`9601ff211fbdafc954e32f9e25206a38479e972b`，后续仅本轮五份Markdown交付记录；交付SHA以PR当前head和证据`final-delivery-proof.json`为准，避免自引用SHA。旧PR #1–#12及原工作区三项未知dirty保持；没有merge/force/tag/Archive/TestFlight。独立远端CI未执行（workflows=0、statusCheckRollup=[]），不能将空检查当通过。停在本轮边界，下一步仅Owner另行授权D1–D4。


## 2026-10-18 独立复核后的修复验收 — 全部待执行

输入：已审交付 `f1b52b58fd11c41f508ec665d583827879ffa202` / 产品 `9601ff211fbdafc954e32f9e25206a38479e972b`；新 FIX_GOAL_SHA 由 Owner 引导 prompt 固定。权威执行要求：[PR #13 独立复核后的本地修复目标](USAGE_REMEDIATION_20261018_REVIEW_FIX_GOAL_ZH.md)。本节 NOT_RUN 只指新修复批次，不抹去原 A–D 的实际历史结果。

| 验收 ID | 必须验证的实际结果 | 初始状态 |
| --- | --- | --- |
| RF-F1 | 撤回后继→再次完成→两渠道各一个有效新代次；反复对账幂等，取消失败仍挡住冲突后继 | OPEN / NOT_RUN |
| RF-F2 | 真实旧 nil 单一期次的单次改期不改系列偏移；完成 / 跳过、>366 天、原子失败、落盘及旧备份恢复 | OPEN / NOT_RUN |
| RF-F3 | 已接受较晚 Todo 可以被更早 / 其他类别候选置换，等待项在位置释放后恢复；保留项与取消不确定占用正确 | OPEN / NOT_RUN |
| RF-F4 | A 第二页晚于 B 返回也不能污染 B；返回 A 正确；更多 / 重试 / 刷新均受当前 query 校验 | OPEN / NOT_RUN |
| RF-F5 | 10,000 条落盘数据的真实草稿保存→事件→workspace 链无额外 UI 全历史扫描；20 条按页 / 单 ID 详情、失效、错误 / 草稿恢复 | OPEN / NOT_RUN |
| RF-UX1 | 最近 7 / 30 天选择窗外日自动全部累计，保留日期 / 月份 / 活动，数值为选中日 | 决策已确定 / NOT_RUN |
| RF-UX2 | 主页面最近 5 条不超过 cutoff 且不误加趋势下界；独立全部记录可查较晚记录 | 决策已确定 / NOT_RUN |
| RF-REGRESSION | 一轮集中受影响 Unit 与关键 UI，提醒取消 / 恢复、时间投入历史 R1–R3、混合 Today / Record 草稿保护 | NOT_RUN |
| RF-BUILD | 最终干净产品 SHA 的 Debug、unsigned Release；App / Share / Widget 实包身份、provenance / minOS / 弱链接 | NOT_RUN |
| RF-REVIEW | 未编写本轮修复的独立 reviewer 检查固定候选、生产路径、回归与原始证据；确认问题闭环 | NOT_RUN |

执行后逐项追加实际命令、候选 SHA、逐轮 PASS / FAIL / SKIP / NOT_RUN 与证据引用；不以旧 9601 实包或原 R1–R8 报告直接满足新候选要求，不将多轮通过数拼成单轮全绿。文档交付提交与产品提交分开记录。

这次已授权的本地修复替代上方旧的“下一步仅 Owner D1–D4”停点。AlarmKit 原生正向 NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间 SKIP/NOT_RUN、D1–D4 与远端 CI NOT_RUN 持续保留。新本地要求关闭后仍需 Owner 后续设备授权；没有签名安装、私人库、merge、force push、tag、Archive 或 TestFlight 授权。


## 独立复核修复最终本地验收（597552a）

## PR #13 2026-10-18 独立复核修复批次（F1–F5 / UX1–UX2）

固定规格 `2add10b0c67d064b7e77478fb18a11479d3c94dc`；最终产品/测试 `597552a020eab22673feed108d8676359efd8822`（其中生产及Unit与f946相同，最后一提交仅UI驱动/补验）。原已审交付 f1b52b5 / 产品9601仅作历史，不作为本轮通过证明。沿同一原worktree和分支续接；2add相对f1仅六份Markdown，原BASE和FIX_GOAL均为本候选祖先；主工作区未知三项dirty保持，未reset/clean/stash/重建/新建PR。远端base仍5a70f01，PR #13 Draft/base原分支未变。

| 编号 | 本地实现与有区分力证据 |
| --- | --- |
| F1 | 仅successorWithdrawn重新启用的后继在applyTemplate换代，期次身份保持。真实磁盘两渠道协调器、确认取消与取消失败再完成、重复reconcile和重开通过；主动停止/已消费负例保持。fake不是AlarmKit原生正向证明。 |
| F2 | 单次覆盖前在同一事务冻结真旧nil系列偏移，普通单实例编辑同样保护。V11.0真实Schema创建单一open实例与原created事件，升级后nil；实际v7 ZIP恢复后同样nil，无早期完成线索。0/-1、短期/800天、同分钟/改分钟、complete/skip参数化；失败全部回滚，无设备账本；重开、新v11实际导出恢复与原事件bytes通过。 |
| F3 | accepted普通通知继续参加共享时间/类别规划；预算取消待确认与capacityWaiting区别于retired/stopped。实际查队确认后释放名额，legacy与新Todo/ImportantDay/Sleep共存。59保留项+L→E置换/完成E恢复L、跨类别、取消失败/恢复、停止项早/晚E都通过。Alarm/prepared读取失败仍confirmationRequired。 |
| F4 | shared WeightMeasurementLoader持有当前query/generation和任务；初始/更多/重试同一归属。可控reader挂起A第二页/重试，让B先返回再放A，B不改写；refresh/返回A及表头再出现保留页通过。 |
| F5 / 原T7 | typed process-local invalidation仅保存版本/ID；草稿与计时事件只读相关operation；正式变更/导入允许一次必要重建。每256条新context临时解码，workspace不常驻完整Session/已保存Operation；真实20条页和ID详情，重复候选同有界reader；保留必要业务冲突/重叠/完整性扫描。错误保持且显式重试；R1同时清values/重复候选baseline/待确认精确区间，R2失败输入与最后成功草稿可恢复。 |
| UX1 | 窗口外inspect自动全部累计，保留日/月/活动；主动期间切换才清日。固定2026-10-18/9-1的45分钟1条、窗口内/无记录/活动/清除语义Unit和中文Dark最大AX原生路径通过。 |
| UX2 | 主页面最近5条上界endExclusive且recordedAt<=snapshot.now，不强加趋势下界，日期选择<=asOf；历史截止标题中英。独立AllRecords仍全历史；10-10截止只显示10-1、AllRecords可查10-17，50→60分页/切日返回通过。 |

### 最终受影响验证

环境：macOS27.0.1/26A434；Xcode27.1/27A9275，SDK27.1；专用iPhone18Pro Simulator42609456-859D-41F8-8977-4B2D85A74082、iOS27.0/24A434。未操作其他模拟器数据或私人库。新原始证据 `/tmp/pgos-pr13-review-fix-evidence`；完整命令/SHA/dirty/exit/elapsed见各run JSON和native-run-index.json，原log/xcresult保留。

- final-unit2，同clean 597552a（final-unit1在clean f946相同241/0/1）：242=241PASS/0FAIL/1SKIP、exit0，runtimeWarnings=[]。九完整类：TodoFoundation48、TodoReminder29、SleepReminder4、ImportantDayReminder7、Weight19、InvestmentFoundation32、InvestmentPersistence29、ImportExportRecovery56、AppComposition18。SKIP为隔离32MB HFS+物理低空间环境，未改标。不是重跑全仓517。原始CoreData负例/Widget projection failed code0/Xcode版本解析诊断和两次构建的AppIntents metadata extraction skipped warning保留，不以warnings=[]抹去原日志。
- F5真实落盘10,000 Session与成对Operation，100条含长备注和两段。初始0.317755103秒，Session/Operation各40批fetch、各10000次decode；真实Service→带sequence通知→与AppShell共用Workspace.receive连续4次草稿、checkpoint(含草稿)/pause/resume后仍40/40与10000/10000，仅9条按ID operation decode。不是helper/generation反证；后台发布调度用同receive(on:RunLoop.main)。第二页与第一页共40decode，单ID详情1decode；正式edit/delete、实际ZIP import、读取故障、失败后草稿无隐式重扫和显式Retry恢复通过。Darwin ru_maxrss前后553107456 bytes（包括10k夹具和整个test host，不能解释为workspace峰值或节省比例）；不另做任意硬件阈值或Instruments批次。
- final-ui1：clean f946为10=8PASS2FAIL，未改写为整套通过；final-ui-supp1：clean597552a为4/4PASS（中文Weight最大AX截止、mixed默认/中文Dark最大AX整行导航、旧Weight编辑删除刷新、duplicate候选修改后清除/保存46分钟）。前轮8个PASS方法和生产/Unit源码与597完全不变，逐方法与blob复用证明见ui-evidence-reuse-proof.json；原失败与新补验分开记录。截图及manifest在final-ui1-attachments、final-ui-supp1-attachments，对应map列出名字/绝对路径。
- final-debug2：clean 597552a Debug build-for-testing exit0，App provenance与三包IDs/1.0(7)/min17及真实debug dylib哈希/AlarmKit弱链接核对；final-release1同clean597552a unsigned generic iOS Release exit0；两配置实际App/Share/Widget均保持原Bundle IDs、1.0(7)/minOS17，App provenance Commit=597552a、Dirty=false、Source=localGit、Tag为空。真实Debug dylib和Release executable均有LC_LOAD_WEAK_DYLIB AlarmKit.framework；中英usage描述均存在。精确哈希和原始otool在final-debug2/final-release1-bundle-proof.json与-mach-o.txt。

### 真实失败与补验（分轮保留）

| 运行 | 真实结果与后续 |
| --- | --- |
| red-a / red-a2 | 首次fixture有区分力不足：F1时区变化走另一换代路径而通过，F2提醒不晚于测试clock而invalidReminder；F3确证不能置换。修夹具后再红测，不把夹具错误冒称产品反例。 |
| red-a3 | 原Todo产品源码来自固定2add；同区/正确future后F1退役代次与F2偏移污染红测成立，原始assertions全部保留。 |
| green-ab | 30/30PASS：当时TodoReminder27+F2一项+Weight两项；工作树候选，非最终gate。 |
| focused-c1 | 4/4PASS：真V11.0/v7、停止负例/跨类别、10k真实链首轮；未包含后续review修复。 |
| focused-ui1 / ui2 | 各0PASS2FAIL：虚拟可见行5误当50、计数标签未在viewport、最大AX滚动落入wheel或详情未滚动。修实际same-query表头重现重载问题，并修正常视口驱动；原图树与失败保留。 |
| focused-ui3 | 2PASS1FAIL：Weight与UX1通过，新重复用例系统popover不提供Cancel仅Save anyway，改为原生外点取消。原始AX树保留，候选含驱动补验。 |
| candidate-unit1 / c2ddf18 | 242=240PASS1FAIL1SKIP；三条失败断言在同一个native read failure用例，修预检只针对accepted普通通知，保留Alarm/prepared语义，不改旧断言。 |
| review-fix-unit1 | 109=108PASS1FAIL；新增故障链test expectation被此前queued通知多fulfill，按每条通知sequence精确配对，所有通知仍送生产receive。计attempt先append再注入失败，使失败后无重扫断言有区分力。 |
| review-fix-unit2 | 109/109PASS；工作树候选。最终f946/597552a集中final-unit1/2均含全部后续assertions和补验。 |
| final-ui1 / f946 | 10=8PASS2FAIL。Weight cutoff/50→60/切日返回、UX1中文Dark最大AX、自然期间/跨日事实、手工编辑删除、R2失败关闭重试冷启、R3显式替换、Record独立草稿、running冷启均通过。mixed失败时目标整行被底栏覆盖；duplicate已验证候选45分钟和ID详情，返回后输入框在导航栏下未聚焦。原截图/AX树与失败保留；597552a仅改驱动可见性/键盘断言并新增中文体重用例，不改生产/Unit。 |
| final-ui-supp1 / 597552a | 4/4PASS exit0，原两个失败项以完整视口/键盘断言补验闭环；另补中文Weight Dark最大AX与旧Weight编辑删除刷新。不是同一轮10项全绿。 |

### 独立复核、兼容与设备门

Reviewer `/root/pr13_fix_independent_reviewer` 没有编写本轮代码，读取固定规格/源码diff/生产路径/测试及原始证据，提出并复核：预算停止/空位边界、查队不确定语义、重复候选伪零/排序/过期、所有Editor内容副本清除、中文截止标题和失败重试可达性。原始终审结论见REVIEW本轮追加章节，不由作者代写独立通过。

持久Schema V1–V15、V11.0/11.1历史模型、v11备份wire与工程/身份/签名/minOS均未改变；设备账本仅新增本地取消原因phase，不进备份。兼容路径blob与祖先/原工作区保全在source-compatibility-proof.json（changedCompatibilityPaths=[]，四条checked路径blob全部相同）；实际迁移/ZIP和回滚由最终相关完整类复验。

本轮不授权D1–D4/私人设备与库/签名安装/merge/force/tag/Archive/TestFlight。原AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、签名/真机/远端CI NOT_RUN继续保留。全部本地门通过才恢复READY_FOR_OWNER_DEVICE_GATE，设备门本身不因此通过。

本轮交付提交在固定产品597552a之后只更新五份Markdown；交付SHA以本次交付commit/PR head和外部final-delivery-proof.json核对，避免文件自引用。普通push后核对Draft/base/head和workflows=0、checks=[]；远端CI仍NOT_RUN。

独立原文报告见REVIEW最后章节；全部本地要求闭环，设备/签名/CI门未通过。

## 2026-10-18 第二轮限定补修验收基线

已审交付 e75ac56110cb9c4f58158eaf494087b2ed946324 / 产品597552a020eab22673feed108d8676359efd8822。新 FIX2_GOAL_SHA 由引导 prompt 指定；执行规格为 [REVIEW_FIX2_GOAL](USAGE_REMEDIATION_20261018_REVIEW_FIX2_GOAL_ZH.md)。本表为待执行要求，不复用旧 PASS 预先关闭新问题。

| 项目 | 当前状态 | 必须新增或核实的证据 |
| --- | --- | --- |
| CR-01 | OPEN / NOT_RUN | pending 容量取消跨过 fireAt 后，在实际缺失/取消后收敛，Recheck/重开幂等，未来仍可等待恢复，过期无旧排程 |
| CR-02 | OPEN / NOT_RUN | 两次 phase 真未保存、native 成功移除的反例；原因先可靠持久化，故障恢复后用户意图不误退役，停止负例保持 |
| CR-03 | OPEN / NOT_RUN | 旧 f1 可生成的有效已覆盖 nil V15/v11，直接 complete/skip/再改期、重开/恢复和原子回滚；原始历史事件快照保留 |
| CR-04 | OPEN / NOT_RUN | 编辑/删除候选 B 后返回未变 A，候选与详情/分页一致，A 输入保留且能正常保存 |
| CR-05 | OPEN / NOT_RUN | 计时保存后正式事实仅一条且有效落点；失败仍可编辑，无空外层页，不恢复全量终态缓存 |
| CR-06 | OPEN / NOT_RUN | 固定完整年月日，不依赖真实执行月/年；截止、全部历史与中英文相关断言继续有效 |
| OBS-01 | 故障契约补验 / NOT_RUN | 同一预热 Workspace：实际保存后报错→refresh/retry→缓存revision与后续命令恢复；区分未保存与已提交 |
| OBS-02 | 未确认观察 / NOT_RUN | 一次有界实际入口核验或最小加固；无可达证据可保留 UNCONFIRMED，不因此阻断原F4/交付 |
| RF2-REGRESSION | NOT_RUN | 按最终diff的受影响Unit与关键UI组合、既有计时/草稿/取消/读取保护 |
| RF2-BUILD-REVIEW | NOT_RUN | 最终干净产品SHA的Debug/unsigned Release及既有实包proof；独立reviewer固定代码/原始证据闭环 |

按新 Goal 完成本地连续修复，不每阶段重复全量测试；只文档提交不重建。实际命令、用例、SHA、计数/失败、原始证据位置与必要哈希追加到既有 EXECUTION 和本矩阵，独立结论追加 REVIEW。旧241/0/1是九类242项，不是全仓517重跑；UI原8/2与补4/4继续分轮记录。

六项明确收尾均有完成或反证处置、OBS完成限定工作、必要本地门与独立复核有效，且无未关闭confirmed P0/P1/P2后，才能恢复READY_FOR_OWNER_DEVICE_GATE。原D1–D4、AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、远端CI NOT_RUN不因此通过。


## PR #13 第二轮限定补修本地交付（2026-10-19）

固定 FIX2_GOAL_SHA `41ef47c384464823f9456e9816d574ba7edff563`；产品/测试 `c296a3691d53ce7f5b5bff36fbf7de525d86510f`；前轮产品597552a / 交付e75ac561保留为历史。原worktree从e75干净fast-forward到41ef，六份Markdown增量；未从BASE重建。主工作区三项未知改动保持，固定规格/原交付/base为候选祖先，原PR #13 Draft / base不变。CR-01～06与前轮F1～F5/UX1～UX2、原R1～R8及时间投入历史T编号分别记录，不重新编号或覆盖历史。

| 项目 | 生产处理及可区分证据 |
| --- | --- |
| CR-01 | retire入口独立处理capacityCancellationPending，native真实缺失确认后未来继续capacityWaiting、过期退役/elapsed；普通通知过期先于selected预算判断，正常ringing Alarm不动。可推进时钟跨fireAt，native已消失/仍失败后取消、重开/重复Recheck、不排过去时间；原F3未来恢复在同候选完整Reminder类通过。 |
| CR-02 | 容量原因pending可靠落盘/精确读回前不移除native；主动取消继续原best-effort语义。mode0 pending真未保存即止，native/accepted保持，不尝试waiting写；mode1 pending已保存但waiting真失败，磁盘pending可恢复；mode2实际save后仅报错以精确读回确认，waiting落盘。冷coordinator恢复L，原generation不变、59保留项与预算/停止负例保持。不是AlarmKit容量证明。 |
| CR-03 | 显式规则offset优先；缺值从经过完整sequence/before/after末端验证的第0期created/converted源恢复，在业务事务中冻结。真V11.0单一open→迁移→旧f1等价事务已覆盖nil→V15/v11实际ZIP恢复，含覆盖前无关标题edit；覆盖后当前版本metadata/title、跨时区刷新、删除清单（含task已单次换清单而rule仍指旧清单）在添事件/改rule时间前冻结；0/-1、短/800天、同/改分钟、complete/skip/再次改期、重开/导出恢复、保存失败回滚，所有既有事件/快照字节保持。独立reviewer逐段比对旧f1 happy path；没有运行旧二进制。真实4625602原V11夹具证明派生后继曾丢lead，不参与原始规则投票；旧断言保留并补验。 |
| CR-04 | 正式facts版本变化仅清草稿候选IDs/baseline/展示与旧duplicate提示，保留输入、最后成功草稿和真实写入错误，不让草稿按键扫历史。修改/删除B后不变A候选失效；仍匹配负例仍触发正常重复确认。UI覆盖默认编辑B、中文Dark最大字号删除B，再保存A。 |
| CR-05 | 内层save成功回调标记完成，外层Timer在内层onDismiss后关闭到有效Hub；不把终态payload放回缓存。首次保存注入未提交错误保留备注/时长，重试成功退出两层，稳定Hub按钮可用、History恰好一条3分钟并有正确详情。原Confirm later/冷启动用例保持。 |
| CR-06 | 仅DEBUG+UITesting可注入的WeightReviewClock同供页面/夹具，固定2026-10-18；native日期弹窗核对完整2026/10月再选10日。Unit的live日期对照为2026-11/2027-10，注入后固定日不变；无UITesting正常使用live。未修改主机时间或声称已在未来真实主机日期执行。中英截止、50→60/切日返回/全历史17日断言保留。 |
| OBS-01 | 同一预热Workspace经pause实际save后抛错，对照未save错误，普通refresh/Retry、resume/checkpoint及关联正式delete缓存清理通过。仅commit真正开始后的错误发布原scope失效，仍抛原错，由canonical reader区分结果；body重复/业务拒绝不发布facts失效。真实RunLoop延迟通知链验证刚显示的候选不被误清。不是原生SwiftData自然必现P2。 |
| OBS-02 | load只处理共享当前query，切换权属于initial/select；正常首载/更多/重试/显式切日及旧reader晚返回保持。有界顺序调用真实loader验证旧A按钮入口不能重选B后的A；未证明该启动顺序实际SwiftUI可达，原观察保持UNCONFIRMED，不重开原F4。 |

CR-03恢复边界：技术时间相等本身不证明未编辑。没有第0期、规则曾变化但没有可识别policy，或多次/无法区分的旧墙钟编辑时拒绝编造offset，原事实与事务回滚保持；可显式改系列规则提供policy。f1/当前正式futureSeries编辑有提醒时会显式写offset，优先使用该值；测试含同分钟正式改-1与converted同now正例，以及nil/sameTimestamp歧义拒绝后显式纠正负例。未宣称任意旧nil都可自动恢复。

### 实际环境与最终本地门

macOS27.0.1/26A434，Xcode27.1/27A9275，SDK27.1；专用iPhone18Pro模拟器42609456-859D-41F8-8977-4B2D85A74082 / iOS27.0(24A434)。Xcode串行，隔离合成库；未操作私人库/设备、其他模拟器数据。原始日志、xcresult、截图manifest、实包proof和完整命令/SHA/dirty/exit在 `/tmp/pgos-pr13-fix2-evidence`。本机独立reviewer实际读取，未声称远端reviewer已取得这些开发机产物；下方小型摘要/哈希供远端核对，CI仍NOT_RUN。

- `final-debug6`：clean c296a36，Debug Simulator `build-for-testing` exit0；`final-unit4` 同候选九类252=251PASS/0FAIL/1SKIP，exit0，34.165秒（测试31.015秒）。AppComposition18、ImportExportRecovery57、ImportantDayReminder7、InvestmentFoundation32、InvestmentPersistence32、SleepReminder4、TodoFoundation50（含1SKIP）、TodoReminder31、WeightFoundation21。不是全仓全套重跑。唯一SKIP为隔离32MB HFS+物理低空间环境未具备；不得填满主盘。
- `final-ui-cr05` 同clean c296a36，完整1/1PASS，exit0；中英两分支共124.619秒（命令128.068秒）。`final-ui-regression` 同候选八项结果：8/8PASS，exit0，594.713秒测试体。原fixtureWeight两项在cec的完整PASS、duplicate在302完整PASS、CR04在b45完整PASS按精确生产路径/方法/helper blob复用；并非把变化路径的旧PASS当新候选，未声称一次13/13。
- `final-release1`：clean c296a36，unsigned generic iOS Release PASS，exit0，41.502秒。实包实际proof含App `com.yocruzer.PersonalGrowthOS`、Share `com.yocruzer.PersonalGrowthOS.ShareExtension`、Widget `com.yocruzer.PersonalGrowthOS.ImportantDaysWidget`，均1.0(7)/minOS17.0；App provenance Commit=c296a3691d53ce7f5b5bff36fbf7de525d86510f、Dirty=false、Source=localGit、Tag为空。Debug实际承载dylib与Release主可执行的AlarmKit `LC_LOAD_WEAK_DYLIB`、中英NSAlarmKitUsageDescription核对。App Group等entitlement/工程源码blob不变；unsigned实包不等于签名安装或设备正向证明。
- F5真实10k磁盘链：`testUsageFiveYearSnapshotReusesStatisticsAndBoundsRealDiskPageThenRefreshesChanges` 首次refresh0.3196220397949219秒，40 fact批次/40 operation批次、10000/10000解码；Service草稿和计时命令→真实事件→同一个Workspace后仍40/40与10000 fact解码，9次operation按ID解码，未靠generation不变推断读取。两页20条详情合计解码40、按ID详情1，初始已保存操作正文保留0。全host peakRSS before/after均552763392 bytes，含夹具与测试host，不能声称Workspace独立峰值或节省量。强制正式变更仍进行必要业务完整性检查。
- 预期故障日志保留：腐坏库CoreData259、注入调度/授权/写入错误、Widget projection code0及Xcode runtime invalidDigitCount诊断；没有把这些原始日志删除或冒称自然设备故障。每项测试真实退出与断言以原始xcresult为准。


### 真实失败、补验与中止

| 轮次 | 真实结果与处置 |
| --- | --- |
| red-a | 2FAIL：跨期pending不收敛；两phase真未落盘却移除native并误retired。新路径pending失败即保留native，不伪称两次抛错但实际保存。 |
| red-cr03 / red-b | 首次与修正intent existing分支后存量红例均FAIL；red-b 4FAIL另含候选成员变化、同Workspace陈旧revision/conflict、旧按钮入口。真实V11/旧f1等价事务来源经校验，非新服务首次覆盖。 |
| red-b-build / green-core-build / recovery-build2 | 新测试缺excluding参数、onSaved参数顺序、收紧root后遗留continue分别编译失败；修正后构建成功，不算产品业务红例。 |
| green-core / diagnostic-cr02 | 12项为11PASS1FAIL；单项诊断仍FAIL。native/journal已恢复，测试错误引用旧coordinator；改断言为实际cold实例，三模式精确phase和等待写尝试另加强。原业务断言保持。 |
| green-scope | 10/10PASS；当时候选dirty，不替代最终门。 |
| red-ui-cr05 | 1FAIL，临时仅将自有Timer段替为固定41ef旧段；真实失败准确为保存后外层Timer未退出，故障输入保留先通过。finally恢复当前源码，有来源hash；未重置未知改动。 |
| final-unit1 / 395 | 251=249PASS1FAIL1SKIP；原4625602 V11实包fixture被新“后继一致性”错误拒绝。保留原断言，改为独立原始root证据；recovery-green 5/5PASS。 |
| final-unit2 / cec | 251=250PASS0FAIL1SKIP；尚未含后来新增的业务错误事件反例，不当最终新候选全通过。 |
| final-ui1 / cec | 13项计划在确认新事件回归后主动中止；summary实际3 collected=2PASS/1FAIL（Testing was canceled），exit75。两Weight完整PASS 85.472/50.531秒，mixed被取消；保留SIGINT记录与Xcode取消堆栈，不把它当产品崩溃或13通过。 |
| red-event-scope / scope2 | 各1FAIL，真实延迟通知会清掉刚显示候选。首轮version对象别名对照偏弱但候选失败有效；改独立int快照后6断言红测成立。仅commitAttempted后错失效修复；event-green 4/4PASS同时覆盖OBS两方向、CR04和10k。 |
| final-ui-core1 / 302 | 3=1PASS2FAIL：原duplicate UI完整PASS37.745秒；CR04/CR05中文最大字号读取duration失败。保留断言，局部gutter视口校准。 |
| final-ui-core2 / c98 | 2=1PASS1FAIL：CR04默认编辑/中文Dark最大字号删除完整PASS118.047秒；CR05辅助函数误用普通表单nav标题失败，修为实际确认标题。 |
| final-ui-core3 / b45 | 2=1PASS1FAIL：CR04再次完整PASS117.560秒；CR05中文已返回Hub，但后置查找上方History驱动方向错误，仍记整项FAIL132.412秒。过渡截图不当稳定落点证明。 |
| red-cr03-continuation | 1FAIL（2断言）：新metadata edit导致nil未冻结及后续invalidReminderOffset；先红后修。 |
| continuation-green | 1测试崩溃：新增fixture捕获旧TodoList跨container销毁；改只传UUID，非忽略生产异常。continuation-green2完整1/1PASS，覆盖三种合法后续命令及回滚。 |
| final-ui-cr05 / c296 | 完整1/1PASS：默认与中文Dark最大字号的失败保留、重试退出两层、稳定Hub可操作、历史1条3分钟、按ID详情备注均断言通过。 |
| final-ui-regression / c296 | 8/8PASS，exit0；594.713秒测试体；完整串行结果，无新增失败。 |

### 独立复核与停止边界

Reviewer `/root/pr13_fix2_reviewer` 未编写本轮代码、未运行Xcode/操作模拟器或push，独立核对固定规格/完整diff/旧等价事务/原实包来源/测试与本机原始证据。原文终审追加REVIEW，作者不代写独立通过。历史Schema V1–V15、TransferModels、ZIPArchive及工程blob保持，兼容由实际恢复/回滚补验。

只有六项收尾、OBS限定工作和必要本地门全部有效才恢复READY_FOR_OWNER_DEVICE_GATE。D1–D4未通过；AlarmKit原生正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、签名/私人设备/私人库与远端CI NOT_RUN保持。本轮不签名安装、merge、force push、tag、Archive或TestFlight。交付在产品之后仅文档，SHA以交付commit/PR head和外部final-delivery-proof.json核对，避免文件自引用。


### 可供远端核对的小型结果摘要

| 原始运行 | 候选SHA / dirty | exit | 结果（xcresult） | log SHA-256 |
| --- | --- | --- | --- | --- |
| red-a | 41ef47c38446 / dirty | 65 | 2 total / 0 PASS / 2 FAIL / 0 SKIP | `b0a6ba6e8d4ad1b0a8387ec2981ccc6d584f46cbcc7815cd22eb0685c273116a` |
| red-b | 41ef47c38446 / dirty | 65 | 4 total / 0 PASS / 4 FAIL / 0 SKIP | `d93aa7ac3de694a4ebbc6de3b39031673a0159faabdfadd28436c31984b2825e` |
| red-cr03 | 41ef47c38446 / dirty | 65 | 1 total / 0 PASS / 1 FAIL / 0 SKIP | `959332255d7de88a7bebcf03cce66fc6029e0da115c58821763def96e3e0211e` |
| red-ui-cr05 | 41ef47c38446 / dirty | 65 | 1 total / 0 PASS / 1 FAIL / 0 SKIP | `16596f9c25e578fb4605eebf24dbbac2e03b3f71782dd098ecfdea5784a0c55a` |
| red-event-scope2 | cec2e4d4cc9e / dirty | 65 | 1 total / 0 PASS / 1 FAIL / 0 SKIP | `9e60a1d5a7aab97802ea0f4f52474115d4efd19d8f9fc0718f7ad2893bfe157d` |
| red-cr03-continuation | b45ce36f4332 / dirty | 65 | 1 total / 0 PASS / 1 FAIL / 0 SKIP | `046483886226dc7902e8e2b104bd2663fd8890fdf5d3e7800f9f75bf253d87a1` |
| continuation-green | b45ce36f4332 / dirty | 65 | 1 total / 0 PASS / 1 FAIL / 0 SKIP | `60d3f0d57698b6e977da1d242cfc57b86b8eccb0ad3910df45830ff043b162fc` |
| continuation-green2 | b45ce36f4332 / dirty | 0 | 1 total / 1 PASS / 0 FAIL / 0 SKIP | `94391f68e00438de4d993681b5750ebb914e77fe7a02c6a351a94d9819ee6043` |
| final-unit1 | 395f3bf5dd35 / clean | 65 | 251 total / 249 PASS / 1 FAIL / 1 SKIP | `ad741e339578925b2d82d75f133cb65ebd80a004166fcb286914b86b514bf43d` |
| final-unit2 | cec2e4d4cc9e / clean | 0 | 251 total / 250 PASS / 0 FAIL / 1 SKIP | `00226dc37be74a95c55a7362bf9e36e7d3a9e995fbea0af0be5c7fbc70760707` |
| final-unit3 | 302e3109c8e0 / clean | 0 | 252 total / 251 PASS / 0 FAIL / 1 SKIP | `5d130c61fd51805512488b4bfca30124ead1b0e1ef03b055ad1e7156c327903f` |
| final-unit4 | c296a3691d53 / clean | 0 | 252 total / 251 PASS / 0 FAIL / 1 SKIP | `67ddc2e5fa3bc31b6f40dd28d6db9fcfb01adc620ae76fb0453ff48a825f45d1` |
| final-ui1 | cec2e4d4cc9e / clean | 75 | 3 total / 2 PASS / 1 FAIL / 0 SKIP | `9bd1095ef5a7dcdfc8c1556dff4c4edf6318f9b0957afc50ca9c0814a26f251b` |
| final-ui-core1 | 302e3109c8e0 / clean | 65 | 3 total / 1 PASS / 2 FAIL / 0 SKIP | `abfbdbe233a52b0b83c196761d43497e69d4883fca11ff4e077056b58a960285` |
| final-ui-core2 | c98e3e2100e3 / clean | 65 | 2 total / 1 PASS / 1 FAIL / 0 SKIP | `360a01e739b54b91b6b4d65338d1f4edaa20eaec3e05d97bdf8deb59ff33bec6` |
| final-ui-core3 | b45ce36f4332 / clean | 65 | 2 total / 1 PASS / 1 FAIL / 0 SKIP | `557817651da526394b1a58f9beded56c91258c2f1c3ecc854e26e70824af88cc` |
| final-ui-cr05 | c296a3691d53 / clean | 0 | 1 total / 1 PASS / 0 FAIL / 0 SKIP | `d721430949ae47bebb9c4c9945714f6cb3ff10351132d735324997a00c0206b9` |
| final-ui-regression | c296a3691d53 / clean | 0 | 8 total / 8 PASS / 0 FAIL / 0 SKIP | `96759dacb258662c28a540d4cc48044ff08bf649c838209f64c884c35a17225f` |
| final-debug6 | c296a3691d53 / clean | 0 | 0 total / 0 PASS / 0 FAIL / 0 SKIP | `ec3a18797fa72f62ccec84b64ddb4555fdc50288499c2d66f3577af024138769` |
| final-release1 | c296a3691d53 / clean | 0 | 0 total / 0 PASS / 0 FAIL / 0 SKIP | `88e1e6e721462ced3397dc686b945de73804834fdf4703d46d67416d82062599` |

日志的实际命令、SHA、dirty、退出码和计数来自同名JSON/xcresult，不将计划数作为执行数；原始大产物只在本机证据根。`—`表示无该项摘要，不代表0。

- `native-run-index.json` SHA-256 `0d5ee45465a89d26bf3fb376bdd746ee6201150178cf5a87160df2e1e3c2fa8b`
- `final-evidence-reuse-proof.json` SHA-256 `63266359547d453ee5632537581c498dfe32a317229788fef0cc94114091d6c9`
- `continuity-proof.json` SHA-256 `6874a6413fba1bc65f95fb79e1219d31ab62c30271005bfbb591f499890fd9a4`
- `final-debug6-bundle-proof.json` SHA-256 `45814a0e9d2e9e489a3718947961d561611c3e9b8357124967ad7a968d018afd`
- `final-release1-bundle-proof.json` SHA-256 `01d280514280f3a30d36d304450a17268263f6d12acca95960ab02d7d780f765`
- `final-debug6-mach-o.txt` SHA-256 `ca49ddfd4cdbb2bab060d8ec9fc392132bca50f8dd1bdc9a185bedf7173b252b`
- `final-release1-mach-o.txt` SHA-256 `2da619a9e252e9c7c63d997f72f7f6bc539483c23a5e6732b945d720753eb0b2`
- `final-bundle-assertions.json` SHA-256 `79668d659e18d9cbda57a62c5f7ab881258c10c6fe2a3ed6f9d46467ad3df96c`
- `screenshot-map.json` SHA-256 `287f54a3a27e0a37842cf551f5041f042d55e82564a99dfd47d493054facaf38`
- `original-v11-immutable-sqlite.json` SHA-256 `e56cb03a5c90aba891aae0ad32e47dc0e32eb2ac06ed703e5a9d7f45b26d64d1`
- `red-source-hashes.json` SHA-256 `a7a91c169cb5222d4b8db4b0e7f2feaf7ab8c9eed3fedbf2be3b3a2f8ae16fb1`
- `red-ui-timer-source.json` SHA-256 `fc80db48a21a56646e5b17dba57df26b68a1becac164ed65f5718b451458f6b1`
- `final-ui-cr05-attachments/manifest.json` SHA-256 `0854e417d548ce5584368fe6ebb59c082b420b78169986b652c3f26d4d41bce6`
- `final-ui-regression-attachments/manifest.json` SHA-256 `eeafceb129354aaccd97f0b2751d07ed3b8cad855c1e43df3044afc1c099bd1e`
- final-debug6 `com.yocruzer.PersonalGrowthOS` v1.0(7) minOS17.0 executableSHA256 `43303593fe3bac299ec83fc15424c5ce48c4e4fa9e4dea8585d16bbc729578f9`；provenance `{'Commit': 'c296a3691d53ce7f5b5bff36fbf7de525d86510f', 'Dirty': False, 'Source': 'localGit', 'Tag': ''}`
- final-debug6 `com.yocruzer.PersonalGrowthOS.ImportantDaysWidget` v1.0(7) minOS17.0 executableSHA256 `15dac98175aa7582e720fd6dca4cd2e9eee1ba9946a78c53ea9695b7f7cf5dd5`
- final-debug6 `com.yocruzer.PersonalGrowthOS.ShareExtension` v1.0(7) minOS17.0 executableSHA256 `42841fffbef5b7cf7db4268d0cf41c40243d50c2abbe9ff6a6b51464b2d4df85`
- final-release1 `com.yocruzer.PersonalGrowthOS` v1.0(7) minOS17.0 executableSHA256 `350819f01ff4035a9fe2d64a437ccd851316335fd59540bc2bde6aa71c6329cc`；provenance `{'Commit': 'c296a3691d53ce7f5b5bff36fbf7de525d86510f', 'Dirty': False, 'Source': 'localGit', 'Tag': ''}`
- final-release1 `com.yocruzer.PersonalGrowthOS.ImportantDaysWidget` v1.0(7) minOS17.0 executableSHA256 `e5af21c4a3ffe0136711933f7d8a1269f02f02b5bd3bdc658317117294705637`
- final-release1 `com.yocruzer.PersonalGrowthOS.ShareExtension` v1.0(7) minOS17.0 executableSHA256 `aa3f9e979eb8d847f3f8b20743b671b8779b4098b4b68feb7fd3608c991d54a7`

### final-debug6

```sh
xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Debug -sdk iphonesimulator -arch arm64 -derivedDataPath /tmp/pgos-pr13-fix-derived -resultBundlePath /tmp/pgos-pr13-fix2-evidence/final-debug6.xcresult CODE_SIGNING_ALLOWED=NO build-for-testing
```
### final-unit4

```sh
xcodebuild test-without-building -xctestrun /tmp/pgos-pr13-fix-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=42609456-859D-41F8-8977-4B2D85A74082' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-pr13-fix2-evidence/final-unit4.xcresult -only-testing:PersonalGrowthOSTests/TodoFoundationTests -only-testing:PersonalGrowthOSTests/TodoReminderTests -only-testing:PersonalGrowthOSTests/SleepReminderTests -only-testing:PersonalGrowthOSTests/ImportantDayReminderTests -only-testing:PersonalGrowthOSTests/WeightFoundationTests -only-testing:PersonalGrowthOSTests/InvestmentFoundationTests -only-testing:PersonalGrowthOSTests/InvestmentPersistenceTests -only-testing:PersonalGrowthOSTests/ImportExportRecoveryTests -only-testing:PersonalGrowthOSTests/AppCompositionTests
```
### final-ui-cr05

```sh
xcodebuild test-without-building -xctestrun /tmp/pgos-pr13-fix-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=42609456-859D-41F8-8977-4B2D85A74082' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-pr13-fix2-evidence/final-ui-cr05.xcresult -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testFix2CR05TimerSaveReturnsToHubDefaultAndChineseDarkMaximumText
```
### final-ui-regression

```sh
xcodebuild test-without-building -xctestrun /tmp/pgos-pr13-fix-derived/Build/Products/PersonalGrowthOS_PersonalGrowthOS_iphonesimulator27.1-arm64.xctestrun -destination 'platform=iOS Simulator,id=42609456-859D-41F8-8977-4B2D85A74082' -parallel-testing-enabled NO -collect-test-diagnostics never -resultBundlePath /tmp/pgos-pr13-fix2-evidence/final-ui-regression.xcresult -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testUsageMixedTodayAndGrowthDefaultAndChineseMaximumText -only-testing:PersonalGrowthOSUITests/AppLaunchSmokeTests/testUsageWeightDailyMeansRangesAndDateHistoryEditDeleteRefresh -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testReviewFixUX1OutsideWindowDateSwitchRetainsDateMonthAndDetailChineseDarkAX -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testManualSaveHistoryNilFeelingEditAndDeleteRefreshSameReview -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testExternalR2FailedCloseKeepsEditorAndRetrySurvivesColdLaunch -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testExternalR3ChineseDarkAXConfirmationPreservesOrExplicitlyReplacesSegments -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testRecordDraftSurvivesManualActivitySaveAndChineseDarkAX -only-testing:PersonalGrowthOSUITests/InvestmentUITests/testTimerForegroundBackgroundFrozenConfirmationAndColdRelaunch
```
### final-release1

```sh
xcodebuild -project PersonalGrowthOS.xcodeproj -scheme PersonalGrowthOS -configuration Release -destination generic/platform=iOS -derivedDataPath /tmp/pgos-pr13-fix-release -resultBundlePath /tmp/pgos-pr13-fix2-evidence/final-release1.xcresult CODE_SIGNING_ALLOWED=NO build
```


## 2026-10-19 真机前系统整改 — 新验收登记

| 项目 | 当前状态 | 最小关闭方向 |
| --- | --- | --- |
| SR-01 / P2 | OPEN；新原生回归 NOT_RUN | 真旧 nil 的 Stop/delete/Edit/list/timezone 全链与健康类别隔离、回滚/重开 |
| SR-02 / P2 | OPEN；NOT_RUN | locale-aware 无损体重编辑、日期-only/no-op、实际保存重开 |
| SR-03 / P2 | OPEN；NOT_RUN | Weekly 保存业务日、Entry/Habit/Weight 同一实际 asOf、历史周完整 |
| SR-04 / P2 | OPEN；NOT_RUN | 真实导出持锁时主执行器响应，最终 checkpoint 可靠落盘与快照一致 |
| SR-05 / P2 | OPEN；NOT_RUN | daily/weekly A晚普通错不覆盖B最新设置，当前失败仍反馈 |
| SR-06 / P3 | OPEN；NOT_RUN | 新manual/timer成功释放Workspace editor，草稿/幂等/落点保持 |
| SR-07 / P3 | OPEN；NOT_RUN | 周/月/多次 mixed UI、反馈收起语义、历史截止文案 |
| BV-01 | NOT_RUN；未确认缺陷 | 真实已挂载Growth/保存事件/历史读取计数，按证据局部处理 |
| BV-02 | NOT_RUN；未确认缺陷 | 非有限数量实际Service→SwiftData重开→export，按结果处理 |

固定输入为产品 c296a3691d53ce7f5b5bff36fbf7de525d86510f／交付 62210d9910bae50acf0d58e6cb928e52a67c4a6f。SYSTEM_FIX_GOAL_SHA 由 Owner prompt 固定。详细合法起点、相反操作、失败回滚、消费者和停止条件以新 [Goal](USAGE_REMEDIATION_20261019_PREDEVICE_FIX_GOAL_ZH.md) 为准。结果追加产品SHA、selector、命令/环境/退出码、证据层级和复用范围，不把多轮相加成一次全绿。

D1–D4未通过，AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、远端CI NOT_RUN原样保留。本次审查/规格准备不改变它们。


### 系统整改实现候选（2026-10-19，未恢复READY）

SR01～07已进入本地候选；BV01实测确认重复无关全历史读，候选限定过滤后可见/切离两状态均0次额外Weight/Sleep读取；BV02实测确认inf落库阻断备份，候选拒绝新非有限输入，对旧异常明确阻止普通备份并提供原样保留数据支持恢复，不自动改事实。具体反例、全部消费者/状态矩阵、真实失败及分轮补验见EXECUTION最新系统整改节。

当前不以阶段PASS关闭最终门：集中完整Unit、关键UI组合、干净产品SHA双构建/实包、独立reviewer和普通push尚待完成。green-e的1crash为新增过滤器的活Context寿命错误，已修并定向补验；UI驱动/前提失败与编译失败均逐轮保留。旧设备/环境门状态保持。


### 系统整改最终验收 — READY_FOR_OWNER_DEVICE_GATE

固定Goal3dad3b04；最终产品/测试c55dc10fde79f1fe4dec18b03195119c2049830f，全部生产/Unit源码与完整Unit候选00b65b70相同，仅三个UI驱动方法补强。SR01～07已有明确本地关闭证据；BV01/02均CONFIRMED_AND_FIXED，最终消费者/状态矩阵及实际selector见[EXECUTION系统整改末节](USAGE_REMEDIATION_20261017_EXECUTION.md)。

| 本地门 | 实际运行与限制 |
| --- | --- |
| 完整Unit | final-unit1一次whole target，557=556PASS/0FAIL/1SKIP，exit0；SKIP为独立32MB HFS+物理低空间用例，未伪造通过 |
| 关键UI | final-ui1=18PASS/3FAIL/21，原视频/层级保留；三个仅驱动修正后final-ui2三个完整方法+相邻反馈4/4PASS。18个不变方法逐项原文哈希复用，不拼称一次21全绿 |
| Debug/Release | 最终c55 clean：final-debug2 build-for-testing PASS，final-release1 unsigned generic iOS PASS；实际三包ID/1.0(7)/min17、完整SHA/Dirty=false及AlarmKit弱链接/用途说明核对 |
| 旧保护 | 完整Unit实际执行提醒取消/满队列/停止负例、真旧nil/恢复/媒体失败、计时/幂等/F5；关键UI保留CR04/05、Record草稿、体重截止/分页及Investment窗外选日/跨日历史 |
| 独立审查 | 未参与实现reviewer先写反例，再审固定c55全相关链并直接核对日志/xcresult/19代表图/实包；原文追加REVIEW，无范围内未关闭confirmed P0/P1/P2，明确P3收尾完成 |

原始根/tmp/pgos-pr13-system-evidence；逐轮完整命令、环境、SHA/dirty、退出码、原错/计数/日志hash以及实包与复用证明已加入[SYSTEM_FIX_RUNS.json](USAGE_REMEDIATION_20261019_SYSTEM_FIX_RUNS.json)。阶段green-e的真实SwiftData寿命crash和UI驱动失败保留。原始大产物仅本机，不等于远端CI或远端reviewer已读。

SR01～07关闭、BV01/02限定处置完成，必要本地门与独立终审完成，恢复READY_FOR_OWNER_DEVICE_GATE；普通push和最终交付证明仍依同一授权执行。D1–D4 NOT_PASSED、AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、远端CI NOT_RUN保持。不签名安装、不操作私人设备/库，不merge/force push/tag/Archive/TestFlight。


最终逐项判定：SR01/02/03/04/05 CLOSED；明确P3 SR06/07 CLOSED；BV01/02 CONFIRMED_AND_FIXED。BV02已有异常仍普通export明确失败，原始支持恢复包保留原事实，不是正常可导入备份；不能声称恢复旧NaN/体重精度损失。SR03缺metadata旧Habit沿既有fallback，QuietWins既有信任边界不外推。SR04删除终态复用源码及原删除/擦除测试，不声称另做了“导出等待后删除”专门原生实验。审查完整原文见[REVIEW](USAGE_REMEDIATION_20261017_REVIEW_ZH.md)，终审SHA256 `97a2b772840552d3ae5f56d34f2017c5332f10d4d4ebd5ddf5a124897ca5f469`。

本批达到本地停点即交接，不开展未授权的设备/签名/发布操作；下一步仅Owner另行授权D1–D4。最终文档提交相对c55只有Docs，产品证据继续同源有效。


## 2026-10-19 集成边界复核 — 新验收登记（未实施）

基于已审c55产品/测试及c1fe交付，当前LOCAL_REVIEW_FIX_REQUIRED。详见 [固定审查](USAGE_REMEDIATION_20261019_INTEGRATION_REVIEW_ZH.md) 和 [执行Goal](USAGE_REMEDIATION_20261019_INTEGRATION_FIX_GOAL_ZH.md)。本表只登记下一轮验收，未运行新原生测试；旧分轮和审查原文保持。

| 项目 | 当前状态 | 必须提供的关闭证据 |
| --- | --- | --- |
| IR-01 / P2 | OPEN；原生回归NOT_RUN | 实际事件桥下stopped/unresolved和混合健康数据有限收敛；健康三类/Settings gate waiter可完成；真实变化和回滚保持 |
| IR-02 / P2 | OPEN；NOT_RUN | 两渠道accepted future隔离、取消/持久确认失败、冷重开、明确纠正恢复；ringing/Stop/retired及容量保护 |
| IR-03 / P2 | OPEN；NOT_RUN | Settings关闭重建/共享owner、同值新意图、旧普通错/成功/取消、当前失败/明确off和无新B时A合法完成 |
| IR-04 / P2 | OPEN；NOT_RUN | 真实import持锁下重命名busy，失败草稿可见可重试、成功仅一次、普通错/取消/不串活动 |
| IR-05 / P3 | OPEN；NOT_RUN | BV01自然日基数与真实mounted读取链；Weekly受控seed/reader/选周/未来推进；LA午夜DST/周一边界 |
| V-01 | REQUIRED_BOUNDED_VALIDATION / NOT_RUN | 真实raw SQLite写事务barrier→独立生产对账→SwiftData.save/MainActor probe；快速错误或阻塞的真实证据及释放后恢复 |
| O-01 | UNCONFIRMED；非阻断 | 可随IR05观察已打开Weekly选周/草稿寿命；未证实不先改产品、不单独阻断 |

新V01不改写已完成BV02原值保留结论；源码写竞争不等于已经复现主线程阻塞。IR05不推翻旧条件下实际PASS/actualFetches=0。完整生产触发、反证、selector、最终SHA、原始证据与复用依新Goal登记。

恢复READY条件：IR01～05明确关闭/有效生产反证；V01为VERIFIED_SAFE/DISPROVED/CONFIRMED_AND_FIXED且有原生证据，VALIDATION_BLOCKED不能放行；必要最终门、双构建/实包和未参与实现reviewer终审完成；无范围内confirmed P0/P1/P2及明确P3收尾。O01仅UNCONFIRMED不阻断。D1–D4 NOT_PASSED、AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、远端CI NOT_RUN仍保留。

### IF-A 定向进展（非最终集中门）

原生平台：本机 Xcode / iOS SDK 27.1、iOS Simulator runtime 27.0 (24A434) arm64，合成测试 simulator 42609456-859D-41F8-8977-4B2D85A74082，主协调者串行运行。完整命令/退出/dirty/日志hash见 INTEGRATION_FIX_RUNS.json；证据根 /tmp/pgos-pr13-integration-evidence。所有当前轮基于b495bea的未提交候选，不能冒称干净产品最终门。

- red-a-build：沙箱插件/CoreSimulator访问失败（exit -5）；正常本机权限 red-a-build2 PASS。red-a实际执行2方法均FAIL（12断言失败）：stopped刷新仍save/post；双owner同值新意图被旧结果覆盖。
- red-b-build PASS；red-b一个完整方法FAIL：两渠道×取消前journal/native cancel/取消后确认三阶段；Alarm旧请求未取消，Notification误用capacity reason。夹具仅增加channel参数，按旧f1既有显式channel选择接线，保留真实V11/事件逻辑。
- green-a-build2因测试桩private跨文件可见性编译FAIL，修测试可见性后build3/4 PASS。green-a实际Settings已完成关闭/重建、偏好和系统请求断言，但测试清理第二次触发onDismiss expectation，host崩溃exit65；保留原log/xcresult，不能算6PASS。
- 清理回调改为一次性，并重新执行六个完整方法green-a2：6/6PASS。含停止显式/旧nil/active unresolved、混合健康Todo/ImportantDay/Sleep、生产事件桥与gate等待；两渠道三阶段冷重开/明确纠正恢复；daily/weekly旧成功/错误/取消、同值意图、明确off/当前错/无新B合法完成；实际MediaStorage sheet关闭/重建。
- focused-a-build PASS；focused-a：45/45PASS，包括两个完整提醒类（31 TodoReminder+11 ImportantDayReminder）及三个集成方法。新增外部真实编辑使旧代次失效且最终实际请求用最新标题、真实跨区save失败回滚/无事件/重试恰一次、系统Stop不复活/正常elapsed Alarm仍ringing对照。未跑全量Unit或最终构建。

实现：仅refresh用onlyIfChanged保存，stopped在候选前排除；生产TodoReminderEvents由AppShell与挂载测试共同使用。unresolved未来native两渠道统一取消并用retired终结该generation，pending优先且不进入capacity reason。Settings意图Scope由AppShell持有，daily/weekly独立、MediaStorage重建的新wrapper共用Scope；所有结果仍有token/cancel/偏好三重检查。未关闭时取消合法A，仍保留合法完成。

IR01～03当前有定向关闭证据，最终固定候选/独立终审尚待；IF-B的IR04/05、IF-C V01、IF-D集中门及交付继续同一授权。不恢复READY。

### IF-B / IF-C 定向收敛及独立异议补修

独立reviewer新增IR02邻接P2：retired Alarm在冷重开查询失败时全局外抛；review-a-red 1方法FAIL/4断言，修成局部cancellationPending。focused-b-clock 3/3PASS：该完整链（健康三类/恢复/不复活）、真实10000日Growth、固定Weekly seed/reader。reviewer已直接核对原始xcresult支持关闭此邻接反例，仍待最终候选绑定。SDK27.1与runtime27.0(24A434)已在前节准确区分。

IR04：以真实ExternalCaptureImporter.scan/consume在attachment checkpoint持StorePublication，输入原活动A→B→Save；red-rename首轮仅夹具附件名非法，red-rename2仅系统alert丢失AX标识，均FAIL且不计产品红例；修驱动后red-rename3完整到Save，因busy后alert关闭/B不可达而FAIL，原源码已保存且哈希与manifest一致。改为按活动ID重建的sheet，失败保留输入/错误、成功或明确Cancel才dismiss，Archive/Restore也只在成功后关闭，阻止隐式交互丢稿。green-b-ui 4方法=3PASS/1FAIL，普通保存错误/重试/Cancel/另一活动、Weekly原完整方法及固定时钟推进均PASS，busy方法因底层Hub与sheet调试控件重名而FAIL；green-b-ui2完整busy链直到成功均已通过，仅最后“文字出现次数”把额外canonical调试文字算作第二条而FAIL。改成实际@Query持久活动数，green-v01同轮busy完整方法PASS（含释放前正式仍A/B可见、释放后重试成功、持久数量1）。各FAIL/录屏/AX均保留，不拼称一次4/4全绿。

IR05：BV01使用固定LA 2026-10-19 00:30 +明确Gregorian calendar逐自然日构造10000日，直接反算旧index*86400公式确为9973日。真实Growth注入相同now/zone，仍经过真实InvestmentService→didSave和可见/切离reader，正式Weight增删/活动变更正对照不变。Weekly固定LA周一00:00:30，当前事实为-10s（同周）、未来+120s、历史周日中午；seed和真实summary共用受控clock/zone，普通App仍Date()/本地时区。fixed clock单元验证任意live时间变化不改变asOf，显式+180s后未来三事实纳入；两个真实Weekly UI完整方法PASS。首个clock构建因误用HabitService calendar参数FAIL，已按实际API修正，并用前周一创建Habit保证可信生效。O01未产生跨周父刷新原生反例，保持UNCONFIRMED/非阻断，未预改导航寿命。

V01：首次有界原生red-v01实际1FAIL。入口为exportRetainedQuantityData→真实BEGIN IMMEDIATE已持有→AlarmClient真实观察回调→production reconcile→journalCommit实际SwiftData.save；独立执行器看到生产保存入口后才投递MainActor probe，2s独立fail-safe释放。原始序列：writer-frozen, production-journal-entry, native-save-held, independent-probe-submitted, probe-failsafe-timeout, release-requested, writer-released, native-save-success, main-probe。明确确认主执行器等writer释放，不是前置查询或手写SQLite假保存。

同批最小修复：TodoTaskService事务与intent journal commit共用现有按真实store root识别的StorePublication；主线程try-lock busy返回，worker仍等待，raw SQLite冻结/媒体归档合同不删除。green-v01 3/3PASS（2 Unit+1 UI）：同一raw/Alarm链变为writer-frozen, production-journal-entry, independent-probe-submitted, main-probe, todo-command-busy-input-retryable, release-requested, writer-released；writer仍持有时实际native-save被互斥阻止，journal状态诚实confirmationRequired，Todo命令原文本/事实不变且释放后可重试，原ID/Infinity bitPattern/unit/result和旧BV02原值恢复保护通过。V01定向结论CONFIRMED_AND_FIXED；最后再为原图/元数据/源文件字节加了同方法断言，进入下一次最终完整Unit。writerReleased观察只在实际SQLite ROLLBACK返回OK后登记。

当前IR01～05/V01已具上述定向证据；最终集中Unit、必要保护UI、干净候选双构建/实包和独立全范围终审仍待，不恢复READY。证据根、实际命令/退出/全部真实FAIL/摘要hash见本机及INTEGRATION_FIX_RUNS.json。原设备/发行/Share/Safari/低空间/CI状态保持。

## 2026-10-19 IF-D 最终集中门与交付 — READY_FOR_OWNER_DEVICE_GATE

固定 Goal `b495bead6c9910ec1e15631227c1146176819583`；产品/测试 `53eeb1d3410630f836bbc3e713c79f9f157a4081`。IF-A checkpoint `cf3d3208206f50f805e252da2f17d42f063a6329`，IF-B/C 整合后固定最终产品。下表绑定最终干净产品（阶段 dirty 红/绿运行单独列示），不替换旧 SR/BV/CR 或先前失败记录。

| 条目 | 结论与生产证据 | 相反操作/邻接保护 |
| --- | --- | --- |
| IR-01 CLOSED | 共用实际 AppShell TodoReminderEvents；Stop/旧 nil Stop/unresolved 无变化不保存/发布，混合健康跨区有限收敛且 gate waiter 完成 | 真实编辑仍使旧代次失效；实际写失败回滚及 retry 恰一次事件；三个起点必要事件 1/1/2 |
| IR-02 CLOSED | 真 V11→旧 f1 两渠道 accepted future→隔离→三个取消失败阶段→冷重开→确认→futureSeries 明确纠正后新 native ID | cancellationPending 优先；Stop/retired 不复活；elapsed ringing/容量保护；reviewer 新增 retired query 故障局部收敛 |
| IR-03 CLOSED | AppShell 稳定 per-channel Scope 接入 MediaStorage，实际 sheet 关/重开同值 B 隔离 A 的 success/error/cancel | B off、当前真错、无 B 时 A 合法完成、两渠道独立；onChange 未提交时偏好变化仍保护 |
| IR-04 CLOSED | 按活动 ID 的 sheet；真实 ExternalCaptureImporter.scan/consume attachment checkpoint 持锁→Save busy 保留 B/正式 A/主响应→释放重试唯一活动 | 普通失败重试、明确取消、成功结束、另一活动不串稿；SR06/Record 独立草稿/CR05 相邻保护 |
| IR-05 CLOSED | LA 午夜按 calendar 建 10000 日（旧秒式仅9973）；Growth 真实 Service→事件→挂载 reader；Weekly seed/summary/UI 同固定 clock 并显式推进 | 可见/切离 actualFetches=0；真实 Weight 增删/活动 metadata 正例；周一首分钟当前/未来排除/推进纳入/历史周日 |
| V-01 CONFIRMED_AND_FIXED | 真实 raw writer→独立 Alarm observation→生产 journal→实际 SwiftData.save 红例确认 MainActor 等待；Todo transaction/journal 共用既有发布互斥后快速 busy | probe 先于实际 ROLLBACK，状态诚实/输入可重试、释放后恢复；原 SQLite/媒体冻结、Infinity bitPattern/ID/unit/result/原图与 metadata 字节保持 |
| O-01 UNCONFIRMED | 未取得原生输入丢失反例，非阻断 | 未据此预改导航 |

修前 red-v01 原始因果：`writer-frozen → production-journal-entry → native-save-held → independent-probe-submitted → probe-failsafe-timeout → release-requested → writer-released → native-save-success → main-probe`。修后：`writer-frozen → production-journal-entry → independent-probe-submitted → main-probe → todo-command-busy-input-retryable → release-requested → writer-released`。release 探针位于实际 SQLite ROLLBACK 返回 SQLITE_OK 后；独立 probe 在真实保存入口后投递，未拿前置权限等待当保存竞争。原 raw 是支持恢复包，不是普通可导入备份。

### 最终同 SHA 本地集中门

- final-debug-build：clean 53eeb1d，Debug Simulator build-for-testing exit0，7.798秒。
- final-unit：同 clean SHA 一次完整 PersonalGrowthOSTests，568=567 PASS/0 FAIL/1 SKIP，exit0，50.884秒；runtimeWarnings=[]。唯一 SKIP：TodoFoundationTests/testRealLowSpaceVolumeHealthyOpenMigrationAndCorruptCopyFailure，需要隔离32MB HFS+镜像，未填主卷。V01 最终方法包含原图字节加强并实际执行。
- final-ui：同 clean SHA，七个完整方法 7/7 PASS、0 SKIP，exit0，298.728秒；runtimeWarnings=[]。两个 IR04、两个 Weekly、Todo repeat/Stop/restart、daily/weekly off/relaunch、CR05 default/中文Dark最大字保存落点。完整 selector、command 数组和原始record/log/summary哈希见 INTEGRATION_FIX_RUNS.json，未只重跑尾断言。
- final-release：同 clean SHA，unsigned generic iOS Release build，CODE_SIGNING_ALLOWED=NO，exit0，42.529秒；不是 Archive。两构建实际 App/Share/Widget 为原 bundle ID、1.0(7)、minOS17.0；两份 App provenance 完整53eeb1d/Dirty=false/Source=localGit/Tag空；AlarmKit 为 LC_LOAD_WEAK_DYLIB，中英 NSAlarmKitUsageDescription 存在；Release三个bundle经codesign只读检查均not signed at all。

环境：主本机 arm64/macOS27.0.1(26A434)，Xcode27.1(27A9275)、iPhoneOS/iPhoneSimulator SDK27.1；专用 iPhone18Pro 模拟器 runtime iOS27.0(24A434)，ID42609456-859D-41F8-8977-4B2D85A74082。模拟器/Xcode操作串行，无私人数据、未改宿主日期/时区。LA固定clock及en/zh测试参数进入真实reader，普通启动实时。

四个最终运行均clean，142个tracked非Docs文件的source manifest完全一致且对应Git产品SHA。纯文档交付不重建。Release三个 executable SHA256：App `caf8c71cd1ddcc687d105932d6b47559717b95d98b09e8d5d9b8699685820865`；Widget `e5af21c4a3ffe0136711933f7d8a1269f02f02b5bd3bdc658317117294705637`；Share `aa3f9e979eb8d847f3f8b20743b671b8779b4098b4b68feb7fd3608c991d54a7`。完整Debug/Release实际plist、Mach-O、签名输出和各包哈希保留本机proof，摘要及proof哈希入机器记录。

本机证据根 `/tmp/pgos-pr13-integration-evidence`；每轮 .json/.log/.xcresult/-summary.json 保留真实结果。最终UI导出18 PNG+manifest共19项哈希；代表图：17C729FC（busy正式A/草稿B/锁held）、1E30C7C7（释放后成功）、C4CE58FC（普通失败输入）、0DAED3A5（另一活动）、3FF670FC（周一当前）、0B697752（推进后未来纳入）、07B11382（历史周日）、729FDC9F（中文Dark最大字Hub）。已直接查看代表像素；appearance-driver按实际marker切Dark，结束恢复light。不是声称已看全部附件或设备VoiceOver通过。

### 独立复核与范围审计

独立 reviewer `/root/integration_independent_reviewer` 未写产品/测试；先登记反例，阶段审查实际发现 retired Alarm query 邻接 P2，同批红绿修复；正式终审原文完整追加 REVIEW，SHA256 `a0c3e3f5cfabd7baa857439dd5e51449a8736ee87a1e11c4d078a130a0cd4c3f`。其直接审读固定diff/未改调用者、既有log与xcresult、八张代表图和实际六bundle，独立复算34阶段轮次68个record/log哈希及四最终轮次、四份manifest、19附件hash；支持本地READY，无范围内未关闭confirmed P0/P1/P2及明确P3。实现者未代写终审。

已认可SR02/03主体、SR06/07、BV01/02及旧R/F/CR保护保持；完整Unit执行提醒取消/容量/Stop、legacy nil/迁移/回滚/恢复、checkpoint/晚pause-finish、editor/F5等。Schema历史、project配置、Transfer/ZIP版本与固定Goal不变。最终必要UI集中跑上述七项，其它未受影响旧UI仅保留历史有效记录，不冒称本轮重跑全部UI或原生系统客户端。

沿原分支普通commit/push唯一OPEN Draft PR13、base codex/time-investment-v1；不覆盖并发有效提交，交付前后核对远端head及PR。产品53eeb1d与之后仅Docs交付SHA分开；后者以实际commit/PR head和本机final-delivery-proof.json核对。主工作区三项未知改动保留。本地批次停在Owner设备门，D1–D4 NOT_PASSED、AlarmKit 原生正向 NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间 SKIP/NOT_RUN、远端 CI NOT_RUN 保持。不操作私人设备/库、签名安装、merge、force push、tag、Archive 或 TestFlight。

### 全部实际分轮（total/PASS/FAIL/SKIP）

red-a是两方法失败（IR01 no-op与IR03旧owner），red-b是一方法失败（两渠道）；green-a是5PASS/1FAIL，实际Settings链后清理重复onDismiss expectation造成host崩溃，不算六绿，修清理后green-a2六完整方法通过。focused-a 45项保护通过。review-a-red一方法四断言失败是真实retired查询问题，修复后focused-b-clock三完整方法通过。

red-rename首轮为附件命名夹具错误；red-rename2为alert AX驱动错误；red-rename3才是旧alert busy后输入不可达的产品红例。green-b-ui的3PASS/1FAIL是busy控件重复匹配；green-b-ui2完整busy→释放→保存已过，仅最终文字计数把调试文本误算第二活动；改用实际@Query活动数后green-v01三完整方法及最终UI全部通过。red-v01是真实保存阻塞的一方法FAIL。未将夹具/驱动错误冒充产品红例。

构建失败也原样保留：red-a-build exit-5为沙箱macro/CoreSimulator限制；正常权限red-a-build2通过；green-a-build2为测试private跨文件访问编译失败；focused-b-clock-build为误传HabitService参数编译失败。它们无测试体，不伪造FAIL测试数。以下38轮各自命令、环境、HEAD/dirty和log/record SHA256全部见机器摘要；阶段dirty是明确记录的当时源码，不能冒充clean最终SHA。

| 运行 | source HEAD/状态 | exit | total/PASS/FAIL/SKIP |
| --- | --- | --- | --- |
| red-a-build | b495bead6c99/dirty | -5 | 无测试体（构建） |
| red-a-build2 | b495bead6c99/dirty | 0 | 无测试体（构建） |
| red-a | b495bead6c99/dirty | 65 | 2/0/2/0 |
| red-b-build | b495bead6c99/dirty | 0 | 无测试体（构建） |
| red-b | b495bead6c99/dirty | 65 | 1/0/1/0 |
| green-a-build | b495bead6c99/dirty | 0 | 无测试体（构建） |
| green-a-build2 | b495bead6c99/dirty | 65 | 无测试体（构建） |
| green-a-build3 | b495bead6c99/dirty | 0 | 无测试体（构建） |
| green-a-build4 | b495bead6c99/dirty | 0 | 无测试体（构建） |
| green-a | b495bead6c99/dirty | 65 | 6/5/1/0 |
| green-a-build5 | b495bead6c99/dirty | 0 | 无测试体（构建） |
| green-a2 | b495bead6c99/dirty | 0 | 6/6/0/0 |
| focused-a-build | b495bead6c99/dirty | 0 | 无测试体（构建） |
| focused-a | b495bead6c99/dirty | 0 | 45/45/0/0 |
| focused-b-clock-build | cf3d3208206f/dirty | 65 | 无测试体（构建） |
| review-a-red-build | cf3d3208206f/dirty | 0 | 无测试体（构建） |
| review-a-red | cf3d3208206f/dirty | 65 | 1/0/1/0 |
| review-a-green-build | cf3d3208206f/dirty | 0 | 无测试体（构建） |
| focused-b-clock-build2 | cf3d3208206f/dirty | 0 | 无测试体（构建） |
| focused-b-clock | cf3d3208206f/dirty | 0 | 3/3/0/0 |
| red-rename-build | cf3d3208206f/dirty | 0 | 无测试体（构建） |
| red-rename | cf3d3208206f/dirty | 65 | 1/0/1/0 |
| green-b-build | cf3d3208206f/dirty | 0 | 无测试体（构建） |
| red-rename-build2 | cf3d3208206f/dirty | 0 | 无测试体（构建） |
| red-rename2 | cf3d3208206f/dirty | 65 | 1/0/1/0 |
| red-rename-build3 | cf3d3208206f/dirty | 0 | 无测试体（构建） |
| red-rename3 | cf3d3208206f/dirty | 65 | 1/0/1/0 |
| green-b-build2 | cf3d3208206f/dirty | 0 | 无测试体（构建） |
| green-b-ui | cf3d3208206f/dirty | 65 | 4/3/1/0 |
| red-v01-build | cf3d3208206f/dirty | 0 | 无测试体（构建） |
| green-b-ui2 | cf3d3208206f/dirty | 65 | 1/0/1/0 |
| red-v01 | cf3d3208206f/dirty | 65 | 1/0/1/0 |
| green-v01-build | cf3d3208206f/dirty | 0 | 无测试体（构建） |
| green-v01 | cf3d3208206f/dirty | 0 | 3/3/0/0 |
| final-debug-build | 53eeb1d34106/clean | 0 | 无测试体（构建） |
| final-unit | 53eeb1d34106/clean | 0 | 568/567/0/1 |
| final-ui | 53eeb1d34106/clean | 0 | 7/7/0/0 |
| final-release | 53eeb1d34106/clean | 0 | 无测试体（构建） |


## 2026-10-19 TERMINAL_FIX — TF-A / FIXES_IN_PROGRESS

固定 Goal `6430a8570ce2d3528c37d491c1252f97066e8da9` 已全文读取；沿原 worktree/分支、唯一 PR #13 连续 TF-A→TF-D。旧运行记录原样保留，不转记本轮 PASS。

- RR-01：真实 V11 nil → 旧 f1 普通编辑（override=false）→ accepted 两渠道 → 升级隔离/取消确认 → 同值同渠道明确应用未来 → 新请求/冷重开；相反操作覆盖 Stop、未确认取消、普通元数据和幂等重试。
- IC-02：真实旧08:00 pending → 设置改09:00/add挂起 → sheet实际移除且无B → 当前错误 → settle/重开核对偏好/native/反馈；对照成功、新B同/异值/关闭、daily/weekly独立及清理未确认。
- RR-02：真实 SleepService 次日目标 → 时钟跨生效日 → raw BEGIN IMMEDIATE held → refresh→observe→SwiftData.save → 独立MainActor probe/可靠释放 → 事实/回滚/恢复；相反操作覆盖无竞争、回拨和等待后规则变化。

尚未运行本轮红例、修复或最终验证；独立预审和原生证据随后原样追加。O-01 不重复开项。


### TERMINAL_FIX TF-B 限定实现与阶段验证

本轮原证据根 `/tmp/pgos-pr13-terminal-evidence`；运行器保存每轮实际 command 数组、HEAD/dirty、142文件源码manifest（数量以机器记录为准）、退出码、耗时、原始 log/xcresult。三条红例是生产策略，替身仅控制 native 外部结果；RR02 的 writer 为实际 raw retained export 的 BEGIN IMMEDIATE/ROLLBACK。

| 编号 | 最终操作与保护 | 阶段证据 |
| --- | --- | --- |
| RR-01 | 仅 open/live 系列 nil 且无法推导旧policy，在明确future确认时renew当前及受影响open期次；同瞬间重编码当前wall time，规则/意图同事务；可推导nil bootstrap、普通元数据、已停止系列不借此续代 | 真V11→旧f1普通编辑false，两渠道accepted→quarantine→同值实际TodoEditorView.save→native唯一新请求→幂等→冷开；旧deleteList邻接、保存失败完整snapshot回滚、取消未确认先纠正不并排、确认后冷开、SystemStop后metadata不复活；旧override=true改值/正常ringing/容量由原测试保护 |
| IC-02 | 当前ticket由稳定Scope的命令在共享gate内完成清理，query后再次核ticket，确认native不存在；稳定Scope保存失败与cleanupPending，重开实际Text展示，未确认提供重试 | daily/weekly真08:00→09:00add挂起→实际sheet移除无B→当前错误→pending0/偏好off→重开错误截图；24分支晚错/成功/cancel×新B无/同值/异值/off；cleanup不生效诚实pending→重试确认；6分支清理query内晚到B，旧cleaner零误删；原跨sheet/渠道独立保护 |
| RR-02 | observe在同发布锁下fresh重读保存；主线程try忙立即返回，busy不再冒充corrupt；只记录rule ID与已观察瞬间的fence，setGoal先flush；workspace合并等待，仅真实busy再等，I/O错不循环 | red-chains实际native-save-held且probe timeout，释放后probe；green三项及扩展矩阵probe在ROLLBACK前，held marker仍false，回拨setGoal busy保留事实；第二publisher在retry前获锁，actual didDefer后释放，无额外用户refresh自动持久恢复，回拨改历史仍拒绝 |

合法自动入口有限核对：AppShell.task/active先Investment checkpoint/Sleep.refresh随后await importShares；Todo transaction及journal已用同StorePublication；本轮Sleep.observe加入同锁；Investment transaction同锁且workspace coalesced checkpoint重读后恢复、晚pause/finish保护；Share importer在worker整个publication临界区内操作。widget rebuild及普通统计是读路径，没有因函数名字另开项目。新Sleep fence不保留ModelContext/旧规则跨await；Scope反馈不依赖已移除页面再触发onChange完成清理。

实际分轮：red-build通过；red-chains **3/0PASS/3FAIL**（原RR01同时暴露跨区wall-time和过早retry断言，最初same-generation/stopped/native0是产品红例；末native1来自后续重试不能当首次恢复）；green-build→green-chains **3/3PASS**。expanded-build/expanded-build2通过。focused-matrix与focused-matrix2各 **36=35PASS/1FAIL**，真实失败保留：挂载实际editor callback后过早第二次service.edit增加revision，首轮并发reconcile、第二轮仍在首次排程settle前编辑，造成checking。只修夹具时序，保留全部业务断言；focused-build3/4通过，focused-matrix3 **37/37PASS**，完整重跑原方法及邻接矩阵。不是一次历史全绿。

独立reviewer先只读预审，阶段指出第二次busy恢复丢失，同批已修复并以真实二次持锁测试闭环；独立原文附REVIEW。当前仍FIXES_IN_PROGRESS，待固定干净产品SHA的集中完整Unit、关键UI、双构建/实包及终审后交付。Schema/ZIP/project/IDs/版本不变；O-01非阻断UNCONFIRMED，所有旧设备/Share/Safari/低空间/CI限制保留。


### TERMINAL_FIX TF-C / TF-D 最终集中门与交付

最终固定干净产品/测试 `744e7729f103549184574e99e311ce5c380a4a16`。先前fcd1完整Unit574=573PASS/0FAIL/1SKIP通过；独立审查发现两张挂载错误截图实际纯黑，不能证明可见错误。随后仅修挂载测试接入真实UIWindowScene和layer截图，visible-feedback完整方法1/1PASS，两张中文错误图直接可见；新744e772上重新完成整套最终门，不仅复用前一次Unit。黑图与原始结果原样保留，生产blob全同fcd1。

最终四轮均clean且同SHA：candidate2-debug-build exit0；candidate2-unit **574=573PASS/0FAIL/1SKIP** / runtimeWarnings=[]；candidate2-ui **3/3PASS，0SKIP** / runtimeWarnings=[]；candidate2-release **unsigned generic iOS build exit0**（非Archive）。精确command、destination、耗时、source manifest与record/log/summary SHA256见本轮JSON。环境arm64/macOS27.0.1(26A434)、Xcode27.1(27A9275)、SDK27.1，专用iPhone18Pro/iOS27.0(24A434)/42609456-859D-41F8-8977-4B2D85A74082；Xcode原生操作串行，未修改宿主时间/私人样本。

关键UI实际完整selectors：AppLaunchSmokeTests/testTodoDailyRepeatCompletionSkipStopAndRestartKeepsOneOpenOccurrence；AppLaunchSmokeTests/testSystemDailyWeeklySettingsKeepExplicitOffAcrossRelaunch；SleepUITests/testGoalVisibilityAndDeniedReminderRemainIndependentOfSavedFacts。RR01实际同值编辑器及IC02真实sheet关闭/重开由最终Unit的挂载完整链证明；后者最终两图真实中文off+红色错误可见。UI前两方法未产生截图，manifest如实记录；睡眠方法有1张PNG。其它未改UI只保留历史有效记录，没有声称本轮重跑全矩阵或真机系统客户端。

RR02最终因果：writer-frozen→production-observe-entry→independent-probe-submitted→marker-pending-after-refresh→main-probe→release-requested→writer-released→second-publisher-held→production-observe-entry→second-busy-observe→production-observe-entry→native-save-free（独立线程之间允许不改变因果的交错，精确顺序以原log为准）。回拨尝试在raw held时busy，观察fence待锁释放fresh合并，最终marker持久/错误清除，无额外用户refresh；随后回拨改变目标被拒绝。旧V01真实Todo journal竞争、非有限quantity原bitPattern/ID/unit/result、原图字节、raw snapshot保留及Investment晚checkpoint/pause/finish均在本轮完整Unit中实际通过。

实包Debug/Release各App、Share、Widget均核对原Bundle IDs、1.0(7)、MinimumOS17.0，两个App BuildProvenance为完整744e772/Dirty=false/Source=localGit/Tag空，Mach-O AlarmKit为LC_LOAD_WEAK_DYLIB，en/zh-Hans用途说明非空；Release三个codesign -dv均not signed at all。四份142文件manifest同字节且独立比Git候选；详细二进制hash和签名输出在final-bundle-and-gates.json，证明hash入本轮JSON。project/plist/历史schema/ZIP均未改，未引入依赖。

独立reviewer `/root/terminal_independent_reviewer` 原文终审SHA256 `991c9453c63e715c8f9e546d9fb97b0ee43abbbddae5d2293aaba0adbac6364d`，原样追加REVIEW。其先独立提反例，阶段发现第二busy恢复遗漏并由本轮闭环，又发现黑图证据缺口后补验；最终直接核完整相关调用者、xcresult/log/代表图与六实包并复算。范围内无未关闭confirmed P0/P1/P2，满足本地READY；O-01仍非阻断UNCONFIRMED。初fetch与simctl的沙箱权限尝试失败属于工具环境，提升到授权本机只读/正常Git操作后恢复，未记成测试PASS或产品缺陷。

以下本轮19次实际分轮全部保留，不重写之前集成38轮。原red-chains 3FAIL、两次focused的夹具时序FAIL、黑图证据问题及全部补验不改写为一次全绿。唯一Unit SKIP仍是物理低空间隔离HFS+图，不填主卷。

| 实际轮次 | source HEAD/状态 | exit | total/PASS/FAIL/SKIP |
| --- | --- | --- | --- |
| red-build | 6430a8570ce2/dirty | 0 | 无测试体（构建） |
| red-chains | 6430a8570ce2/dirty | 65 | 3/0/3/0 |
| green-build | 6430a8570ce2/dirty | 0 | 无测试体（构建） |
| green-chains | 6430a8570ce2/dirty | 0 | 3/3/0/0 |
| expanded-build | 6430a8570ce2/dirty | 0 | 无测试体（构建） |
| expanded-build2 | 6430a8570ce2/dirty | 0 | 无测试体（构建） |
| focused-matrix | 6430a8570ce2/dirty | 65 | 36/35/1/0 |
| focused-build3 | 6430a8570ce2/dirty | 0 | 无测试体（构建） |
| focused-matrix2 | 6430a8570ce2/dirty | 65 | 36/35/1/0 |
| focused-build4 | 6430a8570ce2/dirty | 0 | 无测试体（构建） |
| focused-matrix3 | 6430a8570ce2/dirty | 0 | 37/37/0/0 |
| final-debug-build | fcd1c9b0c310/clean | 0 | 无测试体（构建） |
| final-unit | fcd1c9b0c310/clean | 0 | 574/573/0/1 |
| visible-feedback-build | fcd1c9b0c310/dirty | 0 | 无测试体（构建） |
| visible-feedback | fcd1c9b0c310/dirty | 0 | 1/1/0/0 |
| candidate2-debug-build | 744e7729f103/clean | 0 | 无测试体（构建） |
| candidate2-unit | 744e7729f103/clean | 0 | 574/573/0/1 |
| candidate2-ui | 744e7729f103/clean | 0 | 3/3/0/0 |
| candidate2-release | 744e7729f103/clean | 0 | 无测试体（构建） |


交付仅普通commit/push原分支和更新唯一Draft PR13描述；base保持codex/time-investment-v1。不为纯Docs重建；交付SHA以实际commit/PR head+final-delivery-proof核对，主目录三项未知改动保留。D1–D4 NOT_PASSED、AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、远端CI NOT_RUN保持；设备/私人库/签名安装/merge/force/tag/Archive/TestFlight均未执行，停在Owner设备门。


## 2026-10-20 TERMINAL_RECHECK 最终验收 — READY_FOR_OWNER_DEVICE_GATE

固定Goal `ae92c71e7f4b787456dcaa5ba6f7ea07e91d2627`；最终干净产品/测试 `1b150068e76f4d7e7a6defcd51f10622951f4b4b`；产品实现 `2b0d4917342d03b0f9e5323a1ef2cf58447953fb`，之后仅旧往返测试依赖隔离。独立终审原文见REVIEW（SHA256 `6b75465420b1cfd5043d275ea4c8ba56373f0dddc4cee95cdcf39677e9dbe3f9`）。三项均CONFIRMED_AND_FIXED，无本轮范围未关闭confirmed P0/P1/P2与明确P3。

| 编号 | 最终验收与相反操作 | 实际完整方法 |
| --- | --- | --- |
| TC-01/P2 | completed与skip/canceled祖先真实旧事务产生B；两渠道相同时间/渠道，等偏移不同标识refresh/quarantine后从实际editor确认未来，只恢复开放B且native新ID唯一；A不复活/不因纠正续代，历史/来源/原计划截止保留；失败回滚/未确认取消不并行/确认后磁盘冷开/幂等及健康metadata、SystemStop/seriesStop反证 | ImportExportRecoveryTests/testRecheckTC01TerminatedAncestorSameValueActualEditorRestoresOnlySuccessor；testRecheckTC01TerminatedAncestorRollbackAndUnconfirmedCancellation；原TerminalRR01两完整方法仍通过 |
| TC-02/P2 | daily/weekly实际设置修改失败清理未确认，off跨整个根与两Scope弱释放；新AppShell自动发现仍在/已无/冷清再次失败，denied/notDetermined零权限申请；新B同值/异值/off在冷query内到达不误删，其他渠道/类别和共享预算保持 | AppCompositionTests/testRecheckTC02EntireAppRootDestroyedColdStartReconcilesOffRequests；testRecheckTC02ActualColdRootQueryProtectsSettingsNewIntent；ImportantDayReminderTests/testRecheckTC02ColdOffCleanupQueryProtectsNewSameChangedAndOffIntents及原共享容量/跨sheet/当前失败完整方法 |
| TC-03/P3 | 同Scope与新根从未确认→真实retry确认后native0/pending=false，当前中文未确认文字与Try Again消失；偏好仍off，不要求重开提醒 | 上述整根完整方法的4张真实中文前后图及ImportantDayReminderTests/testTerminalIC02StableFailureCleanupLatestIntentAndRetryMatrix最终文字断言 |

最终四轮同一clean SHA：Debug PASS、完整Unit579=578PASS/0FAIL/1SKIP、关键UI3/3PASS、unsigned generic iOS Release PASS；runtimeWarnings=[]。唯一低空间方法需隔离32MB HFS+图，保留SKIP。六实包原身份/版本/最低系统/完整构建SHA/Dirty=false/AlarmKit弱链接中英用途及Release三包未签名核对，四轮142文件manifest同字节并匹配Git。

原始21轮包含red-chains4FAIL（TC01前提夹具错，TC02/03真实红例）、修正TC01前提后2FAIL、green4PASS、expanded18PASS/3FAIL（偏好污染）、focused22PASS、Todo探针1FAIL后整类31PASS、2b首完整577PASS/1FAIL/1SKIP后1b最终完整578PASS/0FAIL/1SKIP。原编译失败、历史19/38轮与黑图局限保留；精确命令/分轮/hash见EXECUTION及本轮JSON，不拼称历史全绿。未受影响旧UI只依方法/实现blob复用，未冒称全量UI或真机系统Alarm通过。

本地批次完成，纯Docs不重建，原worktree/分支、唯一OPEN Draft PR #13/base不变，普通commit/push。文档交付SHA由实际commit/PR head与final-delivery-proof核对并在PR描述/最终回复列出。D1–D4 NOT_PASSED、AlarmKit正向NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间SKIP/NOT_RUN、CI NOT_RUN及O-01非阻断UNCONFIRMED保持；不触碰私人设备/库、签名安装或发布动作。
