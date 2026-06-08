# ADP-OS workspace external probe policy.

function Test-ADPWorkspaceExternalProbeCommand {
    param(
        [string]$SubCommand,
        [string]$TaskCommand,
        [switch]$ExecuteValidation,
        [switch]$LocalExecution
    )

    $command = if ([string]::IsNullOrWhiteSpace($SubCommand)) { "" } else { $SubCommand.ToLowerInvariant() }
    if ($command -ne "task") {
        return $false
    }

    $task = if ([string]::IsNullOrWhiteSpace($TaskCommand)) { "" } else { $TaskCommand.ToLowerInvariant() }
    return ($task -eq "validate" -and $ExecuteValidation -and -not $LocalExecution)
}

function Set-ADPWorkspaceExternalProbePolicy {
    param(
        [string]$SubCommand,
        [string]$TaskCommand,
        [switch]$ExecuteValidation,
        [switch]$LocalExecution
    )

    $global:ADPWorkspaceAllowExternalProbes = Test-ADPWorkspaceExternalProbeCommand `
        -SubCommand $SubCommand `
        -TaskCommand $TaskCommand `
        -ExecuteValidation:$ExecuteValidation `
        -LocalExecution:$LocalExecution
}

function Test-ADPWorkspaceExternalProbeAllowed {
    $flag = Get-Variable -Name ADPWorkspaceAllowExternalProbes -Scope Global -ErrorAction SilentlyContinue
    return ($flag -and [bool]$flag.Value)
}

function New-ADPWorkspaceProbeSkippedStatus {
    param(
        [ValidateSet("runtime", "sync", "snapshot")]
        [string]$Kind,
        [string]$RuntimeName,
        [string]$SnapshotName
    )

    switch ($Kind) {
        "runtime" {
            return [pscustomobject]@{
                Level  = "WARN"
                Status = "created, not checked"
                Detail = "external provider probe skipped; run adpos status $RuntimeName for live state"
            }
        }
        "sync" {
            return [pscustomobject]@{
                Level  = "INFO"
                Status = "not checked"
                Detail = "external sync probe skipped; run adpos sync status $RuntimeName"
            }
        }
        "snapshot" {
            $target = if ([string]::IsNullOrWhiteSpace($SnapshotName)) { $RuntimeName } else { "$RuntimeName/$SnapshotName" }
            return [pscustomobject]@{
                Level  = "WARN"
                Status = "not checked"
                Detail = "external snapshot probe skipped: $target"
            }
        }
    }
}

function Get-RuntimeVmxPath {
    param([string]$RuntimeName)

    $vmStore = Resolve-Path "vm_store"
    $vmName = "adp-$RuntimeName"
    return (Join-Path $vmStore "$vmName\$vmName.vmx")
}

function Get-WorkspaceRuntimeStatus {
    param([string]$RuntimeName)

    if ([string]::IsNullOrWhiteSpace($RuntimeName)) {
        return [pscustomobject]@{
            Level  = "FAIL"
            Status = "missing runtime"
            Detail = "Set projects[].runtime"
        }
    }

    if (-not (Test-RuntimeExists $RuntimeName)) {
        return [pscustomobject]@{
            Level  = "FAIL"
            Status = "unknown runtime"
            Detail = "Valid: $((Get-AllRuntimeNames) -join ', ')"
        }
    }

    $vmxPath = Get-RuntimeVmxPath -RuntimeName $RuntimeName
    if (-not (Test-Path -LiteralPath $vmxPath)) {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "not created"
            Detail = "Run: adpos up $RuntimeName -Plan"
        }
    }

    if (-not (Test-ADPWorkspaceExternalProbeAllowed)) {
        return New-ADPWorkspaceProbeSkippedStatus -Kind "runtime" -RuntimeName $RuntimeName
    }

    try {
        $statusResult = Get-VMStatus -Name $RuntimeName
        if (-not $statusResult.Success) {
            return [pscustomobject]@{
                Level  = "WARN"
                Status = "created, status unknown"
                Detail = "Provider query failed: $($statusResult.Error)"
            }
        }
        $status = $statusResult.Data
        $level = if ($status -match "running") { "OK" } else { "WARN" }
        return [pscustomobject]@{
            Level  = $level
            Status = $status
            Detail = $vmxPath
        }
    } catch {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "status unavailable"
            Detail = "$_"
        }
    }
}

function Get-WorkspaceSyncStatus {
    param(
        [string]$RuntimeName,
        [bool]$Expected
    )

    if (-not $Expected) {
        return [pscustomobject]@{
            Level  = "INFO"
            Status = "not requested"
            Detail = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($RuntimeName)) {
        return [pscustomobject]@{
            Level  = "FAIL"
            Status = "blocked"
            Detail = "missing runtime"
        }
    }

    if (-not (Test-RuntimeExists $RuntimeName)) {
        return [pscustomobject]@{
            Level  = "FAIL"
            Status = "blocked"
            Detail = "unknown runtime"
        }
    }

    if (-not (Test-ADPWorkspaceExternalProbeAllowed)) {
        return New-ADPWorkspaceProbeSkippedStatus -Kind "sync" -RuntimeName $RuntimeName
    }

    . (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")
    $mutagenPath = Find-Mutagen -ProjectRoot (Get-ProjectRoot)
    if (-not $mutagenPath) {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "unknown"
            Detail = "Mutagen not installed"
        }
    }

    try {
        Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
        $sessionName = "adp-$RuntimeName"
        if (Test-SyncSessionExists -SessionName $sessionName) {
            return [pscustomobject]@{
                Level  = "OK"
                Status = "session present"
                Detail = $sessionName
            }
        }

        return [pscustomobject]@{
            Level  = "WARN"
            Status = "not started"
            Detail = "Run: adpos sync start $RuntimeName"
        }
    } catch {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "status unavailable"
            Detail = "$_"
        }
    }
}

function Get-WorkspaceSnapshotStatus {
    param(
        [string]$RuntimeName,
        [string]$SnapshotName
    )

    if ([string]::IsNullOrWhiteSpace($RuntimeName) -or [string]::IsNullOrWhiteSpace($SnapshotName)) {
        return [pscustomobject]@{
            Level  = "INFO"
            Status = "not configured"
            Detail = ""
        }
    }

    if (-not (Test-RuntimeExists $RuntimeName)) {
        return [pscustomobject]@{
            Level  = "FAIL"
            Status = "blocked"
            Detail = "unknown runtime"
        }
    }

    $vmxPath = Get-RuntimeVmxPath -RuntimeName $RuntimeName
    if (-not (Test-Path -LiteralPath $vmxPath)) {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "not available"
            Detail = "VM not created"
        }
    }

    if (-not (Test-ADPWorkspaceExternalProbeAllowed)) {
        return New-ADPWorkspaceProbeSkippedStatus -Kind "snapshot" -RuntimeName $RuntimeName -SnapshotName $SnapshotName
    }

    try {
        $snapshotResult = Get-SnapshotList -Name $RuntimeName
        $snapshots = if ($snapshotResult.Success) { @($snapshotResult.Data) } else { @() }
        if ($snapshots -contains $SnapshotName) {
            return [pscustomobject]@{
                Level  = "OK"
                Status = "present"
                Detail = $SnapshotName
            }
        }

        return [pscustomobject]@{
            Level  = "WARN"
            Status = "recommended"
            Detail = "Run: adpos snapshot create $RuntimeName $SnapshotName"
        }
    } catch {
        return [pscustomobject]@{
            Level  = "WARN"
            Status = "status unavailable"
            Detail = "$_"
        }
    }
}
