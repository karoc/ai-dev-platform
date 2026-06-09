# ADP-OS sandbox parameter binding contract checks.
# Verifies sandbox command arguments bind as a command, not as sandbox options.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$sandboxCommandPath = Join-Path $projectRoot "cli\commands\sandbox.ps1"

function Quote-TestPowerShellArgument {
    param([string]$Value)

    return ([char]39 + ($Value -replace [char]39, ([char]39 + [char]39)) + [char]39)
}

function Get-SandboxBindingProbeScriptBlock {
    $source = Get-Content -LiteralPath $sandboxCommandPath -Raw -Encoding UTF8
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors -and $parseErrors.Count -gt 0) {
        throw "Could not parse sandbox command: $($parseErrors[0].Message)"
    }

    $prelude = (@($ast.ParamBlock.Attributes | ForEach-Object { $_.Extent.Text }) + $ast.ParamBlock.Extent.Text) -join "`n"
    $probeBody = '[pscustomobject]@{ CommandArgs = $CommandArgs; Distro = $Distro; IsoPath = $IsoPath }'
    return [scriptblock]::Create($prelude + "`n" + $probeBody)
}

function Invoke-SandboxBindingProbe {
    param([string[]]$RawArguments)

    $probe = Get-SandboxBindingProbeScriptBlock
    $parts = @('& $probe')
    foreach ($argument in $RawArguments) {
        if ($argument -match '^-{1,2}[A-Za-z][A-Za-z0-9_-]*$') {
            $parts += $argument
        } else {
            $parts += (Quote-TestPowerShellArgument -Value $argument)
        }
    }

    $invoke = [scriptblock]::Create($parts -join " ")
    & $invoke
}

function Assert-SequenceEqual {
    param(
        [string]$Name,
        [string[]]$Actual,
        [string[]]$Expected
    )

    $actualText = @($Actual) -join "|"
    $expectedText = @($Expected) -join "|"
    if ($actualText -ne $expectedText) {
        throw "$Name expected [$expectedText] but got [$actualText]"
    }
}

$basic = Invoke-SandboxBindingProbe -RawArguments @("curl", "--silent")
Assert-SequenceEqual -Name "sandbox command args keep command switches" -Actual $basic.CommandArgs -Expected @("curl", "--silent")
if ($basic.Distro -ne "ubuntu-26.04" -or $basic.IsoPath) {
    throw "sandbox command args should not bind to Distro or IsoPath"
}

$withDistro = Invoke-SandboxBindingProbe -RawArguments @("-Distro", "ubuntu-26.04", "curl", "--silent")
Assert-SequenceEqual -Name "sandbox command args after Distro" -Actual $withDistro.CommandArgs -Expected @("curl", "--silent")
if ($withDistro.Distro -ne "ubuntu-26.04" -or $withDistro.IsoPath) {
    throw "sandbox -Distro should not consume command arguments"
}

$withIso = Invoke-SandboxBindingProbe -RawArguments @("-IsoPath", "foo.iso", "curl", "--silent")
Assert-SequenceEqual -Name "sandbox command args after IsoPath" -Actual $withIso.CommandArgs -Expected @("curl", "--silent")
if ($withIso.IsoPath -ne "foo.iso" -or $withIso.Distro -ne "ubuntu-26.04") {
    throw "sandbox -IsoPath should bind only IsoPath"
}

$optionAfterCommand = Invoke-SandboxBindingProbe -RawArguments @("curl", "--silent", "-Distro", "ubuntu-26.04")
Assert-SequenceEqual -Name "sandbox command args keep later option-looking tokens" -Actual $optionAfterCommand.CommandArgs -Expected @("curl", "--silent")
if ($optionAfterCommand.Distro -ne "ubuntu-26.04") {
    throw "sandbox named options should still bind when provided after command tokens"
}

Write-Output "sandbox parameter binding contracts OK"
