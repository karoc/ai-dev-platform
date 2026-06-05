# ADP-OS Configuration Module
# Platform-agnostic configuration loader with Host Adapter Layer
# Do NOT hardcode paths; use this module's resolution functions.

$script:_ProjectRoot = $null
$script:PlatformConfig = $null
$script:TopologyConfig = $null
$script:SyncProfiles = $null
$script:LocalConfigStatus = $null
$script:SupportedUILanguages = @("en", "zh-CN")

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
        Path                = $localConfigPath
        Exists              = $false
        Empty               = $false
        Applied             = $false
        Sections            = @()
        UnsupportedSections = @()
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

    $supportedSections = @("platform", "topology", "sync_profiles")
    $script:LocalConfigStatus.UnsupportedSections = @(
        $localConfig.PSObject.Properties.Name | Where-Object { $_ -notin $supportedSections }
    )

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

function Get-SupportedUILanguages {
    return $script:SupportedUILanguages
}

function Normalize-UILanguage {
    param([string]$Language)

    if ([string]::IsNullOrWhiteSpace($Language)) {
        return "en"
    }

    $normalized = $Language.Trim()
    switch ($normalized.ToLowerInvariant()) {
        "en" { return "en" }
        "en-us" { return "en" }
        "zh" { return "zh-CN" }
        "zh-cn" { return "zh-CN" }
        "zh_cn" { return "zh-CN" }
        default {
            if ($normalized -in $script:SupportedUILanguages) {
                return $normalized
            }
            return "en"
        }
    }
}

function Get-UILanguage {
    $envLanguage = [System.Environment]::GetEnvironmentVariable("ADP_LANG")
    if (-not [string]::IsNullOrWhiteSpace($envLanguage)) {
        return Normalize-UILanguage $envLanguage
    }

    $config = Get-PlatformConfig
    if ($config -and
        $config.PSObject.Properties.Name -contains "ui" -and
        $config.ui -and
        $config.ui.PSObject.Properties.Name -contains "language") {
        return Normalize-UILanguage ([string]$config.ui.language)
    }

    return "en"
}

function Get-UIText {
    param(
        [string]$English,
        [string]$Chinese
    )

    if ((Get-UILanguage) -eq "zh-CN") {
        return $Chinese
    }

    return $English
}

function Write-UIHost {
    param(
        [string]$English,
        [string]$Chinese,
        [System.ConsoleColor]$ForegroundColor = [System.ConsoleColor]::Gray,
        [switch]$NoNewline
    )

    $text = Get-UIText -English $English -Chinese $Chinese
    if ($NoNewline) {
        Write-Host $text -ForegroundColor $ForegroundColor -NoNewline
    } else {
        Write-Host $text -ForegroundColor $ForegroundColor
    }
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

function Test-RuntimeAgentProfile {
    param(
        [string]$RuntimeName,
        [object]$Runtime = $null
    )

    return (Get-RuntimeProfileName -RuntimeName $RuntimeName -Runtime $Runtime) -eq "agent-high-io"
}

function Get-RuntimeProfileName {
    param(
        [string]$RuntimeName,
        [object]$Runtime = $null
    )

    $rt = if ($Runtime) { $Runtime } else { Get-RuntimeConfig $RuntimeName }

    if ($rt.PSObject.Properties.Name -contains "profile" -and -not [string]::IsNullOrWhiteSpace([string]$rt.profile)) {
        return [string]$rt.profile
    }

    if ($RuntimeName -eq "agent" -and
        $rt.PSObject.Properties.Name -contains "danger" -and
        [bool]$rt.danger) {
        return "agent-high-io"
    }

    return "standard"
}

function Get-RuntimeProfileBadge {
    param(
        [string]$RuntimeName,
        [object]$Runtime = $null
    )

    if (Test-RuntimeAgentProfile -RuntimeName $RuntimeName -Runtime $Runtime) {
        return Get-UIText -English " [agent/high-IO]" -Chinese " [Agent 高 IO]"
    }

    return ""
}

function Get-RuntimeProfileNoticeLines {
    param(
        [string]$RuntimeName,
        [object]$Runtime = $null
    )

    return @((Get-RuntimeProfileNoticeItems -RuntimeName $RuntimeName -Runtime $Runtime) | ForEach-Object { $_.Text })
}

function Get-RuntimeProfileNoticeItems {
    param(
        [string]$RuntimeName,
        [object]$Runtime = $null
    )

    if (-not (Test-RuntimeAgentProfile -RuntimeName $RuntimeName -Runtime $Runtime)) {
        return @()
    }

    return @(
        [pscustomobject]@{
            Text  = Get-UIText -English "  Agent profile: high-IO runtime for AI agent workloads" -Chinese "  Agent profile: 面向 AI agent 工作负载的高 IO 运行时"
            Color = "Yellow"
        },
        [pscustomobject]@{
            Text  = Get-UIText -English "  Snapshot recommended before destructive or large-scale tasks." -Chinese "  建议在破坏性或大范围任务前创建快照。"
            Color = "DarkGray"
        }
    )
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

# ============================================================
# Provider Configuration — Phase 4
# Reads the provider block from platform.json with fallback
# to legacy features.vmware + network.vmware_nat fields.
# ============================================================

function Get-ProviderMode {
    <#
    .SYNOPSIS
    Returns the active VM provider mode from platform configuration.

    .DESCRIPTION
    Reads provider.mode from platform.json. The feature flag controls
    whether CLI commands use the new Provider interface (vmware-provider)
    or the old VMware adapter path (vmware-classic).

    Modes:
      - vmware-provider  (default) — use IVMProvider contract + vmware-provider.ps1
      - vmware-classic              — use legacy vmware.ps1 adapter directly

    When no provider block exists (legacy config), defaults to vmware-provider
    since Phase 3 migrated all CLI commands to the Provider interface.

    .EXAMPLE
    $mode = Get-ProviderMode
    if ($mode -eq "vmware-classic") { . "...\adapters\windows\vmware\vmware.ps1" }
    #>
    $config = Get-PlatformConfig

    if ($config -and $config.PSObject.Properties.Name -contains "provider") {
        $provider = $config.provider
        if ($provider.PSObject.Properties.Name -contains "mode" -and $provider.mode) {
            return $provider.mode
        }
        return "vmware-provider"
    }

    # No provider block — legacy config. Phase 3 already migrated all
    # CLI commands to the Provider interface, so default to provider path.
    return "vmware-provider"
}

function Get-ProviderConfig {
    <#
    .SYNOPSIS
    Returns a normalized provider configuration object.

    .DESCRIPTION
    Reads from the new provider block when present, falling back to legacy
    fields (features.vmware, paths.vm_store, network.vmware_nat) when not.
    Returns a PSCustomObject with Mode, Type, VmStore, VmrunPath, and Nat.

    .EXAMPLE
    $cfg = Get-ProviderConfig
    # $cfg.Mode       — "vmware-provider" or "vmware-classic"
    # $cfg.Type       — "vmware-workstation"
    # $cfg.VmStore    — resolved VM store path
    # $cfg.VmrunPath  — explicit vmrun.exe path or $null
    # $cfg.Nat        — PSCustomObject with Cidr, Prefix, Gateway, Dns, InterfaceMatch
    #>
    $config = Get-PlatformConfig

    $result = [PSCustomObject]@{
        Mode      = "vmware-provider"
        Type      = "vmware-workstation"
        VmStore   = $null
        VmrunPath = $null
        Nat       = $null
    }

    # New format: provider block
    if ($config -and $config.PSObject.Properties.Name -contains "provider") {
        $p = $config.provider

        # Mode
        if ($p.PSObject.Properties.Name -contains "mode" -and $p.mode) {
            $result.Mode = $p.mode
        }

        # Type
        if ($p.PSObject.Properties.Name -contains "type" -and $p.type) {
            $result.Type = $p.type
        }

        # Config sub-block
        if ($p.PSObject.Properties.Name -contains "config" -and $p.config) {
            $pc = $p.config
            if ($pc.PSObject.Properties.Name -contains "vm_store" -and $pc.vm_store) {
                $result.VmStore = $pc.vm_store
            }
            if ($pc.PSObject.Properties.Name -contains "vmrun_path" -and $pc.vmrun_path) {
                $result.VmrunPath = $pc.vmrun_path
            }
            if ($pc.PSObject.Properties.Name -contains "nat" -and $pc.nat) {
                $result.Nat = $pc.nat
            }
        }
    }

    # Legacy fallback: vm_store from paths
    if (-not $result.VmStore) {
        if ($config -and $config.PSObject.Properties.Name -contains "paths" -and $config.paths.vm_store) {
            $result.VmStore = $config.paths.vm_store
        }
    }

    # Legacy fallback: NAT from network.vmware_nat
    if (-not $result.Nat) {
        if ($config -and $config.PSObject.Properties.Name -contains "network" -and $config.network.vmware_nat) {
            $result.Nat = $config.network.vmware_nat
        }
    }

    return $result
}
