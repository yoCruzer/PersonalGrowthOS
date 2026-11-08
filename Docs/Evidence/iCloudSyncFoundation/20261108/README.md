# 2026-11-08 正式结构输入与隔离SDK准备

接续代码72f5d3d、上一文档交付668ca91；工作树codex/icloud-sync-foundation，Draft PR17。没有真实CloudKit操作、签名、安装、Apple能力变更或Production部署。

- `formal-schema-intake/`：Owner原件来源receipt摘要、实际严格审计摘要及root独立字典/摘要复核；两份CKDB及截图原件仅保存在仓库外本机私有目录，不在Git或CI artifact中。每份356B，同SHA60fec48392126eab598a05dbe0f7f9557494a992df8fb62295ccd3752a7768db，仅Users7fields。来源由Owner说明+截图绑定；文件不内嵌Team/容器/环境，不推导记录数量。正式App关联仍待补。
- `schema-audit/implementation/`：16项原创合成自测、修订失败摘要及源码hash；`schema-audit/review/`：发布路径红例摘要与私有保留链、修复后20项原创合成检查及可复用脚本。旧完整证据转存本机私有目录，未覆盖旧报告。
- `sdk-preparation/implementation/`：51项全包稳定点（24+10+17）和最终17项定向/iOS17核心编译；两处末尾绑定强化后记录在post-review。真实host仅离线检查且返回NOT_READY，SDK adapter仅编译。
- `sdk-preparation/review/`：最终11项独立原生异步反例，旧10项及前版两文件另存；所有transport均为注入的本机合成假实现。未实例化CKDatabase或实际验证网络/账号/服务器权限。

各套用例计数单列，不能将旧轮/重复执行叠加，也不能把注入transport或ad-hoc签名当作真实资格。候选缺3types/11业务fields；Users及其权限保持，候选custom权限仍NOT_SPECIFIED。P0/P1/P2未通过，不生成可导入DDL。当前实现与独立复核无剩余must-fix，远端最终结果将在固定源码后追加。

原件审计在本机完成。CI仅执行独立创作的合成schema用例，不将相同字段结构的摘要当作可还原原件的字节副本，也不把远端合成测试称为Owner原件远端复验。自动审批曾拒绝四份原件的上传，未执行提交/推送；采用本机保管原件、仅发布结构结论与测试代码的方式继续交付。
