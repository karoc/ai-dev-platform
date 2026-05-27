# ADP-OS Sync Command
# Workspace sync status and management (Mutagen integration)

param(
    [string]$SubCommand,
    [string]$RuntimeName
)

Write-InfoLog -Message "Sync command: $SubCommand $RuntimeName" -Component "cli.sync"

if (-not $SubCommand) {
    Write-ErrorLog -Message "Usage: adp sync <status|start|stop|list>" -Component "cli.sync"
    exit 1
}

$validSubCommands = @("status", "start", "stop", "list")
if ($SubCommand -notin $validSubCommands) {
    Write-ErrorLog -Message "Unknown sync command: $SubCommand. Valid: $($validSubCommands -join ', ')" -Component "cli.sync"
    exit 1
}

if ($SubCommand -in @("start", "stop")) {
    if (-not $RuntimeName) {
        Write-ErrorLog -Message "Usage: adp sync $SubCommand <runtime>" -Component "cli.sync"
        exit 1
    }
    if (-not (Test-RuntimeExists $RuntimeName)) {
        Write-ErrorLog -Message "Unknown runtime: $RuntimeName. Valid: $((Get-AllRuntimeNames) -join ', ')" -Component "cli.sync"
        exit 1
    }
}

Write-Host ""
Write-Host "ADP-OS Sync" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

. (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")

try {
    Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
} catch {
    Write-Host "Mutagen is not installed." -ForegroundColor Red
    Write-Host "  Download: https://github.com/mutagen-io/mutagen/releases" -ForegroundColor DarkGray
    Write-Host "  Place:    .tools\mutagen\mutagen.exe" -ForegroundColor DarkGray
    Write-Host "  Or add mutagen.exe to PATH." -ForegroundColor DarkGray
    Write-Host "  ADP helper: .\cli\adp.ps1 doctor -FixMutagen -Plan" -ForegroundColor DarkGray
    return
}

switch ($SubCommand) {
    "status" {
        Write-Host "Sync status:" -ForegroundColor Yellow
        Invoke-Mutagen -Arguments @("sync", "list")
    }
    "list" {
        Write-Host "Active sync sessions:" -ForegroundColor Yellow
        Invoke-Mutagen -Arguments @("sync", "list")
    }
    "start" {
        Write-Host "Starting sync for: $RuntimeName" -ForegroundColor Yellow
        $rt = Get-RuntimeConfig $RuntimeName
        $profile = Get-SyncProfile $rt.sync_profile
        $workspaceRoot = Resolve-Path "workspace_root"
        $localPath = Join-Path $workspaceRoot $rt.workspace
        $vmStore = Resolve-Path "vm_store"
        $vmName = "adp-$RuntimeName"
        $vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

        if (-not (Test-Path $vmxPath)) {
            Write-ErrorLog -Message "VM not found for runtime '$RuntimeName'. Run: adp up $RuntimeName" -Component "cli.sync"
            exit 1
        }

        Initialize-VMware | Out-Null
        $status = Get-VMStatus $vmxPath
        if ($status -notmatch "running") {
            Write-ErrorLog -Message "Runtime '$RuntimeName' is not running. Run: adp up $RuntimeName" -Component "cli.sync"
            exit 1
        }

        $ip = Get-RuntimeStaticIP $RuntimeName
        if (-not $ip) {
            $ip = Get-VMIP $vmxPath
        }
        if (-not $ip -or $ip -eq "0.0.0.0" -or $ip -match "unknown") {
            Write-ErrorLog -Message "Could not resolve VM IP for runtime '$RuntimeName'" -Component "cli.sync"
            exit 1
        }

        Write-Host "  Local:  $localPath" -ForegroundColor DarkGray
        Write-Host "  Remote: adp@${ip}:/home/adp/workspace" -ForegroundColor DarkGray
        Write-Host "  Mode:   $($profile.mode)" -ForegroundColor DarkGray

        $sessionName = "adp-$RuntimeName"
        $sshKeyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
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
        Write-Host "Stopping sync for: $RuntimeName" -ForegroundColor Yellow
        Stop-SyncSession -SessionName $sessionName
    }
}
