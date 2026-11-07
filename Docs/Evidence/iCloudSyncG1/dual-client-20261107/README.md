# 真实双客户端基础往返与冲突验证

固定实现源码df3c081，签名Debug；Mac专用haha用户与单台iPhone，同run账户指纹仅在私有原件比较，不入库。所有云数据为SyncLab Development的synthetic-g1-20261107-r4。

六份手机原始报告经Apple Configurator仅导出SyncLab文稿，逐份核验原计划及命令摘要；这里的报告副本仅删除accountFingerprint并格式化。request文件保留原始字节。Mac请求/结果来自本机受限认证桥，副本同样仅去指纹。历史单Mac基准见../runtime-20261107。

- 手机001首次连接FAIL CK_3，002重试PASS；不推定首次网络失败具体原因。
- 手机003从空库取回Mac两对象、四条历史及68字节PNG；重复同步无内容变化。
- 手机004新增对象，真实ACK、pending清空、同进程存储/引擎重开；Mac003–005取回完整一致快照。
- Mac006与手机005从同一父记录分别修改。Mac007真实serverRecordChanged后报告FAIL CK_2；008重试成功、009保留双方候选和共同祖先preview。
- 手机006先取回相同冲突，再用双父mutation解决，双方历史不删除。Mac010–013取得与手机末条完全相同的snapshot/projections，PNG字节一致，pending均空；各端同进程重开保留checkpoint。
- Mac014停止PASS、快照不变；临时桥受控SIGINT退出130。手机每份计划结束自动停止引擎。

这些结果不等于完整G1通过，不含进程崩溃/真实断网恢复/账户A→B→A/依赖缺失及循环真实时序/旧ACK与新编辑/图片故障与恢复竞态等剩余门禁。不进入G2/G3、正式库或发布。

独立复核：40条实际结果=38 PASS、2保留FAIL；39个可用同run账户指纹一致，23项篡改负控全部拒绝，无must-fix。详见[独立报告](independent-review/review.md)与[脚本](independent-review/verify_dual.py)。

额外覆盖限制：手机反向新建复用了从Mac获取的同一PNG hash，pending仅object；不单独证明iOS上传全新未见过的CKAsset。桥退出130来自主执行记录，独立stop JSON只证明停止命令完成及内容保留。
