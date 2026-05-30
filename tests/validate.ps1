param(
    [switch]$Quick,
    [switch]$SkipCliSmoke,
    [switch]$SkipInstallerSmoke,
    [switch]$SkipShellSyntax
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $repoRoot

if ($Quick) {
    $SkipCliSmoke = $true
    $SkipInstallerSmoke = $true
    Write-Host "Quick validation: CLI smoke and installer smoke tests will be skipped." -ForegroundColor Yellow
}

function Invoke-ValidationStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    Write-Host "==> $Name" -ForegroundColor Cyan
    & $ScriptBlock
    Write-Host "OK: $Name" -ForegroundColor Green
}

Invoke-ValidationStep -Name "Parse PowerShell scripts" -ScriptBlock {
    $failed = $false
    Get-ChildItem -Recurse -Filter *.ps1 -File | ForEach-Object {
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors) > $null
        if ($errors) {
            $failed = $true
            $path = $_.FullName
            $errors | ForEach-Object {
                "{0}:{1}: {2}" -f $path, $_.Extent.StartLineNumber, $_.Message
            }
        }
    }

    if ($failed) {
        throw "PowerShell parser checks failed."
    }
}

Invoke-ValidationStep -Name "Parse JSON configuration" -ScriptBlock {
    @(
        "configs\platform.json",
        "configs\topology.json",
        "configs\sync-profiles.json",
        "configs\local.example.json",
        "configs\workspace.example.json",
        "configs\workspace.recipes.example.json"
    ) | ForEach-Object {
        Get-Content -LiteralPath $_ -Raw | ConvertFrom-Json | Out-Null
    }
}

Invoke-ValidationStep -Name "Check CLI parameter contracts" -ScriptBlock {
    & ".\tests\cli-parameter-contracts.ps1"
}

Invoke-ValidationStep -Name "Check configuration schema" -ScriptBlock {
    & ".\tests\config-schema.ps1"
}

Invoke-ValidationStep -Name "Check GitHub issue templates" -ScriptBlock {
    & ".\tests\issue-templates.ps1"
}

Invoke-ValidationStep -Name "Check artifact hygiene" -ScriptBlock {
    & ".\tests\artifact-hygiene.ps1"
}

Invoke-ValidationStep -Name "Check local config mutation boundaries" -ScriptBlock {
    & ".\tests\local-config-boundary.ps1"
}

if (-not $SkipCliSmoke) {
    Invoke-ValidationStep -Name "Run CLI smoke tests" -ScriptBlock {
        & ".\tests\cli-smoke.ps1"
    }
}
else {
    Write-Host "SKIP: Run CLI smoke tests" -ForegroundColor Yellow
}

if (-not $SkipInstallerSmoke) {
    Invoke-ValidationStep -Name "Run installer smoke tests" -ScriptBlock {
        & ".\tests\install-smoke.ps1"
    }
}
else {
    Write-Host "SKIP: Run installer smoke tests" -ForegroundColor Yellow
}

if (-not $SkipShellSyntax) {
    Invoke-ValidationStep -Name "Check bootstrap shell syntax" -ScriptBlock {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if (-not $bash) {
            throw "bash was not found on PATH. Install Git Bash or WSL bash, or rerun with -SkipShellSyntax for local-only validation."
        }

        $shellScripts = @(
            "bootstrap/base/setup-base.sh",
            "bootstrap/frontend/setup-frontend.sh",
            "bootstrap/frontend/browser-tools.sh",
            "bootstrap/backend/setup-backend.sh",
            "bootstrap/agent/setup-agent.sh",
            "bootstrap/common/common.sh"
        )

        & $bash.Source -n @shellScripts
        if ($LASTEXITCODE -ne 0) {
            throw "Bootstrap shell syntax checks failed."
        }
    }
}
else {
    Write-Host "SKIP: Check bootstrap shell syntax" -ForegroundColor Yellow
}

Invoke-ValidationStep -Name "Check Markdown local links and anchors" -ScriptBlock {
    & ".\tests\markdown-links.ps1"
}

Invoke-ValidationStep -Name "Check documentation language links" -ScriptBlock {
    & ".\tests\docs-language-links.ps1"
}

Write-Output "Repository validation OK"
