# ADP-OS 作为 Deer-Flow 的 VM 沙箱后端

> **日期**: 2026-06-05 | **目标读者**: Deer-flow 运维人员、ADP-OS 管理员
> **双语**: 中文 & English | [English version](../integrations/deer-flow-backend.md)
> **来源标签**: [FILE]=源码分析, [LLM]=LLM 推理

将 ADP-OS 配置为 [ByteDance/deer-flow](https://github.com/ByteDance/deer-flow)（70K⭐）硬件 VM 沙箱后端的实践指南。

关于全面的架构参考、缺口分析和接口映射，请参阅 [将 ADP-OS 部署为 Deer-Flow 的 VM 沙箱后端](deer-flow.md)。关于 MCP 服务器快速上手，请参阅 [MCP 配置指南](deer-flow-mcp-setup.md)。关于完整的双路径集成参考，请参阅 [Deer-Flow 集成指南](../deer-flow-integration.md)。

---

## 这是什么

Deer-flow agent 在沙箱中运行代码。默认情况下，这些沙箱是 Docker 容器。ADP-OS 用**硬件隔离的虚拟机**替代 Docker——每个 deer-flow agent 会话获得自己的 VM，拥有真实的 Linux 内核、完整的 root 权限和真正的进程隔离。

```
Deer-Flow Agent
    │
    ├─ "bash: pip install requests"
    ├─ "write_file: /app/main.py"
    └─ "read_file: /app/main.py"
         │
    ┌────▼────────────────────────────────────┐
    │  ADP-OS VM 沙箱后端                      │
    │                                         │
    │  • VM 运行 Ubuntu 24.04                 │
    │  • 真实内核、真实文件系统                  │
    │  • SSH 支持的命令执行                     │
    │  • MCP 协议或直接适配器                    │
    └─────────────────────────────────────────┘
```

提供两种集成路径：

| 路径 | 工作原理 | 适用场景 |
|------|---------|---------|
| **MCP 服务器** | Deer-flow 将 ADP-OS 加载为 MCP 工具提供者（通过 stdio 暴露 26 个工具） | 跨语言、跨机器、MCP 原生工作流 |
| **直接适配器** | Python `DeerFlowADPSandboxProvider` 类实现 deer-flow 的 `SandboxProvider` 抽象基类 | Python 原生 deer-flow 部署，最小协议开销 |

两种路径都提供相同的 8 个 VM 内沙箱操作：执行命令、读写文件、列出目录、glob、grep、下载和上传。

---

## 前置条件

| 要求 | 检查命令 | 说明 |
|------|---------|------|
| ADP-OS 已安装 | `adpos doctor` | 必须返回 "healthy" |
| VMware Workstation | 在 Windows 主机上运行 | VM 配置后端 |
| 至少一个运行时 | `adpos status` | 在 `configs/topology.json` 中配置 |
| Python 3.10+ | `python3 --version` | MCP 服务器和适配器需要 |
| SSH 可达的 VM | `ssh adp@<vm-ip> echo OK` | 默认凭证: `adp`/`adp` |

---

## 路径 1: MCP 服务器后端

Deer-flow 连接到 ADP-OS MCP 服务器作为工具提供者。所有 26 个 MCP 工具——VM 生命周期、工作区管理和 VM 内沙箱操作——对 deer-flow agent 可用。

### 步骤 1: 验证 MCP 服务器

```bash
cd /path/to/ai-dev-platform

# 验证所有 26 个工具已注册
python3 -c "
from cli.mcp.server import mcp
tools = list(mcp._tool_manager._tools.keys())
print(f'MCP 工具数: {len(tools)}')
print(sorted(tools))
"
```

预期: **26 个工具**，分为平台（3）、工作区（10）、运行时（5）和 VM 内沙箱（8）四类。

### 步骤 2: 配置 Deer-Flow

在 deer-flow 项目根目录创建或更新 `extensions_config.json`：

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

**WSL 用户**必须同时设置 `ADP_HOME_WIN` 用于 PowerShell 解析：

```json
{
  "adp_os_sandbox": {
    "type": "stdio",
    "command": "python3",
    "args": [
      "/home/user/ai-dev-platform/cli/mcp/server.py"
    ],
    "env": {
      "ADP_HOME": "/home/user/ai-dev-platform",
      "ADP_HOME_WIN": "D:\\Dev\\ai-dev-platform"
    }
  }
}
```

> **重要**: 所有路径必须使用**绝对路径**。相对路径在 stdio MCP 传输中会失败，因为工作目录不确定。

### 步骤 3: 重启 Deer-Flow

更新 `extensions_config.json` 后，重启 deer-flow。26 个 ADP-OS 工具将出现在 deer-flow 内置工具旁边。

### 步骤 4: 验证后端

在 deer-flow agent 上下文中。以下内容是 MCP/deer-flow 工具调用，不是终端命令：

```
# 启动 VM
adp_up agent

# 检查状态
adp_status agent

# 在 VM 内运行代码
adp_exec agent "python3 --version"

# 读写文件
adp_file_write agent "/tmp/hello.py" "print('Hello from ADP-OS VM!')" plan_only=False
adp_exec agent "python3 /tmp/hello.py"

# 停止 VM
adp_stop agent
```

---

## 路径 2: 直接适配器后端

`DeerFlowADPSandboxProvider` 类直接实现 deer-flow 的 `SandboxProvider` 抽象基类。无 MCP 协议开销——适配器通过 SSH 与 ADP-OS VM 通信。

### 步骤 1: 安装依赖

```bash
pip install paramiko    # SSH 连接管理（推荐）
```

如果 `paramiko` 不可用，适配器自动回退到 subprocess `ssh` + `sshpass`。

### 步骤 2: 配置 Provider

在 deer-flow Python 代码中：

```python
from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider

provider = DeerFlowADPSandboxProvider(
    adp_home="/path/to/ai-dev-platform",   # ADP-OS 安装目录（必需）
    pool_size=2,                            # 预暖 2 个 VM（0 = 禁用）
    ssh_user="adp",                         # VM SSH 用户名
    ssh_password="adp",                     # VM SSH 密码
)

# 预暖 VM 池（可选，后台运行）
provider.warm_pool()
```

### 步骤 3: 使用后端

```python
# 为 deer-flow 线程获取沙箱
sandbox_id = provider.acquire(thread_id="my-thread")

# 获取沙箱句柄
sandbox = provider.get(sandbox_id)

# 在 VM 内执行命令
output = sandbox.execute_command("pip install requests")
print(output)

# 文件操作
sandbox.write_file("/app/main.py", "print('Hello from ADP-OS VM!')")
content = sandbox.read_file("/app/main.py")

# 搜索
entries = sandbox.list_dir("/app", max_depth=1)
matches, truncated = sandbox.grep("/app", "Hello")

# 完成后释放
provider.release(sandbox_id)
```

### Provider 配置参考

| 参数 | 必需 | 默认值 | 说明 |
|------|------|--------|------|
| `adp_home` | 是 | — | ADP-OS 安装目录 |
| `pool_size` | 否 | `0` | 预暖 VM 数量（0 = 禁用） |
| `ssh_user` | 否 | `"adp"` | VM SSH 用户名 |
| `ssh_password` | 否 | `"adp"` | VM SSH 密码 |

### Thread → Runtime 映射

Deer-flow 通过 `thread_id` 标识会话，ADP-OS 通过 `runtime` 名称标识 VM。Provider 在两者之间建立映射：

- 默认: `thread_id=None` → `"agent"` runtime
- 自定义映射持久化到 `~/.adp-deerflow/thread_runtime_registry.json`
- 使用不同的 runtime 名称（`agent`、`frontend`、`backend`、`sandbox`）实现多 agent 隔离

### VM 池预暖

冷 VM 创建需要 15–45 分钟（Ubuntu 自动安装）。预暖可消除此延迟：

```python
provider = DeerFlowADPSandboxProvider(adp_home="...", pool_size=3)
provider.warm_pool()  # 后台: 启动 3 个 VM

# 首次 acquire() 立即返回——VM 已经就绪
sandbox_id = provider.acquire()
```

池 VM 使用 `deerflow-pool-N` 命名。如果池为空，`acquire()` 会自动创建新 VM。

---

## 端到端流程

使用 ADP-OS 作为 VM 后端的 deer-flow agent 会话：
下面的 `adp_*` 名称是 MCP/deer-flow 工具名；本地 shell 命令仍使用 `adpos`。

```
1. Deer-flow agent 启动任务
2. SandboxMiddleware 调用 provider.acquire(thread_id="task-123")
3. ADP-OS 启动（或从池中获取）名为 "agent" 的 VM
4. Provider 返回 sandbox_id → Deer-flow 拥有一个 VM
5. Agent 在 VM 内执行工具:
   - bash        → adp_exec / SSH exec
   - write_file  → adp_file_write / SSH write
   - read_file   → adp_file_read / SSH read
   - glob/grep   → adp_glob / adp_grep / SSH find+grep
6. 任务完成，中间件调用 provider.release(sandbox_id)
7. ADP-OS 停止 VM (adp_stop) 或销毁它 (adp_down)
```

### 性能特征

| 场景 | 延迟 | 说明 |
|------|------|------|
| 池中热 VM | ~5 秒 | VM 已在运行，仅 SSH 握手 |
| 缓存的 VM（之前启动过） | ~30 秒 | VM 开机，Ubuntu 启动 |
| 冷 VM（首次） | 15–45 分钟 | 从 ISO 进行 Ubuntu 自动安装 |
| VM 内命令执行 | <1 秒 | SSH 往返 |

---

## MCP 工具参考（VM 内沙箱）

映射到 deer-flow `Sandbox` 接口的 8 个 SSH 支持的 MCP 工具：

| MCP 工具 | Sandbox 方法 | 描述 |
|----------|-------------|------|
| `adp_exec(runtime, command, timeout=120)` | `execute_command(command)` | 在 VM 内执行 bash 命令 |
| `adp_file_read(runtime, path)` | `read_file(path)` | 从 VM 读取文件内容 |
| `adp_file_write(runtime, path, content, append=False)` | `write_file(path, content, append)` | 向 VM 写入文本文件 |
| `adp_dir_list(runtime, path, max_depth=2)` | `list_dir(path, max_depth)` | 列出目录内容 |
| `adp_glob(runtime, path, pattern)` | `glob(path, pattern)` | 按模式查找文件 |
| `adp_grep(runtime, path, pattern)` | `grep(path, pattern)` | 在文件中搜索文本 |
| `adp_file_download(runtime, path)` | `download_file(path)` | 下载文件（base64） |
| `adp_file_upload(runtime, path, content_base64)` | `update_file(path, content)` | 上传文件（base64） |

---

## 如何选择路径

| 因素 | MCP 服务器 | 直接适配器 |
|------|-----------|-----------|
| 配置复杂度 | 低（仅 JSON 配置） | 中（Python import） |
| 跨语言 | 是（任何 MCP 客户端） | 仅 Python |
| 协议开销 | MCP stdio JSON | 无（直接 SSH） |
| 工具发现 | 自动（MCP `list_tools`） | 手动（文档化接口） |
| VM 池预暖 | 不可用（仅工具） | 是（`pool_size` + `warm_pool()`） |
| Thread→runtime 映射 | 手动（runtime 参数） | 自动（持久化注册表） |
| SSH 连接缓存 | 每次调用 | 缓存的 `SSHConnection` 池 |

**推荐**: 从 MCP 服务器路径开始快速集成。当需要 VM 池预暖、持久 SSH 连接或更低协议开销时，切换到直接适配器路径。

---

## 已知限制

1. **仅限 Windows 主机**: ADP-OS 当前需要 Windows 主机上的 VMware Workstation。
2. **冷启动延迟**: 首次 VM 创建需要 15–45 分钟。通过 VM 池预暖（直接适配器路径）缓解。
3. **无跨 VM 文件系统隔离**: ADP-OS VM 共享同一文件系统。对于并发 agent，使用不同的 runtime 名称。
4. **静态 SSH 凭证**: 默认 `adp`/`adp`。生产环境部署应更改。
5. **单主机**: 所有 VM 在同一 VMware 主机上运行。多主机扩展需要部署多个 ADP-OS 实例。

---

## 下一步

- [MCP 配置指南](deer-flow-mcp-setup.md) — 逐步 MCP 配置
- [Deer-Flow 集成指南](../deer-flow-integration.md) — 完整双路径参考
- [将 ADP-OS 部署为 Deer-Flow 的 VM 沙箱后端](deer-flow.md) — 架构和缺口分析
- [ADP-OS MCP 服务器源码](../../../cli/mcp/server.py) — 参考实现（26 个工具）
- [直接适配器源码](../../../extensions/deer_flow/deerflow_adp_sandbox.py) — `DeerFlowADPSandboxProvider`
- [操作指南](../operations.md) — ADP-OS 日常运行时管理

---

> **来源标签**: [FILE]=源码分析, [LLM]=LLM 推理
