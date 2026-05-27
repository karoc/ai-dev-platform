# ADP-OS Workspace Command
# Non-destructive workspace manifest helpers.

param(
    [string]$SubCommand,
    [string]$TaskCommand,
    [string]$TaskName,
    [string]$ManifestPath = "adp-workspace.json"
)

$ErrorActionPreference = "Stop"

function Show-WorkspaceUsage {
    Write-ErrorLog -Message "Usage: adp workspace <init|show|plan|status|task> [-ManifestPath <path>]" -Component "cli.workspace"
    Write-Host "  adp workspace task <prepare|snapshot|validate|review> <task-name> [-ManifestPath <path>]" -ForegroundColor DarkGray
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
            $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $task.runtime -SnapshotName $task.snapshot
            Write-WorkspaceCheck -Level $snapshotStatus.Level -Name "snapshot" -Detail "($($snapshotStatus.Status)$(if ($snapshotStatus.Detail) { ': ' + $snapshotStatus.Detail }))"

            $validationCommands = Get-WorkspaceArray $task.validation
            if ($validationCommands.Count -gt 0) {
                Write-WorkspaceCheck -Level "OK" -Name "task validation" -Detail "($($validationCommands.Count) configured)"
            } else {
                Write-WorkspaceCheck -Level "WARN" -Name "task validation" -Detail "(none configured)"
            }
        }
    }
}

function Find-WorkspaceTask {
    param(
        [object]$Manifest,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Task name is required. Usage: adp workspace task <prepare|snapshot|validate|review> <task-name>"
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

    Write-Host "Task:" -ForegroundColor Yellow
    Write-Host "  Name:      $($Task.name)" -ForegroundColor DarkGray
    Write-Host "  Runtime:   $runtime" -ForegroundColor DarkGray
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
    Write-Host ""
    Write-Host "Checkpoint:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $snapshotStatus.Level -Name "snapshot" -Detail "($($snapshotStatus.Status)$(if ($snapshotStatus.Detail) { ': ' + $snapshotStatus.Detail }))"

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
    Write-Host "  3. Run or inspect validation commands:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "  4. Inspect source changes in the target project:" -ForegroundColor DarkGray
    Write-Host "     git status --short" -ForegroundColor DarkGray
    Write-Host "     git diff --stat" -ForegroundColor DarkGray
    Write-Host "     git diff" -ForegroundColor DarkGray
    Write-Host "  5. Decide explicitly: rollback, revise, or commit." -ForegroundColor DarkGray
}

function Invoke-WorkspaceTask {
    param(
        [object]$Manifest,
        [string]$Command,
        [string]$Name,
        [string]$Path
    )

    $validTaskCommands = @("prepare", "snapshot", "validate", "review")
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
        "validate" {
            Write-WorkspaceTaskValidate -Task $task
        }
        "review" {
            Write-WorkspaceTaskReview -Task $task -ManifestPath $Path
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
    "task" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Invoke-WorkspaceTask -Manifest $manifest -Command $TaskCommand -Name $TaskName -Path $ManifestPath
    }
    default {
        Write-ErrorLog -Message "Unknown workspace command: $SubCommand. Valid: init, show, plan, status, task" -Component "cli.workspace"
        exit 1
    }
}
