# 独立Mac客户端可构建产物与签名资格准备

Owner已确认正式App四项关联，见同级上层`formal-app-association-owner.json`；不再重复只读导出。本机profile只读摘要记录6份成功解析、精确候选匹配0以及通配不适用。证书subject OU与有效签名身份交叉核验找到1个目标Team的Apple Development身份；先前按显示名筛选0的观察保留且被更准确结果取代。没有导出私钥、原profile或个人证书信息。

新增`Scripts/FormalDevelopmentHost`，从完整hash绑定的现有Swift源码构建原生Mac未配置开发签名App，保持独立Bundle ID、无AppGroup、不签名、不注册、不安装、不启动CloudKit。外置entitlements仅候选。保留链接器ad-hoc签名不等于开发者签名；实际.app验签失败和无profile拒绝照实留证。

本机实际构建与28项检查通过：产物/源码/hash、独立身份、实际inspect exit2/NOT_READY、实际preflight exit2/NOT_READY、live/wronghash拒绝、既有输出不覆盖、源码/输出symlink、未审源码和package内部输出等。构建快照缺少重新绑定的独立红例已修，独立复核另存review。原输入、失败及初始日志保留，不与最终计数相加。

候选自身Swift代码及测试未变，原d508ae4定向51项及产品回归证据仍成立；新增打包工具与工作流已在固定47df1f3的[定向CI](../ci-foundation-47df1f3/README.md)通过，包含远端实际打包与28项检查。P0/P1/P2仍未通过。下一外部项为[独立客户端配置清单](../../../../ICLOUD_SYNC_FORMAL_HOST_PROVISIONING_ZH.md)，先查复用候选Identifier，再按获批范围补Mac Development profile及实际签名静态预检；不授权live或Production。
