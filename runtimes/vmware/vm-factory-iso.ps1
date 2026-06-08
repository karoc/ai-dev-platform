# ADP-OS VMware factory ISO helpers.

function ConvertTo-VMXPath {
    param([string]$Path)

    return $Path -replace '\\', '/'
}

function Find-VmwareDiskManager {
    $knownPaths = @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmware-vdiskmanager.exe",
        "C:\Program Files\VMware\VMware Workstation\vmware-vdiskmanager.exe"
    )

    foreach ($path in $knownPaths) {
        if (Test-Path $path) { return $path }
    }

    $fromPath = (Get-Command vmware-vdiskmanager.exe -ErrorAction SilentlyContinue).Source
    if ($fromPath) { return $fromPath }

    return $null
}

function Find-ISOCreator {
    $nativeTools = @("mkisofs", "genisoimage", "xorriso", "oscdimg")
    foreach ($tool in $nativeTools) {
        $cmd = Get-Command $tool -ErrorAction SilentlyContinue
        if ($cmd) {
            return @{
                Type = $tool
                Path = $cmd.Source
            }
        }
    }

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wsl) {
        foreach ($tool in @("genisoimage", "mkisofs", "xorriso")) {
            $null = & $wsl.Source bash -lc "command -v $tool >/dev/null 2>&1" 2>$null
            if ($LASTEXITCODE -eq 0) {
                return @{
                    Type = "wsl-$tool"
                    Path = $wsl.Source
                }
            }
        }
    }

    try {
        $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($fsi) | Out-Null
        return @{
            Type = "imapi2"
            Path = "Windows IMAPI2FS"
        }
    } catch {}

    return $null
}

function Find-ISORemasterTool {
    $xorriso = Get-Command xorriso -ErrorAction SilentlyContinue
    if ($xorriso) {
        return @{
            Type = "xorriso"
            Path = $xorriso.Source
        }
    }

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wsl) {
        $null = & $wsl.Source bash -lc "command -v xorriso >/dev/null 2>&1" 2>$null
        if ($LASTEXITCODE -eq 0) {
            return @{
                Type = "wsl-xorriso"
                Path = $wsl.Source
            }
        }
    }

    return $null
}

function New-VirtualDisk {
    param(
        [string]$VmdkPath,
        [int]$DiskGB
    )

    if (Test-Path $VmdkPath) {
        Write-InfoLog -Message "VMDK already exists: $VmdkPath" -Component "vm-factory"
        return $VmdkPath
    }

    $diskManager = Find-VmwareDiskManager
    if (-not $diskManager) {
        throw "vmware-vdiskmanager.exe not found. Install VMware Workstation or add vmware-vdiskmanager.exe to PATH."
    }

    $parent = Split-Path $VmdkPath -Parent
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    $args = @(
        "-c",
        "-s", "${DiskGB}GB",
        "-a", "lsilogic",
        "-t", "0",
        $VmdkPath
    )

    $proc = Start-Process -FilePath $diskManager -ArgumentList $args `
        -WindowStyle Hidden -Wait -PassThru -ErrorAction Stop

    if ($proc.ExitCode -ne 0 -or -not (Test-Path $VmdkPath)) {
        throw "Failed to create VMDK at $VmdkPath (vmware-vdiskmanager exit code: $($proc.ExitCode))"
    }

    Write-InfoLog -Message "VMDK created: $VmdkPath (${DiskGB}GB)" -Component "vm-factory"
    return $VmdkPath
}

function ConvertTo-GrubKernelArgs {
    param([string]$BootArgs)

    return $BootArgs -replace ';', '\;'
}

function New-AutoinstallGrubConfig {
    param([string]$BootArgs)

    $grubArgs = ConvertTo-GrubKernelArgs -BootArgs $BootArgs

    return @"
set timeout=1
set default=0

loadfont unicode

set menu_color_normal=white/black
set menu_color_highlight=black/light-gray

menuentry "ADP-OS Autoinstall" {
    set gfxpayload=keep
    linux  /casper/vmlinuz  $grubArgs ---
    initrd /casper/initrd
}
grub_platform
if [ "`$grub_platform" = "efi" ]; then
menuentry 'Boot from next volume' {
    exit 1
}
menuentry 'UEFI Firmware Settings' {
    fwsetup
}
fi
"@
}

function Invoke-CapturedNativeCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments
    )

    $output = & $FilePath @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $detail = ($output | Out-String).Trim()
    if ([string]::IsNullOrWhiteSpace($detail)) {
        $detail = "no command output captured"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Detail   = $detail
    }
}

function New-AutoinstallISO {
    param(
        [string]$RuntimeName,
        [string]$SourceIsoPath,
        [string]$SeedSourceDir,
        [string]$BootArgs,
        [object]$Layout = $null
    )

    $tool = Find-ISORemasterTool
    if (-not $tool) {
        throw "xorriso is required to remaster Ubuntu autoinstall ISOs. Install xorriso natively or in WSL."
    }

    if (-not $Layout -and (Get-Command Get-ADPVMwareRuntimeLayout -ErrorAction SilentlyContinue)) {
        $Layout = Get-ADPVMwareRuntimeLayout -RuntimeName $RuntimeName -VmStorePath $script:VmFactoryState.VmStore -SeedRootPath $script:VmFactoryState.SeedDir -Namespace ""
    }

    $outputIso = if ($Layout) { $Layout.AutoinstallIsoPath } else { Join-Path $script:VmFactoryState.SeedDir "${RuntimeName}-autoinstall.iso" }
    $workDir = if ($Layout) { $Layout.AutoinstallWorkDir } else { Join-Path $script:VmFactoryState.SeedDir "${RuntimeName}-autoinstall-work" }
    $label = if ($Layout) { $Layout.InstallIsoLabel } else { "ADP_$($RuntimeName.ToUpperInvariant())" }

    if (Test-Path $workDir) { Remove-Item $workDir -Recurse -Force }
    New-Item -ItemType Directory -Path $workDir -Force | Out-Null

    $grubCfgPath = Join-Path $workDir "grub.cfg"
    $grubCfg = New-AutoinstallGrubConfig -BootArgs $BootArgs
    Set-Content -Path $grubCfgPath -Value $grubCfg -NoNewline -Encoding UTF8

    $userDataPath = Join-Path $SeedSourceDir "user-data"
    $metaDataPath = Join-Path $SeedSourceDir "meta-data"
    if (-not (Test-Path $userDataPath) -or -not (Test-Path $metaDataPath)) {
        throw "Cloud-init seed files are missing in $SeedSourceDir"
    }

    if (Test-Path $outputIso) {
        Remove-Item $outputIso -Force
    }

    try {
        switch ($tool.Type) {
            "wsl-xorriso" {
                $sourceWsl = ConvertTo-WSLPath $SourceIsoPath
                $outputWsl = ConvertTo-WSLPath $outputIso
                $grubWsl = ConvertTo-WSLPath $grubCfgPath
                $userDataWsl = ConvertTo-WSLPath $userDataPath
                $metaDataWsl = ConvertTo-WSLPath $metaDataPath

                $commandParts = @(
                    "xorriso",
                    "-indev $(Quote-BashArg $sourceWsl)",
                    "-outdev $(Quote-BashArg $outputWsl)",
                    "-map $(Quote-BashArg $grubWsl) /boot/grub/grub.cfg",
                    "-map $(Quote-BashArg $userDataWsl) /user-data",
                    "-map $(Quote-BashArg $metaDataWsl) /meta-data",
                    "-boot_image any replay",
                    "-volid $(Quote-BashArg $label)"
                )
                $command = $commandParts -join " "
                $result = Invoke-CapturedNativeCommand -FilePath $tool.Path -Arguments @("bash", "-lc", $command)
                if ($result.ExitCode -ne 0) {
                    throw "xorriso failed with exit code $($result.ExitCode): $($result.Detail)"
                }
            }
            "xorriso" {
                $args = @(
                    "-indev", $SourceIsoPath,
                    "-outdev", $outputIso,
                    "-map", $grubCfgPath, "/boot/grub/grub.cfg",
                    "-map", $userDataPath, "/user-data",
                    "-map", $metaDataPath, "/meta-data",
                    "-boot_image", "any", "replay",
                    "-volid", $label
                )
                $result = Invoke-CapturedNativeCommand -FilePath $tool.Path -Arguments $args
                if ($result.ExitCode -ne 0) {
                    throw "xorriso failed with exit code $($result.ExitCode): $($result.Detail)"
                }
            }
            default {
                throw "Unsupported ISO remaster tool: $($tool.Type)"
            }
        }
    } finally {
        Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    if (-not (Test-Path $outputIso)) {
        throw "Autoinstall ISO was not created: $outputIso"
    }

    Write-InfoLog -Message "Autoinstall ISO created: $outputIso" -Component "vm-factory"
    return $outputIso
}

function New-ISO {
    param(
        [string]$SourceDir,
        [string]$OutputPath
    )

    $creator = Find-ISOCreator
    if ($creator -and $creator.Type -eq "imapi2") {
        return New-ISOFallback -SourceDir $SourceDir -OutputPath $OutputPath
    }

    if ($creator) {
        $label = "CIDATA"
        $cmd = $creator.Path
        $args = @()

        switch -Regex ($creator.Type) {
            "^xorriso$" {
                $args = @("-as", "mkisofs", "-output", $OutputPath, "-volid", $label, "-joliet", "-rock", $SourceDir)
            }
            "^oscdimg$" {
                $args = @("-l$label", "-j2", $SourceDir, $OutputPath)
            }
            "^wsl-" {
                $tool = $creator.Type -replace "^wsl-", ""
                $sourceWsl = ConvertTo-WSLPath $SourceDir
                $outputWsl = ConvertTo-WSLPath $OutputPath
                $mkisofsArgs = "-output $(Quote-BashArg $outputWsl) -volid $(Quote-BashArg $label) -joliet -rock $(Quote-BashArg $sourceWsl)"
                if ($tool -eq "xorriso") {
                    $mkisofsArgs = "-as mkisofs $mkisofsArgs"
                }
                $command = "$tool $mkisofsArgs"
                & $cmd bash -lc $command
                if ($LASTEXITCODE -eq 0 -and (Test-Path $OutputPath)) {
                    return $true
                }
                Write-WarnLog -Message "ISO creator $($creator.Type) failed with exit code $LASTEXITCODE, trying fallback..." -Component "vm-factory"
                return New-ISOFallback -SourceDir $SourceDir -OutputPath $OutputPath
            }
            default {
                $args = @("-output", $OutputPath, "-volid", $label, "-joliet", "-rock", $SourceDir)
            }
        }

        $proc = Start-Process -FilePath $cmd -ArgumentList $args -Wait -NoNewWindow -PassThru
        if ($proc.ExitCode -eq 0 -and (Test-Path $OutputPath)) {
            return $true
        }
        Write-WarnLog -Message "ISO creator $($creator.Type) failed with exit code $($proc.ExitCode), trying fallback..." -Component "vm-factory"
    }

    return New-ISOFallback -SourceDir $SourceDir -OutputPath $OutputPath
}

function ConvertTo-WSLPath {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $drive = $fullPath.Substring(0, 1).ToLowerInvariant()
    $rest = $fullPath.Substring(2) -replace '\\', '/'
    return "/mnt/$drive$rest"
}

function Quote-BashArg {
    param([string]$Value)

    return "'" + ($Value -replace "'", "'\''") + "'"
}

function New-ISOFallback {
    param(
        [string]$SourceDir,
        [string]$OutputPath
    )

    try {
        $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
        $fsi.FileSystemsToCreate = 7
        $fsi.VolumeName = "CIDATA"
        $fsi.FreeMediaBlocks = 0

        $dir = $fsi.Root
        Get-ChildItem $SourceDir | ForEach-Object {
            if (-not $_.PSIsContainer) {
                $stream = New-Object -ComObject ADODB.Stream
                $stream.Type = 1
                $stream.Open()
                $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
                $stream.Write($bytes)
                $stream.Position = 0
                $dir.AddFile($_.Name, $stream)
                [System.Runtime.InteropServices.Marshal]::ReleaseComObject($stream) | Out-Null
            }
        }

        $resultImage = $fsi.CreateResultImage()
        $imgStream = [System.Runtime.InteropServices.ComTypes.IStream]$resultImage.ImageStream
        $fileStream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
        $buffer = New-Object byte[] 32768
        $bytesReadPtr = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(4)

        try {
            while ($true) {
                [System.Runtime.InteropServices.Marshal]::WriteInt32($bytesReadPtr, 0)
                $imgStream.Read($buffer, $buffer.Length, $bytesReadPtr)
                $bytesRead = [System.Runtime.InteropServices.Marshal]::ReadInt32($bytesReadPtr)
                if ($bytesRead -le 0) { break }
                $fileStream.Write($buffer, 0, $bytesRead)
            }
        } finally {
            [System.Runtime.InteropServices.Marshal]::FreeHGlobal($bytesReadPtr)
            $fileStream.Close()
        }

        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($fsi) | Out-Null

        if (Test-Path $OutputPath) {
            Write-InfoLog -Message "ISO created via COM fallback: $OutputPath" -Component "vm-factory"
            return $true
        }
    } catch {
        Write-WarnLog -Message "COM fallback failed: $_" -Component "vm-factory"
    }

    Write-ErrorLog -Message "Cannot create ISO. Please install mkisofs or genisoimage." -Component "vm-factory"
    Write-Host "  Option 1: winget install ezwinports.genisoimage" -ForegroundColor DarkGray
    Write-Host "  Option 2: Use WSL: wsl sudo apt install genisoimage" -ForegroundColor DarkGray
    return $false
}

function Generate-PasswordHash {
    param([string]$Password)

    $salt = "adposrounds"

    $openssl = Get-Command openssl -ErrorAction SilentlyContinue
    if ($openssl) {
        $hash = & $openssl.Source passwd -6 -salt $salt $Password 2>$null
        if ($LASTEXITCODE -eq 0 -and $hash) { return $hash.Trim() }
    }

    $wsl = Get-Command wsl.exe -ErrorAction SilentlyContinue
    if ($wsl) {
        $command = "openssl passwd -6 -salt $(Quote-BashArg $salt) $(Quote-BashArg $Password)"
        $hash = & $wsl.Source bash -lc $command 2>$null
        if ($LASTEXITCODE -eq 0 -and $hash) { return $hash.Trim() }
    }

    try {
        $python = Get-Command python3 -ErrorAction SilentlyContinue
        if (-not $python) { $python = Get-Command python -ErrorAction SilentlyContinue }
        if ($python) {
            $script = "import crypt; print(crypt.crypt('$Password', crypt.mksalt(crypt.METHOD_SHA512)))"
            $hash = & $python.Source -c $script 2>$null
            if ($hash) { return $hash.Trim() }
        }
    } catch {}

    if ($Password -ne "adp") {
        throw "Unable to generate SHA-512 password hash. Install openssl in Windows or WSL."
    }

    return '$6$adposrounds$vawoWnCOhM3XqOHrMwZjzZPhAPMVpTQ4D8TiYVPbg5XWJYGmjntjsoRHB.J5VZgyMC6pek.grY5IOtqvTuDwU1'
}
