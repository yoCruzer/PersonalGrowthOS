# 下一组 G1 批次准备：独立离线复核

2026-11-07，独立审查代理 g1_independent_review。工程 `/private/tmp/PersonalGrowthOS-icloud-g1/Experiments/iCloudSyncG1`。审查者未修改工作树、未执行云/设备操作。最终准确源码副本见 `final-source/`，六文件 SHA256 见 `final-source-sha256.json`；结束前已核对与工作树一致。

**结论：发现的重复运行导出碰撞已修复并以原红例复验关闭；最终候选未发现剩余必须修复项。通过的是离线工程与计划门禁，实际服务执行全部 NOT_RUN。**

## 发现并关闭的问题

初版三个 plan.id 只由固定阶段名构成。两个合法的新 dataset/run 虽有各自私有 journal，但 runManualPlan 共享导出名只包含 plan.id；第二轮执行后发布新结果会抛 identityCollision，旧副本不被覆盖、新结果却无法按正常流程导出。

`repeated-run-red.log` 原样保留：1 test / 1 failure，两个合法私有取消报告均持久完成，第二次导出抛 identityCollision。反例不执行任何命令或云操作。初版源码、6项原生绿测及CLI证据也保留，没有将它们改写成修复后的通过。

修复后 plan.id 为 `probe-两位阶段号-SHA256(dataset|runID|stage)`，73字节，满足80字节身份限制。合法dataset/run不含分隔符，完整摘要绑定三个字段。不同run或dataset生成不同ID，同参数确定；不更改既有手工计划的导出格式。原重复run反例在新候选通过，两份结果分别导出且旧文件保留。

## 计划时序与固定图片

- 三阶段分别16、10、4条命令，整个批次30个命令ID唯一，整计划验证仍在执行前发生，未增加授权入口。
- Mac seed 的12次 save 各自已有结果快照。独立本机逐步检查证实 head-old 先ready/preview=old，head-new随后因缺依赖变staged、preview=nil、唯一candidate=new，未回退旧活行。
- seed最终有9对象/12mutation：deleted对象为deleted；deleted-child、缺祖先对象、传递缺失中间/根、依赖环两端、当前head、因果环均staged且无preview。因果环与依赖环是两种不同反例。
- iOS阶段先connect→fetch→before snapshot，再进行四次repair/save，因此具备保留未修复状态证据的顺序。补祖先、传递叶与head依赖后，预期7个相关对象ready；deleted-child、依赖环两端和因果环仍staged，删除对象仍deleted。16条mutation全部保留。第三阶段Mac再fetch核对最终状态。
- 第二PNG为70字节，SHA256 `4d2e03d73058507a3641207a868534b609e130c3498dc298361d2421873a1e43`，区别于旧68字节PNG。独立验证所有PNG chunk CRC、IHDR和解压行长度，候选测试亦实际ImageIO解码成功。allowlist同时绑定hash与count；错误hash/count拒绝。
- 原样源码的本地双Store重建中，repair端产生4对象pending + 新image pending；从真实Wire.record构造的本地CKAsset读取到的原字节恰为第二PNG，绝非仍写旧PNG。这个CKRecord/CKAsset只在本机编码，未启动引擎、无CloudKit账户查询/服务调用。

## 独立测试证据

- 初版 `native.log`：6/6 PASS（2独立+4候选），与随后发现的重复run红例分别记录。
- 最终 `native-fixed.log`：7/7 PASS（3独立+4候选），包含原重复运行红例原样复验、逐保存边界、不回退旧head、修复前后状态、无云双Store编解码、第二图片Wire内容、输出权限和非法目标。
- `cli-fixed.log`：实际编译的Debug LabReplay执行prepare-batch，只生成3目录/3计划文件，不创建Store或授权云访问；umask000下顶层仍0700；已有目标拒绝且原字节不变。独立精确动作/边/删除/图片oracle及14个内存篡改负控全部通过。初版 `cli.log` 和 `verify_cli.py` 原样保留，最终脚本是 `verify_cli_fixed.py`。
- `release-build.log`、`release-boundary.log`：实际Release编译成功；实际Release二进制调用prepare-batch在创建目标前拒绝（预期非零exit -5），无成功输出，符号中无RemainingBatch。此验证在最后身份修复前执行；之后仅变更DEBUG范围内的计划ID/测试/文档，Release入口和整文件的条件边界未改，不将其冒充最后源码重新构建的独立结果。

执行命令：

```
swift test --package-path /private/tmp/g1-next-batch-review/candidate-fixed --scratch-path /private/tmp/g1-next-batch-review/build-fixed
python3 /private/tmp/g1-next-batch-review/verify_cli_fixed.py
swift build -c release --package-path /private/tmp/g1-next-batch-review/candidate --scratch-path /private/tmp/g1-next-batch-review/release-build
python3 /private/tmp/g1-next-batch-review/verify_release.py
```

目录保护：最终输出目录用mkdir0700且必须不存在；已有普通文件、目录、有效/悬空symlink均拒绝。子文件以withoutOverwriting写入，私有父目录限制其他用户访问。生成内容仅含固定合成计划，没有账户标识、token、路径指令或环境授权。Release不编译批次实现和CLI分支；DevelopmentProbe及新增图片也继续位于DEBUG边界内。

## 真实运行前提和保留的限制

README已补充必须使用从未运行过的新dataset/zone。手机before快照没有第二hash只说明当前引用未出现，不能排除远端孤立image record。若新zone前提无法证明，标UNVERIFIED；必须实际观察手机save新增对应image pending和对象pending、随后真实ACK清空，再由Mac下载核对70原字节/hash，才能声称全新iOS CKAsset上传。此次离线准备不证明这些条件已经成立。

阶段间应核验前一阶段实际结果后再运行下一设备；任何FAIL或不完整快照都不能按“计划已经生成”继续记PASS。本计划能观察稳定的修复前/后状态，不控制SDK每条记录实际到达顺序或内部callback的任意退出点。

新签名部署、这30条真实命令、原生断网恢复、独立进程崩溃/state退出点、账户A→B→A、旧ACK在途新编辑、图片缺失/截断/lease退出、恢复门竞争、完整G1与Production仍未由本批审查覆盖。主任务报告的完整51项及签名构建不计入本报告独立测试数量。
