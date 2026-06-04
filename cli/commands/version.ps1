# ADP-OS Version Command
# Prints the installed ADP-OS version from VERSION file or git describe.

$ErrorActionPreference = "Stop"

$versionFile = Join-Path $script:ProjectRoot "VERSION"
if (Test-Path $versionFile) {
    $version = (Get-Content $versionFile -Raw).Trim()
    Write-Host "ADP-OS version $version"
} else {
    Push-Location $script:ProjectRoot
    try {
        $gitVersion = & git describe --tags --always --dirty 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "ADP-OS version dev-$gitVersion"
        } else {
            Write-Host "ADP-OS version dev (unknown)"
        }
    } finally {
        Pop-Location
    }
}
