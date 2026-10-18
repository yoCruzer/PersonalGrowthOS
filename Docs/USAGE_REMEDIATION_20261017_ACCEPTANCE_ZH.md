> **2026-10-18 当前增量：本地修复 F1–F5 / UX1–UX2 待执行。** 原 A–D 验收与失败轮次保留为历史，当前新问题及验收基线见本文件末尾“独立复核后的修复验收”。按 [PR #13 独立复核后的本地修复目标](USAGE_REMEDIATION_20261018_REVIEW_FIX_GOAL_ZH.md) 执行；这次规格准备没有产生产品修复、构建或原生测试 PASS。完成新目标的全部本地要求后才可再次停在 READY_FOR_OWNER_DEVICE_GATE。

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
