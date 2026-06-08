# 配置

简体中文 | [English](../configuration.md)

ADP-OS 通过 `configs` 目录中的 JSON 文件进行配置。

## `platform.json`

`configs\platform.json` 定义主机级路径、默认值、功能开关和网络。

重要路径：

```json
{
  "paths": {
    "workspace_root": "${env:USERPROFILE}\\adp-workspaces",
    "iso_cache": "${env:USERPROFILE}\\adp-iso",
    "vm_store": "${env:USERPROFILE}\\adp-vms",
    "logs": "${project:root}\\logs"
  }
}
```

路径占位符：

- `${env:NAME}` 从主机环境变量解析。
- `${project:root}` 解析为仓库根目录。

默认运行时用户：

```json
{
  "defaults": {
    "admin_user": "adp",
    "admin_password": "adp"
  }
}
```

默认密码用于本地自动 sudo bootstrap。在共享或不可信网络中使用 ADP 前，请修改它。

界面语言：

```json
{
  "ui": {
    "language": "en"
  }
}
```

支持的值为 `en` 和 `zh-CN`。已提交的默认值保持英文。可以使用被忽略的 `configs\local.json` 让本机默认使用简体中文，也可以为单次命令设置 `ADP_LANG=zh-CN`，无需修改文件：

```powershell
$env:ADP_LANG = "zh-CN"
adpos help
```

## `topology.json`

`configs\topology.json` 定义运行时规格和 profile。

示例：

```json
{
  "frontend": {
    "runtime": "vmware",
    "os": "ubuntu-26.04",
    "cpu": 4,
    "memory": 8192,
    "disk": 80,
    "workspace": "frontend",
    "sync_profile": "frontend",
    "bootstrap_profile": "frontend",
    "profile": "standard",
    "static_ip": "192.168.242.131",
    "ssh_port": 22
  }
}
```

字段：

- `runtime`：运行时载体，当前为 `vmware`。
- `os`：来自 `runtimes\vmware\os-profiles.ps1` 的 OS profile 名称。
- `cpu`、`memory`、`disk`：VM 规格。
- `workspace`：本地工作区子目录。
- `sync_profile`：`sync-profiles.json` 中的 profile。
- `bootstrap_profile`：`bootstrap` 下的 bootstrap 目录。
- `profile`：用户可见的运行时 profile。支持值为 `standard` 和 `agent-high-io`。CLI profile badge 和启动提示都从该字段生成，避免不同命令中的 profile 文案漂移。
- `static_ip`：用于 provisioning、CLI、SSH 和同步的 guest IP。
- `ssh_port`：guest SSH 端口。

## `sync-profiles.json`

Sync profiles 配置 Mutagen 行为和忽略列表。

```json
{
  "frontend": {
    "mode": "two-way-resolved",
    "ignore": ["node_modules", ".next", "dist", "build", "coverage", ".turbo", ".cache", "playwright-report", "test-results"]
  }
}
```

默认 sync profiles 会忽略常见依赖目录、构建输出、框架缓存、测试报告、Python virtual environments、Python cache，以及不应通过 Mutagen 复制的本地 ADP/Codex 工具状态。它们保持保守：源码文件、lockfile、manifest 和项目配置仍会同步。可以使用 `workspace status`、`workspace dashboard` 或 `workspace report` 查看某个同步项目是否仍有需要 review profile 的生成目录。

支持的同步模式取决于安装的 Mutagen 版本。本项目已使用 Mutagen `0.18.x` 测试。

## 本地覆盖

`configs\local.json` 是已被忽略的本机覆盖文件。它适合存放主机路径、ISO cache 中使用的 ISO 文件名、本机 VM 规格、静态 IP、本地 bootstrap 凭据、Mutagen archive mirror 等本机工具获取设置、runtime resource namespace 实验，以及不应该提交的同步忽略规则调整。

对于第二个 checkout 或并行的本地版本，请在创建或启动 runtime 前先完成隔离配置。至少要为当前 checkout 计划检查或运行的 runtime 配置不同的 `workspace_root`、`vm_store` 和 `topology.<runtime>.static_ip`：

```json
{
  "platform": {
    "runtime_namespace": "v2",
    "paths": {
      "workspace_root": "D:\\ADP-v2\\workspaces",
      "vm_store": "D:\\ADP-v2\\vms"
    }
  },
  "topology": {
    "agent": {
      "static_ip": "192.168.242.145"
    }
  }
}
```

`platform.runtime_namespace` 是可选字段，默认 `null` 会保留旧资源名：资源 `agent`、VM `adp-agent`、SSH alias `adp-os-adp-agent`、Mutagen session `adp-agent`。设置为 `v2` 这类值后，runtime resource profile 会使用资源 `v2-agent`、VM `adp-v2-agent`、SSH alias `adp-os-adp-v2-agent`、Mutagen session `adp-v2-agent`。

这个 namespace 会影响 `status`、`doctor`、`sync`、`up -Plan`，以及 `up` 的首次 VM 创建。设置 `platform.runtime_namespace` 为 `v2` 后，`adpos up agent` 会创建或启动 VM `adp-v2-agent`，而不是旧的 `adp-agent`。它不会迁移已有 legacy VM，不会自动分配 static IP，不会重写 guest networking，不会修复 NAT mismatch，也不会让全局 `adpos` 同时绑定多个 checkout。并行版本仍要保持 `workspace_root`、`vm_store` 和每个活跃 runtime 的 `static_ip` 互不相同。

全局 `adpos` 命令同一时间只能指向一个 checkout。如果它归属于另一个 checkout，请在第二个 checkout 中使用 `.\adpos.cmd doctor`、`.\adpos.cmd status agent` 和 `.\adpos.cmd up agent -Plan` 运行本地诊断。

从示例开始：

```powershell
Copy-Item configs\local.example.json configs\local.json
```

示例：

```json
{
  "platform": {
    "paths": {
      "workspace_root": "D:\\ADP\\workspaces",
      "iso_cache": "D:\\ADP\\iso",
      "vm_store": "D:\\ADP\\vms"
    },
    "defaults": {
      "iso_path": "ubuntu-26.04-live-server-amd64.iso",
      "admin_user": "adp",
      "admin_password": "change-this-local-password"
    },
    "ui": {
      "language": "zh-CN"
    },
    "tools": {
      "mutagen": {
        "download_url": "https://github.com/mutagen-io/mutagen/releases/download/v0.18.1/mutagen_windows_amd64_v0.18.1.zip",
        "archive_path": "D:\\Downloads\\mutagen_windows_amd64_v0.18.1.zip",
        "sha256": null,
        "connection_timeout_seconds": 30,
        "download_timeout_seconds": 300
      }
    },
    "network": {
      "vmware_nat": {
        "cidr": "192.168.242.0/24",
        "gateway": "192.168.242.2"
      }
    }
  },
  "topology": {
    "frontend": {
      "memory": 12288,
      "static_ip": "192.168.242.131"
    },
    "agent": {
      "memory": 24576,
      "disk": 240
    }
  },
  "sync_profiles": {
    "frontend": {
      "ignore": ["node_modules", ".next", "dist", "build", "coverage", ".turbo", ".cache", "playwright-report", "test-results", "blob-report", ".playwright"]
    }
  }
}
```

支持的顶层字段：

- `platform`：合并到 `configs\platform.json`。
- `topology`：合并到 `configs\topology.json`。
- `sync_profiles`：合并到 `configs\sync-profiles.json`。

JSON object 会递归合并。数组和标量值会替换默认值，因此本地 `sync_profiles.<name>.ignore` 覆盖应包含你仍然想保留的所有默认忽略路径。空的 `configs\local.json` 会被忽略。

`platform.defaults.iso_path` 会在 `platform.paths.iso_cache` 内解析。如果要从任意位置导入 ISO，请运行 `.\setup.cmd -IsoPath C:\path\to\ubuntu-26.04-live-server-amd64.iso`；setup 会把它复制到配置的 ISO cache。

`platform.ui.language` 控制已接入本地化的 installer 和 CLI 用户可见语言。当前支持的值为 `en` 和 `zh-CN`。`ADP_LANG` 优先级高于配置，适合单次命令临时切换，因此用户可以在当前 shell 中设置 `ADP_LANG=zh-CN`，而不必编辑 `configs\local.json`。不支持的值会回退到英文。

简体中文覆盖全新部署主路径的关键输出：`setup.cmd`、`adpos help`、`adpos init`、`adpos doctor -FirstRun`、`adpos doctor -FixMutagen -Plan`、`adpos up <runtime> -Plan`、主要 `adpos up <runtime>` 用户提示、`adpos status [runtime]`，以及 `adpos network configure-local [-Plan|-Apply]`。部分低层诊断检查名和机器可读状态值会有意保留英文，以便日志可搜索、支持输出保持稳定。

`platform.tools.mutagen` 只影响显式执行的 `adpos doctor -FixMutagen` 修复路径。当 GitHub release 下载很慢或不可达时可以使用它：

- `download_url`：ADP 需要下载 Mutagen 时使用的 archive URL。
- `archive_path`：可选本地 archive 路径。设置后，ADP 会把该 archive 复制到被忽略的 `.tools\mutagen`，而不是下载。
- `sha256`：可选的 64 位 archive hash。设置后，ADP 会在解压前校验 archive。
- `connection_timeout_seconds` 和 `download_timeout_seconds`：受控下载进程的 timeout 值。

下载的 archive、复制的 archive 和 `mutagen.exe` 都保留在被忽略的 `.tools\mutagen` 下，不能提交。

如果不同机器上的 VMware NAT 设置不同，优先使用：

```powershell
adpos network configure-local -Plan
adpos network configure-local -Apply
```

该命令会探测 host `VMnet8`，预览目标 `platform.network.vmware_nat` 和 `topology.<runtime>.static_ip` 值；只有显式使用 `-Apply` 时才会写入本地配置。使用 `-Apply` 时，命令只更新被忽略的 `configs\local.json` override，并把已有本地文件备份为 `configs\local.json.bak.<timestamp>`。当 host 探测不可用，或你希望保留 ADP 配置的 subnet 并在 VMware Virtual Network Editor 中修改 `VMnet8` 时，仍然可以手动编辑。如有需要，请在 VMware Workstation 的 Virtual Network Editor 中确认真实 NAT 子网；参见[网络说明](networking.md#前置条件)。

不要提交 `configs\local.json`；共享默认值应提交到主配置文件。

运行 `adpos doctor` 可以查看 `configs\local.json` 是不存在、为空、已应用、存在但没有支持的顶层字段，还是使用了不支持的顶层字段。

`configs\secrets.json` 同样已被忽略，保留给未来专门的 secret 支持。当前 MVP 不会读取它。
