# ADP-OS Provider Interface Contract
# Defines the IVMProvider interface contract that all VM providers must
# implement. PowerShell has no native interface/abstract class support,
# so this uses convention-based contracts: each provider module must
# export the functions listed below.
#
# Functions:
#   Test-ImplementsProvider    Validate a provider module against the contract
#   Get-ProviderContract       Return the list of required function names
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
# Contract functions (optional — checked by capability flags):
#   Clone-VM, Get-VMInfo, Set-VMResources,
#   Get-ProviderCapabilities, Get-ProviderNatInfo

$script:RequiredFunctions = @(
    "Get-ProviderInfo",
    "New-VM",
    "Start-VM",
    "Stop-VM",
    "Restart-VM",
    "Get-VMStatus",
    "Get-VMIP",
    "Remove-VM",
    "New-Snapshot",
    "Restore-Snapshot",
    "Get-SnapshotList"
)

$script:OptionalFunctions = @(
    "Clone-VM",
    "Get-VMInfo",
    "Set-VMResources",
    "Get-ProviderCapabilities",
    "Get-ProviderNatInfo"
)

function Get-ProviderContract {
    return @{
        Required = $script:RequiredFunctions
        Optional = $script:OptionalFunctions
    }
}

function Test-ImplementsProvider {
    <#
    .SYNOPSIS
    Validates that a provider module satisfies the IVMProvider contract.

    .DESCRIPTION
    Dot-sources the provider module, then checks that all required contract
    functions are defined as PowerShell functions in the current scope.
    Optional functions are reported but not required.

    .PARAMETER ModulePath
    Path to the provider .ps1 module file.

    .EXAMPLE
    $result = Test-ImplementsProvider -ModulePath "adapters/windows/vmware/vmware-provider.ps1"
    if (-not $result.Success) { throw $result.Error }
    #>
    param([string]$ModulePath)

    if (-not (Test-Path $ModulePath)) {
        return Get-ProviderResultFail "Provider module not found: $ModulePath"
    }

    # Dot-source in a child scope so we don't pollute the caller
    $missing = @()
    & {
        . $ModulePath

        foreach ($fn in $script:RequiredFunctions) {
            $cmd = Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue
            if (-not $cmd) {
                $missing += $fn
            }
        }
    }

    if ($missing.Count -gt 0) {
        return Get-ProviderResultFail "Missing required functions: $($missing -join ', ')"
    }

    $optionalFound = @()
    & {
        . $ModulePath
        foreach ($fn in $script:OptionalFunctions) {
            if (Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue) {
                $optionalFound += $fn
            }
        }
    }

    return Get-ProviderResultOK @{
        ModulePath      = (Resolve-Path $ModulePath).Path
        RequiredCount   = $script:RequiredFunctions.Count
        OptionalFound   = $optionalFound
        OptionalMissing = @($script:OptionalFunctions | Where-Object { $_ -notin $optionalFound })
    }
}
