# ADP-OS GitHub Actions platform compatibility contracts.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$workflowRoot = Join-Path $projectRoot ".github\workflows"

function Read-Workflow {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return Get-Content -LiteralPath (Join-Path $workflowRoot $Name) -Raw -Encoding UTF8
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "Missing GitHub Actions contract: $Name"
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    if ($Text -match $Pattern) {
        throw "Forbidden GitHub Actions workflow text found: $Name"
    }
}

$ci = Read-Workflow -Name "ci.yml"
$release = Read-Workflow -Name "release.yml"
$combined = @($ci, $release) -join "`n"

Assert-Contains `
    -Name "CI pins explicit Windows 2025 VS2026 runner" `
    -Text $ci `
    -Pattern 'runs-on:\s+windows-2025-vs2026'

Assert-Contains `
    -Name "Release pins explicit Windows 2025 VS2026 runner" `
    -Text $release `
    -Pattern 'runs-on:\s+windows-2025-vs2026'

Assert-Contains `
    -Name "CI uses checkout v6" `
    -Text $ci `
    -Pattern 'uses:\s+actions/checkout@v6'

Assert-Contains `
    -Name "Release uses checkout v6" `
    -Text $release `
    -Pattern 'uses:\s+actions/checkout@v6'

Assert-NotContains `
    -Name "workflows avoid windows-latest alias drift" `
    -Text $combined `
    -Pattern 'runs-on:\s+windows-latest'

Assert-NotContains `
    -Name "workflows avoid Node 20 checkout action" `
    -Text $combined `
    -Pattern 'uses:\s+actions/checkout@v4'

Write-Output "GitHub Actions platform contracts OK"
