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
    -Name "workspace status example manifest" `
    -Arguments @("workspace", "status", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace readiness: example-project", "Status only: no projects will be cloned", "Manifest:", "Projects:", "runtime agent", "validation commands")

Assert-Command `
    -Name "workspace task prepare" `
    -Arguments @("workspace", "task", "prepare", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task prepare: before-large-agent-task", "Task lifecycle output is plan-only", "Preparation checklist:", "adp workspace task snapshot before-large-agent-task")

Assert-Command `
    -Name "workspace task snapshot" `
    -Arguments @("workspace", "task", "snapshot", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task snapshot: before-large-agent-task", "Checkpoint:", "adp snapshot create agent before-large-agent-task")

Assert-Command `
    -Name "workspace task validate" `
    -Arguments @("workspace", "task", "validate", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task validate: before-large-agent-task", "Validation plan:", "git status --short", "pnpm test")

Assert-Command `
    -Name "workspace task review" `
    -Arguments @("workspace", "task", "review", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 0 `
    -Patterns @("Workspace task review: before-large-agent-task", "Human review bundle:", "rollback, revise, or commit")

Assert-Command `
    -Name "workspace task unknown task" `
    -Arguments @("workspace", "task", "prepare", "not-a-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 1 `
    -Patterns @("Workspace task not found: not-a-task", "Available tasks: before-large-agent-task")

Assert-Command `
    -Name "workspace task unknown command" `
    -Arguments @("workspace", "task", "deploy", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 1 `
    -Patterns @("Unknown workspace task command: deploy", "Valid: prepare, snapshot, validate, review")

Assert-Command `
    -Name "workspace unknown subcommand" `
    -Arguments @("workspace", "nope", "-ManifestPath", "configs\workspace.example.json") `
    -ExitCode 1 `
    -Patterns @("Unknown workspace command: nope", "Valid: init, show, plan, status, task")

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
