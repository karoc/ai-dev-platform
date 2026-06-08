# ADP-OS up command provision marker contract checks
# Guards against treating already-provisioned VMs as still INSTALLING when SSH is unavailable.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$upPath = Join-Path $projectRoot "cli\commands\up.ps1"
$up = Get-Content -LiteralPath $upPath -Raw

function Assert-Contains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "$Name did not contain expected pattern: $Pattern"
    }
}

Assert-Contains `
    -Name "up probes provision marker through VMware Tools guest operation" `
    -Text $up `
    -Pattern 'function\s+Test-GuestProvisionMarkerViaVmwareTools[\s\S]*/home/adp/\.adp-provisioned[\s\S]*runProgramInGuest[\s\S]*-TimeoutSeconds\s+15'

Assert-Contains `
    -Name "up rechecks the ADP connection IP over SSH before declaring SSH not ready" `
    -Text $up `
    -Pattern 'function\s+Test-RuntimeConnectionProvisionMarkerViaSSH[\s\S]*Get-RuntimeStaticIP \$TargetRuntime[\s\S]*Invoke-AdpSshCommand[\s\S]*/home/adp/\.adp-provisioned'

Assert-Contains `
    -Name "up bounds SSH provision marker probe and reports timeout" `
    -Text $up `
    -Pattern 'function\s+Test-RuntimeConnectionProvisionMarkerViaSSH[\s\S]*-TimeoutSeconds 12[\s\S]*ssh-timeout[\s\S]*SSH provision marker probe timed out'

Assert-Contains `
    -Name "up reports provisioned network/SSH-not-ready state instead of installing" `
    -Text $up `
    -Pattern 'function\s+Write-ProvisionedNetworkNotReadyGuidance[\s\S]*not an Ubuntu install in progress[\s\S]*State: provisioned, network/SSH not ready'

Assert-Contains `
    -Name "up gives doctor and network apply guidance for provisioned drift" `
    -Text $up `
    -Pattern 'function\s+Write-ProvisionedNetworkNotReadyGuidance[\s\S]*adp doctor[\s\S]*adp network apply \$TargetRuntime -Plan[\s\S]*adp network apply \$TargetRuntime'

Assert-Contains `
    -Name "up checks VMware Tools marker before entering autoinstall monitor" `
    -Text $up `
    -Pattern 'Test-AutoinstallReady -RuntimeName \$TargetRuntime[\s\S]*Test-RuntimeConnectionProvisionMarkerViaSSH -TargetRuntime \$TargetRuntime -TargetVmxPath \$TargetVmxPath[\s\S]*Test-GuestProvisionMarkerViaVmwareTools -TargetRuntime \$TargetRuntime -TargetVmxPath \$TargetVmxPath[\s\S]*if\s*\(\$provisionMarker\.Provisioned\)[\s\S]*Write-ProvisionedNetworkNotReadyGuidance[\s\S]*return[\s\S]*Wait-AutoinstallComplete -VmxPath \$TargetVmxPath -RuntimeName \$TargetRuntime -TimeoutMinutes 60'

Assert-Contains `
    -Name "validate runs up provision marker contract" `
    -Text (Get-Content -LiteralPath (Join-Path $projectRoot "tests\validate.ps1") -Raw) `
    -Pattern 'tests\\up-provision-marker-contract\.ps1'

Write-Output "up provision marker contract OK"
