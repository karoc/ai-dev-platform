# ADP-OS Runtime Module
# Abstracts VM lifecycle management across hypervisors
# Current: VMware only. Future: Hyper-V, KVM, Docker, Cloud

$script:CurrentRuntime = "vmware"

function Initialize-Runtime {
    param([string]$RuntimeEngine = "vmware")

    $script:CurrentRuntime = $RuntimeEngine

    switch ($RuntimeEngine) {
        "vmware" {
            . (Join-Path $script:ProjectRoot "adapters\windows\vmware\vmware.ps1")
            Initialize-VMware
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
    $vmStore = Resolve-Path "vm_store"
    $vmName = "adp-$RuntimeName"
    $vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

    if (-not (Test-Path $vmxPath)) {
        throw "VM not found for runtime: $RuntimeName. Expected: $vmxPath"
    }

    return Start-VM -VmxPath $vmxPath -Mode $Mode
}

function Stop-Runtime {
    param(
        [string]$RuntimeName,
        [string]$Mode = "soft"
    )

    $vmStore = Resolve-Path "vm_store"
    $vmName = "adp-$RuntimeName"
    $vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

    if (-not (Test-Path $vmxPath)) {
        throw "VM not found for runtime: $RuntimeName"
    }

    return Stop-VM -VmxPath $vmxPath -Mode $Mode
}

function Get-RuntimeStatus {
    param([string]$RuntimeName)

    $vmStore = Resolve-Path "vm_store"
    $vmName = "adp-$RuntimeName"
    $vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

    if (-not (Test-Path $vmxPath)) {
        return "not-created"
    }

    return Get-VMStatus $vmxPath
}

function Get-RuntimeIP {
    param([string]$RuntimeName)

    $vmStore = Resolve-Path "vm_store"
    $vmName = "adp-$RuntimeName"
    $vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

    return Get-VMIP $vmxPath
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
