# ADP-OS Configuration Module
# Platform-agnostic configuration loader with Host Adapter Layer
# Do NOT hardcode paths; use this module's resolution functions.

$script:_ProjectRoot = $null
$script:PlatformConfig = $null
$script:TopologyConfig = $null
$script:SyncProfiles = $null
$script:LocalConfigStatus = $null

function Read-JsonConfig {
    param([string]$Path)

    $raw = Get-Content $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }

    return $raw | ConvertFrom-Json
}

function Merge-ConfigObject {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Base,
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Override
    )

    foreach ($property in $Override.PSObject.Properties) {
        $name = $property.Name
        $overrideValue = $property.Value

        if ($Base.PSObject.Properties.Name -contains $name) {
            $baseValue = $Base.$name
            $baseIsObject = $baseValue -is [pscustomobject]
            $overrideIsObject = $overrideValue -is [pscustomobject]

            if ($baseIsObject -and $overrideIsObject) {
                Merge-ConfigObject -Base $baseValue -Override $overrideValue
            } else {
                $Base.$name = $overrideValue
            }
        } else {
            $Base | Add-Member -NotePropertyName $name -NotePropertyValue $overrideValue
        }
    }
}

function Apply-LocalConfig {
    param([string]$ProjectRoot)

    $localConfigPath = Join-Path $ProjectRoot "configs\local.json"
    $script:LocalConfigStatus = [pscustomobject]@{
        Path     = $localConfigPath
        Exists   = $false
        Empty    = $false
        Applied  = $false
        Sections = @()
    }

    if (-not (Test-Path $localConfigPath)) {
        return
    }

    $script:LocalConfigStatus.Exists = $true

    $localConfig = Read-JsonConfig $localConfigPath
    if (-not $localConfig) {
        $script:LocalConfigStatus.Empty = $true
        Write-Verbose "ADP-OS local config exists but is empty: $localConfigPath"
        return
    }

    $sections = [System.Collections.Generic.List[string]]::new()
    if ($localConfig.PSObject.Properties.Name -contains "platform" -and $localConfig.platform) {
        Merge-ConfigObject -Base $script:PlatformConfig -Override $localConfig.platform
        $sections.Add("platform") | Out-Null
    }

    if ($localConfig.PSObject.Properties.Name -contains "topology" -and $localConfig.topology) {
        Merge-ConfigObject -Base $script:TopologyConfig -Override $localConfig.topology
        $sections.Add("topology") | Out-Null
    }

    if ($localConfig.PSObject.Properties.Name -contains "sync_profiles" -and $localConfig.sync_profiles) {
        Merge-ConfigObject -Base $script:SyncProfiles -Override $localConfig.sync_profiles
        $sections.Add("sync_profiles") | Out-Null
    }

    $script:LocalConfigStatus.Sections = @($sections)
    $script:LocalConfigStatus.Applied = ($sections.Count -gt 0)
    Write-Verbose "ADP-OS local config applied from: $localConfigPath"
}

function Initialize-Config {
    param(
        [string]$ProjectRoot
    )

    $script:_ProjectRoot = $ProjectRoot

    $script:PlatformConfig = Read-JsonConfig (Join-Path $ProjectRoot "configs\platform.json")
    $script:TopologyConfig = Read-JsonConfig (Join-Path $ProjectRoot "configs\topology.json")
    $script:SyncProfiles = Read-JsonConfig (Join-Path $ProjectRoot "configs\sync-profiles.json")
    Apply-LocalConfig -ProjectRoot $ProjectRoot

    Write-Verbose "ADP-OS Config initialized from: $ProjectRoot"
}

function Get-PlatformConfig {
    return $script:PlatformConfig
}

function Get-LocalConfigStatus {
    return $script:LocalConfigStatus
}

function Get-TopologyConfig {
    return $script:TopologyConfig
}

function Get-RuntimeConfig {
    param([string]$RuntimeName)

    $topo = Get-TopologyConfig
    $runtime = $topo.$RuntimeName

    if (-not $runtime) {
        throw "Runtime '$RuntimeName' not found in topology.json"
    }

    return $runtime
}

function Get-SyncProfile {
    param([string]$ProfileName)

    $profile = $script:SyncProfiles.$ProfileName
    if (-not $profile) {
        throw "Sync profile '$ProfileName' not found"
    }

    return $profile
}

function Resolve-Path {
    param([string]$PathKey)

    $config = Get-PlatformConfig
    $raw = $config.paths.$PathKey

    if (-not $raw) {
        throw "Path key '$PathKey' not found in platform.json"
    }

    $resolved = $raw -replace '\$\{project:root\}', $script:_ProjectRoot

    # Resolve ${env:VARNAME} placeholders
    $match = [regex]::Match($resolved, '\$\{env:(\w+)\}')
    while ($match.Success) {
        $envName = $match.Groups[1].Value
        $envValue = [System.Environment]::GetEnvironmentVariable($envName)
        $resolved = $resolved -replace [regex]::Escape($match.Value), $envValue
        $match = [regex]::Match($resolved, '\$\{env:(\w+)\}')
    }

    return $resolved
}

function Get-ProjectRoot {
    return $script:_ProjectRoot
}

function Get-AllRuntimeNames {
    $topo = Get-TopologyConfig
    return $topo.PSObject.Properties.Name
}

function Test-RuntimeExists {
    param([string]$RuntimeName)
    $topo = Get-TopologyConfig
    return $null -ne $topo.$RuntimeName
}

function Get-RuntimeStaticIP {
    param([string]$RuntimeName)

    $runtime = Get-RuntimeConfig $RuntimeName
    if ($runtime.PSObject.Properties.Name -contains "static_ip" -and -not [string]::IsNullOrWhiteSpace($runtime.static_ip)) {
        return $runtime.static_ip
    }

    return $null
}

function Get-Platform {
    if ($IsWindows) { return "windows" }
    if ($IsMacOS)   { return "mac" }
    if ($IsLinux)   { return "linux" }
    return "unknown"
}
