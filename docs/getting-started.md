# Getting Started

[简体中文](zh-CN/getting-started.md) | English

Welcome to ADP-OS. This guide walks you through your first setup — from nothing to a running development VM — in about 30-70 minutes, depending mostly on ISO download speed and first VM creation time.

## What is ADP-OS?

ADP-OS (AI Dev Platform OS) is a local AI development runtime platform. It provisions isolated Linux virtual machines on your Windows workstation, keeps your project files synchronized into each VM, and gives you rollback snapshots for repeatable AI coding workflows.

```text
                        Windows 11 Host
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│   ADP-OS Control Plane (PowerShell 7)                       │
│   ┌──────────┐  ┌──────────┐  ┌──────────┐                 │
│   │  setup   │  │  adpos   │  │  doctor  │                 │
│   │  .cmd    │  │ command  │  │  checks  │                 │
│   └──────────┘  └──────────┘  └──────────┘                 │
│         │              │             │                       │
│         ▼              ▼             ▼                       │
│   ┌──────────────────────────────────────────┐              │
│   │         VMware Workstation               │              │
│   │  ┌──────────┐ ┌──────────┐ ┌──────────┐ │              │
│   │  │ frontend │ │ backend  │ │  agent   │ │              │
│   │  │  Ubuntu  │ │  Ubuntu  │ │  Ubuntu  │ │              │
│   │  │ 26.04 VM │ │ 26.04 VM │ │ 26.04 VM │ │              │
│   │  │          │ │          │ │          │ │              │
│   │  │  Docker  │ │  Docker  │ │  Docker  │ │              │
│   │  │  Node.js │ │  Python  │ │  AI dev  │ │              │
│   │  └──────────┘ └──────────┘ └──────────┘ │              │
│   └──────────────────────────────────────────┘              │
│         ▲              ▲             ▲                       │
│         └──────────────┼─────────────┘                       │
│                        │                                     │
│              Mutagen sync (two-way)                          │
│                        │                                     │
│         %USERPROFILE%\adp-workspaces\                        │
│         ├── frontend/  →  frontend VM:/home/adp/workspace    │
│         ├── backend/   →  backend VM :/home/adp/workspace    │
│         └── agent/     →  agent VM   :/home/adp/workspace    │
└─────────────────────────────────────────────────────────────┘
```

ADP-OS does not replace Docker. It provisions Docker-capable VMs and adds lifecycle management, workspace synchronization, static networking, role-specific bootstrap, and snapshot rollback around those runtimes.

## What You Need

Before you start, make sure you have:

| # | Prerequisite | How to Get It |
|---|-------------|---------------|
| 1 | **Windows 11** | Check via Settings → System → About. Windows 10 is not supported. |
| 2 | **PowerShell 7+** | `.\setup.cmd` attempts to install it automatically with `winget` if it is missing. Manual fallback: `winget install --id Microsoft.PowerShell --source winget`, or download from GitHub. Built-in PowerShell 5.1 can launch the bootstrap wrapper, but it cannot run the ADP-OS control plane. |
| 3 | **VMware Workstation Pro** | [Download](https://www.vmware.com/products/workstation-pro.html) (free for personal use, or paid license). Verify with `vmrun.exe` on your PATH. |
| 4 | **WSL** (Windows Subsystem for Linux) | Run `wsl --install` in an admin PowerShell. Required for ISO remastering. |
| 5 | **OpenSSH Client** | Already included in Windows 11. Verify with `ssh -V`. |
| 6 | **Mutagen 0.18.x** | ADP-OS can install it for you via `adpos doctor -FixMutagen` after setup, or `.\adpos.cmd doctor -FixMutagen` from the repo root before your shell refreshes `PATH`. Or [download manually](https://github.com/mutagen-io/mutagen/releases) if GitHub is slow. |
| 7 | **~10 GB free disk space** | For ISOs, VM disks, and tool binaries. |

**Note:** Items 1–5 are pre-requisites you install yourself. Item 6 (Mutagen) can be installed by ADP-OS's built-in doctor. Item 7 is just space.

## Expected Timeline

| Step | Time | What Happens |
|------|------|-------------|
| Clone the repo | < 1 min | `git clone` — a few megabytes |
| Download Ubuntu ISO | 5–15 min | ~2.6 GB download. Speed depends on your connection and [Ubuntu mirror](https://releases.ubuntu.com/26.04/) reachability |
| `setup.cmd` (install + init) | 5–10 min | Installs platform, registers the global `adpos` command, remasters ISO, creates VM templates |
| `adpos up frontend` (first VM) | 15–45 min | Provisions and boots your first VM, runs bootstrap scripts |
| Later warm start | ~30s | Starts an existing VM after it has already been provisioned |
| Verify with `adpos status` | < 1 min | Confirms everything is running |
| **Total** | **~30–70 minutes** | From zero to working development VM |

Times assume a typical broadband connection and a reasonably fast machine. ISO download is usually the slowest step.

## Step-by-Step Walkthrough

### Step 1: Clone the Repository

Open Windows Terminal, PowerShell, or cmd.exe and run:

```powershell
git clone https://github.com/karoc/ai-dev-platform.git
cd ai-dev-platform
```

> [!TIP]
> After setup, use `adpos` from any directory. If the current shell has not picked up the updated user `PATH` yet, open a new terminal or use `.\adpos.cmd` from the repository root. ADP-OS exposes `adpos` as the only user-facing shell command.

#### Using a Second Checkout

If this is a second local checkout or a different ADP-OS version on the same Windows user account, setup may detect that global `adpos` already points to another checkout. You can replace that binding, or keep it and use `.\adpos.cmd` inside this checkout.

Before running the same runtime in two checkouts at the same time, isolate the new checkout in `configs\local.json`:

- Use a different `platform.paths.workspace_root`.
- Use a different `platform.paths.vm_store`.
- Use different `topology.<runtime>.static_ip` values for concurrently running runtimes.

Then check the local checkout before creating or syncing VMs:

```powershell
.\adpos.cmd doctor
.\adpos.cmd status agent
.\adpos.cmd sync status
.\adpos.cmd up agent -Plan
```

### Step 2: Run the Guided Setup

**One-click:** Run `.\setup.cmd` from the repo root:

```powershell
.\setup.cmd
```

This single command handles ISO download, platform installation, initialization, and diagnostics:

1. **Prerequisite Scan** — Checks all 6 prerequisites and shows remediation for any missing items.  
2. **ISO Download** — Downloads Ubuntu Server 26.04 (~2.6 GB). Progress shown with percentage and speed.
3. **Install** — Runs `install.ps1` which sets up directories, registers `adpos`, generates seed ISO, and creates VM templates.
4. **Init** — Runs `adpos init -Quick` through the setup chain to finalize platform configuration.
5. **Doctor** — Runs `adpos doctor` through the setup chain to verify all prerequisites are in place.

You'll see progress indicators like `[1/6]`, `[2/6]` as each phase completes.

> [!TIP]
> If you already have the Ubuntu ISO: `.\setup.cmd -IsoPath C:\path\to\ubuntu.iso`
> For non-interactive/scripted use: `.\setup.cmd -NonInteractive`

> [!NOTE]
> If you already have the Ubuntu ISO downloaded, you can skip the download:
> ```powershell
> .\setup.cmd -IsoPath C:\path\to\ubuntu-26.04-live-server-amd64.iso
> ```

### Step 3: Start Your First Runtime

Provision and boot the frontend VM:

```powershell
adpos up frontend
```

This command:

1. Creates the VM disk and VMX configuration
2. Boots the VM with the remastered ISO
3. Waits for cloud-init to finish provisioning
4. Runs SSH bootstrap scripts (Docker, Node.js, etc.)
5. Confirms the VM is ready

You'll see output as each stage completes. The first VM creation usually takes 15–45 minutes because Ubuntu autoinstall and bootstrap are running for the first time. Later warm starts of an already provisioned VM are usually about 30 seconds.

> [!TIP]
> Want to preview what `up` will do without making changes? Use `-Plan`:
> ```powershell
> adpos up frontend -Plan
> ```

### Step 4: Check Everything is Working

#### Check Runtime Status

```powershell
adpos status
```

Healthy output looks like:

```text
RUNTIME   STATE     IP               SSH
frontend  running   192.168.242.131  adp-os-adp-frontend
```

`STATE` should say `running`. If it says `poweredOff`, the VM didn't start — jump to [Common Mistakes](#common-first-time-mistakes) below.

#### Run Diagnostics

```powershell
adpos doctor
```

Healthy output looks like:

```text
[PASS] VMware Workstation      (vmrun.exe found)
[PASS] VMware Disk Manager     (vmware-vdiskmanager.exe found)
[PASS] WSL                     (WSL detected)
[PASS] WSL xorriso             (xorriso 1.5.6 available)
[PASS] Mutagen                 (0.18.1)
[PASS] OpenSSH                 (OpenSSH_for_Windows_9.5p1)
[PASS] Ubuntu ISO              (ubuntu-26.04-live-server-amd64.iso present)

Doctor complete: 7/7 checks passed.
```

All 7 checks should show `[PASS]`. If any show `[FAIL]`, the output includes remediation instructions — follow them and re-run `adpos doctor`.

### Step 5: Start Workspace Sync (Optional but Recommended)

Synchronize your local project files into the VM:

```powershell
adpos sync start frontend
```

Check sync status:

```powershell
adpos sync status
```

Expected output:

```text
RUNTIME   STATUS    SOURCE                              DEST
frontend  watching  %USERPROFILE%\adp-workspaces\fron... /home/adp/workspace
```

Now any files you put in `%USERPROFILE%\adp-workspaces\frontend\` appear immediately inside the VM at `/home/adp/workspace/`.

### Step 6: SSH Into Your VM

```powershell
ssh adp-os-adp-frontend
```

You're now inside your development VM. Try:

```bash
docker --version
node --version
python3 --version
```

All three should print version numbers — these were installed during bootstrap.

> [!WARNING]
> The VM uses a default `adp:adp` user and password for provisioning. This is safe for local, single-user development on a trusted workstation. Do not expose these VMs to untrusted networks without changing credentials. See [Security](../SECURITY.md) for details.

## Common First-Time Mistakes

### "vmrun.exe not found"

**Symptom:** `adpos doctor` shows `[FAIL] VMware Workstation`.

**Fix:** Install VMware Workstation Pro. After installation, open a new PowerShell window so the PATH updates. Verify with:

```powershell
vmrun.exe list
```

### ISO download fails or is very slow

**Symptom:** `quickstart` hangs during ISO download, or `Invoke-WebRequest` times out.

**Fix:** Download the ISO manually through a browser (which may handle resuming better), then pass the path:

```powershell
.\setup.cmd -IsoPath C:\Users\YOURNAME\Downloads\ubuntu-26.04-live-server-amd64.iso
```

The ISO goes to `%USERPROFILE%\adp-iso\`. Manual download URL: https://releases.ubuntu.com/26.04/ubuntu-26.04-live-server-amd64.iso

### "WSL not detected" or "xorriso not found"

**Symptom:** `adpos doctor` shows `[FAIL] WSL` or `[FAIL] WSL xorriso`.

**Fix:** Install WSL and xorriso:

```powershell
# Install WSL (run in admin PowerShell)
wsl --install

# Install xorriso (run in WSL)
wsl -u root bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso"
```

### VM starts but "provisioning timed out"

**Symptom:** `adpos up frontend` runs for a while then shows a timeout error about cloud-init provisioning.

**Fix:** This usually means VMware networking isn't set up correctly. Check:

1. Open VMware Workstation, go to Edit → Virtual Network Editor
2. Verify the NAT network (default `vmnet8`) is enabled
3. Check that the subnet matches `configs\platform.json`
4. Run `adpos doctor` — it checks NAT host matching when detectable

### "Permission denied" when running .ps1 files

**Symptom:** PowerShell shows red error text about execution policy.

**Fix:** ADP-OS scripts don't require changing your system execution policy. Run them with PowerShell 7 by passing the script path to `pwsh.exe`:

```powershell
pwsh.exe -ExecutionPolicy Bypass -File .\install.ps1
```

If `pwsh.exe` is missing, the normal path is to run `.\setup.cmd`; it attempts the PowerShell 7 install automatically. Manual fallback:

```powershell
winget install --id Microsoft.PowerShell --source winget
```

Or use the `.cmd` wrappers; they also check for PowerShell 7 before running ADP-OS:

```powershell
.\setup.cmd
.\adpos.cmd quickstart
```

### "Mutagen 0.18.x not found"

**Symptom:** `adpos doctor` shows `[FAIL] Mutagen`.

**Fix:** Let ADP-OS install it for you:

```powershell
adpos doctor -FixMutagen
```

This downloads and installs Mutagen into `.tools\mutagen\mutagen.exe`. If GitHub is slow, see the [Operations](operations.md) guide for offline installation.

## Next Steps

Now that your first runtime is running:

- **[Operations](operations.md)** — Day-to-day commands: start/stop VMs, manage sync, create snapshots, run validation.
- **[Troubleshooting](troubleshooting.md)** — Symptom-driven diagnostics guide. Start here when something goes wrong.
- **[Configuration](configuration.md)** — Customize VM sizing, static IPs, bootstrap behavior, and local overrides.
- **[Architecture](architecture.md)** — How the control plane, runtime fabric, and workspace fabric fit together.
- **[Workspaces](workspaces.md)** — Where to put your projects and how to dogfood ADP-OS safely.
- **[Security](../SECURITY.md)** — Understand the local-development security model.

Want all three runtimes? After `frontend` is running:

```powershell
adpos up backend
adpos up agent
```

To remove the global command registration later, run:

```powershell
adpos uninstall
```

This only removes the user-level `adpos` PATH shim. It does not delete VMs, workspace files, ISO cache, local tools, logs, or repository files.

If `adpos` is not available in the current shell, use the repository-root wrapper:

```powershell
.\uninstall.cmd
```
