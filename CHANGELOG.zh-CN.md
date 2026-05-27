# 变更日志

简体中文 | [English](CHANGELOG.md)

这里记录 AI Dev Platform OS 的重要公开变更。

项目尚未发布版本化 release。在引入 release tags 前，变更按日期分组。

## 2026-05-27

### 新增

- 新增公开 `SECURITY.md` 和 `SECURITY.zh-CN.md`。
- 新增公开 `CHANGELOG.md` 和 `CHANGELOG.zh-CN.md`。
- 新增 GitHub bug report 和 feature request issue templates。
- 新增 GitHub pull request template。
- 新增 GitHub Actions CI，用于非破坏性仓库验证。
- 新增英文和简体中文双语公开文档导航。
- 新增 `docs/zh-CN` 下的简体中文文档。
- 新增 `CONTRIBUTING.zh-CN.md`。
- 新增 frontend 浏览器验收辅助命令：
  - `adp-frontend-browser-check`
  - `adp-frontend-browser-install`
- 新增浏览器测试文档。
- 新增 `configs/local.example.json` 和本地配置覆盖支持，用于本机路径、VM 规格、网络、凭据和同步 profile 调整。

### 变更

- 更新 README 语言导航。
- 更新 frontend bootstrap，使其安装轻量浏览器辅助命令，但默认不下载浏览器。
- 更新同步和 Git ignore 规则，忽略浏览器测试报告和 Playwright 产物。

## 2026-05-26

### 新增

- ADP-OS 初始开源发布。
- Windows PowerShell 控制平面。
- VMware Workstation 运行时工厂。
- Ubuntu Server 26.04 autoinstall provisioning。
- Frontend、backend 和 agent 运行时 profiles。
- 静态 VMware NAT 网络。
- Mutagen 工作区同步。
- SSH bootstrap。
- Diagnostics、deployment pre-check、snapshot、restore、stop、logs 和 destroy 命令。
- 公开 README、架构文档、配置文档、操作文档、网络文档、贡献指南和 MIT license。
