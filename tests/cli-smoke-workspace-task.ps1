Assert-Command `
    -Name "workspace task prepare" `
    -Arguments @("workspace", "task", "prepare", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task prepare: before-large-agent-task", "Task lifecycle output is plan-only", "Preparation checklist:", "adpos workspace task snapshot before-large-agent-task")

Assert-Command `
    -Name "workspace task snapshot" `
    -Arguments @("workspace", "task", "snapshot", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task snapshot: before-large-agent-task", "Risk:\s+high", "Snapshot required:\s+True", "Snapshot naming: aligned - matches task checkpoint convention: before-large-agent-task", "Checkpoint:", "snapshot naming \(aligned: matches task checkpoint convention: before-large-agent-task\)", "snapshot-first gate", "adpos snapshot create agent before-large-agent-task")

Assert-Command `
    -Name "workspace task run" `
    -Arguments @("workspace", "task", "run", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task run: before-large-agent-task", "Execution boundary:", "Manual execution only: this command does not start an agent", "Snapshot-first gate before broad agent work", "Do not start broad agent work until this gate is ready", "adpos workspace task mark before-large-agent-task checkpointed", "ssh adp-os-adp-agent", "Run the agent or task command manually", "adpos workspace task mark before-large-agent-task running")

Assert-Command `
    -Name "workspace task validate" `
    -Arguments @("workspace", "task", "validate", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task validate: before-large-agent-task", "Validation plan:", "git status --short", "pnpm test")

Assert-Command `
    -Name "workspace task validate frontend browser recipe" `
    -Arguments @("workspace", "task", "validate", "frontend-browser-acceptance", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task validate: frontend-browser-acceptance", "Validation plan:", "pnpm install", "pnpm exec playwright test", "To execute validation explicitly", "-Execute -ManifestPath")

Assert-Command `
    -Name "workspace task validate execute plan frontend browser recipe" `
    -Arguments @("workspace", "task", "validate", "frontend-browser-acceptance", "-Execute", "-Plan", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task validate: frontend-browser-acceptance", "Explicit execution mode", "Validation execution:", "Readiness gate:", "project \(frontend-app: /home/adp/workspace/frontend-app\)", "runtime frontend", "sync", "snapshot-first gate", "ssh target \(adp@192\.168\.242\.131:22\)", "Plan only: validation commands will not be executed", "ssh -i .*adp@192\.168\.242\.131", "pnpm exec playwright test")

Assert-Command `
    -Name "workspace task run broad agent recipe" `
    -Arguments @("workspace", "task", "run", "broad-agent-refactor", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task run: broad-agent-refactor", "Manual execution only: this command does not start an agent", "Snapshot-first gate before broad agent work", "BLOCKED: create checkpoint first", "Do not start broad agent work until this gate is ready", "adpos snapshot create agent before-broad-agent-refactor")

Assert-Command `
    -Name "workspace task review" `
    -Arguments @("workspace", "task", "review", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task review: before-large-agent-task", "Human review bundle:", "Review decision gate:", "review verdict", "Confirm sync hygiene before review", "sync hygiene \(not checked: project path missing\)", "snapshot-first gate is ready", "rollback: adpos workspace task rollback before-large-agent-task", "accept:   withheld until review decision gate is OK", "resolve:  create or explicitly waive the checkpoint", "Commit readiness requires sync hygiene, recorded validation")

Assert-Command `
    -Name "workspace task rollback" `
    -Arguments @("workspace", "task", "rollback", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task rollback: before-large-agent-task", "Rollback boundary:", "Decision context:", "recorded validation: not recorded", "Snapshot rollback is not ready", "Resolve the checkpoint gate before using VM snapshot rollback", "git restore <paths>", "adpos workspace task mark before-large-agent-task rollback")

Assert-Command `
    -Name "workspace task commit" `
    -Arguments @("workspace", "task", "commit", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task commit: before-large-agent-task", "Commit boundary:", "Commit commands withheld until commit readiness is OK", "Resolve gate first: create or explicitly waive the checkpoint before commit")

$workspaceState = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-workspace-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
$workspaceBoundaryState = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-workspace-boundary-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
$workspaceExtValidationState = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-workspace-ext-validation-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
try {
    Assert-Command `
        -Name "workspace task mark" `
        -Arguments @("workspace", "task", "mark", "before-large-agent-task", "prepared", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceState) `
        -ExitCode 0 `
        -Patterns @("Workspace task mark: before-large-agent-task", "Recorded local lifecycle state only", "State:\s+prepared", "Boundary: this state does not prove execution, validation, review acceptance, rollback readiness, or commit readiness")

    Assert-Command `
        -Name "workspace task mark running boundary" `
        -Arguments @("workspace", "task", "mark", "before-large-agent-task", "running", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceBoundaryState) `
        -ExitCode 0 `
        -Patterns @("Workspace task mark: before-large-agent-task", "State:\s+running", "Boundary: running means manual execution began or was attempted; ADP-OS did not start the agent, approve execution, validate output, or satisfy review/commit readiness")

    Assert-Command `
        -Name "workspace task mark reviewed boundary" `
        -Arguments @("workspace", "task", "mark", "before-large-agent-task", "reviewed", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceBoundaryState) `
        -ExitCode 0 `
        -Patterns @("Workspace task mark: before-large-agent-task", "State:\s+reviewed", "Boundary: reviewed should be used only after human source review accepts the diff, rollback path, snapshot context, and recorded validation evidence")

    Assert-Command `
        -Name "workspace task mark rollback boundary" `
        -Arguments @("workspace", "task", "mark", "before-large-agent-task", "rollback", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceBoundaryState) `
        -ExitCode 0 `
        -Patterns @("Workspace task mark: before-large-agent-task", "State:\s+rollback", "Boundary: rollback is a local lifecycle note only; ADP-OS did not restore snapshots or modify source files")

    Assert-Command `
        -Name "workspace task mark checkpoint waived boundary" `
        -Arguments @("workspace", "task", "mark", "before-large-agent-task", "checkpoint-waived", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceBoundaryState) `
        -ExitCode 0 `
        -Patterns @("Workspace task mark: before-large-agent-task", "State:\s+checkpoint-waived", "checkpoint-waived records explicit human acceptance of missing VM snapshot protection", "does not create a snapshot, prove rollback safety, or restore rollback capability")

    Assert-Command `
        -Name "workspace task mark validated records external validation" `
        -Arguments @("workspace", "task", "mark", "before-large-agent-task", "validated", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceExtValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task mark: before-large-agent-task", "State:\s+validated", "Recorded external validation result", "validated records an external validation result")

    Assert-Command `
        -Name "workspace task mark validation_failed records external failure" `
        -Arguments @("workspace", "task", "mark", "before-large-agent-task", "validation_failed", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceExtValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task mark: before-large-agent-task", "State:\s+validation_failed", "Recorded external validation result", "validation_failed records an external validation result")

    Assert-Command `
        -Name "workspace status with checkpoint waiver" `
        -Arguments @("workspace", "status", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceBoundaryState) `
        -ExitCode 0 `
        -Patterns @("Workspace readiness: example-project", "local state", "snapshot-first gate \(waived: checkpoint explicitly waived in local state; no VM snapshot was confirmed")

    Assert-Command `
        -Name "workspace dashboard with checkpoint waiver" `
        -Arguments @("workspace", "dashboard", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceBoundaryState) `
        -ExitCode 0 `
        -Patterns @("Workspace dashboard: example-project", "state: checkpoint-waived at", "checkpoint: waived", "execution: gated", "commit: validation result missing")

    Assert-Command `
        -Name "workspace report with checkpoint waiver" `
        -Arguments @("workspace", "report", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceBoundaryState) `
        -ExitCode 0 `
        -Patterns @("Workspace report: example-project", "release gate: needs validation", "decision: validation required", "state: checkpoint-waived", "snapshot required: True", "snapshot gate: waived - checkpoint explicitly waived in local state; no VM snapshot was confirmed", "action: validate now", "release readiness: validation required", "rollback: waived", "review: validation result missing", "commit: validation result missing")

    Assert-Command `
        -Name "workspace task commit with checkpoint waiver" `
        -Arguments @("workspace", "task", "commit", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceBoundaryState) `
        -ExitCode 0 `
        -Patterns @("Workspace task commit: before-large-agent-task", "Commit readiness gate:", "commit readiness \(validation result missing", "Commit commands withheld until commit readiness is OK", "Resolve gate first: run adpos workspace task validate before-large-agent-task -Execute before commit")

    Assert-Command `
        -Name "workspace task rollback with checkpoint waiver" `
        -Arguments @("workspace", "task", "rollback", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceBoundaryState) `
        -ExitCode 0 `
        -Patterns @("Workspace task rollback: before-large-agent-task", "Snapshot rollback is waived", "No VM restore command is printed because no checkpoint was confirmed", "git restore <paths>")

    if (-not (Test-Path -LiteralPath $workspaceState)) {
        throw "workspace task mark did not create state file: $workspaceState"
    }

    $state = Get-Content -LiteralPath $workspaceState -Raw | ConvertFrom-Json
    $tasks = @($state.tasks)
    if ($tasks.Count -ne 1 -or $tasks[0].name -ne "before-large-agent-task" -or $tasks[0].state -ne "prepared") {
        throw "workspace task mark wrote unexpected state: $(Get-Content -LiteralPath $workspaceState -Raw)"
    }

    Assert-Command `
        -Name "workspace dashboard with state" `
        -Arguments @("workspace", "dashboard", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceState) `
        -ExitCode 0 `
        -Patterns @("Workspace dashboard: example-project", "state: prepared at", "before-large-agent-task")

    Assert-Command `
        -Name "workspace report with state" `
        -Arguments @("workspace", "report", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceState) `
        -ExitCode 0 `
        -Patterns @("Workspace report: example-project", "Release handoff summary:", "owned: 1; cadence set: 1", "owner gaps: none", "release gate: blocked by snapshot gate", "blocked tasks: before-large-agent-task", "Governance loop:", "platform-maintainer: before-large-agent-task", "attention queue: before-large-agent-task", "Decision queues:", "create snapshot: before-large-agent-task", "release blocked: before-large-agent-task", "Milestone review rollup:", "agent-safety-baseline.*tasks: 1; blocked: 1; validation required: 0; review required: 0; ready to commit: 0", "Release decision policy:", "decision: release blocked", "blockers: before-large-agent-task", "Stale-task remediation:", "before-large-agent-task: owner=platform-maintainer; cadence=per-task; timing=not urgent; action=create snapshot; release=release blocked", "state: prepared", "review bundle:", "project: app", "sync hygiene: not checked - project path missing", "owner: platform-maintainer", "review cadence: per-task", "due: 2099-12-31 \(scheduled\)", "action: create snapshot", "release readiness: release blocked", "checkpoint: before-large-agent-task", "validation result: not recorded", "commit: blocked by snapshot gate", "checklist:")
} finally {
    Remove-Item -LiteralPath $workspaceState -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workspaceBoundaryState -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $workspaceExtValidationState -Force -ErrorAction SilentlyContinue
}

$workspaceValidationState = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-workspace-validation-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
try {
    @"
{
  "version": 1,
  "tasks": [
    {
      "name": "frontend-browser-acceptance",
      "state": "reviewed",
      "updated_at": "2026-05-28T00:00:00.0000000Z",
      "validation": {
        "status": "passed",
        "runtime": "frontend",
        "project": "frontend-app",
        "remote_path": "/home/adp/workspace/frontend-app",
        "command_count": 2,
        "commands": [
          "pnpm install",
          "pnpm exec playwright test"
        ],
        "exit_code": 0,
        "failed_command": "",
        "started_at": "2026-05-28T00:00:00.0000000Z",
        "completed_at": "2026-05-28T00:01:00.0000000Z"
      }
    },
    {
      "name": "docs-copy-edit",
      "state": "validated",
      "updated_at": "2026-05-28T00:01:30.0000000Z",
      "validation": {
        "status": "passed",
        "runtime": "agent",
        "project": "agent-workspace",
        "remote_path": "/home/adp/workspace/agent-workspace",
        "command_count": 2,
        "commands": [
          "git diff --check",
          "git status --short"
        ],
        "exit_code": 0,
        "failed_command": "",
        "started_at": "2026-05-28T00:01:00.0000000Z",
        "completed_at": "2026-05-28T00:01:30.0000000Z"
      }
    },
    {
      "name": "backend-validation-pass",
      "state": "validation_failed",
      "updated_at": "2026-05-28T00:03:00.0000000Z",
      "validation": {
        "status": "failed",
        "runtime": "backend",
        "project": "backend-api",
        "remote_path": "/home/adp/workspace/backend-api",
        "command_count": 3,
        "commands": [
          "uv sync",
          "uv run pytest",
          "uv run ruff check ."
        ],
        "exit_code": 1,
        "failed_command": "uv run pytest",
        "started_at": "2026-05-28T00:02:00.0000000Z",
        "completed_at": "2026-05-28T00:03:00.0000000Z"
      }
    }
  ]
}
"@ | Set-Content -LiteralPath $workspaceValidationState -Encoding utf8

    Assert-Command `
        -Name "workspace dashboard shows validation result state" `
        -Arguments @("workspace", "dashboard", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace dashboard: recipe-workspace", "frontend-browser-acceptance", "state: reviewed at", "validation result: passed at 2026-05-28T00:01:00.0000000Z; project: frontend-app; exit: 0", "commit: commit ready", "docs-copy-edit", "commit: review not recorded", "backend-validation-pass", "commit: blocked by validation")

    Assert-Command `
        -Name "workspace report shows validation result state" `
        -Arguments @("workspace", "report", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace report: recipe-workspace", "Release handoff summary:", "release gate: blocked by validation", "validation passed: 2; failed: 1; missing: 1", "owned: 4; cadence set: 4", "ready for review: docs-copy-edit", "ready to commit: frontend-browser-acceptance", "Governance loop:", "attention queue: .*docs-copy-edit.*review not recorded.*backend-validation-pass.*blocked by validation", "Decision queues:", "ready to commit: frontend-browser-acceptance", "review now: docs-copy-edit", "rollback or revise: backend-validation-pass", "release candidate: frontend-browser-acceptance", "review required: docs-copy-edit", "release blocked: .*backend-validation-pass.*broad-agent-refactor", "Release decision policy:", "decision: release blocked", "blockers: .*backend-validation-pass.*broad-agent-refactor", "review required: docs-copy-edit", "release candidates: frontend-browser-acceptance", "Stale-task remediation:", "backend-validation-pass: owner=backend-reviewer; cadence=per-change; timing=not urgent; action=rollback or revise; release=release blocked", "frontend-browser-acceptance", "project: frontend-app", "owner: frontend-reviewer", "action: ready to commit", "release readiness: release candidate", "validation result: passed at 2026-05-28T00:01:00.0000000Z; project: frontend-app; exit: 0", "commit: commit ready", "docs-copy-edit", "commit: review not recorded", "backend-validation-pass", "failed command: uv run pytest", "commit: blocked by validation", "adpos workspace task rollback backend-validation-pass")

    Assert-Command `
        -Name "workspace review shows validation result state" `
        -Arguments @("workspace", "task", "review", "frontend-browser-acceptance", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task review: frontend-browser-acceptance", "review verdict \(validation passed", "recorded validation: passed at 2026-05-28T00:01:00.0000000Z; project: frontend-app; exit: 0", "remote path: /home/adp/workspace/frontend-app", "command count: 2", "state file: .*adp-workspace-validation-state", "accept:   adpos workspace task mark frontend-browser-acceptance reviewed")

    Assert-Command `
        -Name "workspace review shows failed validation decision" `
        -Arguments @("workspace", "task", "review", "backend-validation-pass", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task review: backend-validation-pass", "review verdict \(validation failed", "recorded validation: failed at 2026-05-28T00:03:00.0000000Z; project: backend-api; exit: 1", "failed command: uv run pytest", "accept:   withheld until review decision gate is OK", "revise and re-run validation, or use rollback guidance")

    Assert-Command `
        -Name "workspace rollback shows failed validation context" `
        -Arguments @("workspace", "task", "rollback", "backend-validation-pass", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task rollback: backend-validation-pass", "Decision context:", "review verdict \(validation failed", "recorded validation: failed at 2026-05-28T00:03:00.0000000Z; project: backend-api; exit: 1", "failed command: uv run pytest", "git restore <paths>", "adpos workspace task mark backend-validation-pass rollback")

    Assert-Command `
        -Name "workspace commit shows readiness when reviewed" `
        -Arguments @("workspace", "task", "commit", "frontend-browser-acceptance", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task commit: frontend-browser-acceptance", "Commit readiness gate:", "commit readiness \(commit ready", "recorded task state: reviewed", "recorded validation: passed at 2026-05-28T00:01:00.0000000Z; project: frontend-app; exit: 0", "git add <paths>", "git commit -m", "adpos workspace task mark frontend-browser-acceptance committed")

    Assert-Command `
        -Name "workspace commit blocks missing review state" `
        -Arguments @("workspace", "task", "commit", "docs-copy-edit", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task commit: docs-copy-edit", "Commit readiness gate:", "commit readiness \(review not recorded", "recorded task state: validated", "Commit commands withheld until commit readiness is OK", "Resolve gate first: run adpos workspace task review docs-copy-edit")

    Assert-Command `
        -Name "workspace commit blocks failed validation" `
        -Arguments @("workspace", "task", "commit", "backend-validation-pass", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task commit: backend-validation-pass", "Commit readiness gate:", "commit readiness \(blocked by validation", "recorded task state: validation_failed", "failed command: uv run pytest", "Commit commands withheld until commit readiness is OK", "Resolve gate first: revise and re-run validation, or rollback")
} finally {
    Remove-Item -LiteralPath $workspaceValidationState -Force -ErrorAction SilentlyContinue
}

$snapshotGateManifest = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-workspace-snapshot-gate-{0}.json" -f ([guid]::NewGuid().ToString("N")))
$snapshotName = "adp-test-missing-snapshot-$([guid]::NewGuid().ToString("N"))"
try {
    @"
{
  "name": "snapshot-gate-workspace",
  "version": 1,
  "projects": [
    {
      "name": "agent-workspace",
      "path": "agent-workspace",
      "runtime": "agent",
      "sync": true,
      "validation": [
        "git status --short"
      ]
    }
  ],
  "tasks": [
    {
      "name": "risky-agent-task",
      "project": "agent-workspace",
      "runtime": "agent",
      "risk": "high",
      "requires_snapshot": true,
      "snapshot": "$snapshotName",
      "validation": [
        "git status --short"
      ]
    }
  ]
}
"@ | Set-Content -LiteralPath $snapshotGateManifest -Encoding utf8

    Assert-Command `
        -Name "workspace dashboard blocks missing high-risk snapshot" `
        -Arguments @("workspace", "dashboard", "-ManifestPath", $snapshotGateManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace dashboard: snapshot-gate-workspace", "snapshot required: True", "checkpoint: blocked", "execution: blocked by snapshot gate")

    Assert-Command `
        -Name "workspace task run blocks missing high-risk snapshot" `
        -Arguments @("workspace", "task", "run", "risky-agent-task", "-ManifestPath", $snapshotGateManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace task run: risky-agent-task", "Snapshot-first gate before broad agent work", "BLOCKED: create checkpoint first", "adpos snapshot create agent $snapshotName")

    Assert-Command `
        -Name "workspace task validate execute blocks missing high-risk snapshot" `
        -Arguments @("workspace", "task", "validate", "risky-agent-task", "-Execute", "-ManifestPath", $snapshotGateManifest) `
        -ExitCode 1 `
        -Patterns @("Workspace task validate: risky-agent-task", "Readiness gate:", "snapshot-first gate \(blocked: create checkpoint first", "snapshot-first gate is blocked: create checkpoint first")
} finally {
    Remove-Item -LiteralPath $snapshotGateManifest -Force -ErrorAction SilentlyContinue
}

Assert-Command `
    -Name "workspace task unknown task" `
    -Arguments @("workspace", "task", "prepare", "not-a-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 1 `
    -Patterns @("Workspace task not found: not-a-task", "Available tasks: before-large-agent-task")

Assert-Command `
    -Name "workspace task unknown command" `
    -Arguments @("workspace", "task", "deploy", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 1 `
    -Patterns @("Unknown workspace task command: deploy", "Valid: prepare, snapshot, run, validate, review, rollback, commit, mark")

Assert-Command `
    -Name "workspace task execute only supports validate" `
    -Arguments @("workspace", "task", "run", "before-large-agent-task", "-Execute", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 1 `
    -Patterns @("-Execute, -Local, and -Plan are only supported with: adpos workspace task validate <task-name>")

Assert-Command `
    -Name "workspace task validate plan requires execute" `
    -Arguments @("workspace", "task", "validate", "before-large-agent-task", "-Plan", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 1 `
    -Patterns @("-Plan is only supported with -Execute or -Local for workspace task validation")

Assert-Command `
    -Name "workspace unknown subcommand" `
    -Arguments @("workspace", "nope", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 1 `
    -Patterns @("Unknown workspace command: nope", "Use 'adpos workspace help' to see grouped subcommands.")
