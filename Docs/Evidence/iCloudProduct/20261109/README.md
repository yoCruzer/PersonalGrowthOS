# 2026-11-09：性能、中文及TestFlight代码候选

## 最新Owner授权与真实设备反馈

Owner确认build11点击Create workspace后，正式Development出现业务Record Types，Pending429→0，约5分钟后显示Latest sync completed；重进页面却显示Waiting，设备有发热感。这是Owner界面报告，不冒称agent已读取云记录或完成双设备/Production验收。Owner随后报告简体中文环境同步页全英文。

Owner明确授权睡后继续，包括普通推送GitHub及testflight-*标签触发TestFlight测试。不再逐步询问这些已授权动作；未授权公开App Store上架、merge、强推/改历史、删数据、退出iCloud或凭据操作。Owner手机陪测仍不作为后续代码/后台准备前提。

## 已修复与验证

- 下载原先逐条持久化后都project全量清单/原图/领域图，导致自身回显的重复计算。现在inbox仅持久化、保留临时资产复制与checkpoint顺序，成功收尾时统一apply；活跃会话重试前也重放durable inbox，冷启动路径在网络结束后应用。64个独立合成业务版本/128个下载record逐条接收时project=0，重开磁盘后显式应用project=1，业务完整恢复且不产生echo outbox。不是手机实测的耗时或温度改善保证。
- 显示检查/上传/下载/应用四阶段，Pending0不当作整个收尾完成；重进保留上次真正完成时间。blockedReason或未完成outbox存在时不推进lastSuccess；未保存草稿/缺件继续保留原数据。旧机器错误reason保留、按当前语言显示说明。
- 新增200条简体中文资源，原1310条资源逐项不变；同步页/确认/状态/冲突预览标签与格式占位符检查通过。真实中文UI合成截图已查看，中文默认关闭/取消确认/历史完成时间重进/下载阶段以及英文相邻路径通过。
- Release仅正式bundle+production pin，Debug保留Development profile检查，simulator不激活云。发行可能无embedded profile，代码不把runtime pin当有效签名证明；最终发行签名仍须产物核验。
- V18只追加本地ProductSyncSelection，V17七个旧实体和schema声明字节不变（独审SHA256 2c9c85e9ceb7f8abb2d87a73e92d3a79eda5ecab9c9635d5e9ae6b75c2842775）。双realm指针保留Dev/Prod身份、ACK/token/inbox；转场禁用旧epoch，Production默认关闭，用户明确Enable才采集本地事实为新baseline。返回原环境先full fingerprint diff，沿原heads生成增量；不复制另一环境ACK，restore保留旧headers并仅替当前realm新随机unbound身份。

本机Xcode27.1/macOS27.0.1、隔离iOS27.0模拟器：

| 验证 | 原始证据 | 结果 |
| --- | --- | --- |
| 完整产品Unit一次 | /private/tmp/PGOS-TF-Candidate-Unit.xcresult | 702执行=701PASS/0FAIL/1SKIP |
| 集中产品UI | /private/tmp/PGOS-TF-Candidate-UI.xcresult | 8/8PASS，0FAIL/0SKIP |
| 早期收尾/持久化定向 | /private/tmp/PGOS-Sync-Completion-Fix.xcresult | 21/21PASS |
| 独立阶段SDK harness | /private/tmp/pgos-sync-activity-tests.log | 27/27PASS，iOS17typecheck通过 |
| 配置纯测试 | /private/tmp/pgos-build-configuration-tddahzsk/result.json | Debug10/10、Release10/10 |
| schema parser自测及独立复核 | /private/tmp/pgos-schema-index-audit-tests-20261109.log | 21/21PASS，两次独立执行 |

两个最终xcresult runtimeWarnings为空；既有Swift6语言模式编译warning保留。唯一Unit跳过仍为需要隔离32MB HFS+镜像的低空间测试，未填满主卷。optional extended UI未另跑。各阶段计数不相加声称同轮全量。

首个定向构建因新增fixture把可空Entry.body当String而失败，修正为显式unwrap；第二轮49项为48PASS/1FAIL，原因是原测试把canonical英文落盘原因与已正确中文化的UI文案硬比，修正后同时验证canonical与localized值。原日志/xcresult保留，没有改生产原因或掩盖失败。完整Unit和UI是修正后的集中验证。

独立审查覆盖持久化先于checkpoint、失效session、完成时间门、双realm/恢复/V17原件保护及权限配置，未发现must-fix。仍有非阻塞上传热点：逐record扫描mutation、逐chunk重复全payload校验；本轮未用不安全的跨epoch/字节缓存绕过校验。未测真机热功耗、未声称消除所有卡顿。

## 正式schema只读核对与边界

登录会话观察正式Team83SKX2PM7B、容器iCloud.com.yocruzer.PersonalGrowthOS。Development当前导出1949B，SHA2566ba50154c75b3780dbe114a0c8bfb3db251fc5f70985fee14f4304c042ec53d5；与v2 codec的3类/11业务字段完全匹配。保留9个带索引字段/21个索引flag以及三类各CREATE/_icloud、READ/_world、WRITE/_creator，应用只使用privateDatabase。Users不变。

Production当前导出预览只见Users七字段及原grants。审计绑定输入仍为Owner此前356B导出（60fec48392126eab598a05dbe0f7f9557494a992df8fb62295ccd3752a7768db），当前UI预览提供结构相同的独立观察；未获取新的Production文件下载，绝不冒称fresh export。raw文件/来源/失败仅本机/private/tmp/PGOS-TestFlight-20261109，公开摘要见schema-preflight.json。未查任何业务record、未部署Production。

旧parser不支持实际QUERYABLE/SEARCHABLE/SORTABLE而拒绝导出，原拒绝保留；已增加严格白名单并完整记录fieldIndexes，拒绝重复/未知/错位置语法，21个原创合成测试与独立复核通过。同原件重跑：Dev缺0/错0，Prod缺3类/11字段。工具仍REVIEW_ONLY_NOT_DEPLOYABLE、gates均false，不将结构比对冒充部署或真实收发成功。

## 当前外部阻塞

Safari只读到上述结构和既有ASC会话；随后Mac锁屏，CUA自动解锁失败，已结束UI操作。未绕过锁屏/提取凭据。解锁后须重新导出Production、复核精确部署差异及XcodeCloud既有testflight-*触发/Release Archive/分发组/构建号，再推进已授权标签。当前没有本轮testflight标签、Archive分发或TestFlight可用的成功证据。代码/本机验证已完成，继续固定源码并做Release离线Archive和远端独立CI。

不需手机或数据线；醒后只需解锁Mac（若Apple重新登录/验证码，Owner在Apple界面输入）。最终真实Production/双向/故障矩阵、TestFlight安装验收保持待验证，不能用Dev429→0或CI通过替代。


## 固定候选的Archive与独立CI后续

代码候选`32ce4ea7e4172eb4314ab68a7cc229e8d607786f`已普通推送。Release普通无签名Archive成功，来源32ce4ea/Dirty=false，主App/Share/Widget均1.0(12)，编译后的中文资源已逐值核对；runtime pin=production，请求的CloudKit环境Production、APS production、正式bundle/Team均匹配。私有原件`/private/tmp/PGOS-TF-Unsigned-32ce4ea.xcarchive`、receipt`/private/tmp/PGOS-TestFlight-20261109/archive-32ce4ea.json`。它未发行签名、未上传，不能填P3签名通过。

[首轮定向CI42506613444](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42506613444)失败：旧历史independent reviewer把现在明确支持的QUERYABLE当未知语法，AssertionError unknown-index（expected2/actual0）；原始工具日志保存在私有`foundation-32ce4ea-failure-tool-result.json`，后续独立SDK/打包步骤因此跳过。schema21自测及此前native阶段通过，不把整轮写PASS。

保留旧日期checker及原输出不动，新增active reviewer `Scripts/SyncSchemaAudit/review_schema.py`：原20检查保留，仅该负例改真正FUTURE_INDEX，增加已知3flags完整保留/索引顺序等价/已知后未知拒绝三个独立case。23/23通过且另一个审查者独立重放通过；CI仅改调用路径，不删gate、不把字段匹配当部署通过。修改不涉及应用/协议代码，因此不重跑本机全Unit/UI；最终远端结果及新源码Archive绑定将在收口记录。
