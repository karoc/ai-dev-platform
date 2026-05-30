# ADP-OS Doctor Command
# System diagnostics — checks all dependencies and platform health

param(
    [switch]$FirstRun,
    [switch]$FixMutagen,
    [switch]$Plan
)

Write-InfoLog -Message "Running: adp doctor" -Component "cli.doctor"

. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\vm-factory.ps1")
. (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")

if ($Plan -and -not $FixMutagen) {
    Write-ErrorLog -Message "-Plan is only supported with -FixMutagen." -Component "cli.doctor"
    exit 1
}

Write-Host ""
Write-Host "ADP-OS Doctor — System Diagnostics" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$script:issues = @()
$script:ok = @()
$script:info = @()

function Test-Check {
    param(
        [string]$Name,
        [bool]$Condition,
        [string]$Detail = ""
    )

    if ($Condition) {
        Write-Host "  [OK]    $Name $Detail" -ForegroundColor Green
        $script:ok += $Name
    } else {
        Write-Host "  [FAIL]  $Name $Detail" -ForegroundColor Red
        $script:issues += $Name
    }
}

function Write-InfoCheck {
    param(
        [string]$Name,
        [string]$Detail = ""
    )

    Write-Host "  [INFO]  $Name $Detail" -ForegroundColor DarkGray
    $script:info += $Name
}

function Test-IPv4InCidr {
    param(
        [string]$Address,
        [string]$Cidr
    )

    if ([string]::IsNullOrWhiteSpace($Address) -or [string]::IsNullOrWhiteSpace($Cidr)) {
        return $false
    }

    $parts = $Cidr -split '/', 2
    if ($parts.Count -ne 2) {
        return $false
    }

    $ip = $null
    $network = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$ip)) {
        return $false
    }
    if (-not [System.Net.IPAddress]::TryParse($parts[0], [ref]$network)) {
        return $false
    }
    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork -or $network.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }

    $prefix = 0
    if (-not [int]::TryParse($parts[1], [ref]$prefix) -or $prefix -lt 0 -or $prefix -gt 32) {
        return $false
    }

    $ipBytes = $ip.GetAddressBytes()
    $networkBytes = $network.GetAddressBytes()
    [array]::Reverse($ipBytes)
    [array]::Reverse($networkBytes)
    $ipInt = [BitConverter]::ToUInt32($ipBytes, 0)
    $networkInt = [BitConverter]::ToUInt32($networkBytes, 0)
    $mask = if ($prefix -eq 0) { [uint32]0 } else { [uint32]::MaxValue -shl (32 - $prefix) }

    return (($ipInt -band $mask) -eq ($networkInt -band $mask))
}

function Test-RuntimeSSHReachable {
    param(
        [string]$HostAddress,
        [int]$Port = 22
    )

    $keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
    if (-not (Test-Path $keyPath)) {
        return $false
    }

    $result = & ssh -i $keyPath `
        -o StrictHostKeyChecking=no `
        -o UserKnownHostsFile=NUL `
        -o IdentitiesOnly=yes `
        -o ConnectTimeout=5 `
        -o BatchMode=yes `
        -p $Port `
        "adp@$HostAddress" `
        "echo ok" 2>$null

    return ($LASTEXITCODE -eq 0 -and $result -eq "ok")
}

function Get-DoctorSeedNetwork {
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

function Write-NetworkDriftRemediation {
    param(
        [string]$TargetRuntime,
        [object]$SeedNetwork,
        [string]$ConfiguredIp
    )

    Write-Host "  [INFO]  Remediation options for $TargetRuntime network drift:" -ForegroundColor DarkGray
    Write-Host "          1. Rebuild when the VM can be recreated: adp destroy $TargetRuntime -Plan, then adp up $TargetRuntime." -ForegroundColor DarkGray
    Write-Host "          2. In-place guest fix when the seed-era address is reachable: adp network apply $TargetRuntime -Plan." -ForegroundColor DarkGray
    Write-Host "          3. Admin-only temporary host-route workaround only to regain SSH to $($SeedNetwork.Address); ADP will not apply host routes automatically." -ForegroundColor DarkGray
    Write-Host "          Seed-era network: $($SeedNetwork.Address)/$($SeedNetwork.Prefix)$(if ($SeedNetwork.Gateway) { ', gateway ' + $SeedNetwork.Gateway } else { '' }); target: $ConfiguredIp." -ForegroundColor DarkGray
}

function Test-WSLCommand {
    param([string]$Command)

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if (-not $wsl) {
        return $false
    }

    & $wsl.Source bash -lc "command -v $Command >/dev/null 2>&1" 2>$null
    return $LASTEXITCODE -eq 0
}

function Test-ISOReasonable {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    $item = Get-Item $Path
    return ($item.Length -ge 1GB -and $item.Extension -ieq ".iso")
}

# --- Platform ---
Write-Host "Platform:" -ForegroundColor Yellow
$platform = Get-Platform
Test-Check -Name "Platform Detection" -Condition ($platform -eq "windows") -Detail "($platform)"

$osInfo = Get-CimInstance Win32_OperatingSystem
Test-Check -Name "Windows Version" -Condition ([Version]$osInfo.Version -ge [Version]"10.0") -Detail "($($osInfo.Caption))"

Test-Check -Name "PowerShell 7+" -Condition ($PSVersionTable.PSVersion.Major -ge 7) -Detail "(v$($PSVersionTable.PSVersion))"

# --- Configuration ---
Write-Host ""
Write-Host "Configuration:" -ForegroundColor Yellow
$localConfigStatus = Get-LocalConfigStatus
if ($localConfigStatus.Exists) {
    if ($localConfigStatus.Empty) {
        Test-Check -Name "local config" -Condition $true -Detail "(empty, ignored: $($localConfigStatus.Path))"
    } elseif ($localConfigStatus.Applied) {
        Test-Check -Name "local config" -Condition $true -Detail "(applied sections: $($localConfigStatus.Sections -join ', '))"
    } else {
        Test-Check -Name "local config" -Condition $true -Detail "(present, no supported sections)"
        Write-Host "  [INFO]  Supported sections: platform, topology, sync_profiles" -ForegroundColor DarkGray
    }
} else {
    Test-Check -Name "local config" -Condition $true -Detail "(not present, using committed defaults)"
    Write-Host "  [INFO]  Optional: copy configs\local.example.json to configs\local.json for machine-local overrides." -ForegroundColor DarkGray
}
if ($localConfigStatus.Exists -and -not $localConfigStatus.Empty) {
    $unsupportedSections = @($localConfigStatus.UnsupportedSections)
    Test-Check -Name "local config supported sections" -Condition ($unsupportedSections.Count -eq 0) -Detail "$(if ($unsupportedSections.Count -gt 0) { '(' + ($unsupportedSections -join ', ') + ')' } else { '(platform, topology, sync_profiles)' })"
}

$config = Get-PlatformConfig
$topology = Get-TopologyConfig
Test-Check -Name "platform paths" -Condition ($config.paths.workspace_root -and $config.paths.iso_cache -and $config.paths.vm_store) -Detail "(workspace_root, iso_cache, vm_store)"
Test-Check -Name "platform defaults" -Condition ($config.defaults.ubuntu_iso -and $config.defaults.admin_user -and $config.defaults.admin_password) -Detail "(ubuntu_iso, admin_user, admin_password)"
Test-Check -Name "network mode" -Condition ($config.network.mode -eq "static") -Detail "($($config.network.mode))"

if ($config.network.vmware_nat) {
    $nat = $config.network.vmware_nat
    Test-Check -Name "VMware NAT config" -Condition ($nat.cidr -and $nat.gateway -and $nat.prefix) -Detail "($($nat.cidr), gateway $($nat.gateway), prefix $($nat.prefix))"
    if ($nat.cidr -and $nat.gateway) {
        Test-Check -Name "VMware NAT gateway range" -Condition (Test-IPv4InCidr -Address $nat.gateway -Cidr $nat.cidr) -Detail "($($nat.gateway) in $($nat.cidr))"
    }
    $hostNat = Test-VMwareNatConfigMatchesHost -ConfiguredNat $nat
    if ($hostNat.Checked) {
        Test-Check -Name "VMware NAT host match" -Condition $hostNat.Matches -Detail "(configured $($hostNat.ConfiguredCidr), host $($hostNat.HostCidr) via $($hostNat.HostSource))"
        Test-Check -Name "VMware NAT gateway host range" -Condition $hostNat.GatewayInHostCidr -Detail "($($nat.gateway) in host $($hostNat.HostCidr))"
        if (-not $hostNat.Matches) {
            Write-Host "  [INFO]  ADP configuration and host VMware NAT disagree; choose one remediation before creating VMs." -ForegroundColor DarkGray
            Write-Host "  [INFO]  Option A: align ADP local overrides: .\cli\adp.ps1 network configure-local -Plan, then .\cli\adp.ps1 network configure-local -Apply" -ForegroundColor DarkGray
            Write-Host "  [INFO]  Option B: keep ADP's configured subnet and change VMware VMnet8 to $($hostNat.ConfiguredCidr) in Virtual Network Editor." -ForegroundColor DarkGray
        }
    } else {
        Write-InfoCheck -Name "VMware NAT host match" -Detail "($($hostNat.Reason); confirm VMnet8/NAT subnet in VMware Virtual Network Editor)"
    }
    Write-InfoCheck -Name "VMware NAT prerequisites" -Detail "(ADP compares configured NAT with host VMnet8 when detectable; override configs\local.json if it differs)"
}

# --- VMware ---
Write-Host ""
Write-Host "VMware:" -ForegroundColor Yellow
$vmwareOk = Test-VMwareAvailable
$runningVmxPaths = @()
Test-Check -Name "vmrun.exe" -Condition $vmwareOk

if ($vmwareOk) {
    Initialize-VMware | Out-Null
    $vmrunPath = Get-VmrunPath
    Test-Check -Name "vmrun path" -Condition (Test-Path $vmrunPath) -Detail "($vmrunPath)"

    $diskManager = Find-VmwareDiskManager
    Test-Check -Name "vmware-vdiskmanager.exe" -Condition ($null -ne $diskManager) -Detail "($diskManager)"

    $isoCreator = Find-ISOCreator
    $isoCreatorDetail = if ($isoCreator) { "$($isoCreator.Type): $($isoCreator.Path)" } else { "missing" }
    Test-Check -Name "seed ISO creator" -Condition ($null -ne $isoCreator) -Detail "($isoCreatorDetail)"

    $isoRemasterTool = Find-ISORemasterTool
    $isoRemasterDetail = if ($isoRemasterTool) { "$($isoRemasterTool.Type): $($isoRemasterTool.Path)" } else { "missing" }
    Test-Check -Name "install ISO remaster" -Condition ($null -ne $isoRemasterTool) -Detail "($isoRemasterDetail)"
    if (-not $isoRemasterTool) {
        Write-Host "  [INFO]  Install xorriso natively or in WSL:" -ForegroundColor DarkGray
        Write-Host "          wsl -u root bash -lc `"apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso`"" -ForegroundColor DarkGray
    }

    try {
        $vms = Get-RunningVMs
        $runningVmxPaths = @($vms | ForEach-Object { Normalize-VMXPath -VmxPath $_ })
        Test-Check -Name "VMware running VMs" -Condition $true -Detail "($($vms.Count) running)"
    } catch {
        Test-Check -Name "VMware accessible" -Condition $false -Detail "($_)"
    }
}

$wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
Test-Check -Name "WSL" -Condition ($null -ne $wsl) -Detail "$(if ($wsl) { '(' + $wsl.Source + ')' } else { '(wsl.exe not found)' })"
Test-Check -Name "WSL xorriso" -Condition (Test-WSLCommand -Command "xorriso") -Detail "(required for Ubuntu autoinstall ISO remastering)"

# --- Mutagen ---
Write-Host ""
Write-Host "Mutagen:" -ForegroundColor Yellow
$mutagenPath = Find-Mutagen -ProjectRoot (Get-ProjectRoot)
$hasMutagen = $null -ne $mutagenPath
Test-Check -Name "mutagen" -Condition $hasMutagen
if (-not $hasMutagen) {
    Write-Host "  [INFO]  Install by placing mutagen.exe at .tools\mutagen\mutagen.exe or adding it to PATH." -ForegroundColor DarkGray
    Write-Host "  [INFO]  Or run: .\cli\adp.ps1 doctor -FixMutagen -Plan" -ForegroundColor DarkGray
}

if ($hasMutagen) {
    Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
    $mutagenVersion = Get-MutagenVersion -Path $mutagenPath
    $mutagenVersionOk = Test-MutagenVersionSupported -VersionText $mutagenVersion
    Test-Check -Name "mutagen version" -Condition $mutagenVersionOk -Detail "($mutagenVersion, $mutagenPath)"
    if (-not $mutagenVersionOk) {
        Write-Host "  [INFO]  ADP-OS is tested with Mutagen 0.18.x." -ForegroundColor DarkGray
        Write-Host "  [INFO]  To install the tested local version, run: .\cli\adp.ps1 doctor -FixMutagen -Plan" -ForegroundColor DarkGray
    }
}

if ($FixMutagen) {
    Write-Host ""
    Write-Host "Mutagen remediation:" -ForegroundColor Cyan
    $remediation = Install-LocalMutagen -ProjectRoot (Get-ProjectRoot) -Plan:$Plan
    if ($Plan) {
        Write-Host "  Plan only: no files will be downloaded, expanded, or overwritten." -ForegroundColor Yellow
        Write-Host "  Version: $($remediation.Version)" -ForegroundColor DarkGray
        Write-Host "  Download: $($remediation.Url)" -ForegroundColor DarkGray
        Write-Host "  Archive:  $($remediation.ZipPath)" -ForegroundColor DarkGray
        Write-Host "  Target:   $($remediation.TargetPath)" -ForegroundColor DarkGray
        Write-Host "  To install: .\cli\adp.ps1 doctor -FixMutagen" -ForegroundColor DarkGray
    } else {
        Write-Host "  Mutagen installed locally." -ForegroundColor Green
        Write-Host "  Version: $($remediation.VersionText)" -ForegroundColor DarkGray
        Write-Host "  Target:  $($remediation.TargetPath)" -ForegroundColor DarkGray
        Write-Host "  Archive: $($remediation.ZipPath)" -ForegroundColor DarkGray
        $script:issues = @($script:issues | Where-Object { $_ -notin @("mutagen", "mutagen version") })
        $script:ok += "mutagen remediation"
    }
}

# --- SSH ---
Write-Host ""
Write-Host "SSH:" -ForegroundColor Yellow
$hasSsh = $null -ne (Get-Command ssh -ErrorAction SilentlyContinue)
Test-Check -Name "OpenSSH Client" -Condition $hasSsh

# --- ISO ---
Write-Host ""
Write-Host "OS ISO:" -ForegroundColor Yellow
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
$isoCache = Resolve-Path "iso_cache"
$isoPath = Join-Path $isoCache $isoName

if (Test-Path $isoPath) {
    $isoSize = [math]::Round((Get-Item $isoPath).Length / 1GB, 1)
    Test-Check -Name "ISO present" -Condition $true -Detail "($isoSize GB)"
    Test-Check -Name "ISO shape" -Condition (Test-ISOReasonable -Path $isoPath) -Detail "(.iso and >= 1 GB)"
} else {
    Test-Check -Name "ISO present" -Condition $false -Detail "(not found at $isoPath)"
}

# --- Directories ---
Write-Host ""
Write-Host "Directories:" -ForegroundColor Yellow
$workspaceRoot = Resolve-Path "workspace_root"
$vmStore = Resolve-Path "vm_store"
Test-Check -Name "Workspace root" -Condition (Test-Path $workspaceRoot) -Detail "($workspaceRoot)"
Test-Check -Name "VM store" -Condition (Test-Path $vmStore) -Detail "($vmStore)"
Test-Check -Name "Logs" -Condition (Test-Path (Join-Path (Get-ProjectRoot) "logs"))

# --- Runtime topology ---
Write-Host ""
Write-Host "Runtimes:" -ForegroundColor Yellow
$staticIpOwners = @{}
foreach ($name in (Get-AllRuntimeNames)) {
    $rt = $topology.$name
    $profile = Get-OSProfile -OSName $rt.os
    $vmName = "adp-$name"
    $vmPath = Join-Path $vmStore $vmName
    $vmxPath = Join-Path $vmPath "$vmName.vmx"
    $vmdkPath = Join-Path $vmPath "$vmName.vmdk"

    $topologyOk = ($profile.seedType -eq "cloud-init" -and $rt.ssh_port -eq 22 -and $rt.cpu -gt 0 -and $rt.memory -gt 0 -and $rt.disk -gt 0 -and $rt.workspace -and $rt.sync_profile -and $rt.bootstrap_profile)
    Test-Check -Name "$name topology" -Condition $topologyOk -Detail "($($rt.os), cpu:$($rt.cpu), memory:$($rt.memory), disk:$($rt.disk), ssh:$($rt.ssh_port))"

    if ($rt.static_ip) {
        $ipDuplicate = $staticIpOwners.ContainsKey($rt.static_ip)
        if ($ipDuplicate) {
            Test-Check -Name "$name static IP unique" -Condition $false -Detail "($($rt.static_ip) also used by $($staticIpOwners[$rt.static_ip]))"
        } else {
            $staticIpOwners[$rt.static_ip] = $name
            Test-Check -Name "$name static IP unique" -Condition $true -Detail "($($rt.static_ip))"
        }

        if ($config.network.vmware_nat.cidr) {
            Test-Check -Name "$name static IP range" -Condition (Test-IPv4InCidr -Address $rt.static_ip -Cidr $config.network.vmware_nat.cidr) -Detail "($($rt.static_ip) in $($config.network.vmware_nat.cidr))"
        }
    } else {
        Test-Check -Name "$name static IP" -Condition $false -Detail "(missing)"
    }

    $syncProfile = $null
    try {
        $syncProfile = Get-SyncProfile $rt.sync_profile
        Test-Check -Name "$name sync profile" -Condition ($syncProfile.mode -and $syncProfile.ignore) -Detail "($($rt.sync_profile), $($syncProfile.mode))"
    } catch {
        Test-Check -Name "$name sync profile" -Condition $false -Detail "($($rt.sync_profile): $_)"
    }

    if ($vmwareOk) {
        $adpRunningVms = @(Get-ADPRunningRuntimeVMs -RunningVmxPaths $runningVmxPaths -RuntimeName $name -ManagedVmxPath $vmxPath)
        $duplicateRunningVms = @($adpRunningVms | Where-Object { -not $_.IsManagedByCurrentCheckout })
        $hasDuplicateRunningVm = ($adpRunningVms.Count -gt 1 -or $duplicateRunningVms.Count -gt 0)
        $hasCurrentRuntimeVm = Test-Path -LiteralPath $vmPath
        if ($hasCurrentRuntimeVm) {
            Test-Check -Name "$name duplicate running VM" -Condition (-not $hasDuplicateRunningVm) -Detail "$(if ($hasDuplicateRunningVm) { '(' + ($duplicateRunningVms.NormalizedVmxPath -join '; ') + ')' } else { '(none)' })"
        } elseif ($hasDuplicateRunningVm) {
            Write-InfoCheck -Name "$name duplicate running VM" -Detail "(same runtime name is running outside this checkout: $($duplicateRunningVms.NormalizedVmxPath -join '; '))"
        } else {
            Test-Check -Name "$name duplicate running VM" -Condition $true -Detail "(none)"
        }
        if ($hasDuplicateRunningVm -and $hasCurrentRuntimeVm) {
            Write-Host "  [INFO]  Stop or rename stale duplicate ADP VMs before diagnosing SSH or network issues." -ForegroundColor DarkGray
            Write-Host "  [INFO]  Current checkout VMX: $vmxPath" -ForegroundColor DarkGray
        }
    }

    if (Test-Path $vmPath) {
        Test-Check -Name "$name VMX" -Condition (Test-Path $vmxPath) -Detail "($vmxPath)"
        Test-Check -Name "$name VMDK" -Condition (Test-Path $vmdkPath) -Detail "($vmdkPath)"
        $seedNetwork = Get-DoctorSeedNetwork -TargetRuntime $name
        if ($seedNetwork -and $rt.static_ip) {
            Test-Check -Name "$name seed network drift" -Condition ($seedNetwork.Address -eq $rt.static_ip) -Detail "(seed $($seedNetwork.Address)/$($seedNetwork.Prefix), configured $($rt.static_ip))"
            if ($seedNetwork.Address -ne $rt.static_ip) {
                Write-NetworkDriftRemediation -TargetRuntime $name -SeedNetwork $seedNetwork -ConfiguredIp $rt.static_ip
            }
        } else {
            Write-InfoCheck -Name "$name seed network drift" -Detail "(seed user-data not found or static IP missing)"
        }
        $status = Get-VMStatus $vmxPath
        Test-Check -Name "$name VM status" -Condition ($status -match "running|stopped") -Detail "($status)"
        if ($status -match "running" -and $rt.static_ip) {
            Test-Check -Name "$name SSH reachable" -Condition (Test-RuntimeSSHReachable -HostAddress $rt.static_ip -Port $rt.ssh_port) -Detail "($($rt.static_ip):$($rt.ssh_port))"
        } else {
            Write-InfoCheck -Name "$name SSH reachable" -Detail "(skipped, VM status: $status)"
        }
    } else {
        Write-InfoCheck -Name "$name VM" -Detail "(not created yet: $vmPath)"
    }

    if ($hasMutagen) {
        $sessionName = "adp-$name"
        try {
            if (Test-SyncSessionExists -SessionName $sessionName) {
                Test-Check -Name "$name Mutagen session" -Condition $true -Detail "($sessionName)"
            } else {
                Write-InfoCheck -Name "$name Mutagen session" -Detail "(not started: $sessionName)"
            }
        } catch {
            Write-InfoCheck -Name "$name Mutagen session" -Detail "(status unavailable: $_)"
        }
    }
}

# --- Summary ---
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Results: $($ok.Count) OK, $($issues.Count) issues, $($info.Count) info" -ForegroundColor $(if ($issues.Count -eq 0) { "Green" } else { "Red" })
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($issues.Count -gt 0) {
    Write-Host "Issues found:" -ForegroundColor Red
    foreach ($issue in $issues) {
        Write-Host "  - $issue" -ForegroundColor Red
    }
} else {
    Write-Host "All checks passed. Platform is healthy." -ForegroundColor Green
}

if ($FirstRun) {
    Write-Host ""
    Write-Host "First-run checklist" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  1. Review local VMware NAT alignment:" -ForegroundColor Yellow
    Write-Host "     .\cli\adp.ps1 network configure-local -Plan" -ForegroundColor DarkGray
    Write-Host "     Apply only if you choose to align ADP local overrides to host VMnet8:" -ForegroundColor DarkGray
    Write-Host "     .\cli\adp.ps1 network configure-local -Apply" -ForegroundColor DarkGray
    Write-Host "     Or keep ADP's configured subnet and change VMware VMnet8 in Virtual Network Editor." -ForegroundColor DarkGray
    Write-Host "     Manual local override path: Copy-Item configs\local.example.json configs\local.json" -ForegroundColor DarkGray
    Write-Host "  2. Confirm ISO availability:" -ForegroundColor Yellow
    Write-Host "     .\install.ps1 -IsoPath C:\path\to\ubuntu-26.04-live-server-amd64.iso" -ForegroundColor DarkGray
    Write-Host "  3. Initialize platform:" -ForegroundColor Yellow
    Write-Host "     .\install.ps1" -ForegroundColor DarkGray
    Write-Host "     .\cli\adp.ps1 init" -ForegroundColor DarkGray
    Write-Host "  4. Preview runtime creation/startup:" -ForegroundColor Yellow
    Write-Host "     .\cli\adp.ps1 up agent -Plan" -ForegroundColor DarkGray
    Write-Host "  5. Start a runtime:" -ForegroundColor Yellow
    Write-Host "     .\cli\adp.ps1 up agent" -ForegroundColor DarkGray
    Write-Host "  6. Preview networking changes when needed:" -ForegroundColor Yellow
    Write-Host "     .\cli\adp.ps1 network apply agent -Plan" -ForegroundColor DarkGray
    Write-Host "  7. Place target projects under the matching workspace root:" -ForegroundColor Yellow
    Write-Host "     $workspaceRoot\agent" -ForegroundColor DarkGray
    Write-Host "  8. Start sync after the runtime is reachable:" -ForegroundColor Yellow
    Write-Host "     .\cli\adp.ps1 sync start agent" -ForegroundColor DarkGray
    Write-Host "  9. Create a snapshot before risky agent work:" -ForegroundColor Yellow
    Write-Host "     .\cli\adp.ps1 snapshot create agent before-large-agent-task" -ForegroundColor DarkGray
    Write-Host ""
}
