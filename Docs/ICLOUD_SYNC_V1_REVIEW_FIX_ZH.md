# PR #15 独立 Review 补正记录

2026-11-05。Owner授权直接在原审计分支修订；不开发产品同步。原HEAD `e036b01e971de9a9f0538d9a5dedfefc099bfc65`，产品基线 `96f72339a1a3082c43018e06d6115dd93df1df97`。

| 发现 | 本轮处理 | 验证边界 |
| --- | --- | --- |
| R1 P1 历史活版本误满足依赖 | 新 `protocol_rules.py`：同对象完整因果图→当前head→递归依赖闭合；删除/冲突/缺失/环暂存，不回退旧活行 | 原四反例从4 FAIL变4 PASS；附加依赖补齐、当前head失效、依赖环、未知版本和排列检查 |
| R2 P1 “上次合法值”不收敛 | 投影为输入集合纯函数；唯一共同祖先仅作不完整预览；删除优先不复活；无唯一基线则待处理 | 排列/重复投递、双共同祖先、显式解决等14项新增检查；尚非真实领域统计 |
| R3 P2 测试名超出断言 | 收紧同业务键候选、固定account/epoch拒绝、旧mutation重放及精确mutation去重命名 | 不再声称已验证真实统计、账户重绑定、ZIP恢复或双设备同期完成 |
| R4 P2 历史兼容范围扩大 | 固定当前V16/v12支持起点；保留既有历史代码/原始报告，不扩加早期回归门禁 | 实际V16/v12升级仍在后续G2，不冒称本轮已测 |

原报告保存为 `ICLOUD_SYNC_V1_AUDIT_INITIAL_20261105_ZH.md`，沿用原blob `db8f663b3d8f038e3138f0fa3c4c9097e62a070c`。原Evidence目录内容不改写；新增证据置于 `Evidence/iCloudSyncV1/review-fix-20261105/`。

本次在隔离Linux/Python执行：原脚本16 PASS；原四反例4 FAIL（预期）；修订脚本16 PASS；同四反例4 PASS；新增投影/依赖14 PASS，合计修订后34 PASS。脚本SHA、命令及退出码见 results.json。源码来自上一轮审查附件，已用Git blob SHA与当前远端固定HEAD复核。无SwiftData原生重跑、真实CloudKit、签名、门户检查、Production或全量App测试。本次为修订者自测；G1仍须独立终审。

新增G1 Goal与Apple就绪门禁，将正式容器Production schema及合成数据往返放到大规模模块接入前；真正TestFlight验证仍独立。没有新建Apple资源、登录后台、修改正式entitlements或改变发布流程。

本轮所有提交限Docs，原产品/工程/测试/工作流通过沿用父Git tree保留。纯Docs提交可使用skip CI标记避免无关全量测试；将来发布候选必须另行核查，不得直接对本次skip提交打testflight tag。PR #15保持Draft和原base，不merge、不tag、不发布。
