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
    Write-UIHost -English "  adp workspace recipes [-ManifestPath <path>]" -Chinese "  adp workspace recipes [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace create [-Plan] [-ManifestPath <path>]" -Chinese "  adp workspace create [-Plan] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace open [project-name] [-ManifestPath <path>]" -Chinese "  adp workspace open [project-name] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace sync [project-name] [-ManifestPath <path>]" -Chinese "  adp workspace sync [project-name] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace project [project-name] [-ManifestPath <path>]" -Chinese "  adp workspace project [project-name] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace report [-Markdown] [-ManifestPath <path>]" -Chinese "  adp workspace report [-Markdown] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name> [-ManifestPath <path>]" -Chinese "  adp workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name> [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace task validate <task-name> [-Execute] [-Plan] [-ManifestPath <path>]" -Chinese "  adp workspace task validate <task-name> [-Execute] [-Plan] [-ManifestPath <path>]" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace task mark <task-name> <prepared|checkpointed|checkpoint-waived|running|validated|reviewed|rollback|committed> [-StatePath <path>]" -Chinese "  adp workspace task mark <task-name> <prepared|checkpointed|checkpoint-waived|running|validated|reviewed|rollback|committed> [-StatePath <path>]" -ForegroundColor DarkGray
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
    Write-UIHost -English "     next: $($Decision.NextStep)" -Chinese "     下一步: $($Decision.NextStep)" -ForegroundColor DarkGray
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
    Write-UIHost -English "     next: $($Decision.NextStep)" -Chinese "     下一步: $($Decision.NextStep)" -ForegroundColor DarkGray
}

function Write-WorkspaceValidationDetailLines {
    param([object]$RecordedState)

    if (-not $RecordedState -or -not ($RecordedState.PSObject.Properties.Name -contains "validation") -or -not $RecordedState.validation) {
        Write-UIHost -English "     validation detail: no recorded execution result" -Chinese "     验证详情: 无已记录的执行结果" -ForegroundColor DarkGray
        return
    }

    $validation = $RecordedState.validation
    if ($validation.PSObject.Properties.Name -contains "failed_command" -and -not [string]::IsNullOrWhiteSpace([string]$validation.failed_command)) {
        Write-UIHost -English "     failed command: $($validation.failed_command)" -Chinese "     失败的命令: $($validation.failed_command)" -ForegroundColor DarkGray
    }
    if ($validation.PSObject.Properties.Name -contains "remote_path" -and -not [string]::IsNullOrWhiteSpace([string]$validation.remote_path)) {
        Write-UIHost -English "     remote path: $($validation.remote_path)" -Chinese "     远程路径: $($validation.remote_path)" -ForegroundColor DarkGray
    }
    if ($validation.PSObject.Properties.Name -contains "command_count") {
        Write-UIHost -English "     command count: $($validation.command_count)" -Chinese "     命令计数: $($validation.command_count)" -ForegroundColor DarkGray
    }
}

function Write-WorkspaceSummary {
    param([object]$Manifest)

    Write-UIHost -English "Workspace: $($Manifest.name)" -Chinese "工作区: $($Manifest.name)" -ForegroundColor Cyan
    if ($Manifest.description) {
        Write-UIHost -English "  $($Manifest.description)" -Chinese "  $($Manifest.description)" -ForegroundColor DarkGray
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Projects:" -Chinese "项目:" -ForegroundColor Yellow
    foreach ($project in (Get-WorkspaceArray $Manifest.projects)) {
        $runtime = if ($project.runtime) { $project.runtime } else { "not configured" }
        $sync = if ($null -ne $project.sync) { $project.sync } else { "not configured" }
        Write-UIHost -English "  - $($project.name): $($project.path) -> $runtime (sync: $sync)" -Chinese "  - $($project.name): $($project.path) -> $runtime (同步: $sync)" -ForegroundColor DarkGray
        $projectPath = Resolve-ProjectWorkspacePath -Project $project
        $devContainerStatus = Get-WorkspaceDevContainerStatus -ProjectPath $projectPath
        Write-UIHost -English "      devcontainer: $($devContainerStatus.Status)$(if ($devContainerStatus.Detail) { ' - ' + $devContainerStatus.Detail })" -Chinese "      devcontainer: $($devContainerStatus.Status)$(if ($devContainerStatus.Detail) { ' - ' + $devContainerStatus.Detail })" -ForegroundColor DarkGray
        $syncHygieneStatus = Get-WorkspaceSyncHygieneStatus -Project $project -ProjectPath $projectPath
        Write-UIHost -English "      sync hygiene: $($syncHygieneStatus.Status)$(if ($syncHygieneStatus.Detail) { ' - ' + $syncHygieneStatus.Detail })" -Chinese "      同步卫生: $($syncHygieneStatus.Status)$(if ($syncHygieneStatus.Detail) { ' - ' + $syncHygieneStatus.Detail })" -ForegroundColor DarkGray
        foreach ($command in (Get-WorkspaceArray $project.validation)) {
            Write-UIHost -English "      validate: $command" -Chinese "      验证: $command" -ForegroundColor DarkGray
        }
    }

    $milestones = Get-WorkspaceMilestones -Manifest $Manifest
    if ($milestones.Count -gt 0) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Milestones:" -Chinese "里程碑:" -ForegroundColor Yellow
        foreach ($milestone in $milestones) {
            $status = Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $milestone
            $name = if ($milestone.name) { [string]$milestone.name } else { "(unnamed)" }
            Write-UIHost -English "  - $name`: runtime=$($status.RuntimeName) snapshot=$($status.SnapshotName) tasks=$($status.TaskNames.Count)" -Chinese "  - $name`: 运行时=$($status.RuntimeName) 快照=$($status.SnapshotName) 任务数=$($status.TaskNames.Count)" -ForegroundColor DarkGray
            if ($milestone.description) {
                Write-UIHost -English "      $($milestone.description)" -Chinese "      $($milestone.description)" -ForegroundColor DarkGray
            }
            Write-UIHost -English "      snapshot naming: $($status.SnapshotNaming.Status) - $($status.SnapshotNaming.Detail)" -Chinese "      快照命名: $($status.SnapshotNaming.Status) - $($status.SnapshotNaming.Detail)" -ForegroundColor DarkGray
            Write-UIHost -English "      linked tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' })" -Chinese "      关联任务: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { '无' })" -ForegroundColor DarkGray
        }
    }

    $evaluations = Get-WorkspaceEvaluations -Manifest $Manifest
    if ($evaluations.Count -gt 0) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Evaluations:" -Chinese "评估:" -ForegroundColor Yellow
        foreach ($evaluation in $evaluations) {
            $status = Get-WorkspaceEvaluationStatus -Manifest $Manifest -Evaluation $evaluation
            Write-UIHost -English "  - $($status.Name): runtime=$($status.RuntimeName) project=$($status.ProjectName) metrics=$($status.Metrics.Count) commands=$($status.Commands.Count) tasks=$($status.TaskNames.Count)" -Chinese "  - $($status.Name): 运行时=$($status.RuntimeName) 项目=$($status.ProjectName) 指标=$($status.Metrics.Count) 命令=$($status.Commands.Count) 任务数=$($status.TaskNames.Count)" -ForegroundColor DarkGray
            Write-UIHost -English "      cadence: $($status.Cadence); readiness: $($status.Readiness)" -Chinese "      节奏: $($status.Cadence); 就绪状态: $($status.Readiness)" -ForegroundColor DarkGray
            if ($evaluation.description) {
                Write-UIHost -English "      $($evaluation.description)" -Chinese "      $($evaluation.description)" -ForegroundColor DarkGray
            }
            if ($status.TaskNames.Count -gt 0) {
                Write-UIHost -English "      linked tasks: $($status.TaskNames -join ', ')" -Chinese "      关联任务: $($status.TaskNames -join ', ')" -ForegroundColor DarkGray
            }
            foreach ($metric in $status.Metrics) {
                Write-UIHost -English "      metric: $metric" -Chinese "      指标: $metric" -ForegroundColor DarkGray
            }
        }
    }

    if ($Manifest.tasks) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Tasks:" -Chinese "任务:" -ForegroundColor Yellow
        foreach ($task in (Get-WorkspaceArray $Manifest.tasks)) {
            $runtime = if ($task.runtime) { $task.runtime } else { "not configured" }
            $snapshot = if ($task.snapshot) { $task.snapshot } else { "not configured" }
            $taskMilestones = Get-WorkspaceTaskMilestones -Manifest $Manifest -Task $task
            $milestoneNames = @($taskMilestones | ForEach-Object { if ($_.name) { [string]$_.name } })
            $milestoneText = if ($milestoneNames.Count -gt 0) { $milestoneNames -join ', ' } else { "none" }
            $taskEvaluations = Get-WorkspaceTaskEvaluations -Manifest $Manifest -Task $task
            $evaluationNames = @($taskEvaluations | ForEach-Object { if ($_.name) { [string]$_.name } })
            $evaluationText = if ($evaluationNames.Count -gt 0) { $evaluationNames -join ', ' } else { "none" }
            Write-UIHost -English "  - $($task.name): runtime=$runtime snapshot=$snapshot milestone=$milestoneText evaluation=$evaluationText" -Chinese "  - $($task.name): 运行时=$runtime 快照=$snapshot 里程碑=$milestoneText 评估=$evaluationText" -ForegroundColor DarkGray
            foreach ($command in (Get-WorkspaceArray $task.validation)) {
                Write-UIHost -English "      validate: $command" -Chinese "      验证: $command" -ForegroundColor DarkGray
            }
        }
    }
}

function Write-WorkspaceCheck {
    param(
        [string]$Level,
        [string]$Name,
        [string]$Detail = "",
        [string]$ChineseName = "",
        [string]$ChineseDetail = ""
    )

    $color = switch ($Level) {
        "OK" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "DarkGray" }
    }

    $enSuffix = if ([string]::IsNullOrWhiteSpace($Detail)) { "" } else { " $Detail" }
    $cnName = if ([string]::IsNullOrWhiteSpace($ChineseName)) { $Name } else { $ChineseName }
    $cnSuffix = if ([string]::IsNullOrWhiteSpace($ChineseDetail)) { $enSuffix } else { " $ChineseDetail" }
    
    Write-UIHost -English "  [$Level] $Name$enSuffix" -Chinese "  [$Level] $cnName$cnSuffix" -ForegroundColor $color
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

    Write-UIHost -English "Workspace create: $($Manifest.name)" -Chinese "工作区创建: $($Manifest.name)" -ForegroundColor Cyan
    if ($PlanOnly) {
        Write-UIHost -English "Plan only: no directories will be created, no projects cloned, no sync sessions changed, no runtimes started, no SSH connections opened, no snapshots created, no validation or evaluation commands run, and no Git commands run." -Chinese "仅计划：不会创建任何目录、不会 clone 任何项目、不会更改任何同步会话、不会启动任何运行时、不会打开 SSH 连接、不会创建快照、不会运行验证或评估命令、不会运行 Git 命令。" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "Create only: local project directories may be created. No projects will be cloned, no sync sessions changed, no runtimes started, no SSH connections opened, no snapshots created, no validation or evaluation commands run, and no Git commands run." -Chinese "仅创建：可能会创建本地项目目录。不会 clone 任何项目、不会更改同步会话、不会启动运行时、不会打开 SSH 连接、不会创建快照、不会运行验证或评估命令、不会运行 Git 命令。" -ForegroundColor DarkGray
    }

    $entries = Get-WorkspaceProjectCreateEntries -Manifest $Manifest
    $invalidEntries = @($entries | Where-Object { -not $_.Valid })
    $missingEntries = @($entries | Where-Object { $_.Valid -and -not $_.Exists })
    $existingEntries = @($entries | Where-Object { $_.Valid -and $_.Exists })

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Project directories:" -Chinese "项目目录:" -ForegroundColor Yellow
    if ($entries.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "projects" -Detail "(none configured)"
    }

    foreach ($entry in $entries) {
        Write-WorkspaceCheck -Level $entry.Level -Name $entry.ProjectName -Detail "(runtime: $($entry.RuntimeName); status: $($entry.Status); path: $(if ($entry.FullPath) { $entry.FullPath } else { 'not available' }); detail: $($entry.Detail))"
        if ($entry.Valid) {
            Write-UIHost -English "       open:      adp workspace open $($entry.ProjectName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       打开:      adp workspace open $($entry.ProjectName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
            Write-UIHost -English "       lifecycle: adp workspace project $($entry.ProjectName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       生命周期:  adp workspace project $($entry.ProjectName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        }
    }

    if ($invalidEntries.Count -gt 0) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Create blocked: fix invalid project paths before creating workspace directories. No directories were created." -Chinese "创建被阻止：在创建工作区目录之前，请先修复无效的项目路径。未创建任何目录。" -ForegroundColor Red
        exit 1
    }

    if ($PlanOnly) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Plan summary: $($missingEntries.Count) directories would be created; $($existingEntries.Count) already exist." -Chinese "计划摘要：将创建 $($missingEntries.Count) 个目录；$($existingEntries.Count) 个已存在。" -ForegroundColor Yellow
        return
    }

    $created = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $missingEntries) {
        New-Item -ItemType Directory -Path $entry.FullPath -Force | Out-Null
        $created.Add($entry.FullPath) | Out-Null
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Create summary:" -Chinese "创建摘要:" -ForegroundColor Yellow
    Write-UIHost -English "  created: $(if ($created.Count -gt 0) { $created.Count } else { 0 })" -Chinese "  已创建: $(if ($created.Count -gt 0) { $created.Count } else { 0 })" -ForegroundColor DarkGray
    foreach ($path in $created) {
        Write-UIHost -English "    $path" -Chinese "    $path" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  already existed: $($existingEntries.Count)" -Chinese "  已存在: $($existingEntries.Count)" -ForegroundColor DarkGray
    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Next:" -Chinese "下一步:" -ForegroundColor Yellow
    Write-UIHost -English "  adp workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adp workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adp workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
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

    Write-UIHost -English "Workspace readiness: $($Manifest.name)" -Chinese "工作区就绪状态: $($Manifest.name)" -ForegroundColor Cyan
    Write-UIHost -English "Status only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, and no validation or evaluation commands will be run." -Chinese "仅状态查看：不会 clone 任何项目、不会更改任何同步会话、不会创建任何快照、不会运行任何验证或评估命令。" -ForegroundColor DarkGray

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
    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Manifest:" -Chinese "清单:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "manifest loaded" -ChineseName "清单已加载" -Detail "(projects: $projectCount, tasks: $taskCount, milestones: $milestoneCount, evaluations: $evaluationCount)"
    Write-WorkspaceCheck -Level "INFO" -Name "local state" -ChineseName "本地状态" -Detail "($resolvedStatePath)"
    if ($Manifest.version) {
        Write-WorkspaceCheck -Level "OK" -Name "manifest version" -ChineseName "清单版本" -Detail "($($Manifest.version))"
    } else {
        Write-WorkspaceCheck -Level "WARN" -Name "manifest version" -ChineseName "清单版本" -Detail "(missing)" -ChineseDetail "(缺失)"
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Projects:" -Chinese "项目:" -ForegroundColor Yellow
    if ($projectCount -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "projects" -ChineseName "项目" -Detail "(none configured)" -ChineseDetail "(未配置)"
    }

    foreach ($project in $projects) {
        $projectName = if ($project.name) { $project.name } else { "(unnamed)" }
        Write-UIHost -English "  - $projectName" -Chinese "  - $projectName" -ForegroundColor DarkGray

        if (-not $project.path) {
            Write-WorkspaceCheck -Level "FAIL" -Name "project path" -ChineseName "项目路径" -Detail "(missing)" -ChineseDetail "(缺失)"
        } else {
            $projectPath = Resolve-ProjectWorkspacePath -Project $project
            $pathLevel = if (Test-Path -LiteralPath $projectPath) { "OK" } else { "WARN" }
            $pathStatus = if ($pathLevel -eq "OK") { "exists" } else { "missing" }
            Write-WorkspaceCheck -Level $pathLevel -Name "project path" -ChineseName "项目路径" -Detail ("({0}: {1})" -f $pathStatus, $projectPath)
            $devContainerStatus = Get-WorkspaceDevContainerStatus -ProjectPath $projectPath
            Write-WorkspaceCheck -Level $devContainerStatus.Level -Name "devcontainer" -ChineseName "devcontainer" -Detail "($($devContainerStatus.Status): $($devContainerStatus.Detail))"
            $syncHygieneStatus = Get-WorkspaceSyncHygieneStatus -Project $project -ProjectPath $projectPath
            Write-WorkspaceCheck -Level $syncHygieneStatus.Level -Name "sync hygiene" -ChineseName "同步卫生" -Detail "($($syncHygieneStatus.Status)$(if ($syncHygieneStatus.Detail) { ': ' + $syncHygieneStatus.Detail }))"
        }

        if (-not $project.runtime) {
            Write-WorkspaceCheck -Level "FAIL" -Name "runtime" -ChineseName "运行时" -Detail "(missing)" -ChineseDetail "(缺失)"
        } else {
            $runtimeStatus = Get-WorkspaceRuntimeStatus -RuntimeName $project.runtime
            Write-WorkspaceCheck -Level $runtimeStatus.Level -Name "runtime $($project.runtime)" -ChineseName "运行时 $($project.runtime)" -Detail "($($runtimeStatus.Status): $($runtimeStatus.Detail))"
        }

        $syncExpected = ($null -ne $project.sync -and [bool]$project.sync)
        $syncStatus = Get-WorkspaceSyncStatus -RuntimeName $project.runtime -Expected $syncExpected
        Write-WorkspaceCheck -Level $syncStatus.Level -Name "sync" -ChineseName "同步" -Detail "($($syncStatus.Status)$(if ($syncStatus.Detail) { ': ' + $syncStatus.Detail }))"

        $validationCommands = Get-WorkspaceArray $project.validation
        if ($validationCommands.Count -gt 0) {
            Write-WorkspaceCheck -Level "OK" -Name "validation commands" -ChineseName "验证命令" -Detail "($($validationCommands.Count) configured)" -ChineseDetail "($($validationCommands.Count) 已配置)"
            foreach ($command in $validationCommands) {
                Write-UIHost -English "        $command" -Chinese "        $command" -ForegroundColor DarkGray
            }
        } else {
            Write-WorkspaceCheck -Level "WARN" -Name "validation commands" -ChineseName "验证命令" -Detail "(none configured)" -ChineseDetail "(未配置)"
        }
    }

    if ($milestoneCount -gt 0) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Milestones:" -Chinese "里程碑:" -ForegroundColor Yellow
        foreach ($milestone in $milestones) {
            $name = if ($milestone.name) { [string]$milestone.name } else { "(unnamed)" }
            $status = Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $milestone
            Write-UIHost -English "  - $name" -Chinese "  - $name" -ForegroundColor DarkGray
            Write-WorkspaceCheck -Level $status.Level -Name "checkpoint" -ChineseName "检查点" -Detail "(runtime: $($status.RuntimeName); snapshot: $($status.SnapshotName); tasks: $($status.TaskNames.Count))" -ChineseDetail "(运行时: $($status.RuntimeName); 快照: $($status.SnapshotName); 任务数: $($status.TaskNames.Count))"
            Write-WorkspaceCheck -Level $status.SnapshotNaming.Level -Name "snapshot naming" -ChineseName "快照命名" -Detail "($($status.SnapshotNaming.Status): $($status.SnapshotNaming.Detail))"
            Write-WorkspaceCheck -Level $status.SnapshotStatus.Level -Name "snapshot" -ChineseName "快照" -Detail "($($status.SnapshotStatus.Status)$(if ($status.SnapshotStatus.Detail) { ': ' + $status.SnapshotStatus.Detail }))"
            Write-UIHost -English "      linked tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' })" -Chinese "      关联任务: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { '无' })" -ForegroundColor DarkGray
        }
    }

    if ($evaluationCount -gt 0) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Evaluations:" -Chinese "评估:" -ForegroundColor Yellow
        Write-UIHost -English "  Evaluation hooks are plan-only here; no evaluation commands will be run." -Chinese "  评估钩子仅计划模式：不会运行任何评估命令。" -ForegroundColor DarkGray
        foreach ($evaluation in $evaluations) {
            $status = Get-WorkspaceEvaluationStatus -Manifest $Manifest -Evaluation $evaluation
            Write-UIHost -English "  - $($status.Name)" -Chinese "  - $($status.Name)" -ForegroundColor DarkGray
            Write-WorkspaceCheck -Level $status.Level -Name "evaluation plan" -ChineseName "评估计划" -Detail "(readiness: $($status.Readiness); runtime: $($status.RuntimeName); project: $($status.ProjectName); cadence: $($status.Cadence); tasks: $($status.TaskNames.Count); metrics: $($status.Metrics.Count); commands: $($status.Commands.Count))" -ChineseDetail "(就绪状态: $($status.Readiness); 运行时: $($status.RuntimeName); 项目: $($status.ProjectName); 节奏: $($status.Cadence); 任务数: $($status.TaskNames.Count); 指标: $($status.Metrics.Count); 命令: $($status.Commands.Count))"
            Write-UIHost -English "      linked tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' })" -Chinese "      关联任务: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { '无' })" -ForegroundColor DarkGray
            Write-UIHost -English "      blockers: $(if ($status.Blockers.Count -gt 0) { $status.Blockers -join ', ' } else { 'none' })" -Chinese "      阻塞项: $(if ($status.Blockers.Count -gt 0) { $status.Blockers -join ', ' } else { '无' })" -ForegroundColor DarkGray
        }
    }

    if ($taskCount -gt 0) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Tasks:" -Chinese "任务:" -ForegroundColor Yellow
        foreach ($task in $tasks) {
            $taskName = if ($task.name) { $task.name } else { "(unnamed)" }
            Write-UIHost -English "  - $taskName" -Chinese "  - $taskName" -ForegroundColor DarkGray
            $taskMilestones = Get-WorkspaceTaskMilestones -Manifest $Manifest -Task $task
            if ($taskMilestones.Count -gt 0) {
                $taskMilestoneNames = @($taskMilestones | ForEach-Object { if ($_.name) { [string]$_.name } })
                Write-WorkspaceCheck -Level "INFO" -Name "milestone" -ChineseName "里程碑" -Detail "($($taskMilestoneNames -join ', '))"
            }
            $taskEvaluations = Get-WorkspaceTaskEvaluations -Manifest $Manifest -Task $task
            if ($taskEvaluations.Count -gt 0) {
                $taskEvaluationNames = @($taskEvaluations | ForEach-Object { if ($_.name) { [string]$_.name } })
                Write-WorkspaceCheck -Level "INFO" -Name "evaluation" -ChineseName "评估" -Detail "($($taskEvaluationNames -join ', '))"
            }
            $risk = Get-WorkspaceTaskRisk -Task $task
            $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $task
            Write-WorkspaceCheck -Level "INFO" -Name "risk" -ChineseName "风险" -Detail "($risk; requires snapshot: $requiresSnapshot)" -ChineseDetail "($risk; 需要快照: $requiresSnapshot)"
            $snapshotNaming = Get-WorkspaceSnapshotNamingStatus -Task $task
            Write-WorkspaceCheck -Level $snapshotNaming.Level -Name "snapshot naming" -ChineseName "快照命名" -Detail "($($snapshotNaming.Status): $($snapshotNaming.Detail))"
            $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $task.runtime -SnapshotName $task.snapshot
            Write-WorkspaceCheck -Level $snapshotStatus.Level -Name "snapshot" -ChineseName "快照" -Detail "($($snapshotStatus.Status)$(if ($snapshotStatus.Detail) { ': ' + $snapshotStatus.Detail }))"
            $recordedState = Get-WorkspaceTaskState -State $state -TaskName $taskName
            $snapshotGate = Get-WorkspaceSnapshotGate -Task $task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
            Write-WorkspaceCheck -Level $snapshotGate.Level -Name "snapshot-first gate" -ChineseName "快照优先门禁" -Detail "($($snapshotGate.Status): $($snapshotGate.Detail))"

            $validationCommands = Get-WorkspaceArray $task.validation
            if ($validationCommands.Count -gt 0) {
                Write-WorkspaceCheck -Level "OK" -Name "task validation" -ChineseName "任务验证" -Detail "($($validationCommands.Count) configured)" -ChineseDetail "($($validationCommands.Count) 已配置)"
            } else {
                Write-WorkspaceCheck -Level "WARN" -Name "task validation" -ChineseName "任务验证" -Detail "(none configured)" -ChineseDetail "(未配置)"
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

    Write-UIHost -English "Workspace dashboard: $($Manifest.name)" -Chinese "工作区仪表盘: $($Manifest.name)" -ForegroundColor Cyan
    Write-UIHost -English "Dashboard only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation or evaluation commands will be run, and no Git commands will be run." -Chinese "仅仪表盘查看：不会 clone 任何项目、不会更改任何同步会话、不会创建任何快照、不会运行任何验证或评估命令、也不会运行任何 Git 命令。" -ForegroundColor DarkGray

    $projects = Get-WorkspaceArray $Manifest.projects
    $tasks = Get-WorkspaceArray $Manifest.tasks
    $milestones = Get-WorkspaceMilestones -Manifest $Manifest
    $evaluations = Get-WorkspaceEvaluations -Manifest $Manifest
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Overview:" -Chinese "概览:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "manifest" -ChineseName "清单" -Detail "(projects: $($projects.Count), tasks: $($tasks.Count), milestones: $($milestones.Count), evaluations: $($evaluations.Count), path: $ManifestPath)"
    Write-WorkspaceCheck -Level "INFO" -Name "state" -ChineseName "状态" -Detail "(path: $resolvedStatePath)"

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Project readiness:" -Chinese "项目就绪状态:" -ForegroundColor Yellow
    if ($projects.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "projects" -ChineseName "项目" -Detail "(none configured)" -ChineseDetail "(未配置)"
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Milestone checkpoints:" -Chinese "里程碑检查点:" -ForegroundColor Yellow
    if ($milestones.Count -eq 0) {
        Write-WorkspaceCheck -Level "INFO" -Name "milestones" -ChineseName "里程碑" -Detail "(none configured)" -ChineseDetail "(未配置)"
    }

    foreach ($milestone in $milestones) {
        $name = if ($milestone.name) { [string]$milestone.name } else { "(unnamed)" }
        $status = Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $milestone
        Write-WorkspaceCheck -Level $status.Level -Name $name -Detail "(runtime: $($status.RuntimeName); snapshot: $($status.SnapshotName); snapshot naming: $($status.SnapshotNaming.Status); snapshot: $($status.SnapshotStatus.Status); tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' }))"
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Evaluation hooks:" -Chinese "评估钩子:" -ForegroundColor Yellow
    if ($evaluations.Count -eq 0) {
        Write-WorkspaceCheck -Level "INFO" -Name "evaluations" -ChineseName "评估" -Detail "(none configured)" -ChineseDetail "(未配置)"
    }

    foreach ($evaluation in $evaluations) {
        $status = Get-WorkspaceEvaluationStatus -Manifest $Manifest -Evaluation $evaluation
        Write-WorkspaceCheck -Level $status.Level -Name $status.Name -Detail "(readiness: $($status.Readiness); runtime: $($status.RuntimeName); project: $($status.ProjectName); metrics: $($status.Metrics.Count); commands: $($status.Commands.Count); tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' }))"
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Task lifecycle:" -Chinese "任务生命周期:" -ForegroundColor Yellow
    if ($tasks.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "tasks" -ChineseName "任务" -Detail "(none configured)" -ChineseDetail "(未配置)"
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
        Write-UIHost -English "      prepare: adp workspace task prepare $taskName -ManifestPath $ManifestPath" -Chinese "      准备: adp workspace task prepare $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "      run:     adp workspace task run $taskName -ManifestPath $ManifestPath" -Chinese "      运行:   adp workspace task run $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "      review:  adp workspace task review $taskName -ManifestPath $ManifestPath" -Chinese "      审查:   adp workspace task review $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Release handoff summary:" -Chinese "发布交接摘要:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $highestLevel -Name "handoff" -ChineseName "交接" -Detail "(handoff: $handoffState; tasks: $total; milestones linked: $milestoned; validation passed: $passed; failed: $failed; missing: $missing; snapshot blocked: $snapshotBlocked; review ready: $reviewReady; commit ready: $commitReady; owned: $owned; cadence set: $cadenced; overdue: $overdue; due soon: $dueSoon)" -ChineseDetail "(状态: $handoffState; 任务: $total; 里程碑关联: $milestoned; 验证通过: $passed; 失败: $failed; 缺失: $missing; 快照阻塞: $snapshotBlocked; 审查就绪: $reviewReady; 提交就绪: $commitReady; 有负责人: $owned; 有节奏: $cadenced; 逾期: $overdue; 即将到期: $dueSoon)"
    Write-UIHost -English "     blocked tasks: $(if ($blockedTasks.Count -gt 0) { $blockedTasks -join ', ' } else { 'none' })" -Chinese "     阻塞任务: $(if ($blockedTasks.Count -gt 0) { $blockedTasks -join ', ' } else { '无' })" -ForegroundColor DarkGray
    Write-UIHost -English "     ready for review: $(if ($reviewTasks.Count -gt 0) { $reviewTasks -join ', ' } else { 'none' })" -Chinese "     审查就绪: $(if ($reviewTasks.Count -gt 0) { $reviewTasks -join ', ' } else { '无' })" -ForegroundColor DarkGray
    Write-UIHost -English "     ready to commit: $(if ($commitTasks.Count -gt 0) { $commitTasks -join ', ' } else { 'none' })" -Chinese "     提交就绪: $(if ($commitTasks.Count -gt 0) { $commitTasks -join ', ' } else { '无' })" -ForegroundColor DarkGray
    Write-UIHost -English "     owner gaps: $(if ($ownerGaps.Count -gt 0) { $ownerGaps -join ', ' } else { 'none' })" -Chinese "     负责人缺口: $(if ($ownerGaps.Count -gt 0) { $ownerGaps -join ', ' } else { '无' })" -ForegroundColor DarkGray
    Write-UIHost -English "     cadence gaps: $(if ($cadenceGaps.Count -gt 0) { $cadenceGaps -join ', ' } else { 'none' })" -Chinese "     节奏缺口: $(if ($cadenceGaps.Count -gt 0) { $cadenceGaps -join ', ' } else { '无' })" -ForegroundColor DarkGray
    Write-UIHost -English "     due attention: $(if ($dueTasks.Count -gt 0) { $dueTasks -join ', ' } else { 'none' })" -Chinese "     需关注: $(if ($dueTasks.Count -gt 0) { $dueTasks -join ', ' } else { '无' })" -ForegroundColor DarkGray
    Write-UIHost -English "     release gate: $handoffState" -Chinese "     发布门控: $handoffState" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Governance loop:" -Chinese "治理循环:" -ForegroundColor Yellow
    Write-UIHost -English "     owner queues:" -Chinese "     负责人队列:" -ForegroundColor DarkGray
    foreach ($group in $ownerGroups) {
        $tasks = @($group.Group | ForEach-Object { $_.TaskName })
        Write-UIHost -English "       $($group.Name): $($tasks -join ', ')" -Chinese "       $($group.Name): $($tasks -join ', ')" -ForegroundColor DarkGray
    }

    Write-UIHost -English "     review cadence:" -Chinese "     审查节奏:" -ForegroundColor DarkGray
    foreach ($group in $cadenceGroups) {
        $tasks = @($group.Group | ForEach-Object { $_.TaskName })
        Write-UIHost -English "       $($group.Name): $($tasks -join ', ')" -Chinese "       $($group.Name): $($tasks -join ', ')" -ForegroundColor DarkGray
    }

    Write-UIHost -English "     attention queue: $(if ($attentionTasks.Count -gt 0) { $attentionTasks -join '; ' } else { 'none' })" -Chinese "     关注队列: $(if ($attentionTasks.Count -gt 0) { $attentionTasks -join '; ' } else { '无' })" -ForegroundColor DarkGray
}

function Write-WorkspaceDecisionQueues {
    param([object[]]$Items)

    $actionGroups = @($Items | Group-Object -Property Action | Sort-Object Name)
    $releaseGroups = @($Items | Group-Object -Property ReleaseReadiness | Sort-Object Name)
    $milestoneGroups = @($Items | Where-Object { $_.MilestoneText -ne "not set" } | Group-Object -Property MilestoneText | Sort-Object Name)

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Decision queues:" -Chinese "决策队列:" -ForegroundColor Yellow
    Write-UIHost -English "     actions:" -Chinese "     操作:" -ForegroundColor DarkGray
    foreach ($group in $actionGroups) {
        $tasks = @($group.Group | ForEach-Object { $_.TaskName })
        Write-UIHost -English "       $($group.Name): $($tasks -join ', ')" -Chinese "       $($group.Name): $($tasks -join ', ')" -ForegroundColor DarkGray
    }

    Write-UIHost -English "     release readiness:" -Chinese "     发布就绪:" -ForegroundColor DarkGray
    foreach ($group in $releaseGroups) {
        $tasks = @($group.Group | ForEach-Object { $_.TaskName })
        Write-UIHost -English "       $($group.Name): $($tasks -join ', ')" -Chinese "       $($group.Name): $($tasks -join ', ')" -ForegroundColor DarkGray
    }

    Write-UIHost -English "     milestones:" -Chinese "     里程碑:" -ForegroundColor DarkGray
    if ($milestoneGroups.Count -eq 0) {
        Write-UIHost -English "       none: no milestone-linked tasks" -Chinese "       无: 没有里程碑关联任务" -ForegroundColor DarkGray
    }
    foreach ($group in $milestoneGroups) {
        $tasks = @($group.Group | ForEach-Object { $_.TaskName })
        Write-UIHost -English "       $($group.Name): $($tasks -join ', ')" -Chinese "       $($group.Name): $($tasks -join ', ')" -ForegroundColor DarkGray
    }
}

function Write-WorkspaceMilestoneCheckpoints {
    param(
        [object]$Manifest,
        [object[]]$Milestones
    )

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Milestone checkpoints:" -Chinese "里程碑检查点:" -ForegroundColor Yellow
    if ($Milestones.Count -eq 0) {
        Write-UIHost -English "     milestones: none configured" -Chinese "     里程碑: 未配置" -ForegroundColor DarkGray
        return
    }

    foreach ($milestone in $Milestones) {
        $status = Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $milestone
        Write-WorkspaceCheck -Level $status.Level -Name $status.Name -ChineseName $status.Name -Detail "(runtime: $($status.RuntimeName); snapshot: $($status.SnapshotName); snapshot: $($status.SnapshotStatus.Status); naming: $($status.SnapshotNaming.Status); tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' }))" -ChineseDetail "(运行时: $($status.RuntimeName); 快照: $($status.SnapshotName); 快照: $($status.SnapshotStatus.Status); 命名: $($status.SnapshotNaming.Status); 任务: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { '无' }))"
        if ($milestone.description) {
            Write-UIHost -English "       description: $($milestone.description)" -Chinese "       描述: $($milestone.description)" -ForegroundColor DarkGray
        }
        if ($status.RuntimeName -ne "not configured") {
            Write-UIHost -English "       checkpoint command: adp snapshot create $($status.RuntimeName) $($status.SnapshotName)" -Chinese "       检查点命令: adp snapshot create $($status.RuntimeName) $($status.SnapshotName)" -ForegroundColor DarkGray
        } else {
            Write-UIHost -English "       checkpoint command: set milestones[].runtime or use tasks from a single runtime first" -Chinese "       检查点命令: 先设置 milestones[].runtime 或使用同一运行时的任务" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Milestone review rollup:" -Chinese "里程碑审查汇总:" -ForegroundColor Yellow
    if ($rollups.Count -eq 0) {
        Write-UIHost -English "     milestones: no milestone-linked tasks" -Chinese "     里程碑: 没有里程碑关联任务" -ForegroundColor DarkGray
        return
    }

    foreach ($rollup in $rollups) {
        Write-WorkspaceCheck -Level $rollup.Level -Name $rollup.Milestone -ChineseName $rollup.Milestone -Detail "(tasks: $($rollup.TaskCount); blocked: $($rollup.Blocked.Count); validation required: $($rollup.ValidationRequired.Count); review required: $($rollup.ReviewRequired.Count); ready to commit: $($rollup.ReadyToCommit.Count))" -ChineseDetail "(任务: $($rollup.TaskCount); 阻塞: $($rollup.Blocked.Count); 需验证: $($rollup.ValidationRequired.Count); 需审查: $($rollup.ReviewRequired.Count); 可提交: $($rollup.ReadyToCommit.Count))"
        Write-UIHost -English "       actions: $(if ($rollup.Actions.Count -gt 0) { $rollup.Actions -join '; ' } else { 'none' })" -Chinese "       操作: $(if ($rollup.Actions.Count -gt 0) { $rollup.Actions -join '; ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       release: $(if ($rollup.ReleaseStates.Count -gt 0) { $rollup.ReleaseStates -join '; ' } else { 'none' })" -Chinese "       发布: $(if ($rollup.ReleaseStates.Count -gt 0) { $rollup.ReleaseStates -join '; ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       blocked tasks: $(if ($rollup.Blocked.Count -gt 0) { $rollup.Blocked -join ', ' } else { 'none' })" -Chinese "       阻塞任务: $(if ($rollup.Blocked.Count -gt 0) { $rollup.Blocked -join ', ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       validation required: $(if ($rollup.ValidationRequired.Count -gt 0) { $rollup.ValidationRequired -join ', ' } else { 'none' })" -Chinese "       需验证: $(if ($rollup.ValidationRequired.Count -gt 0) { $rollup.ValidationRequired -join ', ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       review required: $(if ($rollup.ReviewRequired.Count -gt 0) { $rollup.ReviewRequired -join ', ' } else { 'none' })" -Chinese "       需审查: $(if ($rollup.ReviewRequired.Count -gt 0) { $rollup.ReviewRequired -join ', ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       ready to commit: $(if ($rollup.ReadyToCommit.Count -gt 0) { $rollup.ReadyToCommit -join ', ' } else { 'none' })" -Chinese "       可提交: $(if ($rollup.ReadyToCommit.Count -gt 0) { $rollup.ReadyToCommit -join ', ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       owners: $(if ($rollup.Owners.Count -gt 0) { $rollup.Owners -join ', ' } else { 'not set' })" -Chinese "       负责人: $(if ($rollup.Owners.Count -gt 0) { $rollup.Owners -join ', ' } else { '未设置' })" -ForegroundColor DarkGray
        Write-UIHost -English "       due attention: $(if ($rollup.DueAttention.Count -gt 0) { $rollup.DueAttention -join ', ' } else { 'none' })" -Chinese "       需关注: $(if ($rollup.DueAttention.Count -gt 0) { $rollup.DueAttention -join ', ' } else { '无' })" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Validation execution queue:" -Chinese "验证执行队列:" -ForegroundColor Yellow
    if ($queue.Count -eq 0) {
        Write-UIHost -English "     validation: no tasks configured" -Chinese "     验证: 没有配置任务" -ForegroundColor DarkGray
        return
    }

    foreach ($entry in $queue) {
        Write-WorkspaceCheck -Level $entry.Level -Name $entry.TaskName -ChineseName $entry.TaskName -Detail "(validation: $($entry.Validation); commands: $($entry.CommandCount); readiness: $($entry.Readiness))" -ChineseDetail "(验证: $($entry.Validation); 命令: $($entry.CommandCount); 就绪: $($entry.Readiness))"
        Write-UIHost -English "       blockers: $(if ($entry.Blockers.Count -gt 0) { $entry.Blockers -join ', ' } else { 'none' })" -Chinese "       阻塞: $(if ($entry.Blockers.Count -gt 0) { $entry.Blockers -join ', ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       plan: $($entry.PlanCommand)" -Chinese "       计划: $($entry.PlanCommand)" -ForegroundColor DarkGray
        Write-UIHost -English "       execute preview: $($entry.ExecutePreview)" -Chinese "       执行预览: $($entry.ExecutePreview)" -ForegroundColor DarkGray
        Write-UIHost -English "       execute: $($entry.ExecuteCommand)" -Chinese "       执行: $($entry.ExecuteCommand)" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Evaluation queue:" -Chinese "评估队列:" -ForegroundColor Yellow
    Write-UIHost -English "     Evaluation queue only: no evaluation commands will be run." -Chinese "     仅评估队列: 不会运行评估命令。" -ForegroundColor DarkGray
    if ($queue.Count -eq 0) {
        Write-UIHost -English "     evaluations: none configured" -Chinese "     评估: 未配置" -ForegroundColor DarkGray
        return
    }

    foreach ($entry in $queue) {
        Write-WorkspaceCheck -Level $entry.Level -Name $entry.Name -ChineseName $entry.Name -Detail "(readiness: $($entry.Readiness); runtime: $($entry.RuntimeName); project: $($entry.ProjectName); cadence: $($entry.Cadence); metrics: $($entry.Metrics.Count); commands: $($entry.Commands.Count); tasks: $(if ($entry.TaskNames.Count -gt 0) { $entry.TaskNames -join ', ' } else { 'none' }))" -ChineseDetail "(就绪: $($entry.Readiness); 运行时: $($entry.RuntimeName); 项目: $($entry.ProjectName); 节奏: $($entry.Cadence); 指标: $($entry.Metrics.Count); 命令: $($entry.Commands.Count); 任务: $(if ($entry.TaskNames.Count -gt 0) { $entry.TaskNames -join ', ' } else { '无' }))"
        Write-UIHost -English "       blockers: $(if ($entry.Blockers.Count -gt 0) { $entry.Blockers -join ', ' } else { 'none' })" -Chinese "       阻塞: $(if ($entry.Blockers.Count -gt 0) { $entry.Blockers -join ', ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       metrics: $(if ($entry.Metrics.Count -gt 0) { $entry.Metrics -join ', ' } else { 'none' })" -Chinese "       指标: $(if ($entry.Metrics.Count -gt 0) { $entry.Metrics -join ', ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       commands: $(if ($entry.Commands.Count -gt 0) { $entry.Commands -join '; ' } else { 'none' })" -Chinese "       命令: $(if ($entry.Commands.Count -gt 0) { $entry.Commands -join '; ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       evidence: $($entry.ReportCommand)" -Chinese "       证据: $($entry.ReportCommand)" -ForegroundColor DarkGray
    }
}

function Write-WorkspaceRecipes {
    param(
        [object]$Manifest,
        [string]$ManifestPath,
        [string]$StatePath
    )

    Write-UIHost -English "Workspace recipes: $($Manifest.name)" -Chinese "工作区食谱: $($Manifest.name)" -ForegroundColor Cyan
    Write-UIHost -English "Recipes only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation or evaluation commands will be run, no SSH connection will be opened, and no Git commands will be run." -Chinese "仅食谱: 不会克隆项目、不会更改同步会话、不会创建快照、不会运行验证或评估命令、不会打开 SSH 连接、不会运行 Git 命令。" -ForegroundColor DarkGray

    $projects = Get-WorkspaceArray $Manifest.projects
    $tasks = Get-WorkspaceArray $Manifest.tasks
    $milestones = Get-WorkspaceMilestones -Manifest $Manifest
    $evaluations = Get-WorkspaceEvaluations -Manifest $Manifest
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $reportItems = @($tasks | ForEach-Object { New-WorkspaceReportItem -Manifest $Manifest -Task $_ -State $state })

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Overview:" -Chinese "概览:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "manifest" -ChineseName "清单" -Detail "(projects: $($projects.Count), tasks: $($tasks.Count), milestones: $($milestones.Count), evaluations: $($evaluations.Count), path: $ManifestPath)" -ChineseDetail "(项目: $($projects.Count), 任务: $($tasks.Count), 里程碑: $($milestones.Count), 评估: $($evaluations.Count), 路径: $ManifestPath)"
    Write-WorkspaceCheck -Level "INFO" -Name "state" -ChineseName "状态" -Detail "(path: $resolvedStatePath)" -ChineseDetail "(路径: $resolvedStatePath)"
    Write-UIHost -English "     recipes are discovery and planning records; use explicit lifecycle commands when you choose to execute work." -Chinese "     食谱是发现和规划记录; 使用明确的生命周期命令来执行工作。" -ForegroundColor DarkGray

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Project recipes:" -Chinese "项目食谱:" -ForegroundColor Yellow
    if ($projects.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "projects" -ChineseName "项目" -Detail "(none configured)" -ChineseDetail "(未配置)"
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

        Write-WorkspaceCheck -Level $level -Name $projectName -ChineseName $projectName -Detail "(runtime: $runtimeName; sync: $(if ($syncExpected) { 'requested' } else { 'not requested' }); validation commands: $($validationCommands.Count); linked tasks: $($linkedTasks.Count); devcontainer: $($devContainerStatus.Status); sync hygiene: $($syncHygieneStatus.Status))" -ChineseDetail "(运行时: $runtimeName; 同步: $(if ($syncExpected) { '已请求' } else { '未请求' }); 验证命令: $($validationCommands.Count); 关联任务: $($linkedTasks.Count); devcontainer: $($devContainerStatus.Status); 同步卫生: $($syncHygieneStatus.Status))"
        Write-UIHost -English "       local path:  $(if ($localPath) { $localPath } else { 'not configured' })" -Chinese "       本地路径: $(if ($localPath) { $localPath } else { '未配置' })" -ForegroundColor DarkGray
        Write-UIHost -English "       remote path: $remotePath" -Chinese "       远程路径: $remotePath" -ForegroundColor DarkGray
        if ($validationCommands.Count -gt 0) {
            Write-UIHost -English "       validation recipe:" -Chinese "       验证食谱:" -ForegroundColor DarkGray
            foreach ($command in $validationCommands) {
                Write-UIHost -English "         - $command" -Chinese "         - $command" -ForegroundColor DarkGray
            }
        } else {
            Write-UIHost -English "       validation recipe: none configured" -Chinese "       验证食谱: 未配置" -ForegroundColor Yellow
        }
        Write-UIHost -English "       next: adp workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       下一步: adp workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-UIHost -English "       sync: adp workspace sync $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       同步: adp workspace sync $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-UIHost -English "       lifecycle: adp workspace project $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       生命周期: adp workspace project $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Task recipes:" -Chinese "任务食谱:" -ForegroundColor Yellow
    if ($reportItems.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "tasks" -ChineseName "任务" -Detail "(none configured)" -ChineseDetail "(未配置)"
    }

    foreach ($item in $reportItems) {
        $task = $item.Task
        $validationCommands = Get-WorkspaceArray $task.validation
        $evaluationText = if ($item.EvaluationText -ne "not set") { $item.EvaluationText } else { "none" }
        $milestoneText = if ($item.MilestoneText -ne "not set") { $item.MilestoneText } else { "none" }
        $level = if ($item.SnapshotBlocked -or $item.SyncHygieneBlocking) { "FAIL" } elseif ($validationCommands.Count -gt 0) { "WARN" } else { "WARN" }

        Write-WorkspaceCheck -Level $level -Name $item.TaskName -ChineseName $item.TaskName -Detail "(project: $($item.ProjectName); runtime: $($item.RuntimeName); risk: $($item.Risk); snapshot required: $($item.RequiresSnapshot); milestone: $milestoneText; evaluation: $evaluationText; action: $($item.Action); release: $($item.ReleaseReadiness))" -ChineseDetail "(项目: $($item.ProjectName); 运行时: $($item.RuntimeName); 风险: $($item.Risk); 快照必需: $($item.RequiresSnapshot); 里程碑: $milestoneText; 评估: $evaluationText; 操作: $($item.Action); 发布: $($item.ReleaseReadiness))"
        Write-UIHost -English "       snapshot: $($item.SnapshotName); gate: $($item.SnapshotGate.Status); naming: $($item.SnapshotNaming.Status)" -Chinese "       快照: $($item.SnapshotName); 门控: $($item.SnapshotGate.Status); 命名: $($item.SnapshotNaming.Status)" -ForegroundColor DarkGray
        Write-UIHost -English "       validation recipe: $($validationCommands.Count) command(s)" -Chinese "       验证食谱: $($validationCommands.Count) 条命令" -ForegroundColor DarkGray
        foreach ($command in $validationCommands) {
            Write-UIHost -English "         - $command" -Chinese "         - $command" -ForegroundColor DarkGray
        }
        Write-UIHost -English "       prepare: adp workspace task prepare $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       准备: adp workspace task prepare $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        if ($item.RequiresSnapshot) {
            if ($item.SnapshotName -ne "not configured") {
                Write-UIHost -English "       checkpoint: adp snapshot create $($item.RuntimeName) $($item.SnapshotName)" -Chinese "       检查点: adp snapshot create $($item.RuntimeName) $($item.SnapshotName)" -ForegroundColor DarkGray
            } else {
                Write-UIHost -English "       checkpoint: set tasks[].snapshot before creating a task checkpoint" -Chinese "       检查点: 在创建任务检查点之前设置 tasks[].snapshot" -ForegroundColor Yellow
            }
        }
        Write-UIHost -English "       validate plan: adp workspace task validate $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       验证计划: adp workspace task validate $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-UIHost -English "       execute preview: adp workspace task validate $($item.TaskName) -Execute -Plan -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       执行预览: adp workspace task validate $($item.TaskName) -Execute -Plan -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-UIHost -English "       review: adp workspace task review $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       审查: adp workspace task review $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Milestone recipes:" -Chinese "里程碑食谱:" -ForegroundColor Yellow
    if ($milestones.Count -eq 0) {
        Write-WorkspaceCheck -Level "INFO" -Name "milestones" -ChineseName "里程碑" -Detail "(none configured)" -ChineseDetail "(未配置)"
    }
    foreach ($milestone in $milestones) {
        $status = Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $milestone
        Write-WorkspaceCheck -Level $status.Level -Name $status.Name -ChineseName $status.Name -Detail "(runtime: $($status.RuntimeName); snapshot: $($status.SnapshotName); tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' }))" -ChineseDetail "(运行时: $($status.RuntimeName); 快照: $($status.SnapshotName); 任务: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { '无' }))"
        Write-UIHost -English "       checkpoint command: adp snapshot create $($status.RuntimeName) $($status.SnapshotName)" -Chinese "       检查点命令: adp snapshot create $($status.RuntimeName) $($status.SnapshotName)" -ForegroundColor DarkGray
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Evaluation recipes:" -Chinese "评估食谱:" -ForegroundColor Yellow
    Write-UIHost -English "     Evaluation hooks are plan-only; evaluation commands are listed for evidence and are not executed." -Chinese "     评估钩子仅用于规划; 评估命令仅为证据列出，不会执行。" -ForegroundColor DarkGray
    if ($evaluations.Count -eq 0) {
        Write-WorkspaceCheck -Level "INFO" -Name "evaluations" -ChineseName "评估" -Detail "(none configured)" -ChineseDetail "(未配置)"
    }
    foreach ($entry in (Get-WorkspaceEvaluationQueueItems -Manifest $Manifest -ManifestPath $ManifestPath)) {
        Write-WorkspaceCheck -Level $entry.Level -Name $entry.Name -ChineseName $entry.Name -Detail "(readiness: $($entry.Readiness); runtime: $($entry.RuntimeName); project: $($entry.ProjectName); cadence: $($entry.Cadence); metrics: $($entry.Metrics.Count); commands: $($entry.Commands.Count); tasks: $(if ($entry.TaskNames.Count -gt 0) { $entry.TaskNames -join ', ' } else { 'none' }))" -ChineseDetail "(就绪: $($entry.Readiness); 运行时: $($entry.RuntimeName); 项目: $($entry.ProjectName); 节奏: $($entry.Cadence); 指标: $($entry.Metrics.Count); 命令: $($entry.Commands.Count); 任务: $(if ($entry.TaskNames.Count -gt 0) { $entry.TaskNames -join ', ' } else { '无' }))"
        Write-UIHost -English "       metrics: $(if ($entry.Metrics.Count -gt 0) { $entry.Metrics -join ', ' } else { 'none' })" -Chinese "       指标: $(if ($entry.Metrics.Count -gt 0) { $entry.Metrics -join ', ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       commands: $(if ($entry.Commands.Count -gt 0) { $entry.Commands -join '; ' } else { 'none' })" -Chinese "       命令: $(if ($entry.Commands.Count -gt 0) { $entry.Commands -join '; ' } else { '无' })" -ForegroundColor DarkGray
        Write-UIHost -English "       evidence: $($entry.ReportCommand)" -Chinese "       证据: $($entry.ReportCommand)" -ForegroundColor DarkGray
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Evidence commands:" -Chinese "证据命令:" -ForegroundColor Yellow
    Write-UIHost -English "  adp workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adp workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace report -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adp workspace report -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace report -Markdown -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adp workspace report -Markdown -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Release decision policy:" -Chinese "发布决策策略:" -ForegroundColor Yellow
    Write-UIHost -English "     decision: $decision" -Chinese "     决策: $decision" -ForegroundColor DarkGray
    Write-UIHost -English "     blockers: $(if ($releaseBlocked.Count -gt 0) { $releaseBlocked -join ', ' } else { 'none' })" -Chinese "     阻塞: $(if ($releaseBlocked.Count -gt 0) { $releaseBlocked -join ', ' } else { '无' })" -ForegroundColor DarkGray
    Write-UIHost -English "     validation required: $(if ($validationRequired.Count -gt 0) { $validationRequired -join ', ' } else { 'none' })" -Chinese "     需验证: $(if ($validationRequired.Count -gt 0) { $validationRequired -join ', ' } else { '无' })" -ForegroundColor DarkGray
    Write-UIHost -English "     review required: $(if ($reviewRequired.Count -gt 0) { $reviewRequired -join ', ' } else { 'none' })" -Chinese "     需审查: $(if ($reviewRequired.Count -gt 0) { $reviewRequired -join ', ' } else { '无' })" -ForegroundColor DarkGray
    Write-UIHost -English "     release candidates: $(if ($releaseCandidates.Count -gt 0) { $releaseCandidates -join ', ' } else { 'none' })" -Chinese "     候选发布: $(if ($releaseCandidates.Count -gt 0) { $releaseCandidates -join ', ' } else { '无' })" -ForegroundColor DarkGray
    Write-UIHost -English "     governance gaps: $(if ($ownerGaps.Count -gt 0 -or $cadenceGaps.Count -gt 0) { (@($ownerGaps + $cadenceGaps) | Select-Object -Unique) -join ', ' } else { 'none' })" -Chinese "     治理缺口: $(if ($ownerGaps.Count -gt 0 -or $cadenceGaps.Count -gt 0) { (@($ownerGaps + $cadenceGaps) | Select-Object -Unique) -join ', ' } else { '无' })" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Stale-task remediation:" -Chinese "陈旧任务修复:" -ForegroundColor Yellow
    if ($staleTasks.Count -eq 0) {
        Write-UIHost -English "     queue: none" -Chinese "     队列: 无" -ForegroundColor DarkGray
        return
    }

    foreach ($item in $staleTasks) {
        $owner = if ($item.OwnerName -ne "not set") { $item.OwnerName } else { "assign owner" }
        $cadence = if ($item.ReviewCadence -ne "not set") { $item.ReviewCadence } else { "set cadence" }
        $timing = if ($item.DueStatus -in @("overdue", "due soon")) { "$($item.DueDate) ($($item.DueStatus))" } else { "not urgent" }
        Write-UIHost -English "     $($item.TaskName): owner=$owner; cadence=$cadence; timing=$timing; action=$($item.Action); release=$($item.ReleaseReadiness)" -Chinese "     $($item.TaskName): 负责人=$owner; 节奏=$cadence; 时间=$timing; 操作=$($item.Action); 发布=$($item.ReleaseReadiness)" -ForegroundColor DarkGray
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

    Write-UIHost -English "Workspace open: $projectName" -Chinese "工作区打开: $projectName" -ForegroundColor Cyan
    Write-UIHost -English "Open guide only: no shell, editor, SSH connection, sync session, runtime, or file will be changed." -Chinese "仅打开指南：不会更改 shell、编辑器、SSH 连接、同步会话、运行时或文件。" -ForegroundColor DarkGray

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Project:" -Chinese "项目:" -ForegroundColor Yellow
    Write-UIHost -English "  Name:        $projectName" -Chinese "  名称:        $projectName" -ForegroundColor DarkGray
    Write-UIHost -English "  Runtime:     $(if ($runtimeName) { $runtimeName } else { 'not configured' })" -Chinese "  运行时:      $(if ($runtimeName) { $runtimeName } else { '未配置' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Sync:        $(if ($syncExpected) { 'requested' } else { 'not requested' })" -Chinese "  同步:        $(if ($syncExpected) { '已请求' } else { '未请求' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Local path:  $(if ($localPath) { $localPath } else { 'not configured' })" -Chinese "  本地路径:    $(if ($localPath) { $localPath } else { '未配置' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Remote path: $remotePath" -Chinese "  远程路径:    $remotePath" -ForegroundColor DarkGray

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Readiness:" -Chinese "就绪状态:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $pathLevel -Name "local path" -Detail "($pathDetail)"
    Write-WorkspaceCheck -Level $runtimeStatus.Level -Name "runtime $runtimeName" -Detail "($($runtimeStatus.Status)$(if ($runtimeStatus.Detail) { ': ' + $runtimeStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncStatus.Level -Name "sync" -Detail "($($syncStatus.Status)$(if ($syncStatus.Detail) { ': ' + $syncStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncHygieneStatus.Level -Name "sync hygiene" -Detail "($($syncHygieneStatus.Status)$(if ($syncHygieneStatus.Detail) { ': ' + $syncHygieneStatus.Detail }))"
    Write-WorkspaceCheck -Level $devContainerStatus.Level -Name "devcontainer" -Detail "($($devContainerStatus.Status)$(if ($devContainerStatus.Detail) { ': ' + $devContainerStatus.Detail }))"

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Local commands:" -Chinese "本地命令:" -ForegroundColor Yellow
    if ($localPath) {
        Write-UIHost -English "  Set-Location -LiteralPath $(Quote-WorkspacePowerShellArgument $localPath)" -Chinese "  Set-Location -LiteralPath $(Quote-WorkspacePowerShellArgument $localPath)" -ForegroundColor DarkGray
        Write-UIHost -English "  git status --short" -Chinese "  git status --short" -ForegroundColor DarkGray
        Write-UIHost -English "  code $(Quote-WorkspacePowerShellArgument $localPath)" -Chinese "  code $(Quote-WorkspacePowerShellArgument $localPath)" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  Set projects[].path before opening this project locally." -Chinese "  在本地打开此项目之前，请先设置 projects[].path。" -ForegroundColor Yellow
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Runtime commands:" -Chinese "运行时命令:" -ForegroundColor Yellow
    if ($runtimeName -and (Test-RuntimeExists $runtimeName)) {
        $alias = "adp-os-adp-$runtimeName"
        Write-UIHost -English "  ssh $alias" -Chinese "  ssh $alias" -ForegroundColor DarkGray
        try {
            $sshTarget = Get-WorkspaceRuntimeSshTarget -RuntimeName $runtimeName
            Write-UIHost -English "  ssh -i $(Quote-WorkspacePowerShellArgument $sshTarget.KeyPath) -p $($sshTarget.Port) $($sshTarget.User)@$($sshTarget.Host)" -Chinese "  ssh -i $(Quote-WorkspacePowerShellArgument $sshTarget.KeyPath) -p $($sshTarget.Port) $($sshTarget.User)@$($sshTarget.Host)" -ForegroundColor DarkGray
        } catch {
            Write-UIHost -English "  SSH target unavailable: $_" -Chinese "  SSH 目标不可用: $_" -ForegroundColor Yellow
        }
        if ($remotePath -and $remotePath -notmatch '^unavailable:') {
            Write-UIHost -English "  cd $(Quote-PosixSingleArgument $remotePath)" -Chinese "  cd $(Quote-PosixSingleArgument $remotePath)" -ForegroundColor DarkGray
            Write-UIHost -English "  git status --short" -Chinese "  git status --short" -ForegroundColor DarkGray
        }
    } else {
        Write-UIHost -English "  Set a known projects[].runtime before opening this project in a runtime." -Chinese "  在运行时中打开此项目之前，请先设置已知的 projects[].runtime。" -ForegroundColor Yellow
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Next:" -Chinese "下一步:" -ForegroundColor Yellow
    Write-UIHost -English "  adp workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adp workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    if ($runtimeName) {
        Write-UIHost -English "  adp up $runtimeName -Plan" -Chinese "  adp up $runtimeName -Plan" -ForegroundColor DarkGray
        if ($syncExpected) {
            Write-UIHost -English "  adp sync start $runtimeName" -Chinese "  adp sync start $runtimeName" -ForegroundColor DarkGray
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

    Write-UIHost -English "Workspace sync: $projectName" -Chinese "工作区同步: $projectName" -ForegroundColor Cyan
    Write-UIHost -English "Sync guide only: no Mutagen session, runtime, SSH connection, directory, or file will be changed." -Chinese "仅同步指南：不会更改 Mutagen 会话、运行时、SSH 连接、目录或文件。" -ForegroundColor DarkGray

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Project:" -Chinese "项目:" -ForegroundColor Yellow
    Write-UIHost -English "  Name:        $projectName" -Chinese "  名称:        $projectName" -ForegroundColor DarkGray
    Write-UIHost -English "  Runtime:     $(if ($runtimeName) { $runtimeName } else { 'not configured' })" -Chinese "  运行时:      $(if ($runtimeName) { $runtimeName } else { '未配置' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Sync intent: $(if ($syncExpected) { 'requested' } else { 'not requested' })" -Chinese "  同步意图:    $(if ($syncExpected) { '已请求' } else { '未请求' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Local path:  $(if ($localPath) { $localPath } else { 'not configured' })" -Chinese "  本地路径:    $(if ($localPath) { $localPath } else { '未配置' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Remote path: $remotePath" -Chinese "  远程路径:    $remotePath" -ForegroundColor DarkGray

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Readiness:" -Chinese "就绪状态:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $pathLevel -Name "local path" -Detail "($pathDetail)"
    Write-WorkspaceCheck -Level $runtimeStatus.Level -Name "runtime $runtimeName" -Detail "($($runtimeStatus.Status)$(if ($runtimeStatus.Detail) { ': ' + $runtimeStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncStatus.Level -Name "sync session" -Detail "($($syncStatus.Status)$(if ($syncStatus.Detail) { ': ' + $syncStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncHygieneStatus.Level -Name "sync hygiene" -Detail "($($syncHygieneStatus.Status)$(if ($syncHygieneStatus.Detail) { ': ' + $syncHygieneStatus.Detail }))"

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Runtime sync commands:" -Chinese "运行时同步命令:" -ForegroundColor Yellow
    if ($runtimeName -and (Test-RuntimeExists $runtimeName)) {
        Write-UIHost -English "  adp sync status" -Chinese "  adp sync status" -ForegroundColor DarkGray
        if ($syncExpected) {
            Write-UIHost -English "  adp sync start $runtimeName" -Chinese "  adp sync start $runtimeName" -ForegroundColor DarkGray
            Write-UIHost -English "  adp sync stop $runtimeName" -Chinese "  adp sync stop $runtimeName" -ForegroundColor DarkGray
        } else {
            Write-UIHost -English "  projects[].sync is false; set it to true before treating sync as expected for this project." -Chinese "  projects[].sync 为 false；在将同步视为该项目预期行为之前，请将其设为 true。" -ForegroundColor Yellow
            Write-UIHost -English "  adp sync start $runtimeName" -Chinese "  adp sync start $runtimeName" -ForegroundColor DarkGray
        }
    } else {
        Write-UIHost -English "  Set a known projects[].runtime before using runtime sync for this project." -Chinese "  在为此项目使用运行时同步之前，请先设置已知的 projects[].runtime。" -ForegroundColor Yellow
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Project commands:" -Chinese "项目命令:" -ForegroundColor Yellow
    Write-UIHost -English "  adp workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adp workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adp workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  adp workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adp workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
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

    Write-UIHost -English "Workspace project lifecycle: $projectName" -Chinese "工作区项目生命周期: $projectName" -ForegroundColor Cyan
    Write-UIHost -English "Lifecycle view only: no project, runtime, sync session, snapshot, validation command, Git command, or file will be changed." -Chinese "仅生命周期视图：不会更改项目、运行时、同步会话、快照、验证命令、Git 命令或文件。" -ForegroundColor DarkGray

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Project:" -Chinese "项目:" -ForegroundColor Yellow
    Write-UIHost -English "  Name:        $projectName" -Chinese "  名称:        $projectName" -ForegroundColor DarkGray
    Write-UIHost -English "  Runtime:     $(if ($runtimeName) { $runtimeName } else { 'not configured' })" -Chinese "  运行时:      $(if ($runtimeName) { $runtimeName } else { '未配置' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Sync intent: $(if ($syncExpected) { 'requested' } else { 'not requested' })" -Chinese "  同步意图:    $(if ($syncExpected) { '已请求' } else { '未请求' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Local path:  $(if ($localPath) { $localPath } else { 'not configured' })" -Chinese "  本地路径:    $(if ($localPath) { $localPath } else { '未配置' })" -ForegroundColor DarkGray
    Write-UIHost -English "  Remote path: $remotePath" -Chinese "  远程路径:    $remotePath" -ForegroundColor DarkGray
    Write-UIHost -English "  State path:  $resolvedStatePath" -Chinese "  状态路径:    $resolvedStatePath" -ForegroundColor DarkGray

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Lifecycle gates:" -Chinese "生命周期门控:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $pathLevel -Name "local path" -ChineseName "本地路径" -Detail "($pathDetail)"
    Write-WorkspaceCheck -Level $runtimeStatus.Level -Name "runtime $runtimeName" -ChineseName "运行时 $runtimeName" -Detail "($($runtimeStatus.Status)$(if ($runtimeStatus.Detail) { ': ' + $runtimeStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncStatus.Level -Name "sync session" -ChineseName "同步会话" -Detail "($($syncStatus.Status)$(if ($syncStatus.Detail) { ': ' + $syncStatus.Detail }))"
    Write-WorkspaceCheck -Level $syncHygieneStatus.Level -Name "sync hygiene" -ChineseName "同步卫生" -Detail "($($syncHygieneStatus.Status)$(if ($syncHygieneStatus.Detail) { ': ' + $syncHygieneStatus.Detail }))"
    Write-WorkspaceCheck -Level $devContainerStatus.Level -Name "devcontainer" -ChineseName "开发容器" -Detail "($($devContainerStatus.Status)$(if ($devContainerStatus.Detail) { ': ' + $devContainerStatus.Detail }))"
    if ($validationCommands.Count -gt 0) {
        Write-WorkspaceCheck -Level "OK" -Name "project validation" -ChineseName "项目验证" -Detail "($($validationCommands.Count) configured)" -ChineseDetail "($($validationCommands.Count) 条已配置)"
    } else {
        Write-WorkspaceCheck -Level "WARN" -Name "project validation" -ChineseName "项目验证" -Detail "(none configured)" -ChineseDetail "(未配置)"
    }
    if ($linkedTasks.Count -gt 0) {
        Write-WorkspaceCheck -Level "OK" -Name "linked tasks" -ChineseName "关联任务" -Detail "($($linkedTasks.Count) found)" -ChineseDetail "($($linkedTasks.Count) 个已找到)"
    } else {
        Write-WorkspaceCheck -Level "INFO" -Name "linked tasks" -ChineseName "关联任务" -Detail "(none found)" -ChineseDetail "(未找到)"
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Operational flow:" -Chinese "操作流程:" -ForegroundColor Yellow
    Write-UIHost -English "  1. Open:      adp workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  1. 打开:      adp workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    if ($runtimeName) {
        Write-UIHost -English "  2. Runtime:   adp up $runtimeName -Plan" -Chinese "  2. 运行时:    adp up $runtimeName -Plan" -ForegroundColor DarkGray
        Write-UIHost -English "  3. Sync:      adp workspace sync $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  3. 同步:      adp workspace sync $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  2. Runtime:   set projects[].runtime before planning runtime startup" -Chinese "  2. 运行时:    在规划运行时启动之前设置 projects[].runtime" -ForegroundColor Yellow
        Write-UIHost -English "  3. Sync:      set projects[].runtime before planning sync" -Chinese "  3. 同步:      在规划同步之前设置 projects[].runtime" -ForegroundColor Yellow
    }
    if ($validationCommands.Count -gt 0) {
        Write-UIHost -English "  4. Validate:  run declared project validation commands manually, or use task validation for linked tasks" -Chinese "  4. 验证:      手动运行已声明的项目验证命令，或对关联任务使用任务验证" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  4. Validate:  add projects[].validation or task validation commands" -Chinese "  4. 验证:      添加 projects[].validation 或任务验证命令" -ForegroundColor Yellow
    }
    Write-UIHost -English "  5. Evidence:  adp workspace report -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  5. 证据:      adp workspace report -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Project validation commands:" -Chinese "项目验证命令:" -ForegroundColor Yellow
    if ($validationCommands.Count -gt 0) {
        foreach ($command in $validationCommands) {
            Write-UIHost -English "  - $command" -Chinese "  - $command" -ForegroundColor DarkGray
        }
    } else {
        Write-UIHost -English "  No project validation commands configured." -Chinese "  未配置项目验证命令。" -ForegroundColor Yellow
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Linked tasks:" -Chinese "关联任务:" -ForegroundColor Yellow
    if ($linkedTasks.Count -eq 0) {
        Write-UIHost -English "  No tasks currently target this project." -Chinese "  当前没有任务目标为此项目。" -ForegroundColor DarkGray
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

        Write-UIHost -English "  - $taskName" -Chinese "  - $taskName" -ForegroundColor DarkGray
        Write-UIHost -English "      milestone: $milestoneText" -Chinese "      里程碑: $milestoneText" -ForegroundColor DarkGray
        Write-UIHost -English "      risk: $risk; snapshot required: $requiresSnapshot; snapshot naming: $($snapshotNaming.Status); snapshot gate: $($snapshotGate.Status)" -Chinese "      风险: $risk; 快照必需: $requiresSnapshot; 快照命名: $($snapshotNaming.Status); 快照门控: $($snapshotGate.Status)" -ForegroundColor DarkGray
        Write-UIHost -English "      validation: $validationState; commit: $($commitDecision.Verdict)" -Chinese "      验证: $validationState; 提交: $($commitDecision.Verdict)" -ForegroundColor DarkGray
        Write-UIHost -English "      prepare:  adp workspace task prepare $taskName -ManifestPath $ManifestPath" -Chinese "      准备:  adp workspace task prepare $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "      validate: adp workspace task validate $taskName -ManifestPath $ManifestPath" -Chinese "      验证: adp workspace task validate $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "      review:   adp workspace task review $taskName -ManifestPath $ManifestPath" -Chinese "      审查:   adp workspace task review $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
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

    Write-UIHost -English "Workspace report: $($Manifest.name)" -Chinese "工作区报告: $($Manifest.name)" -ForegroundColor Cyan
    Write-UIHost -English "Report only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation or evaluation commands will be run, and no Git commands will be run." -Chinese "仅报告: 不会克隆项目、不会更改同步会话、不会创建快照、不会运行验证或评估命令、不会运行 Git 命令。" -ForegroundColor DarkGray

    $tasks = Get-WorkspaceArray $Manifest.tasks
    $milestones = Get-WorkspaceMilestones -Manifest $Manifest
    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Sources:" -Chinese "来源:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "manifest" -ChineseName "清单" -Detail "($ManifestPath)" -ChineseDetail "($ManifestPath)"
    Write-WorkspaceCheck -Level "INFO" -Name "state" -ChineseName "状态" -Detail "($resolvedStatePath)" -ChineseDetail "($resolvedStatePath)"

    if ($tasks.Count -eq 0) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Task reports:" -Chinese "任务报告:" -ForegroundColor Yellow
        Write-WorkspaceCheck -Level "WARN" -Name "tasks" -ChineseName "任务" -Detail "(none configured)" -ChineseDetail "(未配置)"
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Task reports:" -Chinese "任务报告:" -ForegroundColor Yellow
    foreach ($item in $reportItems) {
        Write-WorkspaceCheck -Level $item.Level -Name $item.TaskName -ChineseName $item.TaskName -Detail "(state: $($item.RecordedTaskState); risk: $($item.Risk); snapshot required: $($item.RequiresSnapshot))" -ChineseDetail "(状态: $($item.RecordedTaskState); 风险: $($item.Risk); 快照必需: $($item.RequiresSnapshot))"
        Write-UIHost -English "     review bundle:" -Chinese "     审查包:" -ForegroundColor DarkGray
        Write-UIHost -English "       project: $($item.ProjectName)" -Chinese "       项目: $($item.ProjectName)" -ForegroundColor DarkGray
        Write-UIHost -English "       milestone: $($item.MilestoneText)" -Chinese "       里程碑: $($item.MilestoneText)" -ForegroundColor DarkGray
        Write-UIHost -English "       evaluation: $($item.EvaluationText)" -Chinese "       评估: $($item.EvaluationText)" -ForegroundColor DarkGray
        Write-UIHost -English "       sync hygiene: $($item.SyncHygiene.Status)$(if ($item.SyncHygiene.Detail) { ' - ' + $item.SyncHygiene.Detail })" -Chinese "       同步卫生: $($item.SyncHygiene.Status)$(if ($item.SyncHygiene.Detail) { ' - ' + $item.SyncHygiene.Detail })" -ForegroundColor DarkGray
        Write-UIHost -English "       owner: $($item.OwnerName)" -Chinese "       负责人: $($item.OwnerName)" -ForegroundColor DarkGray
        Write-UIHost -English "       review cadence: $($item.ReviewCadence)" -Chinese "       审查节奏: $($item.ReviewCadence)" -ForegroundColor DarkGray
        Write-UIHost -English "       due: $($item.DueDate) ($($item.DueStatus))" -Chinese "       截止: $($item.DueDate) ($($item.DueStatus))" -ForegroundColor DarkGray
        Write-UIHost -English "       runtime: $($item.RuntimeName)" -Chinese "       运行时: $($item.RuntimeName)" -ForegroundColor DarkGray
        Write-UIHost -English "       checkpoint: $($item.SnapshotName)" -Chinese "       检查点: $($item.SnapshotName)" -ForegroundColor DarkGray
        Write-UIHost -English "       snapshot gate: $($item.SnapshotGate.Status) - $($item.SnapshotGate.Detail)" -Chinese "       快照门控: $($item.SnapshotGate.Status) - $($item.SnapshotGate.Detail)" -ForegroundColor DarkGray
        Write-UIHost -English "       snapshot naming: $($item.SnapshotNaming.Status) - $($item.SnapshotNaming.Detail)" -Chinese "       快照命名: $($item.SnapshotNaming.Status) - $($item.SnapshotNaming.Detail)" -ForegroundColor DarkGray
        Write-UIHost -English "       validation commands: $($item.ValidationCommands.Count)" -Chinese "       验证命令: $($item.ValidationCommands.Count)" -ForegroundColor DarkGray
        Write-UIHost -English "       action: $($item.Action)" -Chinese "       操作: $($item.Action)" -ForegroundColor DarkGray
        Write-UIHost -English "       release readiness: $($item.ReleaseReadiness)" -Chinese "       发布就绪: $($item.ReleaseReadiness)" -ForegroundColor DarkGray
        Write-UIHost -English "     validation result: $($item.ValidationStateText)" -Chinese "     验证结果: $($item.ValidationStateText)" -ForegroundColor DarkGray
        Write-WorkspaceValidationDetailLines -RecordedState $item.RecordedState
        Write-UIHost -English "     review: $($item.ReviewDecision.Verdict) - $($item.ReviewDecision.Detail)" -Chinese "     审查: $($item.ReviewDecision.Verdict) - $($item.ReviewDecision.Detail)" -ForegroundColor DarkGray
        Write-UIHost -English "     rollback: $($item.RollbackState)" -Chinese "     回滚: $($item.RollbackState)" -ForegroundColor DarkGray
        Write-UIHost -English "     commit: $($item.CommitDecision.Verdict) - $($item.CommitDecision.Detail)" -Chinese "     提交: $($item.CommitDecision.Verdict) - $($item.CommitDecision.Detail)" -ForegroundColor DarkGray
        Write-UIHost -English "     next: $($item.CommitDecision.NextStep)" -Chinese "     下一步: $($item.CommitDecision.NextStep)" -ForegroundColor DarkGray
        Write-UIHost -English "     checklist:" -Chinese "     检查清单:" -ForegroundColor DarkGray
        Write-UIHost -English "       validation: confirm the latest recorded result matches the task output being reviewed" -Chinese "       验证: 确认最新记录的结果与正在审查的任务输出匹配" -ForegroundColor DarkGray
        Write-UIHost -English "       sync hygiene: confirm clean, covered, not requested, or intentionally reviewed before release" -Chinese "       同步卫生: 发布前确认干净、已覆盖、未请求 或 已审查" -ForegroundColor DarkGray
        Write-UIHost -English "       source: inspect git status, diff stat, and full diff in the target project" -Chinese "       源码: 在目标项目中检查 git status、diff stat 和完整 diff" -ForegroundColor DarkGray
        Write-UIHost -English "       rollback: confirm the VM checkpoint and Git rollback path before accepting risky work" -Chinese "       回滚: 在接受高风险工作前确认 VM 检查点和 Git 回滚路径" -ForegroundColor DarkGray
        Write-UIHost -English "       commit: commit only after sync hygiene, validation, and human review are all accepted" -Chinese "       提交: 仅在同步卫生、验证和人工审查全部通过后提交" -ForegroundColor DarkGray
        Write-UIHost -English "     handoff:" -Chinese "     交接:" -ForegroundColor DarkGray
        Write-UIHost -English "       review:   adp workspace task review $($item.TaskName) -ManifestPath $ManifestPath" -Chinese "       审查:   adp workspace task review $($item.TaskName) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "       rollback: adp workspace task rollback $($item.TaskName) -ManifestPath $ManifestPath" -Chinese "       回滚:   adp workspace task rollback $($item.TaskName) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "       commit:   adp workspace task commit $($item.TaskName) -ManifestPath $ManifestPath" -Chinese "       提交:   adp workspace task commit $($item.TaskName) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "       inspect:  git status --short; git diff --stat; git diff" -Chinese "       检查:   git status --short; git diff --stat; git diff" -ForegroundColor DarkGray
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

    $actionCn = switch ($Action) {
        "prepare"  { "准备" }
        "snapshot" { "快照" }
        "run"      { "运行" }
        "validate" { "验证" }
        "review"   { "审查" }
        "rollback" { "回滚" }
        "commit"   { "提交" }
        default    { $Action }
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Workspace task $Action`: $($Task.name)" -Chinese "工作区任务 $actionCn`: $($Task.name)" -ForegroundColor Cyan
    if ($ExplicitExecution) {
        Write-UIHost -English "Explicit execution mode. ADP-OS runs only the declared validation commands; it does not create snapshots, stage files, or commit changes." -Chinese "显式执行模式。ADP-OS 仅运行已声明的验证命令；不会创建快照、暂存文件或提交更改。" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "Task lifecycle output is plan-only. No VM, sync, snapshot, file, Git, or validation command will be changed or run." -Chinese "任务生命周期输出仅为规划。不会更改或运行任何 VM、同步、快照、文件、Git 或验证命令。" -ForegroundColor DarkGray
    }
    Write-UIHost -English "" -Chinese ""
}

function Write-TaskSummary {
    param(
        [object]$Manifest,
        [object]$Task
    )

    $runtime = if ($Task.runtime) { $Task.runtime } else { "not configured" }
    $runtimeCn = if ($Task.runtime) { $Task.runtime } else { "未配置" }
    $snapshot = if ($Task.snapshot) { $Task.snapshot } else { "not configured" }
    $snapshotCn = if ($Task.snapshot) { $Task.snapshot } else { "未配置" }
    $risk = Get-WorkspaceTaskRisk -Task $Task
    $requiresSnapshot = Test-WorkspaceTaskRequiresSnapshot -Task $Task
    $snapshotNaming = Get-WorkspaceSnapshotNamingStatus -Task $Task
    $taskMilestones = if ($Manifest) { Get-WorkspaceTaskMilestones -Manifest $Manifest -Task $Task } else { @() }
    $milestoneNames = @($taskMilestones | ForEach-Object { if ($_.name) { [string]$_.name } })
    $milestoneText = if ($milestoneNames.Count -gt 0) { $milestoneNames -join ', ' } else { "not set" }
    $milestoneTextCn = if ($milestoneNames.Count -gt 0) { $milestoneNames -join ', ' } else { "未设置" }

    Write-UIHost -English "Task:" -Chinese "任务:" -ForegroundColor Yellow
    Write-UIHost -English "  Name:      $($Task.name)" -Chinese "  名称:      $($Task.name)" -ForegroundColor DarkGray
    Write-UIHost -English "  Milestone: $milestoneText" -Chinese "  里程碑: $milestoneTextCn" -ForegroundColor DarkGray
    Write-UIHost -English "  Runtime:   $runtime" -Chinese "  运行时:   $runtimeCn" -ForegroundColor DarkGray
    Write-UIHost -English "  Risk:      $risk" -Chinese "  风险:      $risk" -ForegroundColor DarkGray
    Write-UIHost -English "  Snapshot required: $requiresSnapshot" -Chinese "  快照必需: $requiresSnapshot" -ForegroundColor DarkGray
    Write-UIHost -English "  Snapshot:  $snapshot" -Chinese "  快照:  $snapshotCn" -ForegroundColor DarkGray
    Write-UIHost -English "  Snapshot naming: $($snapshotNaming.Status) - $($snapshotNaming.Detail)" -Chinese "  快照命名: $($snapshotNaming.Status) - $($snapshotNaming.Detail)" -ForegroundColor DarkGray

    $validationCommands = Get-WorkspaceArray $Task.validation
    Write-UIHost -English "  Validation commands: $($validationCommands.Count)" -Chinese "  验证命令: $($validationCommands.Count)" -ForegroundColor DarkGray
    foreach ($command in $validationCommands) {
        Write-UIHost -English "    - $command" -Chinese "    - $command" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Preparation checklist:" -Chinese "准备清单:" -ForegroundColor Yellow
    Write-UIHost -English "  1. Check workspace readiness:" -Chinese "  1. 检查工作区就绪状态:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace status -ManifestPath $ManifestPath" -Chinese "     adp workspace status -ManifestPath $ManifestPath" -ForegroundColor DarkGray

    if ($Task.runtime) {
        Write-UIHost -English "  2. Preview runtime startup:" -Chinese "  2. 预览运行时启动:" -ForegroundColor DarkGray
        Write-UIHost -English "     adp up $($Task.runtime) -Plan" -Chinese "     adp up $($Task.runtime) -Plan" -ForegroundColor DarkGray
        Write-UIHost -English "  3. Confirm sync when the runtime is ready:" -Chinese "  3. 运行时就绪后确认同步:" -ForegroundColor DarkGray
        Write-UIHost -English "     adp sync start $($Task.runtime)" -Chinese "     adp sync start $($Task.runtime)" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  2. Add tasks[].runtime before preparing runtime and sync commands." -Chinese "  2. 在准备运行时和同步命令之前添加 tasks[].runtime。" -ForegroundColor DarkGray
    }

    if ($Task.snapshot -and $Task.runtime) {
        Write-UIHost -English "  4. Plan the checkpoint:" -Chinese "  4. 规划检查点:" -ForegroundColor DarkGray
        Write-UIHost -English "     adp workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adp workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    } else {
        $recommendedSnapshot = Get-WorkspaceRecommendedSnapshotName -Task $Task
        Write-UIHost -English "  4. Add tasks[].snapshot before planning checkpoint commands." -Chinese "  4. 在规划检查点命令之前添加 tasks[].snapshot。" -ForegroundColor DarkGray
        Write-UIHost -English "     Recommended: `"$recommendedSnapshot`"" -Chinese "     推荐: `"$recommendedSnapshot`"" -ForegroundColor DarkGray
    }

    Write-UIHost -English "  5. Review validation expectations:" -Chinese "  5. 审查验证预期:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
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
    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Checkpoint:" -Chinese "检查点:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level $snapshotNaming.Level -Name "snapshot naming" -ChineseName "快照命名" -Detail "($($snapshotNaming.Status): $($snapshotNaming.Detail))"
    Write-WorkspaceCheck -Level $snapshotStatus.Level -Name "snapshot" -ChineseName "快照" -Detail "($($snapshotStatus.Status)$(if ($snapshotStatus.Detail) { ': ' + $snapshotStatus.Detail }))"
    Write-WorkspaceCheck -Level $snapshotGate.Level -Name "snapshot-first gate" -ChineseName "快照优先门控" -Detail "($($snapshotGate.Status): $($snapshotGate.Detail))"
    Write-UIHost -English "  Local state: $resolvedStatePath" -Chinese "  本地状态: $resolvedStatePath" -ForegroundColor DarkGray

    if ($Task.runtime -and $Task.snapshot) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Explicit command to create the checkpoint when ready:" -Chinese "准备就绪后创建检查点的显式命令:" -ForegroundColor Yellow
        Write-UIHost -English "  adp snapshot create $($Task.runtime) $($Task.snapshot)" -Chinese "  adp snapshot create $($Task.runtime) $($Task.snapshot)" -ForegroundColor DarkGray
        Write-UIHost -English "  If the human reviewer intentionally accepts missing snapshot protection:" -Chinese "  如果人工审查者有意接受缺少快照保护:" -ForegroundColor Yellow
        Write-UIHost -English "  adp workspace task mark $($Task.name) checkpoint-waived" -Chinese "  adp workspace task mark $($Task.name) checkpoint-waived" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Add tasks[].runtime and tasks[].snapshot before creating a checkpoint." -Chinese "在创建检查点之前添加 tasks[].runtime 和 tasks[].snapshot。" -ForegroundColor Yellow
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
    Write-UIHost -English "" -Chinese ""
    $mode = if ($ExecuteValidation) { "Validation execution:" } else { "Validation plan:" }
    $modeCn = if ($ExecuteValidation) { "验证执行:" } else { "验证计划:" }
    Write-UIHost -English $mode -Chinese $modeCn -ForegroundColor Yellow
    if ($validationCommands.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "task validation" -ChineseName "任务验证" -Detail "(none configured)" -ChineseDetail "(未配置)"
        Write-UIHost -English "  Add tasks[].validation commands before using this task for review gates." -Chinese "  在使用此任务进行审查门控之前添加 tasks[].validation 命令。" -ForegroundColor DarkGray
        return
    }

    if (-not $ExecuteValidation) {
        $index = 1
        foreach ($command in $validationCommands) {
            Write-UIHost -English "  $index. $command" -Chinese "  $index. $command" -ForegroundColor DarkGray
            $index += 1
        }

        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "To execute validation explicitly:" -Chinese "显式执行验证:" -ForegroundColor Yellow
        Write-UIHost -English "  adp workspace task validate $($Task.name) -Execute -ManifestPath <manifest>" -Chinese "  adp workspace task validate $($Task.name) -Execute -ManifestPath <manifest>" -ForegroundColor DarkGray
        Write-UIHost -English "  Add -Plan to preview the remote SSH commands without running them." -Chinese "  添加 -Plan 来预览远程 SSH 命令而不实际运行它们。" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Readiness gate:" -Chinese "就绪门控:" -ForegroundColor Yellow
    Write-WorkspaceCheck -Level "OK" -Name "project" -ChineseName "项目" -Detail "($($project.name): $remotePath)" -ChineseDetail "($($project.name): $remotePath)"
    Write-WorkspaceCheck -Level $runtimeStatus.Level -Name "runtime $($Task.runtime)" -ChineseName "运行时 $($Task.runtime)" -Detail "($($runtimeStatus.Status): $($runtimeStatus.Detail))"
    Write-WorkspaceCheck -Level $syncStatus.Level -Name "sync" -ChineseName "同步" -Detail "($($syncStatus.Status)$(if ($syncStatus.Detail) { ': ' + $syncStatus.Detail }))"
    Write-WorkspaceCheck -Level $snapshotGate.Level -Name "snapshot-first gate" -ChineseName "快照优先门控" -Detail "($($snapshotGate.Status): $($snapshotGate.Detail))"
    Write-WorkspaceCheck -Level "OK" -Name "ssh target" -ChineseName "SSH 目标" -Detail "($($sshTarget.User)@$($sshTarget.Host):$($sshTarget.Port))"

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
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Plan only: validation commands will not be executed." -Chinese "仅规划: 验证命令不会被执行。" -ForegroundColor Cyan
    } else {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Executing declared validation commands. No packages, browsers, snapshots, Git staging, or commits are managed by ADP-OS beyond these commands." -Chinese "正在执行已声明的验证命令。ADP-OS 不会管理这些命令之外的包、浏览器、快照、Git 暂存或提交。" -ForegroundColor Yellow
    }

    $index = 1
    $startedAt = (Get-Date).ToUniversalTime().ToString("o")
    $commands = @($validationCommands | ForEach-Object { [string]$_ })
    foreach ($command in $validationCommands) {
        $remoteCommand = "cd $(Quote-PosixSingleArgument $remotePath) && $command"
        if ($PlanOnly) {
            Write-UIHost -English "  $index. ssh -i $($sshTarget.KeyPath) -p $($sshTarget.Port) $($sshTarget.User)@$($sshTarget.Host) $(Quote-PosixSingleArgument $remoteCommand)" -Chinese "  $index. ssh -i $($sshTarget.KeyPath) -p $($sshTarget.Port) $($sshTarget.User)@$($sshTarget.Host) $(Quote-PosixSingleArgument $remoteCommand)" -ForegroundColor DarkGray
        } else {
            Write-UIHost -English "" -Chinese ""
            Write-UIHost -English "[$index/$($validationCommands.Count)] $command" -Chinese "[$index/$($validationCommands.Count)] $command" -ForegroundColor Yellow
            Invoke-WorkspaceRemoteValidationCommand -SshTarget $sshTarget -RemoteCommand $remoteCommand
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                $completedAt = (Get-Date).ToUniversalTime().ToString("o")
                $validation = New-WorkspaceValidationResult -Task $Task -Project $project -RemotePath $remotePath -Status "failed" -StartedAt $startedAt -CompletedAt $completedAt -Commands $commands -ExitCode $exitCode -FailedCommand ([string]$command)
                $resolvedStatePath = Write-WorkspaceValidationResult -StatePath $StatePath -Task $Task -Validation $validation
                Write-UIHost -English "" -Chinese ""
                Write-UIHost -English "Validation result recorded: $resolvedStatePath" -Chinese "验证结果已记录: $resolvedStatePath" -ForegroundColor DarkGray
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
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Workspace validation complete: $($Task.name)" -Chinese "工作区验证完成: $($Task.name)" -ForegroundColor Green
        Write-UIHost -English "  Result recorded: $resolvedStatePath" -Chinese "  结果已记录: $resolvedStatePath" -ForegroundColor DarkGray
        Write-UIHost -English "  Review remains explicit; ADP-OS did not stage files or commit changes." -Chinese "  审查仍需显式进行; ADP-OS 未暂存文件或提交更改。" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Execution boundary:" -Chinese "执行边界:" -ForegroundColor Yellow
    Write-UIHost -English "  Manual execution only: this command does not start an agent, approve broad agent work, record task state, run validation, or make the task commit-ready." -Chinese "  仅手动执行: 此命令不会启动 agent、批准广泛的 agent 工作、记录任务状态、运行验证或使任务达到提交就绪状态。" -ForegroundColor DarkGray
    Write-UIHost -English "  1. Confirm readiness:" -Chinese "  1. 确认就绪状态:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace status -ManifestPath $ManifestPath" -Chinese "     adp workspace status -ManifestPath $ManifestPath" -ForegroundColor DarkGray

    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $recordedState = Get-WorkspaceTaskState -State $state -TaskName $Task.name
    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    $snapshotGate = Get-WorkspaceSnapshotGate -Task $Task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
    if ($Task.runtime -and $Task.snapshot) {
        Write-UIHost -English "  2. Snapshot-first gate before broad agent work:" -Chinese "  2. 广泛 agent 工作之前的快照优先门控:" -ForegroundColor DarkGray
        Write-UIHost -English "     adp workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adp workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        if ($snapshotGate.Blocking) {
            Write-UIHost -English "     BLOCKED: $($snapshotGate.Detail)" -Chinese "     已阻塞: $($snapshotGate.Detail)" -ForegroundColor Yellow
            Write-UIHost -English "     Do not start broad agent work until this gate is ready or explicitly waived in local ADP-OS state." -Chinese "     在此门控就绪或在本地 ADP-OS 状态中显式豁免之前，不要开始广泛的 agent 工作。" -ForegroundColor Yellow
            Write-UIHost -English "     Waive only after human acceptance of the missing checkpoint risk:" -Chinese "     仅在人工接受缺少检查点风险后才豁免:" -ForegroundColor Yellow
            Write-UIHost -English "     adp workspace task mark $($Task.name) checkpoint-waived -ManifestPath $ManifestPath" -Chinese "     adp workspace task mark $($Task.name) checkpoint-waived -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        } else {
            Write-UIHost -English "     READY: $($snapshotGate.Detail)" -Chinese "     就绪: $($snapshotGate.Detail)" -ForegroundColor DarkGray
        }
        Write-UIHost -English "     adp workspace task mark $($Task.name) checkpointed" -Chinese "     adp workspace task mark $($Task.name) checkpointed" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  2. Add tasks[].runtime and tasks[].snapshot before using rollback-capable agent task execution." -Chinese "  2. 在使用可回滚的 agent 任务执行之前添加 tasks[].runtime 和 tasks[].snapshot。" -ForegroundColor DarkGray
    }

    if ($Task.runtime) {
        Write-UIHost -English "  3. Enter or target the runtime explicitly:" -Chinese "  3. 显式进入或目标运行时:" -ForegroundColor DarkGray
        Write-UIHost -English "     adp up $($Task.runtime) -Plan" -Chinese "     adp up $($Task.runtime) -Plan" -ForegroundColor DarkGray
        Write-UIHost -English "     adp sync start $($Task.runtime)" -Chinese "     adp sync start $($Task.runtime)" -ForegroundColor DarkGray
        Write-UIHost -English "     ssh adp-os-adp-$($Task.runtime)" -Chinese "     ssh adp-os-adp-$($Task.runtime)" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  3. Add tasks[].runtime before selecting an execution runtime." -Chinese "  3. 在选择执行运行时之前添加 tasks[].runtime。" -ForegroundColor DarkGray
    }

    Write-UIHost -English "  4. Run the agent or task command manually inside the selected workspace." -Chinese "  4. 在选定的工作区内手动运行 agent 或任务命令。" -ForegroundColor DarkGray
    Write-UIHost -English "     After manual execution starts, mark running only as local state:" -Chinese "     手动执行开始后，仅将运行状态标记为本地状态:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace task mark $($Task.name) running -ManifestPath $ManifestPath" -Chinese "     adp workspace task mark $($Task.name) running -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "  5. Validate before review:" -Chinese "  5. 审查前验证:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "  6. Move to review:" -Chinese "  6. 进入审查:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace task review $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adp workspace task review $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Human review bundle:" -Chinese "人工审查包:" -ForegroundColor Yellow
    Write-UIHost -English "  0. Review decision gate:" -Chinese "  0. 审查决策门控:" -ForegroundColor DarkGray
    Write-WorkspaceReviewDecision -Decision $reviewDecision
    Write-UIHost -English "  1. Confirm sync hygiene before review:" -Chinese "  1. 审查前确认同步卫生:" -ForegroundColor DarkGray
    Write-WorkspaceCheck -Level $syncHygiene.Level -Name "sync hygiene" -ChineseName "同步卫生" -Detail "($($syncHygiene.Status)$(if ($syncHygiene.Detail) { ': ' + $syncHygiene.Detail }))"
    if (Test-WorkspaceSyncHygieneBlocking -SyncHygiene $syncHygiene) {
        Write-UIHost -English "     Review should not accept the task until sync hygiene is reviewed or the runtime sync profile is updated." -Chinese "     在同步卫生经过审查或运行时同步配置文件更新之前，审查不应接受该任务。" -ForegroundColor Yellow
    }
    Write-UIHost -English "  2. Confirm readiness before review:" -Chinese "  2. 审查前确认就绪状态:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace status -ManifestPath $ManifestPath" -Chinese "     adp workspace status -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "  3. Confirm checkpoint state:" -Chinese "  3. 确认检查点状态:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adp workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    if (Test-WorkspaceTaskRequiresSnapshot -Task $Task) {
        Write-UIHost -English "     Review should not accept broad agent work until the snapshot-first gate is ready or explicitly waived in local ADP-OS state." -Chinese "     在快照优先门控就绪或在本地 ADP-OS 状态中显式豁免之前，审查不应接受广泛的 agent 工作。" -ForegroundColor DarkGray
        Write-UIHost -English "     waiver: adp workspace task mark $($Task.name) checkpoint-waived -ManifestPath $ManifestPath" -Chinese "     豁免: adp workspace task mark $($Task.name) checkpoint-waived -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  4. Run or inspect validation commands:" -Chinese "  4. 运行或检查验证命令:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "     recorded validation: $validationStateText" -Chinese "     已记录的验证: $validationStateText" -ForegroundColor DarkGray
    Write-WorkspaceValidationDetailLines -RecordedState $recordedState
    Write-UIHost -English "     state file: $resolvedStatePath" -Chinese "     状态文件: $resolvedStatePath" -ForegroundColor DarkGray
    Write-UIHost -English "  5. Inspect source changes in the target project:" -Chinese "  5. 检查目标项目中的源更改:" -ForegroundColor DarkGray
    Write-UIHost -English "     git status --short" -Chinese "     git status --short" -ForegroundColor DarkGray
    Write-UIHost -English "     git diff --stat" -Chinese "     git diff --stat" -ForegroundColor DarkGray
    Write-UIHost -English "     git diff" -Chinese "     git diff" -ForegroundColor DarkGray
    Write-UIHost -English "  6. Decide explicitly:" -Chinese "  6. 显式决策:" -ForegroundColor DarkGray
    Write-UIHost -English "     rollback: adp workspace task rollback $($Task.name) -ManifestPath $ManifestPath" -Chinese "     回滚: adp workspace task rollback $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "     revise:   fix the task result and re-run validation" -Chinese "     修订:   修正任务结果并重新运行验证" -ForegroundColor DarkGray
    Write-UIHost -English "     commit:   adp workspace task commit $($Task.name) -ManifestPath $ManifestPath" -Chinese "     提交:   adp workspace task commit $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    if ($reviewDecision.Verdict -eq "validation passed") {
        Write-UIHost -English "     accept:   adp workspace task mark $($Task.name) reviewed -ManifestPath $ManifestPath" -Chinese "     接受:   adp workspace task mark $($Task.name) reviewed -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "     accept:   withheld until review decision gate is OK" -Chinese "     接受:   暂缓，直到审查决策门控就绪" -ForegroundColor Yellow
        Write-UIHost -English "     resolve:  $($reviewDecision.NextStep)" -Chinese "     解决:  $($reviewDecision.NextStep)" -ForegroundColor DarkGray
    }
    Write-UIHost -English "     Commit readiness requires sync hygiene, recorded validation, plus local state 'reviewed' or 'committed'." -Chinese "     提交就绪需要同步卫生、已记录的验证以及本地状态 'reviewed' 或 'committed'。" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Rollback boundary:" -Chinese "回滚边界:" -ForegroundColor Yellow
    Write-UIHost -English "  Decision context:" -Chinese "  决策上下文:" -ForegroundColor DarkGray
    Write-WorkspaceReviewDecision -Decision $reviewDecision
    Write-UIHost -English "     sync hygiene: $($syncHygiene.Status)$(if ($syncHygiene.Detail) { ' - ' + $syncHygiene.Detail })" -Chinese "     同步卫生: $($syncHygiene.Status)$(if ($syncHygiene.Detail) { ' - ' + $syncHygiene.Detail })" -ForegroundColor DarkGray
    Write-UIHost -English "     recorded validation: $validationStateText" -Chinese "     已记录的验证: $validationStateText" -ForegroundColor DarkGray
    Write-WorkspaceValidationDetailLines -RecordedState $recordedState
    Write-UIHost -English "     state file: $resolvedStatePath" -Chinese "     状态文件: $resolvedStatePath" -ForegroundColor DarkGray
    if ($Task.runtime -and $Task.snapshot) {
        if ($snapshotGate.Blocking) {
            Write-UIHost -English "  VM snapshot rollback command:" -Chinese "  VM 快照回滚命令:" -ForegroundColor Yellow
            Write-UIHost -English "     Snapshot rollback is not ready: $($snapshotGate.Detail)" -Chinese "     快照回滚未就绪: $($snapshotGate.Detail)" -ForegroundColor Yellow
            Write-UIHost -English "     Resolve the checkpoint gate before using VM snapshot rollback." -Chinese "     在使用 VM 快照回滚之前解决检查点门控。" -ForegroundColor DarkGray
        } elseif ($snapshotGate.Status -eq "waived") {
            Write-UIHost -English "  VM snapshot rollback command:" -Chinese "  VM 快照回滚命令:" -ForegroundColor Yellow
            Write-UIHost -English "     Snapshot rollback is waived: $($snapshotGate.Detail)" -Chinese "     快照回滚已豁免: $($snapshotGate.Detail)" -ForegroundColor Yellow
            Write-UIHost -English "     No VM restore command is printed because no checkpoint was confirmed." -Chinese "     未打印 VM 恢复命令，因为没有确认检查点。" -ForegroundColor DarkGray
        } else {
            Write-UIHost -English "  VM snapshot rollback command:" -Chinese "  VM 快照回滚命令:" -ForegroundColor DarkGray
            Write-UIHost -English "     adp restore $($Task.runtime) $($Task.snapshot)" -Chinese "     adp restore $($Task.runtime) $($Task.snapshot)" -ForegroundColor DarkGray
        }
    } else {
        Write-UIHost -English "  Add tasks[].runtime and tasks[].snapshot before planning VM snapshot rollback." -Chinese "  在规划 VM 快照回滚之前添加 tasks[].runtime 和 tasks[].snapshot。" -ForegroundColor DarkGray
    }

    Write-UIHost -English "  Source rollback remains a separate Git decision inside the target project:" -Chinese "  源回滚仍是目标项目内的独立 Git 决策:" -ForegroundColor DarkGray
    Write-UIHost -English "     git status --short" -Chinese "     git status --short" -ForegroundColor DarkGray
    Write-UIHost -English "     git diff --stat" -Chinese "     git diff --stat" -ForegroundColor DarkGray
    Write-UIHost -English "     git restore <paths>" -Chinese "     git restore <paths>" -ForegroundColor DarkGray
    Write-UIHost -English "  Do not run restore commands until the human reviewer has chosen rollback." -Chinese "  在人工审查者选择回滚之前，不要运行恢复命令。" -ForegroundColor DarkGray
    Write-UIHost -English "  After rollback is completed manually, record local rollback state:" -Chinese "  手动完成回滚后，记录本地回滚状态:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace task mark $($Task.name) rollback -ManifestPath $ManifestPath" -Chinese "     adp workspace task mark $($Task.name) rollback -ManifestPath $ManifestPath" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Commit boundary:" -Chinese "提交边界:" -ForegroundColor Yellow
    Write-UIHost -English "  0. Commit readiness gate:" -Chinese "  0. 提交就绪门控:" -ForegroundColor DarkGray
    Write-WorkspaceCommitDecision -Decision $commitDecision
    Write-UIHost -English "     sync hygiene: $($syncHygiene.Status)$(if ($syncHygiene.Detail) { ' - ' + $syncHygiene.Detail })" -Chinese "     同步卫生: $($syncHygiene.Status)$(if ($syncHygiene.Detail) { ' - ' + $syncHygiene.Detail })" -ForegroundColor DarkGray
    Write-UIHost -English "     recorded task state: $recordedTaskState" -Chinese "     已记录的任务状态: $recordedTaskState" -ForegroundColor DarkGray
    Write-UIHost -English "     recorded validation: $validationStateText" -Chinese "     已记录的验证: $validationStateText" -ForegroundColor DarkGray
    Write-WorkspaceValidationDetailLines -RecordedState $recordedState
    Write-UIHost -English "     state file: $resolvedStatePath" -Chinese "     状态文件: $resolvedStatePath" -ForegroundColor DarkGray
    Write-UIHost -English "  1. Confirm review bundle:" -Chinese "  1. 确认审查包:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace task review $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adp workspace task review $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "  2. Confirm validation expectations:" -Chinese "  2. 确认验证预期:" -ForegroundColor DarkGray
    Write-UIHost -English "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adp workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "  3. Inspect source changes in the target project:" -Chinese "  3. 检查目标项目中的源更改:" -ForegroundColor DarkGray
    Write-UIHost -English "     git status --short" -Chinese "     git status --short" -ForegroundColor DarkGray
    Write-UIHost -English "     git diff --stat" -Chinese "     git diff --stat" -ForegroundColor DarkGray
    Write-UIHost -English "     git diff" -Chinese "     git diff" -ForegroundColor DarkGray
    if ($commitDecision.Verdict -eq "commit ready") {
        Write-UIHost -English "  4. Commit only after the human reviewer accepts the task result:" -Chinese "  4. 仅在人工审查者接受任务结果后才提交:" -ForegroundColor DarkGray
        Write-UIHost -English "     git add <paths>" -Chinese "     git add <paths>" -ForegroundColor DarkGray
        Write-UIHost -English "     git commit -m ""<message>""" -Chinese "     git commit -m ""<message>""" -ForegroundColor DarkGray
        Write-UIHost -English "  5. After the commit is created manually, record local committed state:" -Chinese "  5. 手动创建提交后，记录本地已提交状态:" -ForegroundColor DarkGray
        Write-UIHost -English "     adp workspace task mark $($Task.name) committed -ManifestPath $ManifestPath" -Chinese "     adp workspace task mark $($Task.name) committed -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  4. Commit commands withheld until commit readiness is OK." -Chinese "  4. 提交命令暂缓，直到提交就绪状态正常。" -ForegroundColor Yellow
        Write-UIHost -English "     Resolve gate first: $($commitDecision.NextStep)" -Chinese "     先解决门控: $($commitDecision.NextStep)" -ForegroundColor DarkGray
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

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Workspace task mark: $($Task.name)" -Chinese "工作空间任务标记: $($Task.name)" -ForegroundColor Cyan
    Write-UIHost -English "Recorded local lifecycle state only. No VM, sync, snapshot, file, Git, or validation command was run." -Chinese "仅记录本地生命周期状态。未运行任何 VM、同步、快照、文件、Git 或验证命令。" -ForegroundColor DarkGray
    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "  State: $StateName" -Chinese "  状态: $StateName" -ForegroundColor Green
    Write-UIHost -English "  File:  $resolvedStatePath" -Chinese "  文件:  $resolvedStatePath" -ForegroundColor DarkGray
    switch ($StateName) {
        "checkpoint-waived" {
            Write-UIHost -English "  Boundary: checkpoint-waived records explicit human acceptance of missing VM snapshot protection. It does not create a snapshot, prove rollback safety, or restore rollback capability." -Chinese "  边界: checkpoint-waived 记录了人工明确接受缺少 VM 快照保护的状态。它不会创建快照、不会证明回滚安全、也不会恢复回滚能力。" -ForegroundColor Yellow
            Write-UIHost -English "  Evidence: workspace status, dashboard, project, report, review, rollback, and commit will show the checkpoint gate as waived instead of ready." -Chinese "  证据: workspace status、dashboard、project、report、review、rollback 和 commit 将显示检查点门控为已豁免而非就绪。" -ForegroundColor DarkGray
        }
        "running" {
            Write-UIHost -English "  Boundary: running means manual execution began or was attempted; ADP-OS did not start the agent, approve execution, validate output, or satisfy review/commit readiness." -Chinese "  边界: running 表示人工执行已开始或已尝试；ADP-OS 并未启动 agent、未批准执行、未验证输出、也未满足审查/提交就绪条件。" -ForegroundColor Yellow
        }
        "validated" {
            Write-UIHost -English "  Boundary: validated is a local lifecycle note only. Use 'adp workspace task validate <task> -Execute' to record executable validation evidence." -Chinese "  边界: validated 仅为本机生命周期备注。使用 'adp workspace task validate <task> -Execute' 记录可执行的验证证据。" -ForegroundColor Yellow
        }
        "reviewed" {
            Write-UIHost -English "  Boundary: reviewed should be used only after human source review accepts the diff, rollback path, snapshot context, and recorded validation evidence." -Chinese "  边界: reviewed 应仅在人工源码审查接受 diff、回滚路径、快照上下文和已记录的验证证据后使用。" -ForegroundColor Yellow
        }
        "committed" {
            Write-UIHost -English "  Boundary: committed is a local lifecycle note only; ADP-OS did not stage files or run git commit." -Chinese "  边界: committed 仅为本机生命周期备注；ADP-OS 并未暂存文件或运行 git commit。" -ForegroundColor Yellow
        }
        "rollback" {
            Write-UIHost -English "  Boundary: rollback is a local lifecycle note only; ADP-OS did not restore snapshots or modify source files." -Chinese "  边界: rollback 仅为本机生命周期备注；ADP-OS 并未恢复快照或修改源文件。" -ForegroundColor Yellow
        }
        default {
            Write-UIHost -English "  Boundary: this state does not prove execution, validation, review acceptance, rollback readiness, or commit readiness." -Chinese "  边界: 此状态不证明执行、验证、审查通过、回滚就绪或提交就绪。" -ForegroundColor DarkGray
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
            Write-UIHost -English "Workspace manifest already exists: $ManifestPath" -Chinese "工作区清单已存在: $ManifestPath" -ForegroundColor Yellow
            Write-UIHost -English "  No changes made." -Chinese "  未做任何更改。" -ForegroundColor DarkGray
            return
        }

        $examplePath = Join-Path (Get-ProjectRoot) "configs\workspace.example.json"
        if (-not (Test-Path -LiteralPath $examplePath)) {
            throw "Workspace example missing: $examplePath"
        }

        Copy-Item -LiteralPath $examplePath -Destination $ManifestPath
        Write-UIHost -English "Workspace manifest created: $ManifestPath" -Chinese "工作区清单已创建: $ManifestPath" -ForegroundColor Green
        Write-UIHost -English "  Edit project paths, runtimes, validation commands, and task snapshots before use." -Chinese "  使用前请编辑项目路径、运行时、验证命令和任务快照。" -ForegroundColor DarkGray
    }
    "show" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceSummary -Manifest $manifest
    }
    "plan" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-UIHost -English "Plan only: no projects will be cloned, no sync sessions will be changed, and no snapshots will be created." -Chinese "仅计划：不会 clone 任何项目、不会更改任何同步会话、不会创建任何快照。" -ForegroundColor Cyan
        Write-UIHost -English "" -Chinese ""
        Write-WorkspaceSummary -Manifest $manifest
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Suggested next steps:" -Chinese "建议的后续步骤:" -ForegroundColor Yellow
        foreach ($project in (Get-WorkspaceArray $manifest.projects)) {
            if ($project.runtime) {
                Write-UIHost -English "  - Preview runtime: adp up $($project.runtime) -Plan" -Chinese "  - 预览运行时: adp up $($project.runtime) -Plan" -ForegroundColor DarkGray
                if ($project.sync) {
                    Write-UIHost -English "  - Start sync when ready: adp sync start $($project.runtime)" -Chinese "  - 准备好后启动同步: adp sync start $($project.runtime)" -ForegroundColor DarkGray
                }
            }
        }
        foreach ($task in (Get-WorkspaceArray $manifest.tasks)) {
            if ($task.runtime -and $task.snapshot) {
                $snapshotNaming = Get-WorkspaceSnapshotNamingStatus -Task $task
                Write-UIHost -English "  - Snapshot before task '$($task.name)' (naming: $($snapshotNaming.Status)): adp snapshot create $($task.runtime) $($task.snapshot)" -Chinese "  - 任务 '$($task.name)' 之前的快照 (命名: $($snapshotNaming.Status)): adp snapshot create $($task.runtime) $($task.snapshot)" -ForegroundColor DarkGray
            }
        }
        foreach ($milestone in (Get-WorkspaceMilestones -Manifest $manifest)) {
            $milestoneStatus = Get-WorkspaceMilestoneStatus -Manifest $manifest -Milestone $milestone
            if ($milestoneStatus.RuntimeName -ne "not configured") {
                Write-UIHost -English "  - Milestone checkpoint '$($milestoneStatus.Name)' (naming: $($milestoneStatus.SnapshotNaming.Status)): adp snapshot create $($milestoneStatus.RuntimeName) $($milestoneStatus.SnapshotName)" -Chinese "  - 里程碑检查点 '$($milestoneStatus.Name)' (命名: $($milestoneStatus.SnapshotNaming.Status)): adp snapshot create $($milestoneStatus.RuntimeName) $($milestoneStatus.SnapshotName)" -ForegroundColor DarkGray
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
        if ([string]::IsNullOrWhiteSpace($TaskCommand)) {
            Write-ErrorLog -Message (Get-UIText -English "Usage: adp workspace task <prepare|snapshot|run|validate|review|rollback|commit|mark> <task-name>" -Chinese "用法: adp workspace task <prepare|snapshot|run|validate|review|rollback|commit|mark> <task-name>") -Component "cli.workspace"
            Write-UIHost -English "  adp workspace task validate <task-name> [-Execute] [-Plan] [-ManifestPath <path>]" -Chinese "  adp workspace task validate <task-name> [-Execute] [-Plan] [-ManifestPath <path>]" -ForegroundColor DarkGray
            Write-UIHost -English "  adp workspace task mark <task-name> <state> [-StatePath <path>]" -Chinese "  adp workspace task mark <task-name> <state> [-StatePath <path>]" -ForegroundColor DarkGray
            exit 1
        }
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Invoke-WorkspaceTask -Manifest $manifest -Command $TaskCommand -Name $TaskName -StateName $TaskState -Path $ManifestPath -LocalStatePath $StatePath -ExecuteValidation:$Execute -PlanOnly:$Plan
    }
    default {
        Write-ErrorLog -Message (Get-UIText -English "Unknown workspace command: $SubCommand. Valid: init, show, plan, status, dashboard, report, recipes, create, open, sync, project, task" -Chinese "未知工作区命令: $SubCommand。可用: init, show, plan, status, dashboard, report, recipes, create, open, sync, project, task") -Component "cli.workspace"
        exit 1
    }
}
