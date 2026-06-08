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
        Write-UIHost -English "      prepare: adpos workspace task prepare $taskName -ManifestPath $ManifestPath" -Chinese "      准备: adpos workspace task prepare $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "      run:     adpos workspace task run $taskName -ManifestPath $ManifestPath" -Chinese "      运行:   adpos workspace task run $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "      review:  adpos workspace task review $taskName -ManifestPath $ManifestPath" -Chinese "      审查:   adpos workspace task review $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    }
}
