# ADP-OS Sandbox Command
# One-command disposable VM: creates a temp VM, runs a command inside, destroys the VM.
# Guarantees cleanup regardless of command success/failure.

param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs,
    [string]$Distro = "ubuntu-26.04",
    [string]$IsoPath
)

$ErrorActionPreference = "Stop"

# --- Validate ---
$command = $CommandArgs -join ' '
if ([string]::IsNullOrWhiteSpace($command)) {
    $usageEn = "Usage: adpos sandbox <command...> [-Distro ubuntu-26.04] [-IsoPath <path>]"
    $usageZh = "用法: adpos sandbox <命令...> [-Distro ubuntu-26.04] [-IsoPath <路径>]"
    Write-ErrorLog -Message (Get-UIText -English $usageEn -Chinese $usageZh) -Component "cli.sandbox"
    Write-Host ""
    Write-UIHost -English "Examples:" -Chinese "示例:" -ForegroundColor Yellow
    Write-Host "  adpos sandbox echo hello"
    Write-Host "  adpos sandbox python3 -c 'print(1+1)'"
    Write-Host "  adpos sandbox pip install numpy && python3 -c 'import numpy; print(numpy.__version__)'"
    Write-Host "  adpos sandbox curl -s https://httpbin.org/ip"
    Write-Host ""
    exit 1
}

# --- Source dependencies ---
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\vm-factory.ps1")
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\os-profiles.ps1")

$config = Get-PlatformConfig
$vmStore = Resolve-Path "vm_store"
$isoCache = Resolve-Path "iso_cache"
$sshKeyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
$sandboxName = "sandbox"
$vmName = "adp-$sandboxName"

# Initialize VM provider (after vmStore is resolved)
. (Join-Path $script:ProjectRoot "core\provider\provider-discovery.ps1")
$providerType = Get-ConfiguredProviderType
Initialize-Provider -ProviderType $providerType -ProjectRoot $script:ProjectRoot -InitArgs @{VmStorePath = $vmStore} | Out-Null

Initialize-VmFactory -ProjectRoot (Get-ProjectRoot) -IsoCachePath $isoCache -VmStorePath $vmStore

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  ADP-OS Sandbox: disposable VM" -Chinese "  ADP-OS Sandbox: 一次性 VM" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  Command: $command" -Chinese "  命令:    $command" -ForegroundColor DarkGray
Write-UIHost -English "  VM:      $vmName" -Chinese "  VM:      $vmName" -ForegroundColor DarkGray
Write-UIHost -English "  Distro:  $Distro" -Chinese "  发行版:  $Distro" -ForegroundColor DarkGray
Write-UIHost -English "  CPU:     2 cores  |  RAM: 4096 MB  |  Disk: 40 GB" -Chinese "  CPU:     2 核  |  内存: 4096 MB  |  磁盘: 40 GB" -ForegroundColor DarkGray
Write-Host ""

$vmxPath = $null
$commandExitCode = 1

try {
    # --- Step 1: Destroy any existing sandbox VM (clean up from previous interrupted run) ---
    $statusResult = Get-VMStatus -Name $sandboxName
    if ($statusResult.Success -and $statusResult.Data -ne "not-created") {
        Write-UIHost -English "[prep] Cleaning up previous sandbox VM..." -Chinese "[准备] 清理之前的 sandbox VM..." -ForegroundColor Yellow
        Remove-VM -Name $sandboxName -DeleteFiles $true | Out-Null
        Write-UIHost -English "  Previous sandbox destroyed." -Chinese "  之前的 sandbox 已销毁。" -ForegroundColor Green
        Write-Host ""
    }

    # --- Step 2: Create sandbox VM ---
    Write-UIHost -English "[1/3] Creating disposable VM..." -Chinese "[1/3] 正在创建一次性 VM..." -ForegroundColor Yellow
    Write-UIHost -English "  This provisions a fresh Ubuntu VM from ISO. First run takes 15-45 min." -Chinese "  这将从 ISO 创建全新的 Ubuntu VM。首次运行需要 15-45 分钟。" -ForegroundColor DarkGray

    $vmxPath = New-RuntimeVM -RuntimeName $sandboxName -IsoPath $IsoPath -StartAfterCreate

    Write-Host ""
    Write-UIHost -English "  VM provisioned at: $vmxPath" -Chinese "  VM 已 provisioning 完成: $vmxPath" -ForegroundColor Green

    # --- Step 3: Get VM IP ---
    Write-Host ""
    Write-UIHost -English "[2/3] Connecting to VM..." -Chinese "[2/3] 正在连接到 VM..." -ForegroundColor Yellow

    $ip = $null
    $maxRetries = 10
    for ($i = 0; $i -lt $maxRetries; $i++) {
        try {
            # Use Provider for IP detection
            $detectedIp = $null
            try {
                $ipResult = Get-VMIP -Name $sandboxName
                if ($ipResult.Success) { $detectedIp = $ipResult.Data }
            } catch {}

            if ($detectedIp -and $detectedIp -ne "0.0.0.0" -and $detectedIp -notmatch "unknown") {
                # Test SSH connectivity
                $sshTest = ssh -i $sshKeyPath -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o UserKnownHostsFile=NUL -o ConnectTimeout=5 -o BatchMode=yes "adp@$detectedIp" "echo ok" 2>&1
                if ($LASTEXITCODE -eq 0) {
                    $ip = $detectedIp
                    break
                }
            }
        } catch {}

        if ($i -lt $maxRetries - 1) {
            Write-UIHost -English "  Waiting for SSH... ($($i + 1)/$maxRetries)" -Chinese "  等待 SSH... ($($i + 1)/$maxRetries)" -ForegroundColor DarkGray
            Start-Sleep -Seconds 5
        }
    }

    if (-not $ip) {
        # Try one more time with a longer delay
        Write-UIHost -English "  SSH not ready yet, waiting 15s..." -Chinese "  SSH 尚未就绪，等待 15 秒..." -ForegroundColor Yellow
        Start-Sleep -Seconds 15
        try {
            $ipResult = Get-VMIP -Name $sandboxName
            if ($ipResult.Success) { $detectedIp = $ipResult.Data }
        } catch {}
        if ($detectedIp) {
            $sshTest = ssh -i $sshKeyPath -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o UserKnownHostsFile=NUL -o ConnectTimeout=5 -o BatchMode=yes "adp@$detectedIp" "echo ok" 2>&1
            if ($LASTEXITCODE -eq 0) {
                $ip = $detectedIp
            }
        }
    }

    if (-not $ip) {
        Write-ErrorLog -Message (Get-UIText -English "Could not connect to sandbox VM via SSH. VM may need more time to boot." -Chinese "无法通过 SSH 连接到 sandbox VM。VM 可能需要更多时间启动。") -Component "cli.sandbox"
        Write-UIHost -English "  Try: adpos status sandbox" -Chinese "  尝试: adpos status sandbox" -ForegroundColor Yellow
        exit 1
    }

    Write-UIHost -English "  Connected: $ip" -Chinese "  已连接: $ip" -ForegroundColor Green

    # --- Step 4: Execute command ---
    Write-Host ""
    Write-UIHost -English "[3/3] Running command in sandbox..." -Chinese "[3/3] 在 sandbox 中运行命令..." -ForegroundColor Yellow
    Write-UIHost -English "  Command: $command" -Chinese "  命令:    $command" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "--- output start ---" -ForegroundColor DarkGray

    # Use bash -c so shell metacharacters (&&, |, >, ;) work correctly on the remote VM
    $escapedCommand = $command -replace "'", "'\''"
    $remoteCommand = "bash -c '$escapedCommand'"
    $sshOutput = & ssh -i $sshKeyPath -o StrictHostKeyChecking=no -o IdentitiesOnly=yes -o UserKnownHostsFile=NUL -o ConnectTimeout=10 -o ServerAliveInterval=30 "adp@$ip" $remoteCommand 2>&1
    $commandExitCode = $LASTEXITCODE
    $global:LASTEXITCODE = 0

    $sshOutput = ($sshOutput | Where-Object { $_ }) -join "`n"
    if ($sshOutput) {
        Write-Host $sshOutput
    }

    Write-Host "--- output end (exit: $commandExitCode) ---" -ForegroundColor DarkGray

    if ($commandExitCode -ne 0) {
        Write-UIHost -English "Command exited with code: $commandExitCode" -Chinese "命令退出码: $commandExitCode" -ForegroundColor Yellow
    } else {
        Write-UIHost -English "Command completed successfully." -Chinese "命令执行成功。" -ForegroundColor Green
    }
} catch {
    Write-ErrorLog -Message (Get-UIText -English "Sandbox error: $_" -Chinese "Sandbox 错误: $_") -Component "cli.sandbox"
    Write-UIHost -English "Sandbox failed: $_" -Chinese "Sandbox 失败: $_" -ForegroundColor Red
} finally {
    # --- Always destroy the VM ---
    Write-Host ""
    Write-UIHost -English "Cleaning up disposable VM..." -Chinese "正在清理一次性 VM..." -ForegroundColor Yellow

    $cleanupVmx = Join-Path $vmStore "$vmName\$vmName.vmx"
    if (Test-Path $cleanupVmx) {
        try {
            $stopResult = Stop-VM -VmxPath $cleanupVmx -Mode "soft"
            if (-not $stopResult.Success) {
                Stop-VM -VmxPath $cleanupVmx -Mode "hard" | Out-Null
            }
            Write-UIHost -English "  VM stopped." -Chinese "  VM 已停止。" -ForegroundColor DarkGray
        } catch {
            Write-UIHost -English "  VM stop had issues (may already be off)." -Chinese "  VM 停止过程出现问题（可能已关机）。" -ForegroundColor DarkGray
        }

        try {
            Remove-Item -LiteralPath (Split-Path $cleanupVmx -Parent) -Recurse -Force -ErrorAction SilentlyContinue
            Write-UIHost -English "  VM files removed." -Chinese "  VM 文件已删除。" -ForegroundColor DarkGray
        } catch {
            Write-UIHost -English "  VM file removal had issues." -Chinese "  VM 文件删除出现问题。" -ForegroundColor Yellow
        }
    }

    Write-UIHost -English "Disposable VM destroyed." -Chinese "一次性 VM 已销毁。" -ForegroundColor Green
    Write-UIHost -English "  Workspace data under workspace_root is not removed by sandbox." -Chinese "  workspace_root 下的工作区数据不会被 sandbox 删除。" -ForegroundColor DarkGray

    exit $commandExitCode
}
