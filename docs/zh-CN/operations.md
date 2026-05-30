# 操作指南

简体中文 | [English](../operations.md)

本文档覆盖 ADP-OS 的日常操作。

## 健康检查

运行：

```powershell
.\cli\adp.ps1 doctor
```

期望结果：

```text
All checks passed. Platform is healthy.
```

首次使用时可以附加检查清单：

```powershell
.\cli\adp.ps1 doctor -FirstRun
```

`doctor` 会检查平台前置条件、配置结构、本地覆盖状态、VMware 工具、可探测时的 VMware NAT host match、Mutagen 版本、ISO cache、运行时拓扑、静态 IP 唯一性、静态 IP 网段、跨 VMX path 的 duplicate running ADP runtime 名称、已有 runtime 的 seed network drift、VM 状态、运行中 VM 的 SSH 可达性，以及 Mutagen sessions。

预览本地 Mutagen 修复：

```powershell
.\cli\adp.ps1 doctor -FixMutagen -Plan
```

确认计划后，再安装经过测试的本地 Mutagen binary：

```powershell
.\cli\adp.ps1 doctor -FixMutagen
```

`-FixMutagen` 会把 Mutagen 0.18.x 安装到 `.tools\mutagen\mutagen.exe`，并验证安装后的版本。安装路径会打印明确阶段、下载 source/target、offline archive path、连接和 hard timeout、可选 SHA256 状态、干净的失败输出，以及下载失败时的手动恢复路径。`.tools` 目录已被 Git 忽略，因此下载的 archive 和本地 binary 不会被提交。

如果 GitHub release 下载很慢或不可达，请使用 offline archive path，不要依赖网络下载：

```powershell
New-Item -ItemType Directory -Path .tools\mutagen -Force
# 通过浏览器或其他可信渠道下载此文件：
# https://github.com/mutagen-io/mutagen/releases/download/v0.18.1/mutagen_windows_amd64_v0.18.1.zip
# 保存为：
# .tools\mutagen\mutagen_windows_amd64_v0.18.1.zip
.\cli\adp.ps1 doctor -FixMutagen
```

如果需要自定义本地 archive、mirror 或 timeout policy，可以在被忽略的 `configs\local.json` 中设置 `platform.tools.mutagen`：

```json
{
  "platform": {
    "tools": {
      "mutagen": {
        "download_url": "https://example.invalid/mutagen_windows_amd64_v0.18.1.zip",
        "archive_path": "D:\\Downloads\\mutagen_windows_amd64_v0.18.1.zip",
        "sha256": null,
        "connection_timeout_seconds": 30,
        "download_timeout_seconds": 300
      }
    }
  }
}
```

当 `sha256` 是 64 位十六进制 hash 时，ADP 会在解压前校验 archive，不匹配则失败。当 `sha256` 为 `null` 时，archive hash verification 会被跳过，但 ADP 仍会验证解压出的 `mutagen.exe` 是否报告支持的 `0.18.x` 版本。

运行集成检查：

```powershell
.\tests\validate.ps1
```

如需运行单项检查：

```powershell
.\tests\validate.ps1 -Quick
.\tests\cli-smoke.ps1
.\tests\install-smoke.ps1
.\test-integration.ps1
.\deploy-check.ps1
```

`validate.ps1` 是 CI 仓库验证在本地的同一入口。它会运行 PowerShell 解析、JSON 解析、CLI 参数契约、配置 schema 检查、artifact hygiene 检查、CLI smoke tests、installer smoke tests、bootstrap shell syntax 检查、Markdown 本地链接检查和文档语言链接检查。文档语言检查还会验证根目录公开文档和 `docs/zh-CN` 的翻译文件成对存在。本地迭代时可使用 `-Quick`；它保留 parser、schema、contract、artifact hygiene、shell、Markdown 和文档检查，但跳过较慢的 CLI 与 installer smoke tests。局部排障时可使用 `-SkipCliSmoke`、`-SkipInstallerSmoke` 或 `-SkipShellSyntax`。

`cli-smoke.ps1` 会检查命令分发、非破坏性预览和输入错误边界。它不会创建、启动、停止、同步或销毁 VM。

`install-smoke.ps1` 使用临时 `USERPROFILE` 检查 installer 诊断和本地状态写入。它不会使用真实用户 profile，不会下载依赖，不会验证 VMware，不会创建 VM，也不要求真实 ISO。

Installer 排障开关：

```powershell
.\install.ps1 -SkipDependencyCheck
.\install.ps1 -SkipVMValidation
```

这些开关主要用于受控排障和类似 CI 的验证路径。正常首次安装不建议使用。

`install.ps1` 和 `doctor` 会检查首次创建运行时所需的主机前置条件：

- VMware `vmrun.exe`。
- VMware `vmware-vdiskmanager.exe`。
- WSL 和 WSL `xorriso`。
- ISO remaster 工具。
- Mutagen 0.18.x。
- OpenSSH Client。
- ISO 是否存在以及基本形态。

这些检查会输出修复建议。默认不会下载 VMware、Mutagen、浏览器、ISO 镜像或其他大型二进制文件。Mutagen 安装必须通过 `doctor -FixMutagen` 显式触发。

## 启动运行时

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 up backend
.\cli\adp.ps1 up agent
```

如果 VM 已存在且正在运行，ADP 会报告当前 IP 并跳过创建。

启动后，ADP 会打印配置中的连接目标、SSH 命令、SSH alias、workspace path、sync 命令和 status 命令。连接目标来自合并后的配置；如果存在 `configs\local.json`，也会包含其中的覆盖值。

`agent` 运行时可能会打印 high-IO profile 提示。这不是错误；它表示该运行时面向 AI agent 工作负载配置，执行破坏性或大范围任务前建议先创建快照。

首次创建 VM 时包含较长的 Ubuntu autoinstall 阶段。ADP 会明确说明这是 watched OS installation，不是 CLI 卡住，然后用可复制的 plain `[install monitor] INSTALLING Ubuntu in VM` 心跳持续显示安装状态。每条心跳都会先显示人能直接理解的安装标题，再显示诊断字段，因此即使只看到日志尾部，也能判断 VM 仍在安装，而不是卡在 IP 或 SSH probe。结构化细节包括 `state=installing`、`activity=installing-ubuntu`、`status=watching`、`current-op=readiness-check`、`wait-mode=watched`、`progress=indeterminate`、`user-action=keep-open`、`diagnostics=vmware-console-after-20min`、`phase=ubuntu-autoinstall`、预期耗时、timeout、已用时间、剩余 timeout 时间、下一次检查间隔、已观察到的 readiness signals、下一次 readiness check，以及用户当前是否需要操作。由于这个阶段 Ubuntu 不会通过 VMware 暴露可靠的安装百分比，ADP 使用 indeterminate progress model：报告真实可观测信号，而不是伪造百分比。监控信号包括配置/static IP、VMware-reported IP、SSH key authentication，以及 `/home/adp/.adp-provisioned`。IP 和 SSH probes 是 install monitor 内部的 readiness signals；只要心跳标题仍显示 `INSTALLING Ubuntu in VM`，重复 probe failure 不代表 ADP 卡住。正常安装期间，同一个信号可能会在 Ubuntu boot、install、reboot 或准备目标用户时重复数分钟，因此重复心跳会包含 `normal=yes`。ADP 会在每次心跳中解释 unchanged signals 在 OS installation 期间可能是正常现象，说明何时重新检查 readiness，提示继续保持命令运行、不要手动 SSH；只有当同一信号重复约 20 分钟或达到 timeout 时，才建议检查 VMware console。在这个阶段，SSH 22 端口可能先变为可达，但安装后的系统还没有接受 ADP key，也还没有写入 provision marker；这种中间态会显示为 `auth-pending`，不代表 runtime 已完成。

不创建、不启动、不 provisioning、不 bootstrap VM，只预览启动计划：

```powershell
.\cli\adp.ps1 up agent -Plan
```

只创建 VM 定义，不启动 OS provisioning 或 bootstrap：

```powershell
.\cli\adp.ps1 up agent -NoProvision
```

初始化平台状态，并创建运行时 VM 定义，但不启动 OS provisioning：

```powershell
.\cli\adp.ps1 init agent -SkipProvision
```

首次创建运行时时，可以从任意位置传入 ISO：

```powershell
.\cli\adp.ps1 up agent -IsoPath D:\Share\ubuntu-26.04-live-server-amd64.iso
```

`-IsoPath` 会直接用于 VM 创建，不需要位于配置的 ISO cache 中。

首次创建新 VM 前，`adp up <runtime>` 会在 host 暴露相关信息时，比对配置的 VMware NAT CIDR 和 host `VMnet8` 网络。如果二者不一致，ADP 会在创建 VM 前退出，并给出两条修复路径：用 `.\cli\adp.ps1 network configure-local -Plan` 和 `.\cli\adp.ps1 network configure-local -Apply` 将 ADP 本机 override 对齐到 host `VMnet8`，或保留 ADP 配置的 subnet 并在 VMware Virtual Network Editor 中修改 `VMnet8`。这可以避免新 VM 被安装到 host 无法访问的静态 IP 上。

## 停止运行时

```powershell
.\cli\adp.ps1 stop frontend
```

该命令会先尝试 soft stop，必要时再 hard stop。

## 运行时状态

查看所有运行时状态和连接信息：

```powershell
.\cli\adp.ps1 status
```

查看单个运行时：

```powershell
.\cli\adp.ps1 status frontend
```

`status` 是非破坏性的。它不会创建、启动、停止、同步、创建快照，也不会编辑 guest 文件。它会报告：

- `configs\local.json` 是不存在、为空、已应用，还是使用了不支持的字段。
- 配置的 VMware NAT CIDR 和 gateway。
- 每个运行时的 VM 状态。
- 合并后的 topology 中配置的 static IP。
- VMware 可探测到的 IP（如果可用）。
- VMware 中是否有其他 `adp-<runtime>.vmx` 从当前 checkout 外部运行，造成 duplicate running ADP runtime。
- 已有 autoinstall seed 仍包含旧 static IP 时的 network drift。
- 运行中 VM 的 SSH 状态：`reachable`、`auth-pending`、`unreachable`、`ambiguous-duplicate`，或 `key-missing` 等本地前置条件状态。
- Mutagen sync session 是否存在。
- 具体 SSH 命令、SSH alias、workspace path 和下一步命令。

如果 VMware 探测到的 IP 与配置的 static IP 不同，ADP 仍会把配置的 static IP 显示为连接目标。这是静态网络的预期行为，也能让你在编辑 `configs\local.json` 修改本机 NAT 网段后直接看到实际使用的地址。

如果 `status` 报告 `duplicate VM`，说明另一个 checkout 或 stale VM store 中有同名 runtime VMX 正在运行。请先停止或重命名这个 stale duplicate，再继续诊断 SSH、detected IP 或 network drift；否则 VMware 可能返回另一个同名 runtime 的 IP，而当前 checkout 期望的是不同的 VMX path。

当存在 duplicate 时，`status` 会把 SSH 报告为 `ambiguous-duplicate`，因为即使连接配置 IP 成功，也不能证明响应的是当前 checkout 对应的 VMX。

如果 `status` 报告 `network drift`，说明该 VM 是用比当前配置更旧的 seed 网络创建的。VM 创建完成后再编辑 `configs\local.json` 不会自动重写 guest 内部网络。根据实际情况选择 remediation path：

- VM 可以重建时走 rebuild path。先用 `.\cli\adp.ps1 destroy <runtime> -Plan` 预览，再用 `.\cli\adp.ps1 up <runtime>` 重建。
- seed-era address 仍可达时走 in-place guest netplan fix。先用 `.\cli\adp.ps1 network apply <runtime> -Plan` 预览；确认会 SSH 到预期 guest 后，再去掉 `-Plan` 执行。
- 只有必须先恢复到 seed-era address 的 SSH 时，才考虑 administrator-only temporary host-route workaround。ADP 不会自动添加、修改或删除 host routes。

如果 `status` 报告 `auth-pending`，说明 SSH 端口已经打开，但 ADP key 还没有被接受。首次 autoinstall 期间这通常表示 installer 或 first boot 仍在准备目标用户。请等待到 timeout，或者在该状态长时间不变化时检查 VMware console。

## SSH 访问

```powershell
ssh -i $env:USERPROFILE\.ssh\adp-os\adp-os adp@192.168.242.131
```

默认地址见[网络说明](networking.md)。如果你用 `configs\local.json` 覆盖了 `topology.<runtime>.static_ip`，启动后运行 `.\cli\adp.ps1 status <runtime>`，然后连接输出中显示的地址。

## 工作区同步

启动同步前，将目标项目 clone 到匹配的 Windows workspace root 下。推荐布局和 dogfooding 指南见[工作区](workspaces.md)。

启动同步：

```powershell
.\cli\adp.ps1 sync start frontend
```

检查同步：

```powershell
.\cli\adp.ps1 sync status
```

停止同步：

```powershell
.\cli\adp.ps1 sync stop frontend
```

Mutagen sessions 名称：

```text
adp-frontend
adp-backend
adp-agent
```

## 前端浏览器测试

Frontend 运行时包含轻量浏览器验收辅助命令。它们不会在 bootstrap 时安装浏览器二进制。

检查就绪状态：

```powershell
ssh adp-os-adp-frontend
adp-frontend-browser-check
```

按需安装 Chromium 支持：

```bash
adp-frontend-browser-install chromium
```

然后从同步工作区运行项目测试：

```bash
cd /home/adp/workspace
pnpm install
pnpm exec playwright test
```

浏览器下载保留在 VM 用户缓存中。`playwright-report`、`test-results` 和 `blob-report` 等生成报告会被 frontend 同步 profile 忽略。

## 快照和恢复

创建 baseline 快照：

```powershell
.\cli\adp.ps1 snapshot create frontend clean
```

恢复：

```powershell
.\cli\adp.ps1 restore frontend clean
```

快照是 VMware snapshots，在运行中的 VM 上可能需要几分钟。ADP 会在超时后验证快照是否存在，以避免误报失败。

## 销毁运行时

```powershell
.\cli\adp.ps1 destroy frontend
```

销毁运行时会删除该运行时的 VM 文件。`%USERPROFILE%\adp-workspaces` 下的工作区数据是独立的。

先预览删除计划：

```powershell
.\cli\adp.ps1 destroy frontend -Plan
```

## 重新应用网络

```powershell
.\cli\adp.ps1 network apply all
```

编辑 `configs\platform.json`、`configs\topology.json`，或 `configs\local.json` 中受支持的 `platform`/`topology` 字段后使用此命令。

在任何 VM 存在之前，可以用下面的命令把本机 NAT 设置对齐到 host `VMnet8`，且不会触碰 VM：

```powershell
.\cli\adp.ps1 network configure-local -Plan
.\cli\adp.ps1 network configure-local -Apply
```

`configure-local -Plan` 会预览探测到的 host NAT subnet、目标 gateway/DNS、推导出的 runtime static IP，以及字段级 local config 变更。裸 `configure-local` 同样不会修改文件。只有在审阅 plan 后才使用 `-Apply`；它只会更新 `configs\local.json`，并把已有文件备份为 `configs\local.json.bak.<timestamp>`。如果你想保留 ADP 配置的 subnet，请改为在 VMware Virtual Network Editor 中修改 `VMnet8`，不要应用本机 override。

可以先预览 guest 网络改动：

```powershell
.\cli\adp.ps1 network apply all -Plan
```

当 `network apply -Plan` 检测到 seed-network drift 时，会打印同一套 remediation 划分：rebuild path、in-place guest netplan path 和 administrator-only host-route workaround。该命令只通过 SSH 管理 guest netplan 文件；不会重建 VM，也不会修改 host routes。
