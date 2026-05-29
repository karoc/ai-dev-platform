# ADP-OS Status Command
# Shows runtime status and connection details without changing VM, sync, or guest state.

param(
    [string]$RuntimeName
)

$ErrorActionPreference = "Stop"

if ($RuntimeName -and -not (Test-RuntimeExists $RuntimeName)) {
    Write-ErrorLog -Message "Unknown runtime: $RuntimeName. Valid: $((Get-AllRuntimeNames) -join ', ')" -Component "cli.status"
    exit 1
}

. (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")

function Get-StatusVmxPath {
    param([string]$TargetRuntime)

    $vmStore = Resolve-Path "vm_store"
    $vmName = "adp-$TargetRuntime"
    return (Join-Path $vmStore "$vmName\$vmName.vmx")
}

function Get-StatusRuntimeState {
    param(
        [string]$TargetRuntime,
        [bool]$VmwareAvailable,
        [string[]]$RunningVmxPaths
    )

    $vmxPath = Get-StatusVmxPath -TargetRuntime $TargetRuntime
    if (-not (Test-Path -LiteralPath $vmxPath)) {
        return [pscustomobject]@{
            Status     = "not-created"
            DetectedIp = ""
            VmxPath    = $vmxPath
        }
    }

    if (-not $VmwareAvailable) {
        return [pscustomobject]@{
            Status     = "exists-vmware-unavailable"
            DetectedIp = ""
            VmxPath    = $vmxPath
        }
    }

    $fullVmxPath = [System.IO.Path]::GetFullPath($vmxPath)
    $status = if ($RunningVmxPaths -contains $fullVmxPath) { "running" } else { "stopped" }
    $detectedIp = ""
    try {
        $quick = Invoke-Vmrun -Arguments @("getGuestIPAddress", $vmxPath) -TimeoutSeconds 5
        if ($quick.Success) {
            $detectedIp = Select-VMIPv4FromText -Text $quick.StdOut
        }
        if (-not $detectedIp) {
            $detectedIp = Get-VMIPFromDhcpLeases -VmxPath $vmxPath
        }
        if ($detectedIp) {
            $status = "running"
        }
    } catch {
        $detectedIp = ""
    }

    return [pscustomobject]@{
        Status     = $status
        DetectedIp = $detectedIp
        VmxPath    = $vmxPath
    }
}

function Test-StatusSSHReachable {
    param(
        [string]$HostAddress,
        [int]$Port = 22
    )

    if ([string]::IsNullOrWhiteSpace($HostAddress)) {
        return "not-configured"
    }

    if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
        return "ssh-unavailable"
    }

    $keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
    if (-not (Test-Path -LiteralPath $keyPath)) {
        return "key-missing"
    }

    & ssh -i $keyPath `
        -o StrictHostKeyChecking=no `
        -o UserKnownHostsFile=NUL `
        -o IdentitiesOnly=yes `
        -o ConnectTimeout=5 `
        -o BatchMode=yes `
        -p $Port `
        "adp@$HostAddress" `
        "echo ok" 2>$null | Out-Null

    if ($LASTEXITCODE -eq 0) {
        return "reachable"
    }

    return "unreachable"
}

function Get-StatusSyncState {
    param(
        [string]$TargetRuntime,
        [bool]$MutagenAvailable
    )

    if (-not $MutagenAvailable) {
        return "mutagen-unavailable"
    }

    $sessionName = "adp-$TargetRuntime"
    try {
        if (Test-SyncSessionExists -SessionName $sessionName) {
            return "present"
        }
        return "not-started"
    } catch {
        return "unknown"
    }
}

function Get-StatusSeedNetwork {
    param([string]$TargetRuntime)

    $vmStore = Resolve-Path "vm_store"
    $seedUserData = Join-Path $vmStore "seeds\$TargetRuntime\user-data"
    if (-not (Test-Path -LiteralPath $seedUserData)) {
        return $null
    }

    $text = Get-Content -LiteralPath $seedUserData -Raw -ErrorAction SilentlyContinue
    if ([string]::IsNullOrWhiteSpace($text)) {
        return $null
    }

    $address = ""
    $prefix = ""
    $gateway = ""
    if ($text -match '(?m)^\s*-\s*((?:\d{1,3}\.){3}\d{1,3})/(\d{1,2})\s*$') {
        $address = $matches[1]
        $prefix = $matches[2]
    }
    if ($text -match '(?m)^\s*via:\s*((?:\d{1,3}\.){3}\d{1,3})\s*$') {
        $gateway = $matches[1]
    }

    if (-not $address -and -not $gateway) {
        return $null
    }

    return [pscustomobject]@{
        Address = $address
        Prefix  = $prefix
        Gateway = $gateway
        Path    = $seedUserData
    }
}

function Write-StatusRuntime {
    param(
        [string]$TargetRuntime,
        [bool]$VmwareAvailable,
        [bool]$MutagenAvailable,
        [string[]]$RunningVmxPaths,
        [string]$AdminUser,
        [string]$KeyPath
    )

    $rt = Get-RuntimeConfig $TargetRuntime
    $state = Get-StatusRuntimeState -TargetRuntime $TargetRuntime -VmwareAvailable $VmwareAvailable -RunningVmxPaths $RunningVmxPaths
    $configuredIp = Get-RuntimeStaticIP $TargetRuntime
    $connectIp = if ($configuredIp) { $configuredIp } else { $state.DetectedIp }
    $port = if ($rt.PSObject.Properties.Name -contains "ssh_port" -and $rt.ssh_port) { [int]$rt.ssh_port } else { 22 }
    $sshState = if ($state.Status -match "running") { Test-StatusSSHReachable -HostAddress $connectIp -Port $port } else { "skipped" }
    $syncState = Get-StatusSyncState -TargetRuntime $TargetRuntime -MutagenAvailable $MutagenAvailable
    $seedNetwork = Get-StatusSeedNetwork -TargetRuntime $TargetRuntime
    $alias = "adp-os-adp-$TargetRuntime"
    $workspaceRoot = Resolve-Path "workspace_root"
    $workspacePath = Join-Path $workspaceRoot $rt.workspace

    Write-Host "$TargetRuntime" -ForegroundColor Yellow
    Write-Host "  status:        $($state.Status)" -ForegroundColor DarkGray
    Write-Host "  configured IP: $(if ($configuredIp) { $configuredIp } else { 'not configured' })" -ForegroundColor DarkGray
    if ($state.DetectedIp) {
        Write-Host "  detected IP:   $($state.DetectedIp)" -ForegroundColor DarkGray
        if ($configuredIp -and $state.DetectedIp -ne $configuredIp) {
            Write-Host "  note:          VMware detected $($state.DetectedIp), but ADP-OS will use configured static IP $configuredIp" -ForegroundColor Yellow
        }
    } elseif ($state.Status -match "running") {
        Write-Host "  detected IP:   unavailable" -ForegroundColor Yellow
    }
    if ($seedNetwork -and $configuredIp -and $seedNetwork.Address -and $seedNetwork.Address -ne $configuredIp) {
        Write-Host "  network drift: seed uses $($seedNetwork.Address)/$($seedNetwork.Prefix), current config uses $configuredIp" -ForegroundColor Red
        Write-Host "  remediation:   rebuild this runtime or update guest networking from the seed-era address" -ForegroundColor Yellow
    }
    Write-Host "  ssh:           $sshState" -ForegroundColor DarkGray
    Write-Host "  sync:          $syncState" -ForegroundColor DarkGray
    Write-Host "  workspace:     $workspacePath" -ForegroundColor DarkGray
    Write-Host "  VMX:           $($state.VmxPath)" -ForegroundColor DarkGray
    if ($connectIp) {
        Write-Host "  connect:       ssh -i $KeyPath -p $port $AdminUser@$connectIp" -ForegroundColor Cyan
        Write-Host "  alias:         ssh $alias" -ForegroundColor DarkGray
    } else {
        Write-Host "  connect:       unavailable until a static IP or detected guest IP is available" -ForegroundColor Yellow
    }
    Write-Host "  next:          adp up $TargetRuntime | adp sync start $TargetRuntime | adp doctor" -ForegroundColor DarkGray
    Write-Host ""
}

Write-Host ""
Write-Host "ADP-OS Status" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Status only: no VMs, sync sessions, snapshots, guest files, or workspace files will be changed." -ForegroundColor Cyan
Write-Host ""

$config = Get-PlatformConfig
$localConfigStatus = Get-LocalConfigStatus
$adminUser = if ($config.defaults.admin_user) { [string]$config.defaults.admin_user } else { "adp" }
$keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"

if ($localConfigStatus.Exists) {
    if ($localConfigStatus.Empty) {
        Write-Host "Local config: empty, ignored ($($localConfigStatus.Path))" -ForegroundColor DarkGray
    } elseif ($localConfigStatus.Applied) {
        Write-Host "Local config: applied sections $($localConfigStatus.Sections -join ', ') ($($localConfigStatus.Path))" -ForegroundColor DarkGray
    } else {
        Write-Host "Local config: present, no supported sections ($($localConfigStatus.Path))" -ForegroundColor Yellow
    }
} else {
    Write-Host "Local config: not present, using committed defaults" -ForegroundColor DarkGray
}

if ($config.network.vmware_nat) {
    Write-Host "Network:      $($config.network.vmware_nat.cidr), gateway $($config.network.vmware_nat.gateway)" -ForegroundColor DarkGray
}
Write-Host "SSH key:      $keyPath" -ForegroundColor DarkGray
Write-Host ""

$vmwareAvailable = Test-VMwareAvailable
$runningVmxPaths = @()
if ($vmwareAvailable) {
    Initialize-VMware | Out-Null
    try {
        $runningVmxPaths = @(Get-RunningVMs | ForEach-Object { [System.IO.Path]::GetFullPath($_) })
    } catch {
        $runningVmxPaths = @()
    }
} else {
    Write-Host "VMware:      unavailable; VM status is limited to local VMX presence." -ForegroundColor Yellow
    Write-Host ""
}

$mutagenAvailable = $false
try {
    Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
    $mutagenAvailable = $true
} catch {
    $mutagenAvailable = $false
}

$targets = if ($RuntimeName) { @($RuntimeName) } else { Get-AllRuntimeNames }
foreach ($target in $targets) {
    Write-StatusRuntime -TargetRuntime $target -VmwareAvailable $vmwareAvailable -MutagenAvailable $mutagenAvailable -RunningVmxPaths $runningVmxPaths -AdminUser $adminUser -KeyPath $keyPath
}
