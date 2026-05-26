# AI Dev Platform OS（ADP-OS）—— 本地 AI Coding Runtime 平台工程实现规范（v3）

你现在是一个：

* 基础设施架构师
* DevOps 平台工程师
* 虚拟化系统工程师
* AI Runtime 平台工程师
* 本地开发平台工程师

你的目标不是“写脚本”。

你的目标是：

# 构建一个真正可长期演进的：

# Local AI Development Platform OS（ADP-OS）

这是一个：

* 本地化
* 多 VM
* 多 Agent
* Sandbox-Oriented
* AI-Native
* Workspace-Centric

的 AI Coding Runtime Platform。

该系统未来形态接近：

* DevPod
* GitHub Codespaces
* Daytona
* 本地版 AI Agent OS

但：

* 完全本地化
* 面向 AI coding workflow
* 面向 Codex / Claude Code / Agent Runtime
* 高 IO 优化
* Snapshot / Rollback 优化
* 多工作区 / 多 VM / 多 Agent 优化

---

# 一、系统定位（极其重要）

本项目不是：

* VM 管理脚本
* Ubuntu 安装器
* Docker wrapper
* 开发环境配置器

而是：

# AI Development Runtime Operating System

核心理念：

```text id="core_os"
Host OS（Windows/macOS/Linux）
        ↓
ADP-OS（控制平面）
        ↓
Runtime Fabric（VM / Container / Sandbox）
        ↓
Workspace Fabric（Sync / Snapshot / Isolation）
        ↓
AI Agents（Codex / Claude / OpenHands）
```

系统必须从一开始按“平台系统”设计。

---

# 二、当前阶段目标（MVP）

当前阶段：

# 只实现 Windows MVP

使用：

* Windows 11
* VMware Workstation
* Ubuntu Server 26.04 LTS
* Mutagen

用户允许：

* 手动安装 VMware
* 手动准备 Ubuntu ISO

其余流程必须尽可能自动化。

---

# 三、最终用户体验（目标）

用户只需要：

```powershell id="user_flow"
git clone adp-os
cd adp-os

.\install.ps1
```

然后系统自动完成：

* Runtime 初始化
* VM Factory 初始化
* Ubuntu 自动安装
* SSH 初始化
* AI Runtime Bootstrap
* Docker Runtime
* Workspace Sync
* Snapshot Baseline
* VSCode Remote
* Agent Runtime

最终用户使用：

```powershell id="cli_flow"
adp init

adp up frontend
adp up backend
adp up agent

adp sync status

adp snapshot agent clean
adp restore agent clean

adp doctor
```

---

# 四、架构要求（必须）

必须实现：

# Platform-Abstraction Architecture

必须从一开始预留：

* Windows
* macOS
* Linux

禁止：

* PowerShell 逻辑直接耦合业务
* VMware API 与核心逻辑耦合
* Windows 路径硬编码
* VM 逻辑散落

必须：

# Host Adapter Layer

---

# 五、系统架构（必须）

```text id="system_arch"
adp-os/
├── install.ps1
├── cli/
│   ├── adp.ps1
│   └── commands/
├── core/
│   ├── runtime/
│   ├── workspace/
│   ├── snapshot/
│   ├── topology/
│   ├── config/
│   ├── logging/
│   ├── sync/
│   └── bootstrap/
├── adapters/
│   ├── windows/
│   │   ├── vmware/
│   │   ├── ssh/
│   │   ├── mutagen/
│   │   └── filesystem/
│   ├── mac/
│   └── linux/
├── runtimes/
│   ├── ubuntu/
│   ├── vmware/
│   ├── docker/
│   └── sandbox/
├── bootstrap/
│   ├── base/
│   ├── frontend/
│   ├── backend/
│   ├── agent/
│   └── common/
├── sync/
├── configs/
├── templates/
├── snapshots/
├── docs/
└── tests/
```

---

# 六、核心设计原则（极其重要）

系统必须：

## 1. Runtime-Centric

核心不是 VM。

核心是：

# AI Runtime

VM 只是 Runtime Carrier。

未来必须支持：

* VMware
* Hyper-V
* KVM
* Docker Runtime
* Container Runtime
* Cloud Runtime

---

## 2. Workspace-Centric

Workspace 是第一公民。

必须支持：

* 多 workspace
* 双向 sync
* Snapshot
* Isolation
* Fast rollback

禁止：

```text id="bad_workspace"
D:\project
```

必须：

```text id="good_workspace"
${WORKSPACE_ROOT}
```

由 Host Adapter 注入。

---

## 3. Agent-Centric

系统目标是：

# AI Agent Runtime Optimization

不是传统 IDE。

必须优化：

* 高频 IO
* ripgrep
* AST indexing
* node_modules
* watcher
* Docker build
* git diff
* AI patch workflow

---

## 4. Sandbox-Oriented

Agent Runtime 默认危险。

必须支持：

* isolation
* rollback
* snapshot
* disposable runtime
* dangerous runtime

---

# 七、VM Runtime System（重要）

必须支持：

* frontend runtime
* backend runtime
* agent runtime

每个 runtime：

* CPU
* Memory
* Disk
* Sync profile
* Bootstrap profile
* Snapshot policy

均可配置。

配置文件：

```json id="topology_json"
configs/topology.json
```

示例：

```json id="topology_example"
{
  "frontend": {
    "runtime": "vmware",
    "cpu": 4,
    "memory": 8192,
    "disk": 80,
    "workspace": "frontend"
  },

  "backend": {
    "runtime": "vmware",
    "cpu": 4,
    "memory": 8192,
    "disk": 120,
    "workspace": "backend"
  },

  "agent": {
    "runtime": "vmware",
    "cpu": 6,
    "memory": 16384,
    "disk": 160,
    "danger": true,
    "snapshot_policy": "always"
  }
}
```

---

# 八、Ubuntu Autoinstall（必须）

必须实现：

# 完整无人值守 Ubuntu Runtime 安装

使用：

* cloud-init
* autoinstall
* user-data
* meta-data

自动完成：

* 用户创建
* openssh-server
* docker
* bootstrap system
* runtime registration

禁止：

* 手工安装 Ubuntu
* 手工 SSH 配置
* 手工初始化

---

# 九、Bootstrap System（核心）

必须实现：

```text id="bootstrap_tree"
bootstrap/
  setup-base.sh
  setup-frontend.sh
  setup-backend.sh
  setup-agent.sh
```

---

# setup-base.sh

必须：

* 幂等
* 可重复执行
* 失败可恢复

安装：

* git
* curl
* ripgrep
* fd
* fzf
* jq
* build-essential
* docker
* fnm
* node
* pnpm
* python
* uv
* ssh
* tmux

---

# setup-agent.sh

必须：

* AI runtime tuning
* inotify tuning
* Docker tuning
* high IO tuning
* sandbox preparation

优化：

* fs.inotify.max_user_watches
* swappiness
* ext4 workspace

---

# 十、Workspace Sync System（关键）

必须集成：

# Mutagen

禁止：

* VMware Shared Folder
* WSL mount
* SMB shared dev

必须：

* 自动创建 sync session
* 自动 ignore node_modules
* 自动 ignore dist/.next/.git
* 支持 frontend/backend/agent sync profile

同步模式：

```yaml id="sync_mode"
two-way-resolved
```

---

# 十一、CLI System（必须）

必须实现：

```powershell id="cli_commands"
adp init

adp up frontend
adp up backend
adp up agent

adp stop frontend

adp sync status

adp snapshot create agent clean
adp snapshot restore agent clean

adp logs frontend

adp doctor

adp destroy agent
```

CLI 要求：

* 模块化
* 子命令风格
* 日志清晰
* 支持扩展
* 后续可迁移 TypeScript/Rust

---

# 十二、Snapshot System（重要）

必须抽象：

```text id="snapshot_system"
snapshot/
```

当前实现：

* VMware snapshot

未来预留：

* Hyper-V
* KVM
* ZFS snapshot
* Container snapshot

---

# 十三、Agent Runtime（核心）

Agent Runtime 用于：

```bash id="danger_mode"
codex --ask-for-approval never \
  -c sandbox_mode=danger-full-access
```

因此必须：

* 强隔离
* 高频 IO 优化
* 快速恢复
* disposable runtime
* rollback support

Agent Runtime：

* 不同步 node_modules
* 不共享宿主文件系统
* 使用 ext4 workspace

---

# 十四、Workspace Strategy（非常重要）

系统必须：

# “同步优先，而不是挂载优先”

因为：

AI Agent 场景：

* metadata IO 极高
* watcher 极高
* node_modules 极重

因此：

必须：

```text id="sync_strategy"
Windows Workspace
        ⇅ Mutagen
Linux ext4 Workspace
```

而不是：

```text id="bad_mount"
WSL mount
VM shared folder
```

---

# 十五、日志与可观测性（必须）

实现：

```text id="logging"
logs/
```

支持：

* runtime logs
* sync logs
* bootstrap logs
* snapshot logs
* doctor diagnostics

必须：

* 可读
* 可定位
* 可恢复

---

# 十六、Doctor System（重要）

实现：

```powershell id="doctor"
adp doctor
```

检查：

* VMware
* vmrun
* Mutagen
* SSH
* ISO
* Workspace
* Runtime status
* Snapshot status

输出：

* human-readable
* actionable

---

# 十七、未来演进（必须预留）

必须预留：

## macOS

* VMware Fusion
* Apple Virtualization
* Colima

---

## Linux

* KVM
* libvirt
* QEMU

---

## Runtime Future

* Docker Runtime
* Disposable Runtime
* Cloud Runtime
* Agent Pool
* Multi-Agent Scheduling

---

# 十八、未来 v4/v5 方向（必须预留）

未来会扩展：

* Multi-Agent Runtime
* Task Scheduler
* AI Worker Pool
* Auto PR Workflow
* Self-healing Runtime
* Runtime Orchestration
* AI Coding Cluster

因此：

必须：

* 模块化
* 解耦
* Runtime abstraction
* Workspace abstraction
* Host abstraction

---

# 十九、工程要求（极其重要）

必须：

* 真正可运行
* 不生成伪代码
* 每阶段可执行
* README 完整
* 日志完整
* 错误处理完整
* 幂等
* 可重入
* 支持失败恢复
* 配置集中化
* 不过度耦合

---

# 二十、实现顺序（必须按阶段）

请严格按以下阶段实现：

## Phase 1

* 项目结构
* 配置系统
* install.ps1
* VMware adapter

---

## Phase 2

* Ubuntu autoinstall
* bootstrap system
* SSH bootstrap

---

## Phase 3

* Mutagen integration
* workspace sync
* sync profile

---

## Phase 4

* adp CLI
* runtime lifecycle
* logs

---

## Phase 5

* snapshot system
* rollback
* dangerous runtime

---

## Phase 6

* doctor system
* diagnostics
* recovery flow

---

# 二十一、最终目标（非常重要）

该系统最终目标不是：

# “自动创建 Ubuntu VM”

而是：

# 本地 AI Development Runtime Operating System

即：

一个：

* AI-native
* Runtime-oriented
* Workspace-centric
* Multi-agent-ready
* Sandbox-first

的：

# Local AI Coding Platform

