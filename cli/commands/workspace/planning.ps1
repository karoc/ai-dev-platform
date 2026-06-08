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
