# 排障

简体中文 | [English](../troubleshooting.md)

本文把常见症状映射到最安全的首要检查。排障应先保持非破坏性：在修改 VM、网络、sync session 或本地配置前，先使用 diagnostics、status 和 plan previews。

如果需要创建公开 issue，请先阅读[支持说明](../../SUPPORT.zh-CN.md)，确认应该包含哪些 diagnostics，以及哪些内容不能公开。

## 首要检查

修改配置或重建 runtime 前，先运行：

```powershell
.\cli\adp.ps1 doctor
.\cli\adp.ps1 doctor -FirstRun
.\cli\adp.ps1 status
.\cli\adp.ps1 sync status
.\tests\validate.ps1 -Quick
```

建议保留这些上下文：

- Host OS 和 PowerShell version。
- VMware Workstation version。
- ADP-OS commit：`git rev-parse --short HEAD`。
- `configs\local.json` 是否存在，以及使用了哪些受支持的 top-level sections。
- 失败的完整命令。
- 第一条错误消息，以及它之前的命令输出。

不要公开 secrets、tokens、private keys、VM disks、ISO files、downloaded archives、大型 logs、private local paths 或 private maintainer context。

## 症状索引

| 症状 | 先运行 | 可能区域 | 后续文档 |
| --- | --- | --- | --- |
| 首次 setup 不清楚 | `.\cli\adp.ps1 doctor -FirstRun` | prerequisites、ISO、local overrides | [操作指南](operations.md)、[配置说明](configuration.md) |
| 缺少必要工具 | `.\cli\adp.ps1 doctor` | VMware、WSL、xorriso、Mutagen、OpenSSH | [操作指南](operations.md#健康检查) |
| Mutagen 缺失或版本不对 | `.\cli\adp.ps1 doctor -FixMutagen -Plan` | local Mutagen remediation | [操作指南](operations.md#健康检查) |
| Runtime startup 使用了非预期 ISO path | `.\cli\adp.ps1 up <runtime> -IsoPath <path> -Plan` | explicit ISO path、local config | [操作指南](operations.md#启动运行时) |
| Runtime 已存在但无法连接 | `.\cli\adp.ps1 status <runtime>` | VM state、static IP、SSH reachability | [操作指南](operations.md#运行时状态)、[网络说明](networking.md) |
| Runtime 创建看起来卡住 | 只要 `[install monitor] INSTALLING Ubuntu in VM` 心跳仍在继续，就保持 `adp up <runtime>` 运行 | Ubuntu autoinstall、first boot、IP/SSH/provision marker readiness signals | [操作指南](operations.md#启动运行时) |
| `status` 报告 `auth-pending` | 等待后再次运行 `.\cli\adp.ps1 status <runtime>` | SSH 端口已打开，但 ADP key/user 尚未 ready | [操作指南](operations.md#运行时状态) |
| `up` 因 VMware NAT mismatch 停止 | `.\cli\adp.ps1 doctor -FirstRun` | host VMnet8 与 local config 不一致 | [网络说明](networking.md#前置条件)、[配置说明](configuration.md#本地覆盖) |
| `status` 报告 `duplicate VM` | `.\cli\adp.ps1 doctor` | 另一个 checkout 或 stale VM store 中有同名 runtime 正在运行 | [操作指南](operations.md#运行时状态) |
| `status` 报告 network drift | `.\cli\adp.ps1 doctor` 和 `.\cli\adp.ps1 network apply <runtime> -Plan` | 已有 VM seed 网络与当前配置不一致；rebuild、guest netplan fix 或 host-route workaround | [操作指南](operations.md#运行时状态)、[网络说明](networking.md#新-vm-的静态网络) |
| VMware IP 与配置的 static IP 不同 | `.\cli\adp.ps1 status <runtime>` | static networking、local NAT overrides | [网络说明](networking.md#前置条件) |
| Static IP 不在 NAT subnet 内 | `.\cli\adp.ps1 doctor` | topology 和 platform config | [配置说明](configuration.md#本地覆盖)、[网络说明](networking.md) |
| Sync 无法启动或缺失 | `.\cli\adp.ps1 sync status` | Mutagen sessions、SSH aliases、workspace paths | [操作指南](operations.md#工作区同步) |
| Frontend browser tests 无法运行 | 在 frontend runtime 内运行 `adp-frontend-browser-check` | on-demand browser install | [浏览器测试](browser-testing.md) |
| Workspace task 被阻塞 | `.\cli\adp.ps1 workspace report` | validation、review、snapshot、governance gates | [工作区](workspaces.md)、[Release Readiness](release-readiness.md) |
| 高风险 agent work 尚未 ready | `.\cli\adp.ps1 workspace dashboard` | snapshot-first gate | [工作区](workspaces.md)、[Release Readiness](release-readiness.md) |
| 仓库验证失败 | 先运行 `.\tests\validate.ps1 -Quick`，再运行 targeted checks | parser、config schema、artifact hygiene、docs、issue templates、smoke tests | [操作指南](operations.md#健康检查) |
| 需要创建公开 issue | `.\cli\adp.ps1 doctor` 和相关 status output | support routing | [支持说明](../../SUPPORT.zh-CN.md) |

## 安全预览命令

在修改 runtime state 前，优先使用 plan 或 status commands：

```powershell
.\cli\adp.ps1 up agent -Plan
.\cli\adp.ps1 network apply all -Plan
.\cli\adp.ps1 destroy agent -Plan
.\cli\adp.ps1 doctor -FixMutagen -Plan
.\cli\adp.ps1 workspace plan
.\cli\adp.ps1 workspace report -Markdown
```

这些命令用于展示计划或收集 evidence。它们不会创建 snapshots、运行 task validation、stage 文件、commit 文件或 destroy VMs。

## 何时修改本地配置

当本机专属设置与已提交默认值不同时，使用被忽略的本地覆盖：

```powershell
Copy-Item configs\local.example.json configs\local.json
```

`configs\local.json` 适用于：

- 本机 VMware NAT subnet 差异。
- Runtime static IP 调整。
- 本机 VM sizing 调整。
- 机器专属路径。

编辑后运行：

```powershell
.\cli\adp.ps1 doctor
.\cli\adp.ps1 status
```

请在创建 VM 前完成这些修改。如果 VM 已存在，修改 `configs\local.json` 只会改变 ADP 的目标地址，不会自动重写旧 autoinstall seed 已安装到 guest 内部的网络。如果 `status` 报告 `network drift`，请显式选择 remediation path：

- VM 可以重建时，重建该 runtime。
- seed-era guest address 可达且希望原地修复 guest netplan 时，先运行 `network apply <runtime> -Plan`。
- 只有为了先恢复到 seed-era address 的 SSH 时，才使用 administrator-only temporary host-route workaround。ADP 不会自动应用 host routes。

如果 `status` 或 `doctor` 报告 duplicate running ADP runtime，请先处理它，再修改本地网络。来自另一个 checkout 的同名 VM 可能让 detected IP 和 SSH diagnostics 指向错误的 VM。

不要把 private local paths 或 credentials 粘贴到公开 issue。如果 issue 与 local config 有关，只列出受支持的 top-level sections，例如 `platform` 和 `topology`。

## 何时使用 Runtime 操作

只有当 status 和 plan output 已经清楚表达预期动作后，再使用会改变 runtime 的命令：

- 修改静态网络设置后，使用 `network apply`。
- 高风险或大范围 agent work 前，使用 `snapshot create`。
- 明确需要把 VM 回滚到已有 snapshot 时，使用 `restore`。
- 在 `destroy` 前先使用 `destroy -Plan`。

Workspace commands 会保持 review 和 commit boundaries 显式。`workspace task validate <task> -Execute` 只运行已声明的 validation commands，review、rollback、staging 和 commit 仍然是独立动作。

## 寻求帮助

创建公开 issue 前必须移除敏感信息。请包含：

- 症状。
- 你运行的命令。
- 第一条相关 diagnostic 的非敏感输出。
- Host 和工具版本。
- ADP-OS commit。
- 是否存在 local override。

使用 Usage question template 提问，使用 Bug report template 报告可复现失败，使用 Feature request template 提出产品或 workflow 改进。
