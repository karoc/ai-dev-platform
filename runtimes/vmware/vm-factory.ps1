# ADP-OS VM Factory (Windows/VMware)
# Phase 2: Programmatic VM creation with Ubuntu autoinstall via cloud-init
# Generates VMX files, seed ISOs, and orchestrates full provisioning

$script:VmFactoryState = @{}

function Initialize-VmFactory {
    param(
        [string]$ProjectRoot,
        [string]$IsoCachePath,
        [string]$VmStorePath
    )

    $script:VmFactoryState.ProjectRoot = $ProjectRoot
    $script:VmFactoryState.IsoCache = $IsoCachePath
    $script:VmFactoryState.VmStore = $VmStorePath
    $script:VmFactoryState.SeedDir = Join-Path $VmStorePath "seeds"

    if (-not (Test-Path $script:VmFactoryState.SeedDir)) {
        New-Item -ItemType Directory -Path $script:VmFactoryState.SeedDir -Force | Out-Null
    }

    Write-InfoLog -Message "VM Factory initialized" -Component "vm-factory"
}

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
            & $wsl.Source bash -lc "command -v $tool >/dev/null 2>&1" 2>$null
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
        & $wsl.Source bash -lc "command -v xorriso >/dev/null 2>&1" 2>$null
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

function Test-RuntimeProvisioningPlan {
    param(
        [string]$RuntimeName
    )

    $checks = [System.Collections.Generic.List[object]]::new()

    function Add-PlanCheck {
        param(
            [string]$Name,
            [bool]$Passed,
            [string]$Detail = ""
        )

        $checks.Add([pscustomobject]@{
            Name   = $Name
            Passed = $Passed
            Detail = $Detail
        }) | Out-Null
    }

    $rt = Get-RuntimeConfig $RuntimeName
    $profile = Get-OSProfile -OSName $rt.os
    $config = Get-PlatformConfig

    Add-PlanCheck -Name "runtime exists" -Passed ($null -ne $rt) -Detail $RuntimeName
    Add-PlanCheck -Name "MVP OS profile" -Passed ($rt.os -eq "ubuntu-26.04") -Detail $rt.os
    Add-PlanCheck -Name "seed type" -Passed ($profile.seedType -eq "cloud-init") -Detail $profile.seedType
    Add-PlanCheck -Name "boot args" -Passed (-not [string]::IsNullOrWhiteSpace($profile.bootArgs)) -Detail $profile.bootArgs
    Add-PlanCheck -Name "SSH port" -Passed ($rt.ssh_port -eq 22) -Detail "port $($rt.ssh_port)"

    $isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
    $isoPath = Join-Path $script:VmFactoryState.IsoCache $isoName
    Add-PlanCheck -Name "OS ISO" -Passed (Test-Path $isoPath) -Detail $isoPath

    $diskManager = Find-VmwareDiskManager
    Add-PlanCheck -Name "VMDK creator" -Passed ($null -ne $diskManager) -Detail $diskManager

    $isoCreator = Find-ISOCreator
    $isoCreatorDetail = if ($isoCreator) { "$($isoCreator.Type): $($isoCreator.Path)" } else { "missing" }
    Add-PlanCheck -Name "seed ISO creator" -Passed ($null -ne $isoCreator) -Detail $isoCreatorDetail

    $isoRemasterTool = Find-ISORemasterTool
    $isoRemasterDetail = if ($isoRemasterTool) { "$($isoRemasterTool.Type): $($isoRemasterTool.Path)" } else { "missing" }
    Add-PlanCheck -Name "install ISO remaster" -Passed ($null -ne $isoRemasterTool) -Detail $isoRemasterDetail

    $bootstrapScript = Join-Path $script:VmFactoryState.ProjectRoot "bootstrap\$($rt.bootstrap_profile)\setup-$($rt.bootstrap_profile).sh"
    Add-PlanCheck -Name "bootstrap profile" -Passed (Test-Path $bootstrapScript) -Detail $bootstrapScript

    $baseBootstrap = Join-Path $script:VmFactoryState.ProjectRoot "bootstrap\base\setup-base.sh"
    Add-PlanCheck -Name "base bootstrap" -Passed (Test-Path $baseBootstrap) -Detail $baseBootstrap

    return @($checks)
}

function Get-RuntimeStaticNetwork {
    param([string]$RuntimeName)

    $config = Get-PlatformConfig
    $rt = Get-RuntimeConfig $RuntimeName
    $network = $config.network

    if (-not $network -or $network.mode -ne "static" -or -not $rt.static_ip) {
        return $null
    }

    $nat = $network.vmware_nat
    if (-not $nat) {
        throw "platform.json network.vmware_nat is required when network.mode is static"
    }

    return [pscustomobject]@{
        Address        = $rt.static_ip
        Prefix         = if ($nat.prefix) { [int]$nat.prefix } else { 24 }
        Gateway        = $nat.gateway
        Dns            = @($nat.dns)
        InterfaceMatch = if ($nat.interface_match) { $nat.interface_match } else { "en*" }
    }
}

function New-AutoinstallNetworkYaml {
    param([string]$RuntimeName)

    $network = Get-RuntimeStaticNetwork -RuntimeName $RuntimeName
    if (-not $network) {
        return ""
    }

    $dns = (@($network.Dns) | Where-Object { $_ }) -join ", "
    if (-not $dns) {
        $dns = $network.Gateway
    }

    return @"
  network:
    version: 2
    ethernets:
      adp0:
        match:
          name: "$($network.InterfaceMatch)"
        dhcp4: false
        dhcp6: false
        addresses:
          - $($network.Address)/$($network.Prefix)
        routes:
          - to: default
            via: $($network.Gateway)
        nameservers:
          addresses: [$dns]
"@
}

function New-SeedISO {
    param(
        [string]$RuntimeName,
        [string]$Hostname,
        [string]$Username,
        [string]$SshPubKey
    )

    $rt = Get-RuntimeConfig $RuntimeName
    $profile = Get-OSProfile -OSName $rt.os
    $seedType = $profile.seedType

    $seedDir = Join-Path $script:VmFactoryState.SeedDir $RuntimeName
    if (Test-Path $seedDir) { Remove-Item $seedDir -Recurse -Force }
    New-Item -ItemType Directory -Path $seedDir -Force | Out-Null

    $passwordHash = Generate-PasswordHash -Password "adp"
    $cloudInitPackageLines = ($profile.packages | ForEach-Object { "    - $_" }) -join "`n"
    $kickstartPackageLines = $profile.packages -join "`n"
    $debianPackageList = $profile.packages -join " "
    $networkYaml = New-AutoinstallNetworkYaml -RuntimeName $RuntimeName

    switch ($seedType) {
        "cloud-init" {
            $userData = @"
#cloud-config
autoinstall:
  version: 1
  locale: en_US.UTF-8
  keyboard:
    layout: us
  identity:
    hostname: $Hostname
    username: $Username
    password: "$passwordHash"
  ssh:
    install-server: true
    allow-pw: true
    authorized-keys:
      - $SshPubKey
$networkYaml
  storage:
    layout:
      name: direct
  packages:
$cloudInitPackageLines
  late-commands:
    - curtin in-target --target=/target -- mkdir -p /home/$Username
    - curtin in-target --target=/target -- bash -lc 'passwd -u $Username || true'
    - echo "ADP-OS Runtime $RuntimeName provisioned on `$(date -u)" > /target/home/$Username/.adp-provisioned
    - curtin in-target --target=/target -- chown ${Username}:${Username} /home/$Username/.adp-provisioned
  user-data:
    disable_root: true
    timezone: Asia/Shanghai
  updates: all
  shutdown: reboot
"@
            $metaData = @"
instance-id: adp-${RuntimeName}-001
local-hostname: $Hostname
"@
            Set-Content -Path (Join-Path $seedDir "user-data") -Value $userData -NoNewline
            Set-Content -Path (Join-Path $seedDir "meta-data") -Value $metaData -NoNewline
        }
        "kickstart" {
            $ksContent = @"
#version=RHEL9
ignoredisk --only-use=sda
autopart --type=lvm
clearpart --none --initlabel
timezone Asia/Shanghai --utc
lang en_US.UTF-8
keyboard us
network --bootproto=dhcp --device=link --activate
rootpw --lock
user --name=$Username --password=$passwordHash --iscrypted --groups=wheel
sshkey --username=$Username "$SshPubKey"
firewall --disabled
selinux --permissive
skipx
services --enabled=sshd
reboot
%packages
$kickstartPackageLines
%end
%post --log=/root/ks-post.log
echo "ADP-OS Runtime $RuntimeName provisioned on `$(date -u)" > /home/$Username/.adp-provisioned
chown ${Username}:${Username} /home/$Username/.adp-provisioned
%end
"@
            Set-Content -Path (Join-Path $seedDir "ks.cfg") -Value $ksContent -NoNewline
        }
        "preseed" {
            $preseedContent = @"
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string $Hostname
d-i netcfg/get_domain string localdomain
d-i mirror/country string manual
d-i mirror/http/hostname string archive.ubuntu.com
d-i mirror/http/directory string /ubuntu
d-i clock-setup/utc boolean true
d-i time/zone string Asia/Shanghai
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i passwd/root-login boolean false
d-i passwd/user-fullname string ADP User
d-i passwd/username string $Username
d-i passwd/user-password-crypted password $passwordHash
d-i user-setup/allow-password-remote-login boolean true
d-i pkgsel/include string $debianPackageList
d-i grub-installer/only_debian boolean true
d-i finish-install/reboot_in_progress note
d-i preseed/late_command string `
    in-target bash -c 'echo "ADP-OS Runtime $RuntimeName provisioned on `$(date -u)" > /home/$Username/.adp-provisioned && chown ${Username}:${Username} /home/$Username/.adp-provisioned'
d-i debian-installer/add-kernel-opts string console=ttyS0
d-i cdrom-detect/eject boolean false
"@
            Set-Content -Path (Join-Path $seedDir "preseed.cfg") -Value $preseedContent -NoNewline
        }
        default {
            throw "Unsupported seed type: $seedType"
        }
    }

    $seedIso = Join-Path $script:VmFactoryState.SeedDir "${RuntimeName}-seed.iso"
    $result = New-ISO -SourceDir $seedDir -OutputPath $seedIso

    if (-not $result) {
        throw "Failed to create seed ISO for $RuntimeName"
    }

    Write-InfoLog -Message "Seed ISO created ($seedType): $seedIso" -Component "vm-factory"
    return $seedIso
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

function New-AutoinstallISO {
    param(
        [string]$RuntimeName,
        [string]$SourceIsoPath,
        [string]$SeedSourceDir,
        [string]$BootArgs
    )

    $tool = Find-ISORemasterTool
    if (-not $tool) {
        throw "xorriso is required to remaster Ubuntu autoinstall ISOs. Install xorriso natively or in WSL."
    }

    $outputIso = Join-Path $script:VmFactoryState.SeedDir "${RuntimeName}-autoinstall.iso"
    $workDir = Join-Path $script:VmFactoryState.SeedDir "${RuntimeName}-autoinstall-work"
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
                $label = "ADP_$($RuntimeName.ToUpperInvariant())"

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
                & $tool.Path bash -lc $command
                if ($LASTEXITCODE -ne 0) {
                    throw "xorriso failed with exit code $LASTEXITCODE"
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
                    "-volid", "ADP_$($RuntimeName.ToUpperInvariant())"
                )
                $proc = Start-Process -FilePath $tool.Path -ArgumentList $args -Wait -NoNewWindow -PassThru
                if ($proc.ExitCode -ne 0) {
                    throw "xorriso failed with exit code $($proc.ExitCode)"
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

function New-VMX {
    param(
        [string]$RuntimeName,
        [hashtable]$RuntimeConfig,
        [string]$VmPath,
        [string]$UbuntuIsoPath,
        [string]$SeedIsoPath
    )

    $vmName = "adp-$RuntimeName"
    $vmxPath = Join-Path $VmPath "$vmName.vmx"
    $vmdkPath = Join-Path $VmPath "$vmName.vmdk"

    if (-not (Test-Path $VmPath)) {
        New-Item -ItemType Directory -Path $VmPath -Force | Out-Null
    }

    $rt = Get-RuntimeConfig $RuntimeName
    $profile = Get-OSProfile -OSName $rt.os
    $guestOSType = $profile.guestOS

    $diskGB = $RuntimeConfig.disk
    $memoryMB = $RuntimeConfig.memory
    $numCpus = $RuntimeConfig.cpu
    $bootArgs = $profile.bootArgs
    $nocloudSeed = "ds=nocloud;s=/cdrom/"

    New-VirtualDisk -VmdkPath $vmdkPath -DiskGB $diskGB | Out-Null

    $installIsoVmxPath = ConvertTo-VMXPath $UbuntuIsoPath
    $seedIsoVmxPath = ConvertTo-VMXPath $SeedIsoPath

    $vmxContent = @"
.encoding = "UTF-8"
config.version = "8"
virtualHW.version = "18"
displayName = "$vmName"
guestOS = "$guestOSType"
memsize = "$memoryMB"
numvcpus = "$numCpus"
cpuid.coresPerSocket = "$numCpus"
firmware = "efi"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
scsi0.virtualDev = "lsilogic"
scsi0.present = "TRUE"
sata0.present = "TRUE"
ide0:0.present = "TRUE"
ide0:0.fileName = "$installIsoVmxPath"
ide0:0.deviceType = "cdrom-image"
ide0:1.present = "TRUE"
ide0:1.fileName = "$seedIsoVmxPath"
ide0:1.deviceType = "cdrom-image"
scsi0:0.present = "TRUE"
scsi0:0.fileName = "$vmName.vmdk"
scsi0:0.deviceType = "disk"
ethernet0.present = "TRUE"
ethernet0.connectionType = "nat"
ethernet0.addressType = "generated"
ethernet0.virtualDev = "e1000"
ethernet0.wakeOnPcktRcv = "FALSE"
floppy0.present = "FALSE"
sound.present = "FALSE"
tools.syncTime = "TRUE"
bios.bootDelay = "5000"
guestinfo.adp.runtime = "$RuntimeName"
guestinfo.adp.bootArgs = "$bootArgs"
guestinfo.adp.nocloudSeed = "$nocloudSeed"
uuid.action = "create"
annotation = "ADP-OS Runtime: $RuntimeName | Boot args: $bootArgs | Auto-provisioned $(Get-Date -Format 'yyyy-MM-dd')"
"@

    Set-Content -Path $vmxPath -Value $vmxContent -Encoding UTF8
    Write-InfoLog -Message "VMX created: $vmxPath" -Component "vm-factory"
    return $vmxPath
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

    # Fallback: Create a minimal ISO using raw binary (works for cloud-init seed)
    # cloud-init reads CIDATA volumes - we can create a simple ISO9660
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

    # Use PowerShell + COM (IMAPI2) to create ISO
    try {
        $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
        $fsi.FileSystemsToCreate = 7  # ISO9660 + Joliet
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

    # Last resort: Write a small helper script
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

    # Pre-computed SHA-512 hash for "adp" (salt: adposrounds), verified with openssl passwd -6.
    return '$6$adposrounds$vawoWnCOhM3XqOHrMwZjzZPhAPMVpTQ4D8TiYVPbg5XWJYGmjntjsoRHB.J5VZgyMC6pek.grY5IOtqvTuDwU1'
}

function New-RuntimeVM {
    param(
        [string]$RuntimeName,
        [switch]$SkipProvision,
        [switch]$StartAfterCreate
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Creating VM for: $RuntimeName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $rt = Get-RuntimeConfig $RuntimeName
    $config = Get-PlatformConfig
    $vmName = "adp-$RuntimeName"
    $vmPath = Join-Path $script:VmFactoryState.VmStore $vmName

    # Check if VM already exists
    $vmxPath = Join-Path $vmPath "$vmName.vmx"
    if (Test-Path $vmxPath) {
        Write-Host "VM already exists at: $vmxPath" -ForegroundColor Yellow
        $status = Get-VMStatus $vmxPath
        Write-Host "  Status: $status" -ForegroundColor DarkGray
        if ($StartAfterCreate -and $status -notmatch "running") {
            Write-Host "Starting existing VM..." -ForegroundColor Yellow
            Start-VM -VmxPath $vmxPath -Mode "nogui" | Out-Null
        }
        return $vmxPath
    }

    # Check OS ISO
    $isoCache = $script:VmFactoryState.IsoCache
    $isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
    $isoPath = Join-Path $isoCache $isoName
    if (-not (Test-Path $isoPath)) {
        throw "OS ISO not found: $isoPath. Place the ISO there or use -IsoPath parameter."
    }

    Write-Host "OS ISO: $isoPath" -ForegroundColor Green

    # Initialize SSH keys
    . (Join-Path $script:VmFactoryState.ProjectRoot "adapters\windows\ssh\ssh.ps1")
    $sshKeyPath = Initialize-SSH
    $sshPubKey = Get-SSHPubKey
    Write-Host "SSH key: $sshKeyPath" -ForegroundColor Green

    # Create seed ISO
    Write-Host ""
    Write-Host "[1/5] Creating seed ISO..." -ForegroundColor Yellow
    $hostname = "adp-$RuntimeName"
    $seedIso = New-SeedISO -RuntimeName $RuntimeName -Hostname $hostname `
        -Username $config.defaults.admin_user -SshPubKey $sshPubKey.Trim()
    Write-Host "  Seed ISO: $seedIso" -ForegroundColor Green

    $seedSourceDir = Join-Path $script:VmFactoryState.SeedDir $RuntimeName
    $profile = Get-OSProfile -OSName $rt.os
    $installIsoPath = $isoPath
    if ($profile.seedType -eq "cloud-init") {
        Write-Host "  Creating autoinstall ISO..." -ForegroundColor Yellow
        $installIsoPath = New-AutoinstallISO -RuntimeName $RuntimeName `
            -SourceIsoPath $isoPath -SeedSourceDir $seedSourceDir -BootArgs $profile.bootArgs
        Write-Host "  Install ISO: $installIsoPath" -ForegroundColor Green
    }

    # Generate VMX
    Write-Host "[2/5] Generating VMX configuration..." -ForegroundColor Yellow
    $vmxPath = New-VMX -RuntimeName $RuntimeName -RuntimeConfig @{
        cpu = $rt.cpu
        memory = $rt.memory
        disk = $rt.disk
        ssh_port = $rt.ssh_port
    } -VmPath $vmPath -UbuntuIsoPath $installIsoPath -SeedIsoPath $seedIso

    Write-Host "  VMX: $vmxPath" -ForegroundColor Green
    Write-Host "  CPU: $($rt.cpu) cores | RAM: $($rt.memory) MB | Disk: $($rt.disk) GB" -ForegroundColor DarkGray

    # Register VM with VMware
    Write-Host "[3/5] Registering VM with VMware..." -ForegroundColor Yellow
    $registerResult = Invoke-Vmrun -Arguments @("register", $vmxPath)
    if (-not $registerResult.Success) {
        Write-WarnLog -Message "VM register returned: $($registerResult.StdErr)" -Component "vm-factory"
        Write-Host "  VM may already be registered or will be registered on first start." -ForegroundColor Yellow
    } else {
        Write-Host "  VM registered." -ForegroundColor Green
    }

    if ($SkipProvision) {
        Write-Host ""
        Write-Host "Provisioning skipped. VM definition is ready but not started." -ForegroundColor Yellow
        Write-Host "  Start install later with: adp up $RuntimeName" -ForegroundColor DarkGray
        return $vmxPath
    }

    # Start VM for provisioning
    Write-Host "[4/5] Starting VM (autoinstall)..." -ForegroundColor Yellow
    Write-Host "  This will take 15-45 minutes for automated OS installation." -ForegroundColor Yellow
    Write-Host "  The VM will auto-install and reboot when ready." -ForegroundColor Yellow

    $startResult = Start-VM -VmxPath $vmxPath -Mode "nogui"
    if (-not $startResult.Success) {
        throw "Failed to start VM: $($startResult.StdErr)"
    }
    Write-Host "  VM started — autoinstall in progress..." -ForegroundColor Green

    # Wait for autoinstall to complete
    Write-Host "[5/5] Waiting for autoinstall to complete..." -ForegroundColor Yellow
    $ready = Wait-AutoinstallComplete -VmxPath $vmxPath -TimeoutMinutes 60

    if ($ready) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-Host "  Runtime '$RuntimeName' provisioned!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green

        try {
            $ip = Get-VMIP $vmxPath
            Write-Host "  IP: $ip" -ForegroundColor Cyan
            Write-Host "  SSH: ssh -i $sshKeyPath $($config.defaults.admin_user)@$ip" -ForegroundColor DarkGray
            $script:VmFactoryState."${RuntimeName}_ip" = $ip
        } catch {
            Write-Host "  IP will be available after first reboot." -ForegroundColor Yellow
        }
    } else {
        Write-WarnLog -Message "Autoinstall may still be in progress. Check VMware console." -Component "vm-factory"
    }

    return $vmxPath
}

function Wait-AutoinstallComplete {
    param(
        [string]$VmxPath,
        [int]$TimeoutMinutes = 45,
        [int]$CheckIntervalSeconds = 30
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $bootCount = 0

    Write-Host "  Waiting for autoinstall (timeout: ${TimeoutMinutes}min)..." -ForegroundColor DarkGray

    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds $CheckIntervalSeconds

        try {
            $ip = Get-VMIP $vmxPath
            if ($ip -and $ip -ne "0.0.0.0" -and $ip -notmatch "unknown") {
                Write-Host "  VM has IP: $ip — testing SSH..." -ForegroundColor DarkGray

                # Try SSH connection and require the provisioning marker from late-commands.
                $sshKeyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
                if (Test-Path $sshKeyPath) {
                    $sshTest = ssh -i $sshKeyPath -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o UserKnownHostsFile=NUL -o ConnectTimeout=5 -o BatchMode=yes adp@$ip "cat /home/adp/.adp-provisioned" 2>$null
                    if ($LASTEXITCODE -eq 0 -and $sshTest) {
                        Write-Host "  Provisioning confirmed!" -ForegroundColor Green
                        return $true
                    }
                }
            }
        } catch {
            # Still waiting
        }

        $elapsed = [math]::Round(((Get-Date) - $deadline).TotalMinutes + $TimeoutMinutes, 1)
        Write-Host "  Still waiting... (${elapsed}min elapsed)" -ForegroundColor DarkGray
    }

    return $false
}

function Test-AutoinstallReady {
    param(
        [string]$RuntimeName
    )

    $vmStore = $script:VmFactoryState.VmStore
    $vmName = "adp-$RuntimeName"
    $vmxPath = Join-Path $vmStore "$vmName\$vmName.vmx"

    if (-not (Test-Path $vmxPath)) {
        return $false
    }

    $status = Get-VMStatus $vmxPath
    if ($status -notmatch "running") {
        return $false
    }

    try {
        $ip = Get-VMIP $vmxPath
        if (-not $ip) { return $false }

        $sshKeyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
        ssh -i $sshKeyPath -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o UserKnownHostsFile=NUL -o ConnectTimeout=5 -o BatchMode=yes adp@$ip "test -f /home/adp/.adp-provisioned" 2>$null | Out-Null
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}
