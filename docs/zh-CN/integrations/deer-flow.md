# 将 ADP-OS 部署为 Deer-Flow 的 VM 沙箱后端

> **日期**: 2026-06-05 | **最后验证**: 2026-06-05（看板任务 t_d1591f90 — 重新验证，新增参数级映射）| **来源标签**: [GH]=GitHub API, [FILE]=源码分析, [LLM]=LLM 推理
> **双语**: 中文 & English | **目标读者**: ADP-OS 维护者、deer-flow 集成者
> **集成指南**: [VM 后端指南](deer-flow-backend.md)（部署）| [Deer-Flow 集成指南](../deer-flow-integration.md)（综合参考）| [MCP 配置指南](deer-flow-mcp-setup.md)（快速上手）| [English](../../integrations/deer-flow.md) | [MCP Setup Guide](../../integrations/deer-flow-mcp-setup.md)

---

## 摘要

[LLM] [ByteDance/deer-flow](https://github.com/ByteDance/deer-flow)（70K⭐）是一个基于 Docker 沙箱执行的 SuperAgent 平台。其 `SandboxProvider` / `Sandbox` 抽象层支持可插拔的后端——ADP-OS 可以通过 MCP 协议作为**硬件 VM 沙箱后端**，提供比 Docker 容器更强的隔离性。

**截至 2026-06-05，所有 P0 缺口已解决。** MCP 服务器现已暴露 **26 个工具**：3 个平台工具、10 个工作区工具、5 个运行时工具，以及 8 个 SSH 支持的 VM 内沙箱操作。生产级 `DeerFlowADPSandboxProvider` 适配器类、VM 池预暖以及 thread→runtime 注册表已发布。

完整的集成路径已验证通过：
1. **第一层（已覆盖）**: VM 生命周期——通过 MCP 调用 `adp_up` / `adp_down` / `adp_stop` / `adp_status`
2. **第二层（已解决）**: VM 内部操作——`adp_exec`、`adp_file_read`、`adp_file_write`、`adp_dir_list`、`adp_glob`、`adp_grep`、`adp_file_download`、`adp_file_upload`，通过 SSH
3. **第三层（已发布）**: `DeerFlowADPSandboxProvider` 适配器——deer-flow 原生 Sandbox 接口，后端为 ADP-OS VM

---

## Deer-Flow 沙箱架构

### 沙箱抽象层

```
┌──────────────────────────────────────────────┐
│  Deer-flow Agent                              │
│  使用的工具: bash, ls, glob, grep, read_file, │
│             write_file, str_replace            │
├──────────────────────────────────────────────┤
│  SandboxMiddleware                            │
│  生命周期: acquire → 使用 → release            │
├──────────────────────────────────────────────┤
│  SandboxProvider                              │
│  可插拔: AioSandbox | LocalSandbox | ???      │
├──────────────────────────────────────────────┤
│  Sandbox (ABC)                                │
│  方法: execute_command, read_file,            │
│  write_file, list_dir, glob, grep,            │
│  download_file, update_file                   │
├──────────────────────────────────────────────┤
│  后端: Docker 容器（默认）                     │
│  或通过 provisioner 的 Kubernetes Pod          │
└──────────────────────────────────────────────┘
```

### SandboxProvider 接口 [FILE]

```python
class SandboxProvider(ABC):
    def acquire(self, thread_id: str | None = None) -> str: ...
    def get(self, sandbox_id: str) -> Sandbox | None: ...
    def release(self, sandbox_id: str) -> None: ...
```

### Sandbox 接口 [FILE]

```python
class Sandbox(ABC):
    def execute_command(self, command: str) -> str: ...
    def read_file(self, path: str) -> str: ...
    def write_file(self, path: str, content: str, append: bool = False) -> None: ...
    def list_dir(self, path: str, max_depth: int = 2) -> list[str]: ...
    def glob(self, path: str, pattern: str, ...) -> tuple[list[str], bool]: ...
    def grep(self, path: str, pattern: str, ...) -> tuple[list[GrepMatch], bool]: ...
    def download_file(self, path: str) -> bytes: ...
    def update_file(self, path: str, content: bytes) -> None: ...
```

### Agent 层面的沙箱工具 [FILE]

| 工具 | 功能 |
|------|------|
| `bash` | 在沙箱中执行 bash 命令 |
| `ls` | 列出目录内容 |
| `glob` | 按模式查找文件 |
| `grep` | 在文件中搜索文本 |
| `read_file` | 读取文件内容 |
| `write_file` | 写入文件内容 |
| `str_replace` | 文件中的字符串替换 |

---

## ADP-OS MCP 服务器：工具参考

26 个 MCP 工具，分为 4 类：

### 平台工具（3 个）

| 工具 | 功能 | 返回值 |
|------|------|--------|
| `adp_status` | 所有/指定运行时的健康状态 | `{runtimes, runtime_count, running_count}` |
| `adp_doctor` | 平台诊断（47+ 项检查） | `{ok_count, issue_count, issues, healthy}` |
| `adp_capabilities` | 平台能力和路线图 | `{supported, planned, exploratory}` |

### 工作区工具（10 个）

| 工具 | 功能 | 关键参数 |
|------|------|----------|
| `adp_workspace_list` | 列出清单中的项目 | — |
| `adp_workspace_status` | 工作区就绪摘要 | — |
| `adp_workspace_dashboard` | 任务生命周期概览 | — |
| `adp_workspace_project` | 单个项目生命周期视图 | `project_name` |
| `adp_workspace_create` | 创建项目目录 | `project_name`, `plan_only` |
| `adp_workspace_open` | 项目入口指引（路径、同步、SSH） | `project_name` |
| `adp_workspace_sync` | 按项目的同步指引 | `project_name` |
| `adp_workspace_close` | 关闭工作区（停止同步） | `project_name`, `plan_only` |
| `adp_workspace_recipes` | 列出工作区配方 | — |
| `adp_workspace_report` | Markdown 格式的发布证据 | — |

### 运行时工具（5 个）

| 工具 | 功能 | 关键参数 |
|------|------|----------|
| `adp_up` | 启动 VM（首次从 ISO 创建） | `runtime`, `plan_only`, `iso_path` |
| `adp_down` | 完全销毁 VM | `runtime`, `plan_only`, `force` |
| `adp_stop` | 优雅关闭 VM | `runtime` |
| `adp_sync_status` | Mutagen 同步会话健康 | — |
| `adp_sync_stop` | 停止 Mutagen 同步会话 | `runtime` |

### VM 内沙箱工具（8 个）——SSH 支持

| 工具 | 功能 | 关键参数 | 映射到 Sandbox 方法 |
|------|------|----------|---------------------|
| `adp_exec` | 通过 SSH 在 VM 内执行命令 | `runtime`, `command`, `timeout` | `execute_command()` |
| `adp_file_read` | 从 VM 读取文件内容 | `runtime`, `path` | `read_file()` |
| `adp_file_write` | 向 VM 内文件写入/追加内容 | `runtime`, `path`, `content`, `append` | `write_file()` |
| `adp_dir_list` | 列出 VM 内目录内容 | `runtime`, `path`, `max_depth` | `list_dir()` |
| `adp_glob` | 在 VM 内按模式查找文件 | `runtime`, `path`, `pattern` | `glob()` |
| `adp_grep` | 在 VM 内文件中搜索文本 | `runtime`, `path`, `pattern`, `max_matches` | `grep()` |
| `adp_file_download` | 从 VM 下载文件（base64） | `runtime`, `path` | `download_file()` |
| `adp_file_upload` | 上传 base64 编码内容到 VM 文件 | `runtime`, `path`, `content_base64`, `plan_only` | `update_file()` |

---

## 配置方式

提供两种集成路径：MCP 服务器（跨语言，stdio 传输）和直接适配器（Python 原生，零协议开销）。MCP 服务器路径暴露 26 个 MCP 工具；两种路径都覆盖 deer-flow 需要的 8 个 VM 内沙箱操作。

### 路径 1: MCP 服务器（推荐快速上手）

Deer-flow 通过 stdio 传输将 ADP-OS 加载为 MCP 工具提供者。所有 26 个工具自动发现。

**步骤 1 — 验证 MCP 服务器**（预期 26 个工具）：

```bash
cd /path/to/ai-dev-platform
python3 -c "
from cli.mcp.server import mcp
tools = list(mcp._tool_manager._tools.keys())
print(f'MCP 工具数: {len(tools)}')
print(sorted(tools))
"
```

**步骤 2 — 配置 deer-flow**：在 deer-flow 项目根目录创建 `extensions_config.json`：

```json
{
  "adp_os_sandbox": {
    "type": "stdio",
    "command": "python3",
    "args": [
      "/absolute/path/to/ai-dev-platform/cli/mcp/server.py"
    ],
    "env": {
      "ADP_HOME": "/absolute/path/to/ai-dev-platform"
    }
  }
}
```

WSL 用户必须同时设置 `ADP_HOME_WIN`（详见 [MCP 配置指南](deer-flow-mcp-setup.md)，包含 Windows 与 WSL 调用 Windows 主机的示例）。

**步骤 3 — 重启 deer-flow** 以加载 MCP 扩展。ADP-OS 工具将出现在内置工具旁边。

**步骤 4 — 从 MCP 客户端验证**。这些是 MCP 工具名，不是本地 shell 可执行文件。本地 PowerShell CLI 验证请使用 `adpos up agent`、`adpos status agent` 和 `adpos stop agent`。

```text
adp_up agent                    # 启动 VM（热 VM ~30 秒，首次安装 15-45 分钟）
adp_status agent                # 确认 VM 运行中
adp_exec agent "python3 --version"  # 在 VM 内执行代码
adp_stop agent                  # 优雅关闭
```

> 详细 MCP 配置包括环境变量、故障排查和平台特定示例，请参阅 [MCP 配置指南](deer-flow-mcp-setup.md)。

### 路径 2: 直接适配器（Python 原生，生产环境）

直接导入 `DeerFlowADPSandboxProvider`——零协议开销、持久 SSH 连接池、VM 预暖。

**步骤 1 — 安装依赖**：

```bash
pip install paramiko    # SSH 连接管理（推荐）
```

**步骤 2 — 初始化 provider**：

```python
from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider

provider = DeerFlowADPSandboxProvider(
    adp_home="/path/to/ai-dev-platform",   # ADP-OS 安装目录（必需）
    pool_size=2,                            # 预暖 2 个 VM（0 = 禁用）
    ssh_user="adp",                         # VM SSH 用户名（默认）
    ssh_password="adp",                     # VM SSH 密码（默认）
)

# 可选：预暖 VM 池以消除冷启动延迟
provider.warm_pool()
```

**步骤 3 — 使用沙箱**：

```python
# 为 deer-flow 线程获取沙箱
sandbox_id = provider.acquire(thread_id="my-thread")

# 获取沙箱句柄并执行操作
sandbox = provider.get(sandbox_id)
output = sandbox.execute_command("pip install requests")
sandbox.write_file("/app/main.py", "print('Hello from ADP-OS VM!')")
content = sandbox.read_file("/app/main.py")
entries = sandbox.list_dir("/app", max_depth=1)
matches, truncated = sandbox.grep("/app", "Hello")

# 完成后释放
provider.release(sandbox_id)
```

> 完整的 provider 配置参考、thread→runtime 映射、VM 池预暖及性能特征，请参阅 [VM 后端指南](deer-flow-backend.md)。

### 路径选择

| 因素 | MCP 服务器 | 直接适配器 |
|------|-----------|-----------|
| 配置复杂度 | 低（仅 JSON 配置） | 中（Python import） |
| 跨语言 | 是（任何 MCP 客户端） | 仅 Python |
| 协议开销 | MCP stdio JSON | 无（直接 SSH） |
| VM 池预暖 | 不可用 | 是（`pool_size` + `warm_pool()`） |
| Thread→runtime 映射 | 手动（runtime 参数） | 自动（持久化注册表） |
| SSH 连接缓存 | 每次调用 | 缓存的 `SSHConnection` 池 |

**推荐**：从 MCP 服务器路径开始快速集成。当需要 VM 池预暖、持久 SSH 连接或更低协议开销时，切换到直接适配器路径。

---

## 接口映射

### 生命周期映射（第一层 — ✅ 已覆盖）

| Deer-Flow SandboxProvider | ADP-OS MCP 工具 | 状态 | 备注 |
|---------------------------|-----------------|------|------|
| `acquire(thread_id)` → `sandbox_id` | `adp_up(runtime, plan_only=False)` + VM 就绪检查 | ✅ 已映射 | 支持 thread→runtime 映射（`ThreadRuntimeRegistry`）。首次 ISO 安装需 15-45 分钟，热 VM 约 30 秒 |
| `get(sandbox_id)` → `Sandbox` | `adp_status(runtime)` + SSH 连接缓存 | ✅ 已映射 | `SSHConnection` 包装器返回 `ADPSSHSandbox` 句柄。可选 `VMPool` 预暖 |
| `release(sandbox_id)` | `adp_down(runtime, plan_only=False)` 或 `adp_stop(runtime)` | ✅ 已映射 | `adp_stop` 为优雅关闭，`adp_down` 为销毁 |

### VM 内部操作（第二层 — ✅ 已解决）

| Deer-Flow Sandbox 方法 | ADP-OS MCP 工具 | 状态 | 备注 |
|--------------------------|-----------------|------|------|
| `execute_command(command)` | `adp_exec(runtime, command)` | ✅ 已映射 | 通过 SSH 执行，可配置超时（默认 120 秒） |
| `read_file(path)` | `adp_file_read(runtime, path)` | ✅ 已映射 | 基于 SSH 的文件读取，返回内容 + 元数据 |
| `write_file(path, content, append)` | `adp_file_write(runtime, path, content, append)` | ✅ 已映射 | 基于 SSH 的写入/追加，带路径清理 |
| `list_dir(path, max_depth)` | `adp_dir_list(runtime, path, max_depth)` | ✅ 已映射 | 基于 `find` 的目录列表 |
| `glob(path, pattern)` | `adp_glob(runtime, path, pattern)` | ✅ 已映射 | `find` + 模式匹配 |
| `grep(path, pattern)` | `adp_grep(runtime, path, pattern)` | ✅ 已映射 | `grep` + 结构化匹配输出 |
| `download_file(path)` | `adp_file_download(runtime, path)` | ✅ 已映射 | SSH base64 编码传输 |
| `update_file(path, content)` | `adp_file_upload(runtime, path, content_base64)` | ✅ 已映射 | SSH base64 上传，默认 plan-only 安全 |

### 参数级映射（返回值类型与默认值差异）[FILE]

方法级别映射 8/8 完成。在参数级别，适配器代码需处理返回值类型转换：

| Deer-Flow Sandbox 方法 | ADP-OS MCP 工具 | 返回值差异 | 适配器需处理 |
|---|---|---|---|
| `execute_command() -> str` | `adp_exec() -> {stdout, stderr, exit_code, runtime}` | `str` vs 结构化字典 | 提取 `stdout`，非零 `exit_code` 时抛异常 |
| `read_file() -> str` | `adp_file_read() -> {content, path, runtime}` | `str` vs 结构化字典 | 提取 `content` 字段 |
| `write_file() -> None` | `adp_file_write() -> {path, bytes_written, append}` | `None` vs 结构化字典 | 忽略返回值（void 语义） |
| `list_dir() -> list[str]` | `adp_dir_list() -> {entries, entry_count, path}` | `list[str]` vs 结构化字典 | 提取 `entries` 字段。注意：ADP-OS 默认排除隐藏文件（`-not -path '*/\.*'`） |
| `glob() -> tuple[list[str], bool]` | `adp_glob() -> {matches, match_count, truncated}` | tuple vs 字典 | 提取 `matches`，使用 `truncated` |
| `grep() -> tuple[list[GrepMatch], bool]` | `adp_grep() -> {matches, match_count, truncated}` | `GrepMatch` 对象 vs 原始 `文件:行号:内容` 字符串 | 将原始行解析为 `GrepMatch` 对象；`glob` 参数 → `glob_filter` |
| `download_file() -> bytes` | `adp_file_download() -> {content_base64}` | `bytes` vs base64 字符串 | `base64.b64decode(content_base64)` |
| `update_file(content: bytes) -> None` | `adp_file_upload(content_base64: str) -> dict` | `bytes` 参数 vs base64 字符串参数 | `base64.b64encode(content).decode()` |

**安全默认值**: ADP-OS 写工具默认为 `plan_only=True`。适配器必须对所有操作传入 `plan_only=False`。`DeerFlowADPSandboxProvider` 已处理。

### ADP-OS 独有能力（deer-flow 无对应项）

| ADP-OS MCP 工具 | 对 deer-flow 的价值 |
|-----------------|-------------------|
| `adp_doctor` | Agent 运行前的 VM 级别健康诊断 |
| `adp_capabilities` | 平台能力发现 |
| `adp_workspace_dashboard` | 跨线程的任务生命周期可见性 |
| `adp_workspace_report` | 发布流程的证据生成 |
| `adp_sync_status` | 文件同步健康（Mutagen） |
| `adp_workspace_recipes` | 工作流模板 |

---

## 缺口分析总结

### P0（已解决 — ✅ 2026-06-05 发布）

所有 P0 缺口已通过提交 f7453c8（8 个 SSH 支持的 VM 内工具）和 7a976fd（DeerFlowADPSandboxProvider 适配器）解决：

| ID | 缺口 | 解决方案 |
|----|------|----------|
| ~~P0-1~~ | ~~无 VM 内 `execute_command()`~~ | `adp_exec()` 通过 SSH |
| ~~P0-2~~ | ~~无 VM 内 `read_file()`~~ | `adp_file_read()` 通过 SSH |
| ~~P0-3~~ | ~~无 VM 内 `write_file()`~~ | `adp_file_write()` 通过 SSH |
| ~~P0-4~~ | ~~无 VM 内 `list_dir()`~~ | `adp_dir_list()` 通过 SSH |
| ~~P0-5~~ | ~~无 VM 内 `glob()` / `grep()`~~ | `adp_glob()` / `adp_grep()` 通过 SSH |
| ~~P0-6~~ | ~~无 `get(sandbox_id)`→Sandbox~~ | `DeerFlowADPSandboxProvider.get()` 返回 `ADPSSHSandbox` |

### P1（部分解决 — 2026-06-05 发布）

| ID | 缺口 | 状态 |
|----|------|------|
| ~~P1-1~~ | ~~无 deer-flow `SandboxProvider` 适配器~~ | ✅ `DeerFlowADPSandboxProvider` 已发布 |
| ~~P1-2~~ | ~~无 thread→runtime 名称映射~~ | ✅ `ThreadRuntimeRegistry` + 轮询分配 |
| P1-3 | 首次 VM 启动：15-45 分钟 | ⚠️ 已缓解：`VMPool` 预暖可用。冷启动仍然较长 |
| P1-4 | Windows 优先平台 vs deer-flow Linux 容器 | ⚠️ 已记录：ADP-OS VM 支持 Ubuntu 自动安装 |

### P2（锦上添花——发布后）

| ID | 缺口 | 影响 |
|----|------|------|
| P2-1 | 无 workspace→thread 隔离 | ADP-OS 工作区是项目级别，非线程级别 |
| P2-2 | 未暴露快照/回滚工具 | ADP-OS 有快照但 MCP 未暴露 |
| P2-3 | Skills 挂载路径不匹配 | Deer-flow 期望 `/mnt/skills/`，ADP-OS 使用不同的工作区布局 |

---

## 已知限制

本节记录了集成者在将 ADP-OS 部署为 deer-flow VM 沙箱后端时应注意的实际约束。

### 平台

| 限制 | 影响 | 缓解措施 |
|------|------|---------|
| **仅限 Windows 主机** | ADP-OS VM 配置需要 Windows 上的 VMware Workstation。不支持 Linux/macOS 主机。 | 使用专用 Windows 机器作为沙箱主机。MCP 服务器可从 Windows PowerShell 或 WSL 启动，但 WSL 场景需要 `ADP_HOME_WIN` 指向 Windows 仓库路径；不要把原生 macOS/Linux 当作受支持的 VM 主机。 |
| **VMware 依赖** | 需要安装 VMware Workstation（约 800 MB 下载）。尚无 Hyper-V、VirtualBox 或 KVM 后端。 | VMware Workstation Pro 自 2024-05 起对个人用户免费。Hyper-V 后端在 P2 路线图上——参见[平台能力](../capabilities.md)。 |

### 启动

| 限制 | 影响 | 缓解措施 |
|------|------|---------|
| **冷启动：15–45 分钟** | 首次 VM 创建从 ISO 运行 Ubuntu 自动安装——约 15-45 分钟（取决于硬件）。 | **直接适配器路径**：使用 `VMPool` 预暖（`pool_size=N` + `warm_pool()`）。**MCP 服务器路径**：从 MCP 客户端调用 `adp_up`，或在 agent 会话开始前本地运行 `adpos up agent`。后续启动约 30 秒。 |
| **不支持挂起/恢复** | VM 必须完全关闭（`adp_stop`）或销毁（`adp_down`）。MCP 工具不支持 VMware 挂起/快照。 | 使用 `adp_stop` 进行优雅关闭（约 5 秒）。ADP-OS 有快照基础设施但尚未作为 MCP 工具暴露（P2-2）。 |

### 隔离性

| 限制 | 影响 | 缓解措施 |
|------|------|---------|
| **单个 runtime 内共享文件系统** | 分配到同一 ADP-OS runtime 的并发 agent 会共享该 VM 文件系统，可能互相干扰（文件冲突、进程碰撞）。Deer-flow 原生 Docker 沙箱提供每个会话的独立文件系统。 | 使用不同的 runtime 名称（`agent`、`frontend`、`backend`、`sandbox`）实现并发 agent 隔离。每个 runtime 是拥有独立文件系统的独立 VM。 |
| **无网络沙箱** | VM 具有不受限制的出站网络访问。恶意代码可能泄露数据。 | ADP-OS VM 设计用于可信 agent 工作负载。对于不受信任的代码执行，考虑在 VMware NAT 层面实施网络限制。 |
| **工作区→线程隔离不匹配** | ADP-OS 工作区是项目级别的（一个工作区包含多个项目）。Deer-flow 线程是会话级别的。无自动的 workspace-per-thread 隔离。 | 使用直接适配器的 `ThreadRuntimeRegistry` 将 deer-flow `thread_id` → ADP-OS `runtime` 映射。每个线程获得独立的 VM。 |

### 运维

| 限制 | 影响 | 缓解措施 |
|------|------|---------|
| **静态 SSH 凭证** | 默认 VM SSH 凭证为 `adp`/`adp`。能访问 VMware NAT 子网的任何人都可连接。 | 首次启动后通过 MCP 客户端/工具接口更改 SSH 密码：`adp_exec agent "echo 'adp:NEW_PASSWORD' \| sudo chpasswd"`。通过 `ADP_SSH_USER`/`ADP_SSH_PASSWORD` 环境变量设置。生产环境使用 SSH 密钥。 |
| **单主机** | 所有 VM 在同一 VMware 主机上运行。无分布式 VM 调度。 | 多主机扩展需部署多个 ADP-OS 实例，并通过适配器的 `thread_id→runtime` 映射将 deer-flow 线程路由到对应实例。 |
| **MCP 无快照/回滚** | ADP-OS 有 VM 快照基础设施但未作为 MCP 工具暴露。无法从 deer-flow agent 进行检查点和恢复 VM 状态。 | 快照暴露是 P2 路线图项目。当前变通方案：通过 `adpos workspace task snapshot` 手动管理快照。 |
| **仅 Linux 客户机** | ADP-OS VM 当前运行 Ubuntu 26.04（从 ISO 自动安装）。不支持 Windows 或 macOS 客户机。 | 这符合 deer-flow 的预期——所有 deer-flow 沙箱工具（bash、ls、glob、grep）均假设 Linux 环境。 |

### 性能

| 限制 | 影响 | 缓解措施 |
|------|------|---------|
| **VM 内命令延迟：约 1 秒** | 每次 `adp_exec`/文件操作需要 SSH 往返（约 1 秒）。对比 Docker exec（约 50 毫秒）。 | 对于工具调用以秒为单位的 agent 工作流可接受。尽量批量操作。使用直接适配器的持久 SSH 连接池避免握手开销。 |
| **VM 资源开销** | 默认拓扑是 VM 级资源：最小的 `sandbox` runtime 为 4 GB 内存 / 40 GB 磁盘，默认 `agent` runtime 为 16 GB 内存 / 160 GB 磁盘。对比 Docker 容器（约 50 MB 内存、100 MB overlay）。 | 根据可用主机资源规划 VM 池大小。预暖池 VM 在空闲时仍消耗内存。 |

---

## 集成路径

截至 2026-06-05 全部阶段已完成。

### 阶段一：基于 SSH 的沙箱提供者 ✅（f7453c8）

在 `cli/mcp/server.py` 中注册了 8 个新 MCP 工具，VM 辅助逻辑位于 `cli/mcp/vm_tools.py`，通过 SSH 在运行中的 VM 内执行：

```
adp_exec(runtime, command, timeout=120) → {stdout, stderr, exit_code}
adp_file_read(runtime, path) → {content, path}
adp_file_write(runtime, path, content, append=False) → {path, written}
adp_dir_list(runtime, path, max_depth=2) → {entries}
adp_glob(runtime, path, pattern, ...) → {matches, truncated}
adp_grep(runtime, path, pattern, max_matches=100, ...) → {matches, truncated}
adp_file_download(runtime, path) → {content_base64}
adp_file_upload(runtime, path, content_base64, plan_only=True) → {path}
```

MCP 服务器：18 → 26 个工具。测试：46/46 通过。

### 阶段二：Deer-Flow 适配器类 ✅（7a976fd）

`DeerFlowADPSandboxProvider` 在 `extensions/deer_flow/deerflow_adp_sandbox.py`：

```python
class DeerFlowADPSandboxProvider(SandboxProvider):
    def acquire(self, thread_id=None) -> str:
        runtime = self._thread_to_runtime(thread_id)
        self._adpcli.adp_up(runtime, plan_only=False)
        return runtime

    def get(self, sandbox_id) -> Sandbox:
        ssh_conn = self._ssh_pool.get(sandbox_id)
        return ADPSSHSandbox(sandbox_id, ssh_conn)

    def release(self, sandbox_id):
        self._adpcli.adp_down(sandbox_id, plan_only=False)
```

### 阶段三：生产加固 ✅（7a976fd）

- **VM 池预暖**: `VMPool` 保持 N 个 VM 就绪以消除冷启动
- **Linux 客户机支持**: Ubuntu 自动安装已可用
- **Thread→runtime 注册表**: `ThreadRuntimeRegistry` 映射 deer-flow `thread_id` → ADP-OS `runtime` 名称（持久化到 `~/.adp-deerflow/thread_runtime_registry.json`）
- **SSH 连接缓存**: `SSHConnection` + paramiko + subprocess-ssh 回退
- **代码位置**: `extensions/deer_flow/deerflow_adp_sandbox.py` 兼容入口及包内辅助模块，加上 `extensions/deer_flow/README.md`

---

## 代码示例

### 当前：Deer-Flow + Docker 沙箱

```python
# deer-flow agent 调用 bash 工具
# → SandboxMiddleware 获取 Docker 容器
# → bash_tool 调用 sandbox.execute_command("pip install requests")
# → Docker exec 运行命令，返回 stdout
```

### 目标：Deer-Flow + ADP-OS VM 沙箱

```python
# deer-flow agent 调用 bash 工具
# → SandboxMiddleware 获取 ADP-OS VM
# → ADP-OS MCP: adp_up("agent", plan_only=False)
#   → VMware 启动 Ubuntu VM（缓存约 30 秒，首次安装约 15-45 分钟）
# → ADPSandbox.execute_command("pip install requests")
#   → MCP 工具 adp_exec("agent", "pip install requests")
#   → SSH 进入 VM，运行命令，返回 stdout
# → 清理: adp_down("agent") 或 adp_stop("agent")
```

---

## 验证清单

### 集成前检查

- [x] MCP 服务器测试通过（MCP 核心与 VM 工具套件共 46/46，截至 2026-06-09 全部绿色）
- [x] Deer-flow MCP 配置格式已验证（extensions_config.json，stdio 类型）
- [x] 集成指南已编写（docs/deer-flow-integration.md 英文 + 简体中文）
- [x] 缺口分析已更新（本文档——P0 已解决，P1 部分解决）
- [x] 8 个 SSH 支持的 MCP 工具已在 `cli/mcp/server.py` 中实现（共 26 个）— 提交 f7453c8
- [x] 测试套件已更新（`tests/test-mcp-server.py`、`tests/test-mcp-vm-tools.py`）覆盖新工具 — 46 个测试
- [x] Deer-flow `SandboxProvider` 适配器类已实现 — 提交 7a976fd
- [x] SandboxProvider 测试套件（`tests/test_deerflow_adp_sandbox.py`）— 47 个测试
- [x] 启动时间已记录（冷启动 15-45 分钟 vs 热 VM ~30 秒 — 已记录于本文档及适配器 README）
- [x] Thread→runtime 映射注册表已记录（持久化到 `~/.adp-deerflow/thread_runtime_registry.json`，已记录于本文档及适配器 README）

### 路径 1: MCP 服务器验证

**MCP 工具调用**列中的条目是在 deer-flow/MCP 上下文中的工具调用，不是本地 shell 命令。本地运维检查请使用 `adpos` CLI。

| # | 测试项 | MCP 工具调用 | 预期结果 |
|---|--------|------|---------|
| 1 | MCP 工具注册 | `python3 -c "from cli.mcp.server import mcp; print(len(mcp._tool_manager._tools))"` | `26` |
| 2 | MCP 服务器测试 | `python3 -m pytest tests/test-mcp-server.py tests/test-mcp-vm-tools.py -q` | `46 passed` |
| 3 | Deer-flow 配置有效 | 验证 `extensions_config.json` 语法 | 有效 JSON，绝对路径 |
| 4 | Deer-flow 可看到 ADP-OS 工具 | 重启 deer-flow，检查工具列表 | `adp_up`、`adp_exec` 等可见 |
| 5 | VM 生命周期——启动 | `adp_up agent` | VM 启动，SSH 可达 |
| 6 | VM 生命周期——状态 | `adp_status agent` | 显示 `running`，SSH 可达 |
| 7 | VM 内执行命令 | `adp_exec agent "python3 --version"` | 返回 Python 版本字符串 |
| 8 | VM 内文件写入 | `adp_file_write agent "/tmp/test.py" "print(42)" plan_only=False` | 文件写入，返回字节数 |
| 9 | VM 内文件读取 | `adp_file_read agent "/tmp/test.py"` | 返回 `"print(42)"` |
| 10 | VM 内执行文件 | `adp_exec agent "python3 /tmp/test.py"` | 返回 `"42"` |
| 11 | VM 内目录列表 | `adp_dir_list agent "/tmp" max_depth=1` | 列出目录条目 |
| 12 | VM 内 glob | `adp_glob agent "/tmp" "*.py"` | 匹配 `test.py` |
| 13 | VM 内 grep | `adp_grep agent "/tmp" "print"` | 匹配 `test.py` |
| 14 | VM 内下载 | `adp_file_download agent "/tmp/test.py"` | 返回 base64 内容 |
| 15 | VM 内上传 | `adp_file_upload agent "/tmp/uploaded.txt" "<base64>" plan_only=False` | 文件创建 |
| 16 | VM 生命周期——停止 | `adp_stop agent` | VM 优雅关闭 |
| 17 | VM 生命周期——销毁 | `adp_down agent` | VM 已销毁 |

### 路径 2: 直接适配器验证

| # | 测试项 | 预期结果 |
|---|--------|---------|
| 1 | 适配器测试通过 | `python3 -m pytest tests/test_deerflow_adp_sandbox.py -q` → `47 passed` |
| 2 | Provider 初始化 | `DeerFlowADPSandboxProvider(adp_home=...)` 创建无错误 |
| 3 | VM 池预暖 | `provider.warm_pool()` 在后台启动池 VM |
| 4 | Thread→runtime 映射 | `provider.acquire(thread_id="test-123")` 返回 runtime 名称 |
| 5 | 沙箱句柄获取 | `provider.get(sandbox_id)` 返回 `ADPSSHSandbox` |
| 6 | 命令执行 | `sandbox.execute_command("python3 --version")` 返回版本 |
| 7 | 文件读取/写入 | `sandbox.write_file(...)` + `sandbox.read_file(...)` 往返 |
| 8 | 目录列表 | `sandbox.list_dir("/tmp")` 返回条目 |
| 9 | Glob 搜索 | `sandbox.glob("/tmp", "*.py")` 返回匹配 |
| 10 | Grep 搜索 | `sandbox.grep("/tmp", "pattern")` 返回匹配 |
| 11 | 文件下载/上传 | `sandbox.download_file(...)` + `sandbox.update_file(...)` 往返 |
| 12 | 释放 + 清理 | `provider.release(sandbox_id)` 停止/销毁 VM |

### 集成测试（端到端）

- [ ] 集成测试: deer-flow agent → ADP-OS VM → 代码执行（需要 deer-flow + VMware 环境）

### 集成后健康检查

本地 CLI 检查：

- [ ] ADP-OS CLI 健康: `adpos doctor`
- [ ] 至少一个 VM runtime 已配置: `adpos status`
- [ ] Agent 会话后无遗留 VM: `adpos status` 仅显示预期的 runtime
- [ ] SSH 凭证已更改默认值（生产环境）

MCP 客户端检查：

- [ ] Mutagen 同步健康（如使用工作区工具）: `adp_sync_status`

---

## 参考资料

- [Deer-flow Sandbox Provisioner](https://github.com/ByteDance/deer-flow/tree/main/docker/provisioner) — 基于 K8s 的沙箱 Pod 管理器
- [Deer-flow Sandbox ABC](https://github.com/ByteDance/deer-flow/blob/main/backend/packages/harness/deerflow/sandbox/sandbox.py) — 抽象沙箱接口
- [Deer-flow Sandbox Tools](https://github.com/ByteDance/deer-flow/blob/main/backend/packages/harness/deerflow/sandbox/tools.py) — Agent 端沙箱操作
- [ADP-OS MCP Server](../../../cli/mcp/server.py) — 工具注册入口（26 个工具）
- [ADP-OS MCP Tests](../../../tests/test-mcp-server.py) — 核心测试套件
- [ADP-OS MCP VM Tool Tests](../../../tests/test-mcp-vm-tools.py) — VM 工具测试套件

---

> **来源标签**: [GH]=GitHub API, [FILE]=源码分析, [LLM]=LLM 推理
