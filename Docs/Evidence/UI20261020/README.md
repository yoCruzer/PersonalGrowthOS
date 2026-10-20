# 合成数据原生截图

图片直接复制自 xcresult 或专用模拟器录像帧，未裁剪、缩放、改色。完整来源与 SHA256 见 [manifest](manifest.json)。这些是针对各自已通过方法的证据，不能把同轮其他方法的失败计作通过。固定候选、复用范围与真实失败见 [执行与验收](../../UI_READABILITY_LOCALIZATION_20261020_ZH.md)。

| 检查 | 原图 |
| --- | --- |
| 原布局/图标复现 | [Growth前](before-growth.png)、[Start前](before-start-icon.png) |
| 原生List三方案 | [浅色](native-list-comparison-light.png)、[深色](native-list-comparison-dark.png) |
| 最终布局 | [默认](final-light-default.png)、[较大普通字号](final-light-XXXL.png)、[英文](final-english-default.png) |
| 最终无障碍深色 | [0次](final-dark-zero.png)、[1次](final-dark-one.png)、[完整长名](final-dark-long-title.png) |
| 开始按钮按下 | [前](start-before-press.png)、[中](start-during-press.png)、[进入计时](start-after-press.png) |
| 实际生产深色按下 | [前](dark-start-before-press.png)、[中](dark-start-during-press.png)、[进入计时](dark-start-after-press.png) |
| 中文状态 | [归档](archive-chinese.png)、[恢复](restore-chinese.png)、[上个月](previous-month-chinese.png)、[下个月](next-month-chinese.png) |
| 默认与用户文本 | [纯图片记录/用户Entry](fallback-record-user-entry.png) |
| 中文展示 | [暂无数据](no-data-chinese.png)、[数量](quantity-chinese.png)、[真实重试](real-reminder-retry.png) |
| Goal/Flag状态 | [目标禁用](goal-disabled-icon.png)、[目标启用](goal-enabled-icon.png)、[标记启用](flag-enabled-icon.png) |
| 共享空态 | [添加习惯](habit-empty-icon.png)、[添加体重](weight-empty-icon.png)、[开始周回顾](weekly-empty-icon.png) |
| 生产星期 | [实际当前周](actual-current-week-chinese.png)、[同一Grid中文](production-grid-chinese.png)、[英文](production-grid-english.png) |

Grid日分支目前不从日详情路由；截图标题明确标注原生测试宿主，不当作真实导航路径证明。VoiceOver AX标签已检查，真实设备朗读和相机权限弹窗仍未运行。
