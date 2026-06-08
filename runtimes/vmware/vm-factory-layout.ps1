# ADP-OS VMware runtime layout helpers.
# Pure naming/path derivation for VM factory resources.

$runtimeIdentityPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "core\runtime\runtime-identity.ps1"
if (Test-Path -LiteralPath $runtimeIdentityPath) {
    . $runtimeIdentityPath
}

function Get-ADPVMwareRuntimeLayout {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeName,

        [Parameter(Mandatory = $true)]
        [string]$VmStorePath,

        [Parameter(Mandatory = $true)]
        [string]$SeedRootPath,

        [string]$Namespace = $null,

        [string]$RuntimeResourceName = $null
    )

    if ([string]::IsNullOrWhiteSpace($RuntimeName)) {
        throw "Get-ADPVMwareRuntimeLayout: RuntimeName is required"
    }
    if ([string]::IsNullOrWhiteSpace($VmStorePath)) {
        throw "Get-ADPVMwareRuntimeLayout: VmStorePath is required"
    }
    if ([string]::IsNullOrWhiteSpace($SeedRootPath)) {
        throw "Get-ADPVMwareRuntimeLayout: SeedRootPath is required"
    }

    if ([string]::IsNullOrWhiteSpace($RuntimeResourceName)) {
        $identityArgs = @{
            TargetRuntime = $RuntimeName
        }
        if ($PSBoundParameters.ContainsKey("Namespace")) {
            $identityArgs.Namespace = $Namespace
        }
        $resourceNames = Get-ADPRuntimeResourceNames @identityArgs
    } else {
        $runtimeNamespace = if ($PSBoundParameters.ContainsKey("Namespace")) {
            Normalize-ADPRuntimeNamespace -Namespace $Namespace
        } else {
            ""
        }
        $vmName = "adp-$RuntimeResourceName"
        $resourceNames = [pscustomobject]@{
            RuntimeNamespace    = $runtimeNamespace
            RuntimeResourceName = $RuntimeResourceName
            VmName              = $vmName
            VmDirectoryName     = $vmName
            VmxFileName         = "$vmName.vmx"
            VmdkFileName        = "$vmName.vmdk"
            SshAlias            = "adp-os-$vmName"
            MutagenSession      = $vmName
        }
    }

    $seedDirectoryName = $resourceNames.RuntimeResourceName
    $installIsoLabel = "ADP_" + (($resourceNames.RuntimeResourceName.ToUpperInvariant()) -replace '[^A-Z0-9]', '_')
    $vmPath = Join-Path $VmStorePath $resourceNames.VmDirectoryName

    return [pscustomobject]@{
        RuntimeName            = $RuntimeName
        Runtime                = $RuntimeName
        RuntimeNamespace       = $resourceNames.RuntimeNamespace
        RuntimeResourceName    = $resourceNames.RuntimeResourceName
        VmName                 = $resourceNames.VmName
        VmDirectoryName        = $resourceNames.VmDirectoryName
        VmPath                 = $vmPath
        VmxFileName            = $resourceNames.VmxFileName
        VmxPath                = Join-Path $vmPath $resourceNames.VmxFileName
        VmdkFileName           = $resourceNames.VmdkFileName
        VmdkPath               = Join-Path $vmPath $resourceNames.VmdkFileName
        Hostname               = $resourceNames.VmName
        SeedRootPath           = $SeedRootPath
        SeedDirectoryName      = $seedDirectoryName
        SeedSourceDir          = Join-Path $SeedRootPath $seedDirectoryName
        SeedIsoFileName        = "$($resourceNames.RuntimeResourceName)-seed.iso"
        SeedIsoPath            = Join-Path $SeedRootPath "$($resourceNames.RuntimeResourceName)-seed.iso"
        AutoinstallIsoFileName = "$($resourceNames.RuntimeResourceName)-autoinstall.iso"
        AutoinstallIsoPath     = Join-Path $SeedRootPath "$($resourceNames.RuntimeResourceName)-autoinstall.iso"
        AutoinstallWorkDirName = "$($resourceNames.RuntimeResourceName)-autoinstall-work"
        AutoinstallWorkDir     = Join-Path $SeedRootPath "$($resourceNames.RuntimeResourceName)-autoinstall-work"
        CloudInitInstanceId    = "$($resourceNames.VmName)-001"
        InstallIsoLabel        = $installIsoLabel
    }
}
