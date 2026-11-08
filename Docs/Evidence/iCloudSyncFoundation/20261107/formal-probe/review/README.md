# 正式 Development 批次准备器：独立复核

2026-11-07。审查者 `/root/readiness`，独立于实现者。源码冻结后复制到 `/private/tmp/PGOS-FormalProbeIndependent.SDgRJQ/Candidate`，单独原生构建并通过外部 CLI 检查；没有运行 CloudKit 网络、打开业务库或重跑旧 G1。此目录不沿用 v1/v2 先前的测试计数。

## 结果

当前离线准备器范围内无剩余 must-fix。最终 **22 条 CLI 调用**全部符合独立预期；不是22项XCTest，也不和实现者10项新增单元测试相加。首次19条已通过；随后加强固定文字原字节与重复/缺失/重排记录反例，最终22条通过，两个输出均保留。独立并发 artifact 替换另有1个本机负例通过，不列入稳定CI计数。

检查包括：两个计划具有不同run/dataset及固定正式Development身份/schema；6条record SDK回放、创建→修改→逻辑删除父链、固定文字精确值及原PNG；PNG逐chunk CRC、1×1尺寸、zlib像素数据解压有效；外部expected hash错误、输入字节改变、缺原图、多文件、重算hash后改变environment/container/schema/version/记录次序/重复/缺失/路径逃逸均拒绝；leaf/root/ancestor symlink拒绝；已有计划和报告逐字节不变。成功/失败报告均明确零网络、`p0Passed=false`，原计划前后摘要不变。

实际本机SwiftPM二进制的preflight退出2、`NOT_READY`、正式身份/能力/profile拒绝。该二进制有可验证的本地ad-hoc代码签名，因此其 `signatureVerified=true` 是实际代码签名校验事实，**不是正式签名资格通过**；`readyForCloudRun=false`、`networkAuthorized=false`、实际服务 `NOT_RUN`。

独立并发负例对该二进制的两份同字节副本进行921次不同inode替换，同时执行真实codesign preflight；得到 `ARTIFACT_CHANGED`、`SIGNATURE_NOT_VERIFIED`、`signatureVerified=false`、`NOT_READY`。原始结果见 `artifact-race-result.json`。复现脚本 `artifact_race.py` 为时序相关本机检查，不纳入稳定CI，不宣称能证明任意恶意ABA替换安全；签名产物和SDK资产仍要求调用者不可变lease。

## 复现及原始证据

```sh
swift build --package-path /private/tmp/PGOS-FormalProbeIndependent.SDgRJQ/Candidate --scratch-path /private/tmp/PGOS-FormalProbeIndependent.SDgRJQ/build --product FormalDevelopmentProbe
python3 review_cli.py /private/tmp/PGOS-FormalProbeIndependent.SDgRJQ/build/out/Products/Debug/FormalDevelopmentProbe /private/tmp/PGOS-FormalProbeIndependent.SDgRJQ/NEW_CLI_OUTPUT
```

首轮build因沙箱不能写标准Clang模块缓存而失败，`build.log`原样保留；授权标准原生Swift构建后exit0，见`build-authorized.log`。没有为该环境错误修改产品。`review_cli.py`自包含，只有明确合成输入，可在定向CI用新输出目录复用。它不会执行`artifact_race.py`。

`source-sha256.json`绑定实际快照；`source-verification.json`确认当前包源码、测试和Package.swift全部一致，并绑定实际独立构建binary摘要。README纯文档不作为代码匹配门禁。`cli/summary.json`列出22条实际调用/退出码；同目录保留stdout/stderr和成功/拒绝报告，`plan/`保留最终合成输入。旧19条原始输出为`cli-01.log`，最终为`cli-02.log`。

静态审查确认根代理指出的初稿PNG、路径/fd混用已修复为有效PNG、fd相对逐组件目录访问与SDK边界路径绑定；后续独立要求的签名同一产物绑定已加入前后元数据/combined details与XML/profile bytes/二次verify，异常拒绝。初稿未作为正式测试通过；本目录只为最终冻结源码背书。

## 未验证边界

未创建候选Bundle ID、未签名或安装正式客户端、未验证profile证书/设备资格、未调用真实CloudKit服务、未导入或部署schema。准备器未实现持久outbox/inbox、真实发送/下载、账户切换或领域发布。P0未冻结，P1/P2未通过；此次离线成功不能填正式门禁。
