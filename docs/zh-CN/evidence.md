# 证据链

简体中文 | [English](../evidence.md)

ADP-OS 证据链为工作区快照元数据和操作日志提供了防篡改、仅追加的 SHA-256 哈希链。每个条目加密链接到前一个条目，形成不可变的审计轨迹。

## 为什么需要证据链

当 AI agent 或人类开发者更改工作区状态时，需要回答以下问题：

- 在工作的每个阶段存在哪些快照？
- 谁在何时执行了每个操作？
- 能否证明没有条目被修改或倒填日期？
- 是否发生了 AI 辅助开发，谁进行了审查？

证据链通过加密哈希回答了这些问题。每个条目的 `sha256_hash` 是由其内容和前一个条目的哈希值共同计算得出的。修改任何条目都会破坏后续所有哈希值，使篡改可被检测。

## 快速开始

```powershell
# 1. 签署当前工作区快照元数据
adpos workspace evidence -Snapshot -ManifestPath configs\workspace.recipes.example.json

# 2. 记录操作日志条目
adpos workspace evidence -Log -Operation sync -Details "为 UI 修复启动了前端同步"

# 3. 将所有证据导出为 ZIP 包
adpos workspace evidence -Export

# 4. 声明 AI 辅助开发
adpos workspace declare -AiAssisted -Reviewer "human-reviewer" -Notes "由 Claude 生成，逐行审查"
```

所有证据存储在 `<workspace_root>/.evidence/` 中：

| 文件 | 用途 |
| --- | --- |
| `snapshot-hashes.json` | 仅追加的快照元数据签名 SHA-256 链 |
| `operation-log.json` | 仅追加的操作日志条目 SHA-256 链 |

## 快照签名

`adpos workspace evidence -Snapshot` 创建快照签名条目。每个条目包含：

- `snapshot_id` — 唯一标识符（例如 `snap-1749244800`）
- `timestamp` — UTC ISO 8601 时间戳
- `workspace_name` — 来自 manifest 的工作区名称
- `sha256_hash` — `snapshot_id|timestamp|metadata_content|previous_hash|workspace_name` 的 SHA-256 哈希值
- `previous_hash` — 前一个条目的哈希值（第一个条目为 64 个零）

`metadata_content` 字段捕获：

- manifest 中列出的运行时名称
- 每个任务的快照名称（例如 `agent/before-agent-refactor`）
- 里程碑快照关联
- VMware 快照详情（当可用时）

### 验证快照签名

给定 `snapshot-hashes.json` 中的一个条目：

```json
{
  "snapshot_id": "snap-1749244800",
  "timestamp": "2025-06-06T00:00:00.0000000Z",
  "workspace_name": "example-workspace",
  "sha256_hash": "a1b2c3...",
  "previous_hash": "0000000000000000000000000000000000000000000000000000000000000000"
}
```

重新计算：

```powershell
$content = "snap-1749244800|2025-06-06T00:00:00.0000000Z|<metadata>|0000...0000|example-workspace"
$tmpFile = [System.IO.Path]::GetTempFileName()
Set-Content -LiteralPath $tmpFile -Value $content -Encoding utf8 -NoNewline
$hash = (Get-FileHash -LiteralPath $tmpFile -Algorithm SHA256).Hash
Remove-Item $tmpFile
$hash -eq "a1b2c3..."  # 应为 $true
```

## 操作日志链

`adpos workspace evidence -Log -Operation <op> [-Details <text>]` 记录操作日志条目。每个条目包含：

- `operation` — 操作类型（`create`、`sync`、`start`、`stop`、`validate`、`declare`、`snapshot`、`export`）
- `timestamp` — UTC ISO 8601 时间戳
- `user` — 当前用户
- `details` — 可选自由格式详情
- `sha256_hash` — `operation|timestamp|user|details|previous_hash` 的 SHA-256 哈希值
- `previous_hash` — 前一个条目的哈希值

### 追溯操作历史

查看完整的操作历史：

```powershell
$log = Get-Content .evidence/operation-log.json | ConvertFrom-Json
$log.entries | Select-Object timestamp, operation, user, details
```

要验证整个日志链，遍历每个条目并重新计算其哈希值，与记录值进行比较。如果任何条目的哈希值不匹配，则链已被篡改。

## 证据导出

`adpos workspace evidence -Export [-Path <path>]` 将所有证据打包为 ZIP 文件。

ZIP 包含：

| 文件 | 描述 |
| --- | --- |
| `README.txt` | 自动生成的导出清单，包含文件描述和验证说明 |
| `snapshot-hashes.json` | 快照签名链 |
| `operation-log.json` | 操作日志链 |
| `workspace-report.md` | 工作区报告（如果存在） |
| `adp-workspace.json` | 导出时的工作区 manifest |

默认情况下，ZIP 保存到当前目录为 `evidence-export-<timestamp>.zip`。使用 `-Path` 指定自定义输出路径或目录。

## AI 开发声明

`adpos workspace declare -AiAssisted [-Reviewer <name>] [-Notes "..."]` 在证据链中记录一条正式声明，表明某段代码是 AI 辅助开发的。

声明以 `DECLARE` 操作日志条目附加，详情包含：

- `declaration_type=ai-assisted`
- `reviewer=<name>`（如果提供）
- `notes=<text>`（如果提供）

```powershell
# 最少参数：仅声明 AI 辅助
adpos workspace declare -AiAssisted

# 带审查者和备注
adpos workspace declare -AiAssisted -Reviewer "alice" -Notes "Claude 生成了初始实现；alice 审查了所有逻辑路径"
```

这将创建一个可审计的记录，表明 AI 参与了开发、谁进行了审查以及关于 AI 角色的任何上下文。

## 验证证据完整性

### 手动验证

对于两个文件中的每个条目，重新计算 SHA-256 哈希值：

```powershell
# 对于快照条目：
$entry = $chain[0]
$content = "$($entry.snapshot_id)|$($entry.timestamp)|$metadataContent|$($entry.previous_hash)|$($entry.workspace_name)"
$computed = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($content))) -Algorithm SHA256).Hash

# 对于日志条目：
$entry = $logData.entries[0]
$content = "$($entry.operation)|$($entry.timestamp)|$($entry.user)|$($entry.details)|$($entry.previous_hash)"
$computed = (Get-FileHash -InputStream ([System.IO.MemoryStream]::new([System.Text.Encoding]::UTF8.GetBytes($content))) -Algorithm SHA256).Hash
```

### 链链接验证

每个条目的 `previous_hash` 必须匹配前一个条目的 `sha256_hash`（第一个条目为零哈希）。遍历链：

```text
条目 0: previous_hash = 0000...0000 (创世)
条目 1: previous_hash = sha256_hash(条目 0)  ✓
条目 2: previous_hash = sha256_hash(条目 1)  ✓
...
```

如果任何链接断开，证据已被修改。

### 哈希覆盖范围

哈希覆盖完整的条目内容，包括前一个哈希值。这意味着：

- **修改任何字段**（时间戳、详情、用户等）会改变哈希值
- **插入条目**会破坏下一个条目的 `previous_hash`
- **删除条目**会导致下一个条目指向不存在的哈希值
- **重新排序条目**是不可能的，因为每个条目都引用前一个哈希值

链按设计是仅追加的：新条目只能添加在末尾，链接到最新的哈希值。

## 常见问题

**问：证据文件存储在哪里？**
答：在 `<workspace_root>/.evidence/` 下。`.evidence` 目录在首次使用时自动创建。

**问：可以手动编辑证据文件吗？**
答：不应这样做。手动编辑几乎必然会破坏哈希链。这些文件设计为机器写入和机器验证。

**问：证据链能防止恶意修改吗？**
答：它能检测恶意修改。它不能阻止修改——有文件系统访问权限的人仍然可以编辑文件。但任何修改都会破坏哈希链，使篡改在验证时可以被检测到。

**问：可以重置证据链吗？**
答：删除 `.evidence/` 目录即可从头开始。这是有意为之——链是按工作区的，初始为空。

**问：证据文件会提交到 Git 吗？**
答：这取决于您的工作流。`.evidence/` 目录不在默认的 `.gitignore` 中。如果提交证据文件，它们将成为仓库审计轨迹的一部分。

**问：SHA-256 是如何计算的？**
答：ADP-OS 将内容字符串写入临时 UTF-8 文件（无 BOM 或尾随换行符），然后使用 PowerShell 的 `Get-FileHash -Algorithm SHA256`。

**问：可以使用 JSON 输出来编写脚本吗？**
答：可以。使用 `-Json` 开关：
```powershell
adpos workspace evidence -Snapshot -Json -ManifestPath ... | ConvertFrom-Json
```
