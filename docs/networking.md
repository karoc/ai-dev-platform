# Networking

[简体中文](zh-CN/networking.md) | English

ADP-OS supports static IP networking for VMware NAT runtimes.

## Default Network

The default configuration assumes VMware NAT on:

```text
192.168.242.0/24
```

With:

```text
Gateway: 192.168.242.2
DNS:     192.168.242.2, 1.1.1.1
```

Default runtime addresses:

```text
frontend  192.168.242.131
backend   192.168.242.133
agent     192.168.242.135
```

## Prerequisites

Before creating or networking runtimes, confirm that VMware Workstation's NAT network matches ADP-OS configuration.

1. Open VMware Workstation Pro.
2. Open **Edit > Virtual Network Editor**.
3. Select the NAT network, usually `VMnet8`.
4. Confirm the subnet is `192.168.242.0` with prefix `/24` and that the NAT gateway is `192.168.242.2`.
5. Confirm the ADP runtime static IPs are inside that subnet and outside any DHCP range used by VMware.

Run:

```powershell
.\cli\adp.ps1 doctor
```

`doctor` reports:

- `VMware NAT config`: whether ADP has a configured NAT CIDR, gateway, and prefix.
- `VMware NAT gateway range`: whether the configured gateway is inside the configured CIDR.
- `VMware NAT host match`: when detectable, whether ADP's configured CIDR matches the host `VMnet8` network.
- `VMware NAT gateway host range`: when detectable, whether ADP's configured gateway is inside the host `VMnet8` network.
- `<runtime> static IP range`: whether each runtime IP is inside the configured CIDR.
- `<runtime> seed network drift`: for existing VMs, whether the generated autoinstall seed still matches the current runtime static IP.
- `VMware NAT prerequisites`: a reminder that ADP compares the configured NAT with host `VMnet8` when it can detect it.

ADP blocks first-time VM creation when it can detect that the configured NAT CIDR does not match the host `VMnet8` network. This prevents creating a VM with an unreachable static IP. If host NAT detection is unavailable, ADP continues but prints guidance; treat VMware's Virtual Network Editor as the source of truth for the actual host NAT subnet, then update ADP configuration to match it.

## Configure the Network

Edit `configs\platform.json`:

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

Edit per-runtime IPs in `configs\topology.json`:

```json
{
  "frontend": {
    "static_ip": "192.168.242.131"
  }
}
```

For machine-specific NAT settings, prefer ignored local overrides instead of editing committed defaults:

```powershell
.\cli\adp.ps1 network configure-local -Plan
.\cli\adp.ps1 network configure-local
```

`network configure-local -Plan` detects host `VMnet8`, shows the target local NAT settings and runtime static IPs, and does not change files. Without `-Plan`, it writes only the ignored `configs\local.json` override. It does not create, start, stop, or modify VMs, does not open SSH, and does not change guest networking.

Manual editing is still supported: copy `configs\local.example.json` to `configs\local.json`, then update the `platform.network.vmware_nat` and `topology.<runtime>.static_ip` values.

## Apply Networking to Existing VMs

After changing network settings, apply them:

```powershell
.\cli\adp.ps1 network apply all
```

Or apply one runtime:

```powershell
.\cli\adp.ps1 network apply frontend
```

This command:

- Uploads a generated netplan file.
- Writes `/etc/netplan/99-adp-static.yaml`.
- Runs `netplan generate` and `netplan apply`.
- Waits for SSH to become reachable at the target IP.
- Updates ADP-managed Mutagen SSH Host aliases.

## Static Networking for New VMs

For newly provisioned Ubuntu VMs, ADP injects static networking into cloud-init autoinstall user data. This means newly created VMs should come up directly on their configured `static_ip`.

Before creating a new VM, `adp up <runtime>` checks the configured VMware NAT subnet against the host `VMnet8` network when the host exposes that information. If they differ, ADP exits before creating the VM and points you to `.\cli\adp.ps1 network configure-local -Plan`.

Changing `configs\local.json` after a VM has already been created does not rewrite the guest network by itself. Run `.\cli\adp.ps1 status <runtime>` or `.\cli\adp.ps1 doctor`; if they report `network drift` or `seed network drift`, rebuild the runtime or update guest networking from the old seed-era address.

## Troubleshooting

Check the guest address:

```powershell
ssh -i $env:USERPROFILE\.ssh\adp-os\adp-os adp@192.168.242.131 "ip -4 -o addr show scope global"
```

Check routing:

```powershell
ssh -i $env:USERPROFILE\.ssh\adp-os\adp-os adp@192.168.242.131 "ip route show default"
```

Check sync state:

```powershell
.\cli\adp.ps1 sync status
```

If VMware DHCP and ADP static addresses conflict, change the static addresses to unused IPs inside the NAT subnet and run `network apply` again.
