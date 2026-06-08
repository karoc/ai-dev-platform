# ADP-OS VM Factory (Windows/VMware)
# Phase 2: Programmatic VM creation with Ubuntu autoinstall via cloud-init
# Generates VMX files, seed ISOs, and orchestrates full provisioning

$script:VmFactoryState = @{}

. (Join-Path $PSScriptRoot "vm-factory-layout.ps1")
. (Join-Path $PSScriptRoot "vm-factory-iso.ps1")
. (Join-Path $PSScriptRoot "vm-factory-vmx.ps1")

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

function Test-RuntimeProvisioningPlan {
    param(
        [string]$RuntimeName,
        [string]$IsoPath
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
    $resolvedIsoPath = if ($IsoPath) { $IsoPath } else { Join-Path $script:VmFactoryState.IsoCache $isoName }
    Add-PlanCheck -Name "OS ISO" -Passed (Test-Path $resolvedIsoPath) -Detail $resolvedIsoPath

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
        [string]$SshPubKey,
        [object]$Layout = $null
    )

    $rt = Get-RuntimeConfig $RuntimeName
    $profile = Get-OSProfile -OSName $rt.os
    $seedType = $profile.seedType

    if (-not $Layout) {
        $Layout = Get-ADPVMwareRuntimeLayout -RuntimeName $RuntimeName -VmStorePath $script:VmFactoryState.VmStore -SeedRootPath $script:VmFactoryState.SeedDir -Namespace ""
    }
    if ([string]::IsNullOrWhiteSpace($Hostname)) {
        $Hostname = $Layout.Hostname
    }

    $seedDir = $Layout.SeedSourceDir
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
instance-id: $($Layout.CloudInitInstanceId)
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

    $seedIso = $Layout.SeedIsoPath
    $result = New-ISO -SourceDir $seedDir -OutputPath $seedIso

    if (-not $result) {
        throw "Failed to create seed ISO for $RuntimeName"
    }

    Write-InfoLog -Message "Seed ISO created ($seedType): $seedIso" -Component "vm-factory"
    return $seedIso
}

function New-RuntimeVM {
    param(
        [string]$RuntimeName,
        [string]$IsoPath,
        [object]$Layout,
        [switch]$SkipProvision,
        [switch]$StartAfterCreate
    )

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-UIHost -English "  Creating VM for: $RuntimeName" -Chinese "  正在创建 VM: $RuntimeName" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    $rt = Get-RuntimeConfig $RuntimeName
    $config = Get-PlatformConfig
    $layout = if ($Layout) {
        $Layout
    } else {
        Get-ADPVMwareRuntimeLayout -RuntimeName $RuntimeName -VmStorePath $script:VmFactoryState.VmStore -SeedRootPath $script:VmFactoryState.SeedDir -Namespace ""
    }
    if (-not $layout.VmPath -or -not $layout.VmxPath -or -not $layout.SeedSourceDir) {
        throw "New-RuntimeVM: invalid VMware runtime layout for '$RuntimeName'"
    }
    $vmName = $layout.VmName
    $vmPath = $layout.VmPath

    # Check if VM already exists
    $vmxPath = $layout.VmxPath
    if (Test-Path $vmxPath) {
        Write-UIHost -English "VM already exists at: $vmxPath" -Chinese "VM 已存在: $vmxPath" -ForegroundColor Yellow
        $status = Get-VMStatus $vmxPath
        Write-UIHost -English "  Status: $status" -Chinese "  状态: $status" -ForegroundColor DarkGray
        if ($StartAfterCreate -and $status -notmatch "running") {
            Write-UIHost -English "Starting existing VM..." -Chinese "正在启动已有 VM..." -ForegroundColor Yellow
            Start-VM -VmxPath $vmxPath -Mode "nogui" | Out-Null
        }
        return $vmxPath
    }

    # Check OS ISO
    $isoCache = $script:VmFactoryState.IsoCache
    $isoName = if ($config.defaults.iso_path) { $config.defaults.iso_path } else { $config.defaults.ubuntu_iso }
    $resolvedIsoPath = if ($IsoPath) { $IsoPath } else { Join-Path $isoCache $isoName }
    if (-not (Test-Path $resolvedIsoPath)) {
        throw (Get-UIText -English "OS ISO not found: $resolvedIsoPath. Place the ISO there or use -IsoPath parameter." -Chinese "未找到 OS ISO: $resolvedIsoPath。请将 ISO 放到该位置，或使用 -IsoPath 参数。")
    }

    Write-Host "OS ISO: $resolvedIsoPath" -ForegroundColor Green

    # Initialize SSH keys
    . (Join-Path $script:VmFactoryState.ProjectRoot "adapters\windows\ssh\ssh.ps1")
    $sshKeyPath = Initialize-SSH
    $sshPubKey = Get-SSHPubKey
    Write-Host "SSH key: $sshKeyPath" -ForegroundColor Green

    # Create seed ISO
    Write-Host ""
    Write-UIHost -English "[1/5] Creating seed ISO..." -Chinese "[1/5] 正在创建 seed ISO..." -ForegroundColor Yellow
    $hostname = $layout.Hostname
    $seedIso = New-SeedISO -RuntimeName $RuntimeName -Hostname $hostname `
        -Username $config.defaults.admin_user -SshPubKey $sshPubKey.Trim() -Layout $layout
    Write-Host "  Seed ISO: $seedIso" -ForegroundColor Green

    $seedSourceDir = $layout.SeedSourceDir
    $profile = Get-OSProfile -OSName $rt.os
    $installIsoPath = $resolvedIsoPath
    if ($profile.seedType -eq "cloud-init") {
        Write-UIHost -English "  Creating autoinstall ISO..." -Chinese "  正在创建 autoinstall ISO..." -ForegroundColor Yellow
        $installIsoPath = New-AutoinstallISO -RuntimeName $RuntimeName `
            -SourceIsoPath $resolvedIsoPath -SeedSourceDir $seedSourceDir -BootArgs $profile.bootArgs -Layout $layout
        Write-Host "  Install ISO: $installIsoPath" -ForegroundColor Green
    }

    # Generate VMX
    Write-UIHost -English "[2/5] Generating VMX configuration..." -Chinese "[2/5] 正在生成 VMX 配置..." -ForegroundColor Yellow
    $vmxPath = New-VMX -RuntimeName $RuntimeName -RuntimeConfig @{
        cpu = $rt.cpu
        memory = $rt.memory
        disk = $rt.disk
        ssh_port = $rt.ssh_port
    } -VmPath $vmPath -UbuntuIsoPath $installIsoPath -SeedIsoPath $seedIso -Layout $layout

    Write-Host "  VMX: $vmxPath" -ForegroundColor Green
    Write-Host "  CPU: $($rt.cpu) cores | RAM: $($rt.memory) MB | Disk: $($rt.disk) GB" -ForegroundColor DarkGray

    # Register VM with VMware
    Write-UIHost -English "[3/5] Registering VM with VMware..." -Chinese "[3/5] 正在向 VMware 注册 VM..." -ForegroundColor Yellow
    $registerResult = Invoke-Vmrun -Arguments @("register", $vmxPath)
    if (-not $registerResult.Success) {
        Write-WarnLog -Message "VM register returned: $($registerResult.StdErr)" -Component "vm-factory"
        Write-UIHost -English "  VM may already be registered or will be registered on first start." -Chinese "  VM 可能已经注册，或会在首次启动时注册。" -ForegroundColor Yellow
    } else {
        Write-UIHost -English "  VM registered." -Chinese "  VM 已注册。" -ForegroundColor Green
    }

    if ($SkipProvision) {
        Write-Host ""
        Write-UIHost -English "Provisioning skipped. VM definition is ready but not started." -Chinese "已跳过 provisioning。VM 定义已就绪，但尚未启动。" -ForegroundColor Yellow
        Write-UIHost -English "  Start install later with: adpos up $RuntimeName" -Chinese "  稍后可运行此命令开始安装: adpos up $RuntimeName" -ForegroundColor DarkGray
        return $vmxPath
    }

    # Start VM for provisioning
    Write-UIHost -English "[4/5] Starting VM (Ubuntu autoinstall)..." -Chinese "[4/5] 正在启动 VM（Ubuntu autoinstall）..." -ForegroundColor Yellow
    Write-UIHost -English "  This starts a real guest OS installation. The next step is an install monitor, not a CLI hang." -Chinese "  这会启动真实的 guest OS 安装。下一步是安装监视器，不是 CLI 卡住。" -ForegroundColor Yellow
    Write-UIHost -English "  Typical duration: 15-45 minutes. Keep this window open until ready or timeout." -Chinese "  通常需要 15-45 分钟。请保持此窗口打开，直到就绪或超时。" -ForegroundColor DarkGray
    Write-UIHost -English "  No manual SSH action is needed while install-monitor heartbeats say INSTALLING." -Chinese "  只要 install-monitor 心跳显示 INSTALLING，就不需要手动 SSH。" -ForegroundColor DarkGray
    Write-UIHost -English "  The VM will install Ubuntu, reboot, accept the ADP SSH key, then write a provision marker." -Chinese "  VM 会安装 Ubuntu、重启、接受 ADP SSH key，然后写入 provision marker。" -ForegroundColor DarkGray

    $startResult = Start-VM -VmxPath $vmxPath -Mode "nogui"
    if (-not $startResult.Success) {
        throw "Failed to start VM: $($startResult.StdErr)"
    }
    Write-UIHost -English "  VM started; installer is running in VMware." -Chinese "  VM 已启动；安装器正在 VMware 中运行。" -ForegroundColor Green

    # Wait for autoinstall to complete
    Write-UIHost -English "[5/5] Installing Ubuntu inside VM (watched wait, not stuck; repeated signals can be normal)..." -Chinese "[5/5] 正在 VM 内安装 Ubuntu（受监控等待，不是卡住；重复信号可能正常）..." -ForegroundColor Yellow
    $ready = Wait-AutoinstallComplete -VmxPath $vmxPath -RuntimeName $RuntimeName -TimeoutMinutes 60

    if ($ready) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Green
        Write-UIHost -English "  Runtime '$RuntimeName' provisioned!" -Chinese "  运行时 '$RuntimeName' 已完成 provisioning!" -ForegroundColor Green
        Write-Host "========================================" -ForegroundColor Green

        $configuredIp = Get-RuntimeStaticIP $RuntimeName
        $detectedIp = $null
        try {
            $detectedIp = Get-VMIP $vmxPath
        } catch {}

        $ip = if ($configuredIp) { $configuredIp } else { $detectedIp }
        if ($ip) {
            Write-Host "  IP: $ip" -ForegroundColor Cyan
            if ($configuredIp -and $detectedIp -and $configuredIp -ne $detectedIp) {
                Write-UIHost -English "  VMware detected IP: $detectedIp" -Chinese "  VMware 探测 IP: $detectedIp" -ForegroundColor DarkGray
                Write-UIHost -English "  Using configured static IP from topology/local config." -Chinese "  将使用 topology/local config 中配置的 static IP。" -ForegroundColor DarkGray
            }
            Write-Host "  SSH: ssh -i $sshKeyPath $($config.defaults.admin_user)@$ip" -ForegroundColor DarkGray
            Write-Host "  Status: adpos status $RuntimeName" -ForegroundColor DarkGray
            Write-Host "  Sync:   adpos sync start $RuntimeName" -ForegroundColor DarkGray
            $script:VmFactoryState."$($layout.RuntimeResourceName)_ip" = $ip
        } else {
            Write-UIHost -English "  IP will be available after first reboot." -Chinese "  IP 将在首次重启后可用。" -ForegroundColor Yellow
            Write-UIHost -English "  Check: adpos status $RuntimeName" -Chinese "  检查: adpos status $RuntimeName" -ForegroundColor DarkGray
        }
    } else {
        Write-WarnLog -Message (Get-UIText -English "Autoinstall may still be in progress. Check VMware console." -Chinese "Autoinstall 可能仍在进行。请检查 VMware console。") -Component "vm-factory"
    }

    return $vmxPath
}

function Wait-AutoinstallComplete {
    param(
        [string]$VmxPath,
        [string]$RuntimeName,
        [int]$TimeoutMinutes = 45,
        [int]$CheckIntervalSeconds = 30,
        [int]$AutoinstallCircuitBreakerMinutes = 20
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $startedAt = Get-Date
    $lastDetail = ""
    $sameDetailCount = 0
    $sshKeyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
    $progressId = 135

    # Circuit breaker: stop retrying if the same error category repeats for too long
    $cbIterations = [Math]::Max(1, [Math]::Floor(($AutoinstallCircuitBreakerMinutes * 60) / $CheckIntervalSeconds))
    $autoinstallCb = New-CircuitBreaker -MaxConsecutiveErrors $cbIterations -Name "autoinstall"

    Write-UIHost -English "  Install monitor active: INSTALLING Ubuntu in the VM; ADP is watching readiness, not stuck (timeout: ${TimeoutMinutes}min)." -Chinese "  安装监视器已启动：正在 VM 内安装 Ubuntu；ADP 正在监控 readiness，不是卡住（超时: ${TimeoutMinutes}min）。" -ForegroundColor Yellow
    Write-UIHost -English "  What you should see: an install-monitor heartbeat every ${CheckIntervalSeconds}s until the VM is provisioned." -Chinese "  你应该会看到：每 ${CheckIntervalSeconds}s 输出一次 install-monitor 心跳，直到 VM provisioning 完成。" -ForegroundColor DarkGray
    Write-UIHost -English "  Progress model: indeterminate OS install; VMware does not expose a reliable Ubuntu install percentage, so ADP reports real readiness signals." -Chinese "  进度模型：不确定时长的 OS 安装；VMware 不提供可靠的 Ubuntu 安装百分比，因此 ADP 报告真实就绪信号（readiness signals），而不是伪造百分比。" -ForegroundColor DarkGray
    Write-UIHost -English "  Progress indicator: PowerShell shows an indeterminate activity indicator while copyable log heartbeats continue below." -Chinese "  进度指示：PowerShell 会显示不确定进度的活动指示；下方仍保留可复制的日志心跳。" -ForegroundColor DarkGray
    Write-UIHost -English "  Watch path: installer boot -> OS install -> reboot -> SSH auth-pending -> provision marker -> bootstrap." -Chinese "  监控路径: installer boot -> OS install -> reboot -> SSH auth-pending -> provision marker -> bootstrap。" -ForegroundColor DarkGray
    Write-UIHost -English "  Readiness signals checked every ${CheckIntervalSeconds}s: configured/static IP, VMware-reported IP, SSH key auth, /home/adp/.adp-provisioned." -Chinese "  每 ${CheckIntervalSeconds}s 检查就绪信号（readiness signals）：配置/静态 IP、VMware 探测 IP、SSH key auth、/home/adp/.adp-provisioned。" -ForegroundColor DarkGray
    Write-UIHost -English "  Important: IP and SSH probe failures are readiness signals during install; they are not the primary status while the headline says INSTALLING." -Chinese "  重要：安装期间的 IP 和 SSH probe failure 只是就绪信号（readiness signals）；只要标题显示 INSTALLING，它们不是主要状态，也不代表卡住。" -ForegroundColor DarkGray
    Write-UIHost -English "  Normal during install: the same signal can repeat for many checks while Ubuntu installs, reboots, or prepares the adp user." -Chinese "  安装期间的正常现象：Ubuntu 安装、重启或准备 adp 用户时，同一个信号可能连续重复多次。" -ForegroundColor DarkGray
    Write-UIHost -English "  User action: keep this command running. Do not SSH yet; inspect VMware console only if one signal repeats for about 20min or timeout is reached." -Chinese "  用户操作：保持此命令运行。暂时不要手动 SSH；只有同一信号重复约 20 分钟或达到 timeout 时，再检查 VMware console。" -ForegroundColor DarkGray
    Write-UIHost -English "  First readiness check in ${CheckIntervalSeconds}s..." -Chinese "  第一次 readiness 检查将在 ${CheckIntervalSeconds}s 后进行..." -ForegroundColor DarkGray

    while ((Get-Date) -lt $deadline) {
        $elapsedBeforeSleep = [math]::Round(((Get-Date) - $startedAt).TotalMinutes, 1)
        $remainingBeforeSleep = [math]::Max(0, [math]::Round(($deadline - (Get-Date)).TotalMinutes, 1))
        Write-Progress `
            -Id $progressId `
            -Activity (Get-UIText -English "Installing Ubuntu in ADP VM" -Chinese "正在 ADP VM 中安装 Ubuntu") `
            -Status (Get-UIText -English "Indeterminate install; watching readiness signals. Elapsed ${elapsedBeforeSleep}min, remaining timeout ${remainingBeforeSleep}min." -Chinese "不确定进度安装；正在监控就绪信号（readiness signals）。已用 ${elapsedBeforeSleep}min，剩余 timeout ${remainingBeforeSleep}min。") `
            -CurrentOperation (Get-UIText -English "Next readiness check in ${CheckIntervalSeconds}s; keep this command running." -Chinese "下一次就绪检查将在 ${CheckIntervalSeconds}s 后进行；请保持此命令运行。") `
            -SecondsRemaining -1

        Start-Sleep -Seconds $CheckIntervalSeconds

        $configuredIp = if ($RuntimeName) { Get-RuntimeStaticIP $RuntimeName } else { $null }
        $detectedIp = $null
        $candidateIps = @()
        $probeDetails = [System.Collections.Generic.List[string]]::new()

        try {
            try {
                $detectedIp = Get-VMIPQuick -VmxPath $VmxPath -TimeoutSeconds 5
            } catch {}

            $candidateIps = @($configuredIp, $detectedIp) | Where-Object { $_ -and $_ -ne "0.0.0.0" -and $_ -notmatch "unknown" } | Select-Object -Unique
            foreach ($ip in $candidateIps) {
                $label = if ($configuredIp -and $ip -eq $configuredIp) {
                    Get-UIText -English "configured" -Chinese "配置 IP"
                } else {
                    Get-UIText -English "VMware-detected" -Chinese "VMware 探测 IP"
                }

                if (Test-Path $sshKeyPath) {
                    $sshOutput = ssh -i $sshKeyPath -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o UserKnownHostsFile=NUL -o ConnectTimeout=5 -o BatchMode=yes adp@$ip "cat /home/adp/.adp-provisioned" 2>&1
                    $sshExit = $LASTEXITCODE
                    $sshTest = ($sshOutput | Where-Object { $_ }) -join "`n"
                    if ($sshExit -eq 0 -and $sshTest) {
                        Write-Progress -Id $progressId -Activity (Get-UIText -English "Installing Ubuntu in ADP VM" -Chinese "正在 ADP VM 中安装 Ubuntu") -Completed
                        Write-UIHost -English "  Ready: provision marker confirmed at $ip." -Chinese "  已就绪: 已在 $ip 确认 provision marker。" -ForegroundColor Green
                        return $true
                    }

                    if ($sshExit -eq 255 -and $sshTest -match "Permission denied") {
                        $probeDetails.Add((Get-UIText -English "$label ${ip}: auth-pending; SSH is up but installed-system user/key or provision marker is not ready" -Chinese "$label ${ip}: auth-pending；SSH 已打开，但安装后系统的用户/key 或 provision marker 尚未 ready")) | Out-Null
                    } elseif ($sshExit -eq 255) {
                        $probeDetails.Add((Get-UIText -English "$label ${ip}: SSH not ready yet; installer may still be booting, installing, or rebooting" -Chinese "$label ${ip}: SSH 尚未 ready；installer 可能仍在 boot、install 或 reboot")) | Out-Null
                    } else {
                        $probeDetails.Add((Get-UIText -English "$label ${ip}: provision marker not ready yet" -Chinese "$label ${ip}: provision marker 尚未 ready")) | Out-Null
                    }
                } else {
                    $probeDetails.Add((Get-UIText -English "$label ${ip}: SSH key missing at $sshKeyPath" -Chinese "$label ${ip}: SSH key 缺失: $sshKeyPath")) | Out-Null
                }
            }
        } catch {
            $probeDetails.Add((Get-UIText -English "guest status probe unavailable while installer is running" -Chinese "installer 运行期间 guest status probe 暂不可用")) | Out-Null
        }

        if ($candidateIps.Count -eq 0) {
            $probeDetails.Add((Get-UIText -English "no guest IP observed yet; installer may still be booting, installing, or rebooting" -Chinese "尚未观察到 guest IP；installer 可能仍在 boot、install 或 reboot")) | Out-Null
        }

        $elapsed = [math]::Round(((Get-Date) - $startedAt).TotalMinutes, 1)
        $remaining = [math]::Max(0, [math]::Round(($deadline - (Get-Date)).TotalMinutes, 1))
        $nextCheckSeconds = $CheckIntervalSeconds
        $detail = (@($probeDetails) | Select-Object -Unique) -join "; "
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = Get-UIText -English "installer is still running" -Chinese "installer 仍在运行"
        }

        # Circuit breaker: categorize the dominant error and check if same error has repeated too many times
        $cbErrorKey = ""
        if ($candidateIps.Count -eq 0) { $cbErrorKey = "no-guest-ip" }
        elseif ($probeDetails -match "auth-pending") { $cbErrorKey = "auth-pending" }
        elseif ($probeDetails -match "SSH not ready") { $cbErrorKey = "ssh-not-ready" }
        elseif ($probeDetails -match "SSH key missing") { $cbErrorKey = "ssh-key-missing" }
        elseif ($probeDetails -match "provision marker not ready") { $cbErrorKey = "provision-not-ready" }
        elseif ($probeDetails -match "probe unavailable") { $cbErrorKey = "probe-unavailable" }
        else { $cbErrorKey = "installer-running" }

        $cbContinue = Test-CircuitBreaker -CircuitBreaker $autoinstallCb -ErrorKey $cbErrorKey
        if (-not $cbContinue) {
            Write-Progress -Id $progressId -Activity (Get-UIText -English "Installing Ubuntu in ADP VM" -Chinese "正在 ADP VM 中安装 Ubuntu") -Completed
            $cbMinutes = [math]::Round(($autoinstallCb.ConsecutiveCount * $CheckIntervalSeconds) / 60, 1)
            Write-WarnLog -Message (Get-UIText -English "Circuit breaker opened: '$cbErrorKey' repeated $($autoinstallCb.ConsecutiveCount) times (~${cbMinutes}min)" -Chinese "熔断器断开: '$cbErrorKey' 连续重复 $($autoinstallCb.ConsecutiveCount) 次 (~${cbMinutes}min)") -Component "vm-factory"
            Write-UIHost -English "  Autoinstall circuit breaker opened: same error '$cbErrorKey' repeated for ~${cbMinutes}min (threshold: ${AutoinstallCircuitBreakerMinutes}min)." -Chinese "  自动安装熔断器已断开: 同一错误 '$cbErrorKey' 连续重复约 ${cbMinutes}min (阈值: ${AutoinstallCircuitBreakerMinutes}min)。" -ForegroundColor Yellow
            Write-UIHost -English "  Stopping retry to prevent infinite loop. The VM may have a persistent issue." -Chinese "  停止重试以防止无限循环。VM 可能存在持续性故障。" -ForegroundColor Yellow
            Write-UIHost -English "  Next: check VMware console for installer errors, then investigate with: adpos status $RuntimeName" -Chinese "  下一步: 检查 VMware console 中的 installer 错误，然后通过 adpos status $RuntimeName 排查。" -ForegroundColor DarkGray
            Write-UIHost -English "  To retry, re-run: adpos up $RuntimeName" -Chinese "  如需重试，请重新运行: adpos up $RuntimeName" -ForegroundColor DarkGray
            return $false
        }

        Write-Progress `
            -Id $progressId `
            -Activity (Get-UIText -English "Installing Ubuntu in ADP VM" -Chinese "正在 ADP VM 中安装 Ubuntu") `
            -Status (Get-UIText -English "Watching readiness signals. Elapsed ${elapsed}min, remaining timeout ${remaining}min." -Chinese "正在监控就绪信号（readiness signals）。已用 ${elapsed}min，剩余 timeout ${remaining}min。") `
            -CurrentOperation $detail `
            -SecondsRemaining -1

        if ($detail -ne $lastDetail) {
            $sameDetailCount = 0
            Write-UIHost -English "  [install monitor] INSTALLING Ubuntu in VM - watched wait, not stuck" -Chinese "  [安装监视器] 正在 VM 中安装 Ubuntu - 受监控等待，不是卡住" -ForegroundColor Yellow
            Write-Host "    status: state=installing activity=installing-ubuntu status=watching current-op=readiness-check wait-mode=watched progress=indeterminate user-action=keep-open diagnostics=vmware-console-after-20min phase=ubuntu-autoinstall" -ForegroundColor DarkGray
            Write-UIHost -English "    time: expected=15-45min timeout=${TimeoutMinutes}min elapsed=${elapsed}min remaining=${remaining}min next-check=${nextCheckSeconds}s" -Chinese "    时间: expected=15-45min timeout=${TimeoutMinutes}min elapsed=${elapsed}min remaining=${remaining}min next-check=${nextCheckSeconds}s" -ForegroundColor DarkGray
            Write-UIHost -English "    meaning: Ubuntu is still installing, rebooting, or preparing the installed-system user; ADP is watching for the provision marker." -Chinese "    含义: Ubuntu 仍在安装、重启或准备 installed-system user；ADP 正在等待 provision marker。" -ForegroundColor DarkGray
            Write-UIHost -English "    readiness signals: $detail" -Chinese "    就绪信号(readiness signals): $detail" -ForegroundColor DarkGray
            Write-UIHost -English "    next: ADP will recheck readiness after ${nextCheckSeconds}s and start bootstrap automatically after the provision marker is confirmed." -Chinese "    下一步: ADP 会在 ${nextCheckSeconds}s 后重新检查就绪状态；确认 provision marker 后会自动开始 bootstrap。" -ForegroundColor DarkGray
            Write-UIHost -English "    action: keep this command running; no manual SSH is needed while the status is INSTALLING." -Chinese "    操作: 保持此命令运行；只要状态仍是 INSTALLING，就不需要手动 SSH。" -ForegroundColor DarkGray
            $lastDetail = $detail
        } else {
            $sameDetailCount += 1
            $sameMinutes = [math]::Round(($sameDetailCount * $CheckIntervalSeconds) / 60, 1)
            Write-UIHost -English "  [install monitor] INSTALLING Ubuntu in VM - heartbeat active, repeated signal is normal" -Chinese "  [安装监视器] 正在 VM 中安装 Ubuntu - 心跳正常，重复信号可能是正常现象" -ForegroundColor Yellow
            Write-Host "    status: state=installing activity=installing-ubuntu status=watching current-op=readiness-check wait-mode=watched progress=indeterminate user-action=keep-open diagnostics=vmware-console-after-20min phase=ubuntu-autoinstall normal=yes unchanged-for=${sameMinutes}min" -ForegroundColor DarkGray
            Write-UIHost -English "    time: expected=15-45min timeout=${TimeoutMinutes}min elapsed=${elapsed}min remaining=${remaining}min next-check=${nextCheckSeconds}s" -Chinese "    时间: expected=15-45min timeout=${TimeoutMinutes}min elapsed=${elapsed}min remaining=${remaining}min next-check=${nextCheckSeconds}s" -ForegroundColor DarkGray
            Write-UIHost -English "    meaning: unchanged readiness signals are normal while Ubuntu installs, reboots, or prepares the adp user; this heartbeat means ADP is still watching the install." -Chinese "    含义: Ubuntu 安装、重启或准备 adp 用户时，就绪信号（readiness signals）不变化可能是正常现象；这个心跳表示 ADP 仍在监控安装。" -ForegroundColor DarkGray
            Write-UIHost -English "    readiness signals: $detail" -Chinese "    就绪信号(readiness signals): $detail" -ForegroundColor DarkGray
            Write-UIHost -English "    next: ADP will recheck readiness after ${nextCheckSeconds}s and start bootstrap automatically after the provision marker is confirmed." -Chinese "    下一步: ADP 会在 ${nextCheckSeconds}s 后重新检查就绪状态；确认 provision marker 后会自动开始 bootstrap。" -ForegroundColor DarkGray
            if ($sameMinutes -ge 20) {
                Write-UIHost -English "    action: same signal has repeated for about ${sameMinutes}min; keep the command running, and inspect the VMware console if you need live installer detail." -Chinese "    操作: 同一信号已重复约 ${sameMinutes}min；保持命令运行，如需查看安装器实时细节，可检查 VMware console。" -ForegroundColor Yellow
            } else {
                Write-UIHost -English "    action: keep waiting; repeated signals are expected during this watched OS installation stage, and no manual SSH is needed." -Chinese "    操作: 继续等待；在受监控的 OS 安装阶段，重复信号是预期内现象，不需要手动 SSH。" -ForegroundColor DarkGray
            }
        }
    }

    Write-Progress -Id $progressId -Activity (Get-UIText -English "Installing Ubuntu in ADP VM" -Chinese "正在 ADP VM 中安装 Ubuntu") -Completed
    Write-UIHost -English "  Autoinstall confirmation timed out after ${TimeoutMinutes}min." -Chinese "  Autoinstall 确认在 ${TimeoutMinutes}min 后超时。" -ForegroundColor Yellow
    Write-UIHost -English "  The VM may still be installing, but ADP did not confirm the provision marker in time." -Chinese "  VM 可能仍在安装，但 ADP 没有在超时前确认 provision marker。" -ForegroundColor DarkGray
    Write-UIHost -English "  Next: check the VMware console for installer errors, then run: adpos status $RuntimeName" -Chinese "  下一步: 检查 VMware console 是否有安装错误，然后运行: adpos status $RuntimeName" -ForegroundColor DarkGray
    return $false
}

function Test-AutoinstallReady {
    param(
        [string]$RuntimeName,
        [string]$VmxPath
    )

    $resolvedVmxPath = $VmxPath
    if (-not $resolvedVmxPath) {
        $layout = Get-ADPVMwareRuntimeLayout -RuntimeName $RuntimeName -VmStorePath $script:VmFactoryState.VmStore -SeedRootPath $script:VmFactoryState.SeedDir -Namespace ""
        $resolvedVmxPath = $layout.VmxPath
    }

    if (-not (Test-Path $resolvedVmxPath)) {
        return $false
    }

    $status = Get-VMStatus $resolvedVmxPath
    if ($status -notmatch "running") {
        return $false
    }

    try {
        $configuredIp = Get-RuntimeStaticIP $RuntimeName
        $detectedIp = $null
        try {
            $detectedIp = Get-VMIP $resolvedVmxPath
        } catch {}

        $candidateIps = @($configuredIp, $detectedIp) | Where-Object { $_ -and $_ -ne "0.0.0.0" -and $_ -notmatch "unknown" } | Select-Object -Unique
        if ($candidateIps.Count -eq 0) { return $false }

        $sshKeyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
        foreach ($ip in $candidateIps) {
            ssh -i $sshKeyPath -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o UserKnownHostsFile=NUL -o ConnectTimeout=5 -o BatchMode=yes adp@$ip "test -f /home/adp/.adp-provisioned" 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) {
                return $true
            }
        }

        return $false
    } catch {
        return $false
    }
}
