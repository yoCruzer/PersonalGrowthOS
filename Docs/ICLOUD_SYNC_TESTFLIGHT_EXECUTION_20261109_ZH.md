# iCloud同步：已授权TestFlight执行范围

Owner于2026-11-09明确授权：“我要去睡觉了，明确授权你接下来的操作（包括将代码推送到GitHub，以及打testflight-前缀的tag进行test flight测试等）”。这覆盖代码推送及既有流程所需的Archive/TestFlight测试分发，不再请求重复许可；公开App Store上架、merge、强推、删除/重置数据、退出系统账户及凭据/安全设置变更仍不在范围内。

本轮解释为通过TestFlight推进正式环境测试：P2/P4可在获批测试分发后验收，不能提前写通过或称公开发布就绪。Production schema须先具体核对差异再处理，不能给已知缺正式schema的候选打分发标签。遇新法律条款或安全敏感权限操作仍遵循其动作时边界。

## 已完成的代码与本机门

性能收尾、进度/完成时间与简体中文已修复；Release正式环境路由及V18双realm本地选择器已实现、独立审查通过。完整Unit701PASS/1SKIP、UI8/8PASS。Dev/Prod不共享ACK/token/inbox；本地业务事实保留，首次Production启用仍需用户在App明确确认，不自动把Dev云记录复制到Prod。详情与真实失败见[证据](Evidence/iCloudProduct/20261109/README.md)。

本机源码构建号12；不能把它当作最终XcodeCloud/TestFlight构建号。V18升级后不以降级旧build11作为回滚方式；旧Store/备份保留，不卸载或清库。

## 具体后续顺序

1. 固定非skip候选提交，普通推送现有codex/icloud-product，完成最终独立CI；签名/Archive源SHA、主App与两个扩展版本一致性独立核验。离线unsigned Archive只证明构建与请求配置，不冒充发行签名。
2. 解锁Mac后在既有正式CloudKit会话重新导出两环境。仅审核3类/11业务字段、9个indexed字段/21个flag及实际grants的添加差异；Users/既有类型无改动、无删除，不复制Dev记录、不查业务数据。当前Production仅Users观察不足以宣称部署成功，必须保留部署前后结构及结果。
3. 只读核对既有XcodeCloud product65882429-6fca-4481-8065-30dd0daf8fff / target543C8892-7DD6-4620-B16C-B4F7DFE0255E：testflight-* start condition、Release Archive、发行准备、既有TestFlight组及构建号策略。不新增测试人员或更改原标签机制。
4. 前置条件满足后创建新的不可移动testflight-*标签，精确指向已验证的非skip代码提交（不能给后续[skip ci]文档提交打发行标签）。普通推送标签并跟踪实际SHA→Archive→上传→TestFlight可用；历史9个同前缀标签不能替代当前结果。
5. 核对实际发行权限为正式App/容器、CloudKit、Production、production APS及发行签名。Release runtime pin不是有效签名证明。TestFlight可用也不等于Production同步/离线/推送和完整故障矩阵验收通过。

## 集中人工依赖

当前Mac已锁屏且自动解锁失败，后台UI核对和部署因此不能继续。醒后只需解锁Mac，预计本人操作10–30秒；手机前台/数据线0。若Apple会话过期，密码/验证码只由Owner在Apple界面输入。已有TestFlight授权继续有效，不再重新询问。解锁后agent继续上述集中后台操作；预期后台准备10–20分钟，Apple构建/处理时间另计。
