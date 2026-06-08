# ADP-OS adpos registration decision tests.
# Exercises only pure helpers; do not call install/uninstall helpers that write User PATH.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $projectRoot "scripts\adpos-registration.ps1")

function New-TestRegistration {
    param(
        [string]$RegistrationHome = "",
        [bool]$IsDifferentHome = $false,
        [bool]$ShimExists = $true,
        [bool]$ShimOwned = $true,
        [bool]$UserPathHasBin = $true,
        [string]$UserHome = "",
        [string]$ProcessHome = ""
    )

    if ([string]::IsNullOrWhiteSpace($UserHome)) {
        $UserHome = $RegistrationHome
    }

    return [pscustomobject]@{
        Home           = $RegistrationHome
        IsDifferentHome = $IsDifferentHome
        ShimExists     = $ShimExists
        ShimOwned      = $ShimOwned
        UserPathHasBin = $UserPathHasBin
        UserHome       = $UserHome
        ProcessHome    = $ProcessHome
    }
}

function Assert-Equal {
    param(
        [string]$Name,
        [object]$Actual,
        [object]$Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name expected '$Expected' but got '$Actual'"
    }
}

function Assert-SequenceEqual {
    param(
        [string]$Name,
        [object[]]$Actual,
        [object[]]$Expected
    )

    $actualText = ($Actual | ForEach-Object { [string]$_ }) -join "`n"
    $expectedText = ($Expected | ForEach-Object { [string]$_ }) -join "`n"
    if ($actualText -ne $expectedText) {
        throw "$Name expected:`n$expectedText`nactual:`n$actualText"
    }
}

function Assert-EmptySequence {
    param(
        [string]$Name,
        [object[]]$Actual
    )

    if ($Actual.Count -ne 0) {
        throw "$Name expected an empty sequence but got: $(($Actual | ForEach-Object { [string]$_ }) -join ', ')"
    }
}

function Assert-RegistersWithEffects {
    param(
        [string]$Name,
        [object]$Decision,
        [bool]$Replaced
    )

    Assert-Equal -Name "$Name should register" -Actual $Decision.ShouldRegister -Expected $true
    Assert-Equal -Name "$Name registered flag" -Actual $Decision.Registered -Expected $true
    Assert-Equal -Name "$Name should not require confirmation" -Actual $Decision.RequiresConfirmation -Expected $false
    Assert-Equal -Name "$Name should not skip" -Actual $Decision.Skipped -Expected $false
    Assert-Equal -Name "$Name replaced flag" -Actual $Decision.Replaced -Expected $Replaced
    Assert-Equal -Name "$Name reason should be empty" -Actual $Decision.Reason -Expected ""
    Assert-SequenceEqual -Name "$Name effects" -Actual $Decision.Effects -Expected @(
        "create-bin",
        "write-shim",
        "set-user-home",
        "set-process-home",
        "add-user-path"
    )
}

function Assert-UninstallsWithEffects {
    param(
        [string]$Name,
        [object]$Decision,
        [bool]$Forced,
        [string[]]$Effects,
        [string]$Reason = ""
    )

    Assert-Equal -Name "$Name should uninstall" -Actual $Decision.ShouldUninstall -Expected $true
    Assert-Equal -Name "$Name refused flag" -Actual $Decision.Refused -Expected $false
    Assert-Equal -Name "$Name forced flag" -Actual $Decision.Forced -Expected $Forced
    Assert-Equal -Name "$Name reason" -Actual $Decision.Reason -Expected $Reason
    Assert-SequenceEqual -Name "$Name effects" -Actual $Decision.Effects -Expected $Effects
}

$currentHome = "D:\adp-os\v2"
$previousHome = "D:\adp-os\v1"

$sameDecision = Get-ADPOSRegistrationDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $currentHome -IsDifferentHome $false) `
    -ProjectRoot $currentHome
Assert-RegistersWithEffects -Name "same checkout" -Decision $sameDecision -Replaced $false

$promptDecision = Get-ADPOSRegistrationDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $previousHome -IsDifferentHome $true) `
    -ProjectRoot $currentHome
Assert-Equal -Name "different checkout interactive should not register before confirmation" -Actual $promptDecision.ShouldRegister -Expected $false
Assert-Equal -Name "different checkout interactive should require confirmation" -Actual $promptDecision.RequiresConfirmation -Expected $true
Assert-Equal -Name "different checkout interactive should not skip before answer" -Actual $promptDecision.Skipped -Expected $false
Assert-Equal -Name "different checkout interactive prompt reason" -Actual $promptDecision.Reason -Expected "requires-confirmation"
Assert-EmptySequence -Name "different checkout prompt effects" -Actual $promptDecision.Effects

$skipDecision = Get-ADPOSRegistrationDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $previousHome -IsDifferentHome $true) `
    -ProjectRoot $currentHome `
    -NonInteractive
Assert-Equal -Name "different checkout noninteractive should not register" -Actual $skipDecision.ShouldRegister -Expected $false
Assert-Equal -Name "different checkout noninteractive registered flag" -Actual $skipDecision.Registered -Expected $false
Assert-Equal -Name "different checkout noninteractive should not require confirmation" -Actual $skipDecision.RequiresConfirmation -Expected $false
Assert-Equal -Name "different checkout noninteractive skipped flag" -Actual $skipDecision.Skipped -Expected $true
Assert-Equal -Name "different checkout noninteractive should not be replaced" -Actual $skipDecision.Replaced -Expected $false
Assert-Equal -Name "different checkout noninteractive skip reason" -Actual $skipDecision.Reason -Expected "kept-existing-global"
Assert-Equal -Name "different checkout previous home" -Actual $skipDecision.PreviousHome -Expected $previousHome
Assert-EmptySequence -Name "different checkout noninteractive effects" -Actual $skipDecision.Effects

$rejectedDecision = Get-ADPOSRegistrationDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $previousHome -IsDifferentHome $true) `
    -ProjectRoot $currentHome `
    -ReplacementAccepted $false
Assert-Equal -Name "rejected replacement should not register" -Actual $rejectedDecision.ShouldRegister -Expected $false
Assert-Equal -Name "rejected replacement should skip" -Actual $rejectedDecision.Skipped -Expected $true
Assert-Equal -Name "rejected replacement should not be replaced" -Actual $rejectedDecision.Replaced -Expected $false
Assert-Equal -Name "rejected replacement reason" -Actual $rejectedDecision.Reason -Expected "kept-existing-global"
Assert-EmptySequence -Name "rejected replacement effects" -Actual $rejectedDecision.Effects

$confirmedDecision = Get-ADPOSRegistrationDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $previousHome -IsDifferentHome $true) `
    -ProjectRoot $currentHome `
    -ReplacementAccepted $true
Assert-RegistersWithEffects -Name "confirmed replacement" -Decision $confirmedDecision -Replaced $true

$forceDecision = Get-ADPOSRegistrationDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $previousHome -IsDifferentHome $true) `
    -ProjectRoot $currentHome `
    -Force
Assert-RegistersWithEffects -Name "force replacement" -Decision $forceDecision -Replaced $true

$sameForceDecision = Get-ADPOSRegistrationDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $currentHome -IsDifferentHome $false) `
    -ProjectRoot $currentHome `
    -Force
Assert-RegistersWithEffects -Name "same checkout force" -Decision $sameForceDecision -Replaced $false

$sameUninstallDecision = Get-ADPOSUninstallDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $currentHome -ProcessHome $currentHome) `
    -ProjectRoot $currentHome
Assert-UninstallsWithEffects -Name "same checkout uninstall" -Decision $sameUninstallDecision -Forced $false -Effects @(
    "remove-shim",
    "remove-user-path",
    "remove-user-home",
    "remove-process-home"
)

$otherUninstallDecision = Get-ADPOSUninstallDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $previousHome -IsDifferentHome $true) `
    -ProjectRoot $currentHome
Assert-Equal -Name "different checkout uninstall should not uninstall" -Actual $otherUninstallDecision.ShouldUninstall -Expected $false
Assert-Equal -Name "different checkout uninstall should refuse" -Actual $otherUninstallDecision.Refused -Expected $true
Assert-Equal -Name "different checkout uninstall reason" -Actual $otherUninstallDecision.Reason -Expected "different-home"
Assert-EmptySequence -Name "different checkout uninstall effects" -Actual $otherUninstallDecision.Effects

$forceUninstallDecision = Get-ADPOSUninstallDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $previousHome -IsDifferentHome $true -ProcessHome $previousHome) `
    -ProjectRoot $currentHome `
    -Force
Assert-UninstallsWithEffects -Name "forced different checkout uninstall" -Decision $forceUninstallDecision -Forced $true -Effects @(
    "remove-shim",
    "remove-user-path",
    "remove-user-home",
    "remove-process-home"
)

$nonAdpShimDecision = Get-ADPOSUninstallDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $currentHome -ShimExists $true -ShimOwned $false) `
    -ProjectRoot $currentHome
Assert-Equal -Name "non-ADP shim uninstall should refuse" -Actual $nonAdpShimDecision.Refused -Expected $true
Assert-Equal -Name "non-ADP shim uninstall reason" -Actual $nonAdpShimDecision.Reason -Expected "non-adp-shim"
Assert-EmptySequence -Name "non-ADP shim uninstall effects" -Actual $nonAdpShimDecision.Effects

$staleUninstallDecision = Get-ADPOSUninstallDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome $currentHome -ShimExists $false -ShimOwned $false -ProcessHome $currentHome) `
    -ProjectRoot $currentHome
Assert-UninstallsWithEffects -Name "stale missing shim uninstall" -Decision $staleUninstallDecision -Forced $false -Effects @(
    "remove-user-path",
    "remove-user-home",
    "remove-process-home"
)

$emptyUninstallDecision = Get-ADPOSUninstallDecision `
    -ExistingRegistration (New-TestRegistration -RegistrationHome "" -ShimExists $false -ShimOwned $false -UserPathHasBin $false -UserHome "" -ProcessHome "") `
    -ProjectRoot $currentHome
Assert-UninstallsWithEffects -Name "empty uninstall" -Decision $emptyUninstallDecision -Forced $false -Effects @() -Reason "not-registered"

$guidance = Get-ADPOSMultiCheckoutGuidance -LocalCommand ".\adpos.cmd"
Assert-Equal -Name "guidance config path" -Actual $guidance.ConfigPath -Expected "configs\local.json"
Assert-SequenceEqual -Name "guidance config keys" -Actual $guidance.ConfigKeys -Expected @(
    "platform.runtime_namespace",
    "platform.paths.workspace_root",
    "platform.paths.vm_store",
    "topology.<runtime>.static_ip"
)
Assert-SequenceEqual -Name "guidance validation commands" -Actual $guidance.ValidationCommands -Expected @(
    ".\adpos.cmd doctor",
    ".\adpos.cmd status agent",
    ".\adpos.cmd sync status",
    ".\adpos.cmd up agent -Plan"
)

Write-Output "adpos registration decision tests OK"
