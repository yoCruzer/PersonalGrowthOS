# GitHub 分支初始清点与安全清理规则（2026-10-20）

## 0. 边界

这是一次**名称级初始快照**；29个远端分支来自当时的GitHub搜索，**没有逐条验证 SHA、合并状态、独有提交与 PR 依赖，不能据此删除任意分支**。默认分支 main，PR #8～#13 当前均开放并存在多层叠加依赖。实时状态须由Codex重新fetch验证，逐条生成完整 SHA 和分类。此文档不授权删分支。

## 1. 初始分支名称（29）
1. `codex/external-capture-v1`
2. `codex/important-days-v1`
3. `codex/quiet-wins-on-d72`
4. `codex/sleep-routine-v1`
5. `codex/time-investment-v1`
6. `codex/todo-v1-personal-actions`
7. `codex/usage-remediation-20261017`
8. `docs/foundation-consistency-v0.2`
9. `docs/v1-autonomous-governance`
10. `feat/s0a-project-bootstrap`
11. `feat/v1-autonomous-build`
12. `feature/build8-habit-analytics-dashboard`
13. `feature/build9-today-entry-followups`
14. `feature/usability-s2-review-loop`
15. `feature/v1-completion-push`
16. `fix/build6-owner-feedback-round1`
17. `fix/build7-owner-feedback-round2`
18. `fix/v1-device-smoke-round1`
19. `main`
20. `plan/important-days-v1-goal`
21. `plan/important-days-v1-review-fix-goal`
22. `plan/s0-execution-foundation`
23. `plan/s0a-task-definition`
24. `plan/sleep-routine-v1-goal`
25. `plan/sleep-routine-v1-review-fix`
26. `plan/time-investment-v1-goal`
27. `plan/usage-remediation-20261017-goal`
28. `plan/v1-implementation-foundation`
29. `test/v1-device-validation-round1`

## 2. 首次预分类（仅名称线索，不是安全删除清单）

- **KEEP_ACTIVE / STACK_BASE 优先核实**：`main`，`codex/external-capture-v1`、`codex/todo-v1-personal-actions`、`codex/quiet-wins-on-d72`、`codex/important-days-v1`、`codex/sleep-routine-v1`、`codex/time-investment-v1`、`codex/usage-remediation-20261017`。PR#8–13的真实base/head顺序由GitHub API核实，不能按此文字猜测。
- **REVIEW_AFTER_MERGE**：`plan/*`、`docs/*`、`feature/*`、`fix/*`、`feat/*`、`test/*` 等，只有在证明内容由 main 或受保护保留提交/签发归档完整覆盖，且不是任何开放/关联PR基点，才可能成为安全候选。
- **UNKNOWN**：元数据、差异、引用关系未取到的任何分支；一律先保留。

## 3. 逐分支必须补录

| branch | head完整SHA | 最后提交时间 | PR(open/closed/merged)/base关系 | 是否祖先/独有提交 | 重要tag/发布/Docs引用 | 分类 | 证据与拟议动作 |
|---|---|---|---|---|---|---|---|
| `main` | TO_VERIFY | TO_VERIFY | 默认分支 | TO_VERIFY | TO_VERIFY | KEEP_ACTIVE | 永不因本任务删除 |

命令建议：`git fetch --prune --tags`（仅更新本地远端引用，不是GitHub远端删除）、`git ls-remote --heads origin`、`gh pr list --state all --json number,state,isDraft,baseRefName,headRefName,mergeCommit`、`git merge-base --is-ancestor`、`git log --cherry`、`git branch -r --merged`。一个命令不能代替综合证据。尤其要防止“PR已合并到未合入main的祖先分支”被错误认定为可删。

## 4. 删除安全门

前提：系统真机验收完成或Owner另行明确授权提前处理；叠加PR的合并计划已经得到Owner批准；候选代码/Docs/Tag/备份仍有可恢复引用。每条候选必须列branch+当时完整SHA+为什么不被开放PR依赖+删除后的恢复办法。Owner对具体批次列表确认前：**无远端删除、无force push、无自动merge，也不执行`git push origin --delete`**。

获批后一次少量执行，删除前再次fetch验证完整SHA和依赖未变化；完成后重新核对所有保留PR的head/base与CI/历史Tag可达，记录前后对比。遇到不确定立即停止该分支，仅处理确定项。
