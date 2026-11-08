# 2026-11-08 正式结构输入与隔离SDK准备

接续代码72f5d3d、上一文档交付668ca91；工作树codex/icloud-sync-foundation，Draft PR17。没有真实CloudKit操作、签名、安装、Apple能力变更或Production部署。

- `formal-schema-intake/`：Owner原件来源receipt摘要、实际严格审计摘要及root独立字典/摘要复核；两份CKDB及截图原件仅保存在仓库外本机私有目录，不在Git或CI artifact中。每份356B，同SHA60fec48392126eab598a05dbe0f7f9557494a992df8fb62295ccd3752a7768db，仅Users7fields。来源由Owner说明+截图绑定；文件不内嵌Team/容器/环境，不推导记录数量。正式App关联仍待补。
- `schema-audit/implementation/`：16项原创合成自测、修订失败摘要及源码hash；`schema-audit/review/`：发布路径红例摘要与私有保留链、修复后20项原创合成检查及可复用脚本。旧完整证据转存本机私有目录，未覆盖旧报告。
- `sdk-preparation/implementation/`：51项全包稳定点（24+10+17）和最终17项定向/iOS17核心编译；两处末尾绑定强化后记录在post-review。真实host仅离线检查且返回NOT_READY，SDK adapter仅编译。
- `sdk-preparation/review/`：最终11项独立原生异步反例，旧10项及前版两文件另存；所有transport均为注入的本机合成假实现。未实例化CKDatabase或实际验证网络/账号/服务器权限。

各套用例计数单列，不能将旧轮/重复执行叠加，也不能把注入transport或ad-hoc签名当作真实资格。候选缺3types/11业务fields；Users及其权限保持，候选custom权限仍NOT_SPECIFIED。P0/P1/P2未通过，不生成可导入DDL。当前实现与独立复核无剩余must-fix，固定源码远端验证结果见下。

原件审计在本机完成。CI仅执行独立创作的合成schema用例，不将相同字段结构的摘要当作可还原原件的字节副本，也不把远端合成测试称为Owner原件远端复验。自动审批曾拒绝四份原件的上传，未执行提交/推送；采用本机保管原件、仅发布结构结论与测试代码的方式继续交付。

固定代码d508ae4的[定向CI](ci-foundation-d508ae4/README.md)及独立产物复核已通过，原始ZIP摘要匹配。完整计数为51原生、11分块、22CLI、16schema自测、20schema独立及11SDK独立；源码与实际checkout精确绑定。

[产品CI42435822140](https://github.com/yoCruzer/PersonalGrowthOS/actions/runs/42435822140) SUCCESS：Release三个unsigned bundle检查通过，Unit599=598PASS/1SKIP/0FAIL，iPhone13mini/iOS27.2 Smoke5/5通过，两个测试lane的runtimeWarnings均为空。唯一Unit跳过需要隔离32MB HFS+低空间镜像；optional extended UI条件未执行。既有测试的Swift6异步上下文wait编译警告及AppIntents metadata警告如实保留，未称零编译警告。产品/测试/工程/产品CI与72f5d3d逐Git对象相同；此次由PR工作流自动触发，无手动重跑。旧G1 smoke失败不改写。 见[产品证据](ci-product-d508ae4/README.md)。最后仅文档/证据收口，不修改已验证源码。

后续Owner已确认正式App四项能力/关联，来源见`formal-app-association-owner.json`。新增[独立Mac签名前准备](formal-host-preparation/README.md)、[47df1f3定向CI](ci-foundation-47df1f3/README.md)与[同提交产品CI](ci-product-47df1f3/README.md)。新打包器本机28项、独立20项，远端28项及既有回归均通过；各轮不叠加。仅未配置开发签名产物，无CloudKit/实际开发签名资格。下一步集中配置授权仍待Owner回复。
