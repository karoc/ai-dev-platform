# ADP-OS Sync Command
# Workspace sync status and management (Mutagen integration)

param(
    [string]$SubCommand,
    [string]$RuntimeName
)

Write-InfoLog -Message "Sync command: $SubCommand $RuntimeName" -Component "cli.sync"

if (-not $SubCommand) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adpos sync <status|start|stop|list>" -Chinese "用法: adpos sync <status|start|stop|list>") -Component "cli.sync"
    exit 1
}

$validSubCommands = @("status", "start", "stop", "list")
if ($SubCommand -notin $validSubCommands) {
    Write-ErrorLog -Message (Get-UIText -English "Unknown sync command: $SubCommand. Valid: $($validSubCommands -join ', ')" -Chinese "未知同步命令: $SubCommand。可用: $($validSubCommands -join ', ')") -Component "cli.sync"
    exit 1
}

if ($SubCommand -in @("start", "stop")) {
    if (-not $RuntimeName) {
        Write-ErrorLog -Message (Get-UIText -English "Usage: adpos sync $SubCommand <runtime>" -Chinese "用法: adpos sync $SubCommand <runtime>") -Component "cli.sync"
        exit 1
    }
    if (-not (Test-RuntimeExists $RuntimeName)) {
        Write-ErrorLog -Message (Get-UIText -English "Unknown runtime: $RuntimeName. Valid: $((Get-AllRuntimeNames) -join ', ')" -Chinese "未知运行时: $RuntimeName。可用: $((Get-AllRuntimeNames) -join ', ')") -Component "cli.sync"
        exit 1
    }
}

Write-Host ""
Write-UIHost -English "ADP-OS Sync" -Chinese "ADP-OS 同步" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

. (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")
. (Join-Path (Get-ProjectRoot) "core\diagnostics\resource-conflicts.ps1")
. (Join-Path (Get-ProjectRoot) "core\diagnostics\ssh-alias.ps1")

function Get-SyncExpectedEndpoints {
    param([string]$TargetRuntime)

    $rt = Get-RuntimeConfig $TargetRuntime
    $workspaceRoot = Resolve-Path "workspace_root"
    $localPath = Join-Path $workspaceRoot $rt.workspace
    $sessionName = "adp-$TargetRuntime"
    $remoteUrl = "adp-os-$sessionName`:/home/adp/workspace"
    return [pscustomobject]@{
        SessionName = $sessionName
        LocalPath   = $localPath
        RemoteUrl   = $remoteUrl
    }
}

function Test-SyncAliasNeedsAttention {
    param([object]$AliasStatus)

    return ($AliasStatus.HasConflict -or $AliasStatus.Status -in @("missing-config", "missing-alias"))
}

function Format-SyncAliasDetail {
    param([object]$AliasStatus)

    if ($AliasStatus.Status -in @("missing-config", "missing-alias")) {
        return "$($AliasStatus.Status), expected $($AliasStatus.ExpectedHost):$($AliasStatus.ExpectedPort)"
    }

    return "$($AliasStatus.Status) ($($AliasStatus.ActualHost):$($AliasStatus.ActualPort), expected $($AliasStatus.ExpectedHost):$($AliasStatus.ExpectedPort))"
}

function Write-SyncRuntimeSummary {
    param([string]$TargetRuntime)

    $expected = Get-SyncExpectedEndpoints -TargetRuntime $TargetRuntime
    $resourceProfile = Get-ADPRuntimeResourceProfile -TargetRuntime $TargetRuntime
    $aliasStatus = Get-ADPSshAliasOwnershipStatus -Profile $resourceProfile -ExpectedHost $resourceProfile.StaticIp -ExpectedUser $resourceProfile.SshUser -ExpectedPort $resourceProfile.SshPort -ExpectedKeyPath $resourceProfile.SshKeyPath
    $statusResult = Get-VMStatus -Name $TargetRuntime
    $runtimeCreated = ($statusResult.Success -and $statusResult.Data -ne "not-created")
    try {
        $session = Get-SyncSessionInfo -SessionName $expected.SessionName -ExpectedLocalPath $expected.LocalPath -ExpectedRemoteUrl $expected.RemoteUrl
    } catch {
        Write-Host "  ${TargetRuntime}: status unavailable ($_)" -ForegroundColor Yellow
        return
    }

    if (-not $session.Exists) {
        Write-UIHost -English "  ${TargetRuntime}: not-started — run adpos sync start $TargetRuntime" -Chinese "  ${TargetRuntime}: 未启动 — 运行 adpos sync start $TargetRuntime" -ForegroundColor Yellow
        return
    }

    if (-not $runtimeCreated) {
        Write-UIHost -English "  ${TargetRuntime}: stale-session — existing session was found before this runtime was created in the current checkout" -Chinese "  ${TargetRuntime}: 陈旧会话 — 在当前检出中创建此运行时之前已存在该会话" -ForegroundColor Yellow
        Write-Host "    local:  $($session.AlphaUrl)" -ForegroundColor DarkGray
        Write-Host "    remote: $($session.BetaUrl)" -ForegroundColor DarkGray
        if (Test-SyncAliasNeedsAttention -AliasStatus $aliasStatus) {
            Write-Host "    alias:  $(Format-SyncAliasDetail -AliasStatus $aliasStatus)" -ForegroundColor Yellow
        }
        Write-Host "    cleanup: adpos sync stop $TargetRuntime" -ForegroundColor Yellow
        Write-Host "    next:    adpos up $TargetRuntime; adpos sync start $TargetRuntime" -ForegroundColor DarkGray
        return
    }

    $color = if ($session.Health -in @("healthy", "present")) { "Green" } else { "Red" }
    Write-Host "  ${TargetRuntime}: $($session.Health) — $($session.Detail)" -ForegroundColor $color
    Write-Host "    local:  $($session.AlphaUrl)" -ForegroundColor DarkGray
    Write-Host "    remote: $($session.BetaUrl)" -ForegroundColor DarkGray
    if (Test-SyncAliasNeedsAttention -AliasStatus $aliasStatus) {
        Write-Host "    alias:  $(Format-SyncAliasDetail -AliasStatus $aliasStatus)" -ForegroundColor Yellow
    }
    if ($session.Health -notin @("healthy", "present")) {
        Write-Host "    fix:    adpos sync stop $TargetRuntime; adpos sync start $TargetRuntime" -ForegroundColor Yellow
    }
}

try {
    Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
} catch {
    Write-UIHost -English "Mutagen is not installed." -Chinese "Mutagen 未安装。" -ForegroundColor Red
    Write-Host "  Download: https://github.com/mutagen-io/mutagen/releases" -ForegroundColor DarkGray
    Write-Host "  Place:    .tools\mutagen\mutagen.exe" -ForegroundColor DarkGray
    Write-Host "  Or add mutagen.exe to PATH." -ForegroundColor DarkGray
    Write-Host "  ADP helper: adpos doctor -FixMutagen -Plan" -ForegroundColor DarkGray
    return
}

switch ($SubCommand) {
    "status" {
        Write-UIHost -English "ADP runtime sync summary:" -Chinese "ADP 运行时同步摘要:" -ForegroundColor Yellow
        foreach ($name in (Get-AllRuntimeNames)) {
            Write-SyncRuntimeSummary -TargetRuntime $name
        }
        Write-Host ""
        Write-UIHost -English "Sync status:" -Chinese "同步状态:" -ForegroundColor Yellow
        Invoke-Mutagen -Arguments @("sync", "list")
    }
    "list" {
        Write-UIHost -English "Active sync sessions:" -Chinese "活跃的同步会话:" -ForegroundColor Yellow
        Invoke-Mutagen -Arguments @("sync", "list")
    }
    "start" {
        Write-UIHost -English "Starting sync for: $RuntimeName" -Chinese "正在启动同步: $RuntimeName" -ForegroundColor Yellow
        $rt = Get-RuntimeConfig $RuntimeName
        $profile = Get-SyncProfile $rt.sync_profile
        $workspaceRoot = Resolve-Path "workspace_root"
        $localPath = Join-Path $workspaceRoot $rt.workspace
        $statusResult = Get-VMStatus -Name $RuntimeName
        $resourceProfile = Get-ADPRuntimeResourceProfile -TargetRuntime $RuntimeName
        $runningVmxPaths = Get-ADPRunningVmxPathsForResourceCheck
        $resourceConflict = Get-ADPRuntimeDuplicateConflict -TargetRuntime $RuntimeName -ManagedVmxPath $resourceProfile.VmxPath -RunningVmxPaths $runningVmxPaths
        if ($resourceConflict.HasDuplicateRunningVm) {
            Write-ADPRuntimeResourceConflictGuidance -Profile $resourceProfile -Conflict $resourceConflict -CommandContext (Get-ADPCheckoutCommandContext) -Action "sync start"
            Write-ErrorLog -Message (Get-UIText -English "Runtime '$RuntimeName' has a duplicate running VM. Stop the stale duplicate or isolate this checkout before starting sync." -Chinese "运行时 '$RuntimeName' 存在重复运行的 VM。请先停止 stale duplicate，或隔离当前 checkout 后再启动同步。") -Component "cli.sync"
            exit 1
        }
        $vmCreated = ($statusResult.Success -and $statusResult.Data -ne "not-created")

        if (-not $vmCreated) {
            Write-ErrorLog -Message (Get-UIText -English "VM not found for runtime '$RuntimeName'. Run: adpos up $RuntimeName" -Chinese "运行时 '$RuntimeName' 的 VM 未找到。请运行: adpos up $RuntimeName") -Component "cli.sync"
            exit 1
        }

        $status = if ($statusResult.Success) { $statusResult.Data } else { "unknown" }
        if ($status -notmatch "running") {
            Write-ErrorLog -Message (Get-UIText -English "Runtime '$RuntimeName' is not running. Run: adpos up $RuntimeName" -Chinese "运行时 '$RuntimeName' 未运行。请运行: adpos up $RuntimeName") -Component "cli.sync"
            exit 1
        }

        $ip = Get-RuntimeStaticIP $RuntimeName
        if (-not $ip) {
            $ipResult = Get-VMIP -Name $RuntimeName
            if ($ipResult.Success) {
                $ip = $ipResult.Data
            }
        }
        if (-not $ip -or $ip -eq "0.0.0.0" -or $ip -match "unknown") {
            Write-ErrorLog -Message (Get-UIText -English "Could not resolve VM IP for runtime '$RuntimeName'" -Chinese "无法解析运行时 '$RuntimeName' 的 VM IP") -Component "cli.sync"
            exit 1
        }

        Write-Host "  Local:  $localPath" -ForegroundColor DarkGray
        Write-Host "  Remote: adp@${ip}:/home/adp/workspace" -ForegroundColor DarkGray
        Write-Host "  Mode:   $($profile.mode)" -ForegroundColor DarkGray

        $sessionName = "adp-$RuntimeName"
        $sshKeyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
        $expectedRemoteUrl = "adp-os-$sessionName`:/home/adp/workspace"
        $existingSession = Get-SyncSessionInfo -SessionName $sessionName -ExpectedLocalPath $localPath -ExpectedRemoteUrl $expectedRemoteUrl
        $aliasStatus = Get-ADPSshAliasOwnershipStatus -Profile $resourceProfile -ExpectedHost $ip -ExpectedUser $resourceProfile.SshUser -ExpectedPort $resourceProfile.SshPort -ExpectedKeyPath $sshKeyPath
        if ($existingSession.Exists -and $existingSession.Health -in @("healthy", "present")) {
            if ($aliasStatus.HasConflict) {
                Write-ADPSshAliasOwnershipGuidance -AliasStatus $aliasStatus -CommandContext (Get-ADPCheckoutCommandContext) -Action "sync start"
                Write-ErrorLog -Message (Get-UIText -English "Existing sync session '$sessionName' uses an SSH alias that points to a different target. Stop/recreate the session or run sync start from the checkout that should own it." -Chinese "现有同步会话 '$sessionName' 使用的 SSH alias 指向不同目标。请停止并重建该会话，或从应该拥有它的 checkout 运行 sync start。") -Component "cli.sync"
                exit 1
            }
            if ($aliasStatus.Status -in @("missing-config", "missing-alias")) {
                Set-MutagenSSHHostConfig -HostAlias $resourceProfile.SshAlias -SSHHost $ip -SSHUser $resourceProfile.SshUser -SSHPort $resourceProfile.SshPort -SSHKeyPath $sshKeyPath | Out-Null
                Write-UIHost -English "  SSH alias refreshed: $($resourceProfile.SshAlias) -> $ip" -Chinese "  SSH alias 已刷新: $($resourceProfile.SshAlias) -> $ip" -ForegroundColor Green
            }
        }
        New-SyncSession `
            -SessionName $sessionName `
            -LocalPath $localPath `
            -RemotePath "/home/adp/workspace" `
            -SSHHost $ip `
            -SSHPort $rt.ssh_port `
            -Mode $profile.mode `
            -Ignore $profile.ignore `
            -SSHKeyPath $sshKeyPath
    }
    "stop" {
        $sessionName = "adp-$RuntimeName"
        Write-UIHost -English "Stopping sync for: $RuntimeName" -Chinese "正在停止同步: $RuntimeName" -ForegroundColor Yellow
        Stop-SyncSession -SessionName $sessionName
    }
}
