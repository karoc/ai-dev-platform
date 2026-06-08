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
    $global:LASTEXITCODE = 0
    & $ScriptBlock
    if ($LASTEXITCODE -ne 0) {
        throw "FAIL: $Name (exit code $LASTEXITCODE)"
    }
    Write-Host "OK: $Name" -ForegroundColor Green
}

function Invoke-WithIsolatedUserEnvironment {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock]$ScriptBlock
    )

    $userProfile = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-validate-home-{0}" -f ([guid]::NewGuid().ToString("N")))
    $localAppData = Join-Path $userProfile "AppData\Local"
    $previousEnvironment = @{
        USERPROFILE   = [System.Environment]::GetEnvironmentVariable("USERPROFILE", "Process")
        LOCALAPPDATA  = [System.Environment]::GetEnvironmentVariable("LOCALAPPDATA", "Process")
    }

    New-Item -ItemType Directory -Path $userProfile, $localAppData -Force | Out-Null
    try {
        [System.Environment]::SetEnvironmentVariable("USERPROFILE", $userProfile, "Process")
        [System.Environment]::SetEnvironmentVariable("LOCALAPPDATA", $localAppData, "Process")
        & $ScriptBlock
    } finally {
        foreach ($name in $previousEnvironment.Keys) {
            [System.Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], "Process")
        }
        Remove-Item -LiteralPath $userProfile -Recurse -Force -ErrorAction SilentlyContinue
    }
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

Invoke-ValidationStep -Name "Check CLI UX contracts" -ScriptBlock {
    & ".\tests\cli-ux-contract.ps1"
}

Invoke-ValidationStep -Name "Check adpos public command surface" -ScriptBlock {
    & ".\tests\adpos-public-surface.ps1"
}

Invoke-ValidationStep -Name "Check adpos registration contract" -ScriptBlock {
    & ".\tests\adpos-registration-contract.ps1"
}

Invoke-ValidationStep -Name "Check adpos registration decisions" -ScriptBlock {
    & ".\tests\adpos-registration-decision.ps1"
}

Invoke-ValidationStep -Name "Check providerless entry routing" -ScriptBlock {
    & ".\tests\providerless-routing-contract.ps1"
}

Invoke-ValidationStep -Name "Check checkout isolation plan" -ScriptBlock {
    & ".\tests\isolate-plan-contract.ps1"
}

Invoke-ValidationStep -Name "Check checkout isolation apply" -ScriptBlock {
    & ".\tests\isolate-apply-contract.ps1"
}

Invoke-ValidationStep -Name "Check resource conflict contracts" -ScriptBlock {
    & ".\tests\resource-conflicts-contract.ps1"
}

Invoke-ValidationStep -Name "Check VMware runtime layout contracts" -ScriptBlock {
    & ".\tests\vmware-runtime-layout-contract.ps1"
}

Invoke-ValidationStep -Name "Check SSH alias ownership contracts" -ScriptBlock {
    & ".\tests\ssh-alias-contract.ps1"
}

Invoke-ValidationStep -Name "Check up provision marker handling" -ScriptBlock {
    & ".\tests\up-provision-marker-contract.ps1"
}

Invoke-ValidationStep -Name "Check bounded SSH probe handling" -ScriptBlock {
    & ".\tests\ssh-timeout.ps1"
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

Invoke-ValidationStep -Name "Check Mutagen remediation behavior" -ScriptBlock {
    & ".\tests\mutagen-remediation.ps1"
}

Invoke-ValidationStep -Name "Check Windows CMD wrappers" -ScriptBlock {
    & ".\tests\cmd-wrapper.ps1"
}

Invoke-ValidationStep -Name "Check evidence chain tests" -ScriptBlock {
    & ".\tests\evidence-chain.ps1"
}

Invoke-ValidationStep -Name "Check workspace evidence command contract" -ScriptBlock {
    & ".\tests\workspace-evidence-contract.ps1"
}

if (-not $SkipCliSmoke) {
    Invoke-ValidationStep -Name "Run CLI smoke tests" -ScriptBlock {
        Invoke-WithIsolatedUserEnvironment {
            & ".\tests\cli-smoke.ps1"
        }
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
