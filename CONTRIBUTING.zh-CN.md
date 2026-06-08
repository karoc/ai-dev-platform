# 贡献指南

简体中文 | [English](CONTRIBUTING.md)

> 本指南同时提供英文版本：[Contributing Guide (English)](CONTRIBUTING.md)

## 快速开始

- **环境**：Windows 11 + PowerShell 7 + WSL + Git
- **克隆**：`git clone git@github.com:karoc/ai-dev-platform.git`
- **安装**：`.\\setup.cmd`，完成后使用全局 `adpos` 命令；当前 shell 尚未刷新 `PATH` 时可用 `.\\adpos.cmd`
- **验证**：`bash scripts/test.sh quick`
- **提交规范**：遵循 [约定式提交](https://www.conventionalcommits.org/zh-hans) — `type(scope): 描述`

## 代码规范

- **PowerShell**：优先使用 `Write-UIHost` 而非 `Write-Host` 以支持双语输出
- **Shell 脚本**：使用 `bootstrap/common/common.sh` 工具函数（`check-root`、`mark-step`、`is-installed`、`retry`）
- **代码文件行数**：每个代码文件保持在 700 行以内。如果代码文件超过 700 行，必须按清晰职责拆分后才能视为完成。现有超限文件属于重构债务；除非本次工作同时减少行数或拆分文件，否则不要继续向其中加入实质性逻辑。
- **Markdown**：所有面向用户的文档应中英双语
- **.ps1 文件**：使用 LF 换行

## PR 流程

1. Fork → 创建分支 → 修改 → `bash scripts/test.sh quick` → 提交 → PR
2. CI 自动运行，维护者审查

## 更多信息

完整的中英双语贡献指南（开发环境搭建、提交规范详解、完整 PR 流程、文档规范）请参见 [Contributing Guide (English)](CONTRIBUTING.md)。

有问题？请使用 [GitHub Issues 模板](https://github.com/karoc/ai-dev-platform/issues/new/choose) 提交安装帮助、使用问题、bug 或功能请求。Discord 仍是[搭建计划](docs/zh-CN/discord-setup.md)，发布真实邀请链接前不是当前可用的支持渠道。
