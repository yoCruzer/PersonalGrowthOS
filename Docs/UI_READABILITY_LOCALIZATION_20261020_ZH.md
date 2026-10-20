# UI 可读性与本地化专项整改（2026-10-20）

状态：FIXES_IN_PROGRESS，最终验证与独立终审未完成。

## 授权、身份与边界

实测基线 c7f5a3836140a27801fa0a9f1bacbfb73c0d7e5c；初次 fetch 最新 cd8786b06bb984041ad9968a6736b624ba60d3f3（新增CI/设备门/分支规划），PR #13 OPEN Draft/base codex/time-investment-v1 5a70f0110b151f8a45ac7c33d3f443823b1cff24。主目录另任务分支及三项未知改动不动；独立 /private/tmp/PersonalGrowthOS-ui-20261020，分支 codex/ui-readability-localization-20261020。最终仅普通推送原PR分支，不切换他人工作树、不force、不合并PR、不tag或发布。

只改呈现、本地化与合成测试；不修改模型、业务周期、服务计数/计时或日期算法。按Foundation→契约→CURRENT读取；本条新授权覆盖历史仅设备停点。独立 reviewer /root/ui_independent_review 未参与实现。

## 原因与修复

- A：无名 RepeatableHabitCounter 的 Spacer 仍占用父 HStack 剩余空间；改为只有显示名称时才保留 Spacer。计数控件自然宽度，名称获得剩余空间；概览去掉可从分子分母推知的“还需”重复，保留本周/本月/今天范围。ModuleEntryRow 不作全局截断或固定行高，44pt点击、长名换行与无障碍纵向排布保留。周期累计仍由 analytics 计算，胶囊仍为当天 HabitTodayProgress。
- B：iOS27.0 原始List内 automatic Label 在 borderedProminent 表现为文字正常、图标空白；同结构原生对照 explicit titleAndIcon 与 white foreground 均显示图标。采用局部 titleAndIcon，不硬编码白色，保留系统禁用/按下/深色。Goal/Flag及共享空态消费者实际检查。计数 controls 的 primary 强制前景妨碍 disabled 外观；改为只有计数字体用 primary，按钮使用系统状态前景。
- C：新增8个真实漏键的中英文资源；归档/恢复和翻月等明确查表；相机用途加入InfoPlist.xcstrings。所有普通String默认Entry回退（Goal、EntryDetail、Weekly、Library）与Today目标回退只本地化默认值，用户文本原样。Habit dayLabel Today查表。展示日历复制原Gregorian policy后仅替换locale，周顺序/周期/时区不变。5条Today命名统一“今天”，保留原意。

## 同类排查

逐类型检查展开/收起、置顶/取消置顶、归档/恢复、草稿/确认、计时/手工来源、错误/空态和无障碍文案。LocalizedStringKey/系统Label的条件表达式有现存资源时不误报；用户String、图标名、内部状态/DEBUG标识、品牌不翻译。完整条件字面量清单在证据根 conditional-string-audit.txt；独立reviewer额外定位Library Entry和Today Goal回退。App/Share/Widget既有资源接线保持。

## 本机环境与原始证据

证据根 `/private/tmp/pgos-ui-20261020-evidence`。macOS27.0.1 arm64、Xcode27.1(27A9275)、SDK27.1；专用iPhone13mini/iOS27.0(24A434)，UDID834F841F-D0EA-4240-8EF1-3008ADEEEC2A。只使用合成数据，不改宿主时钟/时区或其他任务设备。

| 轮次 | 真实结果 | 用途/边界 |
| --- | --- | --- |
| baseline-build | PASS | 原A/B产品+合成中文fixture构建，不跑全量基线 |
| baseline-ui | FAIL/exit65 | 我误在同设备并发启动对照Unit，导致App被终止；原记录保留，不计PASS |
| comparison-build/list-comparison | PASS，1/1 | 原List三方案实验；首行部分滚入顶栏，后续分小页补图 |
| baseline-ui2 | PASS，1/1 | 串行完整Today每日/周/月、Growth、实际Investment图标空白；此时C已部分补键，A/B仍原样 |
| fix-build1 | FAIL | 新纯图片fixture误用EntryRepository而非EntryPersisting adapter |
| fix-build2 | PASS | 修为ModelContextEntryPersistence，生产语义不变 |
| fix-unit1 | PASS，109/109 | Habit73+Investment32+AppComposition4；含中英compiled资源、中文TodoFailure实际producer、星期策略、原生List4张图和真实提醒失败/重试图 |

完整命令保存在每轮.log的Command line invocation；xcresult、导出附件manifest与原FAIL保持。baseline2-attachments包括修改前Growth/Today 2+2行、计数同黑和Investment空白；fix1-unit-attachments含浅深色List三方案/共享按钮/disabled及每日每周真实中文重试。后续轮次追加真实结果。

## 验收与剩余门

尚需：受影响UI矩阵实际查看；周期累计≠当日计数反例；中文归档→恢复/月翻页/纯图片Entry回退/星期/NoData/Quantity/错误；原生按下态；固定候选及产物核对、独立终审、普通commit/push和PR更新。

本轮尚未执行真机、VoiceOver真实朗读、签名安装、系统权限相机弹窗、远端CI或既有D1–D4；没有用历史PASS代替本轮通过。必要视觉证据缺失则标BLOCKED/NOT_RUN；全部本地门后止于READY_FOR_OWNER_DEVICE_GATE。
