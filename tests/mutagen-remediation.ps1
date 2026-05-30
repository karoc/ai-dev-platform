# ADP-OS Mutagen remediation checks
# Covers local archive verification behavior without downloading Mutagen or installing binaries.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

. (Join-Path $projectRoot "core\config\config.ps1")
. (Join-Path $projectRoot "adapters\windows\mutagen\mutagen.ps1")

Initialize-Config -ProjectRoot $projectRoot

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-mutagen-remediation-{0}" -f ([guid]::NewGuid().ToString("N")))
try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $archive = Join-Path $tempRoot "mutagen_windows_amd64_v0.18.1.zip"
    "not a real zip, only hash-test content" | Set-Content -LiteralPath $archive -Encoding ascii
    $actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()

    if (-not (Test-MutagenSha256Value -Sha256 $actualHash)) {
        throw "Valid SHA256 was rejected."
    }

    if (Test-MutagenSha256Value -Sha256 "not-a-sha256") {
        throw "Invalid SHA256 was accepted."
    }

    Assert-MutagenArchiveHash -ArchivePath $archive -Sha256 $actualHash
    Assert-MutagenArchiveHash -ArchivePath $archive -Sha256 $null

    $failed = $false
    try {
        Assert-MutagenArchiveHash -ArchivePath $archive -Sha256 ("0" * 64)
    } catch {
        $failed = ($_.Exception.Message -match "SHA256 mismatch")
    }
    if (-not $failed) {
        throw "SHA256 mismatch did not fail with the expected error."
    }

    $settings = Get-MutagenInstallSettings -ProjectRoot $projectRoot -Version "0.18.1"
    if ($settings.Version -ne "0.18.1") {
        throw "Unexpected Mutagen version setting: $($settings.Version)"
    }
    if ([string]::IsNullOrWhiteSpace($settings.DownloadUrl)) {
        throw "Mutagen download URL setting was empty."
    }
    if ($settings.ConnectionTimeoutSeconds -le 0 -or $settings.DownloadTimeoutSeconds -le 0) {
        throw "Mutagen timeout settings must be positive."
    }
} finally {
    if ($tempRoot -and (Test-Path -LiteralPath $tempRoot)) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output "Mutagen remediation checks OK"
