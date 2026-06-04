<#
.SYNOPSIS
ADP-OS release helper — validates, tags, and pushes a versioned release.

.DESCRIPTION
Reads VERSION, runs the full validation suite, then creates and pushes
a 'v<version>' Git tag. Pushing the tag triggers the GitHub Actions
release workflow (.github/workflows/release.yml), which runs CI and
creates the GitHub Release automatically.

.EXAMPLE
.\scripts\release.ps1
    Validates, confirms, and tags the version from the VERSION file.

.EXAMPLE
.\scripts\release.ps1 -DryRun
    Validates and shows what would happen without creating a tag.
#>

param(
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$versionFile = Join-Path $repoRoot 'VERSION'
$changelogFile = Join-Path $repoRoot 'CHANGELOG.md'

if (-not (Test-Path $versionFile)) {
    Write-Error "VERSION file not found at $versionFile"
    exit 1
}

$version = (Get-Content $versionFile).Trim()
$tag = "v$version"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " ADP-OS Release v$version" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ── 1. Show current state ──────────────────────────────────────────

Write-Host "[1/4] Checking repository state..." -ForegroundColor Yellow

Push-Location $repoRoot

$branch = git branch --show-current
$status = git status --short
$dirty = if ($status) { "DIRTY" } else { "clean" }

Write-Host "  Branch : $branch" 
Write-Host "  Status : $dirty"

if ($status) {
    Write-Host ""
    Write-Host "  Uncommitted changes:" -ForegroundColor Red
    git status --short
    Write-Host ""
    Write-Error "Repository has uncommitted changes. Commit or stash before releasing."
    exit 1
}

# ── 2. Run validation ──────────────────────────────────────────────

Write-Host ""
Write-Host "[2/4] Running validation suite..." -ForegroundColor Yellow

$validateScript = Join-Path $repoRoot 'tests\validate.ps1'
if (Test-Path $validateScript) {
    & $validateScript
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Validation failed. Fix issues before releasing."
        exit 1
    }
} else {
    Write-Warning "tests\validate.ps1 not found — skipping validation"
}

# ── 3. Confirm ─────────────────────────────────────────────────────

Write-Host ""
Write-Host "[3/4] Release preview" -ForegroundColor Yellow
Write-Host "  Version : $version"
Write-Host "  Tag     : $tag"
Write-Host "  Branch  : $branch (will push tag to origin)"

$existingTag = git tag --list $tag
if ($existingTag) {
    Write-Host ""
    Write-Host "  WARNING: Tag $tag already exists locally!" -ForegroundColor Red
    Write-Host "  Existing tag points to: $(git rev-parse --short $tag)" -ForegroundColor Red
}

if ($DryRun) {
    Write-Host ""
    Write-Host "[DRY RUN] Would create and push tag '$tag'. No changes made." -ForegroundColor Green
    Pop-Location
    exit 0
}

Write-Host ""
$confirm = Read-Host "Create and push tag '$tag'? (y/N)"
if ($confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Release cancelled." -ForegroundColor Red
    Pop-Location
    exit 0
}

# ── 4. Tag and push ────────────────────────────────────────────────

Write-Host ""
Write-Host "[4/4] Creating and pushing tag..." -ForegroundColor Yellow

git tag -a $tag -m "Release v$version"
Write-Host "  Created tag: $tag"

git push origin $tag
Write-Host "  Pushed tag: $tag"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Release v$version initiated!" -ForegroundColor Green
Write-Host "" 
Write-Host " GitHub Actions will now:" -ForegroundColor Green
Write-Host "   1. Run the validation suite" -ForegroundColor Green
Write-Host "   2. Create the GitHub Release" -ForegroundColor Green
Write-Host "   3. Attach CHANGELOG.md as release notes" -ForegroundColor Green
Write-Host ""
Write-Host " Monitor: https://github.com/karoc/ai-dev-platform/actions" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Green

Pop-Location
