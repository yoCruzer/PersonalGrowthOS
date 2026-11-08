# 隔离Mac未配置签名包：独立审查

2026-11-08，审查者`/root/readiness`。只使用当前源码及独立临时副本、固定合成计划；不签名、不访问CloudKit、不创建Apple资源或读取业务数据。现有profile/签名身份只读摘要另见上级文件，不把这些元数据当成实际App资格通过。

## 发现并关闭的来源绑定问题

初稿检查原仓库源码前后不变，却未检查实际供Swift编译的`source-snapshot`。独立在真实`swift build`开始前，仅向临时快照的host源码追加一行合成注释：实际编译成功，初稿也返回成功，但receipt记录的源码摘要与编译输入不一致。`red-result.json`、初稿脚本、真实build日志和原receipt保留。

最终实现持有编译输入目录fd，构建前后、产品路径查询后及receipt前重核完整快照和目录身份。相同注入、相同真实构建在最终版本明确返回`COMPILER_INPUT_CHANGED`，未发布`packaging.json`；见`green-result.json`和真实build日志。不是用模拟编译器返回值证明修复，不声称能够防任意恶意同用户ABA。

第一次独立复现准备漏复制脚本相邻的source-pin文件，未进入构建；审查脚本随后读取不存在输出而报错。该审查环境错误原始`red-console.log`保留，不作为产品失败。补齐必需的相邻清单后第二次才取得上述有效红例。

## 实际产物正负检查

最终对`/private/tmp/pgos-locked-app-bound-20261108/FormalSyncProbe.app`完成**20项独立检查**，`summary.json`逐项记录；另列上面1个编译输入变更回归，不与实现者28项相加。

核对receipt全部20个输入文件同时匹配实际编译快照与当前源码；binary/Info.plist/外部entitlement三份摘要一致；独立Bundle ID、MacOSX、macOS14、可执行文件名正确。App没有embedded profile、签名资源或已应用entitlement文件，外部候选只限正式容器Development/sandbox/network client，不含App Group或Push。

实际运行App内可执行文件：固定计划inspect退出2、NOT_READY、零网络且无授权；真实preflight拒绝缺profile/正式代码身份；live参数退出64。既有输出拒绝且receipt原字节不变；父目录symlink不产生输出；新增/改名源条目拒绝；输出位于源码包内拒绝。未修改正式App或SyncLab。

receipt只陈述构建及来源摘要，`appExecutionPerformed=false`不被用作运行通过证据；本目录的独立inspect/preflight才是实际运行检查。linker ad-hoc签名不等于开发者签名、profile资格或CloudKit访问权限。

最终脚本SHA256为`a591393b35a93e969aa25849b5d180b9d766944b4cebc8e3e3198886001999e7`，实际binary为`850e08fe6ecb6afa1de96f39db29db101d85c8027094b591ebc97da3a77f35c4`；摘要清单见`source-verification.json`。当前scope无剩余must-fix。

集中配置清单边界经只读复核：复用已确认正式App配置与已有1个本机开发身份；先核查独立候选Identifier是否存在，缺失时在获批后创建；准备匹配macOS Development profile及后续离线签名预检。它不授权live、Production、切换账户或发布。当前P0/P1/P2仍未通过。
