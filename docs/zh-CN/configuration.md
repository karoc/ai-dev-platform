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
- `static_ip`：用于 provisioning、CLI、SSH 和同步的 guest IP。
- `ssh_port`：guest SSH 端口。

## `sync-profiles.json`

Sync profiles 配置 Mutagen 行为和忽略列表。

```json
{
  "frontend": {
    "mode": "two-way-resolved",
    "ignore": ["node_modules", ".next", "dist", "build"]
  }
}
```

支持的同步模式取决于安装的 Mutagen 版本。本项目已使用 Mutagen `0.18.x` 测试。

## 本地覆盖

以下文件已被忽略，保留给本地 secrets 或未来的本地覆盖支持：

```text
configs/local.json
configs/secrets.json
```

当前 MVP 直接读取主配置文件，尚未实现本地覆盖合并。
