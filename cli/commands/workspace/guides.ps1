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
    Write-UIHost -English "  adpos workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adpos workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    if ($runtimeName) {
        Write-UIHost -English "  adpos up $runtimeName -Plan" -Chinese "  adpos up $runtimeName -Plan" -ForegroundColor DarkGray
        if ($syncExpected) {
            Write-UIHost -English "  adpos sync start $runtimeName" -Chinese "  adpos sync start $runtimeName" -ForegroundColor DarkGray
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
        Write-UIHost -English "  adpos sync status" -Chinese "  adpos sync status" -ForegroundColor DarkGray
        if ($syncExpected) {
            Write-UIHost -English "  adpos sync start $runtimeName" -Chinese "  adpos sync start $runtimeName" -ForegroundColor DarkGray
            Write-UIHost -English "  adpos sync stop $runtimeName" -Chinese "  adpos sync stop $runtimeName" -ForegroundColor DarkGray
        } else {
            Write-UIHost -English "  projects[].sync is false; set it to true before treating sync as expected for this project." -Chinese "  projects[].sync 为 false；在将同步视为该项目预期行为之前，请将其设为 true。" -ForegroundColor Yellow
            Write-UIHost -English "  adpos sync start $runtimeName" -Chinese "  adpos sync start $runtimeName" -ForegroundColor DarkGray
        }
    } else {
        Write-UIHost -English "  Set a known projects[].runtime before using runtime sync for this project." -Chinese "  在为此项目使用运行时同步之前，请先设置已知的 projects[].runtime。" -ForegroundColor Yellow
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Project commands:" -Chinese "项目命令:" -ForegroundColor Yellow
    Write-UIHost -English "  adpos workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adpos workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adpos workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adpos workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
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
    Write-UIHost -English "  1. Open:      adpos workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  1. 打开:      adpos workspace open $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    if ($runtimeName) {
        Write-UIHost -English "  2. Runtime:   adpos up $runtimeName -Plan" -Chinese "  2. 运行时:    adpos up $runtimeName -Plan" -ForegroundColor DarkGray
        Write-UIHost -English "  3. Sync:      adpos workspace sync $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  3. 同步:      adpos workspace sync $projectName -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  2. Runtime:   set projects[].runtime before planning runtime startup" -Chinese "  2. 运行时:    在规划运行时启动之前设置 projects[].runtime" -ForegroundColor Yellow
        Write-UIHost -English "  3. Sync:      set projects[].runtime before planning sync" -Chinese "  3. 同步:      在规划同步之前设置 projects[].runtime" -ForegroundColor Yellow
    }
    if ($validationCommands.Count -gt 0) {
        Write-UIHost -English "  4. Validate:  run declared project validation commands manually, or use task validation for linked tasks" -Chinese "  4. 验证:      手动运行已声明的项目验证命令，或对关联任务使用任务验证" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  4. Validate:  add projects[].validation or task validation commands" -Chinese "  4. 验证:      添加 projects[].validation 或任务验证命令" -ForegroundColor Yellow
    }
    Write-UIHost -English "  5. Evidence:  adpos workspace report -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  5. 证据:      adpos workspace report -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray

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
        Write-UIHost -English "      prepare:  adpos workspace task prepare $taskName -ManifestPath $ManifestPath" -Chinese "      准备:  adpos workspace task prepare $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "      validate: adpos workspace task validate $taskName -ManifestPath $ManifestPath" -Chinese "      验证: adpos workspace task validate $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        Write-UIHost -English "      review:   adpos workspace task review $taskName -ManifestPath $ManifestPath" -Chinese "      审查:   adpos workspace task review $taskName -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    }
}
