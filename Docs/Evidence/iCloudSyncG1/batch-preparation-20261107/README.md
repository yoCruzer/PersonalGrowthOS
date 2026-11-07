# 下一批异常依赖与新图片：离线工程准备

实现提交e8b1c3f。新增仅Debug的固定三阶段生成器（16/10/4命令）、第二个70字节固定PNG及严格hash/长度选择。计划ID绑定完整dataset/run/stage摘要，解决独立审查实际发现的重复运行导出碰撞；既有手工计划与旧报告不变。

本机最终51项原生PASS，双平台签名Debug及sim unsigned Release PASS，严格签名校验PASS。工具首轮8PASS/5ERROR为沙箱bind拒绝，按loopback权限复验13PASS，失败原样保留。[检查记录](checks.json)。

[独立复核](independent-review/review-final.md)：原重复run红例1FAIL保留，修复后7项原生/实际CLI/14负控通过；Release拒绝入口证据明确为身份小修前，主执行最终Release重新构建通过。未发现剩余must-fix。

最终IPA与三份计划已准备在本机/private/tmp/g1-next-batch-device-final，未安装或运行。生成计划不是服务验收：需新dataset/zone、手机新image pending/ACK及Mac原字节下载证据；空引用快照不证明远端无孤立asset。每阶段执行后需核对结果。手机before快照是连续执行留证，并非暂停断言。

原有基础双向与冲突真实证据见../dual-client-20261107。剩余崩溃/断网/账户切换/旧ACK/图片故障/恢复竞态未由本工程关闭；本阶段不要求手机连线。正式产品两个既有UI布局失败与发布/Production授权边界保持。

[定向CI42365482372](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42365482372)已SUCCESS，原始产物核对51原生/13工具及unsigned iOS构建通过，见ci-accepted.json。
