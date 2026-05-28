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
    -Patterns @("ADP-OS CLI", "adp up <runtime>")

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
    -Patterns @("Mutagen remediation:", "Plan only: no files will be downloaded", "mutagen_windows_amd64_v0\.18\.1\.zip", "\.tools\\mutagen\\mutagen\.exe", "To install: \.\\cli\\adp\.ps1 doctor -FixMutagen")

Assert-Command `
    -Name "doctor reports VMware NAT prerequisites" `
    -Arguments @("doctor", "-FixMutagen", "-Plan") `
    -ExitCode 0 `
    -Patterns @("VMware NAT config", "VMware NAT gateway range", "VMware NAT prerequisites", "Virtual Network Editor")

Assert-Command `
    -Name "workspace show example manifest" `
    -Arguments @("workspace", "show", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace: example-project", "Projects:", "app:\s+app -> agent")

Assert-Command `
    -Name "workspace plan example manifest" `
    -Arguments @("workspace", "plan", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Plan only: no projects will be cloned", "adp up agent -Plan", "adp snapshot create agent before-large-agent-task")

Assert-Command `
    -Name "workspace show recipes manifest" `
    -Arguments @("workspace", "show", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace: recipe-workspace", "frontend-app:\s+frontend-app -> frontend", "backend-api:\s+backend-api -> backend", "agent-workspace:\s+agent-workspace -> agent")

Assert-Command `
    -Name "workspace plan recipes manifest" `
    -Arguments @("workspace", "plan", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Plan only: no projects will be cloned", "adp up frontend -Plan", "adp up backend -Plan", "adp up agent -Plan", "adp snapshot create agent before-broad-agent-refactor")

Assert-Command `
    -Name "workspace status example manifest" `
    -Arguments @("workspace", "status", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace readiness: example-project", "Status only: no projects will be cloned", "Manifest:", "Projects:", "runtime agent", "risk \(high; requires snapshot: True\)", "snapshot-first gate", "validation commands")

Assert-Command `
    -Name "workspace dashboard example manifest" `
    -Arguments @("workspace", "dashboard", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace dashboard: example-project", "Dashboard only: no projects will be cloned", "Project readiness:", "Task lifecycle:", "snapshot required: True", "checkpoint:", "execution:", "rollback:", "commit:")

Assert-Command `
    -Name "workspace dashboard recipes manifest" `
    -Arguments @("workspace", "dashboard", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace dashboard: recipe-workspace", "frontend-browser-acceptance", "backend-validation-pass", "broad-agent-refactor", "snapshot required: True", "execution: blocked by snapshot gate")

Assert-Command `
    -Name "workspace report recipes manifest" `
    -Arguments @("workspace", "report", "-ManifestPath", "configs\workspace.recipes.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace report: recipe-workspace", "Report only: no projects will be cloned", "Release handoff summary:", "release gate: blocked by snapshot gate", "blocked tasks: .*frontend-browser-acceptance.*backend-validation-pass.*broad-agent-refactor", "Task reports:", "frontend-browser-acceptance", "review bundle:", "project: frontend-app", "runtime: frontend", "validation commands: 2", "validation result: not recorded", "review: validation result missing", "commit: validation result missing", "checklist:", "validation: confirm the latest recorded result", "source: inspect git status", "rollback: confirm the VM checkpoint", "commit: commit only after validation", "handoff:", "adp workspace task review frontend-browser-acceptance", "inspect:  git status --short; git diff --stat; git diff")

Assert-Command `
    -Name "workspace task prepare" `
    -Arguments @("workspace", "task", "prepare", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task prepare: before-large-agent-task", "Task lifecycle output is plan-only", "Preparation checklist:", "adp workspace task snapshot before-large-agent-task")

Assert-Command `
    -Name "workspace task snapshot" `
    -Arguments @("workspace", "task", "snapshot", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task snapshot: before-large-agent-task", "Risk:\s+high", "Snapshot required:\s+True", "Checkpoint:", "snapshot-first gate", "adp snapshot create agent before-large-agent-task")

Assert-Command `
    -Name "workspace task run" `
    -Arguments @("workspace", "task", "run", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task run: before-large-agent-task", "Execution boundary:", "Snapshot-first gate before broad agent work", "adp workspace task mark before-large-agent-task checkpointed", "ssh adp-os-adp-agent", "Run the agent or task command manually")

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
    -Patterns @("Workspace task run: broad-agent-refactor", "Snapshot-first gate before broad agent work", "BLOCKED: create checkpoint first", "adp snapshot create agent before-broad-agent-refactor")

Assert-Command `
    -Name "workspace task review" `
    -Arguments @("workspace", "task", "review", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task review: before-large-agent-task", "Human review bundle:", "Review decision gate:", "review verdict", "snapshot-first gate is ready", "rollback: adp workspace task rollback before-large-agent-task")

Assert-Command `
    -Name "workspace task rollback" `
    -Arguments @("workspace", "task", "rollback", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task rollback: before-large-agent-task", "Rollback boundary:", "Decision context:", "recorded validation: not recorded", "adp restore agent before-large-agent-task", "git restore <paths>")

Assert-Command `
    -Name "workspace task commit" `
    -Arguments @("workspace", "task", "commit", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task commit: before-large-agent-task", "Commit boundary:", "git add <paths>", "git commit -m")

$workspaceState = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-workspace-state-{0}.json" -f ([guid]::NewGuid().ToString("N")))
try {
    Assert-Command `
        -Name "workspace task mark" `
        -Arguments @("workspace", "task", "mark", "before-large-agent-task", "prepared", "-ManifestPath", "configs\workspace.example.json", "-StatePath", $workspaceState) `
        -ExitCode 0 `
        -Patterns @("Workspace task mark: before-large-agent-task", "Recorded local lifecycle state only", "State:\s+prepared")

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
        -Patterns @("Workspace report: example-project", "Release handoff summary:", "release gate: blocked by snapshot gate", "blocked tasks: before-large-agent-task", "state: prepared", "review bundle:", "project: not set", "checkpoint: before-large-agent-task", "validation result: not recorded", "commit: blocked by snapshot gate", "checklist:")
} finally {
    Remove-Item -LiteralPath $workspaceState -Force -ErrorAction SilentlyContinue
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
        -Patterns @("Workspace dashboard: recipe-workspace", "frontend-browser-acceptance", "state: reviewed at", "validation result: passed at 2026-05-28T00:01:00.0000000Z; project: frontend-app; exit: 0", "docs-copy-edit", "commit: blocked by review", "backend-validation-pass", "commit: blocked by validation")

    Assert-Command `
        -Name "workspace report shows validation result state" `
        -Arguments @("workspace", "report", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace report: recipe-workspace", "Release handoff summary:", "release gate: blocked by validation", "validation passed: 2; failed: 1; missing: 1", "ready for review: docs-copy-edit", "ready to commit: frontend-browser-acceptance", "frontend-browser-acceptance", "project: frontend-app", "validation result: passed at 2026-05-28T00:01:00.0000000Z; project: frontend-app; exit: 0", "commit: commit ready", "docs-copy-edit", "commit: review not recorded", "backend-validation-pass", "failed command: uv run pytest", "commit: blocked by validation", "adp workspace task rollback backend-validation-pass")

    Assert-Command `
        -Name "workspace review shows validation result state" `
        -Arguments @("workspace", "task", "review", "frontend-browser-acceptance", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task review: frontend-browser-acceptance", "review verdict \(validation passed", "recorded validation: passed at 2026-05-28T00:01:00.0000000Z; project: frontend-app; exit: 0", "remote path: /home/adp/workspace/frontend-app", "command count: 2", "state file: .*adp-workspace-validation-state")

    Assert-Command `
        -Name "workspace review shows failed validation decision" `
        -Arguments @("workspace", "task", "review", "backend-validation-pass", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task review: backend-validation-pass", "review verdict \(validation failed", "recorded validation: failed at 2026-05-28T00:03:00.0000000Z; project: backend-api; exit: 1", "failed command: uv run pytest", "revise and re-run validation, or use rollback guidance")

    Assert-Command `
        -Name "workspace rollback shows failed validation context" `
        -Arguments @("workspace", "task", "rollback", "backend-validation-pass", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task rollback: backend-validation-pass", "Decision context:", "review verdict \(validation failed", "recorded validation: failed at 2026-05-28T00:03:00.0000000Z; project: backend-api; exit: 1", "failed command: uv run pytest", "git restore <paths>")

    Assert-Command `
        -Name "workspace commit shows readiness when reviewed" `
        -Arguments @("workspace", "task", "commit", "frontend-browser-acceptance", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task commit: frontend-browser-acceptance", "Commit readiness gate:", "commit readiness \(commit ready", "recorded task state: reviewed", "recorded validation: passed at 2026-05-28T00:01:00.0000000Z; project: frontend-app; exit: 0", "git add <paths>", "git commit -m")

    Assert-Command `
        -Name "workspace commit blocks missing review state" `
        -Arguments @("workspace", "task", "commit", "docs-copy-edit", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task commit: docs-copy-edit", "Commit readiness gate:", "commit readiness \(review not recorded", "recorded task state: validated", "run adp workspace task review docs-copy-edit")

    Assert-Command `
        -Name "workspace commit blocks failed validation" `
        -Arguments @("workspace", "task", "commit", "backend-validation-pass", "-ManifestPath", "configs\workspace.recipes.example.json", "-StatePath", $workspaceValidationState) `
        -ExitCode 0 `
        -Patterns @("Workspace task commit: backend-validation-pass", "Commit readiness gate:", "commit readiness \(blocked by validation", "recorded task state: validation_failed", "failed command: uv run pytest")
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
    -Patterns @("Unknown workspace command: nope", "Valid: init, show, plan, status, dashboard, report, task")

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

