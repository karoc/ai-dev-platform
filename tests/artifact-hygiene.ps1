# ADP-OS artifact hygiene checks.
# Keeps local machine state, large runtime artifacts, and assistant settings out of public commits.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$gitignorePath = Join-Path $projectRoot ".gitignore"

if (-not (Test-Path -LiteralPath $gitignorePath)) {
    throw "Missing .gitignore"
}

$gitignore = Get-Content -LiteralPath $gitignorePath -Raw
$requiredIgnorePatterns = @(
    ".claude/",
    ".codex/",
    ".tools/",
    "logs/",
    "snapshots/",
    "configs/local.json",
    "configs/secrets.json",
    "/adp-workspace.json",
    "/adp-workspace.state.json",
    "*.iso",
    "*.vmdk",
    "*.vmem",
    "*.nvram",
    "*.vmsd",
    "*.vmss",
    "*.vmsn",
    "playwright-report/",
    "test-results/",
    "blob-report/",
    ".playwright/",
    "NUL"
)

foreach ($pattern in $requiredIgnorePatterns) {
    $escaped = [regex]::Escape($pattern)
    if ($gitignore -notmatch "(?m)^$escaped\s*$") {
        throw ".gitignore is missing required artifact pattern: $pattern"
    }
}

$trackedForbiddenPatterns = @(
    "^\.claude/",
    "^\.codex/",
    "^\.tools/",
    "^logs/",
    "^snapshots/",
    "^configs/local\.json$",
    "^configs/secrets\.json$",
    "^adp-workspace\.json$",
    "^adp-workspace\.state\.json$",
    "\.iso$",
    "\.vmdk$",
    "\.vmem$",
    "\.nvram$",
    "\.vmsd$",
    "\.vmss$",
    "\.vmsn$",
    "^playwright-report/",
    "^test-results/",
    "^blob-report/",
    "^\.playwright/",
    "^NUL$"
)

$tracked = & git -C $projectRoot ls-files
foreach ($path in $tracked) {
    foreach ($pattern in $trackedForbiddenPatterns) {
        if ($path -match $pattern) {
            throw "Tracked local artifact is forbidden: $path"
        }
    }
}

Write-Output "Artifact hygiene checks OK"
