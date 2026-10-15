# PR #10 限定 Review Fix — IMPLEMENTING

本轮固定输入d98306f219ed5929d38856216cd9af52fa5c7744；外部独立审查确认R1–R4四项P2及R5预览P3，替代下方旧“范围内已收敛/设备Gate”结论。沿原PR10/分支续接，当前候选9538ec7已实现R1–R5并由唯一独立reviewer作代码层复审；集中测试与删除目标宿主边界仍验证中，不宣称最终通过。具体证据见EXECUTION，本轮最终停READY_FOR_INDEPENDENT_REVIEW。

---

# 以下为上一轮交付历史（不覆盖本轮发现）

# 重要日子 V1 独立审查

状态：固定产品/测试b3cc408已完成实际独立复审，无未关闭confirmed范围内P0/P1/P2；集中最终53Unit+17UI=70/70通过，三构建通过；审查不代替运行门禁。

审查视角：独立数据/规则（日期、历史Schema、升级/恢复、封面、引用、通知交错）；独立产品/集成（五Tab/Record/Today、Widget隐私/路由/打包/系统渲染）。审查者只读固定SHA，问题由实现者核实、反例修复并请求新SHA复审。

首轮及最终测试证据见执行断点；最终结论见下方固定SHA闭环。

## R1：独立数据/规则审查

- Reviewer：实际独立 agent `/root/important_days_data_review`；只读，无实现修改。
- 固定 SHA：`cbd2075427c04642876b2d387d00b82c173a5e5f`，比较 `20d315a`。首提交漏工程注册，已由此追加提交修复，reviewer独立核验；没有把不可构建的1cfa标为审查终点。
- 结论：该阶段范围无 confirmed 新 P0/P1/P2；不是完整 V1 验收。
- 实际读取：共享日期、HKO2023/2024/2025样例、历史迁移链/四实体、v8字段/校验/发布回滚、Entry/Todo关系与相邻删除、独立封面服务、共享提醒/gate/pending。
- 证据：独立读取Integration1原始xcresult metrics，30测试/0失败/0跳过/0 warnings/errors；未重跑测试。旧alias SQLite日志另有说明，不将metrics零warning泛化为日志无任何诊断。
- 边界：提交前工作树证据，需最终精确SHA回归。全部旧包版本、新封面真实低空间/取消、真实系统daily/weekly交错、恢复后实际排期/递送未被30项全面证明。Widget/路由/双语/UI在本轮审查之外。
- Reviewer提醒：保存前还缺offset后的实际提醒日期预览，已在正在开发的UI中补入，待最终审查验证。

后续：B收敛后进行独立产品/集成审查，并对后续数据/提醒差异请求R1复审。

## R2–R5：B 与修复闭环

两名实际独立 agent 只读固定提交，不参与实现，不以实现者自评代替：数据/规则 `/root/important_days_data_review`；产品/集成 `/root/important_days_product_review`。

| 固定范围 | 独立发现、实现者核实与闭环 |
| --- | --- |
| 58355a2b7ac5302b31c6a6658624bcc14a1525b0 对 cbd2075 / 产品基线 | 数据reviewer确认P1：仅文字privacySensitive，独立照片背景未保护；产品reviewer确认P3：新关联Todo显示不适用的重新打开/重复说明。其余范围无confirmed新P0/P1/P2。实现者另自查指定年份期次UI缺口，补年份选择/实际日期/禁用无期次。 |
| 06ce32af659812cd3dda28bfeb748f58ce265352 对58355 | 两reviewer确认P1照片遮罩与P3文案已修；真实SwiftUI隐私正负像素对照通过。两人独立发现P2：编辑起始年或preset后，旧年份/explicit状态残留，可能写出开始前或一次性日子的期次。 |
| 9017a2c0af1f5b9fcb71e4a7e3380c4e5e9952bb 对06ce | 两人确认P2关闭：统一explicitPeriod验证annual/年范围/原年，规则变化清选择。数据reviewer提出支持范围无next不应误报elapsed，已独立状态修复；时钟回拨/原字节不变反例。25/25 Unit被独立核实，冷启动恢复UI通过；编辑UI实际失败保留。 |
| 9f34034357ea9329730ab18bfbf6d4b6e426b4b4 对9017 | 实现者追实际UI发现Chinese hydration误触历法确认/可能改已存perspective；以acknowledgedCalendar/lastPreset守加载，真实用户切换仍确认。两reviewer独立检查同task同步初始化与观察顺序，无新confirmed问题。 |
| b3cc408d323e5828e9550decac72ae534f1b0b20 对9f | 仅备份测试夹具：旧wire不带新空keys，非空新数据不剥除；精确计数增加新四零项，V7负例排除错因，新增V8八反例和V7正反。数据reviewer确认没有弱化生产校验或掩盖缺陷，53/53整类补验通过；产品reviewer核对仅测试变化与真实渲染，无未关闭confirmed P0/P1/P2。 |

审查直接覆盖Schema链/主库保护、v8媒体/关系/旧格式、封面输入/回滚、通知实际适配/gate/容量/时区、Today/五Tab/Record、双向引用、Widget授权快照/隐私/实际provider午夜、稳定路由/恢复排队和target嵌入。产品reviewer实际目视 numeric-small-dark-AX / list-medium-dark-AX / photo-medium-dark / privacy-neutral，确认可读且隐私图无原内容；这是离屏SwiftUI渲染，不是实际系统桌面/tint/VoiceOver证明。

所有reviewer均区分早期失败、对应SHA、运行中结果与通过证据。最终全量9f的358PASS/4fixtureFAIL保留；b3整类53PASS不改写原全量。最后集中UI、实包同源核对、远端PR交付结果以验收报告和执行断点为准。实际通知/桌面/真机保留Owner Gate。

## 最终运行证据独立核对

两reviewer独立核对b3的FinalFocused1原始xcresult/summary/log：53Unit+17UI共70PASS，0FAIL/SKIP，driver四次URL exit0；4条Invalid frame dimension如实保留。数据reviewer另外直接读取三产物目录9个bundle，确认App/Share/Widget版本1.0(7)，三个主App provenance均b3且Dirty=false。无未关闭confirmed范围内P0/P1/P2。

实现者已按审查提示将Today位置文字修正为“目标后、周/月习惯前”，并收尾运行中/活命令口径；原358/362全量失败证据仍保留。系统桌面/tint/通知/VoiceOver及真机仍NOT_RUN/Owner Gate。
