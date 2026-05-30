# 能力边界

简体中文 | [English](../capabilities.md)

本文说明 ADP-OS 当前的能力边界，并明确区分哪些已经支持、哪些只是计划中、哪些只是 stub，避免用户把路线图方向误认为已经可用的 runtime support。

可以用这个命令在 CLI 中查看同一份边界：

```powershell
.\cli\adp.ps1 capabilities
```

该命令是非破坏性的。它不会创建、启动、停止、检查或销毁 VM；不会修改 sync sessions、snapshots、guest files、workspace files、downloads 或 host networking。

## 当前支持

ADP-OS 当前支持：

- Windows PowerShell 作为 host control plane。
- VMware Workstation 作为 runtime carrier。
- Ubuntu Server 26.04 guest runtimes。
- `frontend`、`backend` 和 `agent` runtime profiles。
- 通过 SSH 使用 Mutagen 进行 workspace synchronization。
- Runtime lifecycle commands：`up`、`status`、`stop`、`logs`、`destroy` 和 `network apply`。
- Rollback lifecycle commands：`snapshot create` 和 `restore`。
- Workspace evidence commands：`workspace dashboard`、`workspace report`、`workspace report -Markdown` 和显式 task validation recording。

## 运行时承载矩阵

| Carrier | 状态 | 边界 |
| --- | --- | --- |
| VMware Workstation | Windows 上已支持 | 完整 VM runtime，包含 static NAT、SSH bootstrap、Docker-capable guest 和 VMware snapshots。 |
| Hyper-V | 计划中 | 尚未实现。当前没有 Hyper-V VM 创建或生命周期命令。 |
| KVM/libvirt | 计划中 | 尚未实现。Linux adapter 当前只是 stub。 |
| macOS VM carrier | 计划中 | 尚未实现。macOS adapter 当前只是 stub。 |
| Container-backed runtime | 探索中 | 尚未作为 ADP outer runtime carrier 实现。Docker 和 dev containers 当前是 runtime 内部项目工具。 |

## Host Adapter 矩阵

| Host adapter | 状态 | 说明 |
| --- | --- | --- |
| Windows | 已支持 | Filesystem、VMware、SSH 和 Mutagen adapters 已启用。 |
| Linux | 计划中 | `adapters/linux/linux.ps1` 目前是 stub，并报告 unavailable。 |
| macOS | 计划中 | `adapters/mac/mac.ps1` 目前是 stub，并报告 unavailable。 |

## 内层环境集成

Docker、Docker Compose 和 dev containers 不是 ADP-OS 的替代品。它们是可以在 ADP-managed runtimes 内部运行或被检测到的开发环境工具。

- Docker 会安装在已 bootstrap 的 Ubuntu runtimes 中，让项目工具可以在 VM 边界内使用容器。
- Workspace views 会非破坏性地检测 dev container metadata，并把它作为项目上下文展示。
- Workspace planning commands 不会执行 dev containers、安装 packages、下载 browser binaries、创建 snapshots、stage 文件或 commit changes。

## 扩展规则

新的 runtime carriers 在保持同一套用户可见 lifecycle 和 safety expectations 前，不应标记为 supported：

- 将 host-specific behavior 保持在 adapter boundaries 后面。
- 保持 runtime creation、startup、status、stop、diagnostics、sync 和 rollback 语义一致。
- 清楚记录 security boundary 和 tradeoffs。
- 除非未来某个 runtime 明确记录了不同边界，否则 Docker 和 dev containers 仍然作为内层工具。
- 在把某个 carrier 标记为 supported 前，补齐测试和双语文档。
