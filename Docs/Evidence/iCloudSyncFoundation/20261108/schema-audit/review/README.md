# Schema审计：原创合成输入独立复核

2026-11-08，审查者 `/root/readiness`。本目录仅包含独立创作的合成测试和执行结果，不含Owner导出、截图、完整解析副本或默认Users结构的复制品。Owner原件审计只在本机完成，不能把这里的结果称为远端原件复验。

## 隐私修订与证据连续性

此前独立测试把收到的默认结构复制为基准。自动审批拒绝原件上传后，完整旧review目录、原始失败、旧20项结果及逐文件hash清单均转存仓库外私有目录，未删除、改写或上传。此处重新编写基准：`ReviewFixture`类型、三个虚构普通字段及`ReviewObservers`/`ReviewEditors`角色，与Owner导出不同；不是给原件换格式、改空白或加字段。具体修订绑定见`privacy-revision.json`。

旧发布路径红例保留在私有证据中，其代码摘要及问题结论可公开：输出父目录在fsync期间被替换时，初稿曾返回成功但请求路径没有报告。实现修复后重新解析并核对parent/leaf身份；本轮仍用确定性替换验证拒绝，并保留旧fd中的失败输出。没有覆盖旧证据，也不宣称防任意恶意ABA。

## 最终执行

**20项检查通过：19次CLI调用和1个发布API反例。** `summary.json`、`synthetic-review.log`和`cases/`保留本次实际结果；不与旧20项或实现者16项相加。

覆盖原创结构相同、候选缺3types/11fields、输出防覆盖、错误hash、未知类型/系统字段/权限/index语法、重复type/field/grant、第二schema块、尾随内容及注释拒绝；合法extra type/字段、类型冲突与权限变化完整保留。单独的`SystemTypeProbe`用于一个标准系统字段错误类型的报告检查，不复制任何Owner记录定义。修改候选、symlink及发布目录替换均拒绝。所有报告为`REVIEW_ONLY_NOT_DEPLOYABLE`，零网络，P0/P1/P2 false。

```sh
python3 review_schema.py /absolute/path/to/Scripts/SyncSchemaAudit/audit.py /absolute/path/to/schema.json /private/tmp/NEW_SYNTHETIC_REVIEW_OUTPUT
```

脚本自包含且输出根必须不存在，可供CI运行。审计实现仍为SHA256 `d175b24b2380c2dc3d41e24f734cf0523e96975d6348b4168891fcda4e9a7123`；候选schema固定为`6fcf5478c3307685f8a45154b44eeeaec6a907c33412a2c388a6cb8831f04003`。本次未修改SDK或重跑SDK测试。当前范围无剩余must-fix。
