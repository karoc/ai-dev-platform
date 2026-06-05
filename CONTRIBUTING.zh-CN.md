# 贡献指南

简体中文 | [English](CONTRIBUTING.md)

> 本指南同时提供英文版本：[Contributing Guide (English)](CONTRIBUTING.md)

## 快速开始

- **环境**：Windows 11 + PowerShell 7 + WSL + Git
- **克隆**：`git clone git@github.com:karoc/ai-dev-platform.git`
- **安装**：`.\\install.ps1`
- **验证**：`bash scripts/test.sh quick`
- **提交规范**：遵循 [约定式提交](https://www.conventionalcommits.org/zh-hans) — `type(scope): 描述`

## 代码规范

- **PowerShell**：优先使用 `Write-UIHost` 而非 `Write-Host` 以支持双语输出
- **Shell 脚本**：使用 `bootstrap/common/common.sh` 工具函数（`check-root`、`mark-step`、`is-installed`、`retry`）
- **Markdown**：所有面向用户的文档应中英双语
- **.ps1 文件**：使用 LF 换行

## PR 流程

1. Fork → 创建分支 → 修改 → `bash scripts/test.sh quick` → 提交 → PR
2. CI 自动运行，维护者审查

## 更多信息

完整的中英双语贡献指南（开发环境搭建、提交规范详解、完整 PR 流程、文档规范）请参见 [Contributing Guide (English)](CONTRIBUTING.md)。

有问题？加入 [Discord 社区](docs/zh-CN/discord-setup.md) 或在 [GitHub Discussions](https://github.com/karoc/ai-dev-platform/discussions) 提问。
