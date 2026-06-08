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
        -Patterns @("Workspace create: create-workspace", "Create only: local project directories may be created", "Create summary:", "created: 1", "already existed: 0", "adpos workspace status")

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
        -Patterns @("Workspace task rollback: sync-risk-task", "Decision context:", "review verdict \(blocked by sync hygiene", "sync hygiene: review ignore - not ignored by sync profile 'agent': \.tox", "recorded validation: passed at 2026-05-29T00:00:10.0000000Z; project: app; exit: 0", "git restore <paths>", "adpos workspace task mark sync-risk-task rollback")
} finally {
    Remove-Item -LiteralPath $syncHygieneWarningRoot -Recurse -Force -ErrorAction SilentlyContinue
}
