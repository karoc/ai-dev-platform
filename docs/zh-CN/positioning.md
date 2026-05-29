# ADP-OS 与 Docker

简体中文 | [English](../positioning.md)

ADP-OS 不是 Docker 的替代品。

Docker 是容器运行时和应用打包系统。ADP-OS 创建并运维可运行 Docker 的本地 Linux 开发运行时，并在其外层提供宿主隔离、工作区同步、角色化 bootstrap、诊断、静态网络和 VM 级快照回滚。

简短地说：

```text
Docker 用于打包和运行应用。
ADP-OS 用于创建和运维 AI-ready 的开发运行时。
```

## 所处层级不同

Docker 的核心单位是：

```text
container
image
volume
network
```

ADP-OS 的核心单位是：

```text
runtime
workspace
sync session
bootstrap profile
snapshot
role
```

ADP-OS 可以在每个运行时内部安装并使用 Docker。平台边界位于 Docker 之外：

```text
Windows host
  -> ADP-OS control plane
      -> VMware Ubuntu runtime
          -> Docker, Node.js, Python, browsers, project tools
```

## 为什么不只用 Docker？

### 更清晰的宿主边界

Docker containers 共享宿主机内核。当前 Windows MVP 中，ADP-OS 使用完整 Linux VM，让每个运行时拥有更清晰的机器边界：

- 真实 Ubuntu Server 环境。
- 真实 SSH、systemd、apt、Docker daemon、netplan 和 Linux 工具链。
- 系统级修改留在 VM 内。
- AI agent 的实验可以通过 VM snapshot 回滚。

当 AI agent 可能安装系统包、修改配置、运行 Docker、启动服务或执行大量诊断时，这个边界尤其有价值。

### 更好的 Windows 到 Linux 工作区行为

Windows 上的 Docker bind mount 可能暴露文件监听、路径、性能和权限差异。

ADP-OS 使用 Mutagen 同步：

```text
%USERPROFILE%\adp-workspaces\frontend
  <-> /home/adp/workspace
```

Guest runtime 看到的是原生 Linux 文件系统，host 侧仍保留正常 Windows 工作区。这对前端 watchers、Python 环境、`node_modules` 和会扫描大量文件的 AI 工具很有用。

### VM 级快照和恢复

Docker 可以重建 containers 和 images，但 AI 开发环境经常包含单个 container 之外的状态：

- apt packages。
- Docker daemon 状态。
- systemd services。
- SSH 和 shell 配置。
- 语言运行时缓存。
- 浏览器依赖。
- 网络配置。

ADP-OS 暴露 VM 级回滚：

```powershell
.\cli\adp.ps1 snapshot create agent clean
.\cli\adp.ps1 restore agent clean
```

这恢复的是作为机器的 runtime，而不只是某个进程或 container。

### 角色化运行时

Docker 本身不定义 `frontend`、`backend`、`agent` 这类产品级角色。ADP-OS 把这些角色作为一等概念：

```text
frontend: JavaScript、前端工具链、浏览器验收辅助命令
backend: Python 和后端开发
agent: 更高资源规格、IO 调优、agent sandbox 准备
```

同一组 ADP 命令管理每个运行时：

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 sync start frontend
.\cli\adp.ps1 snapshot create frontend clean
.\cli\adp.ps1 doctor
```

### Agent 原生开发

AI agents 经常需要像开发者一样在机器里工作：

- 安装依赖。
- 运行测试。
- 启动多个服务。
- 使用浏览器做验收检查。
- 检查源码树。
- 运行 Docker 命令。
- 修改本地配置。
- 生成 review artifacts。

把 agent 放进 container 往往需要 privileged mode、挂载 Docker socket、嵌套容器、额外 systemd 处理，以及非常谨慎的 host volume 访问。

ADP-OS 给 agent 一个更容易理解、也更容易回滚的 Linux runtime 边界。

## 什么时候 Docker 更合适

当你主要需要以下能力时，直接使用 Docker 更合适：

- 应用打包。
- 使用 `docker compose up` 启动服务栈。
- CI/CD image builds。
- 类生产 container 部署。
- 轻量本地服务。
- 已有成熟 Docker Compose 或 devcontainer 工作流。

ADP-OS 不应该替代这些工作流。

## 什么时候 ADP-OS 更合适

当你需要以下能力时，ADP-OS 更合适：

- Windows 上可复现的本地 Linux 工作站边界。
- 面向 agent 实验的完整 VM 隔离。
- VM 级快照和恢复。
- 原生 Linux 文件系统行为，同时保留 host 同步。
- 多个角色化开发运行时。
- 已准备 SSH、systemd、Node.js、Python、Docker 和诊断工具的 Docker-capable runtime。
- 围绕本地 AI 辅助开发工作流的平台层。

## 设计原则

ADP-OS 不应该变成另一个容器编排器。

Docker 保持为运行时内部的容器层。ADP-OS 提供外层开发运行时生命周期：

```text
provision
bootstrap
sync
diagnose
snapshot
restore
operate
```

目标是为 AI agents 和开发者提供可复现的本地 Linux 工作站边界，而不只是一个容器运行时。
