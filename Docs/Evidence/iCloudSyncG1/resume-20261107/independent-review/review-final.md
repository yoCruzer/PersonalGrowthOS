# G1签名门禁独立复核 — 2026-11-07

结论：本轮限定修复通过；无剩余必须修复项。真实CloudKit服务仍NOT_RUN。本审查不独立认证实际签名包可运行，也没有读取私人签名日志、真实profile、账户或设备标识。

## 规则与发现

- profile services `*` 或精确CloudKit allowlist可以授权 signed `['CloudKit']`；signed wildcard、额外service、类型错误仍拒绝。
- profile Development/Production数组顺序不影响授权；signed必须精确Development。profile只有Production、通配environment或畸形类型全部拒绝。
- Team、Bundle、App ID、Push、有效期、实验容器及无产品App Group门禁保持。
- 复核发现原有container字符串子串匹配问题：合成profile值`prefix-<expected>-suffix`错误PASS。实现者已改为仅接受list[str]精确成员；独立原反例转为FAIL，合法数组仍PASS。原观察日志未覆盖。
- CI只增加Python离线门禁测试与日志，保留限定分支/路径和contents:read；未增加签名密钥、部署或发布动作。

## 独立验证

初轮完整脚本合成integration 24/24、仓库helper 7/7；追加容器负例后最终完整脚本integration 30/30、仓库helper 8/8。所有命令exit0。完整脚本运行使用临时Synthetic.app及mock codesign/security输出，验证的是门禁逻辑，不是真实密码学签名或设备资格。

独立反例覆盖：签名验证失败、无embedded profile、过期、错team/bundle/container/push、产品App Group、profile服务及环境缺失/畸形、signed通配/额外service/Production，以及容器字符串/子串/通配/畸形数组/额外signed容器。合法显式allowlist及Apple所观察profile形态为成对正例。

原始证据：`independent-gate.log`、`repository-tests.log`、`preexisting-container-observation.json`、`independent-final.log`、`repository-final.log`。初版/最终独立测试源码均保留，命令与SHA见两个manifest。

[Apple TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)区分profile授权集合与App实际签名声明，说明profile可含额外权限及部分通配形式；本轮保持这一边界，不把profile通配值接受为signed声明。

## 审查源码SHA256

- `Experiments/iCloudSyncG1/Tools/verify_signing.py`：`35735c0a1fbf0a060aaa86a9b6add1876af2907089e1c8473b2b09ce8fd54d98`
- `Experiments/iCloudSyncG1/Tools/profile_entitlements.py`：`5c33ffb55a21c703d764e2d2044ee2ff245236cb63352f12ffd7d6a8150bb27a`
- `Experiments/iCloudSyncG1/Tools/test_profile_entitlements.py`：`b6928f632572c0bf71f93029d1f101e85d2e8b9f20c6544d36d4887a5a679449`
- `.github/workflows/synclab-offline.yml`：`8218c9287d3ce218f2040637eb0b9eb21bd813a0ffa99c426dd9b9b4a1c9465d`
