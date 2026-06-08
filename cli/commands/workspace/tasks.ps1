function Find-WorkspaceTask {
    param(
        [object]$Manifest,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Task name is required. Usage: adpos workspace task <prepare|snapshot|run|validate|review|rollback|commit> <task-name>"
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
    Write-UIHost -English "     adpos workspace status -ManifestPath $ManifestPath" -Chinese "     adpos workspace status -ManifestPath $ManifestPath" -ForegroundColor DarkGray

    if ($Task.runtime) {
        Write-UIHost -English "  2. Preview runtime startup:" -Chinese "  2. 预览运行时启动:" -ForegroundColor DarkGray
        Write-UIHost -English "     adpos up $($Task.runtime) -Plan" -Chinese "     adpos up $($Task.runtime) -Plan" -ForegroundColor DarkGray
        Write-UIHost -English "  3. Confirm sync when the runtime is ready:" -Chinese "  3. 运行时就绪后确认同步:" -ForegroundColor DarkGray
        Write-UIHost -English "     adpos sync start $($Task.runtime)" -Chinese "     adpos sync start $($Task.runtime)" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  2. Add tasks[].runtime before preparing runtime and sync commands." -Chinese "  2. 在准备运行时和同步命令之前添加 tasks[].runtime。" -ForegroundColor DarkGray
    }

    if ($Task.snapshot -and $Task.runtime) {
        Write-UIHost -English "  4. Plan the checkpoint:" -Chinese "  4. 规划检查点:" -ForegroundColor DarkGray
        Write-UIHost -English "     adpos workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adpos workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    } else {
        $recommendedSnapshot = Get-WorkspaceRecommendedSnapshotName -Task $Task
        Write-UIHost -English "  4. Add tasks[].snapshot before planning checkpoint commands." -Chinese "  4. 在规划检查点命令之前添加 tasks[].snapshot。" -ForegroundColor DarkGray
        Write-UIHost -English "     Recommended: `"$recommendedSnapshot`"" -Chinese "     推荐: `"$recommendedSnapshot`"" -ForegroundColor DarkGray
    }

    Write-UIHost -English "  5. Review validation expectations:" -Chinese "  5. 审查验证预期:" -ForegroundColor DarkGray
    Write-UIHost -English "     adpos workspace task validate $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adpos workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
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
        Write-UIHost -English "  adpos snapshot create $($Task.runtime) $($Task.snapshot)" -Chinese "  adpos snapshot create $($Task.runtime) $($Task.snapshot)" -ForegroundColor DarkGray
        Write-UIHost -English "  If the human reviewer intentionally accepts missing snapshot protection:" -Chinese "  如果人工审查者有意接受缺少快照保护:" -ForegroundColor Yellow
        Write-UIHost -English "  adpos workspace task mark $($Task.name) checkpoint-waived" -Chinese "  adpos workspace task mark $($Task.name) checkpoint-waived" -ForegroundColor DarkGray
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
        [string]$ManifestPath,
        [switch]$ExecuteValidation,
        [switch]$LocalExecution,
        [switch]$PlanOnly
    )

    Write-TaskHeader -Action "validate" -Task $Task -ExplicitExecution:$ExecuteValidation
    Write-TaskSummary -Manifest $Manifest -Task $Task

    $validationCommands = Get-WorkspaceArray $Task.validation
    Write-UIHost -English "" -Chinese ""
    $mode = if ($LocalExecution) { "Local validation execution:" } elseif ($ExecuteValidation) { "Validation execution:" } else { "Validation plan:" }
    $modeCn = if ($LocalExecution) { "本地验证执行:" } elseif ($ExecuteValidation) { "验证执行:" } else { "验证计划:" }
    Write-UIHost -English $mode -Chinese $modeCn -ForegroundColor Yellow
    if ($validationCommands.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "task validation" -ChineseName "任务验证" -Detail "(none configured)" -ChineseDetail "(未配置)"
        Write-UIHost -English "  Add tasks[].validation commands before using this task for review gates." -Chinese "  在使用此任务进行审查门控之前添加 tasks[].validation 命令。" -ForegroundColor DarkGray
        return
    }

    if (-not $ExecuteValidation -and -not $LocalExecution) {
        $index = 1
        foreach ($command in $validationCommands) {
            Write-UIHost -English "  $index. $command" -Chinese "  $index. $command" -ForegroundColor DarkGray
            $index += 1
        }

        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "To execute validation explicitly:" -Chinese "显式执行验证:" -ForegroundColor Yellow
        Write-UIHost -English "  adpos workspace task validate $($Task.name) -Execute -ManifestPath <manifest>" -Chinese "  adpos workspace task validate $($Task.name) -Execute -ManifestPath <manifest>" -ForegroundColor DarkGray
        Write-UIHost -English "  adpos workspace task validate $($Task.name) -Execute -Local -ManifestPath <manifest>  (run locally, no VM required)" -Chinese "  adpos workspace task validate $($Task.name) -Execute -Local -ManifestPath <manifest>  (本地执行，无需 VM)" -ForegroundColor DarkGray
        Write-UIHost -English "  Add -Plan to preview commands without running them." -Chinese "  添加 -Plan 来预览命令而不实际运行它们。" -ForegroundColor DarkGray
        return
    }

    $project = Find-WorkspaceProjectForTask -Manifest $Manifest -Task $Task

    if ($LocalExecution) {
        # --- Local execution path: no SSH, no VM, no runtime gates ---
        $localPath = Resolve-WorkspaceLocalProjectPath -Project $project -ManifestPath $ManifestPath

        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Local readiness gate:" -Chinese "本地就绪门控:" -ForegroundColor Yellow
        Write-WorkspaceCheck -Level "OK" -Name "project" -ChineseName "项目" -Detail "($($project.name): $localPath)" -ChineseDetail "($($project.name): $localPath)"
        if (-not (Test-Path -LiteralPath $localPath -PathType Container)) {
            Write-WorkspaceCheck -Level "FAIL" -Name "local directory" -ChineseName "本地目录" -Detail "(not found: $localPath)" -ChineseDetail "(未找到: $localPath)"
            Write-ErrorLog -Message "Local validation aborted: project directory not found at $localPath" -Component "cli.workspace"
            exit 1
        }
        Write-WorkspaceCheck -Level "OK" -Name "local directory" -ChineseName "本地目录" -Detail "($localPath)" -ChineseDetail "($localPath)"

        if (-not $PlanOnly) {
            Write-UIHost -English "" -Chinese ""
            Write-UIHost -English "Executing declared validation commands locally. No packages, browsers, snapshots, Git staging, or commits are managed by ADP-OS beyond these commands." -Chinese "正在本地执行已声明的验证命令。ADP-OS 不会管理这些命令之外的包、浏览器、快照、Git 暂存或提交。" -ForegroundColor Yellow
        }

        $index = 1
        $startedAt = (Get-Date).ToUniversalTime().ToString("o")
        $commands = @($validationCommands | ForEach-Object { [string]$_ })
        foreach ($command in $validationCommands) {
            $localCommand = [string]$command
            if ($PlanOnly) {
                Write-UIHost -English "  $index. [local] $localCommand  (in $localPath)" -Chinese "  $index. [本地] $localCommand  (在 $localPath)" -ForegroundColor DarkGray
            } else {
                Write-UIHost -English "" -Chinese ""
                Write-UIHost -English "[$index/$($validationCommands.Count)] $localCommand (local)" -Chinese "[$index/$($validationCommands.Count)] $localCommand (本地)" -ForegroundColor Yellow
                $previousLocation = Get-Location
                try {
                    Set-Location -LiteralPath $localPath
                    Invoke-Expression $localCommand
                    $exitCode = $LASTEXITCODE
                } finally {
                    Set-Location -LiteralPath $previousLocation
                }
                if ($exitCode -ne 0) {
                    $completedAt = (Get-Date).ToUniversalTime().ToString("o")
                    $validation = New-WorkspaceValidationResult -Task $Task -Project $project -RemotePath $localPath -Status "failed" -StartedAt $startedAt -CompletedAt $completedAt -Commands $commands -ExitCode $exitCode -FailedCommand ([string]$command)
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
            $validation = New-WorkspaceValidationResult -Task $Task -Project $project -RemotePath $localPath -Status "passed" -StartedAt $startedAt -CompletedAt $completedAt -Commands $commands -ExitCode 0
            $resolvedStatePath = Write-WorkspaceValidationResult -StatePath $StatePath -Task $Task -Validation $validation
            Write-UIHost -English "" -Chinese ""
            Write-UIHost -English "Workspace validation complete: $($Task.name)" -Chinese "工作区验证完成: $($Task.name)" -ForegroundColor Green
            Write-UIHost -English "  Result recorded: $resolvedStatePath" -Chinese "  结果已记录: $resolvedStatePath" -ForegroundColor DarkGray
            Write-UIHost -English "  Review remains explicit; ADP-OS did not stage files or commit changes." -Chinese "  审查仍需显式进行; ADP-OS 未暂存文件或提交更改。" -ForegroundColor DarkGray
        }
    } else {
        # --- Remote execution path: SSH into VM ---
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
    Write-UIHost -English "     adpos workspace status -ManifestPath $ManifestPath" -Chinese "     adpos workspace status -ManifestPath $ManifestPath" -ForegroundColor DarkGray

    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $StatePath
    $state = Read-WorkspaceState -Path $resolvedStatePath
    $recordedState = Get-WorkspaceTaskState -State $state -TaskName $Task.name
    $snapshotStatus = Get-WorkspaceSnapshotStatus -RuntimeName $Task.runtime -SnapshotName $Task.snapshot
    $snapshotGate = Get-WorkspaceSnapshotGate -Task $Task -SnapshotStatus $snapshotStatus -RecordedState $recordedState
    if ($Task.runtime -and $Task.snapshot) {
        Write-UIHost -English "  2. Snapshot-first gate before broad agent work:" -Chinese "  2. 广泛 agent 工作之前的快照优先门控:" -ForegroundColor DarkGray
        Write-UIHost -English "     adpos workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adpos workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        if ($snapshotGate.Blocking) {
            Write-UIHost -English "     BLOCKED: $($snapshotGate.Detail)" -Chinese "     已阻塞: $($snapshotGate.Detail)" -ForegroundColor Yellow
            Write-UIHost -English "     Do not start broad agent work until this gate is ready or explicitly waived in local ADP-OS state." -Chinese "     在此门控就绪或在本地 ADP-OS 状态中显式豁免之前，不要开始广泛的 agent 工作。" -ForegroundColor Yellow
            Write-UIHost -English "     Waive only after human acceptance of the missing checkpoint risk:" -Chinese "     仅在人工接受缺少检查点风险后才豁免:" -ForegroundColor Yellow
            Write-UIHost -English "     adpos workspace task mark $($Task.name) checkpoint-waived -ManifestPath $ManifestPath" -Chinese "     adpos workspace task mark $($Task.name) checkpoint-waived -ManifestPath $ManifestPath" -ForegroundColor DarkGray
        } else {
            Write-UIHost -English "     READY: $($snapshotGate.Detail)" -Chinese "     就绪: $($snapshotGate.Detail)" -ForegroundColor DarkGray
        }
        Write-UIHost -English "     adpos workspace task mark $($Task.name) checkpointed" -Chinese "     adpos workspace task mark $($Task.name) checkpointed" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  2. Add tasks[].runtime and tasks[].snapshot before using rollback-capable agent task execution." -Chinese "  2. 在使用可回滚的 agent 任务执行之前添加 tasks[].runtime 和 tasks[].snapshot。" -ForegroundColor DarkGray
    }

    if ($Task.runtime) {
        Write-UIHost -English "  3. Enter or target the runtime explicitly:" -Chinese "  3. 显式进入或目标运行时:" -ForegroundColor DarkGray
        Write-UIHost -English "     adpos up $($Task.runtime) -Plan" -Chinese "     adpos up $($Task.runtime) -Plan" -ForegroundColor DarkGray
        Write-UIHost -English "     adpos sync start $($Task.runtime)" -Chinese "     adpos sync start $($Task.runtime)" -ForegroundColor DarkGray
        Write-UIHost -English "     ssh adp-os-adp-$($Task.runtime)" -Chinese "     ssh adp-os-adp-$($Task.runtime)" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "  3. Add tasks[].runtime before selecting an execution runtime." -Chinese "  3. 在选择执行运行时之前添加 tasks[].runtime。" -ForegroundColor DarkGray
    }

    Write-UIHost -English "  4. Run the agent or task command manually inside the selected workspace." -Chinese "  4. 在选定的工作区内手动运行 agent 或任务命令。" -ForegroundColor DarkGray
    Write-UIHost -English "     After manual execution starts, mark running only as local state:" -Chinese "     手动执行开始后，仅将运行状态标记为本地状态:" -ForegroundColor DarkGray
    Write-UIHost -English "     adpos workspace task mark $($Task.name) running -ManifestPath $ManifestPath" -Chinese "     adpos workspace task mark $($Task.name) running -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "  5. Validate before review:" -Chinese "  5. 审查前验证:" -ForegroundColor DarkGray
    Write-UIHost -English "     adpos workspace task validate $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adpos workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "  6. Move to review:" -Chinese "  6. 进入审查:" -ForegroundColor DarkGray
    Write-UIHost -English "     adpos workspace task review $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adpos workspace task review $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
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
    Write-UIHost -English "     adpos workspace status -ManifestPath $ManifestPath" -Chinese "     adpos workspace status -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "  3. Confirm checkpoint state:" -Chinese "  3. 确认检查点状态:" -ForegroundColor DarkGray
    Write-UIHost -English "     adpos workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adpos workspace task snapshot $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    if (Test-WorkspaceTaskRequiresSnapshot -Task $Task) {
        Write-UIHost -English "     Review should not accept broad agent work until the snapshot-first gate is ready or explicitly waived in local ADP-OS state." -Chinese "     在快照优先门控就绪或在本地 ADP-OS 状态中显式豁免之前，审查不应接受广泛的 agent 工作。" -ForegroundColor DarkGray
        Write-UIHost -English "     waiver: adpos workspace task mark $($Task.name) checkpoint-waived -ManifestPath $ManifestPath" -Chinese "     豁免: adpos workspace task mark $($Task.name) checkpoint-waived -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  4. Run or inspect validation commands:" -Chinese "  4. 运行或检查验证命令:" -ForegroundColor DarkGray
    Write-UIHost -English "     adpos workspace task validate $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adpos workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "     recorded validation: $validationStateText" -Chinese "     已记录的验证: $validationStateText" -ForegroundColor DarkGray
    Write-WorkspaceValidationDetailLines -RecordedState $recordedState
    Write-UIHost -English "     state file: $resolvedStatePath" -Chinese "     状态文件: $resolvedStatePath" -ForegroundColor DarkGray
    Write-UIHost -English "  5. Inspect source changes in the target project:" -Chinese "  5. 检查目标项目中的源更改:" -ForegroundColor DarkGray
    Write-UIHost -English "     git status --short" -Chinese "     git status --short" -ForegroundColor DarkGray
    Write-UIHost -English "     git diff --stat" -Chinese "     git diff --stat" -ForegroundColor DarkGray
    Write-UIHost -English "     git diff" -Chinese "     git diff" -ForegroundColor DarkGray
    Write-UIHost -English "  6. Decide explicitly:" -Chinese "  6. 显式决策:" -ForegroundColor DarkGray
    Write-UIHost -English "     rollback: adpos workspace task rollback $($Task.name) -ManifestPath $ManifestPath" -Chinese "     回滚: adpos workspace task rollback $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "     revise:   fix the task result and re-run validation" -Chinese "     修订:   修正任务结果并重新运行验证" -ForegroundColor DarkGray
    Write-UIHost -English "     commit:   adpos workspace task commit $($Task.name) -ManifestPath $ManifestPath" -Chinese "     提交:   adpos workspace task commit $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    if ($reviewDecision.Verdict -eq "validation passed") {
        Write-UIHost -English "     accept:   adpos workspace task mark $($Task.name) reviewed -ManifestPath $ManifestPath" -Chinese "     接受:   adpos workspace task mark $($Task.name) reviewed -ManifestPath $ManifestPath" -ForegroundColor DarkGray
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
            Write-UIHost -English "     adpos restore $($Task.runtime) $($Task.snapshot)" -Chinese "     adpos restore $($Task.runtime) $($Task.snapshot)" -ForegroundColor DarkGray
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
    Write-UIHost -English "     adpos workspace task mark $($Task.name) rollback -ManifestPath $ManifestPath" -Chinese "     adpos workspace task mark $($Task.name) rollback -ManifestPath $ManifestPath" -ForegroundColor DarkGray
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
    Write-UIHost -English "     adpos workspace task review $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adpos workspace task review $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "  2. Confirm validation expectations:" -Chinese "  2. 确认验证预期:" -ForegroundColor DarkGray
    Write-UIHost -English "     adpos workspace task validate $($Task.name) -ManifestPath $ManifestPath" -Chinese "     adpos workspace task validate $($Task.name) -ManifestPath $ManifestPath" -ForegroundColor DarkGray
    Write-UIHost -English "  3. Inspect source changes in the target project:" -Chinese "  3. 检查目标项目中的源更改:" -ForegroundColor DarkGray
    Write-UIHost -English "     git status --short" -Chinese "     git status --short" -ForegroundColor DarkGray
    Write-UIHost -English "     git diff --stat" -Chinese "     git diff --stat" -ForegroundColor DarkGray
    Write-UIHost -English "     git diff" -Chinese "     git diff" -ForegroundColor DarkGray
    if ($commitDecision.Verdict -eq "commit ready") {
        Write-UIHost -English "  4. Commit only after the human reviewer accepts the task result:" -Chinese "  4. 仅在人工审查者接受任务结果后才提交:" -ForegroundColor DarkGray
        Write-UIHost -English "     git add <paths>" -Chinese "     git add <paths>" -ForegroundColor DarkGray
        Write-UIHost -English "     git commit -m ""<message>""" -Chinese "     git commit -m ""<message>""" -ForegroundColor DarkGray
        Write-UIHost -English "  5. After the commit is created manually, record local committed state:" -Chinese "  5. 手动创建提交后，记录本地已提交状态:" -ForegroundColor DarkGray
        Write-UIHost -English "     adpos workspace task mark $($Task.name) committed -ManifestPath $ManifestPath" -Chinese "     adpos workspace task mark $($Task.name) committed -ManifestPath $ManifestPath" -ForegroundColor DarkGray
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

    $validStates = @("prepared", "checkpointed", "checkpoint-waived", "running", "validated", "validation_failed", "reviewed", "rollback", "committed")
    if ([string]::IsNullOrWhiteSpace($StateName) -or $StateName -notin $validStates) {
        Write-ErrorLog -Message "Unknown workspace task state: $StateName. Valid: $($validStates -join ', ')" -Component "cli.workspace"
        exit 1
    }

    $resolvedStatePath = Resolve-WorkspaceStatePath -Path $Path
    $state = Read-WorkspaceState -Path $resolvedStatePath
    if ($StateName -eq "checkpoint-waived") {
        $state = Set-WorkspaceTaskCheckpointWaiver -State $state -TaskName $Task.name
    } elseif ($StateName -in @("validated", "validation_failed")) {
        $status = if ($StateName -eq "validated") { "passed" } else { "failed" }
        $state = Set-WorkspaceTaskExternalValidation -State $state -TaskName $Task.name -ValidationStatus $status
    } else {
        $state = Set-WorkspaceTaskState -State $state -TaskName $Task.name -StateName $StateName
    }
    Write-WorkspaceState -State $state -Path $resolvedStatePath

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Workspace task mark: $($Task.name)" -Chinese "工作空间任务标记: $($Task.name)" -ForegroundColor Cyan
    if ($StateName -in @("validated", "validation_failed")) {
        Write-UIHost -English "Recorded external validation result as local lifecycle state. Validation was run outside ADP-OS; the recorded result satisfies review/commit readiness gates." -Chinese "记录了外部验证结果作为本地生命周期状态。验证在 ADP-OS 外运行；记录的结果满足审查/提交就绪门控。" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "Recorded local lifecycle state only. No VM, sync, snapshot, file, Git, or validation command was run." -Chinese "仅记录本地生命周期状态。未运行任何 VM、同步、快照、文件、Git 或验证命令。" -ForegroundColor DarkGray
    }
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
            Write-UIHost -English "  Boundary: validated records an external validation result (status: passed). Validation was run outside ADP-OS; the recorded result satisfies review/commit readiness gates. Use 'adpos workspace task validate <task> -Execute' to record executable validation evidence from inside ADP-OS." -Chinese "  边界: validated 记录了外部验证结果（状态: 通过）。验证在 ADP-OS 外运行；记录的结果满足审查/提交就绪门控。使用 'adpos workspace task validate <task> -Execute' 从 ADP-OS 内记录可执行验证证据。" -ForegroundColor Yellow
        }
        "validation_failed" {
            Write-UIHost -English "  Boundary: validation_failed records an external validation result (status: failed). Validation was run outside ADP-OS. The recorded failure blocks review/commit readiness until a passing result is recorded." -Chinese "  边界: validation_failed 记录了外部验证结果（状态: 失败）。验证在 ADP-OS 外运行。记录的失败会阻塞审查/提交就绪，直到记录通过结果。" -ForegroundColor Yellow
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
        [switch]$LocalExecution,
        [switch]$PlanOnly
    )

    $validTaskCommands = @("prepare", "snapshot", "run", "validate", "review", "rollback", "commit", "mark")
    if ([string]::IsNullOrWhiteSpace($Command) -or $Command -notin $validTaskCommands) {
        Write-ErrorLog -Message "Unknown workspace task command: $Command. Valid: $($validTaskCommands -join ', ')" -Component "cli.workspace"
        $suggestion = Get-ADPCommandSuggestion -InputCommand $Command -CandidateCommands $validTaskCommands
        if ($suggestion) {
            Write-UIHost -English "Did you mean: adpos workspace task $suggestion" -Chinese "你是不是想运行: adpos workspace task $suggestion" -ForegroundColor Cyan
        }
        exit 1
    }

    if (($ExecuteValidation -or $PlanOnly -or $LocalExecution) -and $Command -ne "validate") {
        Write-ErrorLog -Message "-Execute, -Local, and -Plan are only supported with: adpos workspace task validate <task-name>" -Component "cli.workspace"
        exit 1
    }

    if ($PlanOnly -and -not $ExecuteValidation -and -not $LocalExecution) {
        Write-ErrorLog -Message "-Plan is only supported with -Execute or -Local for workspace task validation." -Component "cli.workspace"
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
            Write-WorkspaceTaskValidate -Manifest $Manifest -Task $task -StatePath $LocalStatePath -ManifestPath $Path -ExecuteValidation:$ExecuteValidation -LocalExecution:$LocalExecution -PlanOnly:$PlanOnly
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
