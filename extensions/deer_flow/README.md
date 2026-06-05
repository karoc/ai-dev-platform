# ADP-OS Deer-Flow Sandbox Adapter

让 deer-flow agents 使用 ADP-OS VMs 作为 sandbox 后端的适配器。

## 概述

`DeerFlowADPSandboxProvider` 实现了 deer-flow 的 `SandboxProvider` 接口，将 ADP-OS 虚拟机作为 sandbox 后端。deer-flow agents 可以通过标准的 Sandbox 抽象来管理 ADP-OS VM 的生命周期并在 VM 内执行代码。

```
Deer-Flow Agent
    │
    ├── acquire(thread_id) → sandbox_id     ← ADP CLI: adp up <runtime>
    ├── get(sandbox_id)    → ADPSSHSandbox  ← SSH to VM
    │   ├── execute_command("pip install ...")
    │   ├── read_file("/path/to/file")
    │   ├── write_file("/path/to/file", "...")
    │   ├── list_dir("/path")
    │   ├── glob("/path", "*.py")
    │   ├── grep("/path", "TODO")
    │   ├── download_file("/path")
    │   └── update_file("/path", bytes)
    └── release(sandbox_id)                 ← ADP CLI: adp stop <runtime>
```

## 安装

```bash
# 从 ADP-OS 项目根目录
pip install paramiko   # SSH 连接（推荐；无 paramiko 时自动回退到 subprocess ssh）

# 或在 deer-flow 中直接引用
pip install -e /path/to/ai-dev-platform
```

## 快速开始

```python
from extensions.deer_flow.deerflow_adp_sandbox import DeerFlowADPSandboxProvider

# 初始化 provider
provider = DeerFlowADPSandboxProvider(
    adp_home="/path/to/ai-dev-platform",   # ADP-OS 安装目录（必需）
    pool_size=2,                            # 预暖 VM 池大小（0 = 禁用）
    ssh_user="adp",                         # VM SSH 用户
    ssh_password="adp",                     # VM SSH 密码
)

# 预暖 VM 池（可选，后台线程）
provider.warm_pool()

# 获取 sandbox
sandbox_id = provider.acquire(thread_id="my-thread")
print(f"Sandbox acquired: {sandbox_id}")

# 获取 Sandbox 句柄
sandbox = provider.get(sandbox_id)

# 在 VM 内执行命令
output = sandbox.execute_command("python --version")
print(output)

# 读写文件
sandbox.write_file("/tmp/hello.py", "print('Hello from ADP-OS!')")
content = sandbox.read_file("/tmp/hello.py")
print(content)

# 列出目录
entries = sandbox.list_dir("/tmp", max_depth=1)
print(entries)

# 搜索文件
matches, truncated = sandbox.grep("/tmp", "Hello")
for m in matches:
    print(f"{m.path}:{m.line_number}: {m.line}")

# 释放 sandbox
provider.release(sandbox_id)
```

## SandboxProvider 接口

| 方法 | 说明 | ADP-OS 映射 |
|------|------|------------|
| `acquire(thread_id)` → `sandbox_id` | 获取 sandbox | `adp up <runtime>` |
| `get(sandbox_id)` → `Sandbox` | 获取 SSH 连接句柄 | 创建 SSH 连接到 VM |
| `release(sandbox_id)` | 释放 sandbox | `adp stop <runtime>` |

## Sandbox 接口（8 个方法）

| 方法 | 说明 | SSH 命令 |
|------|------|---------|
| `execute_command(cmd)` → `str` | 执行 shell 命令 | `ssh <vm> <cmd>` |
| `read_file(path)` → `str` | 读取文本文件 | `cat` |
| `write_file(path, content, append)` | 写入/追加文本 | `echo \| base64 -d >` |
| `list_dir(path, max_depth)` → `list[str]` | 列出目录 | `find -maxdepth` |
| `glob(path, pattern)` → `(list, bool)` | glob 匹配 | `find -path` |
| `grep(path, pattern, ...)` → `(list, bool)` | 内容搜索 | `grep -rn` |
| `download_file(path)` → `bytes` | 下载二进制文件 | `base64` 编码传输 |
| `update_file(path, content)` | 写入二进制文件 | `base64 -d` 解码写入 |

## Thread → Runtime 映射

deer-flow 使用 `thread_id` 标识会话，ADP-OS 使用 `runtime` 名称（agent/frontend/backend/sandbox）。

默认映射：`thread_id=None` → `"agent"` runtime。

自定义映射会持久化到 `~/.adp-deerflow/thread_runtime_registry.json`：

```json
{
  "thread-abc": "agent",
  "thread-def": "sandbox"
}
```

## VM 池（预暖）

为避免首次 VM 创建时的冷启动延迟（15-45 分钟），provider 支持 VM 预暖池：

```python
provider = DeerFlowADPSandboxProvider(adp_home="...", pool_size=2)
provider.warm_pool()  # 后台启动 2 个 VM

# acquire() 会优先从池中获取
sandbox_id = provider.acquire()  # 立即可用！
```

池 VM 使用 `deerflow-pool-N` 命名，不会与用户 runtime 冲突。

如果池为空，`acquire()` 会自动创建新的 VM。

## SSH 连接

- **推荐**：安装 `paramiko` 以获得更好的连接管理
  ```bash
  pip install paramiko
  ```
- **回退**：无 paramiko 时自动使用 subprocess `ssh` + `sshpass`

SSH 配置来源于 `configs/topology.json` 中的 `static_ip` 和 `ssh_port`。

## 依赖

| 依赖 | 必需？ | 说明 |
|------|-------|------|
| ADP-OS CLI | ✅ | `cli/adp.ps1` + PowerShell 7+ |
| paramiko | 推荐 | SSH 连接（无则回退 subprocess ssh） |
| sshpass | 回退时 | subprocess SSH 密码认证 |
| VMware Workstation | ✅ | VM 运行时 |

## 环境变量

| 变量 | 说明 |
|------|------|
| `ADP_HOME` | ADP-OS 安装目录（Linux/WSL 路径） |
| `ADP_HOME_WIN` | ADP-OS Windows 路径（仅 WSL） |

## 限制和已知问题

1. **直接 SSH vs MCP 路径**：适配器使用直接 SSH（paramiko 或 subprocess ssh）进行 VM 内操作。ADP-OS MCP server 现已提供 8 个 SSH 支持的 in-VM 工具（adp_exec 等，commit f7453c8），可作为备选路径。目前直接 SSH 方式更轻量且无额外协议开销。
2. **首次启动延迟**：创建新 VM 需 15-45 分钟（Ubuntu autoinstall）。使用 `pool_size > 0` 预暖池缓解。
3. **Windows 仅限**：ADP-OS 当前仅支持 Windows 主机（VMware Workstation）。
4. **单线程安全**：provider 使用 `threading.Lock` 保证线程安全，但 SSH 连接不应跨线程共享。

## 测试

```bash
cd /path/to/ai-dev-platform
python -m pytest tests/test_deerflow_adp_sandbox.py -v
```

## 参考

- [Deer-Flow Sandbox ABC](https://github.com/bytedance/deer-flow/blob/main/backend/packages/harness/deerflow/sandbox/sandbox.py)
- [ADP-OS MCP Server](../../cli/mcp/server.py)
- [Deer-Flow Integration Guide](../../docs/deer-flow-integration.md)
- [Deer-Flow Gap Analysis](../../docs/integrations/deer-flow.md)
