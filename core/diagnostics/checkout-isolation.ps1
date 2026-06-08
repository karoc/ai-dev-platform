# ADP-OS checkout isolation planner.
# Pure read-only helpers for multi-checkout local override previews.

. (Join-Path (Split-Path $PSScriptRoot -Parent) "runtime\runtime-identity.ps1")

function ConvertTo-ADPIsolationIPv4UInt32 {
    param([string]$Address)

    $parts = $Address -split '\.'
    if ($parts.Count -ne 4) {
        throw "Invalid IPv4 address: $Address"
    }

    $value = [uint32]0
    foreach ($part in $parts) {
        $octet = [int]$part
        if ($octet -lt 0 -or $octet -gt 255) {
            throw "Invalid IPv4 address: $Address"
        }
        $value = ([uint32]($value -shl 8)) -bor [uint32]$octet
    }

    return $value
}

function ConvertFrom-ADPIsolationIPv4UInt32 {
    param([uint32]$Value)

    return ("{0}.{1}.{2}.{3}" -f (($Value -shr 24) -band 255), (($Value -shr 16) -band 255), (($Value -shr 8) -band 255), ($Value -band 255))
}

function Get-ADPIsolationIPv4MaskUInt32 {
    param([int]$PrefixLength)

    if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) {
        throw "Invalid IPv4 prefix length: $PrefixLength"
    }
    if ($PrefixLength -eq 0) {
        return [uint32]0
    }

    return [uint32](([uint32]::MaxValue) -shl (32 - $PrefixLength))
}

function Get-ADPIsolationIPv4AddressInCidr {
    param(
        [string]$Cidr,
        [int]$HostOffset
    )

    $parts = $Cidr -split '/', 2
    if ($parts.Count -ne 2) {
        throw "Invalid CIDR: $Cidr"
    }

    $prefix = [int]$parts[1]
    $networkInt = ConvertTo-ADPIsolationIPv4UInt32 -Address $parts[0]
    $mask = Get-ADPIsolationIPv4MaskUInt32 -PrefixLength $prefix
    $network = $networkInt -band $mask
    return ConvertFrom-ADPIsolationIPv4UInt32 -Value ([uint32]($network + [uint32]$HostOffset))
}

function Get-ADPIsolationIPv4HostOffset {
    param(
        [string]$Address,
        [string]$Cidr
    )

    if ([string]::IsNullOrWhiteSpace($Address) -or [string]::IsNullOrWhiteSpace($Cidr)) {
        return $null
    }

    try {
        $parts = $Cidr -split '/', 2
        if ($parts.Count -ne 2) {
            return $null
        }

        $prefix = [int]$parts[1]
        $networkInt = ConvertTo-ADPIsolationIPv4UInt32 -Address $parts[0]
        $mask = Get-ADPIsolationIPv4MaskUInt32 -PrefixLength $prefix
        $network = $networkInt -band $mask
        $addressInt = ConvertTo-ADPIsolationIPv4UInt32 -Address $Address
        return [int]($addressInt - $network)
    } catch {
        return $null
    }
}

function Resolve-ADPCheckoutIsolationNamespace {
    param([string]$RequestedNamespace)

    if (-not [string]::IsNullOrWhiteSpace($RequestedNamespace)) {
        $normalizedRequestedNamespace = Normalize-ADPRuntimeNamespace -Namespace $RequestedNamespace
        if ([string]::IsNullOrWhiteSpace($normalizedRequestedNamespace)) {
            throw "Invalid checkout isolation namespace '$RequestedNamespace'. Use a specific namespace such as 'v2'."
        }

        return [pscustomobject]@{
            Namespace = $normalizedRequestedNamespace
            Source    = "argument"
        }
    }

    $platform = Get-PlatformConfig
    if ($platform.PSObject.Properties.Name -contains "runtime_namespace" -and -not [string]::IsNullOrWhiteSpace([string]$platform.runtime_namespace)) {
        $normalizedConfiguredNamespace = Normalize-ADPRuntimeNamespace -Namespace ([string]$platform.runtime_namespace)
        if (-not [string]::IsNullOrWhiteSpace($normalizedConfiguredNamespace)) {
            return [pscustomobject]@{
                Namespace = $normalizedConfiguredNamespace
                Source    = "current-config"
            }
        }
    }

    $leaf = Split-Path (Get-ProjectRoot) -Leaf
    $candidate = ($leaf.ToLowerInvariant() -replace '[^a-z0-9]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = "checkout"
    }
    if ($candidate.Length -gt 32) {
        $candidate = $candidate.Substring(0, 32).Trim('-')
    }
    if ([string]::IsNullOrWhiteSpace($candidate)) {
        $candidate = "checkout"
    }

    return [pscustomobject]@{
        Namespace = Normalize-ADPRuntimeNamespace -Namespace $candidate
        Source    = "checkout-directory"
    }
}

function Get-ADPCheckoutIsolationHostOffsetShift {
    param([string]$Namespace)

    $sum = 0
    foreach ($char in $Namespace.ToCharArray()) {
        $sum += [int][char]$char
    }

    return ((($sum % 6) + 1) * 10)
}

function Get-ADPCheckoutIsolationPathValue {
    param(
        [string]$BaseName,
        [string]$Namespace
    )

    return ('${env:USERPROFILE}\' + "$BaseName-$Namespace")
}

function Join-ADPCheckoutIsolationPath {
    param(
        [string]$BasePath,
        [string]$ChildPath
    )

    if ([string]::IsNullOrWhiteSpace($BasePath)) {
        return $ChildPath
    }
    if ([string]::IsNullOrWhiteSpace($ChildPath)) {
        return $BasePath
    }

    return ($BasePath.TrimEnd('\', '/') + '\' + $ChildPath.TrimStart('\', '/'))
}

function Get-ADPCheckoutIsolationRuntimeOffset {
    param(
        [string]$Address,
        [string]$Cidr,
        [int]$Fallback
    )

    $offset = Get-ADPIsolationIPv4HostOffset -Address $Address -Cidr $Cidr
    if ($null -ne $offset -and $offset -gt 2) {
        return [int]$offset
    }

    return $Fallback
}

function New-ADPCheckoutIsolationChange {
    param(
        [string]$Path,
        [string]$Current,
        [string]$Target,
        [string]$Reason
    )

    $currentValue = if ([string]::IsNullOrWhiteSpace($Current)) { "(not set)" } else { $Current }
    $targetValue = if ([string]::IsNullOrWhiteSpace($Target)) { "(not set)" } else { $Target }
    $status = if ($currentValue -eq $targetValue) {
        "already-isolated"
    } elseif ($currentValue -eq "(not set)") {
        "missing"
    } else {
        "suggested"
    }

    return [pscustomobject]@{
        Path    = $Path
        Current = $currentValue
        Target  = $targetValue
        Status  = $status
        Reason  = $Reason
    }
}

function Get-ADPCheckoutIsolationRuntimePlans {
    param(
        [object]$BaseTopology,
        [string]$BaseCidr,
        [string]$TargetCidr,
        [string]$Namespace,
        [string]$WorkspaceRoot,
        [string]$VmStore,
        [int]$OffsetShift
    )

    $plans = [System.Collections.Generic.List[object]]::new()
    $fallback = 131
    foreach ($name in (Get-AllRuntimeNames)) {
        $baseRuntime = $BaseTopology.$name
        $currentRuntime = Get-RuntimeConfig $name
        $baseIp = if ($baseRuntime -and $baseRuntime.PSObject.Properties.Name -contains "static_ip") { [string]$baseRuntime.static_ip } else { "" }
        $baseOffset = Get-ADPCheckoutIsolationRuntimeOffset -Address $baseIp -Cidr $BaseCidr -Fallback $fallback
        $targetOffset = $baseOffset + $OffsetShift
        if ($targetOffset -gt 240) {
            $targetOffset = 50 + ($targetOffset % 150)
        }

        $resourceNames = Get-ADPRuntimeResourceNames -TargetRuntime $name -Namespace $Namespace
        $sshPort = if ($currentRuntime.PSObject.Properties.Name -contains "ssh_port" -and $currentRuntime.ssh_port) { [int]$currentRuntime.ssh_port } else { 22 }
        $targetIp = Get-ADPIsolationIPv4AddressInCidr -Cidr $TargetCidr -HostOffset $targetOffset
        $plans.Add([pscustomobject]@{
            Runtime             = $name
            CurrentIp           = if ($currentRuntime.PSObject.Properties.Name -contains "static_ip") { [string]$currentRuntime.static_ip } else { "" }
            TargetIp            = $targetIp
            RuntimeResourceName = $resourceNames.RuntimeResourceName
            VmName              = $resourceNames.VmName
            VmDirectoryName     = $resourceNames.VmDirectoryName
            VmxPath             = Join-ADPCheckoutIsolationPath -BasePath $VmStore -ChildPath "$($resourceNames.VmDirectoryName)\$($resourceNames.VmxFileName)"
            WorkspacePath       = Join-ADPCheckoutIsolationPath -BasePath $WorkspaceRoot -ChildPath $currentRuntime.workspace
            SshAlias            = $resourceNames.SshAlias
            SshPort             = $sshPort
            MutagenSession      = $resourceNames.MutagenSession
            ExpectedRemoteUrl   = "$($resourceNames.SshAlias):/home/adp/workspace"
        }) | Out-Null
        $fallback += 2
    }

    return @($plans)
}

function Get-ADPCheckoutIsolationPlan {
    param([string]$RequestedNamespace)

    $projectRoot = Get-ProjectRoot
    $platform = Get-PlatformConfig
    $basePlatform = Read-JsonConfig (Join-Path $projectRoot "configs\platform.json")
    $baseTopology = Read-JsonConfig (Join-Path $projectRoot "configs\topology.json")
    $namespacePlan = Resolve-ADPCheckoutIsolationNamespace -RequestedNamespace $RequestedNamespace
    $workspaceRoot = Get-ADPCheckoutIsolationPathValue -BaseName "adp-workspaces" -Namespace $namespacePlan.Namespace
    $vmStore = Get-ADPCheckoutIsolationPathValue -BaseName "adp-vms" -Namespace $namespacePlan.Namespace
    $targetCidr = [string]$platform.network.vmware_nat.cidr
    $baseCidr = [string]$basePlatform.network.vmware_nat.cidr
    $runtimePlans = Get-ADPCheckoutIsolationRuntimePlans `
        -BaseTopology $baseTopology `
        -BaseCidr $baseCidr `
        -TargetCidr $targetCidr `
        -Namespace $namespacePlan.Namespace `
        -WorkspaceRoot $workspaceRoot `
        -VmStore $vmStore `
        -OffsetShift (Get-ADPCheckoutIsolationHostOffsetShift -Namespace $namespacePlan.Namespace)

    $changes = [System.Collections.Generic.List[object]]::new()
    $changes.Add((New-ADPCheckoutIsolationChange -Path "platform.runtime_namespace" -Current ([string]$platform.runtime_namespace) -Target $namespacePlan.Namespace -Reason "separates VM, SSH alias, and sync session names")) | Out-Null
    $changes.Add((New-ADPCheckoutIsolationChange -Path "platform.paths.workspace_root" -Current ([string]$platform.paths.workspace_root) -Target $workspaceRoot -Reason "keeps workspace data separate")) | Out-Null
    $changes.Add((New-ADPCheckoutIsolationChange -Path "platform.paths.vm_store" -Current ([string]$platform.paths.vm_store) -Target $vmStore -Reason "keeps VM files separate")) | Out-Null
    $changes.Add((New-ADPCheckoutIsolationChange -Path "platform.provider.config.vm_store" -Current ([string]$platform.provider.config.vm_store) -Target $vmStore -Reason "keeps provider VM store aligned")) | Out-Null
    foreach ($runtimePlan in $runtimePlans) {
        $changes.Add((New-ADPCheckoutIsolationChange -Path "topology.$($runtimePlan.Runtime).static_ip" -Current $runtimePlan.CurrentIp -Target $runtimePlan.TargetIp -Reason "avoids same-subnet runtime IP collision")) | Out-Null
    }

    return [pscustomobject]@{
        ProjectRoot       = $projectRoot
        LocalConfigPath   = Join-Path $projectRoot "configs\local.json"
        LocalConfigStatus = Get-LocalConfigStatus
        RequestedNamespace = $RequestedNamespace
        Namespace         = $namespacePlan.Namespace
        NamespaceSource   = $namespacePlan.Source
        WorkspaceRoot     = $workspaceRoot
        VmStore           = $vmStore
        RuntimePlans      = $runtimePlans
        Changes           = @($changes)
        ValidationRuntime = if ($runtimePlans.Runtime -contains "agent") { "agent" } else { $runtimePlans[0].Runtime }
    }
}

function ConvertTo-ADPCheckoutIsolationLocalJson {
    param([object]$IsolationPlan)

    $topology = [ordered]@{}
    foreach ($runtimePlan in @($IsolationPlan.RuntimePlans)) {
        $topology[$runtimePlan.Runtime] = [ordered]@{ static_ip = $runtimePlan.TargetIp }
    }

    $localConfig = [ordered]@{
        platform = [ordered]@{
            runtime_namespace = $IsolationPlan.Namespace
            paths = [ordered]@{
                workspace_root = $IsolationPlan.WorkspaceRoot
                vm_store       = $IsolationPlan.VmStore
            }
            provider = [ordered]@{
                config = [ordered]@{
                    vm_store = $IsolationPlan.VmStore
                }
            }
        }
        topology = $topology
    }

    return ($localConfig | ConvertTo-Json -Depth 20)
}
