# GitHub Copilot Agent SDK 集成指南

简体中文 | [English](../copilot-sdk-integration.md)

ADP-OS 提供标准的 [Model Context Protocol (MCP)](https://modelcontextprotocol.io) 服务器，与 [GitHub Copilot Agent SDK](https://github.com/github/copilot-sdk) 原生兼容。无需额外适配器，无需修改代码——配置一次即可在 Copilot SDK agent 中使用全部 18 个 ADP-OS 工具。

## 快速开始

安装对应语言的 Copilot SDK，然后加载 ADP-OS 作为 MCP 服务器。

### Python

```python
import asyncio
from copilot import CopilotClient
from copilot.session import PermissionHandler

async def main():
    client = CopilotClient()
    await client.start()

    session = await client.create_session(
        on_permission_request=PermissionHandler.approve_all,
        model="gpt-5",
        mcp_servers={
            "adp-os": {
                "type": "local",
                "command": "python",
                "args": ["cli/mcp/server.py"],
                "cwd": "/path/to/ai-dev-platform",
                "tools": ["*"],
            },
        },
    )

    response = await session.send_and_wait(
        "检查 ADP-OS 平台状态并列出所有工作区项目。"
    )
    print(response.data.content)

    await session.disconnect()
    await client.stop()

asyncio.run(main())
```

### TypeScript (Node.js)

```typescript
import { CopilotClient } from "@github/copilot-sdk";

async function main() {
    const client = new CopilotClient();
    const session = await client.createSession({
        model: "gpt-5",
        mcpServers: {
            "adp-os": {
                type: "local",
                command: "python",
                args: ["cli/mcp/server.py"],
                cwd: "/path/to/ai-dev-platform",
                tools: ["*"],
            },
        },
    });

    const result = await session.sendAndWait({
        prompt: "检查 ADP-OS 平台状态并列出所有工作区项目。",
    });

    console.log(result?.data?.content);
    await session.disconnect();
    await client.stop();
}

main();
```

### 使用环境变量

通过 `env` 字段传递 `ADP_HOME`（以及可选的 `ADP_HOME_WIN`）：

```python
# Python
mcp_servers={
    "adp-os": {
        "type": "local",
        "command": "python",
        "args": ["cli/mcp/server.py"],
        "cwd": "/path/to/ai-dev-platform",
        "env": {
            "ADP_HOME": "/path/to/ai-dev-platform",
            # 仅当 ADP-OS 位于与 wslpath 解析路径不同的 Windows 路径时需要：
            # "ADP_HOME_WIN": "D:\\Dev\\ai-dev-platform",
        },
        "tools": ["*"],
    },
},
```

```typescript
// TypeScript
mcpServers: {
    "adp-os": {
        type: "local",
        command: "python",
        args: ["cli/mcp/server.py"],
        cwd: "/path/to/ai-dev-platform",
        env: {
            ADP_HOME: "/path/to/ai-dev-platform",
        },
        tools: ["*"],
    },
},
```

## 环境变量

| 变量 | 是否必需 | 说明 |
|------|---------|------|
| `ADP_HOME` | **是** | ADP-OS 安装目录的路径。同时支持 Windows（`D:\\Dev\\ai-dev-platform`）和 WSL/Linux（`/mnt/d/Dev/ai-dev-platform`）路径。 |
| `ADP_HOME_WIN` | 否 | 显式的 Windows 路径覆盖。仅当 MCP 服务器在 WSL 上运行，但 ADP-OS 位于与 `wslpath -w` 解析结果不同的 Windows 路径上时需要。设置后优先于自动解析的 Windows 路径。 |

MCP 服务器通过三级回退机制解析 `ADP_HOME`：

1. `ADP_HOME` 环境变量（显式设置）
2. 自动检测：从 `cli/mcp/server.py` 向上查找项目根目录（`cli/adp.ps1`）
3. 平台特定的已知路径（`D:/Dev/ai-dev-platform`、`~/ai-dev-platform`、`/mnt/d/Dev/ai-dev-platform`）

如果遇到 `FileNotFoundError: Cannot locate ADP-OS installation` 错误，请显式设置 `ADP_HOME`。

## ADP-OS MCP 工具列表

MCP 服务器共提供 18 个工具，分为三类：

### 平台工具（3 个）

| 工具 | 说明 |
|------|------|
| `adp_status` | 平台和运行时健康状态。显示运行中的 VM、SSH 可达性、同步健康度。 |
| `adp_doctor` | 运行平台诊断。报告通过/问题数量及逐项修复建议。 |
| `adp_capabilities` | 平台能力与路线图。列出已支持/计划中/探索中的功能。 |

### 工作区工具（10 个）

| 工具 | 说明 |
|------|------|
| `adp_workspace_list` | 列出 manifest 中定义的所有工作区项目。 |
| `adp_workspace_status` | 详细的工作区就绪状态：manifest 状态、路径、运行时状态、同步会话。 |
| `adp_workspace_dashboard` | 任务生命周期概览仪表盘，含里程碑检查点和评估钩子。 |
| `adp_workspace_project` | 单个项目的完整运维生命周期视图（路径、运行时、同步、验证、证据）。 |
| `adp_workspace_create` | 创建工作区项目目录（默认仅预览模式）。 |
| `adp_workspace_open` | 工作区入口指引：本地/远程路径、运行时就绪状态、同步状态。 |
| `adp_workspace_sync` | 按项目的文件同步指引，含显式同步命令。 |
| `adp_workspace_close` | 通过停止运行时同步来关闭工作区（默认仅预览模式）。 |
| `adp_workspace_recipes` | 列出可用的工作区配方、里程碑和评估钩子。 |
| `adp_workspace_report` | 生成 Markdown 格式的发布证据，用于维护者交接。 |

### 运行时工具（5 个）

| 工具 | 说明 |
|------|------|
| `adp_up` | 启动运行时 VM（默认仅预览模式）。首次运行时从 ISO 创建。 |
| `adp_down` | 完全销毁运行时 VM（默认仅预览模式）。不可逆操作。 |
| `adp_stop` | 优雅关闭运行时 VM，不销毁。 |
| `adp_sync_status` | 获取所有运行时的 Mutagen 同步会话状态。 |
| `adp_sync_stop` | 停止指定运行时的 Mutagen 同步会话。 |

## 安全：默认预览模式

**所有破坏性操作默认以 plan-only（预览）模式运行。** `adp_up`、`adp_down`、`adp_workspace_create` 和 `adp_workspace_close` 都需要显式设置 `plan_only=False` 才会实际执行。在预览模式下，工具显示*将会*发生什么，但不做实际更改。

这意味着可以安全地让 agent 探索平台，无需担心意外销毁 VM。准备执行时，传入 `plan_only=False`：

```python
# Agent: "让我看看启动 agent 运行时会怎样。"
response = await session.send_and_wait(
    "预览启动 agent 运行时。"
)
# → 调用 adp_up(runtime="agent") → 仅输出预览，不创建 VM

# Agent: "现在真正启动它。"
response = await session.send_and_wait(
    "真正启动 agent 运行时。"
)
# → 调用 adp_up(runtime="agent", plan_only=False) → 实际创建 VM
```

## 权限注意事项

### 工具访问控制

Copilot SDK MCP 配置中的 `tools` 字段控制哪些工具可用。可选：

- `["*"]` — 启用全部 18 个工具（推荐用于完整 ADP-OS 访问）
- `["adp_status", "adp_doctor", "adp_workspace_list"]` — 仅只读工具
- `[]` — 无工具（实质上禁用服务器）

在生产或 CI 环境中，建议限制为只读工具，仅对特定会话开放变更类工具。

### Copilot SDK 权限处理器

Copilot SDK 的 `PermissionHandler` 控制工具级别的批准。你可以：

- **全部批准**（`PermissionHandler.approve_all`）：适用于可信的本地开发环境。
- **提示批准**（`PermissionHandler.prompt`）：SDK 在每次工具执行前询问你。
- **自定义处理器**：实现自己的批准逻辑——自动批准读操作，对写操作弹窗确认，拒绝销毁操作。

```python
# 自定义：自动批准读操作，其余弹窗确认
class ReadOnlyHandler(PermissionHandler):
    READ_TOOLS = {"adp_status", "adp_doctor", "adp_capabilities",
                  "adp_workspace_list", "adp_workspace_status",
                  "adp_workspace_dashboard", "adp_workspace_project",
                  "adp_workspace_open", "adp_workspace_sync",
                  "adp_workspace_recipes", "adp_workspace_report",
                  "adp_sync_status"}

    def on_permission_request(self, request):
        if request.tool_name in self.READ_TOOLS:
            return True   # 自动批准
        return super().on_permission_request(request)  # 弹窗确认
```

### 本地安全模型

ADP-OS 设计用于**单用户、可信工作站**环境。MCP 服务器继承此模型：

- VM 在本地运行，使用默认的 `adp:adp` 凭据进行自动化 sudo 配置。
- MCP 服务器执行 ADP-OS CLI 命令——其访问权限与直接运行 `adp.ps1` 相同。
- 在未更换凭据和加固 SSH 之前，不要将 MCP 服务器暴露到不受信任的网络或多租户环境（参见[安全策略](../../SECURITY.zh-CN.md)）。

## 参见

- [GitHub Copilot SDK — MCP 文档](https://github.com/github/copilot-sdk/blob/main/docs/features/mcp.md)
- [ADP-OS Agent-Native API (MCP) 概览](../../README.zh-CN.md#agent-native-apimcp)
- [ADP-OS 安全策略](../../SECURITY.zh-CN.md)
- [Model Context Protocol 规范](https://modelcontextprotocol.io/)
