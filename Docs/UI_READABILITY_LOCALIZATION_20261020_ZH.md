# 2026-10-20 后续计数器 P2 复核补修

旧常态蓝色图标/灰底实测2.305:1，原B Counter“恢复系统状态”不足以证明启用图标对比度通过。本轮成对调整浅/深底色与启用/按下前景，零次禁用保持；20个生产PNG实心样本最低7.273:1。Today/Growth/详情实际0→1→0、周期累计与名称导航、普通/最大辅助字号/浅深/按下完成本地补验。真实设置图黑色加号与材质完整，排除旧宿主取图差异，无设置产品补修。

具体原图/复算/分轮失败和复用边界见 [本轮实际执行](CI_DEVICE_BRANCH_CLEANUP_20261020_EXECUTION_ZH.md)。最终产品/测试候选3ee3cb6a846a296baca7f91b705a67c10dcbe51f的真实run39387986862必选检查已通过；本授权批次READY_FOR_OWNER_DEVICE_GATE。原授权等待与失败保留，设备门未代通过；以下旧交接不替代最新本轮执行。

---

# UI 可读性与本地化专项整改（2026-10-20）

状态：READY_FOR_OWNER_DEVICE_GATE（本地验证与独立终审完成；后续设备/CI门未代为通过）。

## 身份与边界

用户实测基线 `c7f5a3836140a27801fa0a9f1bacbfb73c0d7e5c`；首次及推送前 fetch 均确认后续 `cd8786b06bb984041ad9968a6736b624ba60d3f3` 的 CI/设备门/分支规划，全部保留。唯一 OPEN Draft [PR #13](https://github.com/yoCruzer/PersonalGrowthOS/pull/13)，base `codex/time-investment-v1` / `5a70f0110b151f8a45ac7c33d3f443823b1cff24`。

主目录另任务及未知工程/翻译/Cloud 改动未触碰。独立工作树 `/private/tmp/PersonalGrowthOS-ui-20261020`，任务分支 `codex/ui-readability-localization-20261020`，仅普通推送原 PR 分支。本轮最终产品/测试固定候选 `537a6f9103f6ccbf08b8634edf6dfc976247b4c8`（前一验证候选 `fe4b0f77d4ea31cc2d3510952355dbf5a02a8301` 之后只修 Investment UI 测试的子开关定位）；后续交付只增加 Docs，交付完整 SHA 由 PR head、最终回复与本机 `final-delivery-proof.json` 核对，不把 Docs 提交冒称成构建 SHA。

只改呈现、本地化、DEBUG 合成 fixture 和验证；模型、schema、打卡/计时/持久化与业务日期统计未改。没有操作私人设备/库、签名安装、merge、force、tag、Archive 或 TestFlight。

## 逐项原因与修复

| 项目 | 原因与最终行为 | 实证 |
| --- | --- | --- |
| A 行高/密度 | 隐藏习惯名称后的 Counter 仍有伸展 Spacer，挤占左侧名称/进度。只在显示名称时保留 Spacer；进度去掉重复“还需”，保留周期范围。短名默认 1+1 行；长名完整换行，大字号纵向适配；没有全局固定行高或缩小字体 | 修改前 `before-growth.png`，最终默认/XXXL/AX-dark/英文图；默认短名标题<=25pt、行<=70pt、箭头间距<=20pt |
| A 语义/交互 | 周/月累计仍由 analytics 计算；胶囊是当天 HabitTodayProgress，不混成同一个计数。昨日2条真实合成 log + 当天0→1→0，周期2/3→3/3→2/3、2/10→3/10→2/10。名称导航与加减分别验证 | Today 日/周/月与 Growth 周/月/长名、详情路径。周/月边界按真实周期取期望，不冻结宿主时钟 |
| B 开始/同结构按钮 | iOS27.0 原生 List + borderedProminent 的 automatic Label 复现文字正常而图标空白。局部原结构三方案对照，titleAndIcon 与统一 white 均显示图标；采用显式 titleAndIcon，保留系统颜色状态 | 原 List 浅/深对照；实际 Start/Goal/Flag/添加习惯/体重/开始周回顾。没有预称所有旧消费者均有同样缺陷 |
| B Counter 状态 | controls 外层 primary 前景覆盖 disabled 外观；现在只对数值用 primary，按钮恢复系统状态前景 | zero 减号灰、one 减号蓝，禁用与行为一致；实际0→1→0/重启持久化 |
| C 8 漏键 | 补 Archive activity、Restore activity、Previous month、Next month、Try Again、No data、Quantity、真实 staleTask 错误中英文；动态 String 调用处明确查表 | 实际归档→恢复、翻月往返、均值“暂无数据”、证据“数量”、真实设置重试和 stale revision producer；实包两语言查表 |
| C 默认/用户文案 | dayLabel Today 和 Goal/EntryDetail/Weekly/Library 的6处普通 Entry 默认、Timeline目标默认明确查表；用户标题/正文不翻译 | 无标题纯图片显示“记录”，用户标题 Entry 仍是 Entry，正文 Today 原样 |
| C 星期 | Habit 展示日历复制业务 policy 后仅替换 locale，月历头/分布 VoiceOver/当前周期周视图使用它 | 中文一至日、AX星期一，英文对照；Gregorian/firstWeekday/minimumDays/timezone及原en_US_POSIX业务policy断言不变 |
| C 今天/相机 | 5条中文Today页面名统一今天并保留原意；补 NSCameraUsageDescription 中文用途 | Debug/Release实包 App/Share/Widget 8+5资源核对；相机 App InfoPlist中英文核对 |
| 独立预审 P2 | 原 Sleep intro 的44pt外框实际只给~14pt glyph hit node；contentShape+borderless恢复完整区域。最大AX Counter文字超固定30pt灰底；背景随同一字体 ScaledMetric 缩放 | 旧原图/原审计 FAIL 保留；真实关闭按钮44pt边缘点击和旧无过滤审计 PASS；最终深色胶囊不穿字 |
| 严格44pt补修 | 长名实际按钮发生像素对齐43.6667pt；不放松>=44断言，仅2个按钮名义height44→45留取整余量，width44保持 | 旧FAIL保留，最终长名真实AX44×45及完整方法PASS；默认紧凑保护仍PASS |

当前日习惯详情走 MonthCalendar，`PeriodActivityGrid.dayLabel` 的 Today 分支没有现存产品路由。没有为验收增加产品入口；用 `@testable` 原生窗口直接托管**同一生产 Grid**，中英实际截图验其 Today/今天 与星期；仅将 Grid private→internal，不伪称从日详情走到该分支。

## 同类排查结论

| 类型 | 处理与证据边界 |
| --- | --- |
| 展开/收起、置顶/取消置顶 | 查看 Button/Label 实际重载和 LocalizedStringKey 类型、既有资源；不因三元表达式误报。相关既有中文状态资源保持 |
| 归档/恢复 | 动态 String 确认绕过/漏键处已修；两个真实状态和点击往返验证 |
| 草稿/确认、计时/手工/来源 | 检查 LocalizedStringKey、String(localized:)及现有资源；保留用户活动名与内部标识。计时前后台、冻结确认、冷开回归 |
| 空态/错误/无障碍 | 8键、默认Entry/Goal、星期label逐项检查；真实缺口修复，compiled资源与错误producer验证。Sleep无过滤审计发现并关闭额外P2 |
| 排除项 | 品牌、用户标题/正文、systemImage名、DEBUG标识、统计BMI等不是应用漏译。现有1202译文数量不作为完整性证明；新增后1210键 |

完整条件字面量清单保存在原证据根 `conditional-string-audit.txt`；独立 reviewer 另查共享消费者与同类漏项，额外确认 Library Entry/Timeline Goal 回退。

## 环境、命令与证据

macOS27.0.1 arm64、Xcode27.1(27A9275)、SDK27.1；专用 iPhone13mini / iOS27.0(24A434)、375×812pt，UDID `834F841F-D0EA-4240-8EF1-3008ADEEEC2A`。使用本机串行原生测试，数据为合成，无隐私库输入。只改变该专用模拟器 appearance；`-AppleInterfaceStyle Dark` 在该环境未改变实际系统外观，最终用 simctl ui 设置/读回并查看黑底截图。

机器台账 [RUNS](UI_READABILITY_LOCALIZATION_20261020_RUNS.json) 保存各轮命令、退出码/计数、固定SHA、源文件manifest摘要；分别链接 [最终源文件摘要](Evidence/UI20261020/final-source-manifest.json)、[实包报告](Evidence/UI20261020/final-bundle-proof.json) 和 [图片来源/摘要](Evidence/UI20261020/manifest.json)。原始日志/xcresult/全附件及按下录像保留在 `/private/tmp/pgos-ui-20261020-evidence`。selected PNG 是原始合成图的直接复制、无裁剪改色，manifest含来源/名称/SHA256。

| 轮次 / 固定候选 | 真实结果 | 覆盖/复用边界 |
| --- | --- | --- |
| baseline-build / baseline-ui2 | 构建PASS；串行UI 1/1PASS | 原A/B复现，C当时已部分补键；不称完整原版C |
| comparison-build / list-comparison | 构建PASS；1/1PASS | 原结构List三方案，首屏顶行受顶栏遮挡，后续fix-unit1分小页补完整图 |
| fix-unit1 | 109/109PASS | 阶段证据，最终Unit另跑；完整阶段build与FAIL在机器台账 |
| candidate1-ui | 1PASS/2FAIL | Quantity/NoData通过；fallback查询和AX滚动失败；标dark实际light不作深色证明 |
| candidate3-ui-light / 3d9a508 | 4PASS/2FAIL | 两种语言矩阵、NoData/Quantity、habit/weekly空态通过；错误路由假设和Sleep实际hit target审计失败 |
| candidate4-ui-light / 4961eec | 3/3PASS | 修正真实路由后的图片回退/星期、Sleep边缘点击、原counter无过滤审计/重启；最终复用未改方法 |
| final-ui-dark / 6a1ab6a | 0PASS/1FAIL | 真Dark，严格按钮实际高度43.6667pt不满足44；局部加1pt后补跑 |
| final-build / fe4b0f7 | PASS（7.01s） | clean，sourceUnchanged |
| final2-ui-dark / fe4b0f7 | 1/1PASS（50.11s） | 真Dark/最大AX、长名、0→1→0、周期反例、导航及实际>=44pt |
| final-ui-light / fe4b0f7 | 3/3PASS（109.14s） | 中文默认+XXXL、英文默认、旧counter重启持久化与原无过滤无障碍审计 |
| final-investment / fe4b0f7 | 1PASS/1FAIL（87.90s） | 旧前后台/冻结确认/冷开计时通过；新增流程误点外层Switch行，没有把整轮写PASS |
| final2-build / 537a6f9 | PASS（2.96s） | 仅Investment测试定位+实际值断言变更，产品与其他方法和fe4b相同 |
| final2-investment / 537a6f9 | 1/1PASS（33.64s） | 实际中文播放图标/按下、归档→恢复、月份往返 |
| final-dark-investment / 537a6f9 | 1/1PASS（31.93s） | simctl真实Dark，实际生产同流程及按下录像，不只用局部对照 |
| final-unit-zh / 537a6f9 | 111/111PASS（18.51s） | Habit73+Investment32+AppComposition5+真实Todo stale1；0FAIL/0SKIP/runtimeWarnings[] |
| final-unit-en / 537a6f9 | 3/3PASS（4.40s） | compiled中英、实际错误producer、同生产Grid英文对照；0FAIL/0SKIP/runtimeWarnings[] |
| final-release / 537a6f9 | PASS（50.01s） | clean/sourceUnchanged；generic iOS Release build，不是Archive |
| 最终实包核对 / 537a6f9 | PASS | Debug/Release各3包原IDs、1.0(7)/min17，en/zh各1210，8+5键值，App相机用途双语；App provenance完整SHA/Dirty=false、AlarmKit弱链接，Release三包未签名 |

最终具备record的轮次均在运行前clean、运行后sourceUnchanged；源文件摘要由独立reviewer对相应Git blob复算。旧阶段无record的轮次只按原始命令/xcresult记录，不追认clean。所有28轮逐条命令见机器台账，原failed编译/测试与中间成功构建均保留。产物核对精确命令为 `python3 /private/tmp/pgos-ui-20261020-evidence/verify_bundles.py`，脚本副本及报告在Evidence中；构建来源provenance由App bundle提供，扩展只核身份/版本/资源，不虚称扩展有独立provenance。


失败均保留：baseline-ui 意外与对照Unit共用模拟器并发导致App被终止，随后串行 baseline-ui2 补验；fix-build1 fixture错误adapter编译失败后修正；candidate1 查询/AX滚动失败；candidate3 包含错误路由假设与真正Sleep hit target失败；final-ui-dark 严格43.7pt失败。final-investment 为1PASS/1FAIL：旧计时回归通过，新增流程误点外层 Switch 行而没有改变原生子 Switch；只修测试点击子控件并增加value==1断言后补跑，原失败和录像保留。没有删检查、过滤审计或放宽44pt门槛，也没有把失败轮中部分成功拼为整轮PASS。candidate1标注dark但实际light的图不作深色证据。

只复用确实未改的覆盖：candidate3单独PASS的NoData/Quantity及共享空态、candidate4的纯图片回退/星期和Sleep边缘测试；所复用的消费者定义与对应测试方法未改；同文件其他 Counter 定义及新增测试方法的变化由最终定向复验覆盖，且在 fe4b 重新验证受影响计数与原无过滤审计；537 与 fe4b 唯一差异为新 Investment 方法的2处开关定位和状态断言，未改方法及产品证据适用，经独立 reviewer 确认；这里指相应定义/方法不变，不宣称 candidate3/4 整个 HabitViews.swift 或 AppLaunchSmokeTests.swift 文件 blob 与最终相同。fix-unit1旧109仅为阶段证据，最终111与en对照另列。不重复无新证据的全量579旧门。

## 独立复核与剩余门

未参与实现的 `/root/ui_independent_review` 先提出反例/确认P2，再审固定候选完整diff、未改共享消费者、原生对照与最终截图/原始xcresult/实包。原文与摘要见 [REVIEW](UI_READABILITY_LOCALIZATION_20261020_REVIEW_ZH.md)。本轮范围无未关闭confirmed问题后才到当前本地停点。

真机、VoiceOver真实朗读、系统相机权限弹窗、签名安装、本轮远端CI **NOT_RUN**；编译资源和AX label不冒称这些已通过。既有 D1–D4 NOT_PASSED、AlarmKit正向 NOT_RUN、Public Share FAIL/environment、unsigned Safari FAIL、物理低空间 SKIP/NOT_RUN、O-01非阻断UNCONFIRMED保持。后续只由Owner按既有设备门计划执行，当前不发布、不合并。
