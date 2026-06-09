# ADP-OS Workspace Command
# Non-destructive workspace manifest helpers.

[CmdletBinding()]
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

. (Join-Path $PSScriptRoot "workspace\planning.ps1")

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

. (Join-Path $PSScriptRoot "workspace\report.ps1")

. (Join-Path $PSScriptRoot "workspace\recipes.ps1")

. (Join-Path $PSScriptRoot "workspace\guides.ps1")

. (Join-Path $PSScriptRoot "workspace\report-markdown.ps1")

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
        $validWorkspaceCommands = @("help", "show", "plan", "status", "dashboard", "report", "recipes", "init", "create", "open", "sync", "project", "task", "evidence", "declare")
        Write-ErrorLog -Message (Get-UIText -English "Unknown workspace command: $SubCommand. Use 'adpos workspace help' to see grouped subcommands." -Chinese "未知工作区命令: $SubCommand。使用 'adpos workspace help' 查看分组子命令。") -Component "cli.workspace"
        $suggestion = Get-ADPCommandSuggestion -InputCommand $SubCommand -CandidateCommands $validWorkspaceCommands
        if ($suggestion) {
            Write-UIHost -English "Did you mean: adpos workspace $suggestion" -Chinese "你是不是想运行: adpos workspace $suggestion" -ForegroundColor Cyan
        }
        exit 1
    }
}
