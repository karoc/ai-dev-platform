# ADP-OS runtime identity helpers.
# Canonical resource names for VM, SSH, and sync surfaces.

function Normalize-ADPRuntimeNamespace {
    param([string]$Namespace)

    if ([string]::IsNullOrWhiteSpace($Namespace)) {
        return ""
    }

    $normalized = $Namespace.Trim().ToLowerInvariant()
    if ($normalized -in @("default", "none")) {
        return ""
    }

    if ($normalized.Length -gt 32 -or -not ($normalized -match '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$')) {
        throw "Invalid platform.runtime_namespace '$Namespace'. Use 1-32 lowercase letters, numbers, or hyphens, starting and ending with a letter or number."
    }

    return $normalized
}

function Get-ADPRuntimeNamespace {
    $platformConfig = Get-PlatformConfig
    if ($platformConfig -and
        $platformConfig.PSObject.Properties.Name -contains "runtime_namespace" -and
        -not [string]::IsNullOrWhiteSpace([string]$platformConfig.runtime_namespace)) {
        return Normalize-ADPRuntimeNamespace -Namespace ([string]$platformConfig.runtime_namespace)
    }

    return ""
}

function Get-ADPRuntimeResourceNames {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetRuntime,
        [string]$Namespace = $null
    )

    $runtimeNamespace = if ($PSBoundParameters.ContainsKey("Namespace")) {
        Normalize-ADPRuntimeNamespace -Namespace $Namespace
    } else {
        Get-ADPRuntimeNamespace
    }

    $runtimeResourceName = if ($runtimeNamespace) {
        "$runtimeNamespace-$TargetRuntime"
    } else {
        $TargetRuntime
    }
    $vmName = "adp-$runtimeResourceName"

    return [pscustomobject]@{
        RuntimeNamespace    = $runtimeNamespace
        RuntimeResourceName = $runtimeResourceName
        VmName              = $vmName
        VmDirectoryName     = $vmName
        VmxFileName         = "$vmName.vmx"
        VmdkFileName        = "$vmName.vmdk"
        SshAlias            = "adp-os-$vmName"
        MutagenSession      = $vmName
    }
}
