# Deer-Flow 集成指南

简体中文 | [English](../deer-flow-integration.md)

ADP-OS 提供标准的 [Model Context Protocol (MCP)](https://modelcontextprotocol.io) 服务器，可作为 MCP 服务器加载到 [ByteDance/deer-flow](https://github.com/bytedance/deer-flow)（70K⭐）中。只需配置一次，deer-flow agent 即可使用全部 26 个 ADP-OS 平台、工作区、运行时和 VM 内沙箱工具。

> **范围**：本指南涵盖在 deer-flow 中配置 ADP-OS MCP 服务器。ADP-OS 现已提供 26 个工具（18 个生命周期 + 8 个 SSH 支持的 VM 内操作），可作为**完整的 deer-flow 沙箱后端**使用——包括代码执行、文件 I/O 和 VM 内目录导航。关于已解决的 P0 差距和已发布的适配器，请参阅[差距分析](integrations/deer-flow.md)。

## 快速开始

### 1. 安装 MCP 服务器依赖

```bash
cd /path/to/ai-dev-platform/cli/mcp
pip install -r requirements.txt
```

### 2. 配置 deer-flow

如果尚未复制示例扩展配置文件：

```bash
cd /path/to/deer-flow
cp extensions_config.example.json extensions_config.json
```

将 ADP-OS MCP 服务器条目添加到 `extensions_config.json`：

#### Windows（原生）

```json
{
  "mcpServers": {
    "adp-os": {
      "enabled": true,
      "type": "stdio",
      "command": "python",
      "args": ["D:\\Dev\\ai-dev-platform\\cli\\mcp\\server.py"],
      "env": {
        "ADP_HOME": "D:\\Dev\\ai-dev-platform"
      },
      "description": "ADP-OS VM 沙箱后端 — 26 个工具，用于平台、工作区、运行时和 VM 内沙箱管理"
    }
  }
}
```

在 Windows 上，只需设置 `ADP_HOME`。服务器会自动检测平台，并将路径视为原生 Windows 路径。

#### WSL（Python 在 WSL 中运行，pwsh.exe 在 Windows 主机上）

```json
{
  "mcpServers": {
    "adp-os": {
      "enabled": true,
      "type": "stdio",
      "command": "python3",
      "args": ["/home/user/ai-dev-platform/cli/mcp/server.py"],
      "env": {
        "ADP_HOME": "/home/user/ai-dev-platform",
        "ADP_HOME_WIN": "D:\\Dev\\ai-dev-platform"
      },
      "description": "ADP-OS VM 沙箱后端 — 26 个工具，用于平台、工作区、运行时和 VM 内沙箱管理"
    }
  }
}
```

在 WSL 上，需同时设置 `ADP_HOME`（WSL 路径）和 `ADP_HOME_WIN`（Windows 主机路径）。服务器通过 `wslpath` 自动在 WSL 和 Windows 路径之间转换。

### 3. 重启 deer-flow

重启 deer-flow 服务。ADP-OS 工具将在启动时自动发现和注册。

### 4. 验证

向 deer-flow agent 提问："显示 ADP-OS 平台状态"

Agent 应调用 `adp_status` 并报告运行时健康状况。

## 可用工具

配置完成后即可使用全部 26 个工具：

### 平台工具

| 工具 | 功能 |
|------|------|
| `adp_status` | 所有运行时的健康状态（VM 状态、SSH、同步） |
| `adp_doctor` | 平台诊断（47+ 项检查、问题修复建议） |
| `adp_capabilities` | 平台能力和路线图 |

### 工作区工具

| 工具 | 功能 |
|------|------|
| `adp_workspace_list` | 列出清单中的项目及其运行时映射 |
| `adp_workspace_status` | 工作区就绪状态（路径、运行时、同步、快照） |
| `adp_workspace_dashboard` | 任务生命周期总览及治理队列 |
| `adp_workspace_project` | 单项目操作生命周期视图 |
| `adp_workspace_create` | 创建工作区目录（默认 plan-only） |
| `adp_workspace_open` | 进入工作区的指引（路径、SSH、同步命令） |
| `adp_workspace_sync` | 按项目提供同步指引 |
| `adp_workspace_close` | 关闭工作区（停止同步，默认 plan-only） |
| `adp_workspace_recipes` | 列出可用的工作区配方 |
| `adp_workspace_report` | Markdown 发布证据 |

### 运行时工具

| 工具 | 功能 |
|------|------|
| `adp_up` | 启动 VM（首次使用时从 ISO 创建，默认 plan-only） |
| `adp_down` | 销毁 VM（默认 plan-only） |
| `adp_stop` | 优雅关闭 VM |
| `adp_sync_status` | Mutagen 同步会话健康状况 |
| `adp_sync_stop` | 停止 Mutagen 同步会话 |

### VM 内沙箱工具（SSH 支持）

| 工具 | 功能 |
|------|------|
| `adp_exec` | 通过 SSH 在运行中的 VM 内执行命令 |
| `adp_file_read` | 从 VM 内读取文件内容 |
| `adp_file_write` | 写入或追加内容到 VM 内的文件 |
| `adp_dir_list` | 列出 VM 内目录内容（可配置深度的递归） |
| `adp_glob` | 通过模式在 VM 内查找文件 |
| `adp_grep` | 在 VM 内搜索文件中的文本 |
| `adp_file_download` | 从 VM 下载文件（base64 编码） |
| `adp_file_upload` | 上传 base64 编码内容到 VM 内的文件（默认 plan-only） |

## 安全设计

所有破坏性操作默认为 plan-only 模式：

- `adp_up` 和 `adp_down` 默认为 `plan_only=True` — 仅预览
- `adp_workspace_create` 默认为 `plan_only=True` — 仅预览
- `adp_workspace_close` 默认为 `plan_only=True` — 仅预览
- `adp_file_upload` 默认为 `plan_only=True` — 仅预览

要实际执行，需显式设置 `plan_only=False`。所有检查类工具完全无破坏性。

## 当前可完成的任务

使用当前的 26 个工具，deer-flow agent 可以：

| 任务 | 使用的工具 | 说明 |
|------|-----------|------|
| **检查平台健康** | `adp_status`、`adp_doctor` | 验证所有 VM 运行中、SSH 可达、同步正常 |
| **管理 VM 生命周期** | `adp_up`、`adp_stop`、`adp_down` | 启动、停止、销毁 VM |
| **设置工作区** | `adp_workspace_create`、`adp_workspace_open` | 创建项目目录、获取进入指引 |
| **监控同步** | `adp_sync_status`、`adp_sync_stop` | 检查和管理文件同步 |
| **检查工作区** | `adp_workspace_list`、`adp_workspace_status`、`adp_workspace_dashboard`、`adp_workspace_project` | 完整的工作区可见性 |
| **生成证据** | `adp_workspace_report` | 用于 PR 描述的 Markdown 发布证据 |
| **发现能力** | `adp_capabilities`、`adp_workspace_recipes` | 平台和工作流发现 |
| **在 VM 内执行代码** | `adp_exec` | 运行命令、安装软件包、执行脚本 |
| **在 VM 内读写文件** | `adp_file_read`、`adp_file_write`、`adp_file_upload` | 检查输出、创建/修改源文件 |
| **浏览 VM 文件系统** | `adp_dir_list`、`adp_glob`、`adp_grep` | 浏览目录、按模式查找文件、搜索文件内容 |
| **从 VM 下载文件** | `adp_file_download` | 将 VM 文件下载为 base64 以便传输 |

## 当前限制

MCP 服务器现已同时提供 **VM 侧操作**（从主机管理 VM）和 **VM 内操作**（在 VM 内部执行代码）。初始分析中识别的 P0 差距已全部解决。

| 能力 | 状态 | 说明 |
|------|------|------|
| 启动/停止/销毁 VM | ✅ 可用 | 使用 `adp_up`/`adp_stop`/`adp_down` |
| 检查 VM 健康 | ✅ 可用 | 使用 `adp_status`/`adp_doctor` |
| 管理工作区和同步 | ✅ 可用 | 使用工作区和同步工具 |
| 在 VM 内运行代码 | ✅ 可用 | 使用 `adp_exec` 通过 SSH |
| 在 VM 内读写文件 | ✅ 可用 | 使用 `adp_file_read`/`adp_file_write`/`adp_file_upload` |
| 列出 VM 内目录 | ✅ 可用 | 使用 `adp_dir_list` |
| 在 VM 内搜索文件 | ✅ 可用 | 使用 `adp_glob`/`adp_grep` |
| 从 VM 下载文件 | ✅ 可用 | 使用 `adp_file_download` |

**剩余考虑因素**：首次启动 VM 需要 15-45 分钟（冷 ISO 安装）。从预热的 VM 池热启动约需 30 秒。`extensions/deer_flow/` 中的 `DeerFlowADPSandboxProvider` 适配器提供了原生的 deer-flow Sandbox 接口集成，并支持 `VMPool` 预热。

关于完整的 deer-flow 沙箱集成详情，包括 `DeerFlowADPSandboxProvider` 适配器类，请参阅 [../../extensions/deer_flow/README.md](../../extensions/deer_flow/README.md)。

## 工作流示例：通过 Deer-Flow 管理 VM

典型的 deer-flow agent 管理 ADP-OS VM 的会话：

```
用户："设置一个 ADP-OS agent 工作区并检查健康状况"

Agent 调用：
  1. adp_status()                    → "agent: stopped"
  2. adp_up("agent", plan_only=False) → VM 启动（热启动 30 秒，首次安装 20 分钟）
  3. adp_status("agent")             → "agent: running, reachable, healthy"
  4. adp_doctor()                    → "47 OK, 0 issues"
  5. adp_exec("agent", "python --version") → "Python 3.12.0"
  6. adp_workspace_list()            → 项目及运行时映射
  7. adp_workspace_status()          → 就绪状态摘要
  8. adp_sync_status()               → "agent: healthy"
```

## 环境变量

| 变量 | 必需 | 说明 |
|------|------|------|
| `ADP_HOME` | 是 | ADP-OS 安装路径（WSL 路径或 Windows 路径） |
| `ADP_HOME_WIN` | 仅 WSL | ADP-OS 的 Windows 主机路径（如 `D:\\Dev\\ai-dev-platform`） |

路径解析顺序：
1. `ADP_HOME` / `ADP_HOME_WIN` 环境变量（显式）
2. 相对于服务器脚本位置（`cli/mcp/server.py` 向上两级）
3. 常见路径（`D:/Dev/ai-dev-platform`、`/mnt/d/Dev/ai-dev-platform`）

## 故障排除

### 工具未在 deer-flow 中出现

1. 检查 `extensions_config.json` — 确认 `"enabled": true` 且路径正确
2. 查看 deer-flow 日志中的 MCP 服务器启动错误
3. 独立验证 MCP 服务器：
   ```bash
   cd /path/to/ai-dev-platform
   ADP_HOME_WIN="D:\\Dev\\ai-dev-platform" python cli/mcp/server.py
   ```
   （服务器通过 stdio 启动——需要 MCP 客户端连接。stdout 无输出是正常的。）

### pwsh.exe 未找到

从 https://github.com/PowerShell/PowerShell 安装 PowerShell 7+

### 路径问题

- Windows：在 JSON 中使用双反斜杠（`D:\\Dev\\ai-dev-platform`）
- WSL：同时设置 `ADP_HOME`（WSL 路径）和 `ADP_HOME_WIN`（Windows 路径）
- 服务器通过 `wslpath` 自动在 WSL 和 Windows 路径之间转换

### ADP-OS 未安装或未配置

MCP 服务器封装了 ADP-OS PowerShell CLI。你需要：
1. 在配置的路径安装 ADP-OS
2. 安装 VMware Workstation Pro
3. 创建 ADP-OS 运行时（`adp up agent`）

配置后使用 MCP 的 `adp_doctor` 验证平台健康状况。

## 参考资料

- [Deer-Flow MCP 服务器指南](https://github.com/bytedance/deer-flow/blob/main/backend/docs/MCP_SERVER.md) — deer-flow MCP 配置
- [Deer-Flow 沙箱配置](https://github.com/bytedance/deer-flow/blob/main/backend/docs/CONFIGURATION.md#sandbox) — 沙箱模式
- [ADP-OS MCP 服务器 README](../../cli/mcp/README.md) — 完整工具参考和架构
- [Deer-Flow 差距分析](integrations/deer-flow.md) — P0/P1/P2 差距及集成路径
- [Copilot SDK 集成](copilot-sdk-integration.md) — 替代 Agent SDK 集成方案
