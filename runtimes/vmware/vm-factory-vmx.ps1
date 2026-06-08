# ADP-OS VMware factory VMX helpers.

function New-VMX {
    param(
        [string]$RuntimeName,
        [hashtable]$RuntimeConfig,
        [string]$VmPath,
        [string]$UbuntuIsoPath,
        [string]$SeedIsoPath,
        [object]$Layout = $null
    )

    if (-not $Layout -and (Get-Command Get-ADPVMwareRuntimeLayout -ErrorAction SilentlyContinue)) {
        $Layout = Get-ADPVMwareRuntimeLayout -RuntimeName $RuntimeName -VmStorePath $script:VmFactoryState.VmStore -SeedRootPath $script:VmFactoryState.SeedDir -Namespace ""
    }

    $vmName = if ($Layout) { $Layout.VmName } else { "adp-$RuntimeName" }
    $targetVmPath = if ($Layout) { $Layout.VmPath } else { $VmPath }
    $vmxPath = if ($Layout) { $Layout.VmxPath } else { Join-Path $targetVmPath "$vmName.vmx" }
    $vmdkPath = if ($Layout) { $Layout.VmdkPath } else { Join-Path $targetVmPath "$vmName.vmdk" }
    $vmdkFileName = if ($Layout) { $Layout.VmdkFileName } else { "$vmName.vmdk" }

    if (-not (Test-Path $targetVmPath)) {
        New-Item -ItemType Directory -Path $targetVmPath -Force | Out-Null
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
scsi0:0.fileName = "$vmdkFileName"
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
