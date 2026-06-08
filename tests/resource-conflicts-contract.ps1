# ADP-OS resource conflict contract tests.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

. (Join-Path $projectRoot "core\config\config.ps1")
Initialize-Config -ProjectRoot $projectRoot
. (Join-Path $projectRoot "adapters\windows\vmware\vmware.ps1")
. (Join-Path $projectRoot "core\diagnostics\resource-conflicts.ps1")

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if (-not $Condition) {
        throw "$Name failed"
    }
}

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

$currentVmx = "C:\adp-current\vms\adp-agent\adp-agent.vmx"
$otherVmx = "D:\adp-old\vms\adp-agent\adp-agent.vmx"
$otherRuntimeVmx = "D:\adp-old\vms\adp-backend\adp-backend.vmx"
$nonAdpVmx = "D:\other\vms\ubuntu\ubuntu.vmx"

$conflict = Get-ADPRuntimeDuplicateConflict `
    -TargetRuntime "agent" `
    -ManagedVmxPath $currentVmx `
    -RunningVmxPaths @($currentVmx, $otherVmx, $otherRuntimeVmx, $nonAdpVmx)

Assert-True -Name "duplicate same-name runtime blocks mutation" -Condition $conflict.BlocksRuntimeMutation
Assert-Equal -Name "same-name ADP running VM count" -Actual @($conflict.RunningVms).Count -Expected 2
Assert-Equal -Name "other-checkout running VM count" -Actual @($conflict.DuplicateVms).Count -Expected 1
Assert-Equal -Name "other-checkout running VM path" -Actual $conflict.OtherRunningVmxPaths[0] -Expected (Normalize-ADPResourcePath -Path $otherVmx)

$noConflict = Get-ADPRuntimeDuplicateConflict `
    -TargetRuntime "agent" `
    -ManagedVmxPath $currentVmx `
    -RunningVmxPaths @($currentVmx, $otherRuntimeVmx, $nonAdpVmx)

Assert-True -Name "only current same-name VM does not block" -Condition (-not $noConflict.BlocksRuntimeMutation)
Assert-Equal -Name "no duplicate other-checkout VM count" -Actual @($noConflict.DuplicateVms).Count -Expected 0

$profile = Get-ADPRuntimeResourceProfile -TargetRuntime "agent" -VmxPath $currentVmx
Assert-Equal -Name "resource profile runtime" -Actual $profile.Runtime -Expected "agent"
Assert-Equal -Name "resource profile static IP" -Actual $profile.StaticIp -Expected "192.168.242.135"
Assert-Equal -Name "resource profile SSH alias" -Actual $profile.SshAlias -Expected "adp-os-adp-agent"
Assert-Equal -Name "resource profile Mutagen session" -Actual $profile.MutagenSession -Expected "adp-agent"
Assert-True -Name "resource profile includes workspace_root" -Condition ($profile.WorkspaceRoot -and $profile.WorkspacePath)
Assert-True -Name "resource profile includes vm_store" -Condition ($profile.VmStore -and $profile.VmxPath)

$jsonRows = ConvertTo-ADPDuplicateVmJson -RunningVms $conflict.RunningVms
Assert-Equal -Name "duplicate JSON row count" -Actual @($jsonRows).Count -Expected 2
Assert-Equal -Name "duplicate JSON exposes ownership" -Actual @($jsonRows | Where-Object { -not $_.IsManagedByCurrentCheckout }).Count -Expected 1

Write-Output "Resource conflict contracts OK"
