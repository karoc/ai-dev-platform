<#
.SYNOPSIS
Install ADP-OS security guards — pre-commit hook + git exclude patterns.

.DESCRIPTION
Installs two layers of protection:
1. Git pre-commit hook — runs scripts/review-diff.ps1 before every commit
2. Git exclude patterns — prevents accidental staging of private maintainer files

This is the production implementation of the guard referenced in AGENTS.md.

.PARAMETER Uninstall
Remove security guards (pre-commit hook only).

.PARAMETER CheckOnly
Install hook in check-only mode — reports findings but does not block commits.

.EXAMPLE
  .\scripts\install-security-guards.ps1
  .\scripts\install-security-guards.ps1 -CheckOnly
  .\scripts\install-security-guards.ps1 -Uninstall
#>

param(
    [switch]$Uninstall,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$hookPath = Join-Path $repoRoot '.git\hooks\pre-commit'
$reviewScript = Join-Path $repoRoot 'scripts\review-diff.ps1'
$excludePath = Join-Path $repoRoot '.git\info\exclude'

if ($Uninstall) {
    if (Test-Path $hookPath) {
        Remove-Item $hookPath -Force
        Write-Host "[security-guards] Pre-commit hook removed." -ForegroundColor Green
    } else {
        Write-Host "[security-guards] No pre-commit hook found." -ForegroundColor Yellow
    }
    exit 0
}

# ── Verify we're in a git repository ─────────────────────────────────────
if (-not (Test-Path (Join-Path $repoRoot '.git'))) {
    Write-Host "[security-guards] ERROR: Not a git repository. Run from the repo root." -ForegroundColor Red
    exit 1
}

# ── Verify review-diff.ps1 exists ────────────────────────────────────────
if (-not (Test-Path $reviewScript)) {
    Write-Host "[security-guards] ERROR: review-diff.ps1 not found at $reviewScript" -ForegroundColor Red
    exit 1
}

# ── Install pre-commit hook ──────────────────────────────────────────────
$checkFlag = if ($CheckOnly) { ' -CheckOnly' } else { '' }

$hookContent = @"
#!/usr/bin/env pwsh
# ADP-OS Pre-commit Security Hook
# Installed by scripts/install-security-guards.ps1
# To bypass: git commit --no-verify

`$repoRoot = Split-Path -Parent (Split-Path -Parent `$MyInvocation.MyCommand.Path)
`$reviewScript = Join-Path `$repoRoot 'scripts\review-diff.ps1'

if (Test-Path `$reviewScript) {
    & pwsh -NoProfile -File `$reviewScript${checkFlag}
    if (`$LASTEXITCODE -ne 0) {
        exit 1
    }
}
exit 0
"@

Set-Content -Path $hookPath -Value $hookContent -NoNewline
Write-Host "[security-guards] Pre-commit hook installed: $hookPath" -ForegroundColor Green
if ($CheckOnly) {
    Write-Host "  Mode: check-only — findings are reported but commits are not blocked." -ForegroundColor Yellow
} else {
    Write-Host "  Mode: blocking — security findings will prevent commit (bypass: --no-verify)." -ForegroundColor Yellow
}

# ── Update git exclude patterns ──────────────────────────────────────────
$privatePatterns = @(
    '# ADP-OS maintainer private files (installed by install-security-guards.ps1)',
    'AI_DEV_PLATFORM_MAINTAINER.md',
    'PRIVATE_ROADMAP.md',
    'MAINTAINER_PROTOCOL.md',
    'context/',
    'decisions/',
    '.env',
    '.env.*',
    '!configs/.env.example'
)

$existingExclude = if (Test-Path $excludePath) { Get-Content $excludePath -Raw } else { "" }

# Only add patterns if not already present
$alreadyInstalled = $existingExclude -match 'ADP-OS maintainer private files'
if (-not $alreadyInstalled) {
    $newExclude = ($existingExclude.TrimEnd() + "`n`n" + ($privatePatterns -join "`n") + "`n")
    Set-Content -Path $excludePath -Value $newExclude -NoNewline
    Write-Host "[security-guards] Git exclude patterns updated: $excludePath" -ForegroundColor Green
} else {
    Write-Host "[security-guards] Git exclude patterns already present." -ForegroundColor Green
}

Write-Host "[security-guards] Security guards installed. Pre-commit diff review is active." -ForegroundColor Green
