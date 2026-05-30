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

    $sshOutput = & ssh -i $keyPath `
        -o StrictHostKeyChecking=no `
        -o UserKnownHostsFile=NUL `
        -o IdentitiesOnly=yes `
        -o ConnectTimeout=5 `
        -o BatchMode=yes `
        -p $Port `
        "adp@$HostAddress" `
        "echo ok" 2>&1

    $sshExit = $LASTEXITCODE
    $global:LASTEXITCODE = 0
    $sshText = ($sshOutput | Where-Object { $_ }) -join "`n"

    if ($sshExit -eq 0) {
        return "reachable"
    }
    if ($sshExit -eq 255 -and $sshText -match "Permission denied") {
        return "auth-pending"
    }

    return "unreachable"
}

function Get-StatusSyncState {
    param(
        [string]$TargetRuntime,
        [bool]$MutagenAvailable,
        [string]$ExpectedLocalPath,
        [string]$ExpectedRemoteUrl,
        [bool]$RuntimeCreated
    )

    if (-not $MutagenAvailable) {
        return "mutagen-unavailable"
    }

    $sessionName = "adp-$TargetRuntime"
    try {
        $session = Get-SyncSessionInfo -SessionName $sessionName -ExpectedLocalPath $ExpectedLocalPath -ExpectedRemoteUrl $ExpectedRemoteUrl
        if (-not $session.Exists) {
            return "not-started"
        }
        if (-not $RuntimeCreated) {
            return "stale-session"
        }
        if ($session.Health -eq "healthy") {
            return "healthy"
        }
        if ($session.Health -eq "present") {
            return "present"
        }
        return $session.Health
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

function Write-StatusNetworkDriftRemediation {
    param(
        [string]$TargetRuntime,
        [object]$SeedNetwork,
        [string]$ConfiguredIp
    )

    Write-Host "  remediation:" -ForegroundColor Yellow
    Write-Host "    1. Rebuild when the VM can be recreated: adp destroy $TargetRuntime -Plan, then recreate with adp up $TargetRuntime." -ForegroundColor Yellow
    Write-Host "    2. In-place guest fix when the seed-era address is reachable: adp network apply $TargetRuntime -Plan." -ForegroundColor Yellow
    Write-Host "    3. Admin-only temporary host-route workaround only to regain SSH to $($SeedNetwork.Address); ADP will not apply host routes automatically." -ForegroundColor Yellow
    Write-Host "    Seed-era network: $($SeedNetwork.Address)/$($SeedNetwork.Prefix)$(if ($SeedNetwork.Gateway) { ', gateway ' + $SeedNetwork.Gateway } else { '' }); target: $ConfiguredIp." -ForegroundColor DarkGray
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
    $seedNetwork = Get-StatusSeedNetwork -TargetRuntime $TargetRuntime
    $alias = "adp-os-adp-$TargetRuntime"
    $workspaceRoot = Resolve-Path "workspace_root"
    $workspacePath = Join-Path $workspaceRoot $rt.workspace
    $expectedRemoteUrl = "${alias}:/home/adp/workspace"
    $runtimeCreated = ($state.Status -ne "not-created")
    $syncState = Get-StatusSyncState -TargetRuntime $TargetRuntime -MutagenAvailable $MutagenAvailable -ExpectedLocalPath $workspacePath -ExpectedRemoteUrl $expectedRemoteUrl -RuntimeCreated $runtimeCreated
    $adpRunningVms = @()
    if ($VmwareAvailable) {
        $adpRunningVms = @(Get-ADPRunningRuntimeVMs -RunningVmxPaths $RunningVmxPaths -RuntimeName $TargetRuntime -ManagedVmxPath $state.VmxPath)
    }
    $duplicateRunningVms = @($adpRunningVms | Where-Object { -not $_.IsManagedByCurrentCheckout })
    $hasDuplicateRunningVm = ($adpRunningVms.Count -gt 1 -or $duplicateRunningVms.Count -gt 0)
    $sshState = if ($hasDuplicateRunningVm) {
        "ambiguous-duplicate"
    } elseif ($state.Status -match "running") {
        Test-StatusSSHReachable -HostAddress $connectIp -Port $port
    } else {
        "skipped"
    }

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
        Write-StatusNetworkDriftRemediation -TargetRuntime $TargetRuntime -SeedNetwork $seedNetwork -ConfiguredIp $configuredIp
    }
    Write-Host "  ssh:           $sshState" -ForegroundColor DarkGray
    if ($sshState -eq "auth-pending") {
        Write-Host "  note:          SSH port is open, but the ADP key is not accepted yet. During autoinstall this usually means the installer or first boot is still preparing the target user." -ForegroundColor Yellow
    }
    if ($hasDuplicateRunningVm) {
        Write-Host "  duplicate VM:  running ADP runtime name also found outside this checkout" -ForegroundColor Red
        Write-Host "  current VMX:   $($state.VmxPath)" -ForegroundColor DarkGray
        foreach ($vm in $adpRunningVms) {
            $owner = if ($vm.IsManagedByCurrentCheckout) { "current checkout" } else { "other checkout or stale VM" }
            Write-Host "  running VMX:   $($vm.NormalizedVmxPath) [$owner]" -ForegroundColor Yellow
        }
        Write-Host "  remediation:   stop or rename the stale duplicate before diagnosing SSH or network issues" -ForegroundColor Yellow
    }
    Write-Host "  sync:          $syncState" -ForegroundColor DarkGray
    if ($syncState -in @("wrong-local", "wrong-remote", "unhealthy")) {
        Write-Host "  sync note:     existing Mutagen session is not usable for this checkout/runtime" -ForegroundColor Yellow
        Write-Host "  sync fix:      adp sync stop $TargetRuntime; adp sync start $TargetRuntime" -ForegroundColor Yellow
    } elseif ($syncState -eq "stale-session") {
        Write-Host "  sync note:     old Mutagen session exists, but this runtime is not created in the current checkout" -ForegroundColor Yellow
        Write-Host "  sync cleanup:  adp sync stop $TargetRuntime" -ForegroundColor Yellow
        Write-Host "  sync next:     adp up $TargetRuntime; adp sync start $TargetRuntime" -ForegroundColor DarkGray
    }
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
