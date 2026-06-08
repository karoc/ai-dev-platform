# ADP-OS SSH alias ownership contract tests.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

. (Join-Path $projectRoot "core\diagnostics\ssh-alias.ps1")

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

$profile = [pscustomobject]@{
    SshAlias   = "adp-os-adp-agent"
    StaticIp   = "192.168.242.135"
    SshUser    = "adp"
    SshPort    = 22
    SshKeyPath = "C:\Users\tester\.ssh\adp-os\adp-os"
}

$missingConfigPath = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-missing-ssh-config-{0}" -f ([guid]::NewGuid().ToString("N")))
$missingConfig = Get-ADPSshAliasOwnershipStatus -Profile $profile -ConfigPath $missingConfigPath
Assert-Equal -Name "missing config status" -Actual $missingConfig.Status -Expected "missing-config"
Assert-True -Name "missing config is not written" -Condition (-not (Test-Path -LiteralPath $missingConfigPath))

$missingAlias = Get-ADPSshAliasOwnershipStatus -Profile $profile -ConfigText "Host github.com`n    HostName github.com"
Assert-Equal -Name "missing alias status" -Actual $missingAlias.Status -Expected "missing-alias"

$matchingConfig = @"
# >>> ADP-OS adp-os-adp-agent >>>
Host adp-os-adp-agent
    HostName 192.168.242.135
    User adp
    Port 22
    IdentityFile C:/Users/tester/.ssh/adp-os/adp-os
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile NUL
# <<< ADP-OS adp-os-adp-agent <<<
"@

$matching = Get-ADPSshAliasOwnershipStatus -Profile $profile -ConfigText $matchingConfig
Assert-Equal -Name "matching alias status" -Actual $matching.Status -Expected "current-checkout"
Assert-True -Name "matching alias owned by ADP marker" -Condition $matching.OwnedByADP
Assert-True -Name "matching alias has no conflict" -Condition (-not $matching.HasConflict)

$wrongHostConfig = $matchingConfig -replace "192\.168\.242\.135", "192.168.242.199"
$wrongHost = Get-ADPSshAliasOwnershipStatus -Profile $profile -ConfigText $wrongHostConfig
Assert-Equal -Name "wrong host status" -Actual $wrongHost.Status -Expected "alias-mismatch"
Assert-True -Name "wrong host has conflict" -Condition $wrongHost.HasConflict
Assert-Equal -Name "wrong host mismatch field" -Actual $wrongHost.Mismatches[0] -Expected "HostName"

$wrongIdentityConfig = $matchingConfig -replace "C:/Users/tester/.ssh/adp-os/adp-os", "D:/other-checkout/.ssh/adp-os"
$wrongIdentity = Get-ADPSshAliasOwnershipStatus -Profile $profile -ConfigText $wrongIdentityConfig
Assert-Equal -Name "wrong identity status" -Actual $wrongIdentity.Status -Expected "alias-mismatch"
Assert-True -Name "wrong identity mismatch field" -Condition (@($wrongIdentity.Mismatches) -contains "IdentityFile")

$unmanagedConfig = @"
Host adp-os-adp-agent
    HostName 192.168.242.135
    User adp
    Port 22
    IdentityFile C:\Users\tester\.ssh\adp-os\adp-os

Host another-host
    HostName 192.168.242.200
"@

$unmanaged = Get-ADPSshAliasOwnershipStatus -Profile $profile -ConfigText $unmanagedConfig
Assert-Equal -Name "unmanaged matching alias status" -Actual $unmanaged.Status -Expected "unmanaged-current"
Assert-True -Name "unmanaged alias is not ADP owned" -Condition (-not $unmanaged.OwnedByADP)
Assert-True -Name "unmanaged matching alias has no conflict" -Condition (-not $unmanaged.HasConflict)

$json = ConvertTo-ADPSshAliasOwnershipJson -AliasStatus $wrongHost
Assert-Equal -Name "json exposes alias" -Actual $json.HostAlias -Expected "adp-os-adp-agent"
Assert-True -Name "json exposes mismatch" -Condition (@($json.Mismatches) -contains "HostName")

Write-Output "SSH alias contracts OK"
exit 0
