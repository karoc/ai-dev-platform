# ADP-OS Runtime Module
# Abstracts VM lifecycle management across hypervisors
# Current: VMware only. Future: Hyper-V, KVM, Docker, Cloud

$script:CurrentRuntime = "vmware"

function Initialize-Runtime {
    param([string]$RuntimeEngine = "vmware")

    $script:CurrentRuntime = $RuntimeEngine

    switch ($RuntimeEngine) {
        "vmware" {
            . (Join-Path $script:ProjectRoot "core\provider\provider-discovery.ps1")
            $providerType = Get-ConfiguredProviderType
            Initialize-Provider -ProviderType $providerType -ProjectRoot $script:ProjectRoot | Out-Null
        }
        "hyperv" {
            throw "Hyper-V runtime not yet implemented"
        }
        "kvm" {
            throw "KVM runtime not yet implemented"
        }
        default {
            throw "Unknown runtime engine: $RuntimeEngine"
        }
    }
}

function Start-Runtime {
    param(
        [string]$RuntimeName,
        [string]$Mode = "nogui"
    )

    $rt = Get-RuntimeConfig $RuntimeName

    $result = Start-VM -Name $RuntimeName -Mode $Mode
    if (-not $result.Success) {
        throw "VM not found for runtime: $RuntimeName. $($result.Error)"
    }

    return $result
}

function Stop-Runtime {
    param(
        [string]$RuntimeName,
        [string]$Mode = "soft"
    )

    $result = Stop-VM -Name $RuntimeName -Mode $Mode
    if (-not $result.Success) {
        throw "VM not found for runtime: $RuntimeName"
    }

    return $result
}

function Get-RuntimeStatus {
    param([string]$RuntimeName)

    $result = Get-VMStatus -Name $RuntimeName
    if ($result.Success) {
        return $result.Data
    }
    return "unknown"
}

function Get-RuntimeIP {
    param([string]$RuntimeName)

    $result = Get-VMIP -Name $RuntimeName
    if ($result.Success) {
        return $result.Data
    }
    throw "Failed to get IP for runtime: $RuntimeName. $($result.Error)"
}

function Get-RuntimeInfo {
    param([string]$RuntimeName)

    $rt = Get-RuntimeConfig $RuntimeName
    $status = Get-RuntimeStatus $RuntimeName
    $ip = if ($status -match "running") { Get-RuntimeIP $RuntimeName } else { "N/A" }

    return @{
        Name   = $RuntimeName
        Status = $status
        IP     = $ip
        CPU    = $rt.cpu
        Memory = $rt.memory
        Disk   = $rt.disk
        Profile = Get-RuntimeProfileName -RuntimeName $RuntimeName -Runtime $rt
    }
}
