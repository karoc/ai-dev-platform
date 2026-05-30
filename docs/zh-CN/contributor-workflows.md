# 贡献者工作流

简体中文 | [English](../contributor-workflows.md)

本文把 workspace 和 release-readiness 模型转换成可重复的贡献流程。它面向希望变更易于 validation、review、rollback 和 release 的贡献者与维护者。Validation、evidence、safety check、commit 和 publication 流程见[发布流程](release-process.md)。

## 工作流模板

在 `adp-workspace.json` 或项目自己的 workspace manifest 中描述 task 时，使用最接近的模板。

### 文档或小型维护

```json
{
  "name": "docs-copy-edit",
  "project": "agent-workspace",
  "runtime": "agent",
  "risk": "low",
  "owner": "docs-reviewer",
  "review_cadence": "weekly",
  "due": "2099-12-31",
  "requires_snapshot": false,
  "validation": [
    "git diff --check",
    "git status --short"
  ]
}
```

预期流程：

1. 运行 `adp workspace task validate docs-copy-edit -Execute -Plan`。
2. 计划正确后，运行 `adp workspace task validate docs-copy-edit -Execute`。
3. 运行 `adp workspace task review docs-copy-edit`。
4. 只有 source review 被接受后，才标记 reviewed。
5. 只有 sync hygiene 已 review，并且 `workspace report` 显示 `ready to commit` 和 `release candidate` 时才 commit。

### 前端浏览器验收

```json
{
  "name": "frontend-browser-acceptance",
  "project": "frontend-app",
  "runtime": "frontend",
  "risk": "normal",
  "owner": "frontend-reviewer",
  "review_cadence": "per-change",
  "due": "2099-12-31",
  "requires_snapshot": false,
  "validation": [
    "pnpm install",
    "pnpm exec playwright test"
  ]
}
```

预期流程：

1. 使用 `adp workspace task validate frontend-browser-acceptance -Execute -Plan` 预览 validation。
2. 使用 `-Execute` 只执行已声明的 validation commands。
3. commit 前 review 已记录的浏览器 validation、source diff 和生成产物。
4. package install 和浏览器下载必须显式写在 validation command 中，不应隐藏在 ADP-OS 内部。

### 后端验证

```json
{
  "name": "backend-validation-pass",
  "project": "backend-api",
  "runtime": "backend",
  "risk": "normal",
  "owner": "backend-reviewer",
  "review_cadence": "per-change",
  "due": "2099-12-31",
  "requires_snapshot": false,
  "validation": [
    "uv sync",
    "uv run pytest",
    "uv run ruff check ."
  ]
}
```

预期流程：

1. 将 dependency sync、tests 和 lint 保持在 `tasks[].validation` 中。
2. 将失败 validation 视为 `rollback or revise`。
3. 在失败命令解决并重新运行 validation 之前，不要标记 reviewed。

### 大范围 Agent 重构

```json
{
  "name": "broad-agent-refactor",
  "project": "agent-workspace",
  "runtime": "agent",
  "risk": "high",
  "owner": "agent-reviewer",
  "review_cadence": "per-task",
  "due": "2099-12-31",
  "requires_snapshot": true,
  "snapshot": "before-broad-agent-refactor",
  "validation": [
    "git status --short",
    "git diff --check",
    "pnpm test"
  ]
}
```

预期流程：

1. 运行 `adp workspace task snapshot broad-agent-refactor`。
2. 在大范围 agent execution 前创建 checkpoint。task 级 checkpoint 使用 `before-<task-name>`，更大的 checkpoint 使用 `milestone-<name>`。
3. 保持 execution 手动且显式。
4. task 完成后运行 validation。
5. 标记 reviewed 前，review source diff、rollback path 和已记录 validation。
6. 只有 sync hygiene 已 review、snapshot gate ready、validation passed、review 已记录，并且 `workspace report` 显示 `release candidate` 时才 commit。

## 维护者评审流程

接受 contribution 前使用这套可重复流程：

1. 运行 `adp workspace dashboard` 做快速 health scan。
2. 运行 `adp workspace report` 检查 release decision、governance loop、decision queues 和 stale-task remediation。
3. 当 decision 需要复制到 pull request、release note 或 handoff 时，运行 `adp workspace report -Markdown`。
4. 按顺序处理 report：`release blocked`、`validation required`、`review required`、`governance incomplete`、`release candidate`。
5. 当 report 显示 governance gaps 时，要求贡献者补齐 owner、review cadence、due date、validation 或 snapshot metadata。
6. Review acceptance 或 commit 前，先处理所有 `review sync ignore` item。
7. 接受 review 前，要求已有记录的 passing validation result。
8. 对高风险 agent work，要求显式 snapshot gate，并检查 snapshot 名称是否表达 task 或 milestone rollback 意图。
9. rollback 和 commit 始终保持为维护者手动控制的边界。

## Pull Request 预期

Pull request 应包含：

- 使用的 task shape；如果没有适用 workspace task，则简要说明。
- `workspace report` 的 release decision；如果变更影响 workflow、runtime、validation、docs 或 release readiness，优先使用 `workspace report -Markdown`。
- 已运行的 validation commands，以及是否通过 `adp workspace task validate -Execute` 执行。
- Review 状态和未解决的 stale-task remediation items。
- Sync hygiene status，特别是任何 `review sync ignore` decision。
- 相关时，确认 README 和简体中文文档已同步更新。
- 确认没有包含 local state、VM artifacts、credentials、ISO files、downloaded tools 或 private maintainer files。

目标不是增加仪式感，而是让 agent-generated 和 human-generated changes 在成为 release candidates 前可审计。
