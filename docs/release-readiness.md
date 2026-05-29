# Release Readiness

[简体中文](zh-CN/release-readiness.md) | English

ADP-OS treats release readiness as an explicit review boundary, not an implicit side effect of a task finishing. The workspace report is the source of truth for the current release decision because it combines the manifest, ignored local task state, recorded validation results, snapshot gates, review state, and task governance metadata.

Use the report before accepting, publishing, or committing a task bundle:

```powershell
.\cli\adp.ps1 workspace report -ManifestPath configs\workspace.recipes.example.json
.\cli\adp.ps1 workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
```

The report is non-destructive. It does not clone projects, start runtimes, change sync sessions, create snapshots, run validation commands, stage files, or commit files. Add `-Markdown` when the same release decision needs to be pasted into a pull request, release note, or maintainer handoff.

The commands above use `configs\workspace.recipes.example.json` as a copyable example. Its tasks are intentionally illustrative, so a `release blocked` or `validation required` result from that example does not by itself block an unrelated repository change. For real release decisions, run the report against the workspace manifest that describes the actual task bundle being reviewed.

See [Release Process](release-process.md) for the full validation, evidence, safety-check, commit, and publication flow.

## Release Decision Policy

The `Release decision policy` section turns task state into a single release decision:

- `release candidate`: every task is a release candidate, validation has passed, review is recorded, snapshot gates are not blocking, and task governance fields are present.
- `release blocked`: at least one task is blocked by a snapshot gate or failed validation.
- `validation required`: at least one task still needs validation before review or commit.
- `review required`: validation passed, but at least one task has not been reviewed.
- `governance incomplete`: task execution state is otherwise ready, but owner or review cadence metadata is missing.
- `not ready`: the report cannot classify the workspace as releasable yet.

A release should not be accepted while the decision is `release blocked`, `validation required`, `review required`, or `governance incomplete`.

## Required Evidence

Before a task can be treated as release-ready, the report should show:

- `validation result`: passed for the latest relevant task run.
- `review`: validation passed, with source review accepted outside ADP-OS.
- `commit`: `commit ready` or `already marked committed`.
- `release readiness`: `release candidate`.
- `owner`: set to the responsible person or review role.
- `review cadence`: set to the expected review rhythm.
- `snapshot required`: satisfied when the task requires a checkpoint.

For high-risk agent tasks, snapshot readiness is part of release readiness. Do not treat a broad, destructive, or uncertain task as releasable while the snapshot gate is blocking.

## Stale-Task Remediation

The `Stale-task remediation` section lists tasks that need attention. Use it as the maintainer queue:

- `create snapshot`: create or explicitly waive the checkpoint before execution, review, or commit.
- `validate now`: run the declared task validation, usually with `adp workspace task validate <task> -Execute`.
- `review now`: inspect source diff, recorded validation, rollback path, and mark the task reviewed only when accepted.
- `rollback or revise`: failed validation blocks release; revise the task and rerun validation, or use rollback guidance.
- `ready to commit`: inspect final diff, then stage and commit inside the target project.

The queue also shows owner, cadence, and timing so recurring review can be assigned rather than discovered ad hoc.

## Maintainer Checklist

Use this checklist before publishing or accepting a task bundle:

1. Run `adp workspace dashboard` to scan project and lifecycle health.
2. Run `adp workspace report` to inspect release decision, governance loop, decision queues, and stale-task remediation.
3. Run `adp workspace report -Markdown` when PR or release evidence should be copied into another review surface.
4. Resolve every `release blocked` task first.
5. Run or rerun validation for every `validation required` task.
6. Complete source review for every `review required` task.
7. Fill missing `owner` and `review_cadence` fields before treating the workspace as governed.
8. Confirm high-risk tasks have a ready snapshot gate or an explicit external waiver.
9. Commit only tasks shown as `ready to commit` and `release candidate`.
10. Keep review, rollback, and commit as explicit human-controlled boundaries.

## Contributor Expectations

Contributors should make release readiness easy to verify:

- Add `tasks[].owner` when a task needs a specific owner or review role.
- Add `tasks[].review_cadence` when a task participates in recurring review.
- Add `tasks[].due` when a task has a time-sensitive review window.
- Keep `tasks[].validation` specific enough that a reviewer can reproduce the result.
- Use `tasks[].requires_snapshot` and `tasks[].snapshot` for high-risk work.

These fields are lightweight by design. They make the release conversation explicit without adding a database, service, or hidden automation layer.
