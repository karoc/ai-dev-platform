# ADP-OS Evidence Chain Test Runner
# Runs the Pester evidence-chain test file without installing modules.

$ErrorActionPreference = "Stop"

if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Error "Pester is required for evidence-chain tests. Install it explicitly with: Install-Module -Name Pester -Scope CurrentUser"
    exit 1
}

Import-Module Pester -Force -ErrorAction Stop

$testPath = Join-Path $PSScriptRoot "evidence-chain.tests.ps1"

if (Get-Command New-PesterConfiguration -ErrorAction SilentlyContinue) {
    $config = New-PesterConfiguration
    $config.Run.Path = $testPath
    $config.Run.Exit = $false
    $config.Run.PassThru = $true
    $config.Output.Verbosity = "Normal"
    $result = Invoke-Pester -Configuration $config
} else {
    $result = Invoke-Pester -Script $testPath -EnableExit:$false -PassThru
}

function Get-PesterResultCount {
    param(
        [object]$Result,
        [string[]]$Names
    )

    if (-not $Result) {
        return 0
    }

    foreach ($name in $Names) {
        if ($Result.PSObject.Properties.Name -contains $name) {
            return [int]$Result.$name
        }
    }

    return 0
}

$failedCount = Get-PesterResultCount -Result $result -Names @("FailedCount", "Failed", "TestsFailed")
$passedCount = Get-PesterResultCount -Result $result -Names @("PassedCount", "Passed", "TestsPassed")

if ($failedCount -gt 0) {
    Write-Host "Evidence chain tests FAILED: $failedCount failed, $passedCount passed" -ForegroundColor Red
    exit 1
}

if ($passedCount -eq 0) {
    Write-Host "Evidence chain tests FAILED: no tests were reported as passed." -ForegroundColor Red
    exit 1
}

Write-Host "Evidence chain tests OK: $passedCount passed, $failedCount failed" -ForegroundColor Green
exit 0
