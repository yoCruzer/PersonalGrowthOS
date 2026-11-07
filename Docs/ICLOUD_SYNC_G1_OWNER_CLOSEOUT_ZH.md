# G1 本轮收口：Owner 接受的手机侧范围

2026-11-07。状态：`OWNER_ACCEPTED_PHONE_SCOPE`。

按照Owner当天明确调整，以手机侧已核验项目作为本轮验收依据，Mac两次CK_2不再阻塞。原始Mac失败保留；VPN是Owner判断的原因，尚未独立验证。这个状态表示调整范围后的G1本轮完成，不表示原全部故障矩阵或Production已经通过。

## 已核验

- 本轮iPhone build7：6份原始计划，27条命令全部PASS。原件通过Configurator仅导出SyncLab文稿取回，验证计划与命令摘要、账户一致性、逐字段事实及图片字节/hash。
- 异常依赖00：12条初始事实，补齐后16条；固定新图片真实入队并收到SDK ACK，手机本地原图完整。
- 01、05：两份联网写入及ACK，待上传队列清空。
- 16、17：物理关闭Wi-Fi/蜂窝及恢复网络由Owner按步骤操作并确认；缓存分区离线保存、本地store重开后事实与待上传项保留，恢复真实账户连接后ACK且队列清空。这不是进程崩溃恢复证明。
- 19：独立恢复数据集的合成种子上传及ACK，只证明种子准备，不等于恢复竞态通过。
- 此前r5已取得的Mac/iPhone基础双向文字/图片、真实版本冲突及解决后收敛证据继续有效。

## 接受的例外与后续补证

本轮Mac读取新修复数据两次出现CK_2/ZONE_SAVE_FAILED_RETAINED，按Owner明确决定作为非阻塞例外接受，不把原始FAIL改成PASS。新图片的本轮Mac取回未验证。真实内容/state进程退出恢复、旧ACK后继编辑、asset lease/缺图截断故障、A→B→A账户切换及restore-cloud race等剩余场景保持NOT_RUN或未完成；现有离线/模拟覆盖不替代真实服务证据。

## 工程与交付

最终运行源码基于0e1f747：原生64/64、工具38/38，以及已归档独立复核。后来为CK_2准备的数字诊断候选曾65测试和Mac签名构建通过，但Owner调整后未部署，源改动已从最终候选撤回并留私有patch；其日志仅为历史过程，不作为最终运行版本计数。

Mac固定窗口已投递STOP，未再启动诊断或手机测试；手机不再需要连接。保留实验数据和所有原件，不退出任何系统账户。普通推送到既有分支/Draft PR16；未合并、未部署Production、未Archive/TestFlight。正式容器P1/P2及发布门禁尚未验证，本次Owner范围调整不自动授权这些操作。

[机器可读结果](Evidence/iCloudSyncG1/fault-window-20261107/phone-closeout-verification.json) · [Owner范围调整](Evidence/iCloudSyncG1/fault-window-20261107/owner-scope-amendment.json)

## 远端检查

运行源码0e1f747的SyncLab offline gate 42379018988已SUCCESS。正式产品iOS regression 42379022508为FAIL：release与unit成功、smoke失败、extended UI跳过；该失败单独保留，不被本轮Owner手机验收替代。

独立手机收口复核：6报告/27命令通过，9项篡改负控全部拒绝，无must-fix；[独立报告](Evidence/iCloudSyncG1/fault-window-20261107/independent-phone-closeout.json)。
