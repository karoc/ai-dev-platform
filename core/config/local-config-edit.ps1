# ADP-OS local config edit helpers.
# Scoped writers for ignored configs/local.json overrides.

function Set-ADPJsonProperty {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        $Value
    )

    if ($Object.PSObject.Properties.Name -contains $Name) {
        $Object.$Name = $Value
    } else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

function Ensure-ADPJsonObjectProperty {
    param(
        [Parameter(Mandatory = $true)]
        [pscustomobject]$Object,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $currentValue = if ($Object.PSObject.Properties.Name -contains $Name) { $Object.$Name } else { $null }
    if (-not ($currentValue -is [pscustomobject])) {
        Set-ADPJsonProperty -Object $Object -Name $Name -Value ([pscustomobject]@{})
    }

    return $Object.$Name
}

function Read-ADPLocalConfigObject {
    param([string]$LocalConfigPath)

    if (-not (Test-Path -LiteralPath $LocalConfigPath)) {
        return [pscustomobject]@{}
    }

    $raw = Get-Content -LiteralPath $LocalConfigPath -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{}
    }

    return ($raw | ConvertFrom-Json)
}

function Backup-ADPLocalConfig {
    param([string]$LocalConfigPath)

    if (-not (Test-Path -LiteralPath $LocalConfigPath)) {
        return ""
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
    $backupPath = "$LocalConfigPath.bak.$timestamp"
    Copy-Item -LiteralPath $LocalConfigPath -Destination $backupPath -Force
    return $backupPath
}

function Get-ADPCheckoutIsolationChangedFields {
    param([object]$IsolationPlan)

    return @($IsolationPlan.Changes | Where-Object { $_.Status -ne "already-isolated" })
}

function Set-ADPCheckoutIsolationLocalConfig {
    param([object]$IsolationPlan)

    $changedFields = @(Get-ADPCheckoutIsolationChangedFields -IsolationPlan $IsolationPlan)
    if ($changedFields.Count -eq 0) {
        return [pscustomobject]@{
            Changed       = $false
            BackupPath    = ""
            LocalConfigPath = $IsolationPlan.LocalConfigPath
            ChangedFields = @()
        }
    }

    $localConfig = Read-ADPLocalConfigObject -LocalConfigPath $IsolationPlan.LocalConfigPath
    $platform = Ensure-ADPJsonObjectProperty -Object $localConfig -Name "platform"
    Set-ADPJsonProperty -Object $platform -Name "runtime_namespace" -Value $IsolationPlan.Namespace

    $paths = Ensure-ADPJsonObjectProperty -Object $platform -Name "paths"
    Set-ADPJsonProperty -Object $paths -Name "workspace_root" -Value $IsolationPlan.WorkspaceRoot
    Set-ADPJsonProperty -Object $paths -Name "vm_store" -Value $IsolationPlan.VmStore

    $provider = Ensure-ADPJsonObjectProperty -Object $platform -Name "provider"
    $providerConfig = Ensure-ADPJsonObjectProperty -Object $provider -Name "config"
    Set-ADPJsonProperty -Object $providerConfig -Name "vm_store" -Value $IsolationPlan.VmStore

    $topology = Ensure-ADPJsonObjectProperty -Object $localConfig -Name "topology"
    foreach ($runtimePlan in @($IsolationPlan.RuntimePlans)) {
        $runtime = Ensure-ADPJsonObjectProperty -Object $topology -Name $runtimePlan.Runtime
        Set-ADPJsonProperty -Object $runtime -Name "static_ip" -Value $runtimePlan.TargetIp
    }

    $backupPath = Backup-ADPLocalConfig -LocalConfigPath $IsolationPlan.LocalConfigPath
    $json = $localConfig | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $IsolationPlan.LocalConfigPath -Value $json -Encoding utf8

    return [pscustomobject]@{
        Changed       = $true
        BackupPath    = $backupPath
        LocalConfigPath = $IsolationPlan.LocalConfigPath
        ChangedFields = $changedFields
    }
}
