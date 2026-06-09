# ADP-OS ISO Download Command
# Downloads Linux server ISOs to the platform ISO cache
# Supports Ubuntu Server, AlmaLinux, Rocky Linux, Debian
# Uses BITS transfer for download resume support

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("ubuntu", "almalinux", "rocky", "debian")]
    [string]$Distro = "ubuntu",

    [string]$Url,

    [switch]$Force,

    [switch]$NonInteractive
)

. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")

Write-InfoLog -Message (Get-UIText -English "adpos iso $Distro" -Chinese "adpos iso $Distro") -Component "cli.iso"

$config = Get-PlatformConfig
$isoCache = Resolve-Path "iso_cache"
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }

# Map distribution to download URL, filename, and China mirrors
$isoMap = @{
    "ubuntu"    = @{
        Url      = "https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso"
        FileName = "ubuntu-26.04-live-server-amd64.iso"
        Label    = "Ubuntu Server 26.04 LTS"
        Mirrors  = @(
            @{ Name = "Alibaba Cloud"; Url = "https://mirrors.aliyun.com/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso" },
            @{ Name = "USTC";          Url = "https://mirrors.ustc.edu.cn/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso" },
            @{ Name = "TUNA (Tsinghua)"; Url = "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-releases/26.04/ubuntu-26.04-live-server-amd64.iso" }
        )
    }
    "almalinux" = @{
        Url      = "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-dvd.iso"
        FileName = "AlmaLinux-9-latest-x86_64-dvd.iso"
        Label    = "AlmaLinux 9"
        Mirrors  = @(
            @{ Name = "TUNA (Tsinghua)"; Url = "https://mirrors.tuna.tsinghua.edu.cn/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-dvd.iso" }
        )
    }
    "rocky"     = @{
        Url      = "https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9-latest-x86_64-dvd.iso"
        FileName = "Rocky-9-latest-x86_64-dvd.iso"
        Label    = "Rocky Linux 9"
        Mirrors  = @(
            @{ Name = "TUNA (Tsinghua)"; Url = "https://mirrors.tuna.tsinghua.edu.cn/rocky/9/isos/x86_64/Rocky-9-latest-x86_64-dvd.iso" }
        )
    }
    "debian"    = @{
        Url      = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso"
        FileName = "debian-12.10.0-amd64-netinst.iso"
        Label    = "Debian 12"
        Mirrors  = @(
            @{ Name = "TUNA (Tsinghua)"; Url = "https://mirrors.tuna.tsinghua.edu.cn/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso" },
            @{ Name = "USTC";           Url = "https://mirrors.ustc.edu.cn/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso" }
        )
    }
}

$entry = $isoMap[$Distro]
$downloadUrl = if ($Url) { $Url } else { $entry.Url }
$fileName = if (-not $Url) { $entry.FileName } else { Split-Path $downloadUrl -Leaf }
$label = $entry.Label
$destPath = Join-Path $isoCache $fileName

# Banner
if (-not $NonInteractive) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-UIHost -English "  ADP-OS ISO Download" -Chinese "  ADP-OS ISO 下载" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-UIHost -English "  Distribution: $label" -Chinese "  发行版: $label" -ForegroundColor Cyan
    Write-UIHost -English "  Source:       $downloadUrl" -Chinese "  来源:       $downloadUrl" -ForegroundColor DarkGray
    Write-UIHost -English "  Destination:  $destPath" -Chinese "  目标:       $destPath" -ForegroundColor DarkGray
    Write-Host ""
}

# Show China mirror tips (if not using custom URL and not non-interactive)
if (-not $Url -and -not $NonInteractive -and $entry.Mirrors.Count -gt 0) {
    Write-UIHost -English "  China mirror options (faster from mainland China):" -Chinese "  中国镜像选项（从中国大陆下载更快）：" -ForegroundColor Yellow
    foreach ($mirror in $entry.Mirrors) {
        Write-Host "    $($mirror.Name)" -ForegroundColor DarkGray -NoNewline
        Write-Host " : adpos iso $Distro -Url '$($mirror.Url)'" -ForegroundColor DarkGray
    }
    Write-Host ""
}

# Check if ISO already exists
if (Test-Path $destPath) {
    $existingSize = [math]::Round((Get-Item $destPath).Length / 1GB, 1)
    if (-not $Force) {
        Write-UIHost -English "  ISO already exists: $destPath ($existingSize GB)" -Chinese "  ISO 已存在: $destPath ($existingSize GB)" -ForegroundColor Green
        Write-UIHost -English "  Use -Force to re-download." -Chinese "  使用 -Force 重新下载。" -ForegroundColor DarkGray
        Write-UIHost -English "  To use this ISO for init: adpos init -IsoPath `"$destPath`"" -Chinese "  使用此 ISO 进行初始化: adpos init -IsoPath `"$destPath`"" -ForegroundColor DarkGray
        Write-Host ""
        exit 0
    }
    Write-UIHost -English "  Removing existing ISO (Force)...  " -Chinese "  正在移除已存在的 ISO（强制）...  " -ForegroundColor Yellow -NoNewline
    Remove-Item $destPath -Force
    Write-Host "[OK]" -ForegroundColor Green
}

# Ensure ISO cache directory exists
if (-not (Test-Path $isoCache)) {
    New-Item -ItemType Directory -Path $isoCache -Force | Out-Null
}

# Download via BITS transfer (supports resume on connection drop)
$downloadMsg = if ($NonInteractive) {
    Get-UIText -English "Downloading $label ISO via BITS (resumable)..." -Chinese "正在通过 BITS 下载 $label ISO（支持断点续传）..."
} else {
    Get-UIText -English "  Downloading via BITS transfer... (resumable, ~2.6 GB may take several minutes)" -Chinese "  正在通过 BITS 传输下载...（支持断点续传，~2.6 GB 可能需要几分钟）"
}
Write-UIHost -English $downloadMsg -Chinese $downloadMsg -ForegroundColor Yellow

try {
    # Use BITS (Background Intelligent Transfer Service) for resume support
    # BITS automatically resumes partial downloads if the connection drops
    Import-Module BitsTransfer -ErrorAction Stop
    Start-BitsTransfer -Source $downloadUrl -Destination $destPath `
        -DisplayName "ADP-OS: $label" `
        -Description "Downloading $label ISO to $destPath" `
        -ErrorAction Stop

    $downloadedSize = [math]::Round((Get-Item $destPath).Length / 1GB, 1)
    if (-not $NonInteractive) {
        Write-Host ""
        Write-UIHost -English "  Download complete: $destPath ($downloadedSize GB)" -Chinese "  下载完成: $destPath ($downloadedSize GB)" -ForegroundColor Green
        Write-Host ""
    } else {
        Write-UIHost -English "Download complete: $destPath ($downloadedSize GB)" -Chinese "下载完成: $destPath ($downloadedSize GB)" -ForegroundColor Green
    }

    # Verify it looks like a valid ISO
    $item = Get-Item $destPath
    if ($item.Length -lt 1GB) {
        Write-UIHost -English "  WARNING: Downloaded file is smaller than 1 GB. It may be incomplete or not an ISO." -Chinese "  警告：下载文件小于 1 GB，可能不完整或不是 ISO。" -ForegroundColor Yellow
    } elseif ($item.Extension -ine ".iso") {
        Write-UIHost -English "  WARNING: Downloaded file does not have .iso extension." -Chinese "  警告：下载文件没有 .iso 扩展名。" -ForegroundColor Yellow
    }

    if (-not $NonInteractive) {
        Write-UIHost -English "Next steps:" -Chinese "下一步:" -ForegroundColor Cyan
        Write-UIHost -English "  adpos init" -Chinese "  adpos init" -ForegroundColor DarkGray
        Write-Host ""
    }

} catch {
    Write-ErrorLog -Message "ISO download failed: $_" -Component "cli.iso"
    Write-UIHost -English "  Download failed: $_" -Chinese "  下载失败: $_" -ForegroundColor Red

    # NOTE: BITS handles partial downloads better — partial files may be kept by BITS
    # and resumed on retry. Only clean up if the file is clearly corrupt.
    if (Test-Path $destPath) {
        $partialSize = (Get-Item $destPath).Length
        if ($partialSize -lt 1MB) {
            # File is tiny (likely an error page), remove it
            Remove-Item $destPath -Force -ErrorAction SilentlyContinue
        } else {
            Write-UIHost -English "  Partial download preserved ($([math]::Round($partialSize/1MB, 1)) MB). BITS will resume on retry." -Chinese "  部分下载已保留 ($([math]::Round($partialSize/1MB, 1)) MB)。BITS 将在重试时续传。" -ForegroundColor Yellow
        }
    }

    Write-UIHost -English "  Retry with: adpos iso $Distro" -Chinese "  重试: adpos iso $Distro" -ForegroundColor Yellow
    Write-UIHost -English "  Or use a China mirror: adpos iso $Distro -Url '<mirror-url>'" -Chinese "  或使用中国镜像: adpos iso $Distro -Url '<镜像地址>'" -ForegroundColor Yellow
    Write-UIHost -English "  Or download manually and place at: $isoCache" -Chinese "  或手动下载后放到: $isoCache" -ForegroundColor Yellow
    if (-not $NonInteractive) { Write-Host "" }
    exit 1
}
