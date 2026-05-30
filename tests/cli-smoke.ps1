# ADP-OS CLI smoke tests
# Non-destructive behavior checks for command dispatch, preview paths, and input errors.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$cli = Join-Path $projectRoot "cli\adp.ps1"

function Invoke-Cli {
    param([string[]]$Arguments)

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $processArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $cli) + $Arguments
        $process = Start-Process -FilePath "pwsh" `
            -ArgumentList $processArguments `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr

        $outText = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
        $errText = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = "$outText`n$errText"
        }
    } finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Assert-ExitCode {
    param(
        [string]$Name,
        [object]$Result,
        [int]$Expected
    )

    if ($Result.ExitCode -ne $Expected) {
        throw "$Name exit code was $($Result.ExitCode), expected $Expected.`n$($Result.Output)"
    }
}

function Assert-OutputContains {
    param(
        [string]$Name,
        [object]$Result,
        [string]$Pattern
    )

    if ($Result.Output -notmatch $Pattern) {
        throw "$Name output did not match: $Pattern`n$($Result.Output)"
    }
}

function Assert-Command {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [int]$ExitCode,
        [string[]]$Patterns
    )

    $result = Invoke-Cli -Arguments $Arguments
    Assert-ExitCode -Name $Name -Result $result -Expected $ExitCode
    foreach ($pattern in $Patterns) {
        Assert-OutputContains -Name $Name -Result $result -Pattern $pattern
    }
}

Assert-Command `
    -Name "help" `
    -Arguments @("help") `
    -ExitCode 0 `
    -Patterns @("ADP-OS CLI", "adp up <runtime>", "adp capabilities")

Assert-Command `
    -Name "capabilities" `
    -Arguments @("capabilities") `
    -ExitCode 0 `
    -Patterns @("ADP-OS Capabilities", "Capabilities only: no VMs", "\[supported\] vmware-workstation", "host: Windows", "\[planned\] hyper-v", "\[planned\] kvm-libvirt", "\[planned\] macos-vm", "\[exploratory\] container-backed", "Docker and dev containers are runtime-internal project tools today", "Docs: docs/capabilities.md")

Assert-Command `
    -Name "unknown command" `
    -Arguments @("not-a-command") `
    -ExitCode 1 `
    -Patterns @("Unknown command: not-a-command", "Valid commands:")

Assert-Command `
    -Name "up unknown runtime" `
    -Arguments @("up", "not-a-runtime", "-Plan") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent")

Assert-Command `
    -Name "up plan" `
    -Arguments @("up", "agent", "-Plan", "-IsoPath", "D:\Share\ubuntu-26.04-live-server-amd64.iso") `
    -ExitCode 0 `
    -Patterns @("Plan only: no VM will be created", "Runtime:\s+agent", "ISO:\s+D:\\Share\\ubuntu-26\.04-live-server-amd64\.iso")

Assert-Command `
    -Name "status all runtimes" `
    -Arguments @("status") `
    -ExitCode 0 `
    -Patterns @("ADP-OS Status", "Status only: no VMs", "Local config:", "Network:\s+192\.168\.242\.0/24", "frontend", "configured IP:\s+192\.168\.242\.131", "connect:\s+ssh -i .*adp@192\.168\.242\.131", "backend", "agent")

Assert-Command `
    -Name "status single runtime" `
    -Arguments @("status", "agent") `
    -ExitCode 0 `
    -Patterns @("ADP-OS Status", "agent", "configured IP:\s+192\.168\.242\.135", "alias:\s+ssh adp-os-adp-agent")

Assert-Command `
    -Name "status unknown runtime" `
    -Arguments @("status", "not-a-runtime") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent")

Assert-Command `
    -Name "sync unknown subcommand" `
    -Arguments @("sync", "nope") `
    -ExitCode 1 `
    -Patterns @("Unknown sync command: nope", "status, start, stop, list")

Assert-Command `
    -Name "sync unknown runtime" `
    -Arguments @("sync", "stop", "not-a-runtime") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent")

Assert-Command `
    -Name "doctor plan without fix mutagen" `
    -Arguments @("doctor", "-Plan") `
    -ExitCode 1 `
    -Patterns @("-Plan is only supported with -FixMutagen")

Assert-Command `
    -Name "doctor fix mutagen plan" `
    -Arguments @("doctor", "-FixMutagen", "-Plan") `
    -ExitCode 0 `
    -Patterns @("Mutagen remediation:", "Plan only: no files will be downloaded", "mutagen_windows_amd64_v0\.18\.1\.zip", "\.tools\\mutagen\\mutagen\.exe", "Offline archive:", "SHA256:", "Timeout:\s+connection=30s hard=300s", "platform\.tools\.mutagen\.download_url", "To install: \.\\cli\\adp\.ps1 doctor -FixMutagen")

Assert-Command `
    -Name "doctor reports VMware NAT prerequisites" `
    -Arguments @("doctor", "-FixMutagen", "-Plan") `
    -ExitCode 0 `
    -Patterns @("VMware NAT config", "VMware NAT gateway range", "VMware NAT host match", "VMware NAT prerequisites", "VMnet8")

Assert-Command `
    -Name "network apply rejects local apply switch" `
    -Arguments @("network", "apply", "agent", "-Apply") `
    -ExitCode 1 `
    -Patterns @("-Apply is only supported with: adp network configure-local -Apply")

Assert-Command `
    -Name "workspace show example manifest" `
    -Arguments @("workspace", "show", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace: example-project", "Projects:", "app:\s+app -> agent", "Milestones:", "agent-safety-baseline", "milestone-agent-safety-baseline", "Tasks:", "milestone=agent-safety-baseline")

Assert-Command `
    -Name "workspace plan example manifest" `
    -Arguments @("workspace", "plan", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Plan only: no projects will be cloned", "adp up agent -Plan", "Snapshot before task 'before-large-agent-task' \(naming: aligned\): adp snapshot create agent before-large-agent-task", "Milestone checkpoint 'agent-safety-baseline' \(naming: aligned\): adp snapshot create agent milestone-agent-safety-baseline")

Assert-Command `
    -Name "workspace show recipes manifest" `
    -Arguments @("workspace", "show", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace: recipe-workspace", "frontend-app:\s+frontend-app -> frontend", "backend-api:\s+backend-api -> backend", "agent-workspace:\s+agent-workspace -> agent", "Milestones:", "frontend-acceptance", "agent-refactor-safety")

Assert-Command `
    -Name "workspace plan recipes manifest" `
    -Arguments @("workspace", "plan", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Plan only: no projects will be cloned", "adp up frontend -Plan", "adp up backend -Plan", "adp up agent -Plan", "Snapshot before task 'broad-agent-refactor' \(naming: aligned\): adp snapshot create agent before-broad-agent-refactor", "Milestone checkpoint 'frontend-acceptance' \(naming: aligned\): adp snapshot create frontend milestone-frontend-acceptance", "Milestone checkpoint 'agent-refactor-safety' \(naming: aligned\): adp snapshot create agent milestone-agent-refactor-safety")

Assert-Command `
    -Name "workspace recipes manifest discovery" `
    -Arguments @("workspace", "recipes", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace recipes: recipe-workspace", "Recipes only: no projects will be cloned", "no SSH connection will be opened, and no Git commands will be run", "Overview:", "projects: 3, tasks: 4, milestones: 2, evaluations: 2", "Project recipes:", "frontend-app.*runtime: frontend.*validation commands: 3.*linked tasks: 1", "backend-api.*runtime: backend.*validation commands: 3", "agent-workspace.*runtime: agent.*linked tasks: 2", "validation recipe:", "pnpm exec playwright test", "uv run pytest", "Task recipes:", "frontend-browser-acceptance.*project: frontend-app.*runtime: frontend.*milestone: frontend-acceptance.*evaluation: frontend-acceptance-eval", "broad-agent-refactor.*risk: high.*snapshot required: True.*action: create snapshot.*release: release blocked", "checkpoint: adp snapshot create agent before-broad-agent-refactor", "execute preview: adp workspace task validate frontend-browser-acceptance -Execute -Plan", "Milestone recipes:", "frontend-acceptance.*snapshot: milestone-frontend-acceptance", "checkpoint command: adp snapshot create frontend milestone-frontend-acceptance", "Evaluation recipes:", "Evaluation hooks are plan-only", "frontend-acceptance-eval.*readiness: planned.*runtime: frontend.*project: frontend-app", "metrics: browser-tests-pass, visual-regressions-reviewed, sync-hygiene-reviewed", "commands: pnpm exec playwright test; git diff --check", "Evidence commands:", "adp workspace dashboard -ManifestPath 'configs\\workspace\.recipes\.example\.json'", "adp workspace report -Markdown -ManifestPath 'configs\\workspace\.recipes\.example\.json'")

Assert-Command `
    -Name "workspace open single project manifest" `
    -Arguments @("workspace", "open", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace open: app", "Open guide only: no shell, editor, SSH connection, sync session, runtime, or file will be changed", "Project:", "Runtime:\s+agent", "Local path:.*app", "Remote path:\s+/home/adp/workspace/app", "Readiness:", "local path", "runtime agent", "sync", "sync hygiene", "devcontainer", "Local commands:", "Set-Location -LiteralPath", "git status --short", "code ", "Runtime commands:", "ssh adp-os-adp-agent", "ssh -i .*adp@192\.168\.242\.135", "cd '/home/adp/workspace/app'", "Next:", "adp workspace status -ManifestPath 'configs\\workspace\.example\.json'", "adp up agent -Plan", "adp sync start agent")

Assert-Command `
    -Name "workspace open named recipe project" `
    -Arguments @("workspace", "open", "frontend-app", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace open: frontend-app", "Open guide only", "Runtime:\s+frontend", "Local path:.*frontend-app", "Remote path:\s+/home/adp/workspace/frontend-app", "ssh adp-os-adp-frontend", "ssh -i .*adp@192\.168\.242\.131", "cd '/home/adp/workspace/frontend-app'", "adp sync start frontend")

Assert-Command `
    -Name "workspace open requires project for multi project manifest" `
    -Arguments @("workspace", "open", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 1 `
    -Patterns @("Project name required because the workspace has multiple projects", "frontend-app", "backend-api", "agent-workspace")

Assert-Command `
    -Name "workspace sync single project manifest" `
    -Arguments @("workspace", "sync", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace sync: app", "Sync guide only: no Mutagen session, runtime, SSH connection, directory, or file will be changed", "Project:", "Runtime:\s+agent", "Sync intent:\s+requested", "Local path:.*app", "Remote path:\s+/home/adp/workspace/app", "Readiness:", "sync session", "sync hygiene", "Runtime sync commands:", "adp sync status", "adp sync start agent", "adp sync stop agent", "Project commands:", "adp workspace open app -ManifestPath 'configs\\workspace\.example\.json'", "adp workspace dashboard -ManifestPath 'configs\\workspace\.example\.json'")

Assert-Command `
    -Name "workspace sync named recipe project" `
    -Arguments @("workspace", "sync", "frontend-app", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace sync: frontend-app", "Sync guide only", "Runtime:\s+frontend", "Sync intent:\s+requested", "Remote path:\s+/home/adp/workspace/frontend-app", "sync session", "adp sync start frontend", "adp sync stop frontend", "adp workspace open frontend-app -ManifestPath 'configs\\workspace\.recipes\.example\.json'")

Assert-Command `
    -Name "workspace sync requires project for multi project manifest" `
    -Arguments @("workspace", "sync", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 1 `
    -Patterns @("Project name required because the workspace has multiple projects", "frontend-app", "backend-api", "agent-workspace")

Assert-Command `
    -Name "workspace project single project manifest" `
    -Arguments @("workspace", "project", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace project lifecycle: app", "Lifecycle view only: no project, runtime, sync session, snapshot, validation command, Git command, or file will be changed", "Project:", "Runtime:\s+agent", "Sync intent:\s+requested", "Local path:.*app", "Remote path:\s+/home/adp/workspace/app", "Lifecycle gates:", "local path", "runtime agent", "sync session", "sync hygiene", "devcontainer", "project validation", "linked tasks", "Operational flow:", "1\. Open:\s+adp workspace open app", "2\. Runtime:\s+adp up agent -Plan", "3\. Sync:\s+adp workspace sync app", "4\. Validate:", "5\. Evidence:\s+adp workspace report", "Project validation commands:", "pnpm test", "Linked tasks:", "before-large-agent-task", "milestone: agent-safety-baseline", "snapshot gate:", "validation: not recorded", "prepare:\s+adp workspace task prepare before-large-agent-task")

Assert-Command `
    -Name "workspace project named recipe project" `
    -Arguments @("workspace", "project", "frontend-app", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace project lifecycle: frontend-app", "Lifecycle view only", "Runtime:\s+frontend", "Sync intent:\s+requested", "Remote path:\s+/home/adp/workspace/frontend-app", "Operational flow:", "adp workspace open frontend-app", "adp workspace sync frontend-app", "Project validation commands:", "pnpm install", "pnpm exec playwright test", "Linked tasks:", "frontend-browser-acceptance", "risk: normal", "commit: validation result missing")

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
    -Patterns @("Workspace report: recipe-workspace", "Report only: no projects will be cloned", "Release handoff summary:", "milestones linked: 2", "owned: 4; cadence set: 4", "owner gaps: none", "cadence gaps: none", "due attention: none", "release gate: blocked by snapshot gate", "blocked tasks: .*frontend-browser-acceptance.*backend-validation-pass.*broad-agent-refactor", "Governance loop:", "owner queues:", "frontend-reviewer: frontend-browser-acceptance", "review cadence:", "per-change: .*frontend-browser-acceptance.*backend-validation-pass", "attention queue: .*frontend-browser-acceptance.*validation result missing", "Decision queues:", "actions:", "validate now: .*frontend-browser-acceptance.*backend-validation-pass", "create snapshot: broad-agent-refactor", "release readiness:", "validation required: .*frontend-browser-acceptance.*backend-validation-pass", "release blocked: broad-agent-refactor", "milestones:", "frontend-acceptance: frontend-browser-acceptance", "agent-refactor-safety: broad-agent-refactor", "Milestone checkpoints:", "checkpoint command: adp snapshot create frontend milestone-frontend-acceptance", "checkpoint command: adp snapshot create agent milestone-agent-refactor-safety", "Milestone review rollup:", "frontend-acceptance.*tasks: 1; blocked: 0; validation required: 1; review required: 0; ready to commit: 0", "agent-refactor-safety.*tasks: 1; blocked: 1; validation required: 0; review required: 0; ready to commit: 0", "actions: validate now: frontend-browser-acceptance", "release: release blocked: broad-agent-refactor", "blocked tasks: broad-agent-refactor", "owners: frontend-reviewer", "Validation execution queue:", "frontend-browser-acceptance.*validation: not recorded; commands: 2; readiness: ready to execute", "broad-agent-refactor.*readiness: blocked", "blockers: snapshot-first gate: blocked", "execute preview: adp workspace task validate frontend-browser-acceptance -Execute -Plan", "execute: adp workspace task validate frontend-browser-acceptance -Execute", "Evaluation queue:", "Evaluation queue only: no evaluation commands will be run", "frontend-acceptance-eval.*readiness: planned; runtime: frontend; project: frontend-app", "agent-safety-eval.*readiness: planned; runtime: agent; project: agent-workspace", "metrics: browser-tests-pass, visual-regressions-reviewed, sync-hygiene-reviewed", "commands: pnpm exec playwright test; git diff --check", "Release decision policy:", "decision: release blocked", "blockers: broad-agent-refactor", "validation required: .*frontend-browser-acceptance.*backend-validation-pass", "release candidates: none", "Stale-task remediation:", "frontend-browser-acceptance: owner=frontend-reviewer; cadence=per-change; timing=not urgent; action=validate now; release=validation required", "Task reports:", "frontend-browser-acceptance", "review bundle:", "project: frontend-app", "milestone: frontend-acceptance", "evaluation: frontend-acceptance-eval", "owner: frontend-reviewer", "review cadence: per-change", "due: 2099-12-31 \(scheduled\)", "runtime: frontend", "snapshot naming: optional - task does not require a snapshot; recommended if needed: before-frontend-browser-acceptance", "validation commands: 2", "action: validate now", "release readiness: validation required", "validation result: not recorded", "review: validation result missing", "commit: validation result missing", "checklist:", "validation: confirm the latest recorded result", "sync hygiene: confirm clean, covered, not requested, or intentionally reviewed before release", "source: inspect git status", "rollback: confirm the VM checkpoint", "commit: commit only after sync hygiene, validation, and human review", "handoff:", "adp workspace task review frontend-browser-acceptance", "inspect:  git status --short; git diff --stat; git diff")

Assert-Command `
    -Name "workspace report markdown recipes manifest" `
    -Arguments @("workspace", "report", "-Markdown", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("# Workspace Release Evidence: recipe-workspace", "Markdown report only", "## Sources", "\| Manifest \| configs\\workspace\.recipes\.example\.json \|", "\| Local state \| adp-workspace\.state\.json \|", "## Release Decision", "\| Decision \| release blocked \|", "\| Blockers \| broad-agent-refactor \|", "## Handoff Summary", "\| Validation missing \| 4 \|", "## Validation Execution Queue", "\| Task \| Validation \| Commands \| Readiness \| Blockers \| Plan \| Execute preview \| Execute \|", "\| frontend-browser-acceptance \| not recorded \| 2 \| ready to execute \| none \| adp workspace task validate frontend-browser-acceptance -ManifestPath configs\\workspace\.recipes\.example\.json \| adp workspace task validate frontend-browser-acceptance -Execute -Plan -ManifestPath configs\\workspace\.recipes\.example\.json \| adp workspace task validate frontend-browser-acceptance -Execute -ManifestPath configs\\workspace\.recipes\.example\.json \|", "\| broad-agent-refactor \| not recorded \| 3 \| blocked \| snapshot-first gate: blocked \| adp workspace task validate broad-agent-refactor -ManifestPath configs\\workspace\.recipes\.example\.json \|", "## Evaluation Queue", "No evaluation commands were run", "\| Evaluation \| Readiness \| Runtime \| Project \| Cadence \| Metrics \| Commands \| Tasks \| Blockers \| Evidence \|", "\| frontend-acceptance-eval \| planned \| frontend \| frontend-app \| per-change \| browser-tests-pass, visual-regressions-reviewed, sync-hygiene-reviewed \| 2 \| frontend-browser-acceptance \| none \| adp workspace report -ManifestPath configs\\workspace\.recipes\.example\.json \|", "\| agent-safety-eval \| planned \| agent \| agent-workspace \| per-task \| snapshot-ready-or-waived, validation-pass, rollback-path-reviewed \| 3 \| broad-agent-refactor \| none \| adp workspace report -ManifestPath configs\\workspace\.recipes\.example\.json \|", "## Decision Queues", "\| Action: validate now \| .*frontend-browser-acceptance.*backend-validation-pass", "\| Release: release blocked \| broad-agent-refactor \|", "\| Milestone: frontend-acceptance \| frontend-browser-acceptance \|", "\| Milestone: agent-refactor-safety \| broad-agent-refactor \|", "## Milestone Checkpoints", "\| frontend-acceptance \| frontend \| milestone-frontend-acceptance \| aligned - matches milestone checkpoint convention: milestone-frontend-acceptance \| recommended: Run: adp snapshot create frontend milestone-frontend-acceptance \| frontend-browser-acceptance \|", "## Milestone Review Rollup", "\| Milestone \| Tasks \| Actions \| Release \| Blocked \| Validation required \| Review required \| Ready to commit \| Owners \| Due attention \|", "\| frontend-acceptance \| 1 \| validate now: frontend-browser-acceptance \| validation required: frontend-browser-acceptance \| none \| frontend-browser-acceptance \| none \| none \| frontend-reviewer \| none \|", "\| agent-refactor-safety \| 1 \| create snapshot: broad-agent-refactor \| release blocked: broad-agent-refactor \| broad-agent-refactor \| none \| none \| none \| agent-reviewer \| none \|", "## Task Evidence", "\| Task \| Milestone \| Evaluation \| Owner \| Runtime \| Risk \| Sync hygiene \| Validation \| Review \| Commit \| Release \| Next action \|", "\| frontend-browser-acceptance \| frontend-acceptance \| frontend-acceptance-eval \| frontend-reviewer \| frontend \| normal \| not checked: project path missing \| not recorded \| validation result missing \| validation result missing \| validation required \| validate now \|", "## Task Details", "### broad-agent-refactor", "Milestone: agent-refactor-safety", "Evaluation: agent-safety-eval", "Snapshot: before-broad-agent-refactor; required: True; gate: blocked; naming: aligned - matches task checkpoint convention: before-broad-agent-refactor", "Handoff commands:", "adp workspace task rollback broad-agent-refactor -ManifestPath configs\\workspace.recipes.example.json", "## Maintainer Checklist", "Confirm sync hygiene is clean, covered, not requested, or intentionally reviewed before release", "Commit only after sync hygiene, validation, and human review")

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

Assert-Command `
    -Name "workspace task prepare" `
    -Arguments @("workspace", "task", "prepare", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task prepare: before-large-agent-task", "Task lifecycle output is plan-only", "Preparation checklist:", "adp workspace task snapshot before-large-agent-task")

Assert-Command `
    -Name "workspace task snapshot" `
    -Arguments @("workspace", "task", "snapshot", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task snapshot: before-large-agent-task", "Risk:\s+high", "Snapshot required:\s+True", "Snapshot naming: aligned - matches task checkpoint convention: before-large-agent-task", "Checkpoint:", "snapshot naming \(aligned: matches task checkpoint convention: before-large-agent-task\)", "snapshot-first gate", "adp snapshot create agent before-large-agent-task")

Assert-Command `
    -Name "workspace task run" `
    -Arguments @("workspace", "task", "run", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task run: before-large-agent-task", "Execution boundary:", "Manual execution only: this command does not start an agent", "Snapshot-first gate before broad agent work", "Do not start broad agent work until this gate is ready", "adp workspace task mark before-large-agent-task checkpointed", "ssh adp-os-adp-agent", "Run the agent or task command manually", "adp workspace task mark before-large-agent-task running")

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
    -Patterns @("Workspace task run: broad-agent-refactor", "Manual execution only: this command does not start an agent", "Snapshot-first gate before broad agent work", "BLOCKED: create checkpoint first", "Do not start broad agent work until this gate is ready", "adp snapshot create agent before-broad-agent-refactor")

Assert-Command `
    -Name "workspace task review" `
    -Arguments @("workspace", "task", "review", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task review: before-large-agent-task", "Human review bundle:", "Review decision gate:", "review verdict", "Confirm sync hygiene before review", "sync hygiene \(not checked: project path missing\)", "snapshot-first gate is ready", "rollback: adp workspace task rollback before-large-agent-task", "accept:   withheld until review decision gate is OK", "resolve:  create or explicitly waive the checkpoint", "Commit readiness requires sync hygiene, recorded validation")

Assert-Command `
    -Name "workspace task rollback" `
    -Arguments @("workspace", "task", "rollback", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task rollback: before-large-agent-task", "Rollback boundary:", "Decision context:", "recorded validation: not recorded", "Snapshot rollback is not ready", "Resolve the checkpoint gate before using VM snapshot rollback", "git restore <paths>", "adp workspace task mark before-large-agent-task rollback")

Assert-Command `
    -Name "workspace task commit" `
    -Arguments @("workspace", "task", "commit", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task commit: before-large-agent-task", "Commit boundary:", "Commit commands withheld until commit readiness is OK", "Resolve gate first: create or explicitly waive the checkpoint before commit")

$workspaceState = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-workspace-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
$workspaceBoundaryState = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-workspace-boundary-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
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
        -Patterns @("Workspace task commit: before-large-agent-task", "Commit readiness gate:", "commit readiness \(validation result missing", "Commit commands withheld until commit readiness is OK", "Resolve gate first: run adp workspace task validate before-large-agent-task -Execute before commit")

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
        -Patterns @("Workspace report: recipe-workspace", "Release handoff summary:", "release gate: blocked by validation", "validation passed: 2; failed: 1; missing: 1", "owned: 4; cadence set: 4", "ready for review: docs-copy-edit", "ready to commit: frontend-browser-acceptance", "Governance loop:", "attention queue: .*docs-copy-edit.*review not recorded.*backend-validation-pass.*blocked by validation", "Decision queues:", "ready to commit: frontend-browser-acceptance", "review now: docs-copy-edit", "rollback or revise: backend-validation-pass", "release candidate: frontend-browser-acceptance", "review required: docs-copy-edit", "release blocked: .*backend-validation-pass.*broad-agent-refactor", "Release decision policy:", "decision: release blocked", "blockers: .*backend-validation-pass.*broad-agent-refactor", "review required: docs-copy-edit", "release candidates: frontend-browser-acceptance", "Stale-task remediation:", "backend-validation-pass: owner=backend-reviewer; cadence=per-change; timing=not urgent; action=rollback or revise; release=release blocked", "frontend-browser-acceptance", "project: frontend-app", "owner: frontend-reviewer", "action: ready to commit", "release readiness: release candidate", "validation result: passed at 2026-05-28T00:01:00.0000000Z; project: frontend-app; exit: 0", "commit: commit ready", "docs-copy-edit", "commit: review not recorded", "backend-validation-pass", "failed command: uv run pytest", "commit: blocked by validation", "adp workspace task rollback backend-validation-pass")

    Assert-Command `
        -Name "workspace review shows validation result state" `
        -Arguments @("workspace", "task", "review", "frontend-browser-acceptance", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task review: frontend-browser-acceptance", "review verdict \(validation passed", "recorded validation: passed at 2026-05-28T00:01:00.0000000Z; project: frontend-app; exit: 0", "remote path: /home/adp/workspace/frontend-app", "command count: 2", "state file: .*adp-workspace-validation-state", "accept:   adp workspace task mark frontend-browser-acceptance reviewed")

    Assert-Command `
        -Name "workspace review shows failed validation decision" `
        -Arguments @("workspace", "task", "review", "backend-validation-pass", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task review: backend-validation-pass", "review verdict \(validation failed", "recorded validation: failed at 2026-05-28T00:03:00.0000000Z; project: backend-api; exit: 1", "failed command: uv run pytest", "accept:   withheld until review decision gate is OK", "revise and re-run validation, or use rollback guidance")

    Assert-Command `
        -Name "workspace rollback shows failed validation context" `
        -Arguments @("workspace", "task", "rollback", "backend-validation-pass", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task rollback: backend-validation-pass", "Decision context:", "review verdict \(validation failed", "recorded validation: failed at 2026-05-28T00:03:00.0000000Z; project: backend-api; exit: 1", "failed command: uv run pytest", "git restore <paths>", "adp workspace task mark backend-validation-pass rollback")

    Assert-Command `
        -Name "workspace commit shows readiness when reviewed" `
        -Arguments @("workspace", "task", "commit", "frontend-browser-acceptance", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task commit: frontend-browser-acceptance", "Commit readiness gate:", "commit readiness \(commit ready", "recorded task state: reviewed", "recorded validation: passed at 2026-05-28T00:01:00.0000000Z; project: frontend-app; exit: 0", "git add <paths>", "git commit -m", "adp workspace task mark frontend-browser-acceptance committed")

    Assert-Command `
        -Name "workspace commit blocks missing review state" `
        -Arguments @("workspace", "task", "commit", "docs-copy-edit", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task commit: docs-copy-edit", "Commit readiness gate:", "commit readiness \(review not recorded", "recorded task state: validated", "Commit commands withheld until commit readiness is OK", "Resolve gate first: run adp workspace task review docs-copy-edit")

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
        -Patterns @("Workspace task run: risky-agent-task", "Snapshot-first gate before broad agent work", "BLOCKED: create checkpoint first", "adp snapshot create agent $snapshotName")

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
    -Patterns @("-Execute and -Plan are only supported with: adp workspace task validate <task-name>")

Assert-Command `
    -Name "workspace task validate plan requires execute" `
    -Arguments @("workspace", "task", "validate", "before-large-agent-task", "-Plan", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 1 `
    -Patterns @("-Plan is only supported with -Execute for workspace task validation")

Assert-Command `
    -Name "workspace unknown subcommand" `
    -Arguments @("workspace", "nope", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 1 `
    -Patterns @("Unknown workspace command: nope", "Valid: init, show, plan, status, dashboard, report, recipes, create, open, sync, project, task")

$createWorkspaceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-create-workspace-{0}" -f ([guid]::NewGuid().ToString("N")))
$createProjectPath = Join-Path $createWorkspaceRoot "app"
$createManifest = Join-Path $createWorkspaceRoot "adp-workspace.json"
try {
    New-Item -ItemType Directory -Path $createWorkspaceRoot -Force | Out-Null
    $escapedCreateProject = $createProjectPath.Replace('\', '\\')
    @"
{
  "name": "create-workspace",
  "version": 1,
  "projects": [
    {
      "name": "app",
      "path": "$escapedCreateProject",
      "runtime": "agent",
      "sync": true
    }
  ],
  "tasks": []
}
"@ | Set-Content -LiteralPath $createManifest -Encoding utf8

    Assert-Command `
        -Name "workspace create plan does not create directories" `
        -Arguments @("workspace", "create", "-Plan", "-ManifestPath", $createManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace create: create-workspace", "Plan only: no directories will be created", "status: missing", "Plan summary: 1 directories would be created; 0 already exist")

    if (Test-Path -LiteralPath $createProjectPath) {
        throw "workspace create -Plan created a directory: $createProjectPath"
    }

    Assert-Command `
        -Name "workspace create creates missing project directories only" `
        -Arguments @("workspace", "create", "-ManifestPath", $createManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace create: create-workspace", "Create only: local project directories may be created", "Create summary:", "created: 1", "already existed: 0", "adp workspace status")

    if (-not (Test-Path -LiteralPath $createProjectPath -PathType Container)) {
        throw "workspace create did not create project directory: $createProjectPath"
    }

    Assert-Command `
        -Name "workspace create reports existing project directories" `
        -Arguments @("workspace", "create", "-ManifestPath", $createManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace create: create-workspace", "status: exists", "created: 0", "already existed: 1")
} finally {
    Remove-Item -LiteralPath $createWorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$blockedWorkspaceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-create-blocked-{0}" -f ([guid]::NewGuid().ToString("N")))
$blockedFilePath = Join-Path $blockedWorkspaceRoot "not-a-directory"
$blockedSiblingPath = Join-Path $blockedWorkspaceRoot "should-not-be-created"
$blockedManifest = Join-Path $blockedWorkspaceRoot "adp-workspace.json"
try {
    New-Item -ItemType Directory -Path $blockedWorkspaceRoot -Force | Out-Null
    "not a directory" | Set-Content -LiteralPath $blockedFilePath -Encoding utf8
    $escapedBlockedFile = $blockedFilePath.Replace('\', '\\')
    $escapedBlockedSibling = $blockedSiblingPath.Replace('\', '\\')
    @"
{
  "name": "create-blocked-workspace",
  "version": 1,
  "projects": [
    {
      "name": "file-target",
      "path": "$escapedBlockedFile",
      "runtime": "agent",
      "sync": true
    },
    {
      "name": "sibling",
      "path": "$escapedBlockedSibling",
      "runtime": "agent",
      "sync": true
    }
  ],
  "tasks": []
}
"@ | Set-Content -LiteralPath $blockedManifest -Encoding utf8

    Assert-Command `
        -Name "workspace create blocks invalid project paths before creation" `
        -Arguments @("workspace", "create", "-ManifestPath", $blockedManifest) `
        -ExitCode 1 `
        -Patterns @("Workspace create: create-blocked-workspace", "path exists and is not a directory", "Create blocked: fix invalid project paths before creating workspace directories")

    if (Test-Path -LiteralPath $blockedSiblingPath) {
        throw "workspace create created a sibling directory after an invalid path: $blockedSiblingPath"
    }
} finally {
    Remove-Item -LiteralPath $blockedWorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$workspaceManifest = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-workspace-test-{0}.json" -f ([guid]::NewGuid().ToString("N")))
try {
    Assert-Command `
        -Name "workspace init temp manifest" `
        -Arguments @("workspace", "init", "-ManifestPath", $workspaceManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace manifest created:", "Edit project paths")

    if (-not (Test-Path -LiteralPath $workspaceManifest)) {
        throw "workspace init did not create manifest: $workspaceManifest"
    }

    Get-Content -LiteralPath $workspaceManifest -Raw | ConvertFrom-Json | Out-Null
} finally {
    Remove-Item -LiteralPath $workspaceManifest -Force -ErrorAction SilentlyContinue
}

$incompleteWorkspaceManifest = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-workspace-incomplete-{0}.json" -f ([guid]::NewGuid().ToString("N")))
try {
    @"
{
  "name": "incomplete-workspace",
  "version": 1,
  "projects": [
    {
      "name": "app",
      "path": "app",
      "sync": true
    }
  ]
}
"@ | Set-Content -LiteralPath $incompleteWorkspaceManifest -Encoding utf8

    Assert-Command `
        -Name "workspace status incomplete manifest" `
        -Arguments @("workspace", "status", "-ManifestPath", $incompleteWorkspaceManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace readiness: incomplete-workspace", "runtime \(missing\)", "sync \(blocked: missing runtime\)", "validation commands \(none configured\)")
} finally {
    Remove-Item -LiteralPath $incompleteWorkspaceManifest -Force -ErrorAction SilentlyContinue
}

$devContainerWorkspaceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-devcontainer-workspace-{0}" -f ([guid]::NewGuid().ToString("N")))
$devContainerProject = Join-Path $devContainerWorkspaceRoot "app"
$devContainerManifest = Join-Path $devContainerWorkspaceRoot "adp-workspace.json"
try {
    New-Item -ItemType Directory -Path (Join-Path $devContainerProject ".devcontainer") -Force | Out-Null
    '{"name":"adp-test"}' | Set-Content -LiteralPath (Join-Path (Join-Path $devContainerProject ".devcontainer") "devcontainer.json") -Encoding utf8
    $escapedProjectPath = ($devContainerProject -replace '\\', '\\')
    @"
{
  "name": "devcontainer-workspace",
  "version": 1,
  "projects": [
    {
      "name": "app",
      "path": "$escapedProjectPath",
      "runtime": "agent",
      "sync": true,
      "devcontainer": "optional",
      "validation": [
        "git status --short"
      ]
    }
  ],
  "tasks": []
}
"@ | Set-Content -LiteralPath $devContainerManifest -Encoding utf8

    Assert-Command `
        -Name "workspace show detects devcontainer metadata" `
        -Arguments @("workspace", "show", "-ManifestPath", $devContainerManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace: devcontainer-workspace", "devcontainer: found - \.devcontainer/devcontainer\.json", "sync hygiene: clean - no common generated directories found")

    Assert-Command `
        -Name "workspace status detects devcontainer metadata" `
        -Arguments @("workspace", "status", "-ManifestPath", $devContainerManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace readiness: devcontainer-workspace", "devcontainer \(found: \.devcontainer/devcontainer\.json\)", "validation commands \(1 configured\)")

    Assert-Command `
        -Name "workspace dashboard detects devcontainer metadata" `
        -Arguments @("workspace", "dashboard", "-ManifestPath", $devContainerManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace dashboard: devcontainer-workspace", "sync hygiene: clean", "devcontainer: found")
} finally {
    Remove-Item -LiteralPath $devContainerWorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$syncHygieneWorkspaceRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-sync-hygiene-workspace-{0}" -f ([guid]::NewGuid().ToString("N")))
$syncHygieneProject = Join-Path $syncHygieneWorkspaceRoot "app"
$syncHygieneManifest = Join-Path $syncHygieneWorkspaceRoot "adp-workspace.json"
try {
    New-Item -ItemType Directory -Path (Join-Path $syncHygieneProject "node_modules") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $syncHygieneProject ".venv") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $syncHygieneProject ".pytest_cache") -Force | Out-Null
    $escapedProjectPath = ($syncHygieneProject -replace '\\', '\\')
    @"
{
  "name": "sync-hygiene-workspace",
  "version": 1,
  "projects": [
    {
      "name": "app",
      "path": "$escapedProjectPath",
      "runtime": "agent",
      "sync": true,
      "validation": [
        "git status --short"
      ]
    }
  ],
  "tasks": []
}
"@ | Set-Content -LiteralPath $syncHygieneManifest -Encoding utf8

    Assert-Command `
        -Name "workspace status reports sync hygiene coverage" `
        -Arguments @("workspace", "status", "-ManifestPath", $syncHygieneManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace readiness: sync-hygiene-workspace", "sync hygiene \(covered: generated directories ignored by sync profile 'agent': .*node_modules.*\.venv.*\.pytest_cache\)")

    Assert-Command `
        -Name "workspace dashboard reports sync hygiene coverage" `
        -Arguments @("workspace", "dashboard", "-ManifestPath", $syncHygieneManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace dashboard: sync-hygiene-workspace", "sync hygiene: covered")
} finally {
    Remove-Item -LiteralPath $syncHygieneWorkspaceRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$syncHygieneWarningRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-sync-hygiene-warning-{0}" -f ([guid]::NewGuid().ToString("N")))
$syncHygieneWarningProject = Join-Path $syncHygieneWarningRoot "app"
$syncHygieneWarningManifest = Join-Path $syncHygieneWarningRoot "adp-workspace.json"
$syncHygieneWarningState = Join-Path $syncHygieneWarningRoot "adp-workspace.state.json"
try {
    New-Item -ItemType Directory -Path (Join-Path $syncHygieneWarningProject ".tox") -Force | Out-Null
    $escapedProjectPath = ($syncHygieneWarningProject -replace '\\', '\\')
    @"
{
  "name": "sync-hygiene-warning-workspace",
  "version": 1,
  "projects": [
    {
      "name": "app",
      "path": "$escapedProjectPath",
      "runtime": "agent",
      "sync": true,
      "validation": [
        "git status --short"
      ]
    }
  ],
  "tasks": [
    {
      "name": "sync-risk-task",
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
"@ | Set-Content -LiteralPath $syncHygieneWarningManifest -Encoding utf8

    @"
{
  "version": 1,
  "tasks": [
    {
      "name": "sync-risk-task",
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
"@ | Set-Content -LiteralPath $syncHygieneWarningState -Encoding utf8

    Assert-Command `
        -Name "workspace status warns on sync hygiene gaps" `
        -Arguments @("workspace", "status", "-ManifestPath", $syncHygieneWarningManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace readiness: sync-hygiene-warning-workspace", "sync hygiene \(review ignore: not ignored by sync profile 'agent': \.tox\)")

    Assert-Command `
        -Name "workspace dashboard warns on sync hygiene gaps" `
        -Arguments @("workspace", "dashboard", "-ManifestPath", $syncHygieneWarningManifest) `
        -ExitCode 0 `
        -Patterns @("Workspace dashboard: sync-hygiene-warning-workspace", "sync hygiene: review ignore", "commit: blocked by sync hygiene")

    Assert-Command `
        -Name "workspace report blocks release on sync hygiene gaps" `
        -Arguments @("workspace", "report", "-ManifestPath", $syncHygieneWarningManifest, "-StatePath", $syncHygieneWarningState) `
        -ExitCode 0 `
        -Patterns @("Workspace report: sync-hygiene-warning-workspace", "release gate: blocked by sync hygiene", "blocked tasks: sync-risk-task", "attention queue: sync-risk-task \[sync hygiene: review ignore", "review sync ignore: sync-risk-task", "decision: release blocked", "blockers: sync-risk-task", "sync-risk-task: owner=platform-maintainer; cadence=per-change; timing=not urgent; action=review sync ignore; release=release blocked", "sync hygiene: review ignore - not ignored by sync profile 'agent': \.tox", "release readiness: release blocked", "review: blocked by sync hygiene", "commit: blocked by sync hygiene")

    Assert-Command `
        -Name "workspace report markdown blocks release on sync hygiene gaps" `
        -Arguments @("workspace", "report", "-Markdown", "-ManifestPath", $syncHygieneWarningManifest, "-StatePath", $syncHygieneWarningState) `
        -ExitCode 0 `
        -Patterns @("# Workspace Release Evidence: sync-hygiene-warning-workspace", "\| Decision \| release blocked \|", "\| Blockers \| sync-risk-task \|", "\| Action: review sync ignore \| sync-risk-task \|", "\| Release: release blocked \| sync-risk-task \|", "## Evaluation Queue", "No evaluations are configured", "## Milestone Checkpoints", "No milestones are configured", "\| Task \| Milestone \| Evaluation \| Owner \| Runtime \| Risk \| Sync hygiene \|", "\| sync-risk-task \| not set \| not set \| platform-maintainer \| agent \| normal \| review ignore: not ignored by sync profile 'agent': \.tox \|", "review ignore: not ignored by sync profile 'agent': \.tox", "- Evaluation: not set", "- Sync hygiene: review ignore - not ignored by sync profile 'agent': \.tox")

    Assert-Command `
        -Name "workspace task review blocks sync hygiene gaps" `
        -Arguments @("workspace", "task", "review", "sync-risk-task", "-ManifestPath", $syncHygieneWarningManifest, "-StatePath", $syncHygieneWarningState) `
        -ExitCode 0 `
        -Patterns @("Workspace task review: sync-risk-task", "review verdict \(blocked by sync hygiene", "sync hygiene \(review ignore: not ignored by sync profile 'agent': \.tox\)", "Review should not accept the task until sync hygiene is reviewed or the runtime sync profile is updated", "accept:   withheld until review decision gate is OK", "resolve:  review sync ignore before accepting the task", "Commit readiness requires sync hygiene, recorded validation")

    Assert-Command `
        -Name "workspace task commit blocks sync hygiene gaps" `
        -Arguments @("workspace", "task", "commit", "sync-risk-task", "-ManifestPath", $syncHygieneWarningManifest, "-StatePath", $syncHygieneWarningState) `
        -ExitCode 0 `
        -Patterns @("Workspace task commit: sync-risk-task", "commit readiness \(blocked by sync hygiene", "sync hygiene: review ignore - not ignored by sync profile 'agent': \.tox", "Commit commands withheld until commit readiness is OK", "Resolve gate first: review sync ignore before commit")

    Assert-Command `
        -Name "workspace task rollback shows sync hygiene context" `
        -Arguments @("workspace", "task", "rollback", "sync-risk-task", "-ManifestPath", $syncHygieneWarningManifest, "-StatePath", $syncHygieneWarningState) `
        -ExitCode 0 `
        -Patterns @("Workspace task rollback: sync-risk-task", "Decision context:", "review verdict \(blocked by sync hygiene", "sync hygiene: review ignore - not ignored by sync profile 'agent': \.tox", "recorded validation: passed at 2026-05-29T00:00:10.0000000Z; project: app; exit: 0", "git restore <paths>", "adp workspace task mark sync-risk-task rollback")
} finally {
    Remove-Item -LiteralPath $syncHygieneWarningRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Assert-Command `
    -Name "logs unknown runtime" `
    -Arguments @("logs", "not-a-runtime") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent")

Assert-Command `
    -Name "destroy plan unknown runtime" `
    -Arguments @("destroy", "not-a-runtime", "-Plan") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime")

Write-Output "CLI smoke tests OK"
