# ADP-OS Workspace Command
# Non-destructive workspace manifest helpers.

param(
    [string]$SubCommand,
    [string]$TaskCommand,
    [string]$TaskName,
    [string]$TaskState,
    [string]$ManifestPath = "adp-workspace.json",
    [string]$StatePath,
    [switch]$Execute,
    [switch]$Plan,
    [switch]$Markdown
)

$ErrorActionPreference = "Stop"

function Show-WorkspaceUsage {
    Write-ErrorLog -Message "Usage: adp workspace <init|show|plan|status|dashboard|report|recipes|create|open|sync|project|task> [-ManifestPath <path>]" -Component "cli.workspace"
    Write-Host "  adp workspace recipes [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-Host "  adp workspace create [-Plan] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-Host "  adp workspace open [project-name] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-Host "  adp workspace sync [project-name] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-Host "  adp workspace project [project-name] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-Host "  adp workspace report [-Markdown] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-Host "  adp workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name> [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-Host "  adp workspace task validate <task-name> [-Execute] [-Plan] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-Host "  adp workspace task mark <task-name> <prepared|checkpointed|checkpoint-waived|running|validated|reviewed|rollback|committed> [-StatePath <path>]" -ForegroundColor DarkGray
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

    $targetName = [string]$TaskName
    foreach ($taskState in (Get-WorkspaceArray $State.tasks)) {
        if ([string]$taskState.name -eq $targetName) {
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

    if ($Task.PSObject.Properties.Name -contains "milestone" -and -not [string]::IsNullOrWhiteSpace([string]$Task.milestone)) {
        return $true
    }

    $risk = Get-WorkspaceTaskRisk -Task $Task
    return ($risk -in @("high", "broad", "destructive", "uncertain"))
}

function Get-WorkspaceRecommendedSnapshotName {
    param([object]$Task)

    $taskName = if ($Task.name) { [string]$Task.name } else { "task" }
    if ($taskName -match '^(before|milestone)-') {
        return $taskName
    }

    return "before-$taskName"
}

function Get-WorkspaceSnapshotNamingStatus {
    param([object]$Task)

    $recommended = Get-WorkspaceRecommendedSnapshotName -Task $Task
    $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $Task

    if (-not $requiresSnapshot) {
        return [pscustomobject]@{
            Level       = "INFO"
            Status      = "optional"
            Detail      = "task does not require a snapshot; recommended if needed: $recommended"
            Recommended = $recommended
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$Task.snapshot)) {
        return [pscustomobject]@{
            Level       = "WARN"
            Status      = "missing"
            Detail      = "set tasks[].snapshot; recommended: $recommended"
            Recommended = $recommended
        }
    }

    $snapshotName = [string]$Task.snapshot
    if ($snapshotName -eq $recommended) {
        return [pscustomobject]@{
            Level       = "OK"
            Status      = "aligned"
            Detail      = "matches task checkpoint convention: $recommended"
            Recommended = $recommended
        }
    }

    if ($snapshotName -match '^(before|milestone)-') {
        return [pscustomobject]@{
            Level       = "INFO"
            Status      = "accepted"
            Detail      = "uses supported checkpoint prefix; recommended default: $recommended"
            Recommended = $recommended
        }
    }

    return [pscustomobject]@{
        Level       = "INFO"
        Status      = "nonstandard"
        Detail      = "prefer $recommended for task rollback, or milestone-<name> for milestone checkpoints"
        Recommended = $recommended
    }
}

function Get-WorkspaceSnapshotGate {
    param(
        [object]$Task,
        [object]$SnapshotStatus = $null,
        [object]$RecordedState = $null
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

    if (Test-WorkspaceCheckpointWaived -RecordedState $RecordedState) {
        $waiverText = Get-WorkspaceCheckpointWaiverText -RecordedState $RecordedState
        return [pscustomobject]@{
            Level    = "WARN"
            Status   = "waived"
            Detail   = "checkpoint explicitly waived in local state; no VM snapshot was confirmed$waiverText"
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

function Get-WorkspaceMilestones {
    param([object]$Manifest)

    if (-not ($Manifest.PSObject.Properties.Name -contains "milestones")) {
        return @()
    }

    return Get-WorkspaceArray $Manifest.milestones
}

function Get-WorkspaceRecommendedMilestoneSnapshotName {
    param([object]$Milestone)

    $name = if ($Milestone.name) { [string]$Milestone.name } else { "milestone" }
    if ($name -match '^milestone-') {
        return $name
    }

    return "milestone-$name"
}

function Get-WorkspaceMilestoneSnapshotName {
    param([object]$Milestone)

    if ($Milestone.PSObject.Properties.Name -contains "snapshot" -and -not [string]::IsNullOrWhiteSpace([string]$Milestone.snapshot)) {
        return [string]$Milestone.snapshot
    }

    return Get-WorkspaceRecommendedMilestoneSnapshotName -Milestone $Milestone
}

function Get-WorkspaceTaskMilestones {
    param(
        [object]$Manifest,
        [object]$Task
    )

    $taskName = if ($Task.name) { [string]$Task.name } else { "" }
    $taskMilestone = if ($Task.PSObject.Properties.Name -contains "milestone") { [string]$Task.milestone } else { "" }
    $matched = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($milestone in (Get-WorkspaceMilestones -Manifest $Manifest)) {
        $milestoneName = if ($milestone.name) { [string]$milestone.name } else { "" }
        $linkedTasks = if ($milestone.PSObject.Properties.Name -contains "tasks") { Get-WorkspaceArray $milestone.tasks } else { @() }
        $matchesTaskList = (-not [string]::IsNullOrWhiteSpace($taskName) -and ($linkedTasks -contains $taskName))
        $matchesTaskProperty = (-not [string]::IsNullOrWhiteSpace($taskMilestone) -and $taskMilestone -eq $milestoneName)

        if (($matchesTaskList -or $matchesTaskProperty) -and $seen.Add($milestoneName)) {
            $matched.Add($milestone) | Out-Null
        }
    }

    return @($matched.ToArray())
}

function Get-WorkspaceMilestoneTasks {
    param(
        [object]$Manifest,
        [object]$Milestone
    )

    $milestoneName = if ($Milestone.name) { [string]$Milestone.name } else { "" }
    $linkedTaskNames = if ($Milestone.PSObject.Properties.Name -contains "tasks") { Get-WorkspaceArray $Milestone.tasks } else { @() }
    $matched = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($task in (Get-WorkspaceArray $Manifest.tasks)) {
        $taskName = if ($task.name) { [string]$task.name } else { "" }
        $taskMilestone = if ($task.PSObject.Properties.Name -contains "milestone") { [string]$task.milestone } else { "" }
        if (($linkedTaskNames -contains $taskName) -or (-not [string]::IsNullOrWhiteSpace($milestoneName) -and $taskMilestone -eq $milestoneName)) {
            if ($seen.Add($taskName)) {
                $matched.Add($task) | Out-Null
            }
        }
    }

    return @($matched.ToArray())
}

function Get-WorkspaceMilestoneRuntimeName {
    param(
        [object]$Milestone,
        [object[]]$Tasks
    )

    if ($Milestone.PSObject.Properties.Name -contains "runtime" -and -not [string]::IsNullOrWhiteSpace([string]$Milestone.runtime)) {
        return [string]$Milestone.runtime
    }

    $taskRuntimes = @($Tasks | ForEach-Object { if ($_.runtime) { [string]$_.runtime } } | Select-Object -Unique)
    if ($taskRuntimes.Count -eq 1) {
        return $taskRuntimes[0]
    }

    return ""
}

function Get-WorkspaceMilestoneStatus {
    param(
        [object]$Manifest,
        [object]$Milestone
    )

    $tasks = Get-WorkspaceMilestoneTasks -Manifest $Manifest -Milestone $Milestone
    $name = if ($Milestone.name) { [string]$Milestone.name } else { "(unnamed)" }
    $runtimeName = Get-WorkspaceMilestoneRuntimeName -Milestone $Milestone -Tasks $tasks
    $snapshotName = Get-WorkspaceMilestoneSnapshotName -Milestone $Milestone
    $recommended = Get-WorkspaceRecommendedMilestoneSnapshotName -Milestone $Milestone
    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $runtimeName -SnapshotName $snapshotName

    $snapshotNaming = if ($snapshotName -eq $recommended) {
        [pscustomobject]@{
            Level       = "OK"
            Status      = "aligned"
            Detail      = "matches milestone checkpoint convention: $recommended"
            Recommended = $recommended
        }
    } elseif ($snapshotName -match '^milestone-') {
        [pscustomobject]@{
            Level       = "INFO"
            Status      = "accepted"
            Detail      = "uses milestone checkpoint prefix; recommended default: $recommended"
            Recommended = $recommended
        }
    } else {
        [pscustomobject]@{
            Level       = "INFO"
            Status      = "nonstandard"
            Detail      = "prefer $recommended for milestone checkpoints"
            Recommended = $recommended
        }
    }

    $level = Select-WorstWorkspaceLevel -Levels @($snapshotStatus.Level, $snapshotNaming.Level)
    if ($tasks.Count -eq 0) {
        $level = Select-WorstWorkspaceLevel -Levels @($level, "WARN")
    }

    return [pscustomobject]@{
        Name           = $name
        Level          = $level
        RuntimeName    = if ($runtimeName) { $runtimeName } else { "not configured" }
        SnapshotName   = $snapshotName
        Recommended    = $recommended
        SnapshotStatus = $snapshotStatus
        SnapshotNaming = $snapshotNaming
        Tasks          = $tasks
        TaskNames      = @($tasks | ForEach-Object { if ($_.name) { [string]$_.name } })
    }
}

function Get-WorkspaceEvaluations {
    param([object]$Manifest)

    if (-not ($Manifest.PSObject.Properties.Name -contains "evaluations")) {
        return @()
    }

    return Get-WorkspaceArray $Manifest.evaluations
}

function Get-WorkspaceEvaluationTasks {
    param(
        [object]$Manifest,
        [object]$Evaluation
    )

    $evaluationName = if ($Evaluation.name) { [string]$Evaluation.name } else { "" }
    $linkedTaskNames = if ($Evaluation.PSObject.Properties.Name -contains "tasks") { Get-WorkspaceArray $Evaluation.tasks } else { @() }
    $matched = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($task in (Get-WorkspaceArray $Manifest.tasks)) {
        $taskName = if ($task.name) { [string]$task.name } else { "" }
        $taskEvaluation = if ($task.PSObject.Properties.Name -contains "evaluation") { [string]$task.evaluation } else { "" }
        if (($linkedTaskNames -contains $taskName) -or (-not [string]::IsNullOrWhiteSpace($evaluationName) -and $taskEvaluation -eq $evaluationName)) {
            if ($seen.Add($taskName)) {
                $matched.Add($task) | Out-Null
            }
        }
    }

    return @($matched.ToArray())
}

function Get-WorkspaceTaskEvaluations {
    param(
        [object]$Manifest,
        [object]$Task
    )

    $taskName = if ($Task.name) { [string]$Task.name } else { "" }
    $taskEvaluation = if ($Task.PSObject.Properties.Name -contains "evaluation") { [string]$Task.evaluation } else { "" }
    $matched = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($evaluation in (Get-WorkspaceEvaluations -Manifest $Manifest)) {
        $evaluationName = if ($evaluation.name) { [string]$evaluation.name } else { "" }
        $linkedTasks = if ($evaluation.PSObject.Properties.Name -contains "tasks") { Get-WorkspaceArray $evaluation.tasks } else { @() }
        $matchesTaskList = (-not [string]::IsNullOrWhiteSpace($taskName) -and ($linkedTasks -contains $taskName))
        $matchesTaskProperty = (-not [string]::IsNullOrWhiteSpace($taskEvaluation) -and $taskEvaluation -eq $evaluationName)

        if (($matchesTaskList -or $matchesTaskProperty) -and $seen.Add($evaluationName)) {
            $matched.Add($evaluation) | Out-Null
        }
    }

    return @($matched.ToArray())
}

function Get-WorkspaceEvaluationProjectName {
    param(
        [object]$Evaluation,
        [object[]]$Tasks
    )

    if ($Evaluation.PSObject.Properties.Name -contains "project" -and -not [string]::IsNullOrWhiteSpace([string]$Evaluation.project)) {
        return [string]$Evaluation.project
    }

    $taskProjects = @($Tasks | ForEach-Object {
            if ($_.PSObject.Properties.Name -contains "project" -and -not [string]::IsNullOrWhiteSpace([string]$_.project)) {
                [string]$_.project
            }
        } | Select-Object -Unique)
    if ($taskProjects.Count -eq 1) {
        return $taskProjects[0]
    }

    return "not configured"
}

function Get-WorkspaceEvaluationRuntimeName {
    param(
        [object]$Evaluation,
        [object[]]$Tasks
    )

    if ($Evaluation.PSObject.Properties.Name -contains "runtime" -and -not [string]::IsNullOrWhiteSpace([string]$Evaluation.runtime)) {
        return [string]$Evaluation.runtime
    }

    $taskRuntimes = @($Tasks | ForEach-Object { if ($_.runtime) { [string]$_.runtime } } | Select-Object -Unique)
    if ($taskRuntimes.Count -eq 1) {
        return $taskRuntimes[0]
    }

    return "not configured"
}

function Get-WorkspaceEvaluationStatus {
    param(
        [object]$Manifest,
        [object]$Evaluation
    )

    $name = if ($Evaluation.name) { [string]$Evaluation.name } else { "(unnamed)" }
    $tasks = Get-WorkspaceEvaluationTasks -Manifest $Manifest -Evaluation $Evaluation
    $runtimeName = Get-WorkspaceEvaluationRuntimeName -Evaluation $Evaluation -Tasks $tasks
    $projectName = Get-WorkspaceEvaluationProjectName -Evaluation $Evaluation -Tasks $tasks
    $metrics = if ($Evaluation.PSObject.Properties.Name -contains "metrics") { Get-WorkspaceArray $Evaluation.metrics } else { @() }
    $commands = if ($Evaluation.PSObject.Properties.Name -contains "commands") { Get-WorkspaceArray $Evaluation.commands } else { @() }
    $cadence = if ($Evaluation.PSObject.Properties.Name -contains "cadence" -and -not [string]::IsNullOrWhiteSpace([string]$Evaluation.cadence)) { [string]$Evaluation.cadence } else { "not set" }
    $level = "OK"
    $readiness = "planned"
    $blockers = [System.Collections.Generic.List[string]]::new()

    if ($tasks.Count -eq 0) {
        $level = Select-WorstWorkspaceLevel -Levels @($level, "WARN")
        $blockers.Add("no linked tasks") | Out-Null
    }
    if ($metrics.Count -eq 0) {
        $level = Select-WorstWorkspaceLevel -Levels @($level, "WARN")
        $blockers.Add("metrics not configured") | Out-Null
    }
    if ($commands.Count -eq 0) {
        $level = Select-WorstWorkspaceLevel -Levels @($level, "WARN")
        $blockers.Add("commands not configured") | Out-Null
    }
    if ($runtimeName -eq "not configured") {
        $level = Select-WorstWorkspaceLevel -Levels @($level, "WARN")
        $blockers.Add("runtime not configured") | Out-Null
    }
    if ($projectName -eq "not configured") {
        $level = Select-WorstWorkspaceLevel -Levels @($level, "WARN")
        $blockers.Add("project not configured") | Out-Null
    }

    if ($blockers.Count -gt 0) {
        $readiness = "needs manifest detail"
    }

    return [pscustomobject]@{
        Name        = $name
        Level       = $level
        Readiness   = $readiness
        RuntimeName = $runtimeName
        ProjectName = $projectName
        Cadence     = $cadence
        Metrics     = @($metrics)
        Commands    = @($commands)
        Tasks       = @($tasks)
        TaskNames   = @($tasks | ForEach-Object { if ($_.name) { [string]$_.name } })
        Blockers    = @($blockers)
    }
}

function Quote-PosixSingleArgument {
    param([string]$Value)

    return "'" + ($Value -replace "'", "'""'""'") + "'"
}

function Quote-WorkspacePowerShellArgument {
    param([string]$Value)

    return "'" + ($Value -replace "'", "''") + "'"
}

function Find-WorkspaceProject {
    param(
        [object]$Manifest,
        [string]$Name
    )

    $projects = Get-WorkspaceArray $Manifest.projects
    if ($projects.Count -eq 0) {
        throw "Workspace manifest has no projects[]. Add a project before using workspace open."
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        if ($projects.Count -eq 1) {
            return $projects[0]
        }

        $available = @($projects | ForEach-Object { if ($_.name) { [string]$_.name } else { "(unnamed)" } })
        throw "Project name required because the workspace has multiple projects. Available projects: $($available -join ', ')"
    }

    foreach ($project in $projects) {
        if ($project.name -eq $Name) {
            return $project
        }
    }

    $availableNames = @($projects | ForEach-Object { if ($_.name) { [string]$_.name } else { "(unnamed)" } })
    throw "Workspace project not found: $Name. Available projects: $($availableNames -join ', ')"
}

function Find-WorkspaceProjectForTask {
    param(
        [object]$Manifest,
        [object]$Task
    )

    $projects = Get-WorkspaceArray $Manifest.projects
    $taskProjectName = if ($Task.PSObject.Properties.Name -contains "project") { [string]$Task.project } else { "" }

    if (-not [string]::IsNullOrWhiteSpace($taskProjectName)) {
        foreach ($project in $projects) {
            if ($project.name -eq $taskProjectName) {
                return $project
            }
        }

        throw "Workspace task '$($Task.name)' references project '$taskProjectName', but no matching projects[].name exists."
    }

    $runtimeProjects = @($projects | Where-Object { $_.runtime -eq $Task.runtime })
    if ($runtimeProjects.Count -eq 1) {
        return $runtimeProjects[0]
    }

    if ($runtimeProjects.Count -eq 0) {
        throw "Workspace task '$($Task.name)' has no matching project for runtime '$($Task.runtime)'. Set tasks[].project before executing validation."
    }

    throw "Workspace task '$($Task.name)' matches multiple projects for runtime '$($Task.runtime)'. Set tasks[].project before executing validation."
}

function Resolve-WorkspaceRemoteProjectPath {
    param([object]$Project)

    if (-not $Project.path) {
        throw "Workspace project '$($Project.name)' is missing projects[].path."
    }

    $projectPath = ([string]$Project.path).Replace("\", "/").Trim()
    if ([string]::IsNullOrWhiteSpace($projectPath)) {
        throw "Workspace project '$($Project.name)' has an empty projects[].path."
    }

    if ($projectPath.StartsWith("/") -or $projectPath -match '^[A-Za-z]:') {
        throw "Workspace project '$($Project.name)' must use a relative projects[].path before remote validation execution."
    }

    $segments = @($projectPath -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($segments -contains "." -or $segments -contains "..") {
        throw "Workspace project '$($Project.name)' path cannot contain '.' or '..' segments before remote validation execution."
    }

    return "/home/adp/workspace/$($segments -join '/')"
}

function Get-WorkspaceRuntimeSshTarget {
    param([string]$RuntimeName)

    if ([string]::IsNullOrWhiteSpace($RuntimeName)) {
        throw "Set tasks[].runtime before executing validation."
    }

    if (-not (Test-RuntimeExists $RuntimeName)) {
        throw "Unknown runtime: $RuntimeName. Valid: $((Get-AllRuntimeNames) -join ', ')"
    }

    $runtime = Get-RuntimeConfig $RuntimeName
    $sshHost = if ($runtime.PSObject.Properties.Name -contains "static_ip") { [string]$runtime.static_ip } else { "" }
    if ([string]::IsNullOrWhiteSpace($sshHost)) {
        throw "Runtime '$RuntimeName' has no static_ip configured; validation execution needs an explicit SSH target."
    }

    $port = if ($runtime.PSObject.Properties.Name -contains "ssh_port" -and $runtime.ssh_port) { [int]$runtime.ssh_port } else { 22 }
    $config = Get-PlatformConfig
    $user = if ($config.defaults.admin_user) { [string]$config.defaults.admin_user } else { "adp" }
    $keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
    return [pscustomobject]@{
        Host    = $sshHost
        Port    = $port
        User    = $user
        KeyPath = $keyPath
    }
}

function Invoke-WorkspaceRemoteValidationCommand {
    param(
        [object]$SshTarget,
        [string]$RemoteCommand
    )

    & ssh -i $SshTarget.KeyPath `
        -o StrictHostKeyChecking=no `
        -o UserKnownHostsFile=NUL `
        -o IdentitiesOnly=yes `
        -o ConnectTimeout=10 `
        -p $SshTarget.Port `
        "$($SshTarget.User)@$($SshTarget.Host)" `
        $RemoteCommand
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
            if ($StateName -eq "checkpointed" -and $taskState.PSObject.Properties.Name -contains "checkpoint") {
                $taskState.PSObject.Properties.Remove("checkpoint")
            }
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

function Set-WorkspaceTaskCheckpointWaiver {
    param(
        [object]$State,
        [string]$TaskName
    )

    $tasks = [System.Collections.Generic.List[object]]::new()
    $updated = $false
    $timestamp = (Get-Date).ToUniversalTime().ToString("o")
    $checkpoint = [pscustomobject]@{
        status     = "waived"
        updated_at = $timestamp
    }

    foreach ($taskState in (Get-WorkspaceArray $State.tasks)) {
        if ($taskState.name -eq $TaskName) {
            $taskState | Add-Member -NotePropertyName "state" -NotePropertyValue "checkpoint-waived" -Force
            $taskState | Add-Member -NotePropertyName "updated_at" -NotePropertyValue $timestamp -Force
            $taskState | Add-Member -NotePropertyName "checkpoint" -NotePropertyValue $checkpoint -Force
            $updated = $true
        }
        $tasks.Add($taskState) | Out-Null
    }

    if (-not $updated) {
        $tasks.Add([pscustomobject]@{
            name       = $TaskName
            state      = "checkpoint-waived"
            updated_at = $timestamp
            checkpoint = $checkpoint
        }) | Out-Null
    }

    $State.tasks = @($tasks.ToArray())
    $State | Add-Member -NotePropertyName "updated_at" -NotePropertyValue $timestamp -Force
    return $State
}

function Set-WorkspaceTaskValidationResult {
    param(
        [object]$State,
        [string]$TaskName,
        [object]$Validation
    )

    $tasks = [System.Collections.Generic.List[object]]::new()
    $updated = $false
    $timestamp = (Get-Date).ToUniversalTime().ToString("o")
    $stateName = if ($Validation.status -eq "passed") { "validated" } else { "validation_failed" }

    foreach ($taskState in (Get-WorkspaceArray $State.tasks)) {
        if ($taskState.name -eq $TaskName) {
            $taskState | Add-Member -NotePropertyName "state" -NotePropertyValue $stateName -Force
            $taskState | Add-Member -NotePropertyName "updated_at" -NotePropertyValue $timestamp -Force
            $taskState | Add-Member -NotePropertyName "validation" -NotePropertyValue $Validation -Force
            $updated = $true
        }
        $tasks.Add($taskState) | Out-Null
    }

    if (-not $updated) {
        $tasks.Add([pscustomobject]@{
            name       = $TaskName
            state      = $stateName
            updated_at = $timestamp
            validation = $Validation
        }) | Out-Null
    }

    $State.tasks = @($tasks.ToArray())
    $State | Add-Member -NotePropertyName "updated_at" -NotePropertyValue $timestamp -Force
    return $State
}

function New-WorkspaceValidationResult {
    param(
        [object]$Task,
        [object]$Project,
        [string]$RemotePath,
        [string]$Status,
        [string]$StartedAt,
        [string]$CompletedAt,
        [string[]]$Commands,
        [int]$ExitCode,
        [string]$FailedCommand = ""
    )

    return [pscustomobject]@{
        status         = $Status
        runtime        = [string]$Task.runtime
        project        = [string]$Project.name
        remote_path    = $RemotePath
        command_count  = @($Commands).Count
        commands       = @($Commands)
        exit_code      = $ExitCode
        failed_command = $FailedCommand
        started_at     = $StartedAt
        completed_at   = $CompletedAt
    }
}

function Write-WorkspaceValidationResult {
    param(
        [string]$StatePath,
        [object]$Task,
        [object]$Validation
    )

    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $state = Set-WorkspaceTaskValidationResult -State $state -TaskName $Task.name -Validation $Validation
    Write-WorkspaceState -State $state -Path $resolvedStatePath
    return $resolvedStatePath
}

function Format-WorkspaceValidationState {
    param([object]$RecordedState)

    if (-not $RecordedState -or -not ($RecordedState.PSObject.Properties.Name -contains "validation") -or -not $RecordedState.validation) {
        return "not recorded"
    }

    $validation = $RecordedState.validation
    $exitCode = if ($validation.PSObject.Properties.Name -contains "exit_code") { $validation.exit_code } else { "unknown" }
    $completedAt = if ($validation.PSObject.Properties.Name -contains "completed_at" -and $validation.completed_at -is [datetime]) {
        $validation.completed_at.ToUniversalTime().ToString("o")
    } elseif ($validation.PSObject.Properties.Name -contains "completed_at") {
        $validation.completed_at
    } else {
        "unknown time"
    }
    $project = if ($validation.PSObject.Properties.Name -contains "project") { $validation.project } else { "unknown project" }
    return "$($validation.status) at $completedAt; project: $project; exit: $exitCode"
}

function Get-WorkspaceValidationStatus {
    param([object]$RecordedState)

    if (-not $RecordedState -or -not ($RecordedState.PSObject.Properties.Name -contains "validation") -or -not $RecordedState.validation) {
        return "missing"
    }

    if ($RecordedState.validation.PSObject.Properties.Name -contains "status" -and -not [string]::IsNullOrWhiteSpace([string]$RecordedState.validation.status)) {
        return ([string]$RecordedState.validation.status).ToLowerInvariant()
    }

    return "unknown"
}

function Get-WorkspaceReviewDecision {
    param(
        [object]$Task,
        [object]$RecordedState,
        [object]$SnapshotGate,
        [int]$ValidationCommandCount,
        [object]$SyncHygiene
    )

    if (Test-WorkspaceSyncHygieneBlocking -SyncHygiene $SyncHygiene) {
        return [pscustomobject]@{
            Level    = "WARN"
            Verdict  = "blocked by sync hygiene"
            Detail   = "$($SyncHygiene.Status): $($SyncHygiene.Detail)"
            NextStep = "review sync ignore before accepting the task"
        }
    }

    if ($SnapshotGate.Blocking) {
        return [pscustomobject]@{
            Level    = "WARN"
            Verdict  = "blocked by snapshot gate"
            Detail   = $SnapshotGate.Detail
            NextStep = "create or explicitly waive the checkpoint before accepting broad agent work"
        }
    }

    if ($ValidationCommandCount -eq 0) {
        return [pscustomobject]@{
            Level    = "WARN"
            Verdict  = "validation not configured"
            Detail   = "add tasks[].validation before using this task as a review gate"
            NextStep = "revise the workspace manifest before commit"
        }
    }

    $validationStatus = Get-WorkspaceValidationStatus -RecordedState $RecordedState
    switch ($validationStatus) {
        "passed" {
            return [pscustomobject]@{
                Level    = "OK"
                Verdict  = "validation passed"
                Detail   = "source review can decide whether to commit"
                NextStep = "inspect diff, then mark reviewed or move to commit"
            }
        }
        "failed" {
            return [pscustomobject]@{
                Level    = "FAIL"
                Verdict  = "validation failed"
                Detail   = "commit is blocked until the task is revised or rolled back"
                NextStep = "revise and re-run validation, or use rollback guidance"
            }
        }
        default {
            return [pscustomobject]@{
                Level    = "WARN"
                Verdict  = "validation result missing"
                Detail   = "no executed validation result is recorded in local workspace state"
                NextStep = "run adp workspace task validate $($Task.name) -Execute or explicitly review outside ADP-OS"
            }
        }
    }
}

function Write-WorkspaceReviewDecision {
    param([object]$Decision)

    Write-WorkspaceCheck -Level $Decision.Level -Name "review verdict" -Detail "($($Decision.Verdict): $($Decision.Detail))"
    Write-Host "     next: $($Decision.NextStep)" -ForegroundColor DarkGray
}

function Get-WorkspaceRecordedTaskStateName {
    param([object]$RecordedState)

    if ($RecordedState -and $RecordedState.PSObject.Properties.Name -contains "state" -and -not [string]::IsNullOrWhiteSpace([string]$RecordedState.state)) {
        return ([string]$RecordedState.state).ToLowerInvariant()
    }

    return "missing"
}

function Get-WorkspaceCommitDecision {
    param(
        [object]$Task,
        [object]$RecordedState,
        [object]$SnapshotGate,
        [int]$ValidationCommandCount,
        [object]$SyncHygiene
    )

    if (Test-WorkspaceSyncHygieneBlocking -SyncHygiene $SyncHygiene) {
        return [pscustomobject]@{
            Level    = "WARN"
            Verdict  = "blocked by sync hygiene"
            Detail   = "$($SyncHygiene.Status): $($SyncHygiene.Detail)"
            NextStep = "review sync ignore before commit"
        }
    }

    if ($SnapshotGate.Blocking) {
        return [pscustomobject]@{
            Level    = "WARN"
            Verdict  = "blocked by snapshot gate"
            Detail   = $SnapshotGate.Detail
            NextStep = "create or explicitly waive the checkpoint before commit"
        }
    }

    if ($ValidationCommandCount -eq 0) {
        return [pscustomobject]@{
            Level    = "WARN"
            Verdict  = "validation not configured"
            Detail   = "commit should not proceed without a declared validation gate"
            NextStep = "add tasks[].validation and run review again"
        }
    }

    $validationStatus = Get-WorkspaceValidationStatus -RecordedState $RecordedState
    if ($validationStatus -eq "failed") {
        return [pscustomobject]@{
            Level    = "FAIL"
            Verdict  = "blocked by validation"
            Detail   = "latest recorded validation failed"
            NextStep = "revise and re-run validation, or rollback"
        }
    }

    if ($validationStatus -ne "passed") {
        return [pscustomobject]@{
            Level    = "WARN"
            Verdict  = "validation result missing"
            Detail   = "no passing validation result is recorded in local workspace state"
            NextStep = "run adp workspace task validate $($Task.name) -Execute before commit"
        }
    }

    $recordedTaskState = Get-WorkspaceRecordedTaskStateName -RecordedState $RecordedState
    if ($recordedTaskState -eq "committed") {
        return [pscustomobject]@{
            Level    = "OK"
            Verdict  = "already marked committed"
            Detail   = "local workspace state says the commit boundary was completed"
            NextStep = "confirm repository history in the target project"
        }
    }

    if ($recordedTaskState -eq "reviewed") {
        return [pscustomobject]@{
            Level    = "OK"
            Verdict  = "commit ready"
            Detail   = "validation passed and human review is recorded"
            NextStep = "inspect final diff, then stage and commit inside the target project"
        }
    }

    return [pscustomobject]@{
        Level    = "WARN"
        Verdict  = "review not recorded"
        Detail   = "validation passed, but the task is not marked reviewed"
        NextStep = "run adp workspace task review $($Task.name), then mark reviewed when accepted"
    }
}

function Write-WorkspaceCommitDecision {
    param([object]$Decision)

    Write-WorkspaceCheck -Level $Decision.Level -Name "commit readiness" -Detail "($($Decision.Verdict): $($Decision.Detail))"
    Write-Host "     next: $($Decision.NextStep)" -ForegroundColor DarkGray
}

function Write-WorkspaceValidationDetailLines {
    param([object]$RecordedState)

    if (-not $RecordedState -or -not ($RecordedState.PSObject.Properties.Name -contains "validation") -or -not $RecordedState.validation) {
        Write-Host "     validation detail: no recorded execution result" -ForegroundColor DarkGray
        return
    }

    $validation = $RecordedState.validation
    if ($validation.PSObject.Properties.Name -contains "failed_command" -and -not [string]::IsNullOrWhiteSpace([string]$validation.failed_command)) {
        Write-Host "     failed command: $($validation.failed_command)" -ForegroundColor DarkGray
    }
    if ($validation.PSObject.Properties.Name -contains "remote_path" -and -not [string]::IsNullOrWhiteSpace([string]$validation.remote_path)) {
        Write-Host "     remote path: $($validation.remote_path)" -ForegroundColor DarkGray
    }
    if ($validation.PSObject.Properties.Name -contains "command_count") {
        Write-Host "     command count: $($validation.command_count)" -ForegroundColor DarkGray
    }
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
        $projectPath = Resolve-ProjectWorkspacePath -Project $project
        $devContainerStatus = Get-WorkspaceDevContainerStatus -ProjectPath $projectPath
        Write-Host "      devcontainer: $($devContainerStatus.Status)$(if ($devContainerStatus.Detail) { ' - ' + $devContainerStatus.Detail })" -ForegroundColor DarkGray
        $syncHygieneStatus = Get-WorkspaceSyncHygieneStatus -Project $project -ProjectPath $projectPath
        Write-Host "      sync hygiene: $($syncHygieneStatus.Status)$(if ($syncHygieneStatus.Detail) { ' - ' + $syncHygieneStatus.Detail })" -ForegroundColor DarkGray
        foreach ($command in (Get-WorkspaceArray $project.validation)) {
            Write-Host "      validate: $command" -ForegroundColor DarkGray
        }
    }

    $milestones = Get-WorkspaceMilestones -Manifest $Manifest
    if ($milestones.Count -gt 0) {
        Write-Host ""
        Write-Host "Milestones:" -ForegroundColor Yellow
        foreach ($milestone in $milestones) {
            $status = Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $milestone
            $name = if ($milestone.name) { [string]$milestone.name } else { "(unnamed)" }
            Write-Host "  - $name`: runtime=$($status.RuntimeName) snapshot=$($status.SnapshotName) tasks=$($status.TaskNames.Count)" -ForegroundColor DarkGray
            if ($milestone.description) {
                Write-Host "      $($milestone.description)" -ForegroundColor DarkGray
            }
            Write-Host "      snapshot naming: $($status.SnapshotNaming.Status) - $($status.SnapshotNaming.Detail)" -ForegroundColor DarkGray
            Write-Host "      linked tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' })" -ForegroundColor DarkGray
        }
    }

    $evaluations = Get-WorkspaceEvaluations -Manifest $Manifest
    if ($evaluations.Count -gt 0) {
        Write-Host ""
        Write-Host "Evaluations:" -ForegroundColor Yellow
        foreach ($evaluation in $evaluations) {
            $status = Get-WorkspaceEvaluationStatus -Manifest $Manifest -Evaluation $evaluation
            Write-Host "  - $($status.Name): runtime=$($status.RuntimeName) project=$($status.ProjectName) metrics=$($status.Metrics.Count) commands=$($status.Commands.Count) tasks=$($status.TaskNames.Count)" -ForegroundColor DarkGray
            Write-Host "      cadence: $($status.Cadence); readiness: $($status.Readiness)" -ForegroundColor DarkGray
            if ($evaluation.description) {
                Write-Host "      $($evaluation.description)" -ForegroundColor DarkGray
            }
            if ($status.TaskNames.Count -gt 0) {
                Write-Host "      linked tasks: $($status.TaskNames -join ', ')" -ForegroundColor DarkGray
            }
            foreach ($metric in $status.Metrics) {
                Write-Host "      metric: $metric" -ForegroundColor DarkGray
            }
        }
    }

    if ($Manifest.tasks) {
        Write-Host ""
        Write-Host "Tasks:" -ForegroundColor Yellow
        foreach ($task in (Get-WorkspaceArray $Manifest.tasks)) {
            $runtime = if ($task.runtime) { $task.runtime } else { "not configured" }
            $snapshot = if ($task.snapshot) { $task.snapshot } else { "not configured" }
            $taskMilestones = Get-WorkspaceTaskMilestones -Manifest $Manifest -Task $task
            $milestoneNames = @($taskMilestones | ForEach-Object { if ($_.name) { [string]$_.name } })
            $milestoneText = if ($milestoneNames.Count -gt 0) { $milestoneNames -join ', ' } else { "none" }
            $taskEvaluations = Get-WorkspaceTaskEvaluations -Manifest $Manifest -Task $task
            $evaluationNames = @($taskEvaluations | ForEach-Object { if ($_.name) { [string]$_.name } })
            $evaluationText = if ($evaluationNames.Count -gt 0) { $evaluationNames -join ', ' } else { "none" }
            Write-Host "  - $($task.name): runtime=$runtime snapshot=$snapshot milestone=$milestoneText evaluation=$evaluationText" -ForegroundColor DarkGray
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

function Get-WorkspaceProjectCreateEntries {
    param([object]$Manifest)

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($project in (Get-WorkspaceArray $Manifest.projects)) {
        $projectName = if ($project.name) { [string]$project.name } else { "(unnamed)" }
        $runtimeName = if ($project.runtime) { [string]$project.runtime } else { "not configured" }
        $localPath = $null
        $fullPath = $null
        $exists = $false
        $isDirectory = $false
        $valid = $true
        $status = "planned"
        $detail = ""
        $level = "WARN"

        try {
            $localPath = Resolve-ProjectWorkspacePath -Project $project
            if ([string]::IsNullOrWhiteSpace($localPath)) {
                throw "projects[].path missing"
            }

            $fullPath = [System.IO.Path]::GetFullPath($localPath)
            $root = [System.IO.Path]::GetPathRoot($fullPath)
            $trimmedFull = $fullPath.TrimEnd('\', '/')
            $trimmedRoot = if ($root) { $root.TrimEnd('\', '/') } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($trimmedRoot) -and $trimmedFull -eq $trimmedRoot) {
                throw "refusing to create a filesystem root"
            }

            $exists = Test-Path -LiteralPath $fullPath
            if ($exists) {
                $isDirectory = Test-Path -LiteralPath $fullPath -PathType Container
                if (-not $isDirectory) {
                    throw "path exists and is not a directory"
                }

                $level = "OK"
                $status = "exists"
                $detail = "directory already exists"
            } else {
                $level = "WARN"
                $status = "missing"
                $detail = "directory can be created"
            }
        } catch {
            $valid = $false
            $level = "FAIL"
            $status = "blocked"
            $detail = "$_"
        }

        $entries.Add([pscustomobject]@{
                ProjectName = $projectName
                RuntimeName = $runtimeName
                LocalPath   = $localPath
                FullPath    = $fullPath
                Exists      = $exists
                IsDirectory = $isDirectory
                Valid       = $valid
                Level       = $level
                Status      = $status
                Detail      = $detail
            }) | Out-Null
    }

    return @($entries)
}

function Write-WorkspaceCreate {
    param(
        [object]$Manifest,
        [string]$ManifestPath,
        [switch]$PlanOnly
    )

    Write-Host "Workspace create: $($Manifest.name)" -ForegroundColor Cyan
    if ($PlanOnly) {
        Write-Host "Plan only: no directories will be created, no projects cloned, no sync sessions changed, no runtimes started, no SSH connections opened, no snapshots created, no validation or evaluation commands run, and no Git commands run." -ForegroundColor DarkGray
    } else {
        Write-Host "Create only: local project directories may be created. No projects will be cloned, no sync sessions changed, no runtimes started, no SSH connections opened, no snapshots created, no validation or evaluation commands run, and no Git commands run." -ForegroundColor DarkGray
    }

    $entries = Get-WorkspaceProjectCreateEntries -Manifest $Manifest
    $invalidEntries = @($entries | Where-Object { -not $_.Valid })
    $missingEntries = @($entries | Where-Object { $_.Valid -and -not $_.Exists })
    $existingEntries = @($entries | Where-Object { $_.Valid -and $_.Exists })

    Write-Host ""
    Write-Host "Project directories:" -ForegroundColor Yellow
    if ($entries.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "projects" -Detail "(none configured)"
    }

    foreach ($entry in $entries) {
        Write-WorkspaceCheck -Level $entry.Level -Name $entry.ProjectName -Detail "(runtime: $($entry.RuntimeName); status: $($entry.Status); path: $(if ($entry.FullPath) { $entry.FullPath } else { 'not available' }); detail: $($entry.Detail))"
        if ($entry.Valid) {
            Write-Host "       open:      adp workspace open $($entry.ProjectName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
            Write-Host "       lifecycle: adp workspace project $($entry.ProjectName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        }
    }

    if ($invalidEntries.Count -gt 0) {
        Write-Host ""
        Write-Host "Create blocked: fix invalid project paths before creating workspace directories. No directories were created." -ForegroundColor Red
        exit 1
    }

    if ($PlanOnly) {
        Write-Host ""
        Write-Host "Plan summary: $($missingEntries.Count) directories would be created; $($existingEntries.Count) already exist." -ForegroundColor Yellow
        return
    }

    $created = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $missingEntries) {
        New-Item -ItemType Directory -Path $entry.FullPath -Force | Out-Null
        $created.Add($entry.FullPath) | Out-Null
    }

    Write-Host ""
    Write-Host "Create summary:" -ForegroundColor Yellow
    Write-Host "  created: $(if ($created.Count -gt 0) { $created.Count } else { 0 })" -ForegroundColor DarkGray
    foreach ($path in $created) {
        Write-Host "    $path" -ForegroundColor DarkGray
    }
    Write-Host "  already existed: $($existingEntries.Count)" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "Next:" -ForegroundColor Yellow
    Write-Host "  adp workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-Host "  adp workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
}

function Get-WorkspaceDevContainerStatus {
    param([string]$ProjectPath)

    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        return [pscustomobject]@{
            Level  = "INFO"
            Status = "not checked"
            Detail = "project path missing"
        }
    }

    if (-not (Test-Path -LiteralPath $ProjectPath)) {
        return [pscustomobject]@{
            Level  = "INFO"
            Status = "not checked"
            Detail = "project path missing"
        }
    }

    $nested = Join-Path (Join-Path $ProjectPath ".devcontainer") "devcontainer.json"
    if (Test-Path -LiteralPath $nested) {
        return [pscustomobject]@{
            Level  = "OK"
            Status = "found"
            Detail = ".devcontainer/devcontainer.json"
        }
    }

    $root = Join-Path $ProjectPath ".devcontainer.json"
    if (Test-Path -LiteralPath $root) {
        return [pscustomobject]@{
            Level  = "OK"
            Status = "found"
            Detail = ".devcontainer.json"
        }
    }

    return [pscustomobject]@{
        Level  = "INFO"
        Status = "not found"
        Detail = "Docker/dev container metadata can still be used inside the ADP runtime"
    }
}

function Get-WorkspaceTasksForProject {
    param(
        [object]$Manifest,
        [object]$Project
    )

    $tasks = Get-WorkspaceArray $Manifest.tasks
    $projects = Get-WorkspaceArray $Manifest.projects
    $projectName = if ($Project.name) { [string]$Project.name } else { "" }
    $runtimeName = if ($Project.runtime) { [string]$Project.runtime } else { "" }
    $runtimeProjectCount = @($projects | Where-Object { $_.runtime -eq $runtimeName }).Count
    $matched = [System.Collections.Generic.List[object]]::new()

    foreach ($task in $tasks) {
        $taskProject = if ($task.PSObject.Properties.Name -contains "project") { [string]$task.project } else { "" }
        if (-not [string]::IsNullOrWhiteSpace($taskProject)) {
            if ($taskProject -eq $projectName) {
                $matched.Add($task) | Out-Null
            }
            continue
        }

        if (-not [string]::IsNullOrWhiteSpace($runtimeName) -and $runtimeProjectCount -eq 1 -and $task.runtime -eq $runtimeName) {
            $matched.Add($task) | Out-Null
        }
    }

    return @($matched.ToArray())
}

function Get-WorkspaceSyncHygieneStatus {
    param(
        [object]$Project,
        [string]$ProjectPath
    )

    $syncExpected = ($null -ne $Project.sync -and [bool]$Project.sync)
    if (-not $syncExpected) {
        return [pscustomobject]@{
            Level  = "INFO"
            Status = "not requested"
            Detail = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($ProjectPath) -or -not (Test-Path -LiteralPath $ProjectPath)) {
        return [pscustomobject]@{
            Level  = "INFO"
            Status = "not checked"
            Detail = "project path missing"
        }
    }

    if ([string]::IsNullOrWhiteSpace([string]$Project.runtime) -or -not (Test-RuntimeExists $Project.runtime)) {
        return [pscustomobject]@{
            Level  = "INFO"
            Status = "not checked"
            Detail = "runtime missing or unknown"
        }
    }

    $generatedNames = @(
        "node_modules",
        ".venv",
        "venv",
        "dist",
        "build",
        ".next",
        ".turbo",
        ".cache",
        ".parcel-cache",
        ".vite",
        ".nuxt",
        ".svelte-kit",
        "playwright-report",
        "test-results",
        "blob-report",
        ".playwright",
        ".pytest_cache",
        ".mypy_cache",
        ".ruff_cache",
        ".tox",
        ".nox",
        ".coverage",
        "htmlcov",
        "__pycache__"
    )

    $present = @($generatedNames | Where-Object { Test-Path -LiteralPath (Join-Path $ProjectPath $_) })
    if ($present.Count -eq 0) {
        return [pscustomobject]@{
            Level  = "OK"
            Status = "clean"
            Detail = "no common generated directories found"
        }
    }

    try {
        $runtime = Get-RuntimeConfig $Project.runtime
        $profile = Get-SyncProfile $runtime.sync_profile
        $ignored = @($profile.ignore | ForEach-Object { [string]$_ })
        $notIgnored = @($present | Where-Object { $_ -notin $ignored })

        if ($notIgnored.Count -gt 0) {
            return [pscustomobject]@{
                Level  = "WARN"
                Status = "review ignore"
                Detail = "not ignored by sync profile '$($runtime.sync_profile)': $($notIgnored -join ', ')"
            }
        }

        return [pscustomobject]@{
            Level  = "OK"
            Status = "covered"
            Detail = "generated directories ignored by sync profile '$($runtime.sync_profile)': $($present -join ', ')"
        }
    } catch {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "status unavailable"
            Detail = "$_"
        }
    }
}

function Test-WorkspaceCheckpointWaived {
    param([object]$RecordedState)

    if (-not $RecordedState) {
        return $false
    }

    if ($RecordedState.PSObject.Properties.Name -contains "checkpoint" -and $RecordedState.checkpoint) {
        $checkpoint = $RecordedState.checkpoint
        if ($checkpoint.PSObject.Properties.Name -contains "status" -and ([string]$checkpoint.status).ToLowerInvariant() -eq "waived") {
            return $true
        }
    }

    if ($RecordedState.PSObject.Properties.Name -contains "state" -and ([string]$RecordedState.state).ToLowerInvariant() -eq "checkpoint-waived") {
        return $true
    }

    return $false
}

function Get-WorkspaceCheckpointWaiverText {
    param([object]$RecordedState)

    if (-not (Test-WorkspaceCheckpointWaived -RecordedState $RecordedState)) {
        return ""
    }

    $updatedAt = $null
    if ($RecordedState.PSObject.Properties.Name -contains "checkpoint" -and $RecordedState.checkpoint) {
        $checkpoint = $RecordedState.checkpoint
        if ($checkpoint.PSObject.Properties.Name -contains "updated_at" -and -not [string]::IsNullOrWhiteSpace([string]$checkpoint.updated_at)) {
            $updatedAt = [string]$checkpoint.updated_at
        }
    }
    if (-not $updatedAt -and $RecordedState.PSObject.Properties.Name -contains "updated_at" -and -not [string]::IsNullOrWhiteSpace([string]$RecordedState.updated_at)) {
        $updatedAt = [string]$RecordedState.updated_at
    }

    if ($updatedAt) {
        return "; waiver recorded at $updatedAt"
    }

    return ""
}

function Get-WorkspaceTaskSyncHygieneStatus {
    param(
        [object]$Manifest,
        [object]$Task
    )

    try {
        $project = Find-WorkspaceProjectForTask -Manifest $Manifest -Task $Task
        $projectPath = Resolve-ProjectWorkspacePath -Project $project
        return [pscustomobject]@{
            Project = $project
            ProjectPath = $projectPath
            Hygiene = (Get-WorkspaceSyncHygieneStatus -Project $project -ProjectPath $projectPath)
        }
    } catch {
        return [pscustomobject]@{
            Project = $null
            ProjectPath = ""
            Hygiene = [pscustomobject]@{
                Level  = "WARN"
                Status = "not checked"
                Detail = "$_"
            }
        }
    }
}

function Test-WorkspaceSyncHygieneBlocking {
    param([object]$SyncHygiene)

    return ($SyncHygiene -and $SyncHygiene.Level -in @("WARN", "FAIL") -and $SyncHygiene.Status -ne "not checked")
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
    param(
        [object]$Manifest,
        [string]$StatePath
    )

    Write-Host "Workspace readiness: $($Manifest.name)" -ForegroundColor Cyan
    Write-Host "Status only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, and no validation or evaluation commands will be run." -ForegroundColor DarkGray

    $projects = Get-WorkspaceArray $Manifest.projects
    $tasks = Get-WorkspaceArray $Manifest.tasks
    $milestones = Get-WorkspaceMilestones -Manifest $Manifest
    $evaluations = Get-WorkspaceEvaluations -Manifest $Manifest
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $projectCount = $projects.Count
    $taskCount = $tasks.Count
    $milestoneCount = $milestones.Count
    $evaluationCount = $evaluations.Count
    Write-Host ""
    Write-Host "Manifest:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "manifest loaded" -Detail "(projects: $projectCount, tasks: $taskCount, milestones: $milestoneCount, evaluations: $evaluationCount)"
    Write-WorkspaceCheck -Level "INFO" -Name "local state" -Detail "($resolvedStatePath)"
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
            $devContainerStatus = Get-WorkspaceDevContainerStatus -ProjectPath $projectPath
            Write-WorkspaceCheck -Level $devContainerStatus.Level -Name "devcontainer" -Detail "($($devContainerStatus.Status): $($devContainerStatus.Detail))"
            $syncHygieneStatus = Get-WorkspaceSyncHygieneStatus -Project $project -ProjectPath $projectPath
            Write-WorkspaceCheck -Level $syncHygieneStatus.Level -Name "sync hygiene" -Detail "($($syncHygieneStatus.Status)$(if ($syncHygieneStatus.Detail) { ': ' + $syncHygieneStatus.Detail }))"
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

    if ($milestoneCount -gt 0) {
        Write-Host ""
        Write-Host "Milestones:" -ForegroundColor Yellow
        foreach ($milestone in $milestones) {
            $name = if ($milestone.name) { [string]$milestone.name } else { "(unnamed)" }
            $status = Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $milestone
            Write-Host "  - $name" -ForegroundColor DarkGray
            Write-WorkspaceCheck -Level $status.Level -Name "checkpoint" -Detail "(runtime: $($status.RuntimeName); snapshot: $($status.SnapshotName); tasks: $($status.TaskNames.Count))"
            Write-WorkspaceCheck -Level $status.SnapshotNaming.Level -Name "snapshot naming" -Detail "($($status.SnapshotNaming.Status): $($status.SnapshotNaming.Detail))"
            Write-WorkspaceCheck -Level $status.SnapshotStatus.Level -Name "snapshot" -Detail "($($status.SnapshotStatus.Status)$(if ($status.SnapshotStatus.Detail) { ': ' + $status.SnapshotStatus.Detail }))"
            Write-Host "      linked tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' })" -ForegroundColor DarkGray
        }
    }

    if ($evaluationCount -gt 0) {
        Write-Host ""
        Write-Host "Evaluations:" -ForegroundColor Yellow
        Write-Host "  Evaluation hooks are plan-only here; no evaluation commands will be run." -ForegroundColor DarkGray
        foreach ($evaluation in $evaluations) {
            $status = Get-WorkspaceEvaluationStatus -Manifest $Manifest -Evaluation $evaluation
            Write-Host "  - $($status.Name)" -ForegroundColor DarkGray
            Write-WorkspaceCheck -Level $status.Level -Name "evaluation plan" -Detail "(readiness: $($status.Readiness); runtime: $($status.RuntimeName); project: $($status.ProjectName); cadence: $($status.Cadence); tasks: $($status.TaskNames.Count); metrics: $($status.Metrics.Count); commands: $($status.Commands.Count))"
            Write-Host "      linked tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' })" -ForegroundColor DarkGray
            Write-Host "      blockers: $(if ($status.Blockers.Count -gt 0) { $status.Blockers -join ', ' } else { 'none' })" -ForegroundColor DarkGray
        }
    }

    if ($taskCount -gt 0) {
        Write-Host ""
        Write-Host "Tasks:" -ForegroundColor Yellow
        foreach ($task in $tasks) {
            $taskName = if ($task.name) { $task.name } else { "(unnamed)" }
            Write-Host "  - $taskName" -ForegroundColor DarkGray
            $taskMilestones = Get-WorkspaceTaskMilestones -Manifest $Manifest -Task $task
            if ($taskMilestones.Count -gt 0) {
                $taskMilestoneNames = @($taskMilestones | ForEach-Object { if ($_.name) { [string]$_.name } })
                Write-WorkspaceCheck -Level "INFO" -Name "milestone" -Detail "($($taskMilestoneNames -join ', '))"
            }
            $taskEvaluations = Get-WorkspaceTaskEvaluations -Manifest $Manifest -Task $task
            if ($taskEvaluations.Count -gt 0) {
                $taskEvaluationNames = @($taskEvaluations | ForEach-Object { if ($_.name) { [string]$_.name } })
                Write-WorkspaceCheck -Level "INFO" -Name "evaluation" -Detail "($($taskEvaluationNames -join ', '))"
            }
            $risk = Get-WorkspaceTaskRisk -Task $task
            $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $task
            Write-WorkspaceCheck -Level "INFO" -Name "risk" -Detail "($risk; requires snapshot: $requiresSnapshot)"
            $snapshotNaming = Get-WorkspaceSnapshotNamingStatus -Task $task
            Write-WorkspaceCheck -Level $snapshotNaming.Level -Name "snapshot naming" -Detail "($($snapshotNaming.Status): $($snapshotNaming.Detail))"
            $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $task.runtime -SnapshotName $task.snapshot
            Write-WorkspaceCheck -Level $snapshotStatus.Level -Name "snapshot" -Detail "($($snapshotStatus.Status)$(if ($snapshotStatus.Detail) { ': ' + $snapshotStatus.Detail }))"
            $recordedState = Get-WorkspaceTaskState -State $state -TaskName $taskName
            $snapshotGate = Get-WorkspaceSnapshotGate -Task $task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
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
    Write-Host "Dashboard only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation or evaluation commands will be run, and no Git commands will be run." -ForegroundColor DarkGray

    $projects = Get-WorkspaceArray $Manifest.projects
    $tasks = Get-WorkspaceArray $Manifest.tasks
    $milestones = Get-WorkspaceMilestones -Manifest $Manifest
    $evaluations = Get-WorkspaceEvaluations -Manifest $Manifest
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath

    Write-Host ""
    Write-Host "Overview:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "manifest" -Detail "(projects: $($projects.Count), tasks: $($tasks.Count), milestones: $($milestones.Count), evaluations: $($evaluations.Count), path: $ManifestPath)"
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
        $devContainerStatus = Get-WorkspaceDevContainerStatus -ProjectPath $projectPath
        $syncHygieneStatus = Get-WorkspaceSyncHygieneStatus -Project $project -ProjectPath $projectPath
        $projectLevel = Select-WorstWorkspaceLevel -Levels @($pathLevel, $runtimeStatus.Level, $syncStatus.Level, $syncHygieneStatus.Level, $validationLevel)

        $pathDetail = if ($projectPath) { $projectPath } else { "missing" }
        Write-WorkspaceCheck -Level $projectLevel -Name $projectName -Detail "(path: $pathDetail; runtime: $($runtimeStatus.Status); sync: $($syncStatus.Status); sync hygiene: $($syncHygieneStatus.Status); validation: $($validationCommands.Count); devcontainer: $($devContainerStatus.Status))"
    }

    Write-Host ""
    Write-Host "Milestone checkpoints:" -ForegroundColor Yellow
    if ($milestones.Count -eq 0) {
        Write-WorkspaceCheck -Level "INFO" -Name "milestones" -Detail "(none configured)"
    }

    foreach ($milestone in $milestones) {
        $name = if ($milestone.name) { [string]$milestone.name } else { "(unnamed)" }
        $status = Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $milestone
        Write-WorkspaceCheck -Level $status.Level -Name $name -Detail "(runtime: $($status.RuntimeName); snapshot: $($status.SnapshotName); snapshot naming: $($status.SnapshotNaming.Status); snapshot: $($status.SnapshotStatus.Status); tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' }))"
    }

    Write-Host ""
    Write-Host "Evaluation hooks:" -ForegroundColor Yellow
    if ($evaluations.Count -eq 0) {
        Write-WorkspaceCheck -Level "INFO" -Name "evaluations" -Detail "(none configured)"
    }

    foreach ($evaluation in $evaluations) {
        $status = Get-WorkspaceEvaluationStatus -Manifest $Manifest -Evaluation $evaluation
        Write-WorkspaceCheck -Level $status.Level -Name $status.Name -Detail "(readiness: $($status.Readiness); runtime: $($status.RuntimeName); project: $($status.ProjectName); metrics: $($status.Metrics.Count); commands: $($status.Commands.Count); tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' }))"
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
        $snapshotNaming = Get-WorkspaceSnapshotNamingStatus -Task $task
        $validationCommands = Get-WorkspaceArray $task.validation
        $syncContext = Get-WorkspaceTaskSyncHygieneStatus -Manifest $Manifest -Task $task
        $syncHygiene = $syncContext.Hygiene
        $recordedState = Get-WorkspaceTaskState -State $state -TaskName $taskName
        $snapshotGate = Get-WorkspaceSnapshotGate -Task $task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
        $taskMilestones = Get-WorkspaceTaskMilestones -Manifest $Manifest -Task $task
        $milestoneNames = @($taskMilestones | ForEach-Object { if ($_.name) { [string]$_.name } })
        $milestoneText = if ($milestoneNames.Count -gt 0) { $milestoneNames -join ', ' } else { "none" }
        $taskEvaluations = Get-WorkspaceTaskEvaluations -Manifest $Manifest -Task $task
        $evaluationNames = @($taskEvaluations | ForEach-Object { if ($_.name) { [string]$_.name } })
        $evaluationText = if ($evaluationNames.Count -gt 0) { $evaluationNames -join ', ' } else { "none" }
        $validationLevel = if ($validationCommands.Count -gt 0) { "OK" } else { "WARN" }
        $taskLevel = Select-WorstWorkspaceLevel -Levels @($runtimeStatus.Level, $snapshotStatus.Level, $snapshotGate.Level, $snapshotNaming.Level, $syncHygiene.Level, $validationLevel)

        $executionState = if ($snapshotGate.Blocking) {
            "blocked by snapshot gate"
        } elseif ($runtimeStatus.Level -eq "OK" -and $snapshotStatus.Level -eq "OK" -and $validationCommands.Count -gt 0) {
            "ready"
        } elseif ($runtimeStatus.Level -eq "FAIL" -or $validationCommands.Count -eq 0) {
            "blocked"
        } else {
            "gated"
        }
        $risk = Get-WorkspaceTaskRisk -Task $task
        $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $task
        $validationStatus = Get-WorkspaceValidationStatus -RecordedState $recordedState
        $recordedTaskState = Get-WorkspaceRecordedTaskStateName -RecordedState $recordedState
        $rollbackState = if ($task.runtime -and $task.snapshot) {
            if ($snapshotGate.Status -eq "waived") { "waived" } else { $snapshotStatus.Status }
        } else {
            "not configured"
        }
        $commitDecision = Get-WorkspaceCommitDecision -Task $task -RecordedState $recordedState -SnapshotGate $snapshotGate -ValidationCommandCount $validationCommands.Count -SyncHygiene $syncHygiene
        $commitState = $commitDecision.Verdict
        $recordedStateTime = if ($recordedState -and $recordedState.updated_at -is [datetime]) {
            $recordedState.updated_at.ToUniversalTime().ToString("o")
        } elseif ($recordedState) {
            $recordedState.updated_at
        } else {
            $null
        }
        $recordedStateText = if ($recordedState) { "$($recordedState.state) at $recordedStateTime" } else { "not recorded" }
        $validationStateText = Format-WorkspaceValidationState -RecordedState $recordedState

        Write-WorkspaceCheck -Level $taskLevel -Name $taskName -Detail "(state: $recordedStateText; milestone: $milestoneText; evaluation: $evaluationText; risk: $risk; snapshot required: $requiresSnapshot; snapshot naming: $($snapshotNaming.Status); checkpoint: $($snapshotGate.Status); runtime: $($runtimeStatus.Status); execution: $executionState; sync hygiene: $($syncHygiene.Status); validation: $($validationCommands.Count); validation result: $validationStateText; review: gated; rollback: $rollbackState; commit: $commitState)"
        Write-Host "      prepare: adp workspace task prepare $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-Host "      run:     adp workspace task run $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-Host "      review:  adp workspace task review $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    }
}

function New-WorkspaceReportItem {
    param(
        [object]$Manifest,
        [object]$Task,
        [object]$State
    )

    $taskName = if ($Task.name) { [string]$Task.name } else { "(unnamed)" }
    $recordedState = Get-WorkspaceTaskState -State $State -TaskName $taskName
    $recordedTaskState = Get-WorkspaceRecordedTaskStateName -RecordedState $recordedState
    $validationCommands = Get-WorkspaceArray $Task.validation
    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    $snapshotGate = Get-WorkspaceSnapshotGate -Task $Task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
    $snapshotNaming = Get-WorkspaceSnapshotNamingStatus -Task $Task
    $validationStatus = Get-WorkspaceValidationStatus -RecordedState $recordedState
    $risk = Get-WorkspaceTaskRisk -Task $Task
    $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $Task
    $projectName = if ($Task.PSObject.Properties.Name -contains "project" -and -not [string]::IsNullOrWhiteSpace([string]$Task.project)) { [string]$Task.project } else { "not set" }
    $syncContext = Get-WorkspaceTaskSyncHygieneStatus -Manifest $Manifest -Task $Task
    $project = $syncContext.Project
    $projectPath = $syncContext.ProjectPath
    $syncHygiene = $syncContext.Hygiene
    $taskMilestones = Get-WorkspaceTaskMilestones -Manifest $Manifest -Task $Task
    $milestoneNames = @($taskMilestones | ForEach-Object { if ($_.name) { [string]$_.name } })
    $milestoneText = if ($milestoneNames.Count -gt 0) { $milestoneNames -join ", " } else { "not set" }
    $taskEvaluations = Get-WorkspaceTaskEvaluations -Manifest $Manifest -Task $Task
    $evaluationNames = @($taskEvaluations | ForEach-Object { if ($_.name) { [string]$_.name } })
    $evaluationText = if ($evaluationNames.Count -gt 0) { $evaluationNames -join ", " } else { "not set" }
    if ($project -and $project.name) {
        $projectName = [string]$project.name
    }
    $syncHygieneBlocking = Test-WorkspaceSyncHygieneBlocking -SyncHygiene $syncHygiene
    $reviewDecision = Get-WorkspaceReviewDecision -Task $Task -RecordedState $recordedState -SnapshotGate $snapshotGate -ValidationCommandCount $validationCommands.Count -SyncHygiene $syncHygiene
    $commitDecision = Get-WorkspaceCommitDecision -Task $Task -RecordedState $recordedState -SnapshotGate $snapshotGate -ValidationCommandCount $validationCommands.Count -SyncHygiene $syncHygiene
    $runtimeName = if ($Task.runtime) { [string]$Task.runtime } else { "not configured" }
    $snapshotName = if ($Task.snapshot) { [string]$Task.snapshot } else { "not configured" }
    $ownerName = if ($Task.PSObject.Properties.Name -contains "owner" -and -not [string]::IsNullOrWhiteSpace([string]$Task.owner)) { [string]$Task.owner } else { "not set" }
    $reviewCadence = if ($Task.PSObject.Properties.Name -contains "review_cadence" -and -not [string]::IsNullOrWhiteSpace([string]$Task.review_cadence)) { [string]$Task.review_cadence } else { "not set" }
    $dueDateText = if ($Task.PSObject.Properties.Name -contains "due" -and -not [string]::IsNullOrWhiteSpace([string]$Task.due)) { [string]$Task.due } else { "not set" }
    $dueStatus = if ($dueDateText -eq "not set") {
        "not set"
    } else {
        try {
            $dueDate = [datetime]::Parse($dueDateText).Date
            $today = (Get-Date).Date
            if ($dueDate -lt $today) {
                "overdue"
            } elseif ($dueDate -le $today.AddDays(7)) {
                "due soon"
            } else {
                "scheduled"
            }
        } catch {
            "invalid"
        }
    }
    $rollbackState = if ($Task.runtime -and $Task.snapshot) {
        if ($snapshotGate.Status -eq "waived") { "waived" } else { $snapshotStatus.Status }
    } else {
        "not configured"
    }
    $action = if ($syncHygieneBlocking) {
        "review sync ignore"
    } elseif ($snapshotGate.Blocking) {
        "create snapshot"
    } elseif ($validationStatus -eq "failed") {
        "rollback or revise"
    } elseif ($validationStatus -ne "passed") {
        "validate now"
    } elseif ($commitDecision.Verdict -eq "review not recorded") {
        "review now"
    } elseif ($commitDecision.Verdict -in @("commit ready", "already marked committed")) {
        "ready to commit"
    } else {
        "inspect"
    }
    $releaseReadiness = if ($syncHygieneBlocking) {
        "release blocked"
    } elseif ($commitDecision.Verdict -in @("commit ready", "already marked committed")) {
        "release candidate"
    } elseif ($snapshotGate.Blocking -or $validationStatus -eq "failed") {
        "release blocked"
    } elseif ($validationStatus -ne "passed") {
        "validation required"
    } elseif ($commitDecision.Verdict -eq "review not recorded") {
        "review required"
    } else {
        "not ready"
    }
    if ($dueStatus -in @("overdue", "due soon") -and $releaseReadiness -eq "release candidate") {
        $releaseReadiness = "release candidate with timing attention"
    }
    $taskLevel = Select-WorstWorkspaceLevel -Levels @($syncHygiene.Level, $snapshotGate.Level, $snapshotNaming.Level, $reviewDecision.Level, $commitDecision.Level)

    return [pscustomobject]@{
        TaskName           = $taskName
        Task               = $Task
        RecordedState      = $recordedState
        RecordedTaskState  = $recordedTaskState
        ValidationCommands = $validationCommands
        ValidationStatus   = $validationStatus
        ValidationStateText = Format-WorkspaceValidationState -RecordedState $recordedState
        SnapshotStatus     = $snapshotStatus
        SnapshotGate       = $snapshotGate
        SnapshotNaming     = $snapshotNaming
        ReviewDecision     = $reviewDecision
        CommitDecision     = $commitDecision
        Risk               = $risk
        RequiresSnapshot   = $requiresSnapshot
        ProjectName        = $projectName
        ProjectPath        = $projectPath
        MilestoneNames     = $milestoneNames
        MilestoneText      = $milestoneText
        EvaluationNames    = $evaluationNames
        EvaluationText     = $evaluationText
        SyncHygiene        = $syncHygiene
        SyncHygieneBlocking = $syncHygieneBlocking
        RuntimeName        = $runtimeName
        SnapshotName       = $snapshotName
        OwnerName          = $ownerName
        ReviewCadence      = $reviewCadence
        DueDate            = $dueDateText
        DueStatus          = $dueStatus
        RollbackState      = $rollbackState
        Action             = $action
        ReleaseReadiness   = $releaseReadiness
        Level              = $taskLevel
        SnapshotBlocked    = [bool]$snapshotGate.Blocking
        CommitReady        = ($commitDecision.Verdict -in @("commit ready", "already marked committed"))
        ReviewReady        = ($reviewDecision.Verdict -eq "validation passed")
    }
}

function Write-WorkspaceReportSummary {
    param([object[]]$Items)

    $total = $Items.Count
    $passed = @($Items | Where-Object { $_.ValidationStatus -eq "passed" }).Count
    $failed = @($Items | Where-Object { $_.ValidationStatus -eq "failed" }).Count
    $missing = @($Items | Where-Object { $_.ValidationStatus -notin @("passed", "failed") }).Count
    $snapshotBlocked = @($Items | Where-Object { $_.SnapshotBlocked }).Count
    $reviewReady = @($Items | Where-Object { $_.ReviewReady }).Count
    $commitReady = @($Items | Where-Object { $_.CommitReady }).Count
    $reviewNeeded = @($Items | Where-Object { $_.CommitDecision.Verdict -eq "review not recorded" }).Count
    $validationBlocked = @($Items | Where-Object { $_.CommitDecision.Verdict -eq "blocked by validation" }).Count
    $owned = @($Items | Where-Object { $_.OwnerName -ne "not set" }).Count
    $cadenced = @($Items | Where-Object { $_.ReviewCadence -ne "not set" }).Count
    $overdue = @($Items | Where-Object { $_.DueStatus -eq "overdue" }).Count
    $dueSoon = @($Items | Where-Object { $_.DueStatus -eq "due soon" }).Count
    $milestoned = @($Items | Where-Object { $_.MilestoneText -ne "not set" }).Count
    $highestLevel = Select-WorstWorkspaceLevel -Levels @($Items | ForEach-Object { $_.Level })

    $handoffState = if ($total -eq 0) {
        "empty"
    } elseif (@($Items | Where-Object { $_.SyncHygieneBlocking }).Count -gt 0) {
        "blocked by sync hygiene"
    } elseif ($failed -gt 0 -or $validationBlocked -gt 0) {
        "blocked by validation"
    } elseif ($snapshotBlocked -gt 0) {
        "blocked by snapshot gate"
    } elseif ($missing -gt 0) {
        "needs validation"
    } elseif ($reviewNeeded -gt 0) {
        "needs review"
    } elseif ($commitReady -eq $total) {
        "ready to commit"
    } else {
        "needs review"
    }

    $blockedTasks = @($Items | Where-Object { $_.SyncHygieneBlocking -or $_.SnapshotBlocked -or $_.CommitDecision.Verdict -in @("blocked by validation", "validation result missing", "validation not configured") } | ForEach-Object { $_.TaskName })
    $reviewTasks = @($Items | Where-Object { $_.ReviewReady -and -not $_.CommitReady } | ForEach-Object { $_.TaskName })
    $commitTasks = @($Items | Where-Object { $_.CommitReady } | ForEach-Object { $_.TaskName })
    $ownerGaps = @($Items | Where-Object { $_.OwnerName -eq "not set" } | ForEach-Object { $_.TaskName })
    $cadenceGaps = @($Items | Where-Object { $_.ReviewCadence -eq "not set" } | ForEach-Object { $_.TaskName })
    $dueTasks = @($Items | Where-Object { $_.DueStatus -in @("overdue", "due soon") } | ForEach-Object { "$($_.TaskName) ($($_.DueStatus))" })

    Write-Host ""
    Write-Host "Release handoff summary:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $highestLevel -Name "handoff" -Detail "($handoffState; tasks: $total; milestones linked: $milestoned; validation passed: $passed; failed: $failed; missing: $missing; snapshot blocked: $snapshotBlocked; review ready: $reviewReady; commit ready: $commitReady; owned: $owned; cadence set: $cadenced; overdue: $overdue; due soon: $dueSoon)"
    Write-Host "     blocked tasks: $(if ($blockedTasks.Count -gt 0) { $blockedTasks -join ', ' } else { 'none' })" -ForegroundColor DarkGray
    Write-Host "     ready for review: $(if ($reviewTasks.Count -gt 0) { $reviewTasks -join ', ' } else { 'none' })" -ForegroundColor DarkGray
    Write-Host "     ready to commit: $(if ($commitTasks.Count -gt 0) { $commitTasks -join ', ' } else { 'none' })" -ForegroundColor DarkGray
    Write-Host "     owner gaps: $(if ($ownerGaps.Count -gt 0) { $ownerGaps -join ', ' } else { 'none' })" -ForegroundColor DarkGray
    Write-Host "     cadence gaps: $(if ($cadenceGaps.Count -gt 0) { $cadenceGaps -join ', ' } else { 'none' })" -ForegroundColor DarkGray
    Write-Host "     due attention: $(if ($dueTasks.Count -gt 0) { $dueTasks -join ', ' } else { 'none' })" -ForegroundColor DarkGray
    Write-Host "     release gate: $handoffState" -ForegroundColor DarkGray
}

function Write-WorkspaceGovernanceLoop {
    param([object[]]$Items)

    $ownerGroups = @($Items | Group-Object -Property OwnerName | Sort-Object Name)
    $cadenceGroups = @($Items | Group-Object -Property ReviewCadence | Sort-Object Name)
    $attentionTasks = @($Items | Where-Object {
            $_.SnapshotBlocked -or
            $_.SyncHygieneBlocking -or
            $_.DueStatus -in @("overdue", "due soon") -or
            $_.CommitDecision.Verdict -in @("blocked by validation", "validation result missing", "validation not configured", "review not recorded")
        } | ForEach-Object {
            $reason = if ($_.SyncHygieneBlocking) { "sync hygiene: $($_.SyncHygiene.Status)" } else { $_.CommitDecision.Verdict }
            "$($_.TaskName) [$reason; due: $($_.DueStatus)]"
        })

    Write-Host ""
    Write-Host "Governance loop:" -ForegroundColor Yellow
    Write-Host "     owner queues:" -ForegroundColor DarkGray
    foreach ($group in $ownerGroups) {
        $tasks = @($group.Group | ForEach-Object { $_.TaskName })
        Write-Host "       $($group.Name): $($tasks -join ', ')" -ForegroundColor DarkGray
    }

    Write-Host "     review cadence:" -ForegroundColor DarkGray
    foreach ($group in $cadenceGroups) {
        $tasks = @($group.Group | ForEach-Object { $_.TaskName })
        Write-Host "       $($group.Name): $($tasks -join ', ')" -ForegroundColor DarkGray
    }

    Write-Host "     attention queue: $(if ($attentionTasks.Count -gt 0) { $attentionTasks -join '; ' } else { 'none' })" -ForegroundColor DarkGray
}

function Write-WorkspaceDecisionQueues {
    param([object[]]$Items)

    $actionGroups = @($Items | Group-Object -Property Action | Sort-Object Name)
    $releaseGroups = @($Items | Group-Object -Property ReleaseReadiness | Sort-Object Name)
    $milestoneGroups = @($Items | Where-Object { $_.MilestoneText -ne "not set" } | Group-Object -Property MilestoneText | Sort-Object Name)

    Write-Host ""
    Write-Host "Decision queues:" -ForegroundColor Yellow
    Write-Host "     actions:" -ForegroundColor DarkGray
    foreach ($group in $actionGroups) {
        $tasks = @($group.Group | ForEach-Object { $_.TaskName })
        Write-Host "       $($group.Name): $($tasks -join ', ')" -ForegroundColor DarkGray
    }

    Write-Host "     release readiness:" -ForegroundColor DarkGray
    foreach ($group in $releaseGroups) {
        $tasks = @($group.Group | ForEach-Object { $_.TaskName })
        Write-Host "       $($group.Name): $($tasks -join ', ')" -ForegroundColor DarkGray
    }

    Write-Host "     milestones:" -ForegroundColor DarkGray
    if ($milestoneGroups.Count -eq 0) {
        Write-Host "       none: no milestone-linked tasks" -ForegroundColor DarkGray
    }
    foreach ($group in $milestoneGroups) {
        $tasks = @($group.Group | ForEach-Object { $_.TaskName })
        Write-Host "       $($group.Name): $($tasks -join ', ')" -ForegroundColor DarkGray
    }
}

function Write-WorkspaceMilestoneCheckpoints {
    param(
        [object]$Manifest,
        [object[]]$Milestones
    )

    Write-Host ""
    Write-Host "Milestone checkpoints:" -ForegroundColor Yellow
    if ($Milestones.Count -eq 0) {
        Write-Host "     milestones: none configured" -ForegroundColor DarkGray
        return
    }

    foreach ($milestone in $Milestones) {
        $status = Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $milestone
        Write-WorkspaceCheck -Level $status.Level -Name $status.Name -Detail "(runtime: $($status.RuntimeName); snapshot: $($status.SnapshotName); snapshot: $($status.SnapshotStatus.Status); naming: $($status.SnapshotNaming.Status); tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' }))"
        if ($milestone.description) {
            Write-Host "       description: $($milestone.description)" -ForegroundColor DarkGray
        }
        if ($status.RuntimeName -ne "not configured") {
            Write-Host "       checkpoint command: adp snapshot create $($status.RuntimeName) $($status.SnapshotName)" -ForegroundColor DarkGray
        } else {
            Write-Host "       checkpoint command: set milestones[].runtime or use tasks from a single runtime first" -ForegroundColor DarkGray
        }
    }
}

function Get-WorkspaceMilestoneReviewRollups {
    param([object[]]$Items)

    $groups = @($Items | Where-Object { $_.MilestoneText -ne "not set" } | Group-Object -Property MilestoneText | Sort-Object Name)
    $rollups = [System.Collections.Generic.List[object]]::new()

    foreach ($group in $groups) {
        $groupItems = @($group.Group)
        $blocked = @($groupItems | Where-Object { $_.SyncHygieneBlocking -or $_.SnapshotBlocked -or $_.ReleaseReadiness -eq "release blocked" } | ForEach-Object { $_.TaskName })
        $validationRequired = @($groupItems | Where-Object { $_.ReleaseReadiness -eq "validation required" } | ForEach-Object { $_.TaskName })
        $reviewRequired = @($groupItems | Where-Object { $_.ReleaseReadiness -eq "review required" } | ForEach-Object { $_.TaskName })
        $readyToCommit = @($groupItems | Where-Object { $_.CommitReady } | ForEach-Object { $_.TaskName })
        $owners = @($groupItems | ForEach-Object { $_.OwnerName } | Where-Object { $_ -and $_ -ne "not set" } | Select-Object -Unique)
        $dueAttention = @($groupItems | Where-Object { $_.DueStatus -in @("overdue", "due soon") } | ForEach-Object { "$($_.TaskName) ($($_.DueStatus))" })
        $actions = @($groupItems | Group-Object -Property Action | Sort-Object Name | ForEach-Object { "$($_.Name): $(@($_.Group | ForEach-Object { $_.TaskName }) -join ', ')" })
        $releaseStates = @($groupItems | Group-Object -Property ReleaseReadiness | Sort-Object Name | ForEach-Object { "$($_.Name): $(@($_.Group | ForEach-Object { $_.TaskName }) -join ', ')" })
        $level = Select-WorstWorkspaceLevel -Levels @($groupItems | ForEach-Object { $_.Level })

        $rollups.Add([pscustomobject]@{
                Milestone          = [string]$group.Name
                Level              = $level
                TaskCount          = $groupItems.Count
                Actions            = $actions
                ReleaseStates      = $releaseStates
                Blocked            = $blocked
                ValidationRequired = $validationRequired
                ReviewRequired     = $reviewRequired
                ReadyToCommit      = $readyToCommit
                Owners             = $owners
                DueAttention       = $dueAttention
            }) | Out-Null
    }

    return @($rollups)
}

function Write-WorkspaceMilestoneReviewRollup {
    param([object[]]$Items)

    $rollups = Get-WorkspaceMilestoneReviewRollups -Items $Items

    Write-Host ""
    Write-Host "Milestone review rollup:" -ForegroundColor Yellow
    if ($rollups.Count -eq 0) {
        Write-Host "     milestones: no milestone-linked tasks" -ForegroundColor DarkGray
        return
    }

    foreach ($rollup in $rollups) {
        Write-WorkspaceCheck -Level $rollup.Level -Name $rollup.Milestone -Detail "(tasks: $($rollup.TaskCount); blocked: $($rollup.Blocked.Count); validation required: $($rollup.ValidationRequired.Count); review required: $($rollup.ReviewRequired.Count); ready to commit: $($rollup.ReadyToCommit.Count))"
        Write-Host "       actions: $(if ($rollup.Actions.Count -gt 0) { $rollup.Actions -join '; ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       release: $(if ($rollup.ReleaseStates.Count -gt 0) { $rollup.ReleaseStates -join '; ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       blocked tasks: $(if ($rollup.Blocked.Count -gt 0) { $rollup.Blocked -join ', ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       validation required: $(if ($rollup.ValidationRequired.Count -gt 0) { $rollup.ValidationRequired -join ', ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       review required: $(if ($rollup.ReviewRequired.Count -gt 0) { $rollup.ReviewRequired -join ', ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       ready to commit: $(if ($rollup.ReadyToCommit.Count -gt 0) { $rollup.ReadyToCommit -join ', ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       owners: $(if ($rollup.Owners.Count -gt 0) { $rollup.Owners -join ', ' } else { 'not set' })" -ForegroundColor DarkGray
        Write-Host "       due attention: $(if ($rollup.DueAttention.Count -gt 0) { $rollup.DueAttention -join ', ' } else { 'none' })" -ForegroundColor DarkGray
    }
}

function Get-WorkspaceValidationQueueItems {
    param(
        [object[]]$Items,
        [string]$ManifestPath
    )

    $queue = [System.Collections.Generic.List[object]]::new()
    foreach ($item in $Items) {
        $blockers = [System.Collections.Generic.List[string]]::new()
        if ($item.ValidationCommands.Count -eq 0) {
            $blockers.Add("validation not configured") | Out-Null
        }
        if ($item.SyncHygieneBlocking) {
            $blockers.Add("sync hygiene: $($item.SyncHygiene.Status)") | Out-Null
        }
        if ($item.SnapshotBlocked) {
            $blockers.Add("snapshot-first gate: $($item.SnapshotGate.Status)") | Out-Null
        }

        $readiness = if ($item.ValidationStatus -eq "passed") {
            "already passed"
        } elseif ($item.ValidationStatus -eq "failed") {
            "rerun after fix"
        } elseif ($blockers.Count -gt 0) {
            "blocked"
        } else {
            "ready to execute"
        }

        $level = if ($readiness -eq "already passed") {
            "OK"
        } elseif ($readiness -eq "ready to execute" -or $readiness -eq "rerun after fix") {
            "WARN"
        } else {
            "FAIL"
        }

        $base = "adp workspace task validate $($item.TaskName) -ManifestPath $ManifestPath"
        $queue.Add([pscustomobject]@{
                TaskName       = $item.TaskName
                Level          = $level
                Validation     = $item.ValidationStateText
                CommandCount   = $item.ValidationCommands.Count
                Readiness      = $readiness
                Blockers       = @($blockers)
                PlanCommand    = $base
                ExecutePreview = "adp workspace task validate $($item.TaskName) -Execute -Plan -ManifestPath $ManifestPath"
                ExecuteCommand = "adp workspace task validate $($item.TaskName) -Execute -ManifestPath $ManifestPath"
            }) | Out-Null
    }

    return @($queue)
}

function Write-WorkspaceValidationQueue {
    param(
        [object[]]$Items,
        [string]$ManifestPath
    )

    $queue = Get-WorkspaceValidationQueueItems -Items $Items -ManifestPath $ManifestPath

    Write-Host ""
    Write-Host "Validation execution queue:" -ForegroundColor Yellow
    if ($queue.Count -eq 0) {
        Write-Host "     validation: no tasks configured" -ForegroundColor DarkGray
        return
    }

    foreach ($entry in $queue) {
        Write-WorkspaceCheck -Level $entry.Level -Name $entry.TaskName -Detail "(validation: $($entry.Validation); commands: $($entry.CommandCount); readiness: $($entry.Readiness))"
        Write-Host "       blockers: $(if ($entry.Blockers.Count -gt 0) { $entry.Blockers -join ', ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       plan: $($entry.PlanCommand)" -ForegroundColor DarkGray
        Write-Host "       execute preview: $($entry.ExecutePreview)" -ForegroundColor DarkGray
        Write-Host "       execute: $($entry.ExecuteCommand)" -ForegroundColor DarkGray
    }
}

function Get-WorkspaceEvaluationQueueItems {
    param(
        [object]$Manifest,
        [string]$ManifestPath
    )

    $queue = [System.Collections.Generic.List[object]]::new()
    foreach ($evaluation in (Get-WorkspaceEvaluations -Manifest $Manifest)) {
        $status = Get-WorkspaceEvaluationStatus -Manifest $Manifest -Evaluation $evaluation
        $base = "adp workspace report -ManifestPath $ManifestPath"
        $queue.Add([pscustomobject]@{
                Name          = $status.Name
                Level         = $status.Level
                Readiness     = $status.Readiness
                RuntimeName   = $status.RuntimeName
                ProjectName   = $status.ProjectName
                Cadence       = $status.Cadence
                Metrics       = @($status.Metrics)
                Commands      = @($status.Commands)
                TaskNames     = @($status.TaskNames)
                Blockers      = @($status.Blockers)
                ReportCommand = $base
            }) | Out-Null
    }

    return @($queue)
}

function Write-WorkspaceEvaluationQueue {
    param(
        [object]$Manifest,
        [string]$ManifestPath
    )

    $queue = Get-WorkspaceEvaluationQueueItems -Manifest $Manifest -ManifestPath $ManifestPath

    Write-Host ""
    Write-Host "Evaluation queue:" -ForegroundColor Yellow
    Write-Host "     Evaluation queue only: no evaluation commands will be run." -ForegroundColor DarkGray
    if ($queue.Count -eq 0) {
        Write-Host "     evaluations: none configured" -ForegroundColor DarkGray
        return
    }

    foreach ($entry in $queue) {
        Write-WorkspaceCheck -Level $entry.Level -Name $entry.Name -Detail "(readiness: $($entry.Readiness); runtime: $($entry.RuntimeName); project: $($entry.ProjectName); cadence: $($entry.Cadence); metrics: $($entry.Metrics.Count); commands: $($entry.Commands.Count); tasks: $(if ($entry.TaskNames.Count -gt 0) { $entry.TaskNames -join ', ' } else { 'none' }))"
        Write-Host "       blockers: $(if ($entry.Blockers.Count -gt 0) { $entry.Blockers -join ', ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       metrics: $(if ($entry.Metrics.Count -gt 0) { $entry.Metrics -join ', ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       commands: $(if ($entry.Commands.Count -gt 0) { $entry.Commands -join '; ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       evidence: $($entry.ReportCommand)" -ForegroundColor DarkGray
    }
}

function Write-WorkspaceRecipes {
    param(
        [object]$Manifest,
        [string]$ManifestPath,
        [string]$StatePath
    )

    Write-Host "Workspace recipes: $($Manifest.name)" -ForegroundColor Cyan
    Write-Host "Recipes only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation or evaluation commands will be run, no SSH connection will be opened, and no Git commands will be run." -ForegroundColor DarkGray

    $projects = Get-WorkspaceArray $Manifest.projects
    $tasks = Get-WorkspaceArray $Manifest.tasks
    $milestones = Get-WorkspaceMilestones -Manifest $Manifest
    $evaluations = Get-WorkspaceEvaluations -Manifest $Manifest
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $reportItems = @($tasks | ForEach-Object { New-WorkspaceReportItem -Manifest $Manifest -Task $_ -State $state })

    Write-Host ""
    Write-Host "Overview:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "manifest" -Detail "(projects: $($projects.Count), tasks: $($tasks.Count), milestones: $($milestones.Count), evaluations: $($evaluations.Count), path: $ManifestPath)"
    Write-WorkspaceCheck -Level "INFO" -Name "state" -Detail "(path: $resolvedStatePath)"
    Write-Host "     recipes are discovery and planning records; use explicit lifecycle commands when you choose to execute work." -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Project recipes:" -ForegroundColor Yellow
    if ($projects.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "projects" -Detail "(none configured)"
    }

    foreach ($project in $projects) {
        $projectName = if ($project.name) { [string]$project.name } else { "(unnamed)" }
        $runtimeName = if ($project.runtime) { [string]$project.runtime } else { "not configured" }
        $localPath = Resolve-ProjectWorkspacePath -Project $project
        $remotePath = ""
        try {
            $remotePath = Resolve-WorkspaceRemoteProjectPath -Project $project
        } catch {
            $remotePath = "unavailable: $_"
        }
        $validationCommands = Get-WorkspaceArray $project.validation
        $syncExpected = ($null -ne $project.sync -and [bool]$project.sync)
        $devContainerStatus = Get-WorkspaceDevContainerStatus -ProjectPath $localPath
        $syncHygieneStatus = Get-WorkspaceSyncHygieneStatus -Project $project -ProjectPath $localPath
        $linkedTasks = Get-WorkspaceTasksForProject -Manifest $Manifest -Project $project
        $level = if ($validationCommands.Count -gt 0) { $syncHygieneStatus.Level } else { Select-WorstWorkspaceLevel -Levels @($syncHygieneStatus.Level, "WARN") }

        Write-WorkspaceCheck -Level $level -Name $projectName -Detail "(runtime: $runtimeName; sync: $(if ($syncExpected) { 'requested' } else { 'not requested' }); validation commands: $($validationCommands.Count); linked tasks: $($linkedTasks.Count); devcontainer: $($devContainerStatus.Status); sync hygiene: $($syncHygieneStatus.Status))"
        Write-Host "       local path:  $(if ($localPath) { $localPath } else { 'not configured' })" -ForegroundColor DarkGray
        Write-Host "       remote path: $remotePath" -ForegroundColor DarkGray
        if ($validationCommands.Count -gt 0) {
            Write-Host "       validation recipe:" -ForegroundColor DarkGray
            foreach ($command in $validationCommands) {
                Write-Host "         - $command" -ForegroundColor DarkGray
            }
        } else {
            Write-Host "       validation recipe: none configured" -ForegroundColor Yellow
        }
        Write-Host "       next: adp workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-Host "       sync: adp workspace sync $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-Host "       lifecycle: adp workspace project $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Task recipes:" -ForegroundColor Yellow
    if ($reportItems.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "tasks" -Detail "(none configured)"
    }

    foreach ($item in $reportItems) {
        $task = $item.Task
        $validationCommands = Get-WorkspaceArray $task.validation
        $evaluationText = if ($item.EvaluationText -ne "not set") { $item.EvaluationText } else { "none" }
        $milestoneText = if ($item.MilestoneText -ne "not set") { $item.MilestoneText } else { "none" }
        $level = if ($item.SnapshotBlocked -or $item.SyncHygieneBlocking) { "FAIL" } elseif ($validationCommands.Count -gt 0) { "WARN" } else { "WARN" }

        Write-WorkspaceCheck -Level $level -Name $item.TaskName -Detail "(project: $($item.ProjectName); runtime: $($item.RuntimeName); risk: $($item.Risk); snapshot required: $($item.RequiresSnapshot); milestone: $milestoneText; evaluation: $evaluationText; action: $($item.Action); release: $($item.ReleaseReadiness))"
        Write-Host "       snapshot: $($item.SnapshotName); gate: $($item.SnapshotGate.Status); naming: $($item.SnapshotNaming.Status)" -ForegroundColor DarkGray
        Write-Host "       validation recipe: $($validationCommands.Count) command(s)" -ForegroundColor DarkGray
        foreach ($command in $validationCommands) {
            Write-Host "         - $command" -ForegroundColor DarkGray
        }
        Write-Host "       prepare: adp workspace task prepare $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        if ($item.RequiresSnapshot) {
            if ($item.SnapshotName -ne "not configured") {
                Write-Host "       checkpoint: adp snapshot create $($item.RuntimeName) $($item.SnapshotName)" -ForegroundColor DarkGray
            } else {
                Write-Host "       checkpoint: set tasks[].snapshot before creating a task checkpoint" -ForegroundColor Yellow
            }
        }
        Write-Host "       validate plan: adp workspace task validate $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-Host "       execute preview: adp workspace task validate $($item.TaskName) -Execute -Plan -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-Host "       review: adp workspace task review $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Milestone recipes:" -ForegroundColor Yellow
    if ($milestones.Count -eq 0) {
        Write-WorkspaceCheck -Level "INFO" -Name "milestones" -Detail "(none configured)"
    }
    foreach ($milestone in $milestones) {
        $status = Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $milestone
        Write-WorkspaceCheck -Level $status.Level -Name $status.Name -Detail "(runtime: $($status.RuntimeName); snapshot: $($status.SnapshotName); tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' }))"
        Write-Host "       checkpoint command: adp snapshot create $($status.RuntimeName) $($status.SnapshotName)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Evaluation recipes:" -ForegroundColor Yellow
    Write-Host "     Evaluation hooks are plan-only; evaluation commands are listed for evidence and are not executed." -ForegroundColor DarkGray
    if ($evaluations.Count -eq 0) {
        Write-WorkspaceCheck -Level "INFO" -Name "evaluations" -Detail "(none configured)"
    }
    foreach ($entry in (Get-WorkspaceEvaluationQueueItems -Manifest $Manifest -ManifestPath $ManifestPath)) {
        Write-WorkspaceCheck -Level $entry.Level -Name $entry.Name -Detail "(readiness: $($entry.Readiness); runtime: $($entry.RuntimeName); project: $($entry.ProjectName); cadence: $($entry.Cadence); metrics: $($entry.Metrics.Count); commands: $($entry.Commands.Count); tasks: $(if ($entry.TaskNames.Count -gt 0) { $entry.TaskNames -join ', ' } else { 'none' }))"
        Write-Host "       metrics: $(if ($entry.Metrics.Count -gt 0) { $entry.Metrics -join ', ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       commands: $(if ($entry.Commands.Count -gt 0) { $entry.Commands -join '; ' } else { 'none' })" -ForegroundColor DarkGray
        Write-Host "       evidence: $($entry.ReportCommand)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Evidence commands:" -ForegroundColor Yellow
    Write-Host "  adp workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-Host "  adp workspace report -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-Host "  adp workspace report -Markdown -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
}

function Write-WorkspaceReleasePolicy {
    param([object[]]$Items)

    $releaseBlocked = @($Items | Where-Object { $_.ReleaseReadiness -eq "release blocked" } | ForEach-Object { $_.TaskName })
    $validationRequired = @($Items | Where-Object { $_.ReleaseReadiness -eq "validation required" } | ForEach-Object { $_.TaskName })
    $reviewRequired = @($Items | Where-Object { $_.ReleaseReadiness -eq "review required" } | ForEach-Object { $_.TaskName })
    $releaseCandidates = @($Items | Where-Object { $_.ReleaseReadiness -like "release candidate*" } | ForEach-Object { $_.TaskName })
    $ownerGaps = @($Items | Where-Object { $_.OwnerName -eq "not set" } | ForEach-Object { $_.TaskName })
    $cadenceGaps = @($Items | Where-Object { $_.ReviewCadence -eq "not set" } | ForEach-Object { $_.TaskName })

    $decision = if ($Items.Count -eq 0) {
        "no tasks configured"
    } elseif ($releaseBlocked.Count -gt 0) {
        "release blocked"
    } elseif ($validationRequired.Count -gt 0) {
        "validation required"
    } elseif ($reviewRequired.Count -gt 0) {
        "review required"
    } elseif ($ownerGaps.Count -gt 0 -or $cadenceGaps.Count -gt 0) {
        "governance incomplete"
    } elseif ($releaseCandidates.Count -eq $Items.Count) {
        "release candidate"
    } else {
        "not ready"
    }

    Write-Host ""
    Write-Host "Release decision policy:" -ForegroundColor Yellow
    Write-Host "     decision: $decision" -ForegroundColor DarkGray
    Write-Host "     blockers: $(if ($releaseBlocked.Count -gt 0) { $releaseBlocked -join ', ' } else { 'none' })" -ForegroundColor DarkGray
    Write-Host "     validation required: $(if ($validationRequired.Count -gt 0) { $validationRequired -join ', ' } else { 'none' })" -ForegroundColor DarkGray
    Write-Host "     review required: $(if ($reviewRequired.Count -gt 0) { $reviewRequired -join ', ' } else { 'none' })" -ForegroundColor DarkGray
    Write-Host "     release candidates: $(if ($releaseCandidates.Count -gt 0) { $releaseCandidates -join ', ' } else { 'none' })" -ForegroundColor DarkGray
    Write-Host "     governance gaps: $(if ($ownerGaps.Count -gt 0 -or $cadenceGaps.Count -gt 0) { (@($ownerGaps + $cadenceGaps) | Select-Object -Unique) -join ', ' } else { 'none' })" -ForegroundColor DarkGray
}

function Write-WorkspaceStaleTaskRemediation {
    param([object[]]$Items)

    $staleTasks = @($Items | Where-Object {
            $_.SyncHygieneBlocking -or
            $_.DueStatus -in @("overdue", "due soon") -or
            $_.OwnerName -eq "not set" -or
            $_.ReviewCadence -eq "not set" -or
            $_.Action -in @("review sync ignore", "create snapshot", "validate now", "review now", "rollback or revise")
        })

    Write-Host ""
    Write-Host "Stale-task remediation:" -ForegroundColor Yellow
    if ($staleTasks.Count -eq 0) {
        Write-Host "     queue: none" -ForegroundColor DarkGray
        return
    }

    foreach ($item in $staleTasks) {
        $owner = if ($item.OwnerName -ne "not set") { $item.OwnerName } else { "assign owner" }
        $cadence = if ($item.ReviewCadence -ne "not set") { $item.ReviewCadence } else { "set cadence" }
        $timing = if ($item.DueStatus -in @("overdue", "due soon")) { "$($item.DueDate) ($($item.DueStatus))" } else { "not urgent" }
        Write-Host "     $($item.TaskName): owner=$owner; cadence=$cadence; timing=$timing; action=$($item.Action); release=$($item.ReleaseReadiness)" -ForegroundColor DarkGray
    }
}

function Format-WorkspaceMarkdownValue {
    param([object]$Value)

    if ($null -eq $Value) {
        return ""
    }

    $text = [string]$Value
    $text = $text -replace "\r?\n", " "
    $text = $text -replace "\|", "\|"
    return $text.Trim()
}

function Write-WorkspaceOpen {
    param(
        [object]$Manifest,
        [string]$ProjectName,
        [string]$ManifestPath
    )

    $project = Find-WorkspaceProject -Manifest $Manifest -Name $ProjectName
    $projectName = if ($project.name) { [string]$project.name } else { "(unnamed)" }
    $runtimeName = if ($project.runtime) { [string]$project.runtime } else { "" }
    $localPath = Resolve-ProjectWorkspacePath -Project $project
    $remotePath = ""
    try {
        $remotePath = Resolve-WorkspaceRemoteProjectPath -Project $project
    } catch {
        $remotePath = "unavailable: $_"
    }

    $runtimeStatus = Get-WorkspaceRuntimeStatus -RuntimeName $runtimeName
    $syncExpected = ($null -ne $project.sync -and [bool]$project.sync)
    $syncStatus = Get-WorkspaceSyncStatus -RuntimeName $runtimeName -Expected $syncExpected
    $syncHygieneStatus = Get-WorkspaceSyncHygieneStatus -Project $project -ProjectPath $localPath
    $devContainerStatus = Get-WorkspaceDevContainerStatus -ProjectPath $localPath
    $pathLevel = if ($localPath -and (Test-Path -LiteralPath $localPath)) { "OK" } elseif ($localPath) { "WARN" } else { "FAIL" }
    $pathDetail = if ($localPath) {
        if ($pathLevel -eq "OK") { "exists: $localPath" } else { "missing: $localPath" }
    } else {
        "projects[].path missing"
    }

    Write-Host "Workspace open: $projectName" -ForegroundColor Cyan
    Write-Host "Open guide only: no shell, editor, SSH connection, sync session, runtime, or file will be changed." -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Project:" -ForegroundColor Yellow
    Write-Host "  Name:        $projectName" -ForegroundColor DarkGray
    Write-Host "  Runtime:     $(if ($runtimeName) { $runtimeName } else { 'not configured' })" -ForegroundColor DarkGray
    Write-Host "  Sync:        $(if ($syncExpected) { 'requested' } else { 'not requested' })" -ForegroundColor DarkGray
    Write-Host "  Local path:  $(if ($localPath) { $localPath } else { 'not configured' })" -ForegroundColor DarkGray
    Write-Host "  Remote path: $remotePath" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Readiness:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $pathLevel -Name "local path" -Detail "($pathDetail)"
    Write-WorkspaceCheck -Level $runtimeStatus.Level -Name "runtime $runtimeName" -Detail "($($runtimeStatus.Status)$(if ($runtimeStatus.Detail) { ': ' + $runtimeStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncStatus.Level -Name "sync" -Detail "($($syncStatus.Status)$(if ($syncStatus.Detail) { ': ' + $syncStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncHygieneStatus.Level -Name "sync hygiene" -Detail "($($syncHygieneStatus.Status)$(if ($syncHygieneStatus.Detail) { ': ' + $syncHygieneStatus.Detail }))"
    Write-WorkspaceCheck -Level $devContainerStatus.Level -Name "devcontainer" -Detail "($($devContainerStatus.Status)$(if ($devContainerStatus.Detail) { ': ' + $devContainerStatus.Detail }))"

    Write-Host ""
    Write-Host "Local commands:" -ForegroundColor Yellow
    if ($localPath) {
        Write-Host "  Set-Location -LiteralPath $(Quote-WorkspacePowerShellArgument $localPath)" -ForegroundColor DarkGray
        Write-Host "  git status --short" -ForegroundColor DarkGray
        Write-Host "  code $(Quote-WorkspacePowerShellArgument $localPath)" -ForegroundColor DarkGray
    } else {
        Write-Host "  Set projects[].path before opening this project locally." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Runtime commands:" -ForegroundColor Yellow
    if ($runtimeName -and (Test-RuntimeExists $runtimeName)) {
        $alias = "adp-os-adp-$runtimeName"
        Write-Host "  ssh $alias" -ForegroundColor DarkGray
        try {
            $sshTarget = Get-WorkspaceRuntimeSshTarget -RuntimeName $runtimeName
            Write-Host "  ssh -i $(Quote-WorkspacePowerShellArgument $sshTarget.KeyPath) -p $($sshTarget.Port) $($sshTarget.User)@$($sshTarget.Host)" -ForegroundColor DarkGray
        } catch {
            Write-Host "  SSH target unavailable: $_" -ForegroundColor Yellow
        }
        if ($remotePath -and $remotePath -notmatch '^unavailable:') {
            Write-Host "  cd $(Quote-PosixSingleArgument $remotePath)" -ForegroundColor DarkGray
            Write-Host "  git status --short" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  Set a known projects[].runtime before opening this project in a runtime." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Next:" -ForegroundColor Yellow
    Write-Host "  adp workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    if ($runtimeName) {
        Write-Host "  adp up $runtimeName -Plan" -ForegroundColor DarkGray
        if ($syncExpected) {
            Write-Host "  adp sync start $runtimeName" -ForegroundColor DarkGray
        }
    }
}

function Write-WorkspaceSyncGuide {
    param(
        [object]$Manifest,
        [string]$ProjectName,
        [string]$ManifestPath
    )

    $project = Find-WorkspaceProject -Manifest $Manifest -Name $ProjectName
    $projectName = if ($project.name) { [string]$project.name } else { "(unnamed)" }
    $runtimeName = if ($project.runtime) { [string]$project.runtime } else { "" }
    $localPath = Resolve-ProjectWorkspacePath -Project $project
    $remotePath = ""
    try {
        $remotePath = Resolve-WorkspaceRemoteProjectPath -Project $project
    } catch {
        $remotePath = "unavailable: $_"
    }

    $syncExpected = ($null -ne $project.sync -and [bool]$project.sync)
    $runtimeStatus = Get-WorkspaceRuntimeStatus -RuntimeName $runtimeName
    $syncStatus = Get-WorkspaceSyncStatus -RuntimeName $runtimeName -Expected $syncExpected
    $syncHygieneStatus = Get-WorkspaceSyncHygieneStatus -Project $project -ProjectPath $localPath
    $pathLevel = if ($localPath -and (Test-Path -LiteralPath $localPath)) { "OK" } elseif ($localPath) { "WARN" } else { "FAIL" }
    $pathDetail = if ($localPath) {
        if ($pathLevel -eq "OK") { "exists: $localPath" } else { "missing: $localPath" }
    } else {
        "projects[].path missing"
    }

    Write-Host "Workspace sync: $projectName" -ForegroundColor Cyan
    Write-Host "Sync guide only: no Mutagen session, runtime, SSH connection, directory, or file will be changed." -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Project:" -ForegroundColor Yellow
    Write-Host "  Name:        $projectName" -ForegroundColor DarkGray
    Write-Host "  Runtime:     $(if ($runtimeName) { $runtimeName } else { 'not configured' })" -ForegroundColor DarkGray
    Write-Host "  Sync intent: $(if ($syncExpected) { 'requested' } else { 'not requested' })" -ForegroundColor DarkGray
    Write-Host "  Local path:  $(if ($localPath) { $localPath } else { 'not configured' })" -ForegroundColor DarkGray
    Write-Host "  Remote path: $remotePath" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Readiness:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $pathLevel -Name "local path" -Detail "($pathDetail)"
    Write-WorkspaceCheck -Level $runtimeStatus.Level -Name "runtime $runtimeName" -Detail "($($runtimeStatus.Status)$(if ($runtimeStatus.Detail) { ': ' + $runtimeStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncStatus.Level -Name "sync session" -Detail "($($syncStatus.Status)$(if ($syncStatus.Detail) { ': ' + $syncStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncHygieneStatus.Level -Name "sync hygiene" -Detail "($($syncHygieneStatus.Status)$(if ($syncHygieneStatus.Detail) { ': ' + $syncHygieneStatus.Detail }))"

    Write-Host ""
    Write-Host "Runtime sync commands:" -ForegroundColor Yellow
    if ($runtimeName -and (Test-RuntimeExists $runtimeName)) {
        Write-Host "  adp sync status" -ForegroundColor DarkGray
        if ($syncExpected) {
            Write-Host "  adp sync start $runtimeName" -ForegroundColor DarkGray
            Write-Host "  adp sync stop $runtimeName" -ForegroundColor DarkGray
        } else {
            Write-Host "  projects[].sync is false; set it to true before treating sync as expected for this project." -ForegroundColor Yellow
            Write-Host "  adp sync start $runtimeName" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  Set a known projects[].runtime before using runtime sync for this project." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Project commands:" -ForegroundColor Yellow
    Write-Host "  adp workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-Host "  adp workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-Host "  adp workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
}

function Write-WorkspaceProjectLifecycle {
    param(
        [object]$Manifest,
        [string]$ProjectName,
        [string]$ManifestPath,
        [string]$StatePath
    )

    $project = Find-WorkspaceProject -Manifest $Manifest -Name $ProjectName
    $projectName = if ($project.name) { [string]$project.name } else { "(unnamed)" }
    $runtimeName = if ($project.runtime) { [string]$project.runtime } else { "" }
    $localPath = Resolve-ProjectWorkspacePath -Project $project
    $remotePath = ""
    try {
        $remotePath = Resolve-WorkspaceRemoteProjectPath -Project $project
    } catch {
        $remotePath = "unavailable: $_"
    }

    $syncExpected = ($null -ne $project.sync -and [bool]$project.sync)
    $runtimeStatus = Get-WorkspaceRuntimeStatus -RuntimeName $runtimeName
    $syncStatus = Get-WorkspaceSyncStatus -RuntimeName $runtimeName -Expected $syncExpected
    $syncHygieneStatus = Get-WorkspaceSyncHygieneStatus -Project $project -ProjectPath $localPath
    $devContainerStatus = Get-WorkspaceDevContainerStatus -ProjectPath $localPath
    $validationCommands = Get-WorkspaceArray $project.validation
    $linkedTasks = Get-WorkspaceTasksForProject -Manifest $Manifest -Project $project
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $pathLevel = if ($localPath -and (Test-Path -LiteralPath $localPath)) { "OK" } elseif ($localPath) { "WARN" } else { "FAIL" }
    $pathDetail = if ($localPath) {
        if ($pathLevel -eq "OK") { "exists: $localPath" } else { "missing: $localPath" }
    } else {
        "projects[].path missing"
    }

    Write-Host "Workspace project lifecycle: $projectName" -ForegroundColor Cyan
    Write-Host "Lifecycle view only: no project, runtime, sync session, snapshot, validation command, Git command, or file will be changed." -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Project:" -ForegroundColor Yellow
    Write-Host "  Name:        $projectName" -ForegroundColor DarkGray
    Write-Host "  Runtime:     $(if ($runtimeName) { $runtimeName } else { 'not configured' })" -ForegroundColor DarkGray
    Write-Host "  Sync intent: $(if ($syncExpected) { 'requested' } else { 'not requested' })" -ForegroundColor DarkGray
    Write-Host "  Local path:  $(if ($localPath) { $localPath } else { 'not configured' })" -ForegroundColor DarkGray
    Write-Host "  Remote path: $remotePath" -ForegroundColor DarkGray
    Write-Host "  State path:  $resolvedStatePath" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Lifecycle gates:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $pathLevel -Name "local path" -Detail "($pathDetail)"
    Write-WorkspaceCheck -Level $runtimeStatus.Level -Name "runtime $runtimeName" -Detail "($($runtimeStatus.Status)$(if ($runtimeStatus.Detail) { ': ' + $runtimeStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncStatus.Level -Name "sync session" -Detail "($($syncStatus.Status)$(if ($syncStatus.Detail) { ': ' + $syncStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncHygieneStatus.Level -Name "sync hygiene" -Detail "($($syncHygieneStatus.Status)$(if ($syncHygieneStatus.Detail) { ': ' + $syncHygieneStatus.Detail }))"
    Write-WorkspaceCheck -Level $devContainerStatus.Level -Name "devcontainer" -Detail "($($devContainerStatus.Status)$(if ($devContainerStatus.Detail) { ': ' + $devContainerStatus.Detail }))"
    if ($validationCommands.Count -gt 0) {
        Write-WorkspaceCheck -Level "OK" -Name "project validation" -Detail "($($validationCommands.Count) configured)"
    } else {
        Write-WorkspaceCheck -Level "WARN" -Name "project validation" -Detail "(none configured)"
    }
    if ($linkedTasks.Count -gt 0) {
        Write-WorkspaceCheck -Level "OK" -Name "linked tasks" -Detail "($($linkedTasks.Count) found)"
    } else {
        Write-WorkspaceCheck -Level "INFO" -Name "linked tasks" -Detail "(none found)"
    }

    Write-Host ""
    Write-Host "Operational flow:" -ForegroundColor Yellow
    Write-Host "  1. Open:      adp workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    if ($runtimeName) {
        Write-Host "  2. Runtime:   adp up $runtimeName -Plan" -ForegroundColor DarkGray
        Write-Host "  3. Sync:      adp workspace sync $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    } else {
        Write-Host "  2. Runtime:   set projects[].runtime before planning runtime startup" -ForegroundColor Yellow
        Write-Host "  3. Sync:      set projects[].runtime before planning sync" -ForegroundColor Yellow
    }
    if ($validationCommands.Count -gt 0) {
        Write-Host "  4. Validate:  run declared project validation commands manually, or use task validation for linked tasks" -ForegroundColor DarkGray
    } else {
        Write-Host "  4. Validate:  add projects[].validation or task validation commands" -ForegroundColor Yellow
    }
    Write-Host "  5. Evidence:  adp workspace report -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray

    Write-Host ""
    Write-Host "Project validation commands:" -ForegroundColor Yellow
    if ($validationCommands.Count -gt 0) {
        foreach ($command in $validationCommands) {
            Write-Host "  - $command" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  No project validation commands configured." -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Linked tasks:" -ForegroundColor Yellow
    if ($linkedTasks.Count -eq 0) {
        Write-Host "  No tasks currently target this project." -ForegroundColor DarkGray
    }
    foreach ($task in $linkedTasks) {
        $taskName = if ($task.name) { [string]$task.name } else { "(unnamed)" }
        $risk = Get-WorkspaceTaskRisk -Task $task
        $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $task
        $snapshotNaming = Get-WorkspaceSnapshotNamingStatus -Task $task
        $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $task.runtime -SnapshotName $task.snapshot
        $recordedState = Get-WorkspaceTaskState -State $state -TaskName $taskName
        $snapshotGate = Get-WorkspaceSnapshotGate -Task $task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
        $validationState = Format-WorkspaceValidationState -RecordedState $recordedState
        $validationCommandCount = (Get-WorkspaceArray $task.validation).Count
        $syncContext = Get-WorkspaceTaskSyncHygieneStatus -Manifest $Manifest -Task $task
        $commitDecision = Get-WorkspaceCommitDecision -Task $task -RecordedState $recordedState -SnapshotGate $snapshotGate -ValidationCommandCount $validationCommandCount -SyncHygiene $syncContext.Hygiene
        $taskMilestones = Get-WorkspaceTaskMilestones -Manifest $Manifest -Task $task
        $milestoneNames = @($taskMilestones | ForEach-Object { if ($_.name) { [string]$_.name } })
        $milestoneText = if ($milestoneNames.Count -gt 0) { $milestoneNames -join ', ' } else { "none" }

        Write-Host "  - $taskName" -ForegroundColor DarkGray
        Write-Host "      milestone: $milestoneText" -ForegroundColor DarkGray
        Write-Host "      risk: $risk; snapshot required: $requiresSnapshot; snapshot naming: $($snapshotNaming.Status); snapshot gate: $($snapshotGate.Status)" -ForegroundColor DarkGray
        Write-Host "      validation: $validationState; commit: $($commitDecision.Verdict)" -ForegroundColor DarkGray
        Write-Host "      prepare:  adp workspace task prepare $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-Host "      validate: adp workspace task validate $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-Host "      review:   adp workspace task review $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    }
}

function Format-WorkspaceStatusWithDetail {
    param(
        [object]$StatusObject,
        [string]$Separator = ": "
    )

    if ($null -eq $StatusObject) {
        return ""
    }

    $status = if ($StatusObject.PSObject.Properties.Name -contains "Status") { [string]$StatusObject.Status } else { [string]$StatusObject }
    $detail = if ($StatusObject.PSObject.Properties.Name -contains "Detail") { [string]$StatusObject.Detail } else { "" }
    if ([string]::IsNullOrWhiteSpace($detail)) {
        return $status
    }

    return "$status$Separator$detail"
}

function Join-WorkspaceMarkdownList {
    param([object[]]$Values)

    $items = @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object { Format-WorkspaceMarkdownValue $_ })
    if ($items.Count -eq 0) {
        return "none"
    }

    return ($items -join ", ")
}

function Format-WorkspaceEvidencePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    $projectRoot = Get-ProjectRoot
    try {
        $fullPath = [System.IO.Path]::GetFullPath($Path)
        $rootPath = [System.IO.Path]::GetFullPath($projectRoot)
        if (-not $rootPath.EndsWith([System.IO.Path]::DirectorySeparatorChar)) {
            $rootPath = $rootPath + [System.IO.Path]::DirectorySeparatorChar
        }

        if ($fullPath.StartsWith($rootPath, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $fullPath.Substring($rootPath.Length)
        }

        $leaf = [System.IO.Path]::GetFileName($fullPath)
        if (-not [string]::IsNullOrWhiteSpace($leaf)) {
            return "outside repository: $leaf"
        }
    } catch {
        return $Path
    }

    return $Path
}

function Get-WorkspaceReleaseDecisionSummary {
    param([object[]]$Items)

    $releaseBlocked = @($Items | Where-Object { $_.ReleaseReadiness -eq "release blocked" } | ForEach-Object { $_.TaskName })
    $validationRequired = @($Items | Where-Object { $_.ReleaseReadiness -eq "validation required" } | ForEach-Object { $_.TaskName })
    $reviewRequired = @($Items | Where-Object { $_.ReleaseReadiness -eq "review required" } | ForEach-Object { $_.TaskName })
    $releaseCandidates = @($Items | Where-Object { $_.ReleaseReadiness -like "release candidate*" } | ForEach-Object { $_.TaskName })
    $ownerGaps = @($Items | Where-Object { $_.OwnerName -eq "not set" } | ForEach-Object { $_.TaskName })
    $cadenceGaps = @($Items | Where-Object { $_.ReviewCadence -eq "not set" } | ForEach-Object { $_.TaskName })
    $governanceGaps = @(@($ownerGaps + $cadenceGaps) | Select-Object -Unique)

    $decision = if ($Items.Count -eq 0) {
        "no tasks configured"
    } elseif ($releaseBlocked.Count -gt 0) {
        "release blocked"
    } elseif ($validationRequired.Count -gt 0) {
        "validation required"
    } elseif ($reviewRequired.Count -gt 0) {
        "review required"
    } elseif ($governanceGaps.Count -gt 0) {
        "governance incomplete"
    } elseif ($releaseCandidates.Count -eq $Items.Count) {
        "release candidate"
    } else {
        "not ready"
    }

    return [pscustomobject]@{
        Decision           = $decision
        ReleaseBlocked     = $releaseBlocked
        ValidationRequired = $validationRequired
        ReviewRequired     = $reviewRequired
        ReleaseCandidates  = $releaseCandidates
        GovernanceGaps     = $governanceGaps
    }
}

function Write-WorkspaceReportMarkdown {
    param(
        [object]$Manifest,
        [string]$ManifestPath,
        [string]$StatePath
    )

    $tasks = Get-WorkspaceArray $Manifest.tasks
    $milestones = Get-WorkspaceMilestones -Manifest $Manifest
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $reportItems = @($tasks | ForEach-Object { New-WorkspaceReportItem -Manifest $Manifest -Task $_ -State $state })
    $policy = Get-WorkspaceReleaseDecisionSummary -Items $reportItems
    $milestoneStatuses = @($milestones | ForEach-Object { Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $_ })

    $total = $reportItems.Count
    $passed = @($reportItems | Where-Object { $_.ValidationStatus -eq "passed" }).Count
    $failed = @($reportItems | Where-Object { $_.ValidationStatus -eq "failed" }).Count
    $missing = @($reportItems | Where-Object { $_.ValidationStatus -notin @("passed", "failed") }).Count
    $snapshotBlocked = @($reportItems | Where-Object { $_.SnapshotBlocked }).Count
    $reviewReady = @($reportItems | Where-Object { $_.ReviewReady }).Count
    $commitReady = @($reportItems | Where-Object { $_.CommitReady }).Count
    $ownerGaps = @($reportItems | Where-Object { $_.OwnerName -eq "not set" } | ForEach-Object { $_.TaskName })
    $cadenceGaps = @($reportItems | Where-Object { $_.ReviewCadence -eq "not set" } | ForEach-Object { $_.TaskName })
    $dueTasks = @($reportItems | Where-Object { $_.DueStatus -in @("overdue", "due soon") } | ForEach-Object { "$($_.TaskName) ($($_.DueStatus))" })
    $actionGroups = @($reportItems | Group-Object -Property Action | Sort-Object Name)
    $releaseGroups = @($reportItems | Group-Object -Property ReleaseReadiness | Sort-Object Name)
    $milestoneGroups = @($reportItems | Where-Object { $_.MilestoneText -ne "not set" } | Group-Object -Property MilestoneText | Sort-Object Name)
    $milestoneRollups = Get-WorkspaceMilestoneReviewRollups -Items $reportItems
    $validationQueue = Get-WorkspaceValidationQueueItems -Items $reportItems -ManifestPath $ManifestPath
    $evaluationQueue = Get-WorkspaceEvaluationQueueItems -Manifest $Manifest -ManifestPath $ManifestPath
    $attentionTasks = @($reportItems | Where-Object {
            $_.SnapshotBlocked -or
            $_.SyncHygieneBlocking -or
            $_.DueStatus -in @("overdue", "due soon") -or
            $_.CommitDecision.Verdict -in @("blocked by validation", "validation result missing", "validation not configured", "review not recorded")
        } | ForEach-Object {
            $reason = if ($_.SyncHygieneBlocking) { "sync hygiene: $($_.SyncHygiene.Status)" } else { $_.CommitDecision.Verdict }
            "$($_.TaskName) [$reason; due: $($_.DueStatus)]"
        })

    Write-Output "# Workspace Release Evidence: $($Manifest.name)"
    Write-Output ""
    Write-Output "> Markdown report only. No projects were cloned, no sync sessions changed, no snapshots created, no validation or evaluation commands run, and no Git commands run."
    Write-Output ""
    Write-Output "## Sources"
    Write-Output ""
    Write-Output "| Source | Path |"
    Write-Output "| --- | --- |"
    Write-Output "| Manifest | $(Format-WorkspaceMarkdownValue (Format-WorkspaceEvidencePath $ManifestPath)) |"
    Write-Output "| Local state | $(Format-WorkspaceMarkdownValue (Format-WorkspaceEvidencePath $resolvedStatePath)) |"
    Write-Output ""
    Write-Output "## Release Decision"
    Write-Output ""
    Write-Output "| Field | Value |"
    Write-Output "| --- | --- |"
    Write-Output "| Decision | $(Format-WorkspaceMarkdownValue $policy.Decision) |"
    Write-Output "| Blockers | $(Join-WorkspaceMarkdownList $policy.ReleaseBlocked) |"
    Write-Output "| Validation required | $(Join-WorkspaceMarkdownList $policy.ValidationRequired) |"
    Write-Output "| Review required | $(Join-WorkspaceMarkdownList $policy.ReviewRequired) |"
    Write-Output "| Release candidates | $(Join-WorkspaceMarkdownList $policy.ReleaseCandidates) |"
    Write-Output "| Governance gaps | $(Join-WorkspaceMarkdownList $policy.GovernanceGaps) |"
    Write-Output ""
    Write-Output "## Handoff Summary"
    Write-Output ""
    Write-Output "| Metric | Value |"
    Write-Output "| --- | ---: |"
    Write-Output "| Tasks | $total |"
    Write-Output "| Validation passed | $passed |"
    Write-Output "| Validation failed | $failed |"
    Write-Output "| Validation missing | $missing |"
    Write-Output "| Snapshot blocked | $snapshotBlocked |"
    Write-Output "| Ready for review | $reviewReady |"
    Write-Output "| Ready to commit | $commitReady |"
    Write-Output ""
    Write-Output "| Queue | Items |"
    Write-Output "| --- | --- |"
    Write-Output "| Owner gaps | $(Join-WorkspaceMarkdownList $ownerGaps) |"
    Write-Output "| Cadence gaps | $(Join-WorkspaceMarkdownList $cadenceGaps) |"
    Write-Output "| Due attention | $(Join-WorkspaceMarkdownList $dueTasks) |"
    Write-Output "| Attention queue | $(Join-WorkspaceMarkdownList $attentionTasks) |"
    Write-Output ""
    Write-Output "## Validation Execution Queue"
    Write-Output ""
    if ($validationQueue.Count -eq 0) {
        Write-Output "No tasks are configured."
    } else {
        Write-Output "| Task | Validation | Commands | Readiness | Blockers | Plan | Execute preview | Execute |"
        Write-Output "| --- | --- | ---: | --- | --- | --- | --- | --- |"
        foreach ($entry in $validationQueue) {
            $planCommand = Format-WorkspaceMarkdownValue $entry.PlanCommand
            $executePreview = Format-WorkspaceMarkdownValue $entry.ExecutePreview
            $executeCommand = Format-WorkspaceMarkdownValue $entry.ExecuteCommand
            Write-Output "| $(Format-WorkspaceMarkdownValue $entry.TaskName) | $(Format-WorkspaceMarkdownValue $entry.Validation) | $($entry.CommandCount) | $(Format-WorkspaceMarkdownValue $entry.Readiness) | $(Join-WorkspaceMarkdownList $entry.Blockers) | $planCommand | $executePreview | $executeCommand |"
        }
    }
    Write-Output ""
    Write-Output "## Evaluation Queue"
    Write-Output ""
    if ($evaluationQueue.Count -eq 0) {
        Write-Output "No evaluations are configured."
    } else {
        Write-Output "> Evaluation queue only. No evaluation commands were run."
        Write-Output ""
        Write-Output "| Evaluation | Readiness | Runtime | Project | Cadence | Metrics | Commands | Tasks | Blockers | Evidence |"
        Write-Output "| --- | --- | --- | --- | --- | --- | ---: | --- | --- | --- |"
        foreach ($entry in $evaluationQueue) {
            Write-Output "| $(Format-WorkspaceMarkdownValue $entry.Name) | $(Format-WorkspaceMarkdownValue $entry.Readiness) | $(Format-WorkspaceMarkdownValue $entry.RuntimeName) | $(Format-WorkspaceMarkdownValue $entry.ProjectName) | $(Format-WorkspaceMarkdownValue $entry.Cadence) | $(Join-WorkspaceMarkdownList $entry.Metrics) | $($entry.Commands.Count) | $(Join-WorkspaceMarkdownList $entry.TaskNames) | $(Join-WorkspaceMarkdownList $entry.Blockers) | $(Format-WorkspaceMarkdownValue $entry.ReportCommand) |"
        }
    }

    Write-Output ""
    Write-Output "## Decision Queues"
    Write-Output ""
    Write-Output "| Queue | Tasks |"
    Write-Output "| --- | --- |"
    foreach ($group in $actionGroups) {
        Write-Output "| Action: $(Format-WorkspaceMarkdownValue $group.Name) | $(Join-WorkspaceMarkdownList @($group.Group | ForEach-Object { $_.TaskName })) |"
    }
    foreach ($group in $releaseGroups) {
        Write-Output "| Release: $(Format-WorkspaceMarkdownValue $group.Name) | $(Join-WorkspaceMarkdownList @($group.Group | ForEach-Object { $_.TaskName })) |"
    }
    foreach ($group in $milestoneGroups) {
        Write-Output "| Milestone: $(Format-WorkspaceMarkdownValue $group.Name) | $(Join-WorkspaceMarkdownList @($group.Group | ForEach-Object { $_.TaskName })) |"
    }

    Write-Output ""
    Write-Output "## Milestone Checkpoints"
    Write-Output ""
    if ($milestoneStatuses.Count -eq 0) {
        Write-Output "No milestones are configured."
    } else {
        Write-Output "| Milestone | Runtime | Snapshot | Naming | Snapshot status | Tasks |"
        Write-Output "| --- | --- | --- | --- | --- | --- |"
        foreach ($milestoneStatus in $milestoneStatuses) {
            Write-Output "| $(Format-WorkspaceMarkdownValue $milestoneStatus.Name) | $(Format-WorkspaceMarkdownValue $milestoneStatus.RuntimeName) | $(Format-WorkspaceMarkdownValue $milestoneStatus.SnapshotName) | $(Format-WorkspaceMarkdownValue (Format-WorkspaceStatusWithDetail -StatusObject $milestoneStatus.SnapshotNaming -Separator ' - ')) | $(Format-WorkspaceMarkdownValue (Format-WorkspaceStatusWithDetail -StatusObject $milestoneStatus.SnapshotStatus)) | $(Join-WorkspaceMarkdownList $milestoneStatus.TaskNames) |"
        }
    }

    Write-Output ""
    Write-Output "## Milestone Review Rollup"
    Write-Output ""
    if ($milestoneRollups.Count -eq 0) {
        Write-Output "No milestone-linked tasks are configured."
    } else {
        Write-Output "| Milestone | Tasks | Actions | Release | Blocked | Validation required | Review required | Ready to commit | Owners | Due attention |"
        Write-Output "| --- | ---: | --- | --- | --- | --- | --- | --- | --- | --- |"
        foreach ($rollup in $milestoneRollups) {
            Write-Output "| $(Format-WorkspaceMarkdownValue $rollup.Milestone) | $($rollup.TaskCount) | $(Join-WorkspaceMarkdownList $rollup.Actions) | $(Join-WorkspaceMarkdownList $rollup.ReleaseStates) | $(Join-WorkspaceMarkdownList $rollup.Blocked) | $(Join-WorkspaceMarkdownList $rollup.ValidationRequired) | $(Join-WorkspaceMarkdownList $rollup.ReviewRequired) | $(Join-WorkspaceMarkdownList $rollup.ReadyToCommit) | $(Join-WorkspaceMarkdownList $rollup.Owners) | $(Join-WorkspaceMarkdownList $rollup.DueAttention) |"
        }
    }

    Write-Output ""
    Write-Output "## Task Evidence"
    Write-Output ""
    if ($reportItems.Count -eq 0) {
        Write-Output "No tasks are configured."
        return
    }

    Write-Output "| Task | Milestone | Evaluation | Owner | Runtime | Risk | Sync hygiene | Validation | Review | Commit | Release | Next action |"
    Write-Output "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |"
    foreach ($item in $reportItems) {
        Write-Output "| $(Format-WorkspaceMarkdownValue $item.TaskName) | $(Format-WorkspaceMarkdownValue $item.MilestoneText) | $(Format-WorkspaceMarkdownValue $item.EvaluationText) | $(Format-WorkspaceMarkdownValue $item.OwnerName) | $(Format-WorkspaceMarkdownValue $item.RuntimeName) | $(Format-WorkspaceMarkdownValue $item.Risk) | $(Format-WorkspaceMarkdownValue (Format-WorkspaceStatusWithDetail -StatusObject $item.SyncHygiene)) | $(Format-WorkspaceMarkdownValue $item.ValidationStateText) | $(Format-WorkspaceMarkdownValue $item.ReviewDecision.Verdict) | $(Format-WorkspaceMarkdownValue $item.CommitDecision.Verdict) | $(Format-WorkspaceMarkdownValue $item.ReleaseReadiness) | $(Format-WorkspaceMarkdownValue $item.Action) |"
    }

    Write-Output ""
    Write-Output "## Task Details"
    foreach ($item in $reportItems) {
        Write-Output ""
        Write-Output "### $($item.TaskName)"
        Write-Output ""
        Write-Output "- Project: $($item.ProjectName)"
        Write-Output "- Milestone: $($item.MilestoneText)"
        Write-Output "- Evaluation: $($item.EvaluationText)"
        Write-Output "- Sync hygiene: $(Format-WorkspaceStatusWithDetail -StatusObject $item.SyncHygiene -Separator ' - ')"
        Write-Output "- Runtime: $($item.RuntimeName)"
        Write-Output "- Owner: $($item.OwnerName)"
        Write-Output "- Review cadence: $($item.ReviewCadence)"
        Write-Output "- Due: $($item.DueDate) ($($item.DueStatus))"
        Write-Output "- Snapshot: $($item.SnapshotName); required: $($item.RequiresSnapshot); gate: $($item.SnapshotGate.Status); naming: $($item.SnapshotNaming.Status) - $($item.SnapshotNaming.Detail)"
        Write-Output "- Validation: $($item.ValidationStateText)"
        if ($item.RecordedState -and $item.RecordedState.PSObject.Properties.Name -contains "validation" -and $item.RecordedState.validation) {
            $validation = $item.RecordedState.validation
            if ($validation.PSObject.Properties.Name -contains "failed_command" -and -not [string]::IsNullOrWhiteSpace([string]$validation.failed_command)) {
                Write-Output "- Failed command: $($validation.failed_command)"
            }
            if ($validation.PSObject.Properties.Name -contains "remote_path" -and -not [string]::IsNullOrWhiteSpace([string]$validation.remote_path)) {
                Write-Output "- Remote path: $($validation.remote_path)"
            }
            if ($validation.PSObject.Properties.Name -contains "command_count") {
                Write-Output "- Command count: $($validation.command_count)"
            }
        }
        Write-Output "- Review: $($item.ReviewDecision.Verdict) - $($item.ReviewDecision.Detail)"
        Write-Output "- Rollback: $($item.RollbackState)"
        Write-Output "- Commit: $($item.CommitDecision.Verdict) - $($item.CommitDecision.Detail)"
        Write-Output "- Next: $($item.CommitDecision.NextStep)"
        Write-Output ""
        Write-Output "Handoff commands:"
        Write-Output ""
        Write-Output '```powershell'
        Write-Output "adp workspace task review $($item.TaskName) -ManifestPath $ManifestPath"
        Write-Output "adp workspace task rollback $($item.TaskName) -ManifestPath $ManifestPath"
        Write-Output "adp workspace task commit $($item.TaskName) -ManifestPath $ManifestPath"
        Write-Output '```'
    }

    Write-Output ""
    Write-Output "## Maintainer Checklist"
    Write-Output ""
    Write-Output "- Confirm the latest recorded validation result matches the output being reviewed."
    Write-Output "- Confirm sync hygiene is clean, covered, not requested, or intentionally reviewed before release."
    Write-Output "- Inspect source status, diff stat, and full diff in the target project."
    Write-Output "- Confirm snapshot and rollback path before accepting risky work."
    Write-Output "- Commit only after sync hygiene, validation, and human review are all accepted."
}

function Write-WorkspaceReport {
    param(
        [object]$Manifest,
        [string]$ManifestPath,
        [string]$StatePath,
        [switch]$Markdown
    )

    if ($Markdown) {
        Write-WorkspaceReportMarkdown -Manifest $Manifest -ManifestPath $ManifestPath -StatePath $StatePath
        return
    }

    Write-Host "Workspace report: $($Manifest.name)" -ForegroundColor Cyan
    Write-Host "Report only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation or evaluation commands will be run, and no Git commands will be run." -ForegroundColor DarkGray

    $tasks = Get-WorkspaceArray $Manifest.tasks
    $milestones = Get-WorkspaceMilestones -Manifest $Manifest
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath

    Write-Host ""
    Write-Host "Sources:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "manifest" -Detail "($ManifestPath)"
    Write-WorkspaceCheck -Level "INFO" -Name "state" -Detail "($resolvedStatePath)"

    if ($tasks.Count -eq 0) {
        Write-Host ""
        Write-Host "Task reports:" -ForegroundColor Yellow
        Write-WorkspaceCheck -Level "WARN" -Name "tasks" -Detail "(none configured)"
        return
    }

    $reportItems = @($tasks | ForEach-Object { New-WorkspaceReportItem -Manifest $Manifest -Task $_ -State $state })
    Write-WorkspaceReportSummary -Items $reportItems
    Write-WorkspaceGovernanceLoop -Items $reportItems
    Write-WorkspaceDecisionQueues -Items $reportItems
    Write-WorkspaceMilestoneCheckpoints -Manifest $Manifest -Milestones $milestones
    Write-WorkspaceMilestoneReviewRollup -Items $reportItems
    Write-WorkspaceValidationQueue -Items $reportItems -ManifestPath $ManifestPath
    Write-WorkspaceEvaluationQueue -Manifest $Manifest -ManifestPath $ManifestPath
    Write-WorkspaceReleasePolicy -Items $reportItems
    Write-WorkspaceStaleTaskRemediation -Items $reportItems

    Write-Host ""
    Write-Host "Task reports:" -ForegroundColor Yellow
    foreach ($item in $reportItems) {
        Write-WorkspaceCheck -Level $item.Level -Name $item.TaskName -Detail "(state: $($item.RecordedTaskState); risk: $($item.Risk); snapshot required: $($item.RequiresSnapshot))"
        Write-Host "     review bundle:" -ForegroundColor DarkGray
        Write-Host "       project: $($item.ProjectName)" -ForegroundColor DarkGray
        Write-Host "       milestone: $($item.MilestoneText)" -ForegroundColor DarkGray
        Write-Host "       evaluation: $($item.EvaluationText)" -ForegroundColor DarkGray
        Write-Host "       sync hygiene: $($item.SyncHygiene.Status)$(if ($item.SyncHygiene.Detail) { ' - ' + $item.SyncHygiene.Detail })" -ForegroundColor DarkGray
        Write-Host "       owner: $($item.OwnerName)" -ForegroundColor DarkGray
        Write-Host "       review cadence: $($item.ReviewCadence)" -ForegroundColor DarkGray
        Write-Host "       due: $($item.DueDate) ($($item.DueStatus))" -ForegroundColor DarkGray
        Write-Host "       runtime: $($item.RuntimeName)" -ForegroundColor DarkGray
        Write-Host "       checkpoint: $($item.SnapshotName)" -ForegroundColor DarkGray
        Write-Host "       snapshot gate: $($item.SnapshotGate.Status) - $($item.SnapshotGate.Detail)" -ForegroundColor DarkGray
        Write-Host "       snapshot naming: $($item.SnapshotNaming.Status) - $($item.SnapshotNaming.Detail)" -ForegroundColor DarkGray
        Write-Host "       validation commands: $($item.ValidationCommands.Count)" -ForegroundColor DarkGray
        Write-Host "       action: $($item.Action)" -ForegroundColor DarkGray
        Write-Host "       release readiness: $($item.ReleaseReadiness)" -ForegroundColor DarkGray
        Write-Host "     validation result: $($item.ValidationStateText)" -ForegroundColor DarkGray
        Write-WorkspaceValidationDetailLines -RecordedState $item.RecordedState
        Write-Host "     review: $($item.ReviewDecision.Verdict) - $($item.ReviewDecision.Detail)" -ForegroundColor DarkGray
        Write-Host "     rollback: $($item.RollbackState)" -ForegroundColor DarkGray
        Write-Host "     commit: $($item.CommitDecision.Verdict) - $($item.CommitDecision.Detail)" -ForegroundColor DarkGray
        Write-Host "     next: $($item.CommitDecision.NextStep)" -ForegroundColor DarkGray
        Write-Host "     checklist:" -ForegroundColor DarkGray
        Write-Host "       validation: confirm the latest recorded result matches the task output being reviewed" -ForegroundColor DarkGray
        Write-Host "       sync hygiene: confirm clean, covered, not requested, or intentionally reviewed before release" -ForegroundColor DarkGray
        Write-Host "       source: inspect git status, diff stat, and full diff in the target project" -ForegroundColor DarkGray
        Write-Host "       rollback: confirm the VM checkpoint and Git rollback path before accepting risky work" -ForegroundColor DarkGray
        Write-Host "       commit: commit only after sync hygiene, validation, and human review are all accepted" -ForegroundColor DarkGray
        Write-Host "     handoff:" -ForegroundColor DarkGray
        Write-Host "       review:   adp workspace task review $($item.TaskName) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-Host "       rollback: adp workspace task rollback $($item.TaskName) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-Host "       commit:   adp workspace task commit $($item.TaskName) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-Host "       inspect:  git status --short; git diff --stat; git diff" -ForegroundColor DarkGray
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
        [object]$Task,
        [switch]$ExplicitExecution
    )

    Write-Host ""
    Write-Host "Workspace task $Action`: $($Task.name)" -ForegroundColor Cyan
    if ($ExplicitExecution) {
        Write-Host "Explicit execution mode. ADP-OS runs only the declared validation commands; it does not create snapshots, stage files, or commit changes." -ForegroundColor DarkGray
    } else {
        Write-Host "Task lifecycle output is plan-only. No VM, sync, snapshot, file, Git, or validation command will be changed or run." -ForegroundColor DarkGray
    }
    Write-Host ""
}

function Write-TaskSummary {
    param(
        [object]$Manifest,
        [object]$Task
    )

    $runtime = if ($Task.runtime) { $Task.runtime } else { "not configured" }
    $snapshot = if ($Task.snapshot) { $Task.snapshot } else { "not configured" }
    $risk = Get-WorkspaceTaskRisk -Task $Task
    $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $Task
    $snapshotNaming = Get-WorkspaceSnapshotNamingStatus -Task $Task
    $taskMilestones = if ($Manifest) { Get-WorkspaceTaskMilestones -Manifest $Manifest -Task $Task } else { @() }
    $milestoneNames = @($taskMilestones | ForEach-Object { if ($_.name) { [string]$_.name } })
    $milestoneText = if ($milestoneNames.Count -gt 0) { $milestoneNames -join ', ' } else { "not set" }

    Write-Host "Task:" -ForegroundColor Yellow
    Write-Host "  Name:      $($Task.name)" -ForegroundColor DarkGray
    Write-Host "  Milestone: $milestoneText" -ForegroundColor DarkGray
    Write-Host "  Runtime:   $runtime" -ForegroundColor DarkGray
    Write-Host "  Risk:      $risk" -ForegroundColor DarkGray
    Write-Host "  Snapshot required: $requiresSnapshot" -ForegroundColor DarkGray
    Write-Host "  Snapshot:  $snapshot" -ForegroundColor DarkGray
    Write-Host "  Snapshot naming: $($snapshotNaming.Status) - $($snapshotNaming.Detail)" -ForegroundColor DarkGray

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
    Write-TaskSummary -Manifest $Manifest -Task $Task

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
        $recommendedSnapshot = Get-WorkspaceRecommendedSnapshotName -Task $Task
        Write-Host "  4. Add tasks[].snapshot before planning checkpoint commands." -ForegroundColor DarkGray
        Write-Host "     Recommended: `"$recommendedSnapshot`"" -ForegroundColor DarkGray
    }

    Write-Host "  5. Review validation expectations:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
}

function Write-WorkspaceTaskSnapshot {
    param(
        [object]$Manifest,
        [object]$Task,
        [string]$StatePath
    )

    Write-TaskHeader -Action "snapshot" -Task $Task
    Write-TaskSummary -Manifest $Manifest -Task $Task

    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $recordedState = Get-WorkspaceTaskState -State $state -TaskName $Task.name
    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    $snapshotGate = Get-WorkspaceSnapshotGate -Task $Task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
    $snapshotNaming = Get-WorkspaceSnapshotNamingStatus -Task $Task
    Write-Host ""
    Write-Host "Checkpoint:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $snapshotNaming.Level -Name "snapshot naming" -Detail "($($snapshotNaming.Status): $($snapshotNaming.Detail))"
    Write-WorkspaceCheck -Level $snapshotStatus.Level -Name "snapshot" -Detail "($($snapshotStatus.Status)$(if ($snapshotStatus.Detail) { ': ' + $snapshotStatus.Detail }))"
    Write-WorkspaceCheck -Level $snapshotGate.Level -Name "snapshot-first gate" -Detail "($($snapshotGate.Status): $($snapshotGate.Detail))"
    Write-Host "  Local state: $resolvedStatePath" -ForegroundColor DarkGray

    if ($Task.runtime -and $Task.snapshot) {
        Write-Host ""
        Write-Host "Explicit command to create the checkpoint when ready:" -ForegroundColor Yellow
        Write-Host "  adp snapshot create $($Task.runtime) $($Task.snapshot)" -ForegroundColor DarkGray
        Write-Host "  If the human reviewer intentionally accepts missing snapshot protection:" -ForegroundColor Yellow
        Write-Host "  adp workspace task mark $($Task.name) checkpoint-waived" -ForegroundColor DarkGray
    } else {
        Write-Host ""
        Write-Host "Add tasks[].runtime and tasks[].snapshot before creating a checkpoint." -ForegroundColor Yellow
    }
}

function Write-WorkspaceTaskValidate {
    param(
        [object]$Manifest,
        [object]$Task,
        [string]$StatePath,
        [switch]$ExecuteValidation,
        [switch]$PlanOnly
    )

    Write-TaskHeader -Action "validate" -Task $Task -ExplicitExecution:$ExecuteValidation
    Write-TaskSummary -Manifest $Manifest -Task $Task

    $validationCommands = Get-WorkspaceArray $Task.validation
    Write-Host ""
    $mode = if ($ExecuteValidation) { "Validation execution:" } else { "Validation plan:" }
    Write-Host $mode -ForegroundColor Yellow
    if ($validationCommands.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "task validation" -Detail "(none configured)"
        Write-Host "  Add tasks[].validation commands before using this task for review gates." -ForegroundColor DarkGray
        return
    }

    if (-not $ExecuteValidation) {
        $index = 1
        foreach ($command in $validationCommands) {
            Write-Host "  $index. $command" -ForegroundColor DarkGray
            $index += 1
        }

        Write-Host ""
        Write-Host "To execute validation explicitly:" -ForegroundColor Yellow
        Write-Host "  adp workspace task validate $($Task.name) -Execute -ManifestPath <manifest>" -ForegroundColor DarkGray
        Write-Host "  Add -Plan to preview the remote SSH commands without running them." -ForegroundColor DarkGray
        return
    }

    $project = Find-WorkspaceProjectForTask -Manifest $Manifest -Task $Task
    $remotePath = Resolve-WorkspaceRemoteProjectPath -Project $project
    $sshTarget = Get-WorkspaceRuntimeSshTarget -RuntimeName $Task.runtime
    $runtimeStatus = Get-WorkspaceRuntimeStatus -RuntimeName $Task.runtime
    $syncExpected = ($null -ne $project.sync -and [bool]$project.sync)
    $syncStatus = Get-WorkspaceSyncStatus -RuntimeName $Task.runtime -Expected $syncExpected
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $recordedState = Get-WorkspaceTaskState -State $state -TaskName $Task.name
    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    $snapshotGate = Get-WorkspaceSnapshotGate -Task $Task -SnapshotStatus $snapshotStatus -RecordedState $recordedState

    Write-Host ""
    Write-Host "Readiness gate:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "project" -Detail "($($project.name): $remotePath)"
    Write-WorkspaceCheck -Level $runtimeStatus.Level -Name "runtime $($Task.runtime)" -Detail "($($runtimeStatus.Status): $($runtimeStatus.Detail))"
    Write-WorkspaceCheck -Level $syncStatus.Level -Name "sync" -Detail "($($syncStatus.Status)$(if ($syncStatus.Detail) { ': ' + $syncStatus.Detail }))"
    Write-WorkspaceCheck -Level $snapshotGate.Level -Name "snapshot-first gate" -Detail "($($snapshotGate.Status): $($snapshotGate.Detail))"
    Write-WorkspaceCheck -Level "OK" -Name "ssh target" -Detail "($($sshTarget.User)@$($sshTarget.Host):$($sshTarget.Port))"

    if (-not $PlanOnly) {
        $blockingReasons = @()
        if ($runtimeStatus.Level -eq "FAIL") {
            $blockingReasons += "runtime is blocked: $($runtimeStatus.Detail)"
        }
        if ($snapshotGate.Blocking) {
            $blockingReasons += "snapshot-first gate is blocked: $($snapshotGate.Detail)"
        }
        if ($blockingReasons.Count -gt 0) {
            foreach ($reason in $blockingReasons) {
                Write-ErrorLog -Message $reason -Component "cli.workspace"
            }
            exit 1
        }
    }

    if ($PlanOnly) {
        Write-Host ""
        Write-Host "Plan only: validation commands will not be executed." -ForegroundColor Cyan
    } else {
        Write-Host ""
        Write-Host "Executing declared validation commands. No packages, browsers, snapshots, Git staging, or commits are managed by ADP-OS beyond these commands." -ForegroundColor Yellow
    }

    $index = 1
    $startedAt = (Get-Date).ToUniversalTime().ToString("o")
    $commands = @($validationCommands | ForEach-Object { [string]$_ })
    foreach ($command in $validationCommands) {
        $remoteCommand = "cd $(Quote-PosixSingleArgument $remotePath) && $command"
        if ($PlanOnly) {
            Write-Host "  $index. ssh -i $($sshTarget.KeyPath) -p $($sshTarget.Port) $($sshTarget.User)@$($sshTarget.Host) $(Quote-PosixSingleArgument $remoteCommand)" -ForegroundColor DarkGray
        } else {
            Write-Host ""
            Write-Host "[$index/$($validationCommands.Count)] $command" -ForegroundColor Yellow
            Invoke-WorkspaceRemoteValidationCommand -SshTarget $sshTarget -RemoteCommand $remoteCommand
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                $completedAt = (Get-Date).ToUniversalTime().ToString("o")
                $validation = New-WorkspaceValidationResult -Task $Task -Project $project -RemotePath $remotePath -Status "failed" -StartedAt $startedAt -CompletedAt $completedAt -Commands $commands -ExitCode $exitCode -FailedCommand ([string]$command)
                $resolvedStatePath = Write-WorkspaceValidationResult -StatePath $StatePath -Task $Task -Validation $validation
                Write-Host ""
                Write-Host "Validation result recorded: $resolvedStatePath" -ForegroundColor DarkGray
                Write-ErrorLog -Message "Workspace validation command failed with exit code $exitCode`: $command" -Component "cli.workspace"
                exit $exitCode
            }
        }
        $index += 1
    }

    if (-not $PlanOnly) {
        $completedAt = (Get-Date).ToUniversalTime().ToString("o")
        $validation = New-WorkspaceValidationResult -Task $Task -Project $project -RemotePath $remotePath -Status "passed" -StartedAt $startedAt -CompletedAt $completedAt -Commands $commands -ExitCode 0
        $resolvedStatePath = Write-WorkspaceValidationResult -StatePath $StatePath -Task $Task -Validation $validation
        Write-Host ""
        Write-Host "Workspace validation complete: $($Task.name)" -ForegroundColor Green
        Write-Host "  Result recorded: $resolvedStatePath" -ForegroundColor DarkGray
        Write-Host "  Review remains explicit; ADP-OS did not stage files or commit changes." -ForegroundColor DarkGray
    }
}

function Write-WorkspaceTaskRun {
    param(
        [object]$Manifest,
        [object]$Task,
        [string]$ManifestPath,
        [string]$StatePath
    )

    Write-TaskHeader -Action "run" -Task $Task
    Write-TaskSummary -Manifest $Manifest -Task $Task

    Write-Host ""
    Write-Host "Execution boundary:" -ForegroundColor Yellow
    Write-Host "  Manual execution only: this command does not start an agent, approve broad agent work, record task state, run validation, or make the task commit-ready." -ForegroundColor DarkGray
    Write-Host "  1. Confirm readiness:" -ForegroundColor DarkGray
    Write-Host "     adp workspace status -ManifestPath $ManifestPath" -ForegroundColor DarkGray

    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $recordedState = Get-WorkspaceTaskState -State $state -TaskName $Task.name
    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    $snapshotGate = Get-WorkspaceSnapshotGate -Task $Task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
    if ($Task.runtime -and $Task.snapshot) {
        Write-Host "  2. Snapshot-first gate before broad agent work:" -ForegroundColor DarkGray
        Write-Host "     adp workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        if ($snapshotGate.Blocking) {
            Write-Host "     BLOCKED: $($snapshotGate.Detail)" -ForegroundColor Yellow
            Write-Host "     Do not start broad agent work until this gate is ready or explicitly waived in local ADP-OS state." -ForegroundColor Yellow
            Write-Host "     Waive only after human acceptance of the missing checkpoint risk:" -ForegroundColor Yellow
            Write-Host "     adp workspace task mark $($Task.name) checkpoint-waived -ManifestPath $ManifestPath" -ForegroundColor DarkGray
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
    Write-Host "     After manual execution starts, mark running only as local state:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task mark $($Task.name) running -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "  5. Validate before review:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "  6. Move to review:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task review $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
}

function Write-WorkspaceTaskReview {
    param(
        [object]$Manifest,
        [object]$Task,
        [string]$ManifestPath,
        [string]$StatePath
    )

    Write-TaskHeader -Action "review" -Task $Task
    Write-TaskSummary -Manifest $Manifest -Task $Task
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $recordedState = Get-WorkspaceTaskState -State $state -TaskName $Task.name
    $validationStateText = Format-WorkspaceValidationState -RecordedState $recordedState
    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    $snapshotGate = Get-WorkspaceSnapshotGate -Task $Task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
    $validationCommands = Get-WorkspaceArray $Task.validation
    $syncContext = Get-WorkspaceTaskSyncHygieneStatus -Manifest $Manifest -Task $Task
    $syncHygiene = $syncContext.Hygiene
    $reviewDecision = Get-WorkspaceReviewDecision -Task $Task -RecordedState $recordedState -SnapshotGate $snapshotGate -ValidationCommandCount $validationCommands.Count -SyncHygiene $syncHygiene

    Write-Host ""
    Write-Host "Human review bundle:" -ForegroundColor Yellow
    Write-Host "  0. Review decision gate:" -ForegroundColor DarkGray
    Write-WorkspaceReviewDecision -Decision $reviewDecision
    Write-Host "  1. Confirm sync hygiene before review:" -ForegroundColor DarkGray
    Write-WorkspaceCheck -Level $syncHygiene.Level -Name "sync hygiene" -Detail "($($syncHygiene.Status)$(if ($syncHygiene.Detail) { ': ' + $syncHygiene.Detail }))"
    if (Test-WorkspaceSyncHygieneBlocking -SyncHygiene $syncHygiene) {
        Write-Host "     Review should not accept the task until sync hygiene is reviewed or the runtime sync profile is updated." -ForegroundColor Yellow
    }
    Write-Host "  2. Confirm readiness before review:" -ForegroundColor DarkGray
    Write-Host "     adp workspace status -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "  3. Confirm checkpoint state:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    if (Test-WorkspaceTaskRequiresSnapshot -Task $Task) {
        Write-Host "     Review should not accept broad agent work until the snapshot-first gate is ready or explicitly waived in local ADP-OS state." -ForegroundColor DarkGray
        Write-Host "     waiver: adp workspace task mark $($Task.name) checkpoint-waived -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    }
    Write-Host "  4. Run or inspect validation commands:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "     recorded validation: $validationStateText" -ForegroundColor DarkGray
    Write-WorkspaceValidationDetailLines -RecordedState $recordedState
    Write-Host "     state file: $resolvedStatePath" -ForegroundColor DarkGray
    Write-Host "  5. Inspect source changes in the target project:" -ForegroundColor DarkGray
    Write-Host "     git status --short" -ForegroundColor DarkGray
    Write-Host "     git diff --stat" -ForegroundColor DarkGray
    Write-Host "     git diff" -ForegroundColor DarkGray
    Write-Host "  6. Decide explicitly:" -ForegroundColor DarkGray
    Write-Host "     rollback: adp workspace task rollback $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "     revise:   fix the task result and re-run validation" -ForegroundColor DarkGray
    Write-Host "     commit:   adp workspace task commit $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    if ($reviewDecision.Verdict -eq "validation passed") {
        Write-Host "     accept:   adp workspace task mark $($Task.name) reviewed -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    } else {
        Write-Host "     accept:   withheld until review decision gate is OK" -ForegroundColor Yellow
        Write-Host "     resolve:  $($reviewDecision.NextStep)" -ForegroundColor DarkGray
    }
    Write-Host "     Commit readiness requires sync hygiene, recorded validation, plus local state 'reviewed' or 'committed'." -ForegroundColor DarkGray
}

function Write-WorkspaceTaskRollback {
    param(
        [object]$Manifest,
        [object]$Task,
        [string]$ManifestPath,
        [string]$StatePath
    )

    Write-TaskHeader -Action "rollback" -Task $Task
    Write-TaskSummary -Manifest $Manifest -Task $Task
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $recordedState = Get-WorkspaceTaskState -State $state -TaskName $Task.name
    $validationStateText = Format-WorkspaceValidationState -RecordedState $recordedState
    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    $snapshotGate = Get-WorkspaceSnapshotGate -Task $Task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
    $validationCommands = Get-WorkspaceArray $Task.validation
    $syncContext = Get-WorkspaceTaskSyncHygieneStatus -Manifest $Manifest -Task $Task
    $syncHygiene = $syncContext.Hygiene
    $reviewDecision = Get-WorkspaceReviewDecision -Task $Task -RecordedState $recordedState -SnapshotGate $snapshotGate -ValidationCommandCount $validationCommands.Count -SyncHygiene $syncHygiene

    Write-Host ""
    Write-Host "Rollback boundary:" -ForegroundColor Yellow
    Write-Host "  Decision context:" -ForegroundColor DarkGray
    Write-WorkspaceReviewDecision -Decision $reviewDecision
    Write-Host "     sync hygiene: $($syncHygiene.Status)$(if ($syncHygiene.Detail) { ' - ' + $syncHygiene.Detail })" -ForegroundColor DarkGray
    Write-Host "     recorded validation: $validationStateText" -ForegroundColor DarkGray
    Write-WorkspaceValidationDetailLines -RecordedState $recordedState
    Write-Host "     state file: $resolvedStatePath" -ForegroundColor DarkGray
    if ($Task.runtime -and $Task.snapshot) {
        if ($snapshotGate.Blocking) {
            Write-Host "  VM snapshot rollback command:" -ForegroundColor Yellow
            Write-Host "     Snapshot rollback is not ready: $($snapshotGate.Detail)" -ForegroundColor Yellow
            Write-Host "     Resolve the checkpoint gate before using VM snapshot rollback." -ForegroundColor DarkGray
        } elseif ($snapshotGate.Status -eq "waived") {
            Write-Host "  VM snapshot rollback command:" -ForegroundColor Yellow
            Write-Host "     Snapshot rollback is waived: $($snapshotGate.Detail)" -ForegroundColor Yellow
            Write-Host "     No VM restore command is printed because no checkpoint was confirmed." -ForegroundColor DarkGray
        } else {
            Write-Host "  VM snapshot rollback command:" -ForegroundColor DarkGray
            Write-Host "     adp restore $($Task.runtime) $($Task.snapshot)" -ForegroundColor DarkGray
        }
    } else {
        Write-Host "  Add tasks[].runtime and tasks[].snapshot before planning VM snapshot rollback." -ForegroundColor DarkGray
    }

    Write-Host "  Source rollback remains a separate Git decision inside the target project:" -ForegroundColor DarkGray
    Write-Host "     git status --short" -ForegroundColor DarkGray
    Write-Host "     git diff --stat" -ForegroundColor DarkGray
    Write-Host "     git restore <paths>" -ForegroundColor DarkGray
    Write-Host "  Do not run restore commands until the human reviewer has chosen rollback." -ForegroundColor DarkGray
    Write-Host "  After rollback is completed manually, record local rollback state:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task mark $($Task.name) rollback -ManifestPath $ManifestPath" -ForegroundColor DarkGray
}

function Write-WorkspaceTaskCommit {
    param(
        [object]$Manifest,
        [object]$Task,
        [string]$ManifestPath,
        [string]$StatePath
    )

    Write-TaskHeader -Action "commit" -Task $Task
    Write-TaskSummary -Manifest $Manifest -Task $Task
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $recordedState = Get-WorkspaceTaskState -State $state -TaskName $Task.name
    $validationStateText = Format-WorkspaceValidationState -RecordedState $recordedState
    $recordedTaskState = Get-WorkspaceRecordedTaskStateName -RecordedState $recordedState
    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    $snapshotGate = Get-WorkspaceSnapshotGate -Task $Task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
    $validationCommands = Get-WorkspaceArray $Task.validation
    $syncContext = Get-WorkspaceTaskSyncHygieneStatus -Manifest $Manifest -Task $Task
    $syncHygiene = $syncContext.Hygiene
    $commitDecision = Get-WorkspaceCommitDecision -Task $Task -RecordedState $recordedState -SnapshotGate $snapshotGate -ValidationCommandCount $validationCommands.Count -SyncHygiene $syncHygiene

    Write-Host ""
    Write-Host "Commit boundary:" -ForegroundColor Yellow
    Write-Host "  0. Commit readiness gate:" -ForegroundColor DarkGray
    Write-WorkspaceCommitDecision -Decision $commitDecision
    Write-Host "     sync hygiene: $($syncHygiene.Status)$(if ($syncHygiene.Detail) { ' - ' + $syncHygiene.Detail })" -ForegroundColor DarkGray
    Write-Host "     recorded task state: $recordedTaskState" -ForegroundColor DarkGray
    Write-Host "     recorded validation: $validationStateText" -ForegroundColor DarkGray
    Write-WorkspaceValidationDetailLines -RecordedState $recordedState
    Write-Host "     state file: $resolvedStatePath" -ForegroundColor DarkGray
    Write-Host "  1. Confirm review bundle:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task review $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "  2. Confirm validation expectations:" -ForegroundColor DarkGray
    Write-Host "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-Host "  3. Inspect source changes in the target project:" -ForegroundColor DarkGray
    Write-Host "     git status --short" -ForegroundColor DarkGray
    Write-Host "     git diff --stat" -ForegroundColor DarkGray
    Write-Host "     git diff" -ForegroundColor DarkGray
    if ($commitDecision.Verdict -eq "commit ready") {
        Write-Host "  4. Commit only after the human reviewer accepts the task result:" -ForegroundColor DarkGray
        Write-Host "     git add <paths>" -ForegroundColor DarkGray
        Write-Host "     git commit -m ""<message>""" -ForegroundColor DarkGray
        Write-Host "  5. After the commit is created manually, record local committed state:" -ForegroundColor DarkGray
        Write-Host "     adp workspace task mark $($Task.name) committed -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    } else {
        Write-Host "  4. Commit commands withheld until commit readiness is OK." -ForegroundColor Yellow
        Write-Host "     Resolve gate first: $($commitDecision.NextStep)" -ForegroundColor DarkGray
    }
}

function Write-WorkspaceTaskMark {
    param(
        [object]$Task,
        [string]$StateName,
        [string]$Path
    )

    $validStates = @("prepared", "checkpointed", "checkpoint-waived", "running", "validated", "reviewed", "rollback", "committed")
    if ([string]::IsNullOrWhiteSpace($StateName) -or $StateName -notin $validStates) {
        Write-ErrorLog -Message "Unknown workspace task state: $StateName. Valid: $($validStates -join ', ')" -Component "cli.workspace"
        exit 1
    }

    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $Path
    $state = Read-WorkspaceState -Path $resolvedStatePath
    if ($StateName -eq "checkpoint-waived") {
        $state = Set-WorkspaceTaskCheckpointWaiver -State $state -TaskName $Task.name
    } else {
        $state = Set-WorkspaceTaskState -State $state -TaskName $Task.name -StateName $StateName
    }
    Write-WorkspaceState -State $state -Path $resolvedStatePath

    Write-Host ""
    Write-Host "Workspace task mark: $($Task.name)" -ForegroundColor Cyan
    Write-Host "Recorded local lifecycle state only. No VM, sync, snapshot, file, Git, or validation command was run." -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "  State: $StateName" -ForegroundColor Green
    Write-Host "  File:  $resolvedStatePath" -ForegroundColor DarkGray
    switch ($StateName) {
        "checkpoint-waived" {
            Write-Host "  Boundary: checkpoint-waived records explicit human acceptance of missing VM snapshot protection. It does not create a snapshot, prove rollback safety, or restore rollback capability." -ForegroundColor Yellow
            Write-Host "  Evidence: workspace status, dashboard, project, report, review, rollback, and commit will show the checkpoint gate as waived instead of ready." -ForegroundColor DarkGray
        }
        "running" {
            Write-Host "  Boundary: running means manual execution began or was attempted; ADP-OS did not start the agent, approve execution, validate output, or satisfy review/commit readiness." -ForegroundColor Yellow
        }
        "validated" {
            Write-Host "  Boundary: validated is a local lifecycle note only. Use 'adp workspace task validate <task> -Execute' to record executable validation evidence." -ForegroundColor Yellow
        }
        "reviewed" {
            Write-Host "  Boundary: reviewed should be used only after human source review accepts the diff, rollback path, snapshot context, and recorded validation evidence." -ForegroundColor Yellow
        }
        "committed" {
            Write-Host "  Boundary: committed is a local lifecycle note only; ADP-OS did not stage files or run git commit." -ForegroundColor Yellow
        }
        "rollback" {
            Write-Host "  Boundary: rollback is a local lifecycle note only; ADP-OS did not restore snapshots or modify source files." -ForegroundColor Yellow
        }
        default {
            Write-Host "  Boundary: this state does not prove execution, validation, review acceptance, rollback readiness, or commit readiness." -ForegroundColor DarkGray
        }
    }
}

function Invoke-WorkspaceTask {
    param(
        [object]$Manifest,
        [string]$Command,
        [string]$Name,
        [string]$StateName,
        [string]$Path,
        [string]$LocalStatePath,
        [switch]$ExecuteValidation,
        [switch]$PlanOnly
    )

    $validTaskCommands = @("prepare", "snapshot", "run", "validate", "review", "rollback", "commit", "mark")
    if ([string]::IsNullOrWhiteSpace($Command) -or $Command -notin $validTaskCommands) {
        Write-ErrorLog -Message "Unknown workspace task command: $Command. Valid: $($validTaskCommands -join ', ')" -Component "cli.workspace"
        exit 1
    }

    if (($ExecuteValidation -or $PlanOnly) -and $Command -ne "validate") {
        Write-ErrorLog -Message "-Execute and -Plan are only supported with: adp workspace task validate <task-name>" -Component "cli.workspace"
        exit 1
    }

    if ($PlanOnly -and -not $ExecuteValidation) {
        Write-ErrorLog -Message "-Plan is only supported with -Execute for workspace task validation." -Component "cli.workspace"
        exit 1
    }

    $task = Find-WorkspaceTask -Manifest $Manifest -Name $Name

    switch ($Command) {
        "prepare" {
            Write-WorkspaceTaskPrepare -Manifest $Manifest -Task $task -ManifestPath $Path
        }
        "snapshot" {
            Write-WorkspaceTaskSnapshot -Manifest $Manifest -Task $task -StatePath $LocalStatePath
        }
        "run" {
            Write-WorkspaceTaskRun -Manifest $Manifest -Task $task -ManifestPath $Path -StatePath $LocalStatePath
        }
        "validate" {
            Write-WorkspaceTaskValidate -Manifest $Manifest -Task $task -StatePath $LocalStatePath -ExecuteValidation:$ExecuteValidation -PlanOnly:$PlanOnly
        }
        "review" {
            Write-WorkspaceTaskReview -Manifest $Manifest -Task $task -ManifestPath $Path -StatePath $LocalStatePath
        }
        "rollback" {
            Write-WorkspaceTaskRollback -Manifest $Manifest -Task $task -ManifestPath $Path -StatePath $LocalStatePath
        }
        "commit" {
            Write-WorkspaceTaskCommit -Manifest $Manifest -Task $task -ManifestPath $Path -StatePath $LocalStatePath
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
                $snapshotNaming = Get-WorkspaceSnapshotNamingStatus -Task $task
                Write-Host "  - Snapshot before task '$($task.name)' (naming: $($snapshotNaming.Status)): adp snapshot create $($task.runtime) $($task.snapshot)" -ForegroundColor DarkGray
            }
        }
        foreach ($milestone in (Get-WorkspaceMilestones -Manifest $manifest)) {
            $milestoneStatus = Get-WorkspaceMilestoneStatus -Manifest $manifest -Milestone $milestone
            if ($milestoneStatus.RuntimeName -ne "not configured") {
                Write-Host "  - Milestone checkpoint '$($milestoneStatus.Name)' (naming: $($milestoneStatus.SnapshotNaming.Status)): adp snapshot create $($milestoneStatus.RuntimeName) $($milestoneStatus.SnapshotName)" -ForegroundColor DarkGray
            }
        }
    }
    "status" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceStatus -Manifest $manifest -StatePath $StatePath
    }
    "dashboard" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceDashboard -Manifest $manifest -ManifestPath $ManifestPath -StatePath $StatePath
    }
    "report" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceReport -Manifest $manifest -ManifestPath $ManifestPath -StatePath $StatePath -Markdown:$Markdown
    }
    "recipes" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceRecipes -Manifest $manifest -ManifestPath $ManifestPath -StatePath $StatePath
    }
    "create" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceCreate -Manifest $manifest -ManifestPath $ManifestPath -PlanOnly:$Plan
    }
    "open" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceOpen -Manifest $manifest -ProjectName $TaskCommand -ManifestPath $ManifestPath
    }
    "sync" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceSyncGuide -Manifest $manifest -ProjectName $TaskCommand -ManifestPath $ManifestPath
    }
    "project" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceProjectLifecycle -Manifest $manifest -ProjectName $TaskCommand -ManifestPath $ManifestPath -StatePath $StatePath
    }
    "task" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Invoke-WorkspaceTask -Manifest $manifest -Command $TaskCommand -Name $TaskName -StateName $TaskState -Path $ManifestPath -LocalStatePath $StatePath -ExecuteValidation:$Execute -PlanOnly:$Plan
    }
    default {
        Write-ErrorLog -Message "Unknown workspace command: $SubCommand. Valid: init, show, plan, status, dashboard, report, recipes, create, open, sync, project, task" -Component "cli.workspace"
        exit 1
    }
}
