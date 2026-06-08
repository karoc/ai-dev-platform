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
    [switch]$Local,
    [switch]$Plan,
    [switch]$Markdown,
    [switch]$Terse,
    # Evidence chain parameters
    [switch]$Snapshot,
    [switch]$Log,
    [switch]$Export,
    [Alias("Path")]
    [string]$ExportPath,
    [string]$Operation,
    [string]$Details,
    [switch]$AiAssisted,
    [string]$Reviewer,
    [string]$Notes,
    [switch]$Json
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command Set-ADPWorkspaceExternalProbePolicy -ErrorAction SilentlyContinue)) {
    . (Join-Path (Split-Path $PSScriptRoot -Parent) "lib\workspace-probes.ps1")
}
Set-ADPWorkspaceExternalProbePolicy -SubCommand $SubCommand -TaskCommand $TaskCommand -ExecuteValidation:$Execute -LocalExecution:$Local

function Show-WorkspaceUsage {
    Write-ErrorLog -Message "Usage: adpos workspace <command> [-ManifestPath <path>]" -Component "cli.workspace"
    Write-Host ""

    Write-UIHost -English "Inspect:" -Chinese "查看:" -ForegroundColor Yellow
    Write-UIHost -English "  adpos workspace show [-ManifestPath <path>]          Show workspace manifest details" -Chinese "  adpos workspace show [-ManifestPath <path>]          显示工作区 manifest 详情" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace plan [-ManifestPath <path>]          Preview workspace plan" -Chinese "  adpos workspace plan [-ManifestPath <path>]          预览工作区计划" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace status [project-name] [-ManifestPath <path>]   Show workspace task status" -Chinese "  adpos workspace status [project-name] [-ManifestPath <path>]   显示工作区任务状态" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace dashboard [-ManifestPath <path>]      Show workspace health dashboard" -Chinese "  adpos workspace dashboard [-ManifestPath <path>]      显示工作区健康仪表板" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace report [-Markdown] [-Terse] [-ManifestPath <path>]   Generate workspace report" -Chinese "  adpos workspace report [-Markdown] [-Terse] [-ManifestPath <path>]   生成工作区报告" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace recipes [-ManifestPath <path>]        Show workspace recipes" -Chinese "  adpos workspace recipes [-ManifestPath <path>]        显示工作区配方" -ForegroundColor DarkGray
    Write-Host ""
    Write-UIHost -English "Manage:" -Chinese "管理:" -ForegroundColor Yellow
    Write-UIHost -English "  adpos workspace init [-ManifestPath <path>]           Initialize workspace manifest" -Chinese "  adpos workspace init [-ManifestPath <path>]           初始化工作区 manifest" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace create [-Plan] [-ManifestPath <path>]  Create workspace projects" -Chinese "  adpos workspace create [-Plan] [-ManifestPath <path>]  创建工作区项目" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace open [project-name] [-ManifestPath <path>]   Show open guide for a project" -Chinese "  adpos workspace open [project-name] [-ManifestPath <path>]   显示项目打开指南" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace sync [project-name] [-ManifestPath <path>]   Show sync guide for a project" -Chinese "  adpos workspace sync [project-name] [-ManifestPath <path>]   显示项目同步指南" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace project [project-name] [-ManifestPath <path>]  Show project lifecycle" -Chinese "  adpos workspace project [project-name] [-ManifestPath <path>]  显示项目生命周期" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name> [-ManifestPath <path>]  Manage workspace tasks" -Chinese "  adpos workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name> [-ManifestPath <path>]  管理工作区任务" -ForegroundColor DarkGray
    Write-UIHost -English "    validate supports -Execute (SSH), -Local (host), -Plan (preview)" -Chinese "    validate 支持 -Execute (SSH), -Local (本地), -Plan (预览)" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace task mark <task-name> <state> [-StatePath <path>]  Mark task state" -Chinese "  adpos workspace task mark <task-name> <state> [-StatePath <path>]  标记任务状态" -ForegroundColor DarkGray
    Write-Host ""
    Write-UIHost -English "Evidence:" -Chinese "证据:" -ForegroundColor Yellow
    Write-UIHost -English "  adpos workspace evidence -Snapshot [-ManifestPath <path>]   Sign current snapshot metadata" -Chinese "  adpos workspace evidence -Snapshot [-ManifestPath <path>]   签署当前快照元数据" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace evidence -Log -Operation <op> [-Details <text>]   Record operation log entry" -Chinese "  adpos workspace evidence -Log -Operation <op> [-Details <text>]   记录操作日志条目" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace evidence -Export [-Path <path>]             Export evidence as ZIP" -Chinese "  adpos workspace evidence -Export [-Path <path>]             导出证据为 ZIP" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace declare -AiAssisted [-Reviewer <name>] [-Notes ""...""]   Declare AI-assisted development" -Chinese "  adpos workspace declare -AiAssisted [-Reviewer <name>] [-Notes ""...""]   声明 AI 辅助开发" -ForegroundColor DarkGray
}

function Read-WorkspaceManifest {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Workspace manifest not found: $Path. Run: adpos workspace init"
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
        Detail   = "create checkpoint first: adpos snapshot create $($Task.runtime) $($Task.snapshot)"
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

. (Join-Path $PSScriptRoot "workspace\projects.ps1")

. (Join-Path $PSScriptRoot "workspace\validation.ps1")

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
        $projectPath = Resolve-ProjectWorkspacePath -Project $project
        Write-UIHost -English "  - $($project.name): $projectPath -> $runtime (sync: $sync)" -Chinese "  - $($project.name): $projectPath -> $runtime (同步: $sync)" -ForegroundColor DarkGray
        if (-not [string]::IsNullOrWhiteSpace($projectPath)) {
            $pathLevel = if (Test-Path -LiteralPath $projectPath) { "OK" } else { "WARN" }
            $pathStatus = if ($pathLevel -eq "OK") { "exists" } else { "missing" }
            Write-WorkspaceCheck -Level $pathLevel -Name "project path" -ChineseName "项目路径" -Detail ("({0}: {1})" -f $pathStatus, $projectPath)
        } else {
            Write-WorkspaceCheck -Level "FAIL" -Name "project path" -ChineseName "项目路径" -Detail "(missing)" -ChineseDetail "(缺失)"
        }
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

. (Join-Path $PSScriptRoot "workspace\status.ps1")

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
            Write-UIHost -English "       checkpoint command: adpos snapshot create $($status.RuntimeName) $($status.SnapshotName)" -Chinese "       检查点命令: adpos snapshot create $($status.RuntimeName) $($status.SnapshotName)" -ForegroundColor DarkGray
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

        $base = "adpos workspace task validate $($item.TaskName) -ManifestPath $ManifestPath"
        $queue.Add([pscustomobject]@{
                TaskName       = $item.TaskName
                Level          = $level
                Validation     = $item.ValidationStateText
                CommandCount   = $item.ValidationCommands.Count
                Readiness      = $readiness
                Blockers       = @($blockers)
                PlanCommand    = $base
                ExecutePreview = "adpos workspace task validate $($item.TaskName) -Execute -Plan -ManifestPath $ManifestPath"
                ExecuteCommand = "adpos workspace task validate $($item.TaskName) -Execute -ManifestPath $ManifestPath"
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
        $base = "adpos workspace report -ManifestPath $ManifestPath"
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
        Write-UIHost -English "       next: adpos workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       下一步: adpos workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-UIHost -English "       sync: adpos workspace sync $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       同步: adpos workspace sync $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-UIHost -English "       lifecycle: adpos workspace project $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       生命周期: adpos workspace project $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
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
        Write-UIHost -English "       prepare: adpos workspace task prepare $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       准备: adpos workspace task prepare $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        if ($item.RequiresSnapshot) {
            if ($item.SnapshotName -ne "not configured") {
                Write-UIHost -English "       checkpoint: adpos snapshot create $($item.RuntimeName) $($item.SnapshotName)" -Chinese "       检查点: adpos snapshot create $($item.RuntimeName) $($item.SnapshotName)" -ForegroundColor DarkGray
            } else {
                Write-UIHost -English "       checkpoint: set tasks[].snapshot before creating a task checkpoint" -Chinese "       检查点: 在创建任务检查点之前设置 tasks[].snapshot" -ForegroundColor Yellow
            }
        }
        Write-UIHost -English "       validate plan: adpos workspace task validate $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       验证计划: adpos workspace task validate $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-UIHost -English "       execute preview: adpos workspace task validate $($item.TaskName) -Execute -Plan -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       执行预览: adpos workspace task validate $($item.TaskName) -Execute -Plan -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        Write-UIHost -English "       review: adpos workspace task review $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       审查: adpos workspace task review $($item.TaskName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Milestone recipes:" -Chinese "里程碑食谱:" -ForegroundColor Yellow
    if ($milestones.Count -eq 0) {
        Write-WorkspaceCheck -Level "INFO" -Name "milestones" -ChineseName "里程碑" -Detail "(none configured)" -ChineseDetail "(未配置)"
    }
    foreach ($milestone in $milestones) {
        $status = Get-WorkspaceMilestoneStatus -Manifest $Manifest -Milestone $milestone
        Write-WorkspaceCheck -Level $status.Level -Name $status.Name -ChineseName $status.Name -Detail "(runtime: $($status.RuntimeName); snapshot: $($status.SnapshotName); tasks: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { 'none' }))" -ChineseDetail "(运行时: $($status.RuntimeName); 快照: $($status.SnapshotName); 任务: $(if ($status.TaskNames.Count -gt 0) { $status.TaskNames -join ', ' } else { '无' }))"
        Write-UIHost -English "       checkpoint command: adpos snapshot create $($status.RuntimeName) $($status.SnapshotName)" -Chinese "       检查点命令: adpos snapshot create $($status.RuntimeName) $($status.SnapshotName)" -ForegroundColor DarkGray
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
    Write-UIHost -English "  adpos workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adpos workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace report -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adpos workspace report -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace report -Markdown -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adpos workspace report -Markdown -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
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

. (Join-Path $PSScriptRoot "workspace\guides.ps1")

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
        [string]$StatePath,
        [switch]$Terse
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
    if ($Terse) {
        $handoffParts = @()
        $handoffParts += "$total task$(if ($total -ne 1) { 's' })"
        if ($passed -gt 0) { $handoffParts += "$passed passed" }
        if ($failed -gt 0) { $handoffParts += "$failed failed" }
        if ($missing -gt 0) { $handoffParts += "$missing validation missing" }
        if ($snapshotBlocked -gt 0) { $handoffParts += "$snapshotBlocked snapshot-blocked" }
        if ($reviewReady -gt 0) { $handoffParts += "$reviewReady review-ready" }
        if ($commitReady -gt 0) { $handoffParts += "$commitReady commit-ready" }
        Write-Output "> $($handoffParts -join ' · ') · release: $($policy.Decision)"
    } else {
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
    }
    Write-Output ""
    if (-not $Terse -or $validationQueue.Count -gt 0) {
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
    }

    if (-not $Terse -or $evaluationQueue.Count -gt 0) {
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
    }
    if (-not $Terse) {
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
    }
    if (-not $Terse -or $milestoneStatuses.Count -gt 0) {
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
    }

    if (-not $Terse -or $milestoneRollups.Count -gt 0) {
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
    }
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

    if (-not $Terse) {
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
            Write-Output "adpos workspace task review $($item.TaskName) -ManifestPath $ManifestPath"
            Write-Output "adpos workspace task rollback $($item.TaskName) -ManifestPath $ManifestPath"
            Write-Output "adpos workspace task commit $($item.TaskName) -ManifestPath $ManifestPath"
            Write-Output '```'
        }
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
        [switch]$Markdown,
        [switch]$Terse
    )

    if ($Markdown) {
        Write-WorkspaceReportMarkdown -Manifest $Manifest -ManifestPath $ManifestPath -StatePath $StatePath -Terse:$Terse
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
        Write-UIHost -English "       review:   adpos workspace task review $($item.TaskName) -ManifestPath $ManifestPath" -Chinese "       审查:   adpos workspace task review $($item.TaskName) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "       rollback: adpos workspace task rollback $($item.TaskName) -ManifestPath $ManifestPath" -Chinese "       回滚:   adpos workspace task rollback $($item.TaskName) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "       commit:   adpos workspace task commit $($item.TaskName) -ManifestPath $ManifestPath" -Chinese "       提交:   adpos workspace task commit $($item.TaskName) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "       inspect:  git status --short; git diff --stat; git diff" -Chinese "       检查:   git status --short; git diff --stat; git diff" -ForegroundColor DarkGray
    }
}

. (Join-Path $PSScriptRoot "workspace\tasks.ps1")
. (Join-Path $PSScriptRoot "workspace\evidence.ps1")


if (-not $SubCommand) {
    Show-WorkspaceUsage
    exit 0
}

switch ($SubCommand) {
    "help" {
        Show-WorkspaceUsage
        exit 0
    }
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
                Write-UIHost -English "  - Preview runtime: adpos up $($project.runtime) -Plan" -Chinese "  - 预览运行时: adpos up $($project.runtime) -Plan" -ForegroundColor DarkGray
                if ($project.sync) {
                    Write-UIHost -English "  - Start sync when ready: adpos sync start $($project.runtime)" -Chinese "  - 准备好后启动同步: adpos sync start $($project.runtime)" -ForegroundColor DarkGray
                }
            }
        }
        foreach ($task in (Get-WorkspaceArray $manifest.tasks)) {
            if ($task.runtime -and $task.snapshot) {
                $snapshotNaming = Get-WorkspaceSnapshotNamingStatus -Task $task
                Write-UIHost -English "  - Snapshot before task '$($task.name)' (naming: $($snapshotNaming.Status)): adpos snapshot create $($task.runtime) $($task.snapshot)" -Chinese "  - 任务 '$($task.name)' 之前的快照 (命名: $($snapshotNaming.Status)): adpos snapshot create $($task.runtime) $($task.snapshot)" -ForegroundColor DarkGray
            }
        }
        foreach ($milestone in (Get-WorkspaceMilestones -Manifest $manifest)) {
            $milestoneStatus = Get-WorkspaceMilestoneStatus -Manifest $manifest -Milestone $milestone
            if ($milestoneStatus.RuntimeName -ne "not configured") {
                Write-UIHost -English "  - Milestone checkpoint '$($milestoneStatus.Name)' (naming: $($milestoneStatus.SnapshotNaming.Status)): adpos snapshot create $($milestoneStatus.RuntimeName) $($milestoneStatus.SnapshotName)" -Chinese "  - 里程碑检查点 '$($milestoneStatus.Name)' (命名: $($milestoneStatus.SnapshotNaming.Status)): adpos snapshot create $($milestoneStatus.RuntimeName) $($milestoneStatus.SnapshotName)" -ForegroundColor DarkGray
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
        Write-WorkspaceReport -Manifest $manifest -ManifestPath $ManifestPath -StatePath $StatePath -Markdown:$Markdown -Terse:$Terse
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
            Write-ErrorLog -Message (Get-UIText -English "Usage: adpos workspace task <prepare|snapshot|run|validate|review|rollback|commit|mark> <task-name>" -Chinese "用法: adpos workspace task <prepare|snapshot|run|validate|review|rollback|commit|mark> <task-name>") -Component "cli.workspace"
            Write-UIHost -English "  adpos workspace task validate <task-name> [-Execute] [-Local] [-Plan] [-ManifestPath <path>]" -Chinese "  adpos workspace task validate <task-name> [-Execute] [-Local] [-Plan] [-ManifestPath <path>]" -ForegroundColor DarkGray
            Write-UIHost -English "  adpos workspace task mark <task-name> <state> [-StatePath <path>]" -Chinese "  adpos workspace task mark <task-name> <state> [-StatePath <path>]" -ForegroundColor DarkGray
            exit 1
        }
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Invoke-WorkspaceTask -Manifest $manifest -Command $TaskCommand -Name $TaskName -StateName $TaskState -Path $ManifestPath -LocalStatePath $StatePath -ExecuteValidation:$Execute -LocalExecution:$Local -PlanOnly:$Plan
    }
    "evidence" {
        if (-not $Snapshot -and -not $Log -and -not $Export) {
            Show-EvidenceUsage
            exit 1
        }

        $manifest = Read-WorkspaceManifest -Path $ManifestPath

        if ($Snapshot) {
            Invoke-EvidenceSnapshot -Manifest $manifest -ManifestPath $ManifestPath -JsonOutput:$Json
        } elseif ($Log) {
            if ([string]::IsNullOrWhiteSpace($Operation)) {
                Write-ErrorLog -Message "Evidence -Log requires -Operation <op>. Valid: create, sync, start, stop, validate, declare, snapshot, export" -Component "cli.workspace.evidence"
                exit 1
            }
            Invoke-EvidenceLog -ManifestPath $ManifestPath -OperationName $Operation -LogDetails $Details -JsonOutput:$Json
        } elseif ($Export) {
            Invoke-EvidenceExport -ManifestPath $ManifestPath -ExportPathParam $ExportPath
        }
    }
    "declare" {
        if (-not $AiAssisted) {
            Write-UIHost -English "Use -AiAssisted to declare AI-assisted development." -Chinese "使用 -AiAssisted 声明 AI 辅助开发。" -ForegroundColor Yellow
            Write-UIHost -English "  adpos workspace declare -AiAssisted [-Reviewer <name>] [-Notes ""...""]" -Chinese "  adpos workspace declare -AiAssisted [-Reviewer <name>] [-Notes ""...""]" -ForegroundColor DarkGray
            exit 1
        }

        Invoke-EvidenceDeclare -ManifestPath $ManifestPath -AiAssisted:$AiAssisted -Reviewer $Reviewer -Notes $Notes -JsonOutput:$Json
    }
    default {
        Write-ErrorLog -Message (Get-UIText -English "Unknown workspace command: $SubCommand. Use 'adpos workspace help' to see grouped subcommands." -Chinese "未知工作区命令: $SubCommand。使用 'adpos workspace help' 查看分组子命令。") -Component "cli.workspace"
        exit 1
    }
}
