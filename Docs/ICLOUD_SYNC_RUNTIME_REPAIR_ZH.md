# 真实窗口失败后的运行时修复

2026-11-08，当前为代码修复与离线验证；新签名产物没有真实云执行授权，P0/P1/P2未通过。原始失败保留，不再要求Owner用云批次诊断。

## 实际结果与原因

Owner批准的`b3cd013`固定窗口已执行：旧run的closeout exit0，验证现有anchor后仅追加第6条`ownerClosedUnknown`；原5条不变。这是本地未知结果收口，不能表示历史云结果成功。随后新run exit1，两个只读导出exit0；新run目录不存在、ledger仍为同一6条，没有新消费。结合入口顺序与该进程日志，显式账户API和transport均0；不声称操作系统服务完全无活动。

系统原始日志显示新run所调用的`system_profiler`在5秒后终止未响应的硬件报告子进程，随后返回`No items returned for: SPHardwareDataType`。时间与新run失败吻合；该进程没有后续Keychain/ledger活动。这是本次运行时资格检查失败的直接证据。旧顶层catch只输出`GUARDED_EXECUTION_FAILED`，没有保存最终Swift拒绝枚举；不能伪造它，也不能据此断言第一次107963d失败具有同一原因。原始系统日志、审批、ledger与完整导出仅私存，公开摘要及hash见[实际结果](Evidence/iCloudSyncFoundation/20261108/execution-guard/runtime-fix/actual-failed-window.json)。旧交付入口已停用，禁止重跑。

此前把同步离线PASS当作真实异步入口足够的前置验证、反复依赖不稳定硬件报告，以及漏掉顶层错误，是本轮实现和验证的不足。不能归咎于Owner操作或既已接受的CK_2。

## 已实现修复及语义变化

- 生产资格路径不再启动`system_profiler`或硬件报告子进程。通过公开Security API读取实际运行进程的dynamic status，前后两次要求`CS_VALID`与`CS_ENTITLEMENTS_VALIDATED`，拒绝ad-hoc/linker签名及缺失、伪类型、越界状态；静态签名flags和调用方JSON不能制造资格。
- 保留实际自身动态/静态签名、固定Team/Bundle/container及7项entitlements、Apple CMS与证书链、profile期限、签名证书、二进制/profile/Info/源码收据hash和前后绑定检查。Development profile仍必须有合法非空设备列表。
- **这不是同一保证的替代实现**：不再在运行时独立证明“当前设备UDID属于这份精确嵌入profile”。OS状态证明运行进程的受限entitlements已由系统验证，不返回OS实际选择的profile身份。嵌入profile的真实性/绑定检查与OS准入分别记录。原纯UDID membership校验只保留作离线审计，不作为运行时来源。没有Hardware UUID推导或回退。
- 报告升级`evidenceVersion=2`；旧`signatureProfileDeviceVerified`恒false，明确`exactProfileDeviceMembership=NOT_RECHECKED_AT_RUNTIME`。成功分别报告签名/profile与OS准入；未验证时`deviceEligibilityEvidence=NOT_VERIFIED`。即使成功仍`p0Passed=false`、账户/服务`NOT_RUN`。
- 新`inspect-runtime-async`覆盖MainActor入口、yield与continuation四个固定阶段，首次失败即停；不打开Keychain/ledger、不构造CloudKit。顶层失败输出白名单原因，不输出原始Error/userInfo，不从错误码推断已发生的副作用。

公开语义依据：[Security status](https://developer.apple.com/documentation/security/kseccodeinfostatus)、[Apple受限entitlements说明](https://developer.apple.com/documentation/xcode/accessing-app-group-containers)、[Security实现](https://github.com/apple-oss-distributions/Security/blob/main/OSX/libsecurity_codesigning/lib/SecCode.cpp)、[XNU状态位](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/cs_blobs.h)。精确profile选择的限制已经独立审查，不将两种证据混同。

## 本机验证与未验证范围

完整包187/187（协议24、core17、SDK146），包含独立状态位/数值类型与拒绝报告测试；保留独立边界35项另行验证。新打包46/46，iOS17 SDK编译通过、运行NOT_RUN。实际签名产物同步检查及四异步阶段全部PASS，后者共约0.04秒，无Keychain/云调用；原始报告与签名binary摘要见[证据目录](Evidence/iCloudSyncFoundation/20261108/execution-guard/runtime-fix)。50个Swift源码/测试文件绑定到打包快照。

这是开发用户上的实际签名结果；随后Owner已在haha执行同一签名产物，只读四阶段4/4 PASS、约0.93秒、无云/Keychain调用；新云验证仍NOT_RUN。不得从纯测试或开发用户PASS推断haha/账户服务通过。目标用户只读检查已完成，不重复；[真实Development新批次](ICLOUD_SYNC_RUNTIME_FIXED_WINDOW_ZH.md)的具体产物与范围已准备，须获新授权，不能复用本次失败授权。已有closeout不重复、anchor不重新初始化，手机/数据线均不需要。Production/发布/合并未授权且未执行。

之前`b3cd013`[产品CI42474881346](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42474881346)已SUCCESS，三份ZIP摘要与checkout核验：Release3个unsigned bundle、Unit598PASS/1SKIP/0FAIL、Smoke5/5，runtimeWarnings为空。低空间镜像前置缺失与optional extended UI未运行保留。新改动限隔离探针与测试，不修改正式产品代码；该旧CI不覆盖新探针代码。新节点a72befa定向CI42482033378 SUCCESS；187原生、35保留独立、46打包及既有检查通过，ZIP摘要/308成员/merge checkout f873cca/50源pins核验。自动产品CI42482033328因产品Git对象与已全绿b3cd013完全相同主动取消，Release成功、Unit/Smoke取消，未算通过。
