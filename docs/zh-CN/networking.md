# 网络

简体中文 | [English](../networking.md)

ADP-OS 支持 VMware NAT 运行时的静态 IP 网络。

## 默认网络

默认配置假设 VMware NAT 位于：

```text
192.168.242.0/24
```

配置为：

```text
Gateway: 192.168.242.2
DNS:     192.168.242.2, 1.1.1.1
```

默认运行时地址：

```text
frontend  192.168.242.131
backend   192.168.242.133
agent     192.168.242.135
```

## 配置网络

编辑 `configs\platform.json`：

```json
{
  "network": {
    "mode": "static",
    "vmware_nat": {
      "cidr": "192.168.242.0/24",
      "prefix": 24,
      "gateway": "192.168.242.2",
      "dns": ["192.168.242.2", "1.1.1.1"],
      "interface_match": "en*"
    }
  }
}
```

在 `configs\topology.json` 中编辑每个运行时的 IP：

```json
{
  "frontend": {
    "static_ip": "192.168.242.131"
  }
}
```

## 对已有 VM 应用网络

修改网络设置后应用：

```powershell
.\cli\adp.ps1 network apply all
```

也可以只应用一个运行时：

```powershell
.\cli\adp.ps1 network apply frontend
```

该命令会：

- 上传生成的 netplan 文件。
- 写入 `/etc/netplan/99-adp-static.yaml`。
- 运行 `netplan generate` 和 `netplan apply`。
- 等待目标 IP 上的 SSH 可达。
- 更新 ADP 管理的 Mutagen SSH Host aliases。

## 新 VM 的静态网络

对于新 provision 的 Ubuntu VM，ADP 会把静态网络注入 cloud-init autoinstall user data。这意味着新 VM 应直接使用配置的 `static_ip` 启动。

## 排障

检查 guest 地址：

```powershell
ssh -i $env:USERPROFILE\.ssh\adp-os\adp-os adp@192.168.242.131 "ip -4 -o addr show scope global"
```

检查路由：

```powershell
ssh -i $env:USERPROFILE\.ssh\adp-os\adp-os adp@192.168.242.131 "ip route show default"
```

检查同步状态：

```powershell
.\cli\adp.ps1 sync status
```

如果 VMware DHCP 与 ADP 静态地址冲突，请把静态地址改成 NAT 子网内未使用的 IP，然后再次运行 `network apply`。
