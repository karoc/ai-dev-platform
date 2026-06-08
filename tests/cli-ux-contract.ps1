# ADP-OS CLI UX contract checks.
# Exercises typo recovery paths without mutating VM or host state.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$cliPath = Join-Path $projectRoot "cli\adp.ps1"
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source

function Invoke-AdposCli {
    param([string[]]$Arguments)

    $global:LASTEXITCODE = 0
    $output = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $cliPath @Arguments 2>&1 | Out-String
    return [pscustomobject]@{
        ExitCode = $LASTEXITCODE
        Output   = $output
    }
}

function Assert-Contains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "$Name did not contain expected pattern: $Pattern`nOutput:`n$Text"
    }
}

function Assert-ExitCode {
    param(
        [string]$Name,
        [int]$Actual,
        [int]$Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name expected exit code $Expected but got $Actual"
    }
}

$help = Invoke-AdposCli -Arguments @("help")
Assert-ExitCode -Name "adpos help" -Actual $help.ExitCode -Expected 0
Assert-Contains -Name "adpos help shows command overview" -Text $help.Output -Pattern "Commands:"
Assert-Contains -Name "adpos help includes setup" -Text $help.Output -Pattern "adpos setup"
Assert-Contains -Name "adpos help includes isolate" -Text $help.Output -Pattern "adpos isolate"
Assert-Contains -Name "adpos help includes uninstall" -Text $help.Output -Pattern "adpos uninstall"

$topLevelTypo = Invoke-AdposCli -Arguments @("hepl")
Assert-ExitCode -Name "adpos hepl" -Actual $topLevelTypo.ExitCode -Expected 1
Assert-Contains -Name "adpos hepl reports unknown command" -Text $topLevelTypo.Output -Pattern "Unknown command: hepl"
Assert-Contains -Name "adpos hepl suggests help" -Text $topLevelTypo.Output -Pattern "Did you mean: adpos help"
Assert-Contains -Name "adpos hepl gives recovery path" -Text $topLevelTypo.Output -Pattern "Run 'adpos help' to see full help"

$syncTypo = Invoke-AdposCli -Arguments @("sync", "stats")
Assert-ExitCode -Name "adpos sync stats" -Actual $syncTypo.ExitCode -Expected 1
Assert-Contains -Name "adpos sync typo reports unknown subcommand" -Text $syncTypo.Output -Pattern "Unknown sync command: stats"
Assert-Contains -Name "adpos sync typo suggests status" -Text $syncTypo.Output -Pattern "Did you mean: adpos sync status"
Assert-Contains -Name "adpos sync typo gives help path" -Text $syncTypo.Output -Pattern "Run 'adpos sync --help' for sync help"

$networkTypo = Invoke-AdposCli -Arguments @("network", "aplpy")
Assert-ExitCode -Name "adpos network aplpy" -Actual $networkTypo.ExitCode -Expected 1
Assert-Contains -Name "adpos network typo reports unknown subcommand" -Text $networkTypo.Output -Pattern "Unknown network command: aplpy"
Assert-Contains -Name "adpos network typo suggests apply" -Text $networkTypo.Output -Pattern "Did you mean: adpos network apply"
Assert-Contains -Name "adpos network typo gives help path" -Text $networkTypo.Output -Pattern "Run 'adpos network --help' for network help"

$global:LASTEXITCODE = 0
Write-Output "CLI UX contracts OK"
