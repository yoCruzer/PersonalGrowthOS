# 重要日子 V1 独立审查

状态：待固定首个数据/规则 checkpoint。实现者自测不算独立审查。

计划视角：独立数据/规则（日期、历史Schema、升级/恢复、封面、引用、通知交错）；独立产品/集成（五Tab/Record/Today、Widget隐私/路由/打包/系统渲染）。审查者只读固定SHA，问题由实现者核实、反例修复并请求新SHA复审。

首轮测试证据见执行断点。最终结论尚未取得。

## R1：独立数据/规则审查

- Reviewer：实际独立 agent `/root/important_days_data_review`；只读，无实现修改。
- 固定 SHA：`cbd2075427c04642876b2d387d00b82c173a5e5f`，比较 `20d315a`。首提交漏工程注册，已由此追加提交修复，reviewer独立核验；没有把不可构建的1cfa标为审查终点。
- 结论：该阶段范围无 confirmed 新 P0/P1/P2；不是完整 V1 验收。
- 实际读取：共享日期、HKO2023/2024/2025样例、历史迁移链/四实体、v8字段/校验/发布回滚、Entry/Todo关系与相邻删除、独立封面服务、共享提醒/gate/pending。
- 证据：独立读取Integration1原始xcresult metrics，30测试/0失败/0跳过/0 warnings/errors；未重跑测试。旧alias SQLite日志另有说明，不将metrics零warning泛化为日志无任何诊断。
- 边界：提交前工作树证据，需最终精确SHA回归。全部旧包版本、新封面真实低空间/取消、真实系统daily/weekly交错、恢复后实际排期/递送未被30项全面证明。Widget/路由/双语/UI在本轮审查之外。
- Reviewer提醒：保存前还缺offset后的实际提醒日期预览，已在正在开发的UI中补入，待最终审查验证。

后续：B收敛后进行独立产品/集成审查，并对后续数据/提醒差异请求R1复审。
