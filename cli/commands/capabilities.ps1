# ADP-OS Capabilities Command
# Reports supported and planned host/runtime capabilities without changing state.

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

Write-Host ""
Write-UIHost -English "ADP-OS Capabilities" -Chinese "ADP-OS 运行时能力" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "Capabilities only: no VMs, sync sessions, snapshots, guest files, workspace files, downloads, or host networking will be changed." -Chinese "仅查看能力：不会更改 VM、同步会话、快照、guest 文件、工作区文件、下载或主机网络。" -ForegroundColor DarkGray
Write-Host ""

Write-UIHost -English "Current support:" -Chinese "当前支持:" -ForegroundColor Yellow
Write-UIHost -English "  Host control plane: Windows PowerShell" -Chinese "  主机控制平面：Windows PowerShell" -ForegroundColor DarkGray
Write-UIHost -English "  Runtime carrier:    VMware Workstation" -Chinese "  运行时载体：VMware Workstation" -ForegroundColor DarkGray
Write-UIHost -English "  Guest OS profile:   Ubuntu Server 26.04" -Chinese "  Guest OS 配置：Ubuntu Server 26.04" -ForegroundColor DarkGray
Write-UIHost -English "  Runtime profiles:   frontend, backend, agent" -Chinese "  运行时配置：frontend, backend, agent" -ForegroundColor DarkGray
Write-UIHost -English "  Workspace sync:     Mutagen over SSH" -Chinese "  工作区同步：Mutagen over SSH" -ForegroundColor DarkGray
Write-UIHost -English "  Runtime lifecycle:  up, status, stop, logs, destroy, network apply" -Chinese "  运行时生命周期：up, status, stop, logs, destroy, network apply" -ForegroundColor DarkGray
Write-UIHost -English "  Rollback lifecycle: snapshot create, restore" -Chinese "  回滚生命周期：snapshot create, restore" -ForegroundColor DarkGray
Write-UIHost -English "  Evidence workflow:  workspace dashboard, report, report -Markdown, task validation recording" -Chinese "  证据工作流：workspace dashboard, report, report -Markdown, task validation recording" -ForegroundColor DarkGray
Write-Host ""

Write-UIHost -English "Runtime carrier matrix:" -Chinese "运行时载体矩阵:" -ForegroundColor Yellow
Write-UIHost -English "  [supported] vmware-workstation" -Chinese "  [已支持] vmware-workstation" -ForegroundColor Green
Write-UIHost -English "      host: Windows" -Chinese "      主机：Windows" -ForegroundColor DarkGray
Write-UIHost -English "      lifecycle: create/start/status/stop/snapshot/restore/destroy/network/bootstrap" -Chinese "      生命周期：create/start/status/stop/snapshot/restore/destroy/network/bootstrap" -ForegroundColor DarkGray
Write-UIHost -English "      boundary: full VM runtime with static NAT, SSH bootstrap, Docker-capable guest, and VMware snapshots" -Chinese "      边界：完整 VM 运行时，支持静态 NAT、SSH bootstrap、Docker 兼容 guest 和 VMware 快照" -ForegroundColor DarkGray
Write-UIHost -English "  [planned] hyper-v" -Chinese "  [计划中] hyper-v" -ForegroundColor Yellow
Write-UIHost -English "      status: not implemented; no Hyper-V VM creation or lifecycle commands are available" -Chinese "      状态：未实现；暂无可用的 Hyper-V VM 创建或生命周期命令" -ForegroundColor DarkGray
Write-UIHost -English "  [planned] kvm-libvirt" -Chinese "  [计划中] kvm-libvirt" -ForegroundColor Yellow
Write-UIHost -English "      status: not implemented; Linux adapter is a stub" -Chinese "      状态：未实现；Linux 适配器为存根" -ForegroundColor DarkGray
Write-UIHost -English "  [planned] macos-vm" -Chinese "  [计划中] macos-vm" -ForegroundColor Yellow
Write-UIHost -English "      status: not implemented; macOS adapter is a stub" -Chinese "      状态：未实现；macOS 适配器为存根" -ForegroundColor DarkGray
Write-UIHost -English "  [exploratory] container-backed" -Chinese "  [探索中] container-backed" -ForegroundColor Yellow
Write-UIHost -English "      status: not implemented as an ADP outer runtime carrier" -Chinese "      状态：未作为 ADP 外层运行时载体实现" -ForegroundColor DarkGray
Write-UIHost -English "      boundary: Docker and dev containers are runtime-internal project tools today, not the ADP outer lifecycle" -Chinese "      边界：Docker 和 dev container 目前是运行时内部的项目工具，而非 ADP 外层生命周期" -ForegroundColor DarkGray
Write-Host ""

Write-UIHost -English "Host adapter matrix:" -Chinese "主机适配器矩阵:" -ForegroundColor Yellow
Write-UIHost -English "  [supported] windows" -Chinese "  [已支持] windows" -ForegroundColor Green
Write-UIHost -English "      adapters: filesystem, VMware, SSH, Mutagen" -Chinese "      适配器：filesystem, VMware, SSH, Mutagen" -ForegroundColor DarkGray
Write-UIHost -English "  [planned] linux" -Chinese "  [计划中] linux" -ForegroundColor Yellow
Write-UIHost -English "      adapters/linux/linux.ps1 exists as a stub and returns unavailable" -Chinese "      adapters/linux/linux.ps1 作为存根存在，返回不可用" -ForegroundColor DarkGray
Write-UIHost -English "  [planned] macos" -Chinese "  [计划中] macos" -ForegroundColor Yellow
Write-UIHost -English "      adapters/mac/mac.ps1 exists as a stub and returns unavailable" -Chinese "      adapters/mac/mac.ps1 作为存根存在，返回不可用" -ForegroundColor DarkGray
Write-Host ""

Write-UIHost -English "Inner environment integrations:" -Chinese "内部环境集成:" -ForegroundColor Yellow
Write-UIHost -English "  Docker:       installed inside bootstrapped Ubuntu runtimes; not a replacement for the ADP outer runtime lifecycle" -Chinese "  Docker：已安装在 bootstrap 的 Ubuntu 运行时内；不能替代 ADP 外层运行时生命周期" -ForegroundColor DarkGray
Write-UIHost -English "  Devcontainer: detected non-destructively as project metadata in workspace views; not executed by ADP workspace planning commands" -Chinese "  Devcontainer：在工作区视图中以非破坏性方式检测为项目元数据；不由 ADP 工作区规划命令执行" -ForegroundColor DarkGray
Write-UIHost -English "  Browser tests: frontend helper can install browser dependencies on demand inside the runtime; browser binaries are not committed" -Chinese "  浏览器测试：前端辅助工具可按需在运行时内安装浏览器依赖；浏览器二进制文件不会被提交" -ForegroundColor DarkGray
Write-Host ""

Write-UIHost -English "Expansion rules:" -Chinese "扩展规则:" -ForegroundColor Yellow
Write-UIHost -English "  Keep host-specific behavior behind adapters." -Chinese "  将主机特定行为保留在适配器背后。" -ForegroundColor DarkGray
Write-UIHost -English "  Preserve the same user-facing lifecycle before adding a new runtime carrier." -Chinese "  在添加新运行时载体之前，保留相同的用户界面生命周期。" -ForegroundColor DarkGray
Write-UIHost -English "  Do not label a carrier supported until create/start/status/stop/snapshot or equivalent rollback behavior is documented and tested." -Chinese "  在 create/start/status/stop/snapshot 或等效回滚行为经过文档化和测试之前，不要将载体标记为已支持。" -ForegroundColor DarkGray
Write-UIHost -English "  Do not hide security tradeoffs behind a uniform runtime label." -Chinese "  不要将安全权衡隐藏在统一的运行时标签背后。" -ForegroundColor DarkGray
Write-Host ""
Write-UIHost -English "Docs: docs/capabilities.md" -Chinese "文档：docs/capabilities.md" -ForegroundColor DarkGray
