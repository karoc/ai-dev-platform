# ADP-OS VMware runtime layout contracts.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

. (Join-Path $projectRoot "core\runtime\runtime-identity.ps1")
. (Join-Path $projectRoot "runtimes\vmware\vm-factory-layout.ps1")
. (Join-Path $projectRoot "adapters\windows\vmware\vmware-paths.ps1")

function Assert-Equal {
    param(
        [string]$Name,
        $Actual,
        $Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name expected '$Expected' but got '$Actual'"
    }
}

function Assert-Throws {
    param(
        [string]$Name,
        [scriptblock]$ScriptBlock
    )

    $thrown = $false
    try {
        & $ScriptBlock
    } catch {
        $thrown = $true
    }

    if (-not $thrown) {
        throw "$Name did not throw"
    }
}

$vmStore = "C:\adp-test\vms"
$seedRoot = Join-Path $vmStore "seeds"

$expectedRuntimeNames = @("frontend", "backend", "agent", "sandbox")
foreach ($runtime in $expectedRuntimeNames) {
    $layout = Get-ADPVMwareRuntimeLayout -RuntimeName $runtime -VmStorePath $vmStore -SeedRootPath $seedRoot -Namespace ""
    $vmName = "adp-$runtime"

    Assert-Equal -Name "$runtime legacy runtime" -Actual $layout.RuntimeName -Expected $runtime
    Assert-Equal -Name "$runtime legacy namespace" -Actual $layout.RuntimeNamespace -Expected ""
    Assert-Equal -Name "$runtime legacy resource" -Actual $layout.RuntimeResourceName -Expected $runtime
    Assert-Equal -Name "$runtime legacy VM name" -Actual $layout.VmName -Expected $vmName
    Assert-Equal -Name "$runtime legacy VM directory" -Actual $layout.VmDirectoryName -Expected $vmName
    Assert-Equal -Name "$runtime legacy VM path" -Actual $layout.VmPath -Expected (Join-Path $vmStore $vmName)
    Assert-Equal -Name "$runtime legacy VMX file" -Actual $layout.VmxFileName -Expected "$vmName.vmx"
    Assert-Equal -Name "$runtime legacy VMX path" -Actual $layout.VmxPath -Expected (Join-Path (Join-Path $vmStore $vmName) "$vmName.vmx")
    Assert-Equal -Name "$runtime legacy VMDK file" -Actual $layout.VmdkFileName -Expected "$vmName.vmdk"
    Assert-Equal -Name "$runtime legacy VMDK path" -Actual $layout.VmdkPath -Expected (Join-Path (Join-Path $vmStore $vmName) "$vmName.vmdk")
    Assert-Equal -Name "$runtime legacy hostname" -Actual $layout.Hostname -Expected $vmName
    Assert-Equal -Name "$runtime legacy seed dir" -Actual $layout.SeedSourceDir -Expected (Join-Path $seedRoot $runtime)
    Assert-Equal -Name "$runtime legacy seed ISO" -Actual $layout.SeedIsoPath -Expected (Join-Path $seedRoot "$runtime-seed.iso")
    Assert-Equal -Name "$runtime legacy autoinstall ISO" -Actual $layout.AutoinstallIsoPath -Expected (Join-Path $seedRoot "$runtime-autoinstall.iso")
    Assert-Equal -Name "$runtime legacy autoinstall work dir" -Actual $layout.AutoinstallWorkDir -Expected (Join-Path $seedRoot "$runtime-autoinstall-work")
    Assert-Equal -Name "$runtime legacy cloud-init instance-id" -Actual $layout.CloudInitInstanceId -Expected "$vmName-001"
    Assert-Equal -Name "$runtime legacy install ISO label" -Actual $layout.InstallIsoLabel -Expected ("ADP_" + $runtime.ToUpperInvariant())

    $providerPath = Get-ADPVMwareProviderRuntimePath -VmStorePath $vmStore -RuntimeResourceName $layout.RuntimeResourceName
    Assert-Equal -Name "$runtime provider VMX path matches factory layout" -Actual $providerPath.VmxPath -Expected $layout.VmxPath
}

$namespaced = Get-ADPVMwareRuntimeLayout -RuntimeName "agent" -VmStorePath $vmStore -SeedRootPath $seedRoot -Namespace " V2 "
Assert-Equal -Name "namespaced namespace normalization" -Actual $namespaced.RuntimeNamespace -Expected "v2"
Assert-Equal -Name "namespaced resource" -Actual $namespaced.RuntimeResourceName -Expected "v2-agent"
Assert-Equal -Name "namespaced VM" -Actual $namespaced.VmName -Expected "adp-v2-agent"
Assert-Equal -Name "namespaced VMX" -Actual $namespaced.VmxPath -Expected (Join-Path (Join-Path $vmStore "adp-v2-agent") "adp-v2-agent.vmx")
Assert-Equal -Name "namespaced VMDK" -Actual $namespaced.VmdkPath -Expected (Join-Path (Join-Path $vmStore "adp-v2-agent") "adp-v2-agent.vmdk")
Assert-Equal -Name "namespaced hostname" -Actual $namespaced.Hostname -Expected "adp-v2-agent"
Assert-Equal -Name "namespaced seed dir" -Actual $namespaced.SeedSourceDir -Expected (Join-Path $seedRoot "v2-agent")
Assert-Equal -Name "namespaced seed ISO" -Actual $namespaced.SeedIsoPath -Expected (Join-Path $seedRoot "v2-agent-seed.iso")
Assert-Equal -Name "namespaced autoinstall ISO" -Actual $namespaced.AutoinstallIsoPath -Expected (Join-Path $seedRoot "v2-agent-autoinstall.iso")
Assert-Equal -Name "namespaced instance-id" -Actual $namespaced.CloudInitInstanceId -Expected "adp-v2-agent-001"
Assert-Equal -Name "namespaced install ISO label" -Actual $namespaced.InstallIsoLabel -Expected "ADP_V2_AGENT"

$namespacedProvider = Get-ADPVMwareProviderRuntimePath -VmStorePath $vmStore -RuntimeResourceName $namespaced.RuntimeResourceName
Assert-Equal -Name "namespaced provider VMX path" -Actual $namespacedProvider.VmxPath -Expected $namespaced.VmxPath

$defaultNamespace = Get-ADPVMwareRuntimeLayout -RuntimeName "agent" -VmStorePath $vmStore -SeedRootPath $seedRoot -Namespace "default"
Assert-Equal -Name "default namespace stays legacy" -Actual $defaultNamespace.RuntimeResourceName -Expected "agent"

$noneNamespace = Get-ADPVMwareRuntimeLayout -RuntimeName "agent" -VmStorePath $vmStore -SeedRootPath $seedRoot -Namespace "none"
Assert-Equal -Name "none namespace stays legacy" -Actual $noneNamespace.RuntimeResourceName -Expected "agent"

foreach ($invalidNamespace in @("bad_name", "-bad", "bad-", "bad namespace", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")) {
    Assert-Throws -Name "invalid namespace $invalidNamespace" -ScriptBlock {
        Get-ADPVMwareRuntimeLayout -RuntimeName "agent" -VmStorePath $vmStore -SeedRootPath $seedRoot -Namespace $invalidNamespace | Out-Null
    }
}

Write-Output "VMware runtime layout contracts OK"
