# 真实双客户端基础往返与冲突批次：独立复核

日期：2026-11-07。审查者：独立代理 g1_independent_review。实现基线 `df3c081f72d5d86681f37c57ae236543ab45d3e8`；复核时 HEAD `62923957c4892c4daddecb262856fd01678aa48e`，`Experiments/iCloudSyncG1` 相对实现基线无源码差异。只读检查原始手机报告、计划、Mac 请求/结果和公开脱敏副本；未运行控制脚本、排队命令、写云或操作设备。

**结论：本组基础双向往返、真实版本冲突、显式解决及同进程重开证据通过独立逐字段/原字节 oracle。未发现本组证据需要修复的矛盾或数据丢失；完整 G1 仍未通过，首次失败与现有产品 CI 失败均不能消除。**

## 输入与证据完整性

- 六份从 Configurator 取回的手机原始报告含 26 条命令结果；另有 14 组 Mac 请求/结果。总计 40 条结果：38 PASS、2 FAIL。手机计划001首连 FAIL CK_3；Mac r5-007同步 FAIL CK_2。首次失败原件保持，不改写或省略。
- 对六个原始计划 bytes 计算 SHA256，与 planDigest 精确匹配；对每条手机指令按实际 Swift 使用的排序/不转义斜杠 JSON 规则重新编码，核对 commandDigest、planID、run、dataset、顺序。固定输入文本/parents/图片声明也与独立常量相等。Mac 使用原始 request bytes 的摘要核对结果绑定。
- 公开 request 文件与私有原请求逐字节相等；公开 result 与私有原件解析后递归仅删除 accountFingerprint 的对象完全相等，没有删除失败、改事件或改内容。
- 39 条带账户指纹的同 run 结果全部相等，手机首次失败没有账户指纹。指纹仅在内存检查，不打印、不存入审查文件、不提交。旧 r4 与 r5 salt 不同，未跨 run 错比指纹。
- 源文件/输入/审查产物 SHA256 分别保存；报告不复制私有原件。摘要不是运行环境远程证明：实际签名部署和 Configurator 操作由主任务执行，本审查独立验证其交付原始产物，不冒称自己重新操作了设备。

## 逐项核验

| 场景 | 独立证据与结论 |
|---|---|
| 手机空存储取回 | 计划002 connect 与003首条 connect 的账户分区快照为空、pending空。003首次 sync 后出现 FETCH_CONTENT_DURABLE，完整快照精确等于此前 r4 Mac013：2对象、4条 mutation、删除历史及68字节PNG；重复同步/快照不变。 |
| 手机反向新建 | 004新增固定 mutation，save 后仅对象 pending，随后新 ACK/STATE 事件且pending空；Mac003–005取得完全相同的3对象5mutation快照和投影。 |
| 真实版本冲突 | Mac006和手机005各自新增不同 mutation，parents均为相同已知 ios-create；各自此前局部快照只含自己的分支。Mac007相对006新增 SERVER_RECORD_CHANGED_MERGED，结果仍FAIL CK_2。实现源码该事件由实际 CKError.serverRecordChanged 且有 serverRecord 的 SDK回调路径产生。本批原始运行输入未使用故障注入。 |
| 保留失败后的重试 | Mac007不含snapshot/pending/checkpoint，不能臆测失败瞬间队列数量。Mac008随后增加新的ACK/FETCH/STATE事件，PASS、pending清空，包含双方全部内容；009内容相同。只证明这次失败后重试恢复，不称首次同步成功。 |
| 双端冲突一致 | 手机006第2/3条与Mac009完整snapshot/projections相等：两候选均保留，preview为共同祖先 ios-create，complete=false。未将一方覆盖另一方或把冲突误称ready。 |
| 显式解决与收敛 | 手机006第4条新增解决mutation，parents精确引用双方候选；原父/双方分支仍在历史。后续真实ACK清pending。手机006末条与Mac013完整snapshot/projections精确相等：3对象8mutation、唯一已知PNG全部68字节/hash相等、解决投影ready且唯一head，两个原对象及逻辑删除历史不丢。 |
| 同进程重开 | 手机004第4→5、006第6→7、Mac011→012的checkpoint hash分别相等，内容与投影不变，重开的driver事件重新开始。证据是Store/Engine同进程重开，不是独立进程崩溃或设备重启。 |
| 收尾 | Mac014 stop PASS、pending空，snapshot/projections与013相等，driver事件为空。临时桥SIGINT退出130由主任务实际执行报告；单凭stop JSON不能独立证明服务器进程已退出。 |

图片覆盖需精确描述：手机反向新建引用的是先前已从Mac取回、相同hash的固定PNG，手机save只有对象pending。因此它证明引用/原字节随新对象往返保持，不单独证明iOS上传了一个此前云中不存在的新CKAsset。

## 可重跑脚本与负控

```
python3 /private/tmp/g1-dual-review-20261107/verify_dual.py --self-test
```

`verification.log` 保存实际执行输出及原始输入摘要。该验证器使用标准库和独立固定 mutation 常量，逐结果检查全部历史/投影/图片与阶段预期，并检查新事件后缀，避免仅计数相等或累计旧ACK蒙混通过。

**23个内存篡改负控全部被拒绝**：计划/指令摘要、Mac摘要、账户不一致、planID、结果顺序、伪空库、丢基线/反向对象、改写两次首次失败、移除真实冲突事件、复用旧ACK、丢冲突分支、错误共同祖先、将冲突标complete、丢解决parent、图片原字节改变、重复mutation、残留pending、重开checkpoint改变、stop数据丢失、公开副本擅改。除专门的公开副本负控外，其余负控同时更新相应脱敏副本，确保是实质oracle拒绝，而不是仅因副本不一致被挡。所有篡改仅在内存中；原始输入和公开证据完全只读。

## 尚未覆盖和停止边界

本次只关闭固定基础/冲突运行批次，不能据此声称完整 G1 或正式产品同步可发布。仍未在本批真实服务中覆盖：物理断网与恢复、独立进程退出点/崩溃后state恢复、旧ACK在途时新编辑且另一端接收、A→B→A/冷启动账户与晚回调epoch、缺祖先/依赖传递缺失/因果环真实时序、原图缺失/截断及lease退出恢复、恢复发布门与远端安装竞态、Production schema/发布环境。原离线测试或故障注入不得自动升级成这些真实服务门禁。

公开 `ci-status.json` 当前记录定向CI成功、产品CI失败（Release/Unit成功，smoke 3/5，两个短名称布局断言失败）。本审查没有重新访问远端CI验证日志，故将其列为主任务已记录事实；不能称全项目CI绿，也不扩大本次证据审查为产品回归验收。提交脱敏证据后应停在本组批次边界，不由此进入G2/G3或发布。
