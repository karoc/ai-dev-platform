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

function Set-WorkspaceTaskExternalValidation {
    param(
        [object]$State,
        [string]$TaskName,
        [string]$ValidationStatus
    )

    $tasks = [System.Collections.Generic.List[object]]::new()
    $updated = $false
    $timestamp = (Get-Date).ToUniversalTime().ToString("o")
    $stateName = if ($ValidationStatus -eq "passed") { "validated" } else { "validation_failed" }

    $validation = [pscustomobject]@{
        status       = $ValidationStatus
        completed_at = $timestamp
        source       = "external"
        note         = "marked manually via adpos workspace task mark — validation was run outside ADP-OS"
    }

    foreach ($taskState in (Get-WorkspaceArray $State.tasks)) {
        if ($taskState.name -eq $TaskName) {
            $taskState | Add-Member -NotePropertyName "state" -NotePropertyValue $stateName -Force
            $taskState | Add-Member -NotePropertyName "updated_at" -NotePropertyValue $timestamp -Force
            $taskState | Add-Member -NotePropertyName "validation" -NotePropertyValue $validation -Force
            $updated = $true
        }
        $tasks.Add($taskState) | Out-Null
    }

    if (-not $updated) {
        $tasks.Add([pscustomobject]@{
            name       = $TaskName
            state      = $stateName
            updated_at = $timestamp
            validation = $validation
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
                NextStep = "run adpos workspace task validate $($Task.name) -Execute or explicitly review outside ADP-OS"
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
            NextStep = "run adpos workspace task validate $($Task.name) -Execute before commit"
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
        NextStep = "run adpos workspace task review $($Task.name), then mark reviewed when accepted"
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
    if ($validation.PSObject.Properties.Name -contains "source" -and [string]$validation.source -eq "external") {
        Write-UIHost -English "     validation source: external (marked manually — validation was run outside ADP-OS)" -Chinese "     验证来源: 外部（手动标记 — 验证在 ADP-OS 外运行）" -ForegroundColor DarkGray
        if ($validation.PSObject.Properties.Name -contains "note" -and -not [string]::IsNullOrWhiteSpace([string]$validation.note)) {
            Write-UIHost -English "     note: $($validation.note)" -Chinese "     备注: $($validation.note)" -ForegroundColor DarkGray
        }
    }
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
