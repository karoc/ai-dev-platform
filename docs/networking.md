# Networking

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
