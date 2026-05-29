# 贡献指南

简体中文 | [English](CONTRIBUTING.md)

感谢你帮助改进 AI Dev Platform OS。

支持问题、可复现 bug reports、feature requests 和 diagnostics 预期见[支持说明](SUPPORT.zh-CN.md)。

## 开发要求

- Windows 11。
- PowerShell 7+。
- VMware Workstation Pro。
- 安装了 `xorriso` 的 WSL。
- OpenSSH client。
- Mutagen 0.18.x。

## 提交变更前

Workspace task templates、release-readiness expectations 和维护者 review flow 见[贡献者工作流](docs/zh-CN/contributor-workflows.md)与[发布就绪](docs/zh-CN/release-readiness.md)。

运行：

```powershell
.\tests\validate.ps1
.\test-integration.ps1
.\deploy-check.ps1
.\cli\adp.ps1 doctor
```

本地迭代时可先运行 `.\tests\validate.ps1 -Quick`，提交前再运行完整 validation gate。

对于 bootstrap shell 脚本：

```powershell
$repo = (Get-Location).Path -replace '\\', '/'
$drive = $repo.Substring(0, 1).ToLowerInvariant()
$path = "/mnt/$drive" + $repo.Substring(2)
wsl bash -lc "bash -n '$path/bootstrap/base/setup-base.sh' '$path/bootstrap/frontend/setup-frontend.sh' '$path/bootstrap/frontend/browser-tools.sh' '$path/bootstrap/backend/setup-backend.sh' '$path/bootstrap/agent/setup-agent.sh' '$path/bootstrap/common/common.sh'"
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

## Pull Request 就绪

- 说明使用的 workspace task shape；如果没有适用 task，说明原因。
- 当变更影响 workflow、runtime behavior、validation、documentation 或 release readiness 时，包含 `workspace report -Markdown` release evidence。
- README 或用户可见文档变更时，保持 README 和简体中文文档同步。
- 高风险 agent work 在没有 snapshot gate 或维护者显式豁免前，不应标记 ready。

## 安全

MVP 使用本地开发默认值。不要向仓库添加真实凭据、私有 SSH keys、tokens、内部主机名或客户数据。
