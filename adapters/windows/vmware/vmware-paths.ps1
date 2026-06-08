# ADP-OS VMware provider path helpers.
# Provider Name is a runtime resource name, for example "agent" or "v2-agent".

function Get-ADPVMwareProviderRuntimePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VmStorePath,

        [Parameter(Mandatory = $true)]
        [string]$RuntimeResourceName
    )

    if ([string]::IsNullOrWhiteSpace($VmStorePath)) {
        throw "Get-ADPVMwareProviderRuntimePath: VmStorePath is required"
    }
    if ([string]::IsNullOrWhiteSpace($RuntimeResourceName)) {
        throw "Get-ADPVMwareProviderRuntimePath: RuntimeResourceName is required"
    }

    $vmName = "adp-$RuntimeResourceName"
    $vmPath = Join-Path $VmStorePath $vmName

    return [pscustomobject]@{
        RuntimeResourceName = $RuntimeResourceName
        VmName              = $vmName
        VmDirectoryName     = $vmName
        VmPath              = $vmPath
        VmxFileName         = "$vmName.vmx"
        VmxPath             = Join-Path $vmPath "$vmName.vmx"
        VmdkFileName        = "$vmName.vmdk"
        VmdkPath            = Join-Path $vmPath "$vmName.vmdk"
    }
}
