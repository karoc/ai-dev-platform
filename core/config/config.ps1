# ADP-OS Configuration Module
# Platform-agnostic configuration loader with Host Adapter Layer
# Do NOT hardcode paths; use this module's resolution functions.

$script:_ProjectRoot = $null
$script:PlatformConfig = $null
$script:TopologyConfig = $null
$script:SyncProfiles = $null

function Initialize-Config {
    param(
        [string]$ProjectRoot
    )

    $script:_ProjectRoot = $ProjectRoot

    $script:PlatformConfig = Get-Content (Join-Path $ProjectRoot "configs\platform.json") -Raw | ConvertFrom-Json
    $script:TopologyConfig = Get-Content (Join-Path $ProjectRoot "configs\topology.json") -Raw | ConvertFrom-Json
    $script:SyncProfiles = Get-Content (Join-Path $ProjectRoot "configs\sync-profiles.json") -Raw | ConvertFrom-Json

    Write-Verbose "ADP-OS Config initialized from: $ProjectRoot"
}

function Get-PlatformConfig {
    return $script:PlatformConfig
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
