# ADP-OS Mutagen Adapter (Windows)
# Mutagen session management for workspace sync

$script:MutagenPath = $null
$script:MutagenExpectedVersion = "0.18.1"

function Get-MutagenExpectedVersion {
    return $script:MutagenExpectedVersion
}

function Get-LocalMutagenPath {
    param([string]$ProjectRoot)

    if (-not $ProjectRoot) {
        $ProjectRoot = Get-ProjectRoot
    }

    return (Join-Path $ProjectRoot ".tools\mutagen\mutagen.exe")
}

function Get-MutagenDownloadUrl {
    param([string]$Version = (Get-MutagenExpectedVersion))

    return "https://github.com/mutagen-io/mutagen/releases/download/v$Version/mutagen_windows_amd64_v$Version.zip"
}

function Resolve-MutagenToolPath {
    param(
        [string]$ProjectRoot,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $null
    }

    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    $expanded = $expanded -replace '\$\{project:root\}', $ProjectRoot
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        return $expanded
    }

    return (Join-Path $ProjectRoot $expanded)
}

function Get-MutagenInstallSettings {
    param(
        [string]$ProjectRoot,
        [string]$Version
    )

    if (-not $ProjectRoot) {
        $ProjectRoot = Get-ProjectRoot
    }
    if (-not $Version) {
        $Version = Get-MutagenExpectedVersion
    }

    $platform = Get-PlatformConfig
    $mutagenTools = $null
    if ($platform -and $platform.PSObject.Properties.Name -contains "tools" -and $platform.tools.PSObject.Properties.Name -contains "mutagen") {
        $mutagenTools = $platform.tools.mutagen
    }

    $configuredVersion = if ($mutagenTools -and $mutagenTools.PSObject.Properties.Name -contains "version" -and -not [string]::IsNullOrWhiteSpace([string]$mutagenTools.version)) {
        [string]$mutagenTools.version
    } else {
        $Version
    }

    $downloadUrl = if ($mutagenTools -and $mutagenTools.PSObject.Properties.Name -contains "download_url" -and -not [string]::IsNullOrWhiteSpace([string]$mutagenTools.download_url)) {
        [string]$mutagenTools.download_url
    } else {
        Get-MutagenDownloadUrl -Version $configuredVersion
    }

    $archivePath = if ($mutagenTools -and $mutagenTools.PSObject.Properties.Name -contains "archive_path" -and -not [string]::IsNullOrWhiteSpace([string]$mutagenTools.archive_path)) {
        Resolve-MutagenToolPath -ProjectRoot $ProjectRoot -Path ([string]$mutagenTools.archive_path)
    } else {
        $null
    }

    $sha256 = if ($mutagenTools -and $mutagenTools.PSObject.Properties.Name -contains "sha256" -and -not [string]::IsNullOrWhiteSpace([string]$mutagenTools.sha256)) {
        ([string]$mutagenTools.sha256).Trim().ToLowerInvariant()
    } else {
        $null
    }

    $connectionTimeout = 30
    if ($mutagenTools -and $mutagenTools.PSObject.Properties.Name -contains "connection_timeout_seconds") {
        $configuredConnectionTimeout = 0
        if ([int]::TryParse([string]$mutagenTools.connection_timeout_seconds, [ref]$configuredConnectionTimeout) -and $configuredConnectionTimeout -gt 0) {
            $connectionTimeout = $configuredConnectionTimeout
        }
    }

    $downloadTimeout = 300
    if ($mutagenTools -and $mutagenTools.PSObject.Properties.Name -contains "download_timeout_seconds") {
        $configuredDownloadTimeout = 0
        if ([int]::TryParse([string]$mutagenTools.download_timeout_seconds, [ref]$configuredDownloadTimeout) -and $configuredDownloadTimeout -gt 0) {
            $downloadTimeout = $configuredDownloadTimeout
        }
    }

    return [pscustomobject]@{
        Version                  = $configuredVersion
        DownloadUrl              = $downloadUrl
        ArchivePath              = $archivePath
        Sha256                   = $sha256
        ConnectionTimeoutSeconds = $connectionTimeout
        DownloadTimeoutSeconds   = $downloadTimeout
    }
}

function Test-MutagenSha256Value {
    param([string]$Sha256)

    if ([string]::IsNullOrWhiteSpace($Sha256)) {
        return $true
    }

    return ($Sha256 -match '^[a-fA-F0-9]{64}$')
}

function Assert-MutagenArchiveHash {
    param(
        [string]$ArchivePath,
        [string]$Sha256
    )

    if ([string]::IsNullOrWhiteSpace($Sha256)) {
        Write-Host "        sha256: not configured; archive hash verification skipped." -ForegroundColor DarkGray
        return
    }

    if (-not (Test-MutagenSha256Value -Sha256 $Sha256)) {
        throw "Configured Mutagen SHA256 must be a 64-character hexadecimal value."
    }

    $actual = (Get-FileHash -LiteralPath $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $expected = $Sha256.ToLowerInvariant()
    if ($actual -ne $expected) {
        throw "Mutagen archive SHA256 mismatch for $ArchivePath. Expected $expected, got $actual."
    }

    Write-Host "        sha256: verified $actual" -ForegroundColor DarkGray
}

function Find-Mutagen {
    param([string]$ProjectRoot)

    $fromPath = (Get-Command mutagen -ErrorAction SilentlyContinue).Source
    if ($fromPath) { return $fromPath }

    if ($ProjectRoot) {
        $localPath = Get-LocalMutagenPath -ProjectRoot $ProjectRoot
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

function Get-MutagenVersion {
    param([string]$Path)

    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    return (& $Path version 2>$null | Select-Object -First 1)
}

function Test-MutagenVersionSupported {
    param([string]$VersionText)

    return ("$VersionText" -match '^0\.18\.')
}

function Invoke-MutagenArchiveDownload {
    param(
        [string]$DownloadUrl,
        [string]$ZipPath,
        [string]$TempPath,
        [int]$ConnectionTimeoutSeconds = 30,
        [int]$DownloadTimeoutSeconds = 300
    )

    if (Test-Path -LiteralPath $TempPath) {
        Remove-Item -LiteralPath $TempPath -Force
    }

    Write-Host "  [2/5] Downloading Mutagen archive..." -ForegroundColor Yellow
    Write-Host "        source: $DownloadUrl" -ForegroundColor DarkGray
    Write-Host "        target: $ZipPath" -ForegroundColor DarkGray
    Write-Host "        timeout: connection=${ConnectionTimeoutSeconds}s hard=${DownloadTimeoutSeconds}s" -ForegroundColor DarkGray
    Write-Host "        ADP will stop the download process if the hard timeout is reached." -ForegroundColor DarkGray

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()

    try {
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $pwsh) {
            $pwsh = (Get-Process -Id $PID).Path
        }
        if (-not $pwsh) {
            throw "PowerShell executable was not found for controlled download."
        }

        $escapedUrl = $DownloadUrl.Replace("'", "''")
        $escapedTempPath = $TempPath.Replace("'", "''")
        $downloadScript = @"
`$ErrorActionPreference = 'Stop'
`$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri '$escapedUrl' -OutFile '$escapedTempPath' -ConnectionTimeoutSeconds $ConnectionTimeoutSeconds -OperationTimeoutSeconds $DownloadTimeoutSeconds
"@

        $process = Start-Process -FilePath $pwsh `
            -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $downloadScript) `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError $errFile

        $completed = $process.WaitForExit($DownloadTimeoutSeconds * 1000)
        if (-not $completed) {
            try {
                $process.Kill($true)
            } catch {
                try { $process.Kill() } catch {}
            }
            Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
            throw "Mutagen download timed out after ${DownloadTimeoutSeconds}s. You can retry, or manually download $DownloadUrl and place it at $ZipPath."
        }

        $stdout = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
        if ($process.ExitCode -ne 0) {
            Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
            $detail = (($stderr, $stdout) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
            if ([string]::IsNullOrWhiteSpace($detail)) {
                $detail = "download process exited with code $($process.ExitCode)"
            }
            throw "Mutagen download failed. You can retry, or manually download $DownloadUrl and place it at $ZipPath. Details: $detail"
        }
    } catch {
        Remove-Item -LiteralPath $TempPath -Force -ErrorAction SilentlyContinue
        throw $_
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path -LiteralPath $TempPath)) {
        throw "Mutagen download did not create an archive: $TempPath"
    }

    Move-Item -LiteralPath $TempPath -Destination $ZipPath -Force
}

function Copy-MutagenArchive {
    param(
        [string]$SourcePath,
        [string]$ZipPath,
        [string]$TempPath
    )

    Write-Host "  [2/5] Copying configured Mutagen archive..." -ForegroundColor Yellow
    Write-Host "        source: $SourcePath" -ForegroundColor DarkGray
    Write-Host "        target: $ZipPath" -ForegroundColor DarkGray

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Configured Mutagen archive was not found: $SourcePath"
    }

    if (Test-Path -LiteralPath $TempPath) {
        Remove-Item -LiteralPath $TempPath -Force
    }
    Copy-Item -LiteralPath $SourcePath -Destination $TempPath -Force
    Move-Item -LiteralPath $TempPath -Destination $ZipPath -Force
}

function Install-LocalMutagen {
    param(
        [string]$ProjectRoot,
        [string]$Version = (Get-MutagenExpectedVersion),
        [switch]$Plan
    )

    if (-not $ProjectRoot) {
        $ProjectRoot = Get-ProjectRoot
    }

    $toolRoot = Join-Path $ProjectRoot ".tools\mutagen"
    $settings = Get-MutagenInstallSettings -ProjectRoot $ProjectRoot -Version $Version
    $Version = $settings.Version
    $targetPath = Get-LocalMutagenPath -ProjectRoot $ProjectRoot
    $zipName = "mutagen_windows_amd64_v$Version.zip"
    $zipPath = Join-Path $toolRoot $zipName
    $tempZipPath = "$zipPath.download"
    $extractPath = Join-Path $toolRoot "extract-$Version"
    $downloadUrl = $settings.DownloadUrl

    if ($Plan) {
        return [pscustomobject]@{
            Planned                  = $true
            Version                  = $Version
            Url                      = $downloadUrl
            ConfiguredArchivePath    = $settings.ArchivePath
            ZipPath                  = $zipPath
            ExtractPath              = $extractPath
            TempZipPath              = $tempZipPath
            TargetPath               = $targetPath
            Sha256                   = $settings.Sha256
            ConnectionTimeoutSeconds = $settings.ConnectionTimeoutSeconds
            DownloadTimeoutSeconds   = $settings.DownloadTimeoutSeconds
        }
    }

    Write-Host "  Installing Mutagen locally..." -ForegroundColor Yellow
    Write-Host "  Version: $Version" -ForegroundColor DarkGray
    Write-Host "  Local tools are kept under ignored .tools and must not be committed." -ForegroundColor DarkGray
    if ($settings.ArchivePath) {
        Write-Host "  Offline archive: $($settings.ArchivePath)" -ForegroundColor DarkGray
    } else {
        Write-Host "  Download source: $downloadUrl" -ForegroundColor DarkGray
    }
    if ($settings.Sha256) {
        Write-Host "  Archive SHA256: $($settings.Sha256)" -ForegroundColor DarkGray
    } else {
        Write-Host "  Archive SHA256: not configured; add platform.tools.mutagen.sha256 in configs\local.json when you need strict archive verification." -ForegroundColor DarkGray
    }

    Write-Host "  [1/5] Preparing local tool directory..." -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath $toolRoot)) {
        New-Item -ItemType Directory -Path $toolRoot -Force | Out-Null
    }
    Write-Host "        directory: $toolRoot" -ForegroundColor DarkGray

    $archiveWasReused = $false
    $useConfiguredArchive = $false
    if ($settings.ArchivePath) {
        $configuredFullPath = [System.IO.Path]::GetFullPath($settings.ArchivePath)
        $cacheFullPath = [System.IO.Path]::GetFullPath($zipPath)
        $useConfiguredArchive = (-not $configuredFullPath.Equals($cacheFullPath, [System.StringComparison]::OrdinalIgnoreCase))
    }

    if ($useConfiguredArchive) {
        Copy-MutagenArchive -SourcePath $settings.ArchivePath -ZipPath $zipPath -TempPath $tempZipPath
    } elseif (Test-Path -LiteralPath $zipPath) {
        $archiveWasReused = $true
        $archiveSize = [math]::Round((Get-Item -LiteralPath $zipPath).Length / 1MB, 1)
        Write-Host "  [2/5] Reusing existing Mutagen archive..." -ForegroundColor Yellow
        Write-Host "        archive: $zipPath ($archiveSize MB)" -ForegroundColor DarkGray
        Write-Host "        If extraction fails, ADP will delete it and download a fresh copy." -ForegroundColor DarkGray
    } else {
        Invoke-MutagenArchiveDownload -DownloadUrl $downloadUrl -ZipPath $zipPath -TempPath $tempZipPath -ConnectionTimeoutSeconds $settings.ConnectionTimeoutSeconds -DownloadTimeoutSeconds $settings.DownloadTimeoutSeconds
    }

    Assert-MutagenArchiveHash -ArchivePath $zipPath -Sha256 $settings.Sha256

    Write-Host "  [3/5] Extracting Mutagen archive..." -ForegroundColor Yellow
    if (Test-Path -LiteralPath $extractPath) {
        Remove-Item -LiteralPath $extractPath -Recurse -Force
    }
    New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    try {
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
    } catch {
        if (-not $archiveWasReused) {
            throw "Mutagen archive could not be expanded: $zipPath. Details: $_"
        }

        Write-Host "        existing archive was invalid; downloading a fresh copy." -ForegroundColor Yellow
        Remove-Item -LiteralPath $zipPath -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        if ($useConfiguredArchive) {
            Copy-MutagenArchive -SourcePath $settings.ArchivePath -ZipPath $zipPath -TempPath $tempZipPath
        } else {
            Invoke-MutagenArchiveDownload -DownloadUrl $downloadUrl -ZipPath $zipPath -TempPath $tempZipPath -ConnectionTimeoutSeconds $settings.ConnectionTimeoutSeconds -DownloadTimeoutSeconds $settings.DownloadTimeoutSeconds
        }
        Assert-MutagenArchiveHash -ArchivePath $zipPath -Sha256 $settings.Sha256
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
        Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force
    }

    $extracted = Get-ChildItem -LiteralPath $extractPath -Recurse -Filter "mutagen.exe" -File | Select-Object -First 1
    if (-not $extracted) {
        throw "Downloaded Mutagen archive did not contain mutagen.exe: $zipPath"
    }

    Write-Host "  [4/5] Installing mutagen.exe..." -ForegroundColor Yellow
    Copy-Item -LiteralPath $extracted.FullName -Destination $targetPath -Force
    Write-Host "        target: $targetPath" -ForegroundColor DarkGray

    Write-Host "  [5/5] Verifying Mutagen version..." -ForegroundColor Yellow
    $versionText = Get-MutagenVersion -Path $targetPath
    if (-not (Test-MutagenVersionSupported -VersionText $versionText)) {
        throw "Installed Mutagen version is unsupported: $versionText. Expected 0.18.x."
    }
    Write-Host "        detected: $versionText" -ForegroundColor DarkGray
    Remove-Item -LiteralPath $extractPath -Recurse -Force

    return [pscustomobject]@{
        Planned     = $false
        Version     = $Version
        VersionText = $versionText
        Url         = $downloadUrl
        ConfiguredArchivePath = $settings.ArchivePath
        ZipPath     = $zipPath
        ExtractPath = $extractPath
        TempZipPath = $tempZipPath
        TargetPath  = $targetPath
        Sha256      = $settings.Sha256
    }
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
