# ADP-OS Mutagen Adapter (Windows)
# Mutagen session management for workspace sync

$script:MutagenPath = $null

function Find-Mutagen {
    param([string]$ProjectRoot)

    $fromPath = (Get-Command mutagen -ErrorAction SilentlyContinue).Source
    if ($fromPath) { return $fromPath }

    if ($ProjectRoot) {
        $localPath = Join-Path $ProjectRoot ".tools\mutagen\mutagen.exe"
        if (Test-Path $localPath) { return $localPath }
    }

    return $null
}

function Initialize-Mutagen {
    param([string]$ProjectRoot)

    $script:MutagenPath = Find-Mutagen -ProjectRoot $ProjectRoot
    if (-not $script:MutagenPath) {
        throw "Mutagen not installed. Download the Windows AMD64 release from https://github.com/mutagen-io/mutagen/releases and place mutagen.exe at .tools\mutagen\mutagen.exe, or add it to PATH."
    }
    return $script:MutagenPath
}

function Invoke-Mutagen {
    param([string[]]$Arguments)

    if (-not $script:MutagenPath) {
        Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
    }

    & $script:MutagenPath @Arguments
}

function Test-SyncSessionExists {
    param([string]$SessionName)

    if (-not $script:MutagenPath) {
        Initialize-Mutagen -ProjectRoot (Get-ProjectRoot) | Out-Null
    }

    $output = & $script:MutagenPath sync list $SessionName 2>$null
    return ($LASTEXITCODE -eq 0 -and (($output -join "`n") -match "Name:\s+$([regex]::Escape($SessionName))\b"))
}

function Set-MutagenSSHHostConfig {
    param(
        [string]$HostAlias,
        [string]$SSHHost,
        [string]$SSHUser = "adp",
        [int]$SSHPort = 22,
        [string]$SSHKeyPath
    )

    if (-not $SSHKeyPath) {
        return $HostAlias
    }

    $sshDir = Join-Path $env:USERPROFILE ".ssh"
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
    }

    $configPath = Join-Path $sshDir "config"
    $beginMarker = "# >>> ADP-OS $HostAlias >>>"
    $endMarker = "# <<< ADP-OS $HostAlias <<<"
    $identityPath = $SSHKeyPath -replace '\\', '/'

    $block = @(
        $beginMarker,
        "Host $HostAlias",
        "    HostName $SSHHost",
        "    User $SSHUser",
        "    Port $SSHPort",
        "    IdentityFile $identityPath",
        "    IdentitiesOnly yes",
        "    StrictHostKeyChecking no",
        "    UserKnownHostsFile NUL",
        $endMarker
    ) -join [Environment]::NewLine

    $existing = if (Test-Path $configPath) { Get-Content -Path $configPath -Raw } else { "" }
    $pattern = "(?ms)^$([regex]::Escape($beginMarker))\r?\n.*?\r?\n$([regex]::Escape($endMarker))\r?\n?"

    if ($existing -match $pattern) {
        $updated = [regex]::Replace($existing, $pattern, $block + [Environment]::NewLine)
    } else {
        $separator = if ([string]::IsNullOrWhiteSpace($existing)) { "" } elseif ($existing.EndsWith([Environment]::NewLine)) { "" } else { [Environment]::NewLine }
        $updated = $existing + $separator + $block + [Environment]::NewLine
    }

    Set-Content -Path $configPath -Value $updated -Encoding ascii
    return $HostAlias
}

function New-SyncSession {
    param(
        [string]$SessionName,
        [string]$LocalPath,
        [string]$RemotePath,
        [string]$SSHHost,
        [string]$SSHUser = "adp",
        [int]$SSHPort = 22,
        [string]$Mode = "two-way-resolved",
        [string[]]$Ignore = @(),
        [string]$SSHKeyPath
    )

    if (-not $SSHHost) {
        throw "SSHHost is required for Mutagen sync"
    }

    if (Test-SyncSessionExists -SessionName $SessionName) {
        Write-Host "  Sync session '$SessionName' already exists." -ForegroundColor Green
        return
    }

    if (-not (Test-Path $LocalPath)) {
        New-Item -ItemType Directory -Path $LocalPath -Force | Out-Null
    }

    $hostAlias = "adp-os-$SessionName"
    $endpointHost = if ($SSHKeyPath) {
        Set-MutagenSSHHostConfig `
            -HostAlias $hostAlias `
            -SSHHost $SSHHost `
            -SSHUser $SSHUser `
            -SSHPort $SSHPort `
            -SSHKeyPath $SSHKeyPath
    } else {
        "${SSHUser}@${SSHHost}"
    }

    $sshUrl = "${endpointHost}:${RemotePath}"

    $defaultIgnoreList = @(
        "node_modules", ".next", "dist", "build",
        ".git", "__pycache__", ".venv", ".cache"
    )
    $ignoreList = @($defaultIgnoreList + $Ignore) | Select-Object -Unique

    $ignoreArgs = $ignoreList | ForEach-Object { "--ignore=$_" }

    $args = @(
        "sync", "create",
        "--name", $SessionName,
        "--mode", $Mode
    ) + $ignoreArgs + @($LocalPath, $sshUrl)

    Invoke-Mutagen -Arguments $args
}

function Get-SyncSessions {
    return Invoke-Mutagen -Arguments @("sync", "list")
}

function Stop-SyncSession {
    param([string]$SessionName)
    Invoke-Mutagen -Arguments @("sync", "terminate", $SessionName)
}

function Get-SyncStatus {
    param([string]$SessionName)
    return Invoke-Mutagen -Arguments @("sync", "monitor", "--identifier", $SessionName)
}
