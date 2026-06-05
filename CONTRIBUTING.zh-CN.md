# 贡献指南

简体中文 | [English](CONTRIBUTING.md)

感谢你帮助改进 AI Dev Platform OS。

支持问题、可复现 bug reports、feature requests 和 diagnostics 预期见[支持说明](SUPPORT.zh-CN.md)。

## 搭建开发环境

### 1. 克隆仓库

```powershell
git clone git@github.com:karoc/ai-dev-platform.git
cd ai-dev-platform
```

### 2. 安装所需依赖

| 依赖 | 最低版本 | 安装方式 |
|---|---|---|
| Windows 11 | — | 你的主机系统 |
| PowerShell 7 | 7.0 | `winget install Microsoft.PowerShell` |
| VMware Workstation Pro | 17.x | [VMware 下载](https://www.vmware.com/products/workstation-pro.html)（2024年5月起个人免费） |
| WSL | — | `wsl --install`（Windows 功能） |
| xorriso（在 WSL 中） | — | `wsl -u root bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso"` |
| Mutagen | 0.18.x | [Mutagen releases](https://github.com/mutagen-io/mutagen/releases)。将 `mutagen.exe` 放到 `PATH` 或 `.tools\mutagen\` 下。 |
| OpenSSH 客户端 | — | `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0` |

### 3. 下载 Ubuntu Server ISO

从 [Ubuntu releases](https://releases.ubuntu.com/26.04/) 下载 Ubuntu Server 26.04 live server ISO，放到 ADP-OS 可找到的位置。默认路径在 `configs/platform.json` 中配置。

### 4. 运行首次诊断

```powershell
.\cli\adp.ps1 doctor -FirstRun
```

这会检查所有依赖并报告缺失项及修复建议。解决所有问题后再继续。

### 5. 配置本地网络（如需）

如果你的 VMware NAT 子网与默认值不同，预览并应用本地覆盖：

```powershell
.\cli\adp.ps1 network configure-local -Plan
.\cli\adp.ps1 network configure-local -Apply
```

### 6. 验证开发环境

```powershell
.\tests\validate.ps1 -Quick
```

这会运行语法检查、CLI 冒烟测试和文档验证。大约需要 10 秒。所有检查应通过，输出 `Repository validation OK`。

## 开发流程

### 进行变更

1. 创建聚焦分支：`git checkout -b my-change`
2. 遵循[编码规范](#编码规范)进行变更
3. 开发过程中频繁运行验证：

```powershell
.\tests\validate.ps1 -Quick
```

### 用真实 VM 测试

端到端测试 VM 生命周期变更：

```powershell
.\cli\adp.ps1 up agent -IsoPath D:\path\to\ubuntu-26.04-live-server-amd64.iso -Plan
.\cli\adp.ps1 up agent -IsoPath D:\path\to\ubuntu-26.04-live-server-amd64.iso
.\cli\adp.ps1 status agent
.\cli\adp.ps1 doctor
```

> VM 创建需要约 10-15 分钟用于 Ubuntu 自动安装，外加约 5 分钟用于 bootstrap。先用 `-Plan` 预览操作。

### 提交变更前

Workspace task templates、release-readiness expectations 和维护者 review flow 见[贡献者工作流](docs/zh-CN/contributor-workflows.md)与[发布就绪](docs/zh-CN/release-readiness.md)。

运行完整验证门：

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

## Pull Request 流程

1. **推送你的分支**并对 `main` 发起 pull request。
2. **CI 会自动运行**完整的验证套件。修复任何失败。
3. **在 PR 描述中包含上下文**：
   - 解决了什么问题（如有相关 issue 请链接）
   - 哪些文件被修改、为什么修改
   - 进行的测试（运行的命令、输出）
4. **保持 PR 聚焦**——每次 PR 一个逻辑变更。如果你的工作涉及多个领域，拆分为多个 PR。
5. **文档**——如果你的变更影响了用户可见行为、命令或配置，更新相关文档。保持英文和简体中文文档同步。
6. **发布证据**——当变更影响 workflow、runtime behavior、validation、documentation 或 release readiness 时，包含 `workspace report -Markdown` 输出。
7. **审查**——维护者会审查你的 PR。在新 commits 中或通过 amend 来响应反馈。

### PR 就绪清单

- [ ] 完整验证通过：`.\tests\validate.ps1`
- [ ] 集成测试通过：`.\test-integration.ps1`
- [ ] 部署检查通过：`.\deploy-check.ps1`
- [ ] 文档已更新（用户可见变更需同步中英文）
- [ ] 如有用户可见变更，CHANGELOG 已更新
- [ ] 未提交 secrets、凭据、VM 磁盘、ISO、日志或工具二进制文件
- [ ] 高风险 agent work 包含 snapshot gate 或维护者显式豁免

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

## 社区

- **Issues**：使用 [issue 模板](https://github.com/karoc/ai-dev-platform/issues/new/choose)——Bug Report、Feature Request、安装帮助或使用问题。
- **Discord**：加入 [ADP-OS Discord 服务器](docs/zh-CN/discord-setup.md)进行实时讨论、求助和开发协作。
- **Discussions**：对于不适合 issue 模板的开放想法和问题，使用 [GitHub Discussions](https://github.com/karoc/ai-dev-platform/discussions)。要启用 Discussions，前往仓库 Settings → General → Features，勾选 "Discussions"。

## 安全

MVP 使用本地开发默认值。不要向仓库添加真实凭据、私有 SSH keys、tokens、内部主机名或客户数据。
