# 发布就绪

简体中文 | [English](../release-readiness.md)

ADP-OS 将 release readiness 视为显式 review 边界，而不是 task 完成后的隐式结果。Workspace report 是当前 release decision 的可信入口，因为它会合并 manifest、被忽略的本地 task state、已记录的 validation result、snapshot gate、review state 和 task governance metadata。

在接受、发布或提交 task bundle 前，先运行 report：

```powershell
.\cli\adp.ps1 workspace report -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
```

Report 是非破坏性的。它不会 clone project、启动 runtime、修改 sync session、创建快照、运行 validation command、stage 文件或 commit 文件。当同一份 release decision 需要粘贴到 pull request、release note 或维护者 handoff 时，可以添加 `-Markdown`。

上面的命令使用 `configs\workspace.recipes.example.json` 作为可复制示例。它里面的 task 有意作为示例存在，因此该示例输出 `release blocked` 或 `validation required` 本身不代表无关的仓库变更不能提交。真实 release decision 应针对描述当前 task bundle 的 workspace manifest 运行 report。

完整的 validation、evidence、safety check、commit 和 publication 流程见[发布流程](release-process.md)。

## 发布决策策略

`Release decision policy` 会把 task state 汇总成一个整体 release decision：

- `release candidate`：所有 task 都是 release candidate，sync hygiene 未阻塞，validation 已通过，review 已记录，snapshot gate 未阻塞，并且 task governance 字段已填写。
- `release blocked`：至少一个 task 被 sync hygiene、snapshot gate 或失败 validation 阻塞。
- `validation required`：至少一个 task 在 review 或 commit 前仍需要 validation。
- `review required`：validation 已通过，但至少一个 task 尚未 review。
- `governance incomplete`：执行状态已经接近 ready，但缺少 owner 或 review cadence metadata。
- `not ready`：report 还无法把 workspace 归类为可发布状态。

当 decision 是 `release blocked`、`validation required`、`review required` 或 `governance incomplete` 时，不应接受 release。

## 必要证据

一个 task 被视为 release-ready 前，report 应显示：

- `validation result`：最近一次相关 task 运行已通过。
- `sync hygiene`：`clean`、`covered`、`not requested`，或在 report 显示 `review ignore` 时已被显式 review。
- `review`：validation passed，并且源码 review 已在 ADP-OS 外部接受。
- `commit`：`commit ready` 或 `already marked committed`。
- `release readiness`：`release candidate`。
- `owner`：已设置负责人或 review role。
- `review cadence`：已设置预期 review rhythm。
- `snapshot required`：如果 task 需要 checkpoint，则 snapshot gate 已满足。

对于启用 sync 的 project，sync hygiene 是 release readiness 的一部分。当 report 显示 `review ignore` 时，不应把 task 视为可发布；应先检查检测到的生成目录和 runtime sync profile，再更新 manifest/profile 或记录外部 review decision。

对于高风险 agent task，snapshot readiness 是 release readiness 的一部分。当 snapshot gate 仍在阻塞时，不应把 broad、destructive 或 uncertain task 视为可发布。

Snapshot naming 也是 rollback clarity 的 review 内容。task 级 checkpoint 优先使用 `before-<task-name>`，更大的 release 或 migration checkpoint 使用 `milestone-<name>`。命名约定提示本身不阻塞 release，但在 task bundle 变得难以 review 或 restore 之前，应修正不清晰的 checkpoint 名称。

## 过期任务处理

`Stale-task remediation` 会列出需要关注的 task。维护者应把它当作处理队列：

- `create snapshot`：在 execution、review 或 commit 前创建 checkpoint，或用 `adp workspace task mark <task> checkpoint-waived` 记录显式本地 waiver。
- `review sync ignore`：发布前检查检测到的生成目录和 runtime sync profile。
- `validate now`：运行声明的 task validation，通常是 `adp workspace task validate <task> -Execute`。
- `review now`：检查源码 diff、已记录 validation、rollback path，并且只在接受后标记 reviewed。
- `rollback or revise`：失败 validation 会阻塞 release；修订 task 并重新 validation，或使用 rollback guidance。
- `ready to commit`：检查最终 diff，然后在目标 project 内 stage 和 commit。

该队列还会显示 owner、cadence 和 timing，让周期性 review 可以被分配，而不是临时发现。

## 维护者检查清单

发布或接受 task bundle 前使用这份 checklist：

1. 运行 `adp workspace dashboard` 扫描 project 和 lifecycle health。
2. 运行 `adp workspace report` 检查 release decision、governance loop、decision queues 和 stale-task remediation。
3. 当 PR 或 release evidence 需要复制到其他 review surface 时，运行 `adp workspace report -Markdown`。
4. 先处理所有 `release blocked` task，包括 `review sync ignore` task。
5. 对所有 `validation required` task 运行或重新运行 validation。
6. 对所有 `review required` task 完成 source review。
7. 在把 workspace 视为 governed 前，补齐缺失的 `owner` 和 `review_cadence` 字段。
8. 确认高风险 task 的 snapshot gate 已 ready，或已经用 `checkpoint-waived` 记录显式本地 waiver。
9. 只提交显示为 `ready to commit` 和 `release candidate`，并且 sync hygiene 已 review 的 task。
10. 保持 review、rollback 和 commit 都是显式的人类控制边界。

## 贡献者预期

贡献者应让 release readiness 容易验证：

- 当 task 需要明确负责人或 review role 时，添加 `tasks[].owner`。
- 当 task 进入周期性 review 时，添加 `tasks[].review_cadence`。
- 当 task 有时间敏感的 review window 时，添加 `tasks[].due`。
- 保持 `tasks[].validation` 足够具体，让 reviewer 可以复现结果。
- 对高风险工作使用 `tasks[].requires_snapshot` 和 `tasks[].snapshot`，snapshot 名称采用 `before-<task-name>` 或 `milestone-<name>`。

这些字段有意保持轻量。它们让 release 对话显式化，而不引入数据库、服务或隐藏自动化层。
