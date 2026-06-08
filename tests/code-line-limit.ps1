# ADP-OS code file line-limit check.
# Keeps code and test files small enough to split by responsibility.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$maxLines = 700
$codeExtensions = @(
    ".ps1",
    ".psm1",
    ".py",
    ".sh",
    ".cmd",
    ".bat",
    ".js",
    ".ts",
    ".tsx",
    ".jsx",
    ".mjs",
    ".cjs"
)

function Get-FileLineCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $reader = [System.IO.File]::OpenText($Path)
    try {
        $count = 0
        while ($null -ne $reader.ReadLine()) {
            $count++
        }
        return $count
    } finally {
        $reader.Dispose()
    }
}

$tracked = & git -C $projectRoot ls-files
if ($LASTEXITCODE -ne 0) {
    throw "Unable to list tracked files with git."
}

$violations = @()
$checked = 0
foreach ($relativePath in $tracked) {
    $extension = [System.IO.Path]::GetExtension($relativePath)
    if ($codeExtensions -notcontains $extension) {
        continue
    }

    $fullPath = Join-Path $projectRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        continue
    }

    $checked++
    $lineCount = Get-FileLineCount -Path $fullPath
    if ($lineCount -gt $maxLines) {
        $violations += [pscustomobject]@{
            Path = $relativePath
            Lines = $lineCount
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Output "Code line limit failed: each tracked code/test file must be at or below $maxLines lines."
    $violations |
        Sort-Object -Property Lines -Descending |
        ForEach-Object {
            Write-Output ("  {0,5} {1}" -f $_.Lines, $_.Path)
        }
    throw "Code line limit failed."
}

Write-Output "Code line limit OK ($checked files checked, max $maxLines lines)"
