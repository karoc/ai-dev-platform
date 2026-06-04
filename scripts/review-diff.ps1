<#
.SYNOPSIS
Pre-commit diff review — scans staged changes for security issues before commit.

.DESCRIPTION
Examines staged git diffs for common security issues:
- Hardcoded credentials (API keys, tokens, passwords)
- Private keys accidentally staged
- Large binary files
- Suspicious patterns (command injection, SQL injection indicators)

Returns exit code 0 if clean, 1 if issues found.

.PARAMETER StagedOnly
If set, only scans staged changes. Default: scans staged changes.

.PARAMETER CheckOnly
If set, reports findings without blocking commit. Default: blocks on findings.

.EXAMPLE
  .\scripts\review-diff.ps1
  .\scripts\review-diff.ps1 -CheckOnly
#>

param(
    [switch]$CheckOnly
)

$exitCode = 0
$findings = @()
$stagedDiff = & git diff --cached --diff-filter=ACMR 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "review-diff: git diff failed — $stagedDiff"
    exit 0  # Don't block on tool failure
}

if (-not $stagedDiff -or $stagedDiff.Count -eq 0) {
    exit 0
}

$diffText = if ($stagedDiff -is [array]) { $stagedDiff -join "`n" } else { $stagedDiff }

# ── Rule 1: Detect private keys ──────────────────────────────────────────
if ($diffText -match '-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----') {
    $findings += "[SECURITY] Private key detected in staged changes. Never commit private keys."
}

# ── Rule 2: Detect API keys, tokens, secrets ─────────────────────────────
$secretPatterns = @(
    @{ Name = 'Generic API key';        Pattern = 'api[_-]?key\s*[:=]\s*["''][A-Za-z0-9+/_-]{20,}["'']' },
    @{ Name = 'Access token';           Pattern = 'access[_-]?token\s*[:=]\s*["''][A-Za-z0-9+.=_-]{20,}["'']' },
    @{ Name = 'Secret key';             Pattern = 'secret[_-]?key\s*[:=]\s*["''][A-Za-z0-9+/=_-]{20,}["'']' },
    @{ Name = 'Password assignment';    Pattern = 'password\s*[:=]\s*["''][^"'']{6,}["'']\s*(?!#\s*noqa)' },
    @{ Name = 'AWS Access Key';         Pattern = 'AKIA[0-9A-Z]{16}' },
    @{ Name = 'GitHub token';           Pattern = '(gh[pous]_[A-Za-z0-9_]{36,}|github[_-]?token\s*[:=]\s*["''][A-Za-z0-9_]{20,}["''])' },
    @{ Name = 'Slack token';            Pattern = 'xox[baprs]-[0-9A-Za-z-]{10,}' },
    @{ Name = 'Stripe secret key';      Pattern = 'sk_(live|test)_[0-9a-zA-Z]{24,}' },
    @{ Name = 'Generic JWT/Base64 token'; Pattern = 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' }
)

foreach ($sp in $secretPatterns) {
    if ($diffText -match $sp.Pattern) {
        $findings += "[SECURITY] Possible $($sp.Name) in staged diff. Review and remove before committing."
    }
}

# ── Rule 3: Large files ──────────────────────────────────────────────────
$stagedFiles = & git diff --cached --name-only --diff-filter=ACMR 2>&1
if ($LASTEXITCODE -eq 0 -and $stagedFiles) {
    $files = if ($stagedFiles -is [array]) { $stagedFiles } else { @($stagedFiles) }
    foreach ($file in $files) {
        if (Test-Path $file) {
            try {
                $size = (Get-Item $file -ErrorAction Stop).Length
                if ($size -gt 1MB) {
                    $sizeMB = [math]::Round($size / 1MB, 1)
                    $findings += "[SIZE] Large file staged: $file ($sizeMB MB). Consider using Git LFS or .gitignore."
                }
            } catch {
                # File may be staged but not on disk (deletion) — skip
            }
        }
    }
}

# ── Rule 4: Suspicious shell patterns in scripts ─────────────────────────
$dangerPatterns = @(
    @{ Name = 'Recursive force remove'; Pattern = 'rm\s+-rf\s+[/~]' },
    @{ Name = 'Force push to main';     Pattern = 'push\s+.*--force.*main' },
    @{ Name = 'SQL injection pattern';  Pattern = '["'']\s*\+\s*\$_(GET|POST|REQUEST)\[' },
    @{ Name = 'eval with variable';     Pattern = 'eval\s+\$' }
)

foreach ($dp in $dangerPatterns) {
    # Only flag if the pattern appears in added lines (lines starting with +)
    $addedLines = ($diffText -split "`n" | Where-Object { $_ -match '^\+\s' }) -join "`n"
    if ($addedLines -match $dp.Pattern) {
        $findings += "[CAUTION] Possible $($dp.Name) in staged diff. Review carefully."
    }
}

# ── Report ────────────────────────────────────────────────────────────────
if ($findings.Count -eq 0) {
    exit 0
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Yellow
Write-Host "║              Pre-commit Diff Review — Findings              ║" -ForegroundColor Yellow
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Yellow
Write-Host ""

foreach ($finding in $findings) {
    $color = if ($finding -match '^\[SECURITY\]') { 'Red' } elseif ($finding -match '^\[CAUTION\]') { 'Yellow' } else { 'Magenta' }
    Write-Host "  $finding" -ForegroundColor $color
}

Write-Host ""
if (-not $CheckOnly) {
    Write-Host "  Review the findings above before committing." -ForegroundColor Red
    Write-Host "  To bypass: git commit --no-verify" -ForegroundColor DarkGray
    exit 1
} else {
    Write-Host "  [check-only mode] Review these findings before pushing." -ForegroundColor Yellow
    exit 0
}
