# Deer-Flow ADP-OS 集成指南

> **日期**: 2026-06-05 | **目标读者**: Deer-flow 集成者、ADP-OS 运维人员
> **双语**: 中文 & English | [English version](../deer-flow-integration.md)

将 [ByteDance/deer-flow](https://github.com/ByteDance/deer-flow)（70K⭐）与 ADP-OS VM 连接作为硬件虚拟机沙箱后端的实践配置指南。

关于架构分析和缺口跟踪，参见[将 ADP-OS 部署为 Deer-Flow VM 沙箱后端](integrations/deer-flow.md)。

---

## 概述

ADP-OS 为 deer-flow 提供**两种集成方式**：

| 方式 | 原理 | 适用场景 |
|------|------|----------|
| **MCP 服务器**（推荐） | Deer-flow 通过 MCP 协议连接 ADP-OS MCP 服务器，26 个工具通过 stdio MCP 传输暴露 | Deer-flow agent 支持 MCP 协议。跨语言、跨机器。 |
| **直接适配器** | `DeerFlowADPSandboxProvider` Python 类直接导入，实现 deer-flow `SandboxProvider` ABC | Python 原生的 deer-flow 集成，协议开销最小。 |

两种方式提供相同的沙箱能力：VM 生命周期管理（acquire/release）+ 8 个 VM 内操作（exec、文件读写、目录列表、glob、grep、下载、上传）。

---

## 前置条件

- **ADP-OS 已安装**在 Windows 主机上，带 VMware Workstation
  - 验证：`adpos doctor` 返回 healthy
- **至少一个 VM 运行时**在 `configs/topology.json` 中配置
  - 测试：`adpos up agent`
- **SSH 可访问 VM**（VMware NAT 子网端口 22）
  - 默认凭据：`adp` / `adp`（Ubuntu 自动安装时设置）
- **Python 3.10+** 和 **PowerShell 7+** 在集成主机上
- （可选）`paramiko` 以获得更好的 SSH 连接管理：`pip install paramiko`

---

## 方式一：MCP 服务器集成（推荐）

Deer-flow 通过 stdio 传输将 ADP-OS MCP 服务器连接为 MCP 工具提供者。所有 26 个工具对 deer-flow agent 可用。

### 第一步：验证 ADP-OS MCP 服务器

```bash
cd /path/to/ai-dev-platform

# 验证 MCP 服务器模块加载，26 个工具正确注册
python3 -c "
from cli.mcp.server import mcp
tools = list(mcp._tool_manager._tools.keys())
print(f'MCP tools registered: {len(tools)}')
print(f'Tool names: {sorted(tools)}')
"
```

预期输出：26 个工具，分为 4 类（平台、工作区、运行时、VM 内沙箱）。

### 第二步：配置 Deer-Flow MCP 扩展

在 deer-flow 项目根目录创建或更新 `extensions_config.json`：

```json
{
  "adp_os_sandbox": {
    "type": "stdio",
    "command": "python",
    "args": [
      "/absolute/path/to/ai-dev-platform/cli/mcp/server.py"
    ],
    "env": {
      "ADP_HOME": "/absolute/path/to/ai-dev-platform",
      "ADP_HOME_WIN": "D:\\Dev\\ai-dev-platform"
    }
  }
}
```

**环境变量**：

| 变量 | 必需 | 说明 |
|------|------|------|
| `ADP_HOME` | 是 | ADP-OS 安装目录（Linux/WSL 路径） |
| `ADP_HOME_WIN` | 仅 WSL | ADP-OS Windows 路径，用于调用 PowerShell |
| `ADP_SSH_USER` | 否 | VM SSH 用户（默认：`adp`） |
| `ADP_SSH_PASSWORD` | 否 | VM SSH 密码（默认：`adp`） |

### 第三步：重启 Deer-Flow

重启 deer-flow 以加载 MCP 扩展。ADP-OS 工具会出现在 deer-flow agent 的工具列表中。

### 第四步：验证集成

在 deer-flow 中，验证工具已注册：

```
# Agent 应该看到以下 MCP 工具名：
adp_status, adp_up, adp_down, adp_stop, adp_exec,
adp_file_read, adp_file_write, adp_dir_list, adp_glob, adp_grep,
adp_file_download, adp_file_upload, ...
```

用简单的 VM 生命周期测试。以下内容是 MCP/deer-flow 工具调用，不是终端命令；本地 shell 验证请使用 `adpos up agent`、`adpos status agent` 和 `adpos stop agent`。

```
adp_up agent                     # 启动 VM（首次：15-45 分钟，热 VM：~30 秒）
adp_status agent                 # 验证 VM 正在运行
adp_exec agent "python --version"  # 在 VM 中执行命令
adp_stop agent                   # 优雅关闭
```

### MCP 工具参考

26 个工具，4 类：

| 类别 | 工具 | 数量 |
|------|------|------|
| **平台** | `adp_status`、`adp_doctor`、`adp_capabilities` | 3 |
| **工作区** | `adp_workspace_list`、`adp_workspace_status`、`adp_workspace_dashboard`、`adp_workspace_project`、`adp_workspace_create`、`adp_workspace_open`、`adp_workspace_sync`、`adp_workspace_close`、`adp_workspace_recipes`、`adp_workspace_report` | 10 |
| **运行时** | `adp_up`、`adp_down`、`adp_stop`、`adp_sync_status`、`adp_sync_stop` | 5 |
| **VM 内沙箱** | `adp_exec`、`adp_file_read`、`adp_file_write`、`adp_dir_list`、`adp_glob`、`adp_grep`、`adp_file_download`、`adp_file_upload` | 8 |

---

## 方式二：直接适配器（Python 原生）

在 Python 中直接导入 `DeerFlowADPSandboxProvider`。适用于 Python 互操作可用的嵌入式 deer-flow 部署场景。

### 第一步：安装依赖

```bash
cd /path/to/ai-dev-platform
pip install paramiko   # 推荐的 SSH 后端
```

### 第二步：导入并初始化

```python
from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider

provider = DeerFlowADPSandboxProvider(
    adp_home="/path/to/ai-dev-platform",   # ADP-OS 安装目录（必需）
    pool_size=2,                            # 预暖 VM 池大小（0 = 禁用）
    ssh_user="adp",                         # VM SSH 用户
    ssh_password="adp",                     # VM SSH 密码
)
```

### 第三步：预暖 VM 池（可选）

```python
# 启动后台 VM 以消除冷启动延迟（15-45 分钟 → 即时可用）
provider.warm_pool()
```

池 VM 使用 `deerflow-pool-N` 运行时名称——不会与用户运行时冲突。

### 第四步：使用沙箱

```python
# 获取沙箱（将 thread_id 映射到 ADP-OS runtime）
sandbox_id = provider.acquire(thread_id="my-agent-thread")
print(f"沙箱已获取: {sandbox_id}")

# 获取 Sandbox 句柄
sandbox = provider.get(sandbox_id)

# 在 VM 中执行命令
output = sandbox.execute_command("python --version")
print(output)

# 读写文件
sandbox.write_file("/tmp/hello.py", "print('Hello from ADP-OS!')")
content = sandbox.read_file("/tmp/hello.py")
print(content)

# 列出目录
entries = sandbox.list_dir("/tmp", max_depth=1)
for entry in entries:
    print(entry)

# glob 模式搜索文件
matches, truncated = sandbox.glob("/tmp", "*.py")
print(f"找到 {len(matches)} 个 Python 文件")

# grep 搜索文件内容
matches, truncated = sandbox.grep("/tmp", "Hello")
for m in matches:
    print(f"{m.path}:{m.line_number}: {m.line}")

# 下载/上传二进制文件
data = sandbox.download_file("/path/to/binary")
sandbox.update_file("/path/to/dest", data)

# 完成后释放沙箱
provider.release(sandbox_id)
```

### Sandbox 接口完整参考

| 方法 | 签名 | 返回值 |
|------|------|--------|
| `execute_command` | `(command: str)` | `str`（stdout） |
| `read_file` | `(path: str)` | `str`（文件内容） |
| `write_file` | `(path: str, content: str, append: bool = False)` | `None` |
| `list_dir` | `(path: str, max_depth: int = 2)` | `list[str]` |
| `glob` | `(path: str, pattern: str)` | `tuple[list[str], bool]` |
| `grep` | `(path: str, pattern: str, max_matches: int = 100, ...)` | `tuple[list[GrepMatch], bool]` |
| `download_file` | `(path: str)` | `bytes` |
| `update_file` | `(path: str, content: bytes)` | `None` |

### Thread → Runtime 映射

适配器在 `~/.adp-deerflow/thread_runtime_registry.json` 维护持久化的 thread-runtime 注册表：

```json
{
  "thread-abc123": "agent",
  "thread-def456": "sandbox"
}
```

`thread_id=None` 时的默认映射：`"agent"` 运行时。

---

## 环境变量参考

| 变量 | 必需 | 说明 |
|------|------|------|
| `ADP_HOME` | 是 | ADP-OS 安装目录（Linux/WSL 路径） |
| `ADP_HOME_WIN` | 仅 WSL | ADP-OS Windows 路径，用于调用 `pwsh.exe` |
| `ADP_SSH_USER` | 否 | VM SSH 用户名（默认：`adp`） |
| `ADP_SSH_PASSWORD` | 否 | VM SSH 密码（默认：`adp`） |

---

## 验证清单

- [ ] ADP-OS CLI 健康：`adpos doctor`
- [ ] 至少一个 VM 运行时已配置：`adpos status`
- [ ] MCP 服务器列出 26 个工具：`python3 -c "from cli.mcp.server import mcp; print(len(mcp._tool_manager._tools))"` → `26`
- [ ] MCP 服务器测试通过：`python -m pytest tests/test-mcp-server.py tests/test-mcp-vm-tools.py -v`
- [ ] Deer-flow 适配器测试通过：`python -m pytest tests/test_deerflow_adp_sandbox.py -v`
- [ ] （可选）集成测试：deer-flow agent 在 ADP-OS VM 中执行代码

---

## 故障排除

### VM 无法启动（超时）

**症状**：`adp_up` 超时或几分钟后返回"VM not ready"。

**检查**：
1. VMware Workstation 正在运行
2. ISO 存在于配置路径
3. 首次 Ubuntu 自动安装可能需要 15-45 分钟——等待更长时间，或使用 `VMPool` 预暖

### SSH 连接被拒绝

**症状**：`adp_exec` 或适配器方法返回"Connection refused"。

**检查**：
1. VM 正在运行：`adpos status agent`
2. SSH 端口可从集成主机访问
3. SSH 凭据与 `configs/topology.json` 设置匹配
4. VMware NAT 网络配置正确

### MCP 服务器无法启动

**症状**：Deer-flow 无法连接到 MCP 服务器。

**检查**：
1. Python 3.10+：`python --version`
2. ADP-OS 已安装：`ls cli/mcp/server.py`
3. `extensions_config.json` 中已设置环境变量
4. 配置中使用绝对路径（相对路径在 stdio 模式下可能失败）

### 未找到 paramiko

**解决方案**：安装它，否则适配器回退到 `subprocess ssh` + `sshpass`：

```bash
pip install paramiko

# 或安装 sshpass 作为回退：
# Ubuntu: sudo apt install sshpass
# macOS: brew install hudochenkov/sshpass/sshpass
```

### WSL 特定：未找到 pwsh.exe

**症状**：`adpos` 命令失败，提示"pwsh not found"。

**解决方案**：将 `ADP_HOME_WIN` 设置为 ADP-OS 目录的 Windows 风格路径，以便从 WSL 通过 `pwsh.exe` 运行 PowerShell 脚本。

---

## 参考资料

- [Deer-Flow 沙箱架构](https://github.com/ByteDance/deer-flow/tree/main/docker/provisioner)
- [ADP-OS MCP 服务器源码](../../cli/mcp/server.py)
- [Deer-Flow 缺口分析](integrations/deer-flow.md)
- [Deer-Flow VM 后端指南](integrations/deer-flow-backend.md)
- [适配器模块源码](../../extensions/deer_flow/deerflow_adp_sandbox.py)
- [适配器 README](../../extensions/deer_flow/README.md)
