# ADP-OS Filesystem Adapter (Windows)
# Platform-specific filesystem operations
# Reserved abstractions for macOS/Linux

function Initialize-Filesystem {
    param([string]$BasePath)

    $dirs = @(
        "$BasePath\workspaces",
        "$BasePath\vms",
        "$BasePath\iso",
        "$BasePath\snapshots"
    )

    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
        }
    }
}

function Get-ADPDataPath {
    param([string]$SubPath)
    $base = "$env:USERPROFILE\.adp-os"
    if ($SubPath) { return Join-Path $base $SubPath }
    return $base
}

function Test-ADPInitialized {
    $marker = Get-ADPDataPath "initialized"
    return Test-Path $marker
}

function Set-ADPInitialized {
    $marker = Get-ADPDataPath "initialized"
    $dir = Split-Path $marker -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    New-Item -ItemType File -Path $marker -Force | Out-Null
}

function Get-HomeDir {
    return $env:USERPROFILE
}

function Resolve-WorkspacePath {
    param([string]$WorkspaceName)
    return (Get-ADPDataPath "workspaces\$WorkspaceName")
}

function Get-TempPath {
    return Join-Path $env:TEMP "adp-os"
}