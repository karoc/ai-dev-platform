# 变更日志

简体中文 | [English](CHANGELOG.md)

这里记录 AI Dev Platform OS 的重要公开变更。

项目尚未发布版本化 release。在引入 release tags 前，变更按日期分组。

## 2026-05-27

### 新增

- 新增 CLI 参数契约 CI 验证，用于检查已接收的开关是否贯通到实际执行路径。
- 新增非破坏性 CLI smoke tests，覆盖命令分发、预览输出和输入错误边界。
- 新增更强的首次使用依赖诊断，覆盖 VMware disk manager、WSL、`xorriso`、ISO remaster、Mutagen 版本和 ISO 基本形态。
- 新增 workspace manifest 示例，以及非破坏性的 `adp workspace init/show/plan` 命令。
- 新增 `adp doctor -FirstRun`，提供首次使用检查清单。
- 新增 `adp up`、`adp network apply` 和 `adp destroy` 的 `-Plan` 预览。
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
- 新增目标项目 clone 和 ADP-OS dogfooding 的工作区指南。

### 变更

- 修复 `adp init <runtime> -SkipProvision`，现在会传递到 `adp up -NoProvision`，不再只是跳过 bootstrap。
- 修复 `adp up <runtime> -NoProvision`，现在创建 VM 定义后会停止，不再继续进入 bootstrap readiness checks。
- 更新 `adp up <runtime> -Plan`，当不需要查询 VM 状态时，预览输出可在未安装 VMware 的环境中运行。
- 修复 CLI 子命令退出码传播，使自动化和 CI 能正确识别命令失败。
- 修复 `adp help`，现在 help 定义会在 CLI dispatch 路径调用前加载。
- 修复嵌套命令日志状态查询，避免命令调用命令时因日志级别状态查找失败。
- 修复 `adp logs`、`adp sync start` 和 `adp sync stop`，现在会在命令边界拒绝未知 runtime 名称。
- 修复 `install.ps1 -SkipDependencyCheck` 和 `install.ps1 -SkipVMValidation`，现在两个开关都会改变对应 installer 行为。
- 修复 `adp up <runtime> -IsoPath <path>`，现在传入的 ISO 路径会正确传递给 VM 创建流程，不再回退到配置的 ISO cache。
- 更新 README 语言导航。
- 更新 frontend bootstrap，使其安装轻量浏览器辅助命令，但默认不下载浏览器。
- 更新同步和 Git ignore 规则，忽略浏览器测试报告和 Playwright 产物。
- 将 agent 运行时启动提示从 `DANGER MODE` 改为 high-IO agent profile 提示。
- 更新 `adp doctor`，报告本地配置覆盖状态。
- 扩展 `adp doctor`，检查配置结构、VMware NAT 网段、运行时静态 IP 唯一性、sync profiles、运行中 VM 的 SSH 可达性、Mutagen 版本和 Mutagen sessions。

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
