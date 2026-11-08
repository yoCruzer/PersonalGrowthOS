# 独立 Mac 配置、签名与离线资格验证

2026-11-08。Owner明确回复“同意由你按清单配置和预检”。实际完成独立App ID注册、iCloud/CloudKit支持与唯一正式容器关联、Mac Development profile生成下载；复用1张已有开发证书和1台已登记Mac，没有新增证书/设备，未改正式App或SyncLab。保存后回读关联，下载文件14014字节。参见[授权与门户摘要](authorization-and-portal.json)。

原profile、证书、设备标识、CMS解码和签名原始输出仅保存在仓库外。签名前核对profile的OSX平台、精确AppID/Team/容器、有效期、明确provisioning UDID覆盖，以及DeveloperCertificates与本机有效身份SHA1交集。签后再次核对实际叶证书；未导出私钥。公开材料仅摘要、布尔检查与合成测试。

## 实际发现与修复

1. profile使用服务字符串`*`和环境允许集合`[Production, Development]`。旧preflight真实返回exit2/PROFILE_MISMATCH_OR_EXPIRED，虽然signatureVerified=true。依照[Apple TN3125允许列表语义](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)修正profile解析，未知/混合/重复值拒绝；实际App签名仍只允许CloudKit/Development。保留[旧失败](preflight-before-allowlist-fix.json)及[同一旧签名副本修复后结果](preflight-after-allowlist-fix-47df1f3.json)。profile中的Production不是运行/部署授权。
2. 真正签名的App Sandbox拒绝外部临时计划，外部程序写探针容器也被macOS拒绝。新增无路径参数`inspect-fixture`，只在系统提供的进程临时目录中新UUID目录生成固定合成计划并输出脱敏报告。目录祖先改Darwin `O_SEARCH`，末级仍O_RDONLY；O_NOFOLLOW、fd相对访问、独占创建和目录身份复查保留。没有关闭sandbox或授予额外磁盘权限。最初系统`/var`别名导致invalidPath后，只有系统temp使用realpath规范化，调用方路径仍严格拒绝符号链接。
3. preflight的注册字段改为`NOT_VERIFIED_BY_PREFLIGHT`，避免将静态检查错误描述为“未注册”。门户注册已由单独事实证明；preflight仍不自动证明证书/设备资格，实际资格在独立签名报告中核验。

[初始失败摘要](initial-failures.json)、[实现历史](host-implementation-history.json)及原始合成失败日志均保留。受限工具沙盒中的CMS/证书信任失败，在正常本机上下文对同一文件验签通过；未修改系统信任设置。O_EVTONLY试验失败不当作可行修复。

## 最终本机证据

- 完整包62项（24协议+17准备器+21SDK/host），0失败；iOS17 FormalDevelopmentSDK编译通过，iOS17运行NOT_RUN。
- 实际未配置签名的新包32检查、既有独立CLI22命令通过；[源码及产物receipt](packaging-final.json)绑定22个源码/测试/manifest文件。
- [允许值独立审查](review-allowance/README.md)：3 XCTest，272类型组合、8序列化往返、1正11负签名边界。
- [目录/host独立审查](review-host/README.md)：8 XCTest和8 CLI检查；独立最终签名31项通过，源文件/pins/编译快照/receipt/签名/已有runtime报告一致。
- [最终实际静态预检](preflight-final.json) exit0 `STATIC_SIGNING_MATCH_REQUIRES_OWNER_GATE`。
- [最终实际签名沙盒运行](signed-inspect-fixture-final.json) exit2 `NOT_READY / EXTERNAL_GATE_NOT_COMPLETE`。这是锁定门禁的预期正确结果，不是CloudKit失败，也不是真实云通过。网络计数0，networkAuthorized与p0Passed均false。

最初47df1f3签名副本和最终新副本分别留证，签名会改变Mach-O摘要，不要求已签hash等于未签hash。最终签名二进制SHA256为`5708bd5bd9b4bfcb81937310c535b590965047bdab19833e521213be380ca7cf`；没有重复运行独立审查中已有的实际App自检。

当前候选远端CI待稳定提交后验证，旧47df1f3成功不替代本次。未重新跑G1、未占手机或数据线、未切换系统账户。正式Development/P0真实往返、Production/P1/P2仍未通过；真实authority factory、持久单次执行和账户/取消保护尚待实现，见[后续保护设计](../../../../ICLOUD_SYNC_FORMAL_EXECUTION_GUARD_DESIGN_ZH.md)。本次未进行任何CloudKit操作、Production、Archive、TestFlight或merge。
