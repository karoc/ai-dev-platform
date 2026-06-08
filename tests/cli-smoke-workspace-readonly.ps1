Assert-Command `
    -Name "workspace show example manifest" `
    -Arguments @("workspace", "show", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace: example-project", "Projects:", "app:.*\\app\s+->\s+agent", "Milestones:", "agent-safety-baseline", "milestone-agent-safety-baseline", "Tasks:", "milestone=agent-safety-baseline")

Assert-Command `
    -Name "workspace plan example manifest" `
    -Arguments @("workspace", "plan", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Plan only: no projects will be cloned", "adpos up agent -Plan", "Snapshot before task 'before-large-agent-task' \(naming: aligned\): adpos snapshot create agent before-large-agent-task", "Milestone checkpoint 'agent-safety-baseline' \(naming: aligned\): adpos snapshot create agent milestone-agent-safety-baseline")

Assert-Command `
    -Name "workspace show recipes manifest" `
    -Arguments @("workspace", "show", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace: recipe-workspace", "frontend-app:.*\\frontend-app\s+->\s+frontend", "backend-api:.*\\backend-api\s+->\s+backend", "agent-workspace:.*\\agent-workspace\s+->\s+agent", "Milestones:", "frontend-acceptance", "agent-refactor-safety")

Assert-Command `
    -Name "workspace plan recipes manifest" `
    -Arguments @("workspace", "plan", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Plan only: no projects will be cloned", "adpos up frontend -Plan", "adpos up backend -Plan", "adpos up agent -Plan", "Snapshot before task 'broad-agent-refactor' \(naming: aligned\): adpos snapshot create agent before-broad-agent-refactor", "Milestone checkpoint 'frontend-acceptance' \(naming: aligned\): adpos snapshot create frontend milestone-frontend-acceptance", "Milestone checkpoint 'agent-refactor-safety' \(naming: aligned\): adpos snapshot create agent milestone-agent-refactor-safety")

Assert-Command `
    -Name "workspace recipes manifest discovery" `
    -Arguments @("workspace", "recipes", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace recipes: recipe-workspace", "Recipes only: no projects will be cloned", "no SSH connection will be opened, and no Git commands will be run", "Overview:", "projects: 3, tasks: 4, milestones: 2, evaluations: 2", "Project recipes:", "frontend-app.*runtime: frontend.*validation commands: 3.*linked tasks: 1", "backend-api.*runtime: backend.*validation commands: 3", "agent-workspace.*runtime: agent.*linked tasks: 2", "validation recipe:", "pnpm exec playwright test", "uv run pytest", "Task recipes:", "frontend-browser-acceptance.*project: frontend-app.*runtime: frontend.*milestone: frontend-acceptance.*evaluation: frontend-acceptance-eval", "broad-agent-refactor.*risk: high.*snapshot required: True.*action: create snapshot.*release: release blocked", "checkpoint: adpos snapshot create agent before-broad-agent-refactor", "execute preview: adpos workspace task validate frontend-browser-acceptance -Execute -Plan", "Milestone recipes:", "frontend-acceptance.*snapshot: milestone-frontend-acceptance", "checkpoint command: adpos snapshot create frontend milestone-frontend-acceptance", "Evaluation recipes:", "Evaluation hooks are plan-only", "frontend-acceptance-eval.*readiness: planned.*runtime: frontend.*project: frontend-app", "metrics: browser-tests-pass, visual-regressions-reviewed, sync-hygiene-reviewed", "commands: pnpm exec playwright test; git diff --check", "Evidence commands:", "adpos workspace dashboard -ManifestPath 'configs\\workspace\.recipes\.example\.json'", "adpos workspace report -Markdown -ManifestPath 'configs\\workspace\.recipes\.example\.json'")

Assert-Command `
    -Name "workspace open single project manifest" `
    -Arguments @("workspace", "open", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace open: app", "Open guide only: no shell, editor, SSH connection, sync session, runtime, or file will be changed", "Project:", "Runtime:\s+agent", "Local path:.*app", "Remote path:\s+/home/adp/workspace/app", "Readiness:", "local path", "runtime agent", "sync", "sync hygiene", "devcontainer", "Local commands:", "Set-Location -LiteralPath", "git status --short", "code ", "Runtime commands:", "ssh adp-os-adp-agent", "ssh -i .*adp@192\.168\.242\.135", "cd '/home/adp/workspace/app'", "Next:", "adpos workspace status -ManifestPath 'configs\\workspace\.example\.json'", "adpos up agent -Plan", "adpos sync start agent")

Assert-Command `
    -Name "workspace open named recipe project" `
    -Arguments @("workspace", "open", "frontend-app", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace open: frontend-app", "Open guide only", "Runtime:\s+frontend", "Local path:.*frontend-app", "Remote path:\s+/home/adp/workspace/frontend-app", "ssh adp-os-adp-frontend", "ssh -i .*adp@192\.168\.242\.131", "cd '/home/adp/workspace/frontend-app'", "adpos sync start frontend")

Assert-Command `
    -Name "workspace open requires project for multi project manifest" `
    -Arguments @("workspace", "open", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 1 `
    -Patterns @("Project name required because the workspace has multiple projects", "frontend-app", "backend-api", "agent-workspace")

Assert-Command `
    -Name "workspace sync single project manifest" `
    -Arguments @("workspace", "sync", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace sync: app", "Sync guide only: no Mutagen session, runtime, SSH connection, directory, or file will be changed", "Project:", "Runtime:\s+agent", "Sync intent:\s+requested", "Local path:.*app", "Remote path:\s+/home/adp/workspace/app", "Readiness:", "sync session", "sync hygiene", "Runtime sync commands:", "adpos sync status", "adpos sync start agent", "adpos sync stop agent", "Project commands:", "adpos workspace open app -ManifestPath 'configs\\workspace\.example\.json'", "adpos workspace dashboard -ManifestPath 'configs\\workspace\.example\.json'")

Assert-Command `
    -Name "workspace sync named recipe project" `
    -Arguments @("workspace", "sync", "frontend-app", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace sync: frontend-app", "Sync guide only", "Runtime:\s+frontend", "Sync intent:\s+requested", "Remote path:\s+/home/adp/workspace/frontend-app", "sync session", "adpos sync start frontend", "adpos sync stop frontend", "adpos workspace open frontend-app -ManifestPath 'configs\\workspace\.recipes\.example\.json'")

Assert-Command `
    -Name "workspace sync requires project for multi project manifest" `
    -Arguments @("workspace", "sync", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 1 `
    -Patterns @("Project name required because the workspace has multiple projects", "frontend-app", "backend-api", "agent-workspace")

Assert-Command `
    -Name "workspace project single project manifest" `
    -Arguments @("workspace", "project", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace project lifecycle: app", "Lifecycle view only: no project, runtime, sync session, snapshot, validation command, Git command, or file will be changed", "Project:", "Runtime:\s+agent", "Sync intent:\s+requested", "Local path:.*app", "Remote path:\s+/home/adp/workspace/app", "Lifecycle gates:", "local path", "runtime agent", "sync session", "sync hygiene", "devcontainer", "project validation", "linked tasks", "Operational flow:", "1\. Open:\s+adpos workspace open app", "2\. Runtime:\s+adpos up agent -Plan", "3\. Sync:\s+adpos workspace sync app", "4\. Validate:", "5\. Evidence:\s+adpos workspace report", "Project validation commands:", "pnpm test", "Linked tasks:", "before-large-agent-task", "milestone: agent-safety-baseline", "snapshot gate:", "validation: not recorded", "prepare:\s+adpos workspace task prepare before-large-agent-task")

Assert-Command `
    -Name "workspace project named recipe project" `
    -Arguments @("workspace", "project", "frontend-app", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace project lifecycle: frontend-app", "Lifecycle view only", "Runtime:\s+frontend", "Sync intent:\s+requested", "Remote path:\s+/home/adp/workspace/frontend-app", "Operational flow:", "adpos workspace open frontend-app", "adpos workspace sync frontend-app", "Project validation commands:", "pnpm install", "pnpm exec playwright test", "Linked tasks:", "frontend-browser-acceptance", "risk: normal", "commit: validation result missing")

Assert-Command `
    -Name "workspace project requires project for multi project manifest" `
    -Arguments @("workspace", "project", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 1 `
    -Patterns @("Project name required because the workspace has multiple projects", "frontend-app", "backend-api", "agent-workspace")

Assert-Command `
    -Name "workspace status example manifest" `
    -Arguments @("workspace", "status", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace readiness: example-project", "Status only: no projects will be cloned", "Manifest:", "projects: 1, tasks: 1, milestones: 1, evaluations: 1", "Projects:", "runtime agent", "Milestones:", "agent-safety-baseline", "milestone-agent-safety-baseline", "Evaluations:", "agent-change-evaluation", "Evaluation hooks are plan-only", "Tasks:", "milestone \(agent-safety-baseline\)", "evaluation \(agent-change-evaluation\)", "risk \(high; requires snapshot: True\)", "snapshot naming \(aligned: matches task checkpoint convention: before-large-agent-task\)", "snapshot-first gate", "validation commands")

Assert-Command `
    -Name "workspace dashboard example manifest" `
    -Arguments @("workspace", "dashboard", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace dashboard: example-project", "Dashboard only: no projects will be cloned", "Project readiness:", "Milestone checkpoints:", "agent-safety-baseline", "Evaluation hooks:", "agent-change-evaluation", "readiness: planned", "Task lifecycle:", "milestone: agent-safety-baseline", "evaluation: agent-change-evaluation", "snapshot required: True", "snapshot naming: aligned", "checkpoint:", "execution:", "rollback:", "commit:")

Assert-Command `
    -Name "workspace dashboard recipes manifest" `
    -Arguments @("workspace", "dashboard", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace dashboard: recipe-workspace", "Milestone checkpoints:", "frontend-acceptance", "agent-refactor-safety", "Evaluation hooks:", "frontend-acceptance-eval", "agent-safety-eval", "frontend-browser-acceptance", "backend-validation-pass", "broad-agent-refactor", "milestone: frontend-acceptance", "milestone: agent-refactor-safety", "evaluation: frontend-acceptance-eval", "evaluation: agent-safety-eval", "snapshot required: True", "execution: blocked by snapshot gate")

Assert-Command `
    -Name "workspace report recipes manifest" `
    -Arguments @("workspace", "report", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace report: recipe-workspace", "Report only: no projects will be cloned", "Release handoff summary:", "milestones linked: 2", "owned: 4; cadence set: 4", "owner gaps: none", "cadence gaps: none", "due attention: none", "release gate: blocked by snapshot gate", "blocked tasks: .*frontend-browser-acceptance.*backend-validation-pass.*broad-agent-refactor", "Governance loop:", "owner queues:", "frontend-reviewer: frontend-browser-acceptance", "review cadence:", "per-change: .*frontend-browser-acceptance.*backend-validation-pass", "attention queue: .*frontend-browser-acceptance.*validation result missing", "Decision queues:", "actions:", "validate now: .*frontend-browser-acceptance.*backend-validation-pass", "create snapshot: broad-agent-refactor", "release readiness:", "validation required: .*frontend-browser-acceptance.*backend-validation-pass", "release blocked: broad-agent-refactor", "milestones:", "frontend-acceptance: frontend-browser-acceptance", "agent-refactor-safety: broad-agent-refactor", "Milestone checkpoints:", "checkpoint command: adpos snapshot create frontend milestone-frontend-acceptance", "checkpoint command: adpos snapshot create agent milestone-agent-refactor-safety", "Milestone review rollup:", "frontend-acceptance.*tasks: 1; blocked: 0; validation required: 1; review required: 0; ready to commit: 0", "agent-refactor-safety.*tasks: 1; blocked: 1; validation required: 0; review required: 0; ready to commit: 0", "actions: validate now: frontend-browser-acceptance", "release: release blocked: broad-agent-refactor", "blocked tasks: broad-agent-refactor", "owners: frontend-reviewer", "Validation execution queue:", "frontend-browser-acceptance.*validation: not recorded; commands: 2; readiness: ready to execute", "broad-agent-refactor.*readiness: blocked", "blockers: snapshot-first gate: blocked", "execute preview: adpos workspace task validate frontend-browser-acceptance -Execute -Plan", "execute: adpos workspace task validate frontend-browser-acceptance -Execute", "Evaluation queue:", "Evaluation queue only: no evaluation commands will be run", "frontend-acceptance-eval.*readiness: planned; runtime: frontend; project: frontend-app", "agent-safety-eval.*readiness: planned; runtime: agent; project: agent-workspace", "metrics: browser-tests-pass, visual-regressions-reviewed, sync-hygiene-reviewed", "commands: pnpm exec playwright test; git diff --check", "Release decision policy:", "decision: release blocked", "blockers: broad-agent-refactor", "validation required: .*frontend-browser-acceptance.*backend-validation-pass", "release candidates: none", "Stale-task remediation:", "frontend-browser-acceptance: owner=frontend-reviewer; cadence=per-change; timing=not urgent; action=validate now; release=validation required", "Task reports:", "frontend-browser-acceptance", "review bundle:", "project: frontend-app", "milestone: frontend-acceptance", "evaluation: frontend-acceptance-eval", "owner: frontend-reviewer", "review cadence: per-change", "due: 2099-12-31 \(scheduled\)", "runtime: frontend", "snapshot naming: optional - task does not require a snapshot; recommended if needed: before-frontend-browser-acceptance", "validation commands: 2", "action: validate now", "release readiness: validation required", "validation result: not recorded", "review: validation result missing", "commit: validation result missing", "checklist:", "validation: confirm the latest recorded result", "sync hygiene: confirm clean, covered, not requested, or intentionally reviewed before release", "source: inspect git status", "rollback: confirm the VM checkpoint", "commit: commit only after sync hygiene, validation, and human review", "handoff:", "adpos workspace task review frontend-browser-acceptance", "inspect:  git status --short; git diff --stat; git diff")

Assert-Command `
    -Name "workspace report markdown recipes manifest" `
    -Arguments @("workspace", "report", "-Markdown", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("# Workspace Release Evidence: recipe-workspace", "Markdown report only", "## Sources", "\| Manifest \| configs\\workspace\.recipes\.example\.json \|", "\| Local state \| adp-workspace\.state\.json \|", "## Release Decision", "\| Decision \| release blocked \|", "\| Blockers \| broad-agent-refactor \|", "## Handoff Summary", "\| Validation missing \| 4 \|", "## Validation Execution Queue", "\| Task \| Validation \| Commands \| Readiness \| Blockers \| Plan \| Execute preview \| Execute \|", "\| frontend-browser-acceptance \| not recorded \| 2 \| ready to execute \| none \| adpos workspace task validate frontend-browser-acceptance -ManifestPath configs\\workspace\.recipes\.example\.json \| adpos workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\\workspace\.recipes\.example\.json \| adpos workspace task validate frontend-browser-acceptance -Execute -ManifestPath configs\\workspace\.recipes\.example\.json \|", "\| broad-agent-refactor \| not recorded \| 3 \| blocked \| snapshot-first gate: blocked \| adpos workspace task validate broad-agent-refactor -ManifestPath configs\\workspace\.recipes\.example\.json \|", "## Evaluation Queue", "No evaluation commands were run", "\| Evaluation \| Readiness \| Runtime \| Project \| Cadence \| Metrics \| Commands \| Tasks \| Blockers \| Evidence \|", "\| frontend-acceptance-eval \| planned \| frontend \| frontend-app \| per-change \| browser-tests-pass, visual-regressions-reviewed, sync-hygiene-reviewed \| 2 \| frontend-browser-acceptance \| none \| adpos workspace report -ManifestPath configs\\workspace\.recipes\.example\.json \|", "\| agent-safety-eval \| planned \| agent \| agent-workspace \| per-task \| snapshot-ready-or-waived, validation-pass, rollback-path-reviewed \| 3 \| broad-agent-refactor \| none \| adpos workspace report -ManifestPath configs\\workspace\.recipes\.example\.json \|", "## Decision Queues", "\| Action: validate now \| .*frontend-browser-acceptance.*backend-validation-pass", "\| Release: release blocked \| broad-agent-refactor \|", "\| Milestone: frontend-acceptance \| frontend-browser-acceptance \|", "\| Milestone: agent-refactor-safety \| broad-agent-refactor \|", "## Milestone Checkpoints", "\| frontend-acceptance \| frontend \| milestone-frontend-acceptance \| aligned - matches milestone checkpoint convention: milestone-frontend-acceptance \| (not checked: external snapshot probe skipped: frontend/milestone-frontend-acceptance|not available: VM not created|recommended: Run: adpos snapshot create frontend milestone-frontend-acceptance) \| frontend-browser-acceptance \|", "## Milestone Review Rollup", "\| Milestone \| Tasks \| Actions \| Release \| Blocked \| Validation required \| Review required \| Ready to commit \| Owners \| Due attention \|", "\| frontend-acceptance \| 1 \| validate now: frontend-browser-acceptance \| validation required: frontend-browser-acceptance \| none \| frontend-browser-acceptance \| none \| none \| frontend-reviewer \| none \|", "\| agent-refactor-safety \| 1 \| create snapshot: broad-agent-refactor \| release blocked: broad-agent-refactor \| broad-agent-refactor \| none \| none \| none \| agent-reviewer \| none \|", "## Task Evidence", "\| Task \| Milestone \| Evaluation \| Owner \| Runtime \| Risk \| Sync hygiene \| Validation \| Review \| Commit \| Release \| Next action \|", "\| frontend-browser-acceptance \| frontend-acceptance \| frontend-acceptance-eval \| frontend-reviewer \| frontend \| normal \| not checked: project path missing \| not recorded \| validation result missing \| validation result missing \| validation required \| validate now \|", "## Task Details", "### broad-agent-refactor", "Milestone: agent-refactor-safety", "Evaluation: agent-safety-eval", "Snapshot: before-broad-agent-refactor; required: True; gate: blocked; naming: aligned - matches task checkpoint convention: before-broad-agent-refactor", "Handoff commands:", "adpos workspace task rollback broad-agent-refactor -ManifestPath configs\\workspace.recipes.example.json", "## Maintainer Checklist", "Confirm sync hygiene is clean, covered, not requested, or intentionally reviewed before release", "Commit only after sync hygiene, validation, and human review")

$syncNotRequestedRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-sync-not-requested-{0}" -f ([guid]::NewGuid().ToString("N")))
$syncNotRequestedManifest = Join-Path $syncNotRequestedRoot "adp-workspace.json"
$syncNotRequestedState = Join-Path $syncNotRequestedRoot "adp-workspace.state.json"
try {
    New-Item -ItemType Directory -Path $syncNotRequestedRoot -Force | Out-Null
    @"
{
  "name": "sync-not-requested-workspace",
  "version": 1,
  "projects": [
    {
      "name": "app",
      "path": "app",
      "runtime": "agent",
      "sync": false
    }
  ],
  "tasks": [
    {
      "name": "sync-not-requested-task",
      "project": "app",
      "runtime": "agent",
      "risk": "normal",
      "owner": "platform-maintainer",
      "review_cadence": "per-change",
      "due": "2099-12-31",
      "requires_snapshot": false,
      "validation": [
        "git status --short"
      ]
    }
  ]
}
"@ | Set-Content -LiteralPath $syncNotRequestedManifest -Encoding utf8

    @"
{
  "version": 1,
  "tasks": [
    {
      "name": "sync-not-requested-task",
      "state": "reviewed",
      "updated_at": "2026-05-29T00:00:00.0000000Z",
      "validation": {
        "status": "passed",
        "runtime": "agent",
        "project": "app",
        "remote_path": "/home/adp/workspace/app",
        "command_count": 1,
        "commands": [
          "git status --short"
        ],
        "exit_code": 0,
        "failed_command": "",
        "started_at": "2026-05-29T00:00:00.0000000Z",
        "completed_at": "2026-05-29T00:00:10.0000000Z"
      }
    }
  ]
}
"@ | Set-Content -LiteralPath $syncNotRequestedState -Encoding utf8

    Assert-Command `
        -Name "workspace report markdown formats sync hygiene without empty detail punctuation" `
        -Arguments @("workspace", "report", "-Markdown", "-ManifestPath", $syncNotRequestedManifest, "-StatePath", $syncNotRequestedState) `
        -ExitCode 0 `
        -Patterns @("\| sync-not-requested-task \| not set \| not set \| platform-maintainer \| agent \| normal \| not requested \|", "- Sync hygiene: not requested")
} finally {
    Remove-Item -LiteralPath $syncNotRequestedRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$outsideStatePath = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-workspace-outside-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
try {
    Assert-Command `
        -Name "workspace report markdown redacts outside state path" `
        -Arguments @("workspace", "report", "-Markdown", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $outsideStatePath) `
        -ExitCode 0 `
        -Patterns @("\| Local state \| outside repository: .*adp-workspace-outside-state-.*\.json \|")
} finally {
    Remove-Item -LiteralPath $outsideStatePath -Force -ErrorAction SilentlyContinue
}
