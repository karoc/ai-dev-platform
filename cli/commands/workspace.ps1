# ADP-OS Workspace Command
# Non-destructive workspace manifest helpers.

param(
    [string]$SubCommand,
    [string]$TaskCommand,
    [string]$TaskName,
    [string]$TaskState,
    [string]$ManifestPath = "adp-workspace.json",
    [string]$StatePath
)

$ErrorActionPreference = "Stop"

function Show-WorkspaceUsage {
    Write-ErrorLog -Message "Usage: adp workspace <init|show|plan|status|dashboard|task> [-ManifestPath <path>]" -Component "cli.workspace"
    Write-Host "  adp workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name> [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-Host "  adp workspace task mark <task-name> <prepared|checkpointed|running|validated|reviewed|rollback|committed> [-StatePath <path>]" -ForegroundColor DarkGray
}

function Read-WorkspaceManifest {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Workspace manifest not found: $Path. Run: adp workspace init"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Workspace manifest is empty: $Path"
    }

    return $raw | ConvertFrom-Json
}

function Get-WorkspaceArray {
    param([object]$Value)

    if ($null -eq $Value) {
        return @()
    }

    return @($Value)
}

function Resolve-WorkspaceStatePath {
    param([string]$Path)

    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    return (Join-Path (Get-ProjectRoot) "adp-workspace.state.json")
}

function Read-WorkspaceState {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            version = 1
            tasks   = @()
        }
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{
            version = 1
            tasks   = @()
        }
    }

    $state = $raw | ConvertFrom-Json
    if (-not ($state.PSObject.Properties.Name -contains "tasks")) {
        $state | Add-Member -NotePropertyName "tasks" -NotePropertyValue @()
    }

    return $state
}

function Write-WorkspaceState {
    param(
        [object]$State,
        [string]$Path
    )

    $parent = Split-Path -Path $Path -Parent
    if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $State | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Get-WorkspaceTaskState {
    param(
        [object]$State,
        [string]$TaskName
    )

    foreach ($taskState in (Get-WorkspaceArray $State.tasks)) {
        if ($taskState.name -eq $TaskName) {
            return $taskState
        }
    }

    return $null
}

function Get-WorkspaceTaskRisk {
    param([object]$Task)

    if ($Task.PSObject.Properties.Name -contains "risk" -and -not [string]::IsNullOrWhiteSpace([string]$Task.risk)) {
        return ([string]$Task.risk).ToLowerInvariant()
    }

    return "normal"
}

function Test-WorkspaceTaskRequiresSnapshot {
    param([object]$Task)

    if ($Task.PSObject.Properties.Name -contains "requires_snapshot") {
        return [bool]$Task.requires_snapshot
    }

    $risk = Get-WorkspaceTaskRisk -Task $Task
    return ($risk -in @("high", "broad", "destructive", "uncertain"))
}

function Get-WorkspaceSnapshotGate {
    param(
        [object]$Task,
        [object]$SnapshotStatus = $null
    )

    $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $Task
    if (-not $requiresSnapshot) {
        return [pscustomobject]@{
            Level    = "INFO"
            Status   = "optional"
            Detail   = "task does not require a snapshot gate"
            Blocking = $false
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$Task.runtime) -or [string]::IsNullOrWhiteSpace([string]$Task.snapshot)) {
        return [pscustomobject]@{
            Level    = "FAIL"
            Status   = "blocked"
            Detail   = "set tasks[].runtime and tasks[].snapshot"
            Blocking = $true
        }
    }

    if ($null -eq $SnapshotStatus) {
        $SnapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    }

    if ($SnapshotStatus.Level -eq "OK") {
        return [pscustomobject]@{
            Level    = "OK"
            Status   = "ready"
            Detail   = "checkpoint present: $($Task.snapshot)"
            Blocking = $false
        }
    }

    return [pscustomobject]@{
        Level    = "WARN"
        Status   = "blocked"
        Detail   = "create checkpoint first: adp snapshot create $($Task.runtime) $($Task.snapshot)"
        Blocking = $true
    }
}

function Set-WorkspaceTaskState {
    param(
        [object]$State,
        [string]$TaskName,
        [string]$StateName
    )

    $tasks = [System.Collections.Generic.List[object]]::new()
    $updated = $false
    $timestamp = (Get-Date).ToUniversalTime().ToString("o")

    foreach ($taskState in (Get-WorkspaceArray $State.tasks)) {
        if ($taskState.name -eq $TaskName) {
            $taskState.state = $StateName
            $taskState.updated_at = $timestamp
            $updated = $true
        }
        $tasks.Add($taskState) | Out-Null
    }

    if (-not $updated) {
        $tasks.Add([pscustomobject]@{
            name       = $TaskName
            state      = $StateName
            updated_at = $timestamp
        }) | Out-Null
    }

    $State.tasks = @($tasks.ToArray())
    $State | Add-Member -NotePropertyName "updated_at" -NotePropertyValue $timestamp -Force
    return $State
}

function Write-WorkspaceSummary {
    param([object]$Manifest)

    Write-Host "Workspace: $($Manifest.name)" -ForegroundColor Cyan
    if ($Manifest.description) {
        Write-Host "  $($Manifest.description)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Projects:" -ForegroundColor Yellow
    foreach ($project in (Get-WorkspaceArray $Manifest.projects)) {
        $runtime = if ($project.runtime) { $project.runtime } else { "not configured" }
        $sync = if ($null -ne $project.sync) { $project.sync } else { "not configured" }
        Write-Host "  - $($project.name): $($project.path) -> $runtime (sync: $sync)" -ForegroundColor DarkGray
        foreach ($command in (Get-WorkspaceArray $project.validation)) {
            Write-Host "      validate: $command" -ForegroundColor DarkGray
        }
    }

    if ($Manifest.tasks) {
        Write-Host ""
        Write-Host "Tasks:" -ForegroundColor Yellow
        foreach ($task in (Get-WorkspaceArray $Manifest.tasks)) {
            $runtime = if ($task.runtime) { $task.runtime } else { "not configured" }
            $snapshot = if ($task.snapshot) { $task.snapshot } else { "not configured" }
            Write-Host "  - $($task.name): runtime=$runtime snapshot=$snapshot" -ForegroundColor DarkGray
            foreach ($command in (Get-WorkspaceArray $task.validation)) {
                Write-Host "      validate: $command" -ForegroundColor DarkGray
            }
        }
    }
}

function Write-WorkspaceCheck {
    param(
        [string]$Level,
        [string]$Name,
        [string]$Detail = ""
    )

    $color = switch ($Level) {
        "OK" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "DarkGray" }
    }

    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { "" } else { " $Detail" }
    Write-Host "  [$Level] $Name$suffix" -ForegroundColor $color
}

function Resolve-ProjectWorkspacePath {
    param([object]$Project)

    if (-not $Project.path) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted([string]$Project.path)) {
        return [string]$Project.path
    }

    if ($Project.runtime -and (Test-RuntimeExists $Project.runtime)) {
        $runtime = Get-RuntimeConfig $Project.runtime
        $workspaceRoot = Resolve-Path "workspace_root"
        return (Join-Path (Join-Path $workspaceRoot $runtime.workspace) $Project.path)
    }

    return [System.IO.Path]::GetFullPath($Project.path)
}

function Get-RuntimeVmxPath {
    param([string]$RuntimeName)

    $vmStore = Resolve-Path "vm_store"
    $vmName = "adp-$RuntimeName"
    return (Join-Path $vmStore "$vmName\$vmName.vmx")
}

function Get-WorkspaceRuntimeStatus {
    param([string]$RuntimeName)

    if ([string]::IsNullOrWhiteSpace($RuntimeName)) {
        return [pscustomobject]@{
            Level  = "FAIL"
            Status = "missing runtime"
            Detail = "Set projects[].runtime"
        }
    }

    if (-not (Test-RuntimeExists $RuntimeName)) {
        return [pscustomobject]@{
            Level  = "FAIL"
            Status = "unknown runtime"
            Detail = "Valid: $((Get-AllRuntimeNames) -join ', ')"
        }
    }

    $vmxPath = Get-RuntimeVmxPath -RuntimeName $RuntimeName
    if (-not (Test-Path -LiteralPath $vmxPath)) {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "not created"
            Detail = "Run: adp up $RuntimeName -Plan"
        }
    }

    if (-not (Test-VMwareAvailable)) {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "created, status unknown"
            Detail = "vmrun.exe unavailable"
        }
    }

    try {
        Initialize-VMware | Out-Null
        $status = Get-VMStatus $vmxPath
        $level = if ($status -match "running") { "OK" } else { "WARN" }
        return [pscustomobject]@{
            Level  = $level
            Status = $status
            Detail = $vmxPath
        }
    } catch {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "status unavailable"
            Detail = "$_"
        }
    }
}

function Get-WorkspaceSyncStatus {
    param(
        [string]$RuntimeName,
        [bool]$Expected
    )

    if (-not $Expected) {
        return [pscustomobject]@{
            Level  = "INFO"
            Status = "not requested"
            Detail = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($RuntimeName)) {
        return [pscustomobject]@{
            Level  = "FAIL"
            Status = "blocked"
            Detail = "missing runtime"
        }
    }

    if (-not (Test-RuntimeExists $RuntimeName)) {
        return [pscustomobject]@{
            Level  = "FAIL"
            Status = "blocked"
            Detail = "unknown runtime"
        }
    }

    . (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")
    $mutagenPath = Find-Mutagen -ProjectRoot (Get-ProjectRoot)
    if (-not $mutagenPath) {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "unknown"
            Detail = "Mutagen not installed"
        }
    }

    try {
        Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
        $sessionName = "adp-$RuntimeName"
        if (Test-SyncSessionExists -SessionName $sessionName) {
            return [pscustomobject]@{
                Level  = "OK"
                Status = "session present"
                Detail = $sessionName
            }
        }

        return [pscustomobject]@{
            Level  = "WARN"
            Status = "not started"
            Detail = "Run: adp sync start $RuntimeName"
        }
    } catch {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "status unavailable"
            Detail = "$_"
        }
    }
}

function Get-WorkspaceSnapshotStatus {
    param(
        [string]$RuntimeName,
        [string]$SnapshotName
    )

    if ([string]::IsNullOrWhiteSpace($RuntimeName) -or [string]::IsNullOrWhiteSpace($SnapshotName)) {
        return [pscustomobject]@{
            Level  = "INFO"
            Status = "not configured"
            Detail = ""
        }
    }

    if (-not (Test-RuntimeExists $RuntimeName)) {
        return [pscustomobject]@{
            Level  = "FAIL"
            Status = "blocked"
            Detail = "unknown runtime"
        }
    }

    $vmxPath = Get-RuntimeVmxPath -RuntimeName $RuntimeName
    if (-not (Test-Path -LiteralPath $vmxPath)) {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "not available"
            Detail = "VM not created"
        }
    }

    if (-not (Test-VMwareAvailable)) {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "unknown"
            Detail = "vmrun.exe unavailable"
        }
    }

    try {
        Initialize-VMware | Out-Null
        $snapshots = @(List-VMSnapshots -VmxPath $vmxPath)
        if ($snapshots -contains $SnapshotName) {
            return [pscustomobject]@{
                Level  = "OK"
                Status = "present"
                Detail = $SnapshotName
            }
        }

        return [pscustomobject]@{
            Level  = "WARN"
            Status = "recommended"
            Detail = "Run: adp snapshot create $RuntimeName $SnapshotName"
        }
    } catch {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "status unavailable"
            Detail = "$_"
        }
    }
}

function Write-WorkspaceStatus {
    param([object]$Manifest)

    Write-Host "Workspace readiness: $($Manifest.name)" -ForegroundColor Cyan
    Write-Host "Status only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, and no validation commands will be run." -ForegroundColor DarkGray

    $projects = Get-WorkspaceArray $Manifest.projects
    $tasks = Get-WorkspaceArray $Manifest.tasks
    $projectCount = $projects.Count
    $taskCount = $tasks.Count
    Write-Host ""
    Write-Host "Manifest:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "manifest loaded" -Detail "(projects: $projectCount, tasks: $taskCount)"
    if ($Manifest.version) {
        Write-WorkspaceCheck -Level "OK" -Name "manifest version" -Detail "($($Manifest.version))"
    } else {
        Write-WorkspaceCheck -Level "WARN" -Name "manifest version" -Detail "(missing)"
    }

    Write-Host ""
    Write-Host "Projects:" -ForegroundColor Yellow
    if ($projectCount -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "projects" -Detail "(none configured)"
    }

    foreach ($project in $projects) {
        $projectName = if ($project.name) { $project.name } else { "(unnamed)" }
        Write-Host "  - $projectName" -ForegroundColor DarkGray

        if (-not $project.path) {
            Write-WorkspaceCheck -Level "FAIL" -Name "project path" -Detail "(missing)"
        } else {
            $projectPath = Resolve-ProjectWorkspacePath -Project $project
            $pathLevel = if (Test-Path -LiteralPath $projectPath) { "OK" } else { "WARN" }
            $pathStatus = if ($pathLevel -eq "OK") { "exists" } else { "missing" }
            Write-WorkspaceCheck -Level $pathLevel -Name "project path" -Detail ("({0}: {1})" -f $pathStatus, $projectPath)
        }

        if (-not $project.runtime) {
            Write-WorkspaceCheck -Level "FAIL" -Name "runtime" -Detail "(missing)"
        } else {
            $runtimeStatus = Get-WorkspaceRuntimeStatus -RuntimeName $project.runtime
            Write-WorkspaceCheck -Level $runtimeStatus.Level -Name "runtime $($project.runtime)" -Detail "($($runtimeStatus.Status): $($runtimeStatus.Detail))"
        }

        $syncExpected = ($null -ne $project.sync -and [bool]$project.sync)
        $syncStatus = Get-WorkspaceSyncStatus -RuntimeName $project.runtime -Expected $syncExpected
        Write-WorkspaceCheck -Level $syncStatus.Level -Name "sync" -Detail "($($syncStatus.Status)$(if ($syncStatus.Detail) { ': ' + $syncStatus.Detail }))"

        $validationCommands = Get-WorkspaceArray $project.validation
        if ($validationCommands.Count -gt 0) {
            Write-WorkspaceCheck -Level "OK" -Name "validation commands" -Detail "($($validationCommands.Count) configured)"
            foreach ($command in $validationCommands) {
                Write-Host "        $command" -ForegroundColor DarkGray
            }
        } else {
            Write-WorkspaceCheck -Level "WARN" -Name "validation commands" -Detail "(none configured)"
        }
    }

    if ($taskCount -gt 0) {
        Write-Host ""
        Write-Host "Tasks:" -ForegroundColor Yellow
        foreach ($task in $tasks) {
            $taskName = if ($task.name) { $task.name } else { "(unnamed)" }
            Write-Host "  - $taskName" -ForegroundColor DarkGray
            $risk = Get-WorkspaceTaskRisk -Task $task
            $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $task
            Write-WorkspaceCheck -Level "INFO" -Name "risk" -Detail "($risk; requires snapshot: $requiresSnapshot)"
            $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $task.runtime -SnapshotName $task.snapshot
            Write-WorkspaceCheck -Level $snapshotStatus.Level -Name "snapshot" -Detail "($($snapshotStatus.Status)$(if ($snapshotStatus.Detail) { ': ' + $snapshotStatus.Detail }))"
            $snapshotGate = Get-WorkspaceSnapshotGate -Task $task -SnapshotStatus $snapshotStatus
            Write-WorkspaceCheck -Level $snapshotGate.Level -Name "snapshot-first gate" -Detail "($($snapshotGate.Status): $($snapshotGate.Detail))"

            $validationCommands = Get-WorkspaceArray $task.validation
            if ($validationCommands.Count -gt 0) {
                Write-WorkspaceCheck -Level "OK" -Name "task validation" -Detail "($($validationCommands.Count) configured)"
            } else {
                Write-WorkspaceCheck -Level "WARN" -Name "task validation" -Detail "(none configured)"
            }
        }
    }
}

function Get-WorkspaceLevelRank {
    param([string]$Level)

    switch ($Level) {
        "FAIL" { return 3 }
        "WARN" { return 2 }
        "INFO" { return 1 }
        "OK" { return 0 }
        default { return 1 }
    }
}

function Select-WorstWorkspaceLevel {
    param([string[]]$Levels)

    $worst = "OK"
    foreach ($level in $Levels) {
        if ((Get-WorkspaceLevelRank $level) -gt (Get-WorkspaceLevelRank $worst)) {
            $worst = $level
        }
    }

    return $worst
}

function Write-WorkspaceDashboard {
    param(
        [object]$Manifest,
        [string]$ManifestPath,
        [string]$StatePath
    )

    Write-Host "Workspace dashboard: $($Manifest.name)" -ForegroundColor Cyan
    Write-Host "Dashboard only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation commands will be run, and no Git commands will be run." -ForegroundColor DarkGray

    $projects = Get-WorkspaceArray $Manifest.projects
    $tasks = Get-WorkspaceArray $Manifest.tasks
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath

    Write-Host ""
    Write-Host "Overview:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "manifest" -Detail "(projects: $($projects.Count), tasks: $($tasks.Count), path: $ManifestPath)"
    Write-WorkspaceCheck -Level "INFO" -Name "state" -Detail "(path: $resolvedStatePath)"

    Write-Host ""
    Write-Host "Project readiness:" -ForegroundColor Yellow
    if ($projects.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "projects" -Detail "(none configured)"
    }

    foreach ($project in $projects) {
        $projectName = if ($project.name) { $project.name } else { "(unnamed)" }
        $projectPath = Resolve-ProjectWorkspacePath -Project $project
        $pathLevel = if ($project.path -and (Test-Path -LiteralPath $projectPath)) { "OK" } elseif ($project.path) { "WARN" } else { "FAIL" }
        $runtimeStatus = Get-WorkspaceRuntimeStatus -RuntimeName $project.runtime
        $syncExpected = ($null -ne $project.sync -and [bool]$project.sync)
        $syncStatus = Get-WorkspaceSyncStatus -RuntimeName $project.runtime -Expected $syncExpected
        $validationCommands = Get-WorkspaceArray $project.validation
        $validationLevel = if ($validationCommands.Count -gt 0) { "OK" } else { "WARN" }
        $projectLevel = Select-WorstWorkspaceLevel -Levels @($pathLevel, $runtimeStatus.Level, $syncStatus.Level, $validationLevel)

        $pathDetail = if ($projectPath) { $projectPath } else { "missing" }
        Write-WorkspaceCheck -Level $projectLevel -Name $projectName -Detail "(path: $pathDetail; runtime: $($runtimeStatus.Status); sync: $($syncStatus.Status); validation: $($validationCommands.Count))"
    }

    Write-Host ""
    Write-Host "Task lifecycle:" -ForegroundColor Yellow
    if ($tasks.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "tasks" -Detail "(none configured)"
    }

    foreach ($task in $tasks) {
        $taskName = if ($task.name) { $task.name } else { "(unnamed)" }
        $runtimeStatus = Get-WorkspaceRuntimeStatus -RuntimeName $task.runtime
        $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $task.runtime -SnapshotName $task.snapshot
        $snapshotGate = Get-WorkspaceSnapshotGate -Task $task -SnapshotStatus $snapshotStatus
        $validationCommands = Get-WorkspaceArray $task.validation
        $validationLevel = if ($validationCommands.Count -gt 0) { "OK" } else { "WARN" }
        $taskLevel = Select-WorstWorkspaceLevel -Levels @($runtimeStatus.Level, $snapshotStatus.Level, $snapshotGate.Level, $validationLevel)

        $executionState = if ($snapshotGate.Blocking) {
            "blocked by snapshot gate"
        } elseif ($runtimeStatus.Level -eq "OK" -and $snapshotStatus.Level -eq "OK" -and $validationCommands.Count -gt 0) {
            "ready"
        } elseif ($runtimeStatus.Level -eq "FAIL" -or $validationCommands.Count -eq 0) {
            "blocked"
        } else {
            "gated"
        }
        $rollbackState = if ($task.runtime -and $task.snapshot) { $snapshotStatus.Status } else { "not configured" }
        $commitState = if ($validationCommands.Count -gt 0) { "review gated" } else { "blocked" }
        $risk = Get-WorkspaceTaskRisk -Task $task
        $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $task
        $recordedState = Get-WorkspaceTaskState -State $state -TaskName $taskName
        $recordedStateTime = if ($recordedState -and $recordedState.updated_at -is [datetime]) {
            $recordedState.updated_at.ToUniversalTime().ToString("o")
        } elseif ($recordedState) {
            $recordedState.updated_at
        } else {
            $null
        }
        $recordedStateText = if ($recordedState) { "$($recordedState.state) at $recordedStateTime" } else { "not recorded" }

        Write-WorkspaceCheck -Level $taskLevel -Name $taskName -Detail "(state: $recordedStateText; risk: $risk; snapshot required: $requiresSnapshot; checkpoint: $($snapshotGate.Status); runtime: $($runtimeStatus.Status); execution: $executionState; validation: $($validationCommands.Count); review: gated; rollback: $rollbackState; commit: $commitState)"
        Write-Host "      prepare: adp workspace task prepare $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-Host "      run:     adp workspace task run $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-Host "      review:  adp workspace task review $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    }
}

function Find-WorkspaceTask {
    param(
        [object]$Manifest,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Task name is required. Usage: adp workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name>"
    }

    $tasks = Get-WorkspaceArray $Manifest.tasks
    foreach ($task in $tasks) {
        if ($task.name -eq $Name) {
            return $task
        }
    }

    $available = @($tasks | ForEach-Object { $_.name } | Where-Object { $_ })
    $detail = if ($available.Count -gt 0) { "Available tasks: $($available -join ', ')" } else { "No tasks are configured in the workspace manifest." }
    throw "Workspace task not found: $Name. $detail"
}

function Write-TaskHeader {
    param(
        [string]$Action,
        [object]$Task
    )

    Write-Host ""
    Write-Host "Workspace task $Action`: $($Task.name)" -ForegroundColor Cyan
    Write-Host "Task lifecycle output is plan-only. No VM, sync, snapshot, file, Git, or validation command will be changed or run." -ForegroundColor DarkGray
    Write-Host ""
}

function Write-TaskSummary {
    param([object]$Task)

    $runtime = if ($Task.runtime) { $Task.runtime } else { "not configured" }
    $snapshot = if ($Task.snapshot) { $Task.snapshot } else { "not configured" }
    $risk = Get-WorkspaceTaskRisk -Task $Task
    $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $Task

    Write-Host "Task:" -ForegroundColor Yellow
    Write-Host "  Name:      $($Task.name)" -ForegroundColor DarkGray
    Write-Host "  Runtime:   $runtime" -ForegroundColor DarkGray
    Write-Host "  Risk:      $risk" -ForegroundColor DarkGray
    Write-Host "  Snapshot required: $requiresSnapshot" -ForegroundColor DarkGray
    Write-Host "  Snapshot:  $snapshot" -ForegroundColor DarkGray

    $validationCommands = Get-WorkspaceArray $Task.validation
    Write-Host "  Validation commands: $($validationCommands.Count)" -ForegroundColor DarkGray
    foreach ($command in $validationCommands) {
        Write-Host "    - $command" -ForegroundColor DarkGray
    }
}

function Write-WorkspaceTaskPrepare {
    param(
        [object]$Manifest,
        [object]$Task,
        [string]$ManifestPath
    )

    Write-TaskHeader -Action "prepare" -Task $Task
    Write-TaskSummary -Task $Task

    Write-Host ""
    Write-Host "Preparation checklist:" -ForegroundColor Yellow
    Write-Host "  1. Check workspace readiness:" -ForegroundColor DarkGray
    Write-Host "     adp workspace status -ManifestPath $ManifestPath" -ForegroundColor DarkGray

    if ($Task.runtime) {
        Write-Host "  2. Preview runtime startup:" -ForegroundColor DarkGray
        Write-Host "     adp up $($Task.runtime) -Plan" -ForegroundColor DarkGray
        Write-Host "  3. Confirm sync when the runtime is ready:" -ForegroundColor DarkGray
        Write-Host "     adp sync start $($Task.runtime)" -ForegroundColor DarkGray
    } else {
        Write-Host "  2. Add tasks[].runtime before preparing runtime and sync commands." -ForegroundColor DarkGray
    }

    if ($Task.snapshot -and $Task.runtime) {
        Write-Host "  4. Plan the checkpoint:" -ForegroundColor DarkGray
        Write-Host "     adp workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    } else {
        Write-Host "  4. Add tasks[].snapshot before planning checkpoint commands." -ForegroundColor DarkGray
    }

    Write-Host "  5. Review validation expectations:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
}

function Write-WorkspaceTaskSnapshot {
    param([object]$Task)

    Write-TaskHeader -Action "snapshot" -Task $Task
    Write-TaskSummary -Task $Task

    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    $snapshotGate = Get-WorkspaceSnapshotGate -Task $Task -SnapshotStatus $snapshotStatus
    Write-Host ""
    Write-Host "Checkpoint:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $snapshotStatus.Level -Name "snapshot" -Detail "($($snapshotStatus.Status)$(if ($snapshotStatus.Detail) { ': ' + $snapshotStatus.Detail }))"
    Write-WorkspaceCheck -Level $snapshotGate.Level -Name "snapshot-first gate" -Detail "($($snapshotGate.Status): $($snapshotGate.Detail))"

    if ($Task.runtime -and $Task.snapshot) {
        Write-Host ""
        Write-Host "Explicit command to create the checkpoint when ready:" -ForegroundColor Yellow
        Write-Host "  adp snapshot create $($Task.runtime) $($Task.snapshot)" -ForegroundColor DarkGray
    } else {
        Write-Host ""
        Write-Host "Add tasks[].runtime and tasks[].snapshot before creating a checkpoint." -ForegroundColor Yellow
    }
}

function Write-WorkspaceTaskValidate {
    param([object]$Task)

    Write-TaskHeader -Action "validate" -Task $Task
    Write-TaskSummary -Task $Task

    $validationCommands = Get-WorkspaceArray $Task.validation
    Write-Host ""
    Write-Host "Validation plan:" -ForegroundColor Yellow
    if ($validationCommands.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "task validation" -Detail "(none configured)"
        Write-Host "  Add tasks[].validation commands before using this task for review gates." -ForegroundColor DarkGray
        return
    }

    $index = 1
    foreach ($command in $validationCommands) {
        Write-Host "  $index. $command" -ForegroundColor DarkGray
        $index += 1
    }
}

function Write-WorkspaceTaskRun {
    param(
        [object]$Task,
        [string]$ManifestPath
    )

    Write-TaskHeader -Action "run" -Task $Task
    Write-TaskSummary -Task $Task

    Write-Host ""
    Write-Host "Execution boundary:" -ForegroundColor Yellow
    Write-Host "  1. Confirm readiness:" -ForegroundColor DarkGray
    Write-Host "     adp workspace status -ManifestPath $ManifestPath" -ForegroundColor DarkGray

    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    $snapshotGate = Get-WorkspaceSnapshotGate -Task $Task -SnapshotStatus $snapshotStatus
    if ($Task.runtime -and $Task.snapshot) {
        Write-Host "  2. Snapshot-first gate before broad agent work:" -ForegroundColor DarkGray
        Write-Host "     adp workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        if ($snapshotGate.Blocking) {
            Write-Host "     BLOCKED: $($snapshotGate.Detail)" -ForegroundColor Yellow
        } else {
            Write-Host "     READY: $($snapshotGate.Detail)" -ForegroundColor DarkGray
        }
        Write-Host "     adp workspace task mark $($Task.name) checkpointed" -ForegroundColor DarkGray
    } else {
        Write-Host "  2. Add tasks[].runtime and tasks[].snapshot before using rollback-capable agent task execution." -ForegroundColor DarkGray
    }

    if ($Task.runtime) {
        Write-Host "  3. Enter or target the runtime explicitly:" -ForegroundColor DarkGray
        Write-Host "     adp up $($Task.runtime) -Plan" -ForegroundColor DarkGray
        Write-Host "     adp sync start $($Task.runtime)" -ForegroundColor DarkGray
        Write-Host "     ssh adp-os-adp-$($Task.runtime)" -ForegroundColor DarkGray
    } else {
        Write-Host "  3. Add tasks[].runtime before selecting an execution runtime." -ForegroundColor DarkGray
    }

    Write-Host "  4. Run the agent or task command manually inside the selected workspace." -ForegroundColor DarkGray
    Write-Host "  5. Validate before review:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "  6. Move to review:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task review $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
}

function Write-WorkspaceTaskReview {
    param(
        [object]$Task,
        [string]$ManifestPath
    )

    Write-TaskHeader -Action "review" -Task $Task
    Write-TaskSummary -Task $Task

    Write-Host ""
    Write-Host "Human review bundle:" -ForegroundColor Yellow
    Write-Host "  1. Confirm readiness before review:" -ForegroundColor DarkGray
    Write-Host "     adp workspace status -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "  2. Confirm checkpoint state:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    if (Test-WorkspaceTaskRequiresSnapshot -Task $Task) {
        Write-Host "     Review should not accept broad agent work until the snapshot-first gate is ready or explicitly waived outside ADP-OS." -ForegroundColor DarkGray
    }
    Write-Host "  3. Run or inspect validation commands:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "  4. Inspect source changes in the target project:" -ForegroundColor DarkGray
    Write-Host "     git status --short" -ForegroundColor DarkGray
    Write-Host "     git diff --stat" -ForegroundColor DarkGray
    Write-Host "     git diff" -ForegroundColor DarkGray
    Write-Host "  5. Decide explicitly: rollback, revise, or commit." -ForegroundColor DarkGray
}

function Write-WorkspaceTaskRollback {
    param([object]$Task)

    Write-TaskHeader -Action "rollback" -Task $Task
    Write-TaskSummary -Task $Task

    Write-Host ""
    Write-Host "Rollback boundary:" -ForegroundColor Yellow
    if ($Task.runtime -and $Task.snapshot) {
        Write-Host "  VM snapshot rollback command:" -ForegroundColor DarkGray
        Write-Host "     adp restore $($Task.runtime) $($Task.snapshot)" -ForegroundColor DarkGray
    } else {
        Write-Host "  Add tasks[].runtime and tasks[].snapshot before planning VM snapshot rollback." -ForegroundColor DarkGray
    }

    Write-Host "  Source rollback remains a separate Git decision inside the target project:" -ForegroundColor DarkGray
    Write-Host "     git status --short" -ForegroundColor DarkGray
    Write-Host "     git diff --stat" -ForegroundColor DarkGray
    Write-Host "     git restore <paths>" -ForegroundColor DarkGray
    Write-Host "  Do not run restore commands until the human reviewer has chosen rollback." -ForegroundColor DarkGray
}

function Write-WorkspaceTaskCommit {
    param(
        [object]$Task,
        [string]$ManifestPath
    )

    Write-TaskHeader -Action "commit" -Task $Task
    Write-TaskSummary -Task $Task

    Write-Host ""
    Write-Host "Commit boundary:" -ForegroundColor Yellow
    Write-Host "  1. Confirm review bundle:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task review $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "  2. Confirm validation expectations:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "  3. Inspect source changes in the target project:" -ForegroundColor DarkGray
    Write-Host "     git status --short" -ForegroundColor DarkGray
    Write-Host "     git diff --stat" -ForegroundColor DarkGray
    Write-Host "     git diff" -ForegroundColor DarkGray
    Write-Host "  4. Commit only after the human reviewer accepts the task result:" -ForegroundColor DarkGray
    Write-Host "     git add <paths>" -ForegroundColor DarkGray
    Write-Host "     git commit -m ""<message>""" -ForegroundColor DarkGray
}

function Write-WorkspaceTaskMark {
    param(
        [object]$Task,
        [string]$StateName,
        [string]$Path
    )

    $validStates = @("prepared", "checkpointed", "running", "validated", "reviewed", "rollback", "committed")
    if ([string]::IsNullOrWhiteSpace($StateName) -or $StateName -notin $validStates) {
        Write-ErrorLog -Message "Unknown workspace task state: $StateName. Valid: $($validStates -join ', ')" -Component "cli.workspace"
        exit 1
    }

    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $Path
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $state = Set-WorkspaceTaskState -State $state -TaskName $Task.name -StateName $StateName
    Write-WorkspaceState -State $state -Path $resolvedStatePath

    Write-Host ""
    Write-Host "Workspace task mark: $($Task.name)" -ForegroundColor Cyan
    Write-Host "Recorded local lifecycle state only. No VM, sync, snapshot, file, Git, or validation command was run." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  State: $StateName" -ForegroundColor Green
    Write-Host "  File:  $resolvedStatePath" -ForegroundColor DarkGray
}

function Invoke-WorkspaceTask {
    param(
        [object]$Manifest,
        [string]$Command,
        [string]$Name,
        [string]$StateName,
        [string]$Path,
        [string]$LocalStatePath
    )

    $validTaskCommands = @("prepare", "snapshot", "run", "validate", "review", "rollback", "commit", "mark")
    if ([string]::IsNullOrWhiteSpace($Command) -or $Command -notin $validTaskCommands) {
        Write-ErrorLog -Message "Unknown workspace task command: $Command. Valid: $($validTaskCommands -join ', ')" -Component "cli.workspace"
        exit 1
    }

    $task = Find-WorkspaceTask -Manifest $Manifest -Name $Name

    switch ($Command) {
        "prepare" {
            Write-WorkspaceTaskPrepare -Manifest $Manifest -Task $task -ManifestPath $Path
        }
        "snapshot" {
            Write-WorkspaceTaskSnapshot -Task $task
        }
        "run" {
            Write-WorkspaceTaskRun -Task $task -ManifestPath $Path
        }
        "validate" {
            Write-WorkspaceTaskValidate -Task $task
        }
        "review" {
            Write-WorkspaceTaskReview -Task $task -ManifestPath $Path
        }
        "rollback" {
            Write-WorkspaceTaskRollback -Task $task
        }
        "commit" {
            Write-WorkspaceTaskCommit -Task $task -ManifestPath $Path
        }
        "mark" {
            Write-WorkspaceTaskMark -Task $task -StateName $StateName -Path $LocalStatePath
        }
    }
}

if (-not $SubCommand) {
    Show-WorkspaceUsage
    exit 1
}

switch ($SubCommand) {
    "init" {
        if (Test-Path -LiteralPath $ManifestPath) {
            Write-Host "Workspace manifest already exists: $ManifestPath" -ForegroundColor Yellow
            Write-Host "  No changes made." -ForegroundColor DarkGray
            return
        }

        $examplePath = Join-Path (Get-ProjectRoot) "configs\workspace.example.json"
        if (-not (Test-Path -LiteralPath $examplePath)) {
            throw "Workspace example missing: $examplePath"
        }

        Copy-Item -LiteralPath $examplePath -Destination $ManifestPath
        Write-Host "Workspace manifest created: $ManifestPath" -ForegroundColor Green
        Write-Host "  Edit project paths, runtimes, validation commands, and task snapshots before use." -ForegroundColor DarkGray
    }
    "show" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceSummary -Manifest $manifest
    }
    "plan" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-Host "Plan only: no projects will be cloned, no sync sessions will be changed, and no snapshots will be created." -ForegroundColor Cyan
        Write-Host ""
        Write-WorkspaceSummary -Manifest $manifest
        Write-Host ""
        Write-Host "Suggested next steps:" -ForegroundColor Yellow
        foreach ($project in (Get-WorkspaceArray $manifest.projects)) {
            if ($project.runtime) {
                Write-Host "  - Preview runtime: adp up $($project.runtime) -Plan" -ForegroundColor DarkGray
                if ($project.sync) {
                    Write-Host "  - Start sync when ready: adp sync start $($project.runtime)" -ForegroundColor DarkGray
                }
            }
        }
        foreach ($task in (Get-WorkspaceArray $manifest.tasks)) {
            if ($task.runtime -and $task.snapshot) {
                Write-Host "  - Snapshot before task '$($task.name)': adp snapshot create $($task.runtime) $($task.snapshot)" -ForegroundColor DarkGray
            }
        }
    }
    "status" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceStatus -Manifest $manifest
    }
    "dashboard" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceDashboard -Manifest $manifest -ManifestPath $ManifestPath -StatePath $StatePath
    }
    "task" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Invoke-WorkspaceTask -Manifest $manifest -Command $TaskCommand -Name $TaskName -StateName $TaskState -Path $ManifestPath -LocalStatePath $StatePath
    }
    default {
        Write-ErrorLog -Message "Unknown workspace command: $SubCommand. Valid: init, show, plan, status, dashboard, task" -Component "cli.workspace"
        exit 1
    }
}
