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

## 前置条件

创建运行时或应用网络前，先确认 VMware Workstation 的 NAT 网络与 ADP-OS 配置一致。

1. 打开 VMware Workstation Pro。
2. 打开 **Edit > Virtual Network Editor**。
3. 选择 NAT 网络，通常是 `VMnet8`。
4. 确认 subnet 是 `192.168.242.0`，prefix 是 `/24`，NAT gateway 是 `192.168.242.2`。
5. 确认 ADP 运行时静态 IP 位于该子网内，并且不落在 VMware DHCP 已使用的地址范围中。

运行：

```powershell
.\cli\adp.ps1 doctor
```

`doctor` 会报告：

- `VMware NAT config`：ADP 是否配置了 NAT CIDR、gateway 和 prefix。
- `VMware NAT gateway range`：配置的 gateway 是否位于配置的 CIDR 内。
- `VMware NAT host match`：如果可探测，ADP 配置的 CIDR 是否与 host `VMnet8` 网络一致。
- `VMware NAT gateway host range`：如果可探测，ADP 配置的 gateway 是否位于 host `VMnet8` 网络内。
- `<runtime> static IP range`：每个运行时 IP 是否位于配置的 CIDR 内。
- `<runtime> seed network drift`：对于已有 VM，生成过的 autoinstall seed 是否仍与当前 runtime static IP 一致。
- `VMware NAT prerequisites`：说明 ADP 会在可探测时把配置的 NAT 与 host `VMnet8` 进行比对。

当 ADP 能探测到配置的 NAT CIDR 与 host `VMnet8` 网络不一致时，会在首次创建 VM 前阻断，避免生成一个静态 IP 不可达的 VM。如果 host NAT 无法探测，ADP 会继续执行但打印指引；请把 VMware Virtual Network Editor 视为实际 host NAT 子网的事实来源，然后让 ADP 配置与它保持一致。

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

对于本机专属的 NAT 设置，优先使用被忽略的本地覆盖文件，而不是直接修改已提交的默认配置：

```powershell
Copy-Item configs\local.example.json configs\local.json
```

然后在 `configs\local.json` 中更新 `platform.network.vmware_nat` 和 `topology.<runtime>.static_ip`。

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

创建新 VM 前，`adp up <runtime>` 会在 host 暴露相关信息时，比对配置的 VMware NAT 子网和 host `VMnet8` 网络。如果二者不一致，ADP 会在创建 VM 前退出，并提示你更新 `configs\local.json`。

VM 创建完成后再修改 `configs\local.json`，不会自动重写 guest 内部网络。运行 `.\cli\adp.ps1 status <runtime>` 或 `.\cli\adp.ps1 doctor`；如果看到 `network drift` 或 `seed network drift`，请重建该 runtime，或从旧 seed-era 地址进入 guest 后更新网络。

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
