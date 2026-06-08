# ADP-OS VMware Workstation Provider
# Implements the IVMProvider contract by wrapping existing vmware.ps1.
#
# Dot-source this file to activate the VMware provider.  It internally
# dot-sources vmware.ps1 (preserving all existing adapter functions) and
# provider-result.ps1, then exposes the 11 required contract functions
# plus optional capability and NAT introspection.
#
# Contract functions (required):
#   Get-ProviderInfo           -> ProviderResult { Data = @{Name; Version; Capabilities} }
#   New-VM($Manifest)          -> ProviderResult { Data = "vm-identifier" }
#   Start-VM([string]$Name)    -> ProviderResult
#   Stop-VM([string]$Name, [string]$Mode="soft") -> ProviderResult
#   Restart-VM([string]$Name)  -> ProviderResult
#   Get-VMStatus([string]$Name) -> ProviderResult { Data = "running"|"stopped"|"not-created"|"unknown" }
#   Get-VMIP([string]$Name)    -> ProviderResult { Data = "ip-address" }
#   Remove-VM([string]$Name)   -> ProviderResult
#   New-Snapshot([string]$Name, [string]$SnapshotName) -> ProviderResult
#   Restore-Snapshot([string]$Name, [string]$SnapshotName) -> ProviderResult
#   Get-SnapshotList([string]$Name) -> ProviderResult { Data = @("snap1","snap2") }
#
# Optional:
#   Get-ProviderCapabilities   -> ProviderResult { Data = @{SupportsNAT; SupportsCloning; ...} }
#   Get-ProviderNatInfo        -> ProviderResult { Data = @{Cidr; Gateway; Interface; ...} }
#
# Initialization:
#   Initialize-VMwareProvider  -- called by core/provider/provider-discovery.ps1

# ============================================================================
# Dot-source dependencies
# ============================================================================

# Load the canonical VMware adapter (all functions: Invoke-Vmrun, Find-Vmrun,
# Get-RegisteredVMs, Get-VMStatus, Start-VM, Stop-VM, Suspend-VM, Reset-VM,
# Get-VMIP, Get-VMIPQuick, Get-VMIPFromDhcpLeases, Create-VMSnapshot,
# Restore-VMSnapshot, List-VMSnapshots, Remove-VMSnapshot, etc.)
. (Join-Path $PSScriptRoot "vmware.ps1")

# Load the standard ProviderResult factory functions
. (Join-Path $PSScriptRoot ".." ".." ".." "core" "provider" "provider-result.ps1")

# Load provider path helpers
. (Join-Path $PSScriptRoot "vmware-paths.ps1")


# ============================================================================
# Provider state
# ============================================================================

$script:ProviderState = @{
    Name        = "vmware-workstation"
    Version     = ""
    VmrunPath   = $null
    VmStorePath = $null
    Initialized = $false
}


# ============================================================================
# Initialization
# ============================================================================

function Initialize-VMwareProvider {
    <#
    .SYNOPSIS
    Initialize the VMware provider.  Called by Initialize-Provider from
    core/provider/provider-discovery.ps1.

    .DESCRIPTION
    Resolves the vmrun path, validates VMware Workstation availability,
    and stores the VM store path.  Accepts a hashtable splatted from
    the discovery module's -InitArgs parameter.

    .PARAMETER VmStorePath
    Path to the VM store directory (e.g., "$env:USERPROFILE\adp-vms").

    .PARAMETER VmrunExePath
    Optional explicit path to vmrun.exe.  When omitted, Find-Vmrun is used.
    #>
    param(
        [string]$VmStorePath,
        [string]$VmrunExePath
    )

    if (-not $VmStorePath) {
        throw "Initialize-VMwareProvider: VmStorePath is required"
    }

    # Resolve vmrun
    if ($VmrunExePath) {
        $script:ProviderState.VmrunPath = $VmrunExePath
    } else {
        $found = Find-Vmrun
        if (-not $found) {
            throw "Initialize-VMwareProvider: vmrun.exe not found.  Please install VMware Workstation."
        }
        $script:ProviderState.VmrunPath = $found
    }

    if (-not (Test-Path $script:ProviderState.VmrunPath)) {
        throw "Initialize-VMwareProvider: vmrun.exe not found at '$($script:ProviderState.VmrunPath)'"
    }

    # Initialize the low-level adapter
    Initialize-VMware -VmrunExePath $script:ProviderState.VmrunPath | Out-Null

    # Normalise and store VmStorePath
    try {
        $resolved = [System.IO.Path]::GetFullPath($VmStorePath)
    } catch {
        $resolved = $VmStorePath
    }
    $script:ProviderState.VmStorePath = $resolved

    # Detect VMware Workstation version
    try {
        $verInfo = Invoke-Vmrun -Arguments @("list") -TimeoutSeconds 10
        # vmrun doesn't have a --version flag; record that we probed successfully
        $script:ProviderState.Version = "probed"
    } catch {
        $script:ProviderState.Version = "unknown"
    }

    $script:ProviderState.Initialized = $true
    return $script:ProviderState.VmrunPath
}


# ============================================================================
# Internal helpers
# ============================================================================

function Resolve-ProviderVmxPath {
    param([string]$Name)

    if (-not $script:ProviderState.Initialized) {
        throw "VMware provider not initialized. Call Initialize-VMwareProvider first."
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        throw "Resolve-ProviderVmxPath: Name is required"
    }

    return (Get-ADPVMwareProviderRuntimePath -VmStorePath $script:ProviderState.VmStorePath -RuntimeResourceName $Name).VmxPath
}

function Get-InternalVMXPath {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return $null
    }
    return (Get-ADPVMwareProviderRuntimePath -VmStorePath $script:ProviderState.VmStorePath -RuntimeResourceName $Name).VmxPath
}


# ============================================================================
# Required contract: Get-ProviderInfo
# ============================================================================

function Get-ProviderInfo {
    return Get-ProviderResultOK @{
        Name         = $script:ProviderState.Name
        Version      = $script:ProviderState.Version
        VmrunPath    = $script:ProviderState.VmrunPath
        VmStorePath  = $script:ProviderState.VmStorePath
        Initialized  = $script:ProviderState.Initialized
        Capabilities = @("nat", "snapshot", "guest-exec")
    }
}


# ============================================================================
# Required contract: New-VM
# ============================================================================

function New-VM {
    <#
    .SYNOPSIS
    Register or create a virtual machine.

    .DESCRIPTION
    $Manifest must contain at least a Name key.
    If the VM directory already exists with a .vmx file, the VM is registered.
    Full VM creation (disk provisioning, .vmx generation, OS installation)
    is handled by vm-factory.ps1 and invoked transparently when the VM does
    not yet exist.

    .PARAMETER Manifest
    Hashtable with keys: Name (required), CPU, Memory, Disk, ImagePath, NetworkConfig.
    #>
    param([hashtable]$Manifest)

    if (-not $Manifest -or -not $Manifest.Name) {
        return Get-ProviderResultFail "New-VM: Manifest.Name is required"
    }

    $name    = $Manifest.Name
    $vmxPath = Resolve-ProviderVmxPath -Name $name
    $providerLayout = Get-ADPVMwareProviderRuntimePath -VmStorePath $script:ProviderState.VmStorePath -RuntimeResourceName $name

    # If the VM directory already has a .vmx, just register it
    if (Test-Path $vmxPath -PathType Leaf) {
        try {
            $result = Invoke-Vmrun -Arguments @("register", $vmxPath)
            if ($result.Success) {
                return Get-ProviderResultOK $name
            }
            return Get-ProviderResultFail "Failed to register existing VM '$name': $($result.StdErr)"
        } catch {
            return Get-ProviderResultFail "New-VM register error: $_"
        }
    }

    # VM directory does not exist — create it and delegate to vm-factory
    $vmDir = $providerLayout.VmPath
    try {
        New-Item -ItemType Directory -Path $vmDir -Force -ErrorAction Stop | Out-Null
    } catch {
        return Get-ProviderResultFail "New-VM: failed to create directory '$vmDir': $_"
    }

    # Attempt to use vm-factory.ps1 for full VM provisioning
    $factoryPath = Join-Path $PSScriptRoot ".." ".." ".." "runtimes" "vmware" "vm-factory.ps1"
    if (Test-Path $factoryPath) {
        try {
            . $factoryPath

            # Build factory arguments from manifest
            $factoryArgs = @{
                RuntimeName      = $name
                VmStore          = $script:ProviderState.VmStorePath
                CPU              = if ($Manifest.CPU)    { [int]$Manifest.CPU }    else { 4 }
                Memory           = if ($Manifest.Memory) { [int]$Manifest.Memory } else { 4096 }
                DiskSizeGB       = if ($Manifest.Disk)   { [int]$Manifest.Disk }   else { 60 }
                ImagePath        = if ($Manifest.ImagePath) { $Manifest.ImagePath } else { $null }
                NetworkConfig    = if ($Manifest.NetworkConfig) { $Manifest.NetworkConfig } else { $null }
            }

            $factoryResult = New-RuntimeVM @factoryArgs
            if ($factoryResult) {
                return Get-ProviderResultOK $name
            }
            return Get-ProviderResultFail "New-VM: vm-factory New-RuntimeVM returned null"
        } catch {
            return Get-ProviderResultFail "New-VM: vm-factory error: $_"
        }
    }

    # Fallback: create minimal .vmx + register
    try {
        $emptyVmx = @"
.encoding = "windows-1252"
config.version = "8"
virtualHW.version = "18"
displayName = "$($providerLayout.VmName)"
guestOS = "ubuntu-64"
"@
        Set-Content -Path $vmxPath -Value $emptyVmx -Encoding ASCII -ErrorAction Stop
        $regResult = Invoke-Vmrun -Arguments @("register", $vmxPath)
        if (-not $regResult.Success) {
            return Get-ProviderResultFail "New-VM: register failed: $($regResult.StdErr)"
        }
        return Get-ProviderResultOK $name
    } catch {
        return Get-ProviderResultFail "New-VM: fallback creation error: $_"
    }
}


# ============================================================================
# Required contract: Start-VM
# ============================================================================

function Start-VM {
    <#
    .SYNOPSIS
    Start a VM by runtime name (e.g., "agent").

    .PARAMETER Name
    Runtime name, not a .vmx path.

    .PARAMETER Mode
    "nogui" (default) or "gui".
    #>
    param(
        [string]$Name,
        [string]$Mode = "nogui"
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return Get-ProviderResultFail "Start-VM: Name is required"
    }

    $vmxPath = Resolve-ProviderVmxPath -Name $Name
    if (-not (Test-Path $vmxPath)) {
        return Get-ProviderResultFail "Start-VM: VM '$Name' not found at '$vmxPath'"
    }

    $flag = if ($Mode -eq "gui") { "gui" } else { "nogui" }
    try {
        $result = Invoke-Vmrun -Arguments @("start", $vmxPath, $flag)
        if ($result.Success) {
            return Get-ProviderResultOK $null
        }
        return Get-ProviderResultFail "Start-VM: $($result.StdErr)"
    } catch {
        return Get-ProviderResultFail "Start-VM error: $_"
    }
}


# ============================================================================
# Required contract: Stop-VM
# ============================================================================

function Stop-VM {
    <#
    .SYNOPSIS
    Stop a VM by runtime name.

    .PARAMETER Name
    Runtime name.

    .PARAMETER Mode
    "soft" (default, graceful guest shutdown) or "hard" (power off).
    #>
    param(
        [string]$Name,
        [string]$Mode = "soft"
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return Get-ProviderResultFail "Stop-VM: Name is required"
    }

    $vmxPath = Resolve-ProviderVmxPath -Name $Name
    if (-not (Test-Path $vmxPath)) {
        return Get-ProviderResultFail "Stop-VM: VM '$Name' not found"
    }

    try {
        $result = Invoke-Vmrun -Arguments @("stop", $vmxPath, $Mode)
        if ($result.Success) {
            return Get-ProviderResultOK $null
        }
        return Get-ProviderResultFail "Stop-VM: $($result.StdErr)"
    } catch {
        return Get-ProviderResultFail "Stop-VM error: $_"
    }
}


# ============================================================================
# Required contract: Restart-VM
# ============================================================================

function Restart-VM {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return Get-ProviderResultFail "Restart-VM: Name is required"
    }

    $vmxPath = Resolve-ProviderVmxPath -Name $Name
    if (-not (Test-Path $vmxPath)) {
        return Get-ProviderResultFail "Restart-VM: VM '$Name' not found"
    }

    # Reset via vmrun (hard reset, guest doesn't get graceful shutdown)
    try {
        $result = Invoke-Vmrun -Arguments @("reset", $vmxPath, "hard")
        if ($result.Success) {
            return Get-ProviderResultOK $null
        }
        return Get-ProviderResultFail "Restart-VM: $($result.StdErr)"
    } catch {
        return Get-ProviderResultFail "Restart-VM error: $_"
    }
}


# ============================================================================
# Required contract: Get-VMStatus
# ============================================================================

function Get-VMStatus {
    <#
    .SYNOPSIS
    Return VM status by runtime name.  Possible values:
      "running", "stopped", "not-created", "unknown"
    #>
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return Get-ProviderResultFail "Get-VMStatus: Name is required"
    }

    $vmxPath = Get-InternalVMXPath -Name $Name
    if (-not $vmxPath -or -not (Test-Path $vmxPath)) {
        return Get-ProviderResultOK "not-created"
    }

    try {
        $target    = [System.IO.Path]::GetFullPath($vmxPath)
        $running   = Get-RegisteredVMs | ForEach-Object { [System.IO.Path]::GetFullPath($_) }
        if ($running -contains $target) {
            return Get-ProviderResultOK "running"
        }

        # Probe with getGuestIPAddress as secondary check
        $ipProbe = Invoke-Vmrun -Arguments @("getGuestIPAddress", $vmxPath) -TimeoutSeconds 10
        if ($ipProbe.Success -and $ipProbe.StdOut -match '\b(?:\d{1,3}\.){3}\d{1,3}\b') {
            return Get-ProviderResultOK "running"
        }

        return Get-ProviderResultOK "stopped"
    } catch {
        return Get-ProviderResultOK "unknown"
    }
}


# ============================================================================
# Required contract: Get-VMIP
# ============================================================================

function Get-VMIP {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return Get-ProviderResultFail "Get-VMIP: Name is required"
    }

    $vmxPath = Resolve-ProviderVmxPath -Name $Name
    if (-not (Test-Path $vmxPath)) {
        return Get-ProviderResultFail "Get-VMIP: VM '$Name' not found"
    }

    $errors = [System.Collections.Generic.List[string]]::new()

    # Quick guest IP probe
    try {
        $quick = Invoke-Vmrun -Arguments @("getGuestIPAddress", $vmxPath) -TimeoutSeconds 15
        if ($quick.Success) {
            $ip = Select-VMIPv4FromText -Text $quick.StdOut
            if ($ip) {
                return Get-ProviderResultOK $ip
            }
            $errors.Add("getGuestIPAddress: no usable IPv4 in '$($quick.StdOut)'") | Out-Null
        } else {
            $errors.Add("getGuestIPAddress: $($quick.StdErr)") | Out-Null
        }
    } catch {
        $errors.Add("getGuestIPAddress exception: $_") | Out-Null
    }

    # Wait-mode probe
    try {
        $wait = Invoke-Vmrun -Arguments @("getGuestIPAddress", $vmxPath, "-wait") -TimeoutSeconds 60
        if ($wait.Success) {
            $ip = Select-VMIPv4FromText -Text $wait.StdOut
            if ($ip) {
                return Get-ProviderResultOK $ip
            }
            $errors.Add("getGuestIPAddress -wait: no usable IPv4") | Out-Null
        } else {
            $errors.Add("getGuestIPAddress -wait: $($wait.StdErr)") | Out-Null
        }
    } catch {
        $errors.Add("getGuestIPAddress -wait exception: $_") | Out-Null
    }

    # DHCP leases fallback
    try {
        $leaseIp = Get-VMIPFromDhcpLeases -VmxPath $vmxPath
        if ($leaseIp) {
            return Get-ProviderResultOK $leaseIp
        }
    } catch {
        $errors.Add("DHCP leases: $_") | Out-Null
    }

    return Get-ProviderResultFail "Get-VMIP: $($errors -join '; ')"
}


# ============================================================================
# Required contract: Remove-VM
# ============================================================================

function Remove-VM {
    <#
    .SYNOPSIS
    Unregister a VM and optionally delete its files.

    .PARAMETER Name
    Runtime name.

    .PARAMETER DeleteFiles
    If $true, also remove the VM directory from disk.  Default: $false (unregister only).
    #>
    param(
        [string]$Name,
        [bool]$DeleteFiles = $false
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return Get-ProviderResultFail "Remove-VM: Name is required"
    }

    $vmxPath = Resolve-ProviderVmxPath -Name $Name
    if (-not (Test-Path $vmxPath)) {
        return Get-ProviderResultFail "Remove-VM: VM '$Name' not found"
    }

    # Stop the VM first if it's running
    try {
        $statusResult = Get-VMStatus -Name $Name
        if ($statusResult.Success -and $statusResult.Data -eq "running") {
            $stopResult = Stop-VM -Name $Name -Mode "hard"
            if (-not $stopResult.Success) {
                return Get-ProviderResultFail "Remove-VM: failed to stop VM: $($stopResult.Error)"
            }
        }
    } catch {
        # VM may not be registered; continue with unregister attempt
    }

    # Unregister
    try {
        $result = Invoke-Vmrun -Arguments @("unregister", $vmxPath)
        if (-not $result.Success) {
            # Non-fatal: VM might not be registered
            Write-Warning "Remove-VM: unregister warning: $($result.StdErr)"
        }
    } catch {
        Write-Warning "Remove-VM: unregister error: $_"
    }

    # Optionally delete files
    if ($DeleteFiles) {
        $vmDir = Split-Path $vmxPath -Parent
        if (Test-Path $vmDir) {
            try {
                Remove-Item -Path $vmDir -Recurse -Force -ErrorAction Stop
                return Get-ProviderResultOK $Name
            } catch {
                return Get-ProviderResultFail "Remove-VM: unregistered but failed to delete files: $_"
            }
        }
    }

    return Get-ProviderResultOK $Name
}


# ============================================================================
# Required contract: New-Snapshot
# ============================================================================

function New-Snapshot {
    param(
        [string]$Name,
        [string]$SnapshotName
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return Get-ProviderResultFail "New-Snapshot: Name is required"
    }
    if ([string]::IsNullOrWhiteSpace($SnapshotName)) {
        return Get-ProviderResultFail "New-Snapshot: SnapshotName is required"
    }

    $vmxPath = Resolve-ProviderVmxPath -Name $Name
    if (-not (Test-Path $vmxPath)) {
        return Get-ProviderResultFail "New-Snapshot: VM '$Name' not found"
    }

    try {
        $result = Create-VMSnapshot -VmxPath $vmxPath -SnapshotName $SnapshotName
        if ($result.Success) {
            return Get-ProviderResultOK $null
        }
        return Get-ProviderResultFail "New-Snapshot: $($result.StdErr)"
    } catch {
        return Get-ProviderResultFail "New-Snapshot error: $_"
    }
}


# ============================================================================
# Required contract: Restore-Snapshot
# ============================================================================

function Restore-Snapshot {
    param(
        [string]$Name,
        [string]$SnapshotName
    )

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return Get-ProviderResultFail "Restore-Snapshot: Name is required"
    }
    if ([string]::IsNullOrWhiteSpace($SnapshotName)) {
        return Get-ProviderResultFail "Restore-Snapshot: SnapshotName is required"
    }

    $vmxPath = Resolve-ProviderVmxPath -Name $Name
    if (-not (Test-Path $vmxPath)) {
        return Get-ProviderResultFail "Restore-Snapshot: VM '$Name' not found"
    }

    try {
        $result = Restore-VMSnapshot -VmxPath $vmxPath -SnapshotName $SnapshotName
        if ($result.Success) {
            return Get-ProviderResultOK $null
        }
        return Get-ProviderResultFail "Restore-Snapshot: $($result.StdErr)"
    } catch {
        return Get-ProviderResultFail "Restore-Snapshot error: $_"
    }
}


# ============================================================================
# Required contract: Get-SnapshotList
# ============================================================================

function Get-SnapshotList {
    param([string]$Name)

    if ([string]::IsNullOrWhiteSpace($Name)) {
        return Get-ProviderResultFail "Get-SnapshotList: Name is required"
    }

    $vmxPath = Resolve-ProviderVmxPath -Name $Name
    if (-not (Test-Path $vmxPath)) {
        return Get-ProviderResultFail "Get-SnapshotList: VM '$Name' not found"
    }

    try {
        $snapshots = List-VMSnapshots -VmxPath $vmxPath
        return Get-ProviderResultOK @($snapshots)
    } catch {
        return Get-ProviderResultFail "Get-SnapshotList error: $_"
    }
}


# ============================================================================
# Optional: Get-ProviderCapabilities
# ============================================================================

function Get-ProviderCapabilities {
    <#
    .SYNOPSIS
    Return provider capability flags for runtime feature detection.
    #>
    return Get-ProviderResultOK @{
        SupportsNAT             = $true
        SupportsCloning         = $true
        SupportsLiveMigration   = $false
        SupportsSnapshots       = $true
        SupportsGuestExec       = $true
        SupportsDynamicResize   = $false
        ProviderType            = $script:ProviderState.Name
        ProviderVersion         = $script:ProviderState.Version
    }
}


# ============================================================================
# Optional: Get-ProviderNatInfo
# ============================================================================

function Get-ProviderNatInfo {
    <#
    .SYNOPSIS
    Return VMware NAT network information.  Uses the existing vmware.ps1
    NAT detection logic (VMnet8 host adapter / vmnetnat.conf).
    #>
    try {
        $nat = Get-VMwareNatNetwork
        if (-not $nat) {
            return Get-ProviderResultFail "Get-ProviderNatInfo: NAT network not detected (VMnet8 not found)"
        }

        return Get-ProviderResultOK @{
            Cidr       = $nat.Cidr
            Gateway    = $nat.Address
            Prefix     = $nat.Prefix
            Interface  = $nat.InterfaceAlias
            Source     = $nat.Source
        }
    } catch {
        return Get-ProviderResultFail "Get-ProviderNatInfo error: $_"
    }
}
