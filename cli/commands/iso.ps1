# ADP-OS ISO Download Command
# Downloads Linux server ISOs to the platform ISO cache
# Supports Ubuntu Server, AlmaLinux, Rocky Linux, Debian

param(
    [Parameter(Position = 0)]
    [ValidateSet("ubuntu", "almalinux", "rocky", "debian")]
    [string]$Distro = "ubuntu",

    [string]$Url,

    [switch]$Force
)

. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")

Write-InfoLog -Message (Get-UIText -English "adp iso download $Distro" -Chinese "adp iso 下载 $Distro") -Component "cli.iso"

$config = Get-PlatformConfig
$isoCache = Resolve-Path "iso_cache"
$isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }

# Map distribution to download URL and filename
$isoMap = @{
    "ubuntu"    = @{
        Url      = "https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso"
        FileName = "ubuntu-26.04-live-server-amd64.iso"
        Label    = "Ubuntu Server 26.04 LTS"
    }
    "almalinux" = @{
        Url      = "https://repo.almalinux.org/almalinux/9/isos/x86_64/AlmaLinux-9-latest-x86_64-dvd.iso"
        FileName = "AlmaLinux-9-latest-x86_64-dvd.iso"
        Label    = "AlmaLinux 9"
    }
    "rocky"     = @{
        Url      = "https://download.rockylinux.org/pub/rocky/9/isos/x86_64/Rocky-9-latest-x86_64-dvd.iso"
        FileName = "Rocky-9-latest-x86_64-dvd.iso"
        Label    = "Rocky Linux 9"
    }
    "debian"    = @{
        Url      = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.10.0-amd64-netinst.iso"
        FileName = "debian-12.10.0-amd64-netinst.iso"
        Label    = "Debian 12"
    }
}

$entry = $isoMap[$Distro]
$downloadUrl = if ($Url) { $Url } else { $entry.Url }
$fileName = if (-not $Url) { $entry.FileName } else { Split-Path $downloadUrl -Leaf }
$label = $entry.Label
$destPath = Join-Path $isoCache $fileName

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  ADP-OS ISO Download" -Chinese "  ADP-OS ISO 下载" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-UIHost -English "  Distribution: $label" -Chinese "  发行版: $label" -ForegroundColor Cyan
Write-UIHost -English "  Source:       $downloadUrl" -Chinese "  来源:       $downloadUrl" -ForegroundColor DarkGray
Write-UIHost -English "  Destination:  $destPath" -Chinese "  目标:       $destPath" -ForegroundColor DarkGray
Write-Host ""

# Check if ISO already exists
if (Test-Path $destPath) {
    $existingSize = [math]::Round((Get-Item $destPath).Length / 1GB, 1)
    if (-not $Force) {
        Write-UIHost -English "  ISO already exists: $destPath ($existingSize GB)" -Chinese "  ISO 已存在: $destPath ($existingSize GB)" -ForegroundColor Green
        Write-UIHost -English "  Use -Force to re-download." -Chinese "  使用 -Force 重新下载。" -ForegroundColor DarkGray
        Write-UIHost -English "  To use this ISO for init: adp init -IsoPath `"$destPath`"" -Chinese "  使用此 ISO 进行初始化: adp init -IsoPath `"$destPath`"" -ForegroundColor DarkGray
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

# Download with progress
Write-UIHost -English "  Downloading... (this may take several minutes for a ~2.6 GB ISO)" -Chinese "  正在下载...（~2.6 GB 的 ISO 可能需要几分钟）" -ForegroundColor Yellow

try {
    $ProgressPreference = "Continue"
    Invoke-WebRequest -Uri $downloadUrl -OutFile $destPath -UseBasicParsing

    $downloadedSize = [math]::Round((Get-Item $destPath).Length / 1GB, 1)
    Write-Host ""
    Write-UIHost -English "  Download complete: $destPath ($downloadedSize GB)" -Chinese "  下载完成: $destPath ($downloadedSize GB)" -ForegroundColor Green
    Write-Host ""

    # Verify it looks like a valid ISO
    $item = Get-Item $destPath
    if ($item.Length -lt 1GB) {
        Write-UIHost -English "  WARNING: Downloaded file is smaller than 1 GB. It may be incomplete or not an ISO." -Chinese "  警告：下载文件小于 1 GB，可能不完整或不是 ISO。" -ForegroundColor Yellow
    } elseif ($item.Extension -ine ".iso") {
        Write-UIHost -English "  WARNING: Downloaded file does not have .iso extension." -Chinese "  警告：下载文件没有 .iso 扩展名。" -ForegroundColor Yellow
    }

    Write-UIHost -English "Next steps:" -Chinese "下一步:" -ForegroundColor Cyan
    Write-UIHost -English "  .\cli\adp.ps1 init" -Chinese "  .\cli\adp.ps1 init" -ForegroundColor DarkGray
    Write-Host ""

} catch {
    Write-ErrorLog -Message "ISO download failed: $_" -Component "cli.iso"
    Write-UIHost -English "  Download failed: $_" -Chinese "  下载失败: $_" -ForegroundColor Red

    # Clean up partial download
    if (Test-Path $destPath) {
        Remove-Item $destPath -Force -ErrorAction SilentlyContinue
    }

    Write-UIHost -English "  Retry with: .\cli\adp.ps1 iso download $Distro" -Chinese "  重试: .\cli\adp.ps1 iso download $Distro" -ForegroundColor Yellow
    Write-UIHost -English "  Or download manually and place at: $isoCache" -Chinese "  或手动下载后放到: $isoCache" -ForegroundColor Yellow
    Write-Host ""
    exit 1
}
