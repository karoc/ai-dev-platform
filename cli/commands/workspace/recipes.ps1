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