Assert-Command `
    -Name "help" `
    -Arguments @("help") `
    -ExitCode 0 `
    -Patterns @("ADP-OS CLI", "adpos up <runtime>", "adpos capabilities")

Assert-Command `
    -Name "help zh-CN" `
    -Arguments @("help") `
    -ExitCode 0 `
    -Patterns @("ADP-OS CLI", "命令:", "初始化平台", "显示运行时状态", "adpos capabilities.*显示已支持和计划中的运行时能力") `
    -Environment @{ ADP_LANG = "zh-CN" }

Assert-Command `
    -Name "capabilities" `
    -Arguments @("capabilities") `
    -ExitCode 0 `
    -Patterns @("ADP-OS Capabilities", "Capabilities only: no VMs", "Runtime profiles:\s+frontend, backend, agent, sandbox", "\[supported\] vmware-workstation", "host: Windows", "\[planned\] hyper-v", "\[planned\] kvm-libvirt", "\[planned\] macos-vm", "\[exploratory\] container-backed", "Docker and dev containers are runtime-internal project tools today", "Docs: docs/capabilities.md")

Assert-Command `
    -Name "unknown command" `
    -Arguments @("not-a-command") `
    -ExitCode 1 `
    -Patterns @("Unknown command: not-a-command", "Valid commands:")

Assert-Command `
    -Name "unknown command zh-CN" `
    -Arguments @("not-a-command") `
    -ExitCode 1 `
    -Patterns @("未知命令: not-a-command", "可用命令:") `
    -Environment @{ ADP_LANG = "zh-CN" }

Assert-Command `
    -Name "up unknown runtime" `
    -Arguments @("up", "not-a-runtime", "-Plan") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent, sandbox")

if (Get-Command vmrun.exe -ErrorAction SilentlyContinue) {
    Assert-Command `
        -Name "up plan" `
        -Arguments @("up", "agent", "-Plan", "-IsoPath", "D:\Share\ubuntu-26.04-live-server-amd64.iso") `
        -ExitCode 0 `
        -Patterns @("Plan only: no VM will be created", "Runtime:\s+agent", "ISO:\s+D:\\Share\\ubuntu-26\.04-live-server-amd64\.iso")

    Assert-Command `
        -Name "up plan zh-CN" `
        -Arguments @("up", "agent", "-Plan", "-IsoPath", "D:\Share\ubuntu-26.04-live-server-amd64.iso") `
        -ExitCode 0 `
        -Patterns @("ADP-OS: 正在启动 agent", "仅预览：不会创建、启动、provision 或 bootstrap 任何 VM", "运行时:\s+agent", "工作区:") `
        -Environment @{ ADP_LANG = "zh-CN" }
} else {
    Write-Host "SKIP: up plan tests (vmrun.exe not found — CI without VMware)"
}

Assert-Command `
    -Name "status all runtimes" `
    -Arguments @("status") `
    -ExitCode 0 `
    -Patterns @("ADP-OS Status", "Status only: no VMs", "Local config:", "Network:\s+192\.168\.242\.0/24", "frontend", "configured IP:\s+192\.168\.242\.131", "connect:\s+ssh -i .*adp@192\.168\.242\.131", "backend", "agent")

Assert-Command `
    -Name "status all runtimes zh-CN" `
    -Arguments @("status") `
    -ExitCode 0 `
    -Patterns @("ADP-OS 状态", "仅查看状态：不会修改 VM", "本机配置:", "网络:\s+192\.168\.242\.0/24", "frontend", "配置 IP:\s+192\.168\.242\.131", "连接:\s+ssh -i .*adp@192\.168\.242\.131", "backend", "agent") `
    -Environment @{ ADP_LANG = "zh-CN" }

Assert-Command `
    -Name "status single runtime" `
    -Arguments @("status", "agent") `
    -ExitCode 0 `
    -Patterns @("ADP-OS Status", "agent", "configured IP:\s+192\.168\.242\.135", "alias:\s+ssh adp-os-adp-agent")

Assert-Command `
    -Name "status unknown runtime" `
    -Arguments @("status", "not-a-runtime") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent, sandbox")

Assert-Command `
    -Name "sync unknown subcommand" `
    -Arguments @("sync", "nope") `
    -ExitCode 1 `
    -Patterns @("Unknown sync command: nope", "status, start, stop, list")

Assert-Command `
    -Name "sync unknown runtime" `
    -Arguments @("sync", "stop", "not-a-runtime") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent, sandbox")

Assert-Command `
    -Name "doctor plan without fix mutagen" `
    -Arguments @("doctor", "-Plan") `
    -ExitCode 1 `
    -Patterns @("-Plan is only supported with -FixMutagen")

Assert-Command `
    -Name "doctor fix mutagen plan" `
    -Arguments @("doctor", "-FixMutagen", "-Plan") `
    -ExitCode 0 `
    -Patterns @("Mutagen remediation:", "Plan only: no files will be downloaded", "mutagen_windows_amd64_v0\.18\.1\.zip", "\.tools\\mutagen\\mutagen\.exe", "Offline archive:", "SHA256:", "Timeout:\s+connection=30s hard=300s", "platform\.tools\.mutagen\.download_url", "To install: adpos doctor -FixMutagen")

Assert-Command `
    -Name "doctor fix mutagen plan zh-CN" `
    -Arguments @("doctor", "-FixMutagen", "-Plan") `
    -ExitCode 0 `
    -Patterns @("ADP-OS Doctor — 系统诊断", "Mutagen 修复:", "仅预览：不会下载、解压或覆盖任何文件", "mutagen_windows_amd64_v0\.18\.1\.zip", "\.tools\\mutagen\\mutagen\.exe", "SHA256:", "超时:\s+连接=30s 硬性=300s") `
    -Environment @{ ADP_LANG = "zh-CN" }

Assert-Command `
    -Name "doctor reports VMware NAT prerequisites" `
    -Arguments @("doctor", "-FixMutagen", "-Plan") `
    -ExitCode 0 `
    -Patterns @("VMware NAT config", "VMware NAT gateway range", "VMware NAT host match", "VMware NAT prerequisites", "VMnet8")

Assert-Command `
    -Name "network apply rejects local apply switch" `
    -Arguments @("network", "apply", "agent", "-Apply") `
    -ExitCode 1 `
    -Patterns @("-Apply is only supported with: adpos network configure-local -Apply")
