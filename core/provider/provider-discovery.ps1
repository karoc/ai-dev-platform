# ADP-OS Provider Discovery Module
# Provider discovery and initialization — determines which VM provider
# to use based on configuration and loads it.
#
# Functions:
#   Get-ConfiguredProviderType    Read provider type from platform config
#   Initialize-Provider            Load and initialize the active provider
#   Get-ActiveProvider             Return the currently active provider name

$script:ActiveProvider = $null
$script:Initialized = $false

function Get-ConfiguredProviderType {
    <#
    .SYNOPSIS
    Resolves the configured VM provider type from platform configuration.

    .DESCRIPTION
    Reads platform.json and extracts the provider type. Supports both
    the new config format ({provider: {type: "vmware-workstation"}})
    and the legacy format ({features: {vmware: true}} -> "vmware-workstation").

    .PARAMETER Config
    Optional platform config hashtable. When omitted, calls Get-PlatformConfig
    from the config module (which must be loaded first).

    .EXAMPLE
    $providerType = Get-ConfiguredProviderType
    #>
    param($Config = $null)

    if (-not $Config) {
        if (Get-Command Get-PlatformConfig -ErrorAction SilentlyContinue) {
            $Config = Get-PlatformConfig
        } else {
            throw "Get-PlatformConfig not available — load core/config/config.ps1 first or pass -Config"
        }
    }

    # New format: provider.type
    if ($Config.provider -and $Config.provider.type) {
        return $Config.provider.type
    }

    # Legacy format: features.vmware
    if ($Config.features -and $Config.features.vmware) {
        return "vmware-workstation"
    }

    throw "No VM provider configured in platform.json"
}

function Initialize-Provider {
    <#
    .SYNOPSIS
    Load and initialize a VM provider by type.

    .DESCRIPTION
    Uses the provider registry to map a named provider type to its module
    file and initialization function. Dot-sources the module, calls its
    initialization function, and runs contract validation.
    Returns the result of Get-ProviderInfo from the loaded provider.

    .PARAMETER ProviderType
    The provider type name (e.g., "vmware-workstation", "hyper-v").

    .PARAMETER ProjectRoot
    Absolute path to the ADP-OS project root, used to resolve relative
    module paths.

    .PARAMETER InitArgs
    Additional arguments forwarded to the provider's initialization function
    (e.g., VmStorePath for VMware).

    .PARAMETER SkipValidation
    Skip the Test-ImplementsProvider contract check. Useful during
    development or when the contract module isn't yet loaded.

    .EXAMPLE
    $info = Initialize-Provider -ProviderType "vmware-workstation" `
        -ProjectRoot "D:\Dev\ai-dev-platform" `
        -InitArgs @{VmStorePath = "$env:USERPROFILE\adp-vms"}
    #>
    param(
        [Parameter(Mandatory=$true)]
        [string]$ProviderType,
        [Parameter(Mandatory=$true)]
        [string]$ProjectRoot,
        [hashtable]$InitArgs = @{},
        [switch]$SkipValidation
    )

    $providerMap = @{
        "vmware-workstation" = @{
            ModulePath = "adapters\windows\vmware\vmware-provider.ps1"
            InitFn     = "Initialize-VMwareProvider"
        }
        "hyper-v" = @{
            ModulePath = "adapters\windows\hyperv\hyperv-provider.ps1"
            InitFn     = "Initialize-HyperVProvider"
        }
    }

    $info = $providerMap[$ProviderType]
    if (-not $info) {
        throw "Unknown provider type: '$ProviderType'. Known types: $($providerMap.Keys -join ', ')"
    }

    $fullPath = Join-Path $ProjectRoot $info.ModulePath
    if (-not (Test-Path $fullPath)) {
        throw "Provider module not found: $fullPath"
    }

    # Dot-source the provider module into the current scope
    . $fullPath

    # Call the provider's initialization function
    $initFn = $info.InitFn
    $initCmd = Get-Command -Name $initFn -CommandType Function -ErrorAction Stop
    & $initFn @InitArgs

    # Validate the contract (optional)
    if (-not $SkipValidation) {
        if (Get-Command Test-ImplementsProvider -ErrorAction SilentlyContinue) {
            $validation = Test-ImplementsProvider -ModulePath $fullPath
            if (-not $validation.Success) {
                Write-Warning "Provider contract validation: $($validation.Error)"
            }
        }
    }

    $script:ActiveProvider = $ProviderType
    $script:Initialized = $true

    # Return provider info
    if (Get-Command Get-ProviderInfo -ErrorAction SilentlyContinue) {
        return Get-ProviderInfo
    }

    return Get-ProviderResultOK @{
        Name    = $ProviderType
        Status  = "initialized"
        Warning = "Get-ProviderInfo not exported by provider module"
    }
}

function Get-ActiveProvider {
    return $script:ActiveProvider
}
