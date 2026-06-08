# ADP-OS MCP 服务器连接 Deer-Flow 配置指南

> **日期**: 2026-06-05 | **目标读者**: Deer-flow 集成者、ADP-OS 运维人员
> **双语**: 中文 & English | [English version](../../integrations/deer-flow-mcp-setup.md)

逐步可复制执行的实操指南，将 [ByteDance/deer-flow](https://github.com/ByteDance/deer-flow)（70K⭐）通过 **MCP 协议**连接到 ADP-OS VM。每个命令均经过测试，可独立执行。

完整的双路径集成参考（MCP + 直接适配器），参见 [Deer-Flow 集成指南](../deer-flow-integration.md) ([English](../../deer-flow-integration.md))。架构分析和缺口跟踪，参见[将 ADP-OS 部署为 Deer-Flow VM 沙箱后端](deer-flow.md)。

---

## 配置完成后你将获得

- **按需启停 ADP-OS VM**（通过 MCP 工具管理 VM 生命周期）
- **在 VM 内执行命令**（shell、Python、任意工具）
- **读写沙箱文件系统**中的文件
- **使用 glob 和 grep 模式**搜索内容
- **下载/上传文件**在 agent 上下文和 VM 之间

共 26 个 MCP 工具，分 4 大类别：平台（3 个）、工作空间（10 个）、运行时（5 个）、VM 内沙箱（8 个）。

---

## 前置条件

| 条件 | 验证方式 | 说明 |
|------|---------|------|
| ADP-OS 已安装 | `adpos doctor` | Windows 主机上的 VMware Workstation |
| SSH 可达的 VM | `adpos status` | 至少一个运行时已配置 |
| Python 3.10+ | `python3 --version` | MCP 服务器所需 |
| deer-flow 已安装 | 项目根目录包含 `extensions_config.json` | deer-flow MCP 扩展支持 |
| （可选）`paramiko` | `pip install paramiko` | 更好的 SSH 性能 |

```bash
# 快速前置检查
adpos doctor   # 应返回 "healthy"
python3 --version                # 应为 ≥3.10
```

---

## 第一步：验证 ADP-OS MCP 服务器

MCP 服务器将 ADP-OS 暴露为 MCP 工具提供者。

```bash
cd /path/to/ai-dev-platform

# 验证 MCP 服务器模块加载且所有 26 个工具已注册
python3 -c "
from cli.mcp.server import mcp
tools = list(mcp._tool_manager._tools.keys())
print(f'MCP 工具注册数: {len(tools)}')
print(f'工具名称: {sorted(tools)}')
"
```

预期输出：**26 个工具**，分为以下类别：

| 类别 | 工具 | 数量 |
|------|------|------|
| **平台** | `adp_status`, `adp_doctor`, `adp_capabilities` | 3 |
| **工作空间** | `adp_workspace_list`, `adp_workspace_status`, `adp_workspace_dashboard`, `adp_workspace_project`, `adp_workspace_create`, `adp_workspace_open`, `adp_workspace_sync`, `adp_workspace_close`, `adp_workspace_recipes`, `adp_workspace_report` | 10 |
| **运行时** | `adp_up`, `adp_down`, `adp_stop`, `adp_sync_status`, `adp_sync_stop` | 5 |
| **VM 内沙箱** | `adp_exec`, `adp_file_read`, `adp_file_write`, `adp_dir_list`, `adp_glob`, `adp_grep`, `adp_file_download`, `adp_file_upload` | 8 |

验证服务器正常启动：

```bash
# 测试 MCP 服务器启动并响应（出现输出后按 Ctrl+C 退出）
ADP_HOME=$(pwd) python3 cli/mcp/server.py
```

---

## 第二步：配置 Deer-Flow MCP 扩展

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

### 环境变量

| 变量 | 必需 | 说明 | 示例 |
|------|------|------|------|
| `ADP_HOME` | **是** | ADP-OS 安装目录（WSL/Linux 路径） | `/home/user/ai-dev-platform` |
| `ADP_HOME_WIN` | WSL 专用 | ADP-OS Windows 路径用于 `pwsh.exe` | `D:\\Dev\\ai-dev-platform` |
| `ADP_SSH_USER` | 否 | VM SSH 用户名（默认: `adp`） | `adp` |
| `ADP_SSH_PASSWORD` | 否 | VM SSH 密码（默认: `adp`） | `adp` |

### 配置示例

**WSL（Windows Subsystem for Linux）**

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

**原生 Linux**

```json
{
  "adp_os_sandbox": {
    "type": "stdio",
    "command": "python3",
    "args": [
      "/opt/ai-dev-platform/cli/mcp/server.py"
    ],
    "env": {
      "ADP_HOME": "/opt/ai-dev-platform"
    }
  }
}
```

**macOS（需 pwsh + VMware Fusion 或 UTM 作为 VM 后端）**

```json
{
  "adp_os_sandbox": {
    "type": "stdio",
    "command": "python3",
    "args": [
      "/Users/me/ai-dev-platform/cli/mcp/server.py"
    ],
    "env": {
      "ADP_HOME": "/Users/me/ai-dev-platform"
    }
  }
}
```

> **重要提示**：`command` 和 `args` 中的路径必须使用**绝对路径**。在 stdio MCP 传输模式下，相对路径会失败，因为工作目录是不确定的。

---

## 第三步：重启 Deer-Flow

更新 `extensions_config.json` 后，重启 deer-flow 以加载 ADP-OS MCP 扩展。26 个 ADP-OS 工具将出现在 deer-flow 内置沙箱工具旁边。

Deer-flow agent 现在应该可以访问以下沙箱工具。这些 `adp_*` 名称是 MCP 工具名，不是本地 shell 命令：

```
adp_up, adp_down, adp_stop, adp_status,
adp_exec, adp_file_read, adp_file_write,
adp_dir_list, adp_glob, adp_grep,
adp_file_download, adp_file_upload,
adp_workspace_*, adp_sync_*, adp_doctor, adp_capabilities
```

---

## 第四步：验证集成

### VM 生命周期测试

在 deer-flow agent 上下文中，执行 VM 生命周期操作。以下内容是 MCP 工具调用；如果在本地终端验证，请使用 `adpos up agent`、`adpos status agent` 和 `adpos stop agent`。

```
# 启动 ADP-OS VM
adp_up agent

# 检查 VM 状态
adp_status agent

# 在 VM 内执行命令
adp_exec agent "python3 --version"

# 优雅关机
adp_stop agent
```

**预期行为**：
- `adp_up agent`：创建或启动 `agent` 运行时 VM。首次：15-45 分钟（Ubuntu 自动安装）。热启动：约 30 秒。
- `adp_status agent`：显示 VM 运行中且 SSH 可达。
- `adp_exec`：返回 VM 内的命令 stdout 输出。
- `adp_stop agent`：优雅关闭 VM。

### VM 内文件操作测试

```
# 在 VM 内写入文件
adp_file_write agent "/tmp/test.py" "print('Hello from ADP-OS!')" plan_only=False

# 读回文件
adp_file_read agent "/tmp/test.py"

# 列出目录
adp_dir_list agent "/tmp" max_depth=1

# 执行文件
adp_exec agent "python3 /tmp/test.py"

# 使用 glob 搜索
adp_glob agent "/tmp" "*.py"

# 搜索文件内容
adp_grep agent "/tmp" "Hello"
```

**预期行为**：
- 文件成功写入和读取。
- `adp_dir_list` 返回目录条目。
- `adp_exec` 运行 Python 并打印 "Hello from ADP-OS!"。
- `adp_glob` 找到 `test.py`。
- `adp_grep` 在文件中找到 "Hello"。

### 诊断测试

```
# 平台健康检查
adp_doctor

# 平台能力
adp_capabilities
```

---

## MCP 工具 → Sandbox 方法映射

8 个 VM 内 MCP 工具与 deer-flow `Sandbox` 抽象接口一一对应：

| MCP 工具 | Sandbox 方法 | 签名匹配 | 说明 |
|----------|-------------|---------|------|
| `adp_exec(runtime, command, timeout)` | `execute_command(command)` | ✅ 兼容 | `runtime` 为会话级别（MCP 额外参数） |
| `adp_file_read(runtime, path)` | `read_file(path)` | ✅ 兼容 | |
| `adp_file_write(runtime, path, content, append)` | `write_file(path, content, append)` | ✅ 完全匹配 | `plan_only=True` 默认值——适配器覆盖 |
| `adp_dir_list(runtime, path, max_depth)` | `list_dir(path, max_depth)` | ✅ 完全匹配 | |
| `adp_glob(runtime, path, pattern, include_dirs, max_results)` | `glob(path, pattern, include_dirs, max_results)` | ✅ 完全匹配 | |
| `adp_grep(runtime, path, pattern, glob_filter, literal, case_sensitive, max_results)` | `grep(path, pattern, glob, literal, case_sensitive, max_results)` | ✅ 兼容 | `glob_filter` vs `glob` 命名差异（可平滑映射） |
| `adp_file_download(runtime, path)` | `download_file(path)` | ✅ 兼容 | |
| `adp_file_upload(runtime, path, content_base64, plan_only)` | `update_file(path, content)` | ✅ 兼容 | base64（MCP 安全格式）vs bytes（Sandbox 原生格式） |

### 可桥接差异

| 差异 | 类型 | 影响 | 解决方案 |
|------|------|------|----------|
| 每个工具都有 `runtime` 参数 | 会话隔离 | MCP 工具将操作限定到特定 VM；deer-flow 限定到 `Sandbox` 实例 | 适配器层为每个 acquire 周期注入 `runtime` |
| `content_base64` (str) vs `bytes` | 内容编码 | MCP 协议使用 JSON 安全的 base64；deer-flow 原生使用 bytes | 适配器在协议边界处进行 base64 编解码 |
| `plan_only=True` 默认值 | 安全设计 | MCP 工具默认预览以防止意外 VM 变更 | 适配器在生产调用时传递 `plan_only=False` |
| `glob_filter` vs `glob` 命名 | 表面差异 | `adp_grep` 将文件过滤器命名为 `glob_filter`；deer-flow 的 `Sandbox.grep()` 命名为 `glob` | 适配器中进行参数映射 |

所有差异都可以**在适配器层桥接**，无需修改 MCP 服务器。

---

## 故障排查

### MCP 服务器无法启动

**症状**：Deer-flow 无法连接到 MCP 服务器。日志显示 "failed to start MCP extension."

**检查项**：
1. Python 3.10+ 已安装：`python3 --version`
2. ADP-OS 仓库存在：`ls /path/to/ai-dev-platform/cli/mcp/server.py`
3. `extensions_config.json` 中使用绝对路径（stdio 模式下相对路径会失败）
4. `fastmcp` 已安装：`python3 -c "from mcp.server.fastmcp import FastMCP; print('OK')"`
5. 环境变量已设置且正确

```bash
# 验证 MCP 服务器可独立启动
cd /absolute/path/to/ai-dev-platform
ADP_HOME=$(pwd) python3 cli/mcp/server.py 2>&1 &
# 应无错误启动；验证后 kill
kill %1
```

### VM 无法启动（超时）

**症状**：`adp_up agent` 在几分钟后返回超时或 "VM not ready"。

**检查项**：
1. VMware Workstation 在 Windows 主机上运行
2. `adpos status` 显示 VM 状态
3. 首次 Ubuntu 自动安装可能需要 15-45 分钟——多等一会儿
4. ISO 存在于 `configs/topology.json` 中配置的路径

### "adp_exec" 返回 "Connection refused"

**症状**：VM 内工具失败，提示 "Connection refused" 或 SSH 错误。

**检查项**：
1. VM 正在运行：`adp_status agent`
2. SSH 凭据匹配 `configs/topology.json`
3. VMware NAT 网络配置正确
4. 集成主机可以访问 VM 的 IP 地址

```bash
# 直接 SSH 测试（将 IP 替换为实际 VM IP）
ssh -o StrictHostKeyChecking=no adp@<vm-ip> "echo 'SSH OK'"
```

### "pwsh.exe not found"（WSL）

**症状**：从 WSL 运行时，ADP-OS 命令失败提示 "pwsh not found"。

**解决方案**：在 `extensions_config.json` 的 env 部分设置 `ADP_HOME_WIN`。MCP 服务器使用此变量在 WSL 上下文中解析 `pwsh.exe`。

### "plan_only" 阻止了实际的写入操作

**症状**：`adp_file_write` 或 `adp_file_upload` 没有实际写入 VM。

**说明**：MCP 工具出于安全考虑默认 `plan_only=True`。agent 必须显式传递 `plan_only=False`：

```
adp_file_write agent "/tmp/config.json" '{"key": "value"}' plan_only=False
adp_file_upload agent "/tmp/data.bin" "SGVsbG8=" plan_only=False
```

---

## 已知限制

1. **冷启动延迟**：首次 VM 创建需要 15-45 分钟进行 Ubuntu 自动安装。后续启动约 30 秒。建议在 agent 会话开始前调用 MCP 工具 `adp_up` 预暖 VM。

2. **仅限 Windows 主机**：ADP-OS 目前需要 VMware Workstation 在 Windows 主机上运行。Linux/macOS 主机不支持 VM 供应。

3. **无跨 VM 文件系统隔离**：deer-flow 原生 Docker 沙箱为每个会话创建隔离的文件系统。ADP-OS VM 共享同一个文件系统——同一运行时上的并发 agent 可能相互干扰。

4. **SSH 凭据管理**：VM SSH 密码目前为静态（`adp`/`adp`）。生产部署应更改默认密码并使用 SSH 密钥。

5. **每个会话只能使用一个运行时**：MCP 工具绑定到单个 `runtime` 参数。对于多 agent 场景，通过不同的运行时名称（agent、frontend、backend、sandbox）获取独立的 VM。

---

## 验证清单

使用 `adpos` 的项目是本地 CLI 检查；使用 `adp_*` 的项目是 deer-flow agent 上下文中的 MCP 工具检查。

- [ ] ADP-OS CLI 健康：`adpos doctor`
- [ ] 至少一个 VM 运行时已配置：`adpos status`
- [ ] MCP 服务器模块可加载：`python3 -c "from cli.mcp.server import mcp; print(len(mcp._tool_manager._tools))"` → `26`
- [ ] MCP 服务器测试通过：`python3 -m pytest tests/test-mcp-server.py -q` → `45 passed`
- [ ] Deer-flow 适配器测试通过：`python3 -m pytest tests/test_deerflow_adp_sandbox.py -q` → `46 passed`
- [ ] `extensions_config.json` 使用绝对路径和正确的环境变量配置
- [ ] Deer-flow 已重启，26 个 ADP-OS 工具对 agent 可见
- [ ] `adp_up agent` 成功（创建或启动 VM）
- [ ] `adp_exec agent "python3 --version"` 从 VM 内返回 Python 版本
- [ ] `adp_file_read` / `adp_file_write` 在 VM 上正确工作

---

## 参考资料

- [Deer-Flow 沙箱架构](https://github.com/ByteDance/deer-flow/tree/main/docker/provisioner)
- [Deer-Flow Sandbox ABC](https://github.com/ByteDance/deer-flow/blob/main/backend/packages/harness/deerflow/sandbox/sandbox.py)
- [ADP-OS MCP 服务器源码](../../../cli/mcp/server.py) — 26 个工具，1,365 行
- [ADP-OS Deer-Flow 适配器](../../../extensions/deer_flow/deerflow_adp_sandbox.py) — Python 原生集成路径
- [Deer-Flow 集成指南](../deer-flow-integration.md) — 双路径综合参考
- [Deer-Flow 缺口分析](deer-flow.md) — 架构和缺口跟踪

---

> **来源标签**: [FILE]=源码分析, [LLM]=LLM 推理

---

**完成本指南后的下一步**：部署 Python 原生的 `DeerFlowADPSandboxProvider` 适配器用于生产环境（VM 池预暖、thread→runtime 注册表、SSH 连接缓存）。参见 [Deer-Flow 集成指南 - 方式二](../deer-flow-integration.md#方式二直接适配器python-原生)。
