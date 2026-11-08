# 修复后的固定 Development 验证窗口

状态：代码、签名产物、本机与haha四阶段只读资格、独立审查及定向CI均已通过；以下是一个新的具体云操作范围，尚未获批、尚未执行。旧单次失败授权不复用。

- 源码：`a72befa6c46516ede572e9d561c735c07d8cf5fc`，PR18；定向CI42482033378 SUCCESS，原ZIP/merge checkout/50源指纹已核验。
- 同一已在haha验证的签名二进制：`3afb421d0b92c34d1090d4afeccf71e58fef7c4c5cc3352258ab99eb1c9afe7f`。haha异步4/4 PASS，约0.93秒，云/Keychain调用0；不重新签名或换产物。
- 新run：`3254C900-8C8D-4AD4-95B7-10CB3C36F6DE`；新dataset：`3314BECE-01A8-4692-89F7-B858EF5FD32E`。
- 新plan SHA256：`2d74da8e35536be1e719899dd10ad2ab0a39560cd824444cf86587e13768121f`；同一候选schema。该计划6项离线SDK回放PASS，不能代替真实云结果。

## 授权后仅做这些操作

在保持预期测试iCloud不变的haha会话中，使用既有guard/Keychain anchor，执行一次`run-approved`：正式容器Development中新建合成zone，写入3条asset/chunk与3条mutation并精确读回全部6条。最多12次账户API＋5次数据调用，可能新增3类型/11字段。只访问明确的合成zone/记录；不查日常业务，不删除，不操作Production或发布。

已完成的旧run收口不再执行；不重新enrollment、不重置或删除anchor/ledger，不复用历史run/dataset/plan。新运行仍按既有单次持久消费和身份/并发保护执行，任何失败即停，无自动重试。

运行成功或失败后，仅调用一次同一新run的只读证据导出。云窗口最多15分钟，随后导出最多30秒；正常预计2–5分钟。手机前台/数据线占用均0。云成功但证据导出失败仍以非零返回，不能当完整验收通过，不能据此重跑云。

交付目录`/private/tmp/PGOS-RuntimeFixedWindow-20261108`。授权前`ownerApproved=false`，脚本拒绝执行。获批后只需在haha终端启动一次`/usr/bin/python3 /private/tmp/PGOS-RuntimeFixedWindow-20261108/run-reviewed-window.py`，回复打印的证据目录；不重复旧命令。

## 验收与边界

必须核对实际账户/数据调用、六条读回字节、回调与ledger/输出一致性及原始错误；CI或只读资格PASS不能代替云成功。成功后才需要Owner导出更新的Development schema，以核验实际类型/字段；该结构依赖本次真实写入，因此不能提前合并完成。Production仍保持未部署/未写入，P0需证据审计后判断。

运行时资格已按[修复说明](ICLOUD_SYNC_RUNTIME_REPAIR_ZH.md)改为OS验证受限entitlements，保留固定嵌入profile真实性/绑定；不再声称运行时独立核对当前UDID属于精确profile。旧失败、CK_2非阻塞例外和G1已接受手机范围保留。
