# Contributing to ADP-OS / 贡献指南

[简体中文](#贡献指南) | [English](#english)

Thank you for your interest in contributing to ADP-OS! This guide will help you get started.

---

## English

### Development Environment Setup

ADP-OS is a Windows-first PowerShell 7 project with WSL-based build tooling. You need:

- **Windows 11** — the primary host platform
- **PowerShell 7** (`pwsh`) — required; Windows PowerShell 5.1 won't work
- **WSL** (Windows Subsystem for Linux) — for `xorriso` ISO remastering and cross-platform testing
- **Git** — for version control (SSH remotes preferred: `git@github.com:karoc/ai-dev-platform.git`)

Recommended but optional for local validation:
- VMware Workstation Pro (free for personal use since May 2024)
- Mutagen 0.18.x

#### Clone and Install

```powershell
git clone git@github.com:karoc/ai-dev-platform.git
cd ai-dev-platform
.\setup.cmd            # Guided setup; registers the global `adpos` command
```

After setup, use `adpos` from any directory. If the current shell has not refreshed `PATH`, use `.\adpos.cmd` from the repository root. ADP-OS exposes `adpos` as the only user-facing shell command.

### Validation Flow

All changes must pass validation before submission. From WSL:

```bash
# Quick validation — static checks only (~10 seconds)
bash scripts/test.sh quick

# Full validation — all tests including CLI smoke
bash scripts/test.sh full

# Integration tests
bash scripts/test.sh integration

# Deploy readiness check
bash scripts/test.sh deploy

# System diagnostics
bash scripts/test.sh doctor
```

`test.sh` syncs your WSL changes to the Windows clone at `D:\Dev\ai-dev-platform\` via `rsync`, then runs the tests under PowerShell 7.

### Commit Conventions

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
type(scope): brief description

- `feat` — new feature
- `fix` — bug fix
- `docs` — documentation
- `refactor` — code restructuring (no behavior change)
- `test` — tests
- `chore` — tooling, CI, build
- `community` — community assets (issue templates, Discord, etc.)

Scope examples: `docs`, `deer-flow`, `ci`, `install`, `network`, `workspace`
```

Examples:
```
feat(deer-flow): SandboxProvider adapter for ADP-OS MCP backend
fix(ci): skip setup non-interactive test when VMware absent
docs: add getting-started guide
community: add Discord badge + issue templates
```

Keep commits focused — one logical change per commit. Write messages in English.

### Pull Request Process

1. **Fork** the repository and create a feature branch:
   ```bash
   git checkout -b feat/my-feature
   ```

2. **Make your changes**. Follow existing code and document conventions:
   - PowerShell: prefer `Write-UIHost` over `Write-Host` for bilingual output
   - Shell scripts: use `bootstrap/common/common.sh` utilities (`check-root`, `mark-step`, `is-installed`, `retry`)
   - Code file size: keep each code file at or below 700 lines. If a code file exceeds 700 lines, split it by coherent responsibility before considering the change complete. Existing over-limit files are refactor debt; do not add new substantive logic to them unless the work also reduces or splits the file.
   - Markdown: all user-facing docs should be bilingual (EN + zh-CN)
   - `.ps1` files: use LF line endings (CRLF is normalized at commit time)

3. **Validate** before pushing:
   ```bash
   bash scripts/test.sh quick
   ```

4. **Commit** with a conventional commit message.

5. **Push** and open a Pull Request against `main`.

6. A maintainer will review your PR. CI checks run automatically on push.

### Documentation

- All user-facing docs must be bilingual (English + 简体中文)
- English docs live at `docs/`; Chinese translations at `docs/zh-CN/`
- Top-level files use paired files: `README.md` / `README.zh-CN.md`, `CHANGELOG.md` / `CHANGELOG.zh-CN.md`
- Internal / maintainer docs are English-only

### Questions?

- **GitHub Issues**: Use the templates for [installation help, usage questions, bugs, or feature requests](https://github.com/karoc/ai-dev-platform/issues/new/choose).
- **Discord**: The [Discord setup plan](docs/discord-setup.md) is available for maintainers, but Discord is not an active support channel until an invite link is published.

---

## 贡献指南

感谢你对 ADP-OS 的关注！本指南将帮助你快速上手。

### 开发环境设置

ADP-OS 是一个 Windows-first PowerShell 7 项目，使用 WSL 作为构建工具。你需要：

- **Windows 11** — 主要主机平台
- **PowerShell 7** (`pwsh`) — 必需；Windows PowerShell 5.1 不可用
- **WSL**（适用于 Linux 的 Windows 子系统）— 用于 `xorriso` ISO 重封装和跨平台测试
- **Git** — 版本控制（推荐 SSH 远程：`git@github.com:karoc/ai-dev-platform.git`）

建议但不强制安装（用于本地验证）：
- VMware Workstation Pro（自 2024 年 5 月起个人免费）
- Mutagen 0.18.x

#### 克隆和安装

```powershell
git clone git@github.com:karoc/ai-dev-platform.git
cd ai-dev-platform
.\setup.cmd            # 引导式设置；注册全局 `adpos` 命令
```

设置完成后，在任意目录使用 `adpos`。如果当前 shell 尚未刷新 `PATH`，可在仓库根目录使用 `.\adpos.cmd`。ADP-OS 对外只暴露 `adpos` 这一个用户 shell 命令。

### 验证流程

所有更改必须在提交前通过验证。在 WSL 中：

```bash
# 快速验证 — 仅静态检查（约 10 秒）
bash scripts/test.sh quick

# 完整验证 — 所有测试（含 CLI 冒烟测试）
bash scripts/test.sh full

# 集成测试
bash scripts/test.sh integration

# 部署就绪检查
bash scripts/test.sh deploy

# 系统诊断
bash scripts/test.sh doctor
```

`test.sh` 通过 `rsync` 将 WSL 更改同步到 `D:\Dev\ai-dev-platform\` 的 Windows 克隆，然后在 PowerShell 7 下运行测试。

### 提交规范

我们遵循 [约定式提交](https://www.conventionalcommits.org/zh-hans)：

```
type(scope): 简要描述

- `feat` — 新功能
- `fix` — 错误修复
- `docs` — 文档
- `refactor` — 代码重构（无行为变更）
- `test` — 测试
- `chore` — 工具、CI、构建
- `community` — 社区资产（Issue 模板、Discord 等）

Scope 示例：`docs`、`deer-flow`、`ci`、`install`、`network`、`workspace`
```

示例：
```
feat(deer-flow): SandboxProvider adapter for ADP-OS MCP backend
fix(ci): skip setup non-interactive test when VMware absent
docs: add getting-started guide
community: add Discord badge + issue templates
```

保持提交聚焦——每次提交一个逻辑变更。提交信息使用英文。

### Pull Request 流程

1. **Fork** 仓库并创建功能分支：
   ```bash
   git checkout -b feat/my-feature
   ```

2. **进行更改**。遵循现有代码和文档规范：
   - PowerShell：优先使用 `Write-UIHost` 而非 `Write-Host` 以支持双语输出
   - Shell 脚本：使用 `bootstrap/common/common.sh` 工具函数（`check-root`、`mark-step`、`is-installed`、`retry`）
   - 代码文件行数：每个代码文件保持在 700 行以内。如果代码文件超过 700 行，必须按清晰职责拆分后才能视为完成。现有超限文件属于重构债务；除非本次工作同时减少行数或拆分文件，否则不要继续向其中加入实质性逻辑。
   - Markdown：所有面向用户的文档应中英双语
   - `.ps1` 文件：使用 LF 换行（CRLF 在提交时自动规范化）

3. **验证**后推送：
   ```bash
   bash scripts/test.sh quick
   ```

4. **提交**，使用约定式提交消息。

5. **推送** 并对 `main` 分支发起 Pull Request。

6. 维护者会审查你的 PR。CI 检查在推送时自动运行。

### 文档

- 所有面向用户的文档必须中英双语
- 英文文档位于 `docs/`；中文翻译位于 `docs/zh-CN/`
- 顶级文件使用配对文件：`README.md` / `README.zh-CN.md`、`CHANGELOG.md` / `CHANGELOG.zh-CN.md`
- 内部/维护者文档仅英文

### 有问题？

- **GitHub Issues**：使用模板提交[安装帮助、使用问题、bug 或功能请求](https://github.com/karoc/ai-dev-platform/issues/new/choose)。
- **Discord**：[Discord 搭建计划](docs/discord-setup.md) 供维护者准备社区入口；发布真实邀请链接前，Discord 不是当前可用的支持渠道。
