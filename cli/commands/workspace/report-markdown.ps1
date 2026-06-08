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
