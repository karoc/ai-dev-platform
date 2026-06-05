# ADP-OS Provider Result Module
# Standardized result object for all VM Provider operations.
#
# Uses [PSCustomObject] + factory functions instead of PowerShell classes
# to avoid PS 5.1 class-redefinition crashes when multiple .ps1 files are
# dot-sourced into the same session.
#
# Functions:
#   New-ProviderResult        Raw constructor — requires all fields
#   Get-ProviderResultOK      Success factory (Success=$true)
#   Get-ProviderResultFail    Failure factory (Success=$false)

function New-ProviderResult {
    param(
        [bool]$Success,
        [object]$Data = $null,
        [string]$Error = ""
    )
    return [PSCustomObject]@{
        Success = $Success
        Data    = $Data
        Error   = $Error
    }
}

function Get-ProviderResultOK {
    param([object]$Data = $null)
    return New-ProviderResult -Success $true -Data $Data
}

function Get-ProviderResultFail {
    param([string]$Error)
    return New-ProviderResult -Success $false -Error $Error
}

# Convenience checker
function Test-ProviderResultOK {
    param([PSCustomObject]$Result)
    return ($null -ne $Result -and $Result.Success)
}
