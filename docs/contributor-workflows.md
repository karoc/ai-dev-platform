# Contributor Workflows

[简体中文](zh-CN/contributor-workflows.md) | English

This guide turns the workspace and release-readiness model into repeatable contribution flows. It is written for contributors and maintainers who want changes to be easy to validate, review, roll back, and release. See [Release Process](release-process.md) for the validation, evidence, safety-check, commit, and publication flow.

## Workflow Templates

Use the closest template when describing a task in `adp-workspace.json` or a project-specific workspace manifest.

### Documentation or Small Maintenance

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

Expected flow:

1. Run `adp workspace task validate docs-copy-edit -Execute -Plan`.
2. Run `adp workspace task validate docs-copy-edit -Execute` when the plan is correct.
3. Run `adp workspace task review docs-copy-edit`.
4. Mark reviewed only after source review is accepted.
5. Commit only when `workspace report` shows `ready to commit` and `release candidate`.

### Frontend Browser Acceptance

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

Expected flow:

1. Preview validation with `adp workspace task validate frontend-browser-acceptance -Execute -Plan`.
2. Execute only the declared validation commands with `-Execute`.
3. Review recorded browser validation, source diff, and generated artifacts before commit.
4. Keep package installs and browser downloads explicit in the validation command, not hidden in ADP-OS.

### Backend Validation

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

Expected flow:

1. Keep dependency sync, tests, and lint in `tasks[].validation`.
2. Treat failed validation as `rollback or revise`.
3. Do not mark reviewed until the failed command is resolved and validation is rerun.

### Broad Agent Refactor

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

Expected flow:

1. Run `adp workspace task snapshot broad-agent-refactor`.
2. Create the checkpoint before broad agent execution.
3. Keep execution manual and explicit.
4. Run validation after the task.
5. Review source diff, rollback path, and recorded validation before marking reviewed.
6. Commit only when the snapshot gate is ready, validation passed, review is recorded, and `workspace report` shows `release candidate`.

## Maintainer Review Ritual

Use this repeatable ritual before accepting a contribution:

1. Run `adp workspace dashboard` for the fast health scan.
2. Run `adp workspace report` for release decision, governance loop, decision queues, and stale-task remediation.
3. Run `adp workspace report -Markdown` when the decision needs to be copied into a pull request, release note, or handoff.
4. Resolve the report in this order: `release blocked`, `validation required`, `review required`, `governance incomplete`, `release candidate`.
5. Ask the contributor to fill missing owner, review cadence, due date, validation, or snapshot metadata when the report shows governance gaps.
6. Require a recorded passing validation result before review acceptance.
7. Require an explicit snapshot gate for high-risk agent work.
8. Keep rollback and commit as manual maintainer-controlled boundaries.

## Pull Request Expectations

Pull requests should include:

- The task shape used, or a short explanation if no workspace task applies.
- The `workspace report` release decision, preferably from `workspace report -Markdown` when the change affects workflows, runtimes, validation, docs, or release readiness.
- Validation commands run and whether they were executed through `adp workspace task validate -Execute`.
- Review status and any unresolved stale-task remediation items.
- Confirmation that README and Simplified Chinese docs were updated together when relevant.
- Confirmation that no local state, VM artifacts, credentials, ISO files, downloaded tools, or private maintainer files are included.

The goal is not to add ceremony. The goal is to make agent-generated and human-generated changes auditable before they become release candidates.
