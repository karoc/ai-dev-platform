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