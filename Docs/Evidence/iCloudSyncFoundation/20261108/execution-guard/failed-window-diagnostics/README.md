# 首次窗口失败与诊断修复

Owner 实际执行 `107963d`：enrollment exit0、run exit74。原始批准输入、签名包、sandbox 导出与 ledger 仅存本机私有目录；公开结果见 `owner-window-result.json`。没有重试、重新 enrollment、删除、Production 或手机操作。

只读 `export-run` 已由同一探针身份签名，并在 haha 成功读取15份固定批次文件。文件摘要、事件关联与顺序复核通过；未访问 Keychain，不声称验证 ledger HMAC。两个回调分别为首次 account-status 的 enqueue请求与取消，均 started=false。结合107963d的bridge/AccountSession控制流，显式账户API及transport/data调用均为0；CKContainer已构造，不能泛称未涉及系统服务。enqueue至fatal记录5066ms，缺少原始错误码，不能据此推断system_profiler或CK_2根因。

修复包括：

- 固定本应用run/ledger的只读导出，不接受任意路径，不写锁或修复状态；原始字节只能用于私人诊断。
- fd相对读取、所有者/单链接/类型/大小/路径绑定校验。独立硬链接负例先失败，再修复；原红绿日志保留。
- enqueue前门禁失败的原始类型与受限错误码在取消前保留。包装调用次数与enqueue admission分别计数，不把它们冒充实际SDK调用。
- 所有失败仍保持REMOTE_OUTCOME_UNKNOWN；marker写失败或矛盾回调不能靠首因改成“已知无远端影响”。门禁拒绝、marker碰撞、started矛盾、已调用后证据写失败均有配对验证。

初始完整回归163项（24协议+17准备+122SDK）、独立边界35项、打包38项、iOS17 SDK编译通过。随后独立审查要求收紧失败分类，最终完整回归164项（24+17+123）、定向6项及最终产物38项通过，源码见source-hashes-final.json；原始中间验证保留，不混用版本。真实iOS运行、完整产品同步及P0/P1/P2均未通过本次诊断验证；旧107963d CI不覆盖新代码。

当前唯一诊断人工输入是haha终端的有界离线资格检查结果；最多4次、首次失败即停，不读取Keychain或调用CloudKit。新云窗口必须另按具体产物/范围确认，不能扩大旧单次授权。
