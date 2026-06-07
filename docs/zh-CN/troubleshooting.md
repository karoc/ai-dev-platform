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

从 stock Windows shell 运行时，优先使用 wrapper 形式，例如 `.\adp.cmd doctor`。如果未安装 `pwsh.exe`，先运行 `.\setup.cmd`；内置 Windows PowerShell 5.1 只是 bootstrap 路径，不运行 ADP-OS control plane。

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
| 机器只有 Windows PowerShell 5.1 | `.\setup.cmd` | PowerShell 7 bootstrap | [README](../../README.zh-CN.md#环境要求) |
| 缺少必要工具 | `.\cli\adp.ps1 doctor` | VMware、WSL、xorriso、Mutagen、OpenSSH | [操作指南](operations.md#健康检查) |
| Mutagen 缺失或版本不对 | `.\cli\adp.ps1 doctor -FixMutagen -Plan` | local Mutagen remediation、offline archive、可选 SHA256 | [操作指南](operations.md#健康检查) |
| Runtime startup 使用了非预期 ISO path | `.\cli\adp.ps1 up <runtime> -IsoPath <path> -Plan` | explicit ISO path、local config | [操作指南](operations.md#启动运行时) |
| Runtime 已存在但无法连接 | `.\cli\adp.ps1 status <runtime>` | VM state、static IP、SSH reachability | [操作指南](operations.md#运行时状态)、[网络说明](networking.md) |
| Runtime 创建看起来卡住 | 只要 `[安装监视器] 正在 VM 中安装 Ubuntu` 或 `[install monitor] INSTALLING Ubuntu in VM` 心跳仍在继续，就保持 `adp up <runtime>` 运行；如果该 VM 本应已预先 provisioned，转入 `status`、`doctor` 和 network drift 检查 | Ubuntu autoinstall、first boot、IP/SSH/provision marker readiness signals、stale VM networking | [操作指南](operations.md#启动运行时) |
| `status` 报告 `auth-pending` | 等待后再次运行 `.\\cli\\adp.ps1 status <runtime>` | SSH 端口已打开，但 ADP key/user 尚未 ready | [操作指南](operations.md#运行时状态) |
| SSH 连接失败，提示 `Permission denied` | `.\\cli\\adp.ps1 status <runtime>` | SSH 密钥不匹配，VM 是用不同密钥创建的 | [操作指南](operations.md#ssh-密钥故障排除) |
| `status` 报告 `key-missing` | 运行任意 `adp up` 或 SSH 操作 | SSH 密钥对尚未创建 | [操作指南](operations.md#ssh-密钥故障排除) |
| SSH 密钥被意外删除 | 运行任意 SSH 操作后会重新生成 | `%USERPROFILE%\\.ssh\\adp-os\\` 密钥对缺失 | [操作指南](operations.md#ssh-密钥故障排除) |
| `up` 因 VMware NAT mismatch 停止 | `.\cli\adp.ps1 network configure-local -Plan` | host VMnet8 与 local config 不一致 | [网络说明](networking.md#前置条件)、[配置说明](configuration.md#本地覆盖) |
| `status` 报告 `duplicate VM` | `.\cli\adp.ps1 doctor` | 另一个 checkout 或 stale VM store 中有同名 runtime 正在运行 | [操作指南](operations.md#运行时状态) |
| `status` 报告 network drift | `.\cli\adp.ps1 doctor` 和 `.\cli\adp.ps1 network apply <runtime> -Plan` | 已有 VM seed 网络与当前配置不一致；rebuild、guest netplan fix 或 host-route workaround | [操作指南](operations.md#运行时状态)、[网络说明](networking.md#新-vm-的静态网络) |
| VMware IP 与配置的 static IP 不同 | `.\cli\adp.ps1 status <runtime>` | static networking、local NAT overrides | [网络说明](networking.md#前置条件) |
| Static IP 不在 NAT subnet 内 | `.\cli\adp.ps1 doctor` | topology 和 platform config | [配置说明](configuration.md#本地覆盖)、[网络说明](networking.md) |
| Sync 无法启动或缺失 | `.\cli\adp.ps1 sync status` | Mutagen sessions、stale endpoints、SSH aliases、workspace paths | [操作指南](operations.md#工作区同步) |
| Frontend browser tests 无法运行 | 在 frontend runtime 内运行 `adp-frontend-browser-check` | on-demand browser install | [浏览器测试](browser-testing.md) |
| Workspace task 被阻塞 | `.\cli\adp.ps1 workspace report` | validation、review、snapshot、governance gates | [工作区](workspaces.md)、[Release Readiness](release-readiness.md) |
| 高风险 agent work 尚未 ready | `.\cli\adp.ps1 workspace dashboard` | snapshot-first gate | [工作区](workspaces.md)、[Release Readiness](release-readiness.md) |
| `snapshot create` 看起来卡住 | 继续运行或重新演示前，先确认 snapshot 是否已经存在 | VMware snapshot command return、rollback checkpoint | [生存验证](survival-validation.md#demo-就绪清单) |
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

## 预先创建的 Runtime 仍看起来像 Installing

首次创建期间，重复出现 `[install monitor] INSTALLING Ubuntu in VM` 或 `[安装监视器] 正在 VM 中安装 Ubuntu` 心跳可能是正常现象。不要仅因为 SSH 或 IP probe 重复，就中断真实首次安装。

但如果 runtime 本应已经预先 provisioned，规则就不同。survival rehearsal 中，如果已有 `agent` VM 仍被描述为 installing，不要无限等待，改为运行 diagnostics：

```powershell
.\adp.cmd status agent
.\adp.cmd doctor
.\adp.cmd network apply agent -Plan
.\adp.cmd sync status
```

如果 VMware 报告的 guest IP 不在当前 ADP NAT subnet 内，或 `status` / `doctor` 报告 `network drift` / `seed network drift`，应把该 VM 当作 stale networking。旧 VM 可能是在静态网络 seed 注入之前创建的，因此 guest 已经 fully provisioned，但仍启动到旧 VMware NAT 地址，而 ADP-OS 当前不再使用该地址。

显式选择一种 remediation path：

- VM 可以重建时，重建该 runtime。
- 旧 guest address 可通过 SSH 访问时，使用 `network apply agent -Plan` 规划原地修复。
- 只有为了先恢复到旧 guest address 的 SSH 时，才使用 administrator-only temporary host-route workaround。ADP 不会自动添加、修改或删除 host routes。

不要把这种运行计为有效 10 分钟 demo。它是 product-readiness 或本机 stale-state 问题，必须在展示 rollback 和 evidence 价值前解决。

## Snapshot 命令看起来卡住

`adp snapshot create <runtime> <name>` 位于 rollback-critical path。如果它看起来卡住，在 checkpoint 被确认前，不要继续高风险 agent work 或 survival demo。

先确认 snapshot 是否已经创建：

```powershell
vmrun.exe listSnapshots <path-to-runtime.vmx>
.\adp.cmd snapshot create agent <name>
```

如果目标 snapshot 已存在，重新运行 `adp snapshot create` 应该报告它已经存在。如果 VMware 已创建 snapshot，但 ADP-OS 没有及时返回，应把这次彩排记录为产品失败。即使 VM snapshot 存在，一个无法干净确认的 rollback checkpoint 也不能作为可接受的 demo evidence。

## Mutagen 下载问题

如果 `doctor -FixMutagen` timeout，或无法访问 GitHub releases，请保持修复路径本地且显式：

```powershell
.\cli\adp.ps1 doctor -FixMutagen -Plan
New-Item -ItemType Directory -Path .tools\mutagen -Force
# 将 mutagen_windows_amd64_v0.18.1.zip 放到 .tools\mutagen 后运行：
.\cli\adp.ps1 doctor -FixMutagen
```

如果 archive 存在其他位置，在被忽略的 `configs\local.json` 中设置 `platform.tools.mutagen.archive_path`。如果需要 mirror，设置 `platform.tools.mutagen.download_url`。如果需要严格校验 archive，设置 `platform.tools.mutagen.sha256` 为预期的 64 位 SHA256 hash。ADP 不会提交 archive 或 `mutagen.exe`；`.tools` 始终被忽略。

## Sync Session 问题

如果 `sync status`、`status` 或 `doctor` 报告 `wrong-local`、`wrong-remote` 或 `unhealthy`，说明 Mutagen session 虽然存在，但不匹配当前 checkout/runtime，或者当前不可用。移动 workspace、切换 clone、重建 VM，或复用了另一个 setup 中同名的 `adp-<runtime>` session 后，都可能出现这种情况。

使用显式 reset 路径：

```powershell
.\\cli\\adp.ps1 sync stop agent
.\\cli\\adp.ps1 sync start agent
.\\cli\\adp.ps1 sync status
```

如果 runtime 尚未在当前 checkout 创建，`sync status`、`status` 和 `doctor` 可能会把同一个 stale session 报告为 `stale-session` 或 cleanup guidance。这还不是 VM 健康失败。先停止 stale session，创建 runtime，然后再启动 sync。

`sync start <runtime>` 不会静默替换不可用的同名 session。它会要求显式执行 stop/start，让用户清楚知道已有同步关系将被终止并重建。

这三个命令（`status`、`doctor` 和 `sync status`）现在会检测具体的恢复场景，并提供精确的修复步骤。创建新的 sync session 不会删除 workspace 文件。停止 stale session 只会移除 Mutagen session 定义——两侧的 workspace 文件保持不动。

## 单边 root 清空保护

如果 Mutagen 因 one-sided root emptying protection 而停止，说明同步 root 在一侧或两侧被清空，Mutagen 为了安全拒绝继续镜像删除。这是预期的保护行为，不是平台崩溃。通常会出现在清理 probe 文件，或者对同一个 workspace 的两侧都做过实验之后。

`doctor` 和 `status` 现在会检测此特定状态并显式标注，而不是报告通用的 `unhealthy` 同步状态。诊断输出包含：

- 发生了什么：哪个 session 触发了 root-emptying 保护
- 为什么发生：Mutagen 防止镜像意外删除的安全机制
- 恢复步骤：补回内容、停止、重启、验证

恢复方式是：重新从源头把一侧内容补回去，或者如果你本来就是要重来，则明确重建项目目录。然后显式重启 session：

```powershell
.\\cli\\adp.ps1 sync stop agent
.\\cli\\adp.ps1 sync start agent
.\\cli\\adp.ps1 sync status
```

如果项目应该从头重建，不要指望 Mutagen 自动把两个空 root 恢复成可用状态，应当有意重建。

无需同步即可检测 root-emptying：

```powershell
.\\cli\\adp.ps1 doctor            # 显示 [SYNC] 及恢复场景标题和步骤
.\\cli\\adp.ps1 status agent      # 显示 sync 恢复: 含详情和步骤
.\\cli\\adp.ps1 sync status       # 显示 session 健康分类
```

## 跨 Clone 的 Stale Session

如果你同时维护 ai-dev-platform 的多个本地 clone（常用于 dogfooding ADP-OS 同时开发），在其中一个 clone 创建的 Mutagen session 全局可见。在 `D:\\ai-dev-platform` 创建的 `adp-agent` session 也会出现在 `D:\\other-clone` 中，即使 workspace 路径不同。

这会导致 `status` 和 `doctor` 报告 `wrong-local` 或 `wrong-remote`，因为 session 存储的本地路径（来自创建它的 clone）与当前 checkout 的 workspace 路径不匹配。

`status`、`doctor` 和 `sync status` 现在会检测这种交叉并显式标注：

```
sync 恢复:     Sync session local endpoint mismatch
sync 详情:     Mutagen session 'adp-agent' 的本地路径来自
              另一个 checkout 或 clone。
sync 步骤:     此 session 很可能是在另一个 clone 中创建的。
sync 步骤:     如果另一个 clone 仍在活跃使用中，请确认哪个
              checkout 应拥有此 session。
sync 步骤:     如需为当前 checkout 重建: adp sync stop agent，
              然后 adp sync start agent
sync 安全:     停止 stale session 不会删除任何一侧的 workspace 文件。
```

停止前请先检查 session 是否仍在活跃使用中：

```powershell
.\\cli\\adp.ps1 sync list          # 显示所有 session 及其端点
.\\cli\\adp.ps1 status agent       # 显示预期当前 checkout 路径
```

如果另一个 clone 仍需要该 session，不要动它。如果不需要，从当前 checkout 停止并重建：

```powershell
.\\cli\\adp.ps1 sync stop agent
.\\cli\\adp.ps1 sync start agent
```

这是安全的：`sync stop` 仅终止 Mutagen session 定义。不会删除任何一侧的 workspace 文件。

## 运行时创建前的 Stale Session 清理

删除 VM（或切换到新 clone）后，该 runtime 的 Mutagen session 可能仍然全局存在。`sync status`、`status` 和 `doctor` 会将其报告为 `stale-session` 或 `sync 恢复: Stale sync session before runtime creation`。

这不是阻塞性故障——`doctor` 将其作为 info 级别的观察而非 issue。VM 已删除，但 Mutagen session 定义仍然保留。清理安全且直接：

```powershell
.\\cli\\adp.ps1 sync stop agent     # 停止 stale session
.\\cli\\adp.ps1 up agent            # 创建 runtime
.\\cli\\adp.ps1 sync start agent    # 启动新 sync session
```

诊断输出包含安全提示：停止 stale session 不会删除任何一侧的 workspace 文件。仅移除 Mutagen session 元数据。

在创建 runtime 之前检测 stale session：

```powershell
.\\cli\\adp.ps1 doctor              # 以 info 级别列出 stale session
.\\cli\\adp.ps1 sync status         # 显示 stale-session 及清理指导
.\\cli\\adp.ps1 status agent        # 显示 sync 恢复: 含详情和步骤
```

如果你打算保留另一个活跃的 clone，且该 session 属于它，在当前 checkout 中忽略 stale-session 报告即可。

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
