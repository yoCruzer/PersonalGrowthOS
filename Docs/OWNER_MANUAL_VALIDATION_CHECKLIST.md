# 随心log：当前候选集中真机验收

这份清单在代码再次独立 Review 通过、Owner 明确授权候选安装之后使用，不代表本次已安装或已通过。历史文档里 pending 的同一事项只在当前候选验证一次，不逐代重复 Build5/6/7/8/9。

## 安装前

记录当前已安装 App 的真实版本/build，导出并妥善保管升级前备份。由现有发布流程确认候选 git SHA、App/Extension 实际版本与 build 一致，App Group provisioning 正确。保留原 App 数据覆盖安装；不要先卸载来制造“干净通过”。不能用旧 App 直接打开已升级的 V10 数据库。

## 最小验收矩阵

| 场景 | 操作与判定 |
|---|---|
| 原有数据 | 抽查旧文字、图片、习惯、体重、目标、周回顾、置顶与补充；重启后身份/内容仍在。发现缺失先记录诊断，不继续做删除或清库操作。 |
| Safari URL | 系统 Share Sheet 能找到随心log；保存 URL，主 App 导入后来源能重新打开原页。 |
| Safari 选文 | 保存准确选中的段落和可获得的标题/原始 URL；不把全文、导航文字或文件路径当引用。 |
| Photos 单图/多图 | 单图、数张普通图片、多张较大图片各测代表场景；预览/数量提示与最终记录相符，界面可操作，图片清晰、重启可读。 |
| 微信边界 | 只测能调用系统 Share Sheet 的页面/图片/内容；记录其实际提供的类型和效果。微信自己的转发菜单没有随心log，不直接记成 App 缺陷。 |
| 断网与慢加载 | 离线分享已可读的文本/图片/URL，metadata 失败不阻止核心保存；云端图片未下载时有加载/失败/重试说明，不能假装图片已完整保存。 |
| 取消与重开 | 读取中取消、保存前取消、重新发起另一次分享；不出现上一会话结果，不生成幽灵记录。已发布后系统退出，回主 App 仍能导入。 |
| 搜索衔接 | 先打开无结果的特定查询，到外部分享匹配内容再返回；导入完成后出现结果。按来源域名/URL 找回引用；原 follow-up 搜索仍可定位。 |
| 恢复与备份 | 并发破坏性场景只在合成测试库跑，不能在私人真机库冒险；真机仅验证正常导出、待处理内容范围提示与必要的非破坏性预览。 |
| 新错误入口 | 遇到问题能找到待处理条目、重试/保留；复制诊断不含分享正文、链接、照片等私人内容。测试丢弃使用专门合成条目，不删除个人记录。 |
| 核心旧流程 | Record 草稿跨 Tab、普通图文创建编辑/重启、Today 周/月 Habit、一次 Weight 输入、一次中文 Weekly Review 与补充编辑，做一组代表性 smoke。 |

## 反馈格式

记录候选版本/build/SHA、iOS 版本、源 App/入口、动作、预期与实际、复现频率、脱敏诊断 ID。截图/录屏先检查私人内容。分清“系统没提供分享入口”“扩展没出现”“读取失败”“已保存未导入”“来源不可访问”等不同阶段。

已通过事项记录明确版本和日期；未执行填 NOT_RUN，不用历史版本的通过替代本候选的签名、App Group 与真实升级验证。长期 Daily Driver 观察仍可以继续，但不要求为了发布前验收重置计时或重新体验每个历史版本。

当前候选版本身份以 [执行计划发布对照](EXTERNAL_CAPTURE_EXECUTION_PLAN.md) 为准；App/Extension 工程仍为 1.0(7)，schema V10、备份 v6。候选安装 SHA、实际云端 build、TestFlight 可用性与下表结果由 Owner 据实填写，未执行项一律 NOT_RUN。

| 记录项 | 当前状态 |
| --- | --- |
| 候选安装 SHA / 版本 / build | OWNER_REQUIRED |
| 真机型号 / iOS / 日期 | NOT_RUN |
| 签名 / App Group / 覆盖升级 | NOT_RUN |
| 上方矩阵各项结果 / 诊断 ID | NOT_RUN |
| Owner 接受或要求修复 | OWNER_REQUIRED |

以下旧 Build 3 清单仅保留历史证据，已 superseded，不作为当前操作指令；其中卸载/重装与逐代重复验收不适用于当前候选或私人数据。

<details>
<summary>历史 Build 3 清单（superseded）</summary>

# Owner Build 3 TestFlight Validation Checklist

Candidate: PersonalGrowthOS Version 1.0 (Build 3).

This checklist begins after Build 3 is uploaded, processed and available for Internal Testing. Every item below is intentionally **unchecked**: Codex has not installed Build 3 on a physical iPhone, overlaid the Owner store, used Owner data, or started the formal 30-day observation.

## Safety Before Testing

- [ ] Use a physical iPhone and signing configuration selected by the Owner.
- [ ] Begin with disposable test content, not the only copy of real memories.
- [ ] Confirm the device has comfortable free storage before image and restore tests.
- [ ] Keep exported ZIP files in an Owner-controlled location outside the app container.
- [ ] Treat every export as sensitive: the ZIP is not encrypted and contains entry text plus original photos.
- [ ] Keep the current app installation until an external backup has been confirmed present and shareable.
- [ ] Do not delete the current App before the Build 3 overlay and migration check.
- [ ] Record current Entry, image, Habit, Goal and other important counts or screenshots.

## Overlay Install, Migration and Offline Boundary

- [ ] Install Build 3 from TestFlight over the existing App; do not uninstall first.
- [ ] Launch it successfully and confirm Today, Timeline, Growth and Library are reachable.
- [ ] Confirm the App does not crash and did not open an unexpected empty store.
- [ ] Confirm existing Entries, original images, Tags, Habits/HabitLogs, Goals/Flags, Reviews and relationships remain visible.
- [ ] Turn on Airplane Mode and confirm launch, capture, search, organization and Growth flows still work.
- [ ] Confirm no account, network, CloudKit or sign-in prompt is required.
- [ ] Force-quit and reopen the app; confirm previously created content remains available.

## Capture, Media and Time Semantics

- [ ] Create, reopen and edit a text-only Entry.
- [ ] Create and reopen an image-only Entry through the real Photos Picker.
- [ ] Create and reopen a mixed text-and-image Entry.
- [ ] Select multiple photos, reorder them, save, reopen and confirm order and original quality.
- [ ] Exercise camera capture if the device and signing configuration expose it.
- [ ] Test Photos and Camera permission grant, denial and later Settings recovery behavior.
- [ ] Backdate `occurredAt`; confirm the Entry appears at the intended Timeline time while creation time remains current.
- [ ] Archive and restore an Entry; confirm its images remain intact.
- [ ] Permanently delete one of two image Entries; confirm only its own image disappears.

## Organization, Growth, Review and Search

- [ ] Leave an Entry in Inbox, then organize it without creating a Tag.
- [ ] Create a Tag, attach it to an Entry and find the Entry through global Search.
- [ ] Create a Habit and perform a simple HabitLog check-in.
- [ ] Add a Habit insight through a linked Entry and reopen it from Habit history.
- [ ] Pause, restart, complete and archive a disposable Habit as appropriate.
- [ ] Create both a Goal and a Flag; verify their lifecycle and Today context.
- [ ] Link an Entry to a Goal and a Habit to a Goal, then reopen each relationship.
- [ ] Create a lightweight Review with a period and link an Entry, Habit and Goal.
- [ ] Find an ordinary Entry, Review Entry, Tag, Habit, Goal and Flag through Search.

## Weight

- [ ] Open Weight from Today and confirm Growth opens the same history.
- [ ] Add the first dated Weight record and confirm the latest value.
- [ ] Add a second record and confirm the change from the preceding record and the chart.
- [ ] Edit a Weight value/date and confirm history ordering and latest/change update.
- [ ] Delete a disposable Weight record after confirming the destructive prompt.
- [ ] Force-quit and reopen; confirm remaining Weight records persist.
- [ ] Confirm Today and Growth still show the same data after relaunch and background recovery.

## Export, Privacy Warning and Disposable Restore Rehearsal

- [ ] Open Settings and start Export; confirm the unencrypted-backup privacy warning appears before sharing.
- [ ] Export a disposable complete data set to an Owner-controlled Files location.
- [ ] Confirm the exported backup includes the expected Weight record count after Build 3.
- [ ] Confirm the ZIP exists outside the app container and can be copied before altering the app installation.
- [ ] Confirm Import refuses a non-empty database and does not erase or merge its content.
- [ ] Do not restore over the only copy of real data. For a destructive rehearsal, use only disposable content and retain at least one external ZIP copy.
- [ ] Remove the disposable active app data by deleting/reinstalling the app, then launch the empty database.
- [ ] Import the retained ZIP and verify text, timestamps, image order/originals, Tags, Habits, HabitLogs, Goals/Flags, Reviews and relationships.
- [ ] Force-quit and reopen after restore; confirm restored content and media remain intact.
- [ ] Export the restored data again and retain both packages until the rehearsal is accepted.

## Physical-device Quality Review

- [ ] Review capture, Timeline scrolling, Search and image viewing responsiveness with representative real-life content volume.
- [ ] Watch for memory pressure, termination, heat or long main-thread stalls during multi-image capture and full backup/restore.
- [ ] Compare free storage before and after representative image capture, export and restore.
- [ ] Confirm progress, cancellation and failure messages are understandable and leave the prior data set intact.
- [ ] Check VoiceOver labels, selected-state announcements, Dynamic Type at the Owner's preferred size, contrast and touch targets on the physical device.
- [ ] Record every real-iPhone Daily Driver blocker with reproduction steps and whether it risks data integrity.

## Owner Decision Boundary

- [ ] Review the Candidate report, known limitations, Milestone C evidence and this completed checklist.
- [ ] Decide whether to accept the Candidate, request fixes or abandon selected implementation areas.
- [ ] Explicitly decide whether formal Dogfooding may begin; technical completion does not start it automatically.
- [ ] Only after Candidate acceptance and the physical-device blocker review, record the date formal Dogfooding begins.
- [ ] Only after the Owner explicitly starts it, record the start date of the Foundation-defined continuous 30-day V1 Exit Observation.
- [ ] At the end of that uninterrupted period, evaluate the Foundation exit criteria using actual Owner experience; do not infer success from simulator or automated evidence.

## Owner Notes

| Item | Owner record |
| --- | --- |
| Physical device / iOS version |  |
| Candidate commit |  |
| TestFlight processing state |  |
| Signing configuration |  |
| Validation date |  |
| Blocking defects |  |
| Non-blocking defects |  |
| Candidate decision |  |
| Dogfooding start decision/date |  |
| 30-day observation start decision/date |  |

## Feedback Format

For each finding, record:

```text
Page:
Steps:
Expected:
Actual:
Reproduces consistently:
Screenshot or recording:
Severity:
```

</details>
