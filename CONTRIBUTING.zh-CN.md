# 贡献指南

简体中文 | [English](CONTRIBUTING.md)

感谢你帮助改进 AI Dev Platform OS。

## 开发要求

- Windows 11。
- PowerShell 7+。
- VMware Workstation Pro。
- 安装了 `xorriso` 的 WSL。
- OpenSSH client。
- Mutagen 0.18.x。

## 提交变更前

运行：

```powershell
pwsh -NoProfile -Command '$failed = $false; Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object { $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors) > $null; if ($errors) { $failed = $true; $path = $_.FullName; $errors | ForEach-Object { "{0}:{1}: {2}" -f $path, $_.Extent.StartLineNumber, $_.Message } } }; if ($failed) { exit 1 }'
.\test-integration.ps1
.\deploy-check.ps1
.\cli\adp.ps1 doctor
```

对于 bootstrap shell 脚本：

```powershell
$repo = (Get-Location).Path -replace '\\', '/'
$drive = $repo.Substring(0, 1).ToLowerInvariant()
$path = "/mnt/$drive" + $repo.Substring(2)
wsl bash -lc "bash -n '$path/bootstrap/base/setup-base.sh' '$path/bootstrap/frontend/setup-frontend.sh' '$path/bootstrap/frontend/browser-tools.sh' '$path/bootstrap/backend/setup-backend.sh' '$path/bootstrap/agent/setup-agent.sh'"
```

## 编码规范

- 主机专属操作放在 `adapters` 下。
- 运行时创建逻辑放在 `runtimes` 下。
- 命令入口保持轻量，通过 adapters/core modules 路由。
- 优先编写幂等 bootstrap 脚本。
- 避免提交本地 VM 数据、日志、ISO、工具二进制、SSH keys 或本地 assistant 设置。
- 保持 PowerShell 与 Windows 上的 PowerShell 7 兼容。

## 提交卫生

使用聚焦的提交。说明影响的运行时路径，例如：

```text
vmware: make guest IP detection resilient
network: add static IP apply command
docs: add configuration guide
```

## 安全

MVP 使用本地开发默认值。不要向仓库添加真实凭据、私有 SSH keys、tokens、内部主机名或客户数据。
