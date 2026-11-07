# SyncLab：剩余 Development 集中验证窗口

2026-11-07。仅独立 SyncLab、合成数据、Development。工程准备不等于真实场景通过；完整 G1 和 Production 门禁保持未通过。

## 已准备的入口

`LabReplay prepare-faults NEW_DIRECTORY synthetic-g1-UNUSED probe-NEW_RUN` 离线生成27阶段：此前3份异常依赖/新图片计划，加24份故障计划；手机8份打包为 `SyncLab-Probe-Batch.json`。三类 dataset 分开：主故障、`-deps`、`-restore`，均必须从未用于真实运行。计划ID绑定dataset/run/stage，旧请求、结果和故障标记不可覆盖；中断命令不重放，使用专门恢复计划。

新增能力全部仅Debug并受显式测试授权约束：

- 已核验账户的不可变A/B缓存槽；离线打开时明确 `cachedPartitionNotCurrentAccount`，不能代表当前系统账户。真实连接必须再核验绑定，失败不能把A快照标为B。
- 本地事务提交前/后 `_exit(73/74)`；真实SDK非空内容落盘后退出75、其后首次state落盘后退出76；CKAsset已交给SDK且尚未ACK的窗口退出77。state内容保持不透明，不推测其中token语义。
- 固定旧批次交给SDK后创建后继修改，真实旧ACK前后留证；ACK抢先到达则该场景失败，不能假造成功窗口。不能由此额外声称网络字节已经发送。
- 故障观测绑定原请求摘要、计划、dataset/run、账户分区、进程nonce/PID和来源。实际SDK回调与本地callback seam区分。恢复要求nonce变化，不能用同进程重建对象冒充。
- 缺图/截断观测保留事实、缺图hash与已验证原图，`snapshotComplete=false`，允许继续恢复同步；完整备份导出仍严格拒绝缺图。非预期权限、损坏、限额等错误不吞掉。
- 只对两张固定PNG做缺失/截断实验，原件和坏件保留；小快照恢复目标保持发布门关闭，旧接收器被epoch围栏，不代表v12 ZIP恢复验收。

## 一次启动与收集

`prepare_fault_window.py` 只打包已严格验签的Mac App和固定计划；不启动、登录、联网测试或改变系统设置。`Start-Fault-Window.command` 必须由Owner在haha用户启动。监听器最多两小时，仅处理准备清单中的Mac阶段；原用户投递 `requested-stage.json`，内容为固定stage名称。它不接受任意Shell、路径、容器或账户。

Mac启动器使用固定沙箱Documents文件和显式启动参数；签名App完成计划后退出。计划退出和恢复由启动器协调，不要求Owner逐次重开。`open -W`不暴露App退出码，因此设备证据依赖新鲜私有claim、对应故障标记和后续新进程nonce；不把启动器exit0称为App预期退出码。已存在私有claim/报告拒绝重放。所有文件读取有大小、普通文件及不跟随符号链接门禁；包的可读权限和结果继承ACL显式设置，兼容umask077。

手机先导入一个批次文件，点击“载入已导入的测试批次”。选择不执行；每一步仍由Owner显式点击启动。读取批次不授予云访问权限。执行阶段按下面顺序，阶段间可以正常使用手机；运行中的短步骤保持SyncLab前台。

| 手机选择项 | 配合动作 | 前置Mac阶段 |
| --- | --- | --- |
| 00-phone-dependency-repair | 点击启动 | Mac已种入异常依赖并核对 |
| 01-phone-seed | 点击启动 | 上一批Mac取回已核对 |
| 05-phone-next-content | 点击启动 | Mac内容退出/恢复已核对 |
| 15-phone-receive | 点击启动 | Mac state/事务/旧ACK/lease恢复已核对 |
| 16-phone-offline | 在设置关闭WLAN及蜂窝数据后点击；不要只用控制中心暂断Wi-Fi | 上一步完成；A缓存已经建立 |
| 17-phone-reconnect | 恢复网络后点击 | 离线保存/本地重开已完成 |
| 19-phone-restore-seed | 点击启动 | Mac已取回离线记录 |
| 24-phone-account-receive | 点击启动 | haha中A→B→A及待发恢复已完成 |

只在haha切换测试iCloud账户，登录、密码、验证码由Owner在Apple界面处理；手机日常账户不退出。B阶段显式同步并核对空云内容，不能用本地空库冒充B云无泄漏。A返回先核对离线待发事实再联网，最后手机实际取回。若B凭据不可用，其他独立阶段可完成，但账户门禁仍NOT_RUN。

初次安装/导入预计数据线占用3–5分钟，最终取回报告约2–5分钟；中间可拔线。集中验证预计30–45分钟，账户登录/验证码可能额外10–20分钟。时间是安排估计，不是保证；SDK时序抢跑、网络或账户问题会保留失败并重新安排必要场景，不无限占用手机。

## 验证与证据

将设备原始报告放入对应私有 `results/STAGE/report.json`，故意退出为 `boundary.json`。`verify_fault_window.py PLANS RESULTS` 按原始命令摘要、固定mutation逐字段真值、图片字节/hash、完整事实集合、投影、旧ACK、账户和进程身份核对。全部命令PASS也不能替代该校验。物理断网由Owner动作记录单独佐证，不从离线代码入口推断无线网络实际关闭。

公开副本必须递归删除 `accountFingerprint` 和 `sourceAccountHash`；私有原件不改写。保留原失败、测试注入来源与未运行项。本地原生/子进程/工具通过只证明工程入口，不替代真实CloudKit运行、真实账户变化或Production证据。

Development全部实证通过后，再准备正式容器的具体Production差异和Owner步骤。未获新授权不得部署/写Production、merge、Archive、TestFlight或扩大正式业务接入。
