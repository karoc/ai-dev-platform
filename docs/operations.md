# Operations

[简体中文](zh-CN/operations.md) | English

This guide covers day-to-day operation of ADP-OS.

## Health Checks

Run:

```powershell
.\cli\adp.ps1 doctor
```

Expected result:

```text
All checks passed. Platform is healthy.
```

For first-run guidance, include the checklist:

```powershell
.\cli\adp.ps1 doctor -FirstRun
```

`doctor` checks platform prerequisites, configuration shape, local override status, VMware tooling, VMware NAT host match when detectable, Mutagen version, ISO cache, runtime topology, static IP uniqueness, static IP ranges, duplicate running ADP runtime names across VMX paths, existing-runtime seed network drift, VM status, SSH reachability for running VMs, and Mutagen sessions.

Preview local Mutagen remediation:

```powershell
.\cli\adp.ps1 doctor -FixMutagen -Plan
```

Install the tested local Mutagen binary only after reviewing the plan:

```powershell
.\cli\adp.ps1 doctor -FixMutagen
```

`-FixMutagen` installs Mutagen 0.18.x into `.tools\mutagen\mutagen.exe`, then verifies the installed version. The install path prints explicit phases, download source/target, offline archive path, connection and hard timeout guidance, optional SHA256 status, clean failure output, and a manual recovery path if the download fails. The `.tools` directory is ignored by Git, so downloaded archives and local binaries are not committed.

If GitHub release downloads are slow or blocked, use the offline archive path instead of relying on the network:

```powershell
New-Item -ItemType Directory -Path .tools\mutagen -Force
# Download this file through a browser or another trusted channel:
# https://github.com/mutagen-io/mutagen/releases/download/v0.18.1/mutagen_windows_amd64_v0.18.1.zip
# Save it as:
# .tools\mutagen\mutagen_windows_amd64_v0.18.1.zip
.\cli\adp.ps1 doctor -FixMutagen
```

For a custom local archive, mirror, or timeout policy, use ignored `configs\local.json` under `platform.tools.mutagen`:

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

When `sha256` is a 64-character hexadecimal hash, ADP verifies the archive before extraction and fails if it does not match. When `sha256` is `null`, archive hash verification is skipped and ADP still verifies the extracted `mutagen.exe` reports a supported `0.18.x` version.

Run integration checks:

```powershell
.\tests\validate.ps1
```

For targeted checks:

```powershell
.\tests\validate.ps1 -Quick
.\tests\cli-smoke.ps1
.\tests\install-smoke.ps1
.\test-integration.ps1
.\deploy-check.ps1
```

`validate.ps1` is the local version of the CI repository validation. It runs PowerShell parsing, JSON parsing, CLI parameter contracts, config schema checks, artifact hygiene checks, CLI smoke tests, installer smoke tests, bootstrap shell syntax checks, Markdown local link checks, and documentation language-link checks. The documentation language check also enforces translated file pairs for root public docs and `docs/zh-CN`. Use `-Quick` for local iteration; it keeps parser, schema, contract, artifact hygiene, shell, Markdown, and documentation checks, but skips the slower CLI and installer smoke tests. Use `-SkipCliSmoke`, `-SkipInstallerSmoke`, or `-SkipShellSyntax` for narrower troubleshooting.

`cli-smoke.ps1` checks command dispatch, non-destructive previews, and input error boundaries. It does not create, start, stop, sync, or destroy VMs.

`install-smoke.ps1` checks installer diagnostics and local-state writes with a temporary `USERPROFILE`. It does not use the real user profile, download dependencies, validate VMware, create VMs, or require a real ISO.

Installer troubleshooting switches:

```powershell
.\install.ps1 -SkipDependencyCheck
.\install.ps1 -SkipVMValidation
```

These switches are intended for controlled troubleshooting and CI-like validation paths. Normal first-run setup should not use them.

`install.ps1` and `doctor` check the host prerequisites needed for first runtime creation:

- VMware `vmrun.exe`.
- VMware `vmware-vdiskmanager.exe`.
- WSL and WSL `xorriso`.
- An ISO remaster tool.
- Mutagen 0.18.x.
- OpenSSH Client.
- ISO presence and basic shape.

The checks print remediation guidance. They do not download VMware, Mutagen, browsers, ISO images, or other large binaries by default. Mutagen installation is explicit through `doctor -FixMutagen`.

## Start Runtimes

```powershell
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 up backend
.\cli\adp.ps1 up agent
```

If a VM exists and is already running, ADP reports the current IP and skips creation.

After startup, ADP prints the configured connection target, SSH command, SSH alias, workspace path, sync command, and status command. The connection target comes from the merged configuration, including `configs\local.json` when present.

The `agent` runtime may print a high-IO profile notice. This is not an error; it means the runtime is sized for AI agent workloads and snapshots are recommended before destructive or large-scale tasks.

First-time VM creation includes a long Ubuntu autoinstall phase. ADP reports this as a watched OS installation, not a CLI hang, then prints plain, copyable `[install monitor] INSTALLING Ubuntu in VM` heartbeats. Each heartbeat starts with a human-readable installation headline before the diagnostic fields, so the visible tail of the log still says the VM is installing instead of looking like a stuck IP or SSH probe. The structured details include `state=installing`, `activity=installing-ubuntu`, `status=watching`, `current-op=readiness-check`, `wait-mode=watched`, `progress=indeterminate`, `user-action=keep-open`, `diagnostics=vmware-console-after-20min`, `phase=ubuntu-autoinstall`, expected duration, timeout, elapsed time, remaining timeout time, next check interval, observed readiness signals, the next readiness check, and whether user action is needed. Because Ubuntu does not expose a reliable install percentage through VMware at this stage, ADP uses an indeterminate progress model: it reports observable readiness signals instead of fake percentages. The monitored signals are configured/static IP, VMware-reported IP, SSH key authentication, and `/home/adp/.adp-provisioned`. IP and SSH probes are readiness signals inside the install monitor; repeated probe failures do not mean ADP is stuck while the heartbeat headline still says `INSTALLING Ubuntu in VM`. During normal installation, the same signal can repeat for several minutes while Ubuntu boots, installs, reboots, or prepares the target user, so repeated heartbeats include `normal=yes`. ADP explains in each heartbeat that unchanged signals can be normal during OS installation, states when it will recheck readiness, tells you to keep the command running and avoid manual SSH, and only recommends inspecting the VMware console after the same signal repeats for about 20 minutes or the timeout is reached. During this phase, SSH port 22 may become reachable before the installed system has accepted the ADP key or written the provision marker; that intermediate state is reported as `auth-pending`, not as a finished runtime.

Preview startup without creating, starting, provisioning, or bootstrapping a VM:

```powershell
.\cli\adp.ps1 up agent -Plan
```

Create the VM definition without starting OS provisioning or bootstrap:

```powershell
.\cli\adp.ps1 up agent -NoProvision
```

Initialize platform state and create a runtime VM definition without starting OS provisioning:

```powershell
.\cli\adp.ps1 init agent -SkipProvision
```

When creating a runtime for the first time, you can pass an ISO from any location:

```powershell
.\cli\adp.ps1 up agent -IsoPath D:\Share\ubuntu-26.04-live-server-amd64.iso
```

`-IsoPath` is used directly for VM creation. It does not need to be inside the configured ISO cache.

Before creating a new VM, `adp up <runtime>` compares the configured VMware NAT CIDR with the host `VMnet8` network when the host exposes it. If they do not match, ADP exits before creating the VM and presents two remediation paths: align ADP local overrides to host `VMnet8` with `.\cli\adp.ps1 network configure-local -Plan` and `.\cli\adp.ps1 network configure-local -Apply`, or keep ADP's configured subnet and change VMware `VMnet8` in Virtual Network Editor. This prevents a new VM from being installed with a static IP that the host cannot reach.

## Stop Runtimes

```powershell
.\cli\adp.ps1 stop frontend
```

The command tries a soft stop first, then a hard stop if needed.

## Runtime Status

Show all runtime states and connection details:

```powershell
.\cli\adp.ps1 status
```

Show one runtime:

```powershell
.\cli\adp.ps1 status frontend
```

`status` is non-destructive. It does not create, start, stop, sync, snapshot, or edit guest files. It reports:

- Whether `configs\local.json` is missing, empty, applied, or unsupported.
- The configured VMware NAT CIDR and gateway.
- Each runtime's VM status.
- The configured static IP from the merged topology.
- The VMware-detected IP when available.
- Duplicate running ADP runtime names when VMware has another `adp-<runtime>.vmx` running outside the current checkout.
- Network drift when an existing autoinstall seed still contains an older static IP than the current merged configuration.
- SSH state for running VMs: `reachable`, `auth-pending`, `unreachable`, `ambiguous-duplicate`, or a local prerequisite state such as `key-missing`.
- Mutagen sync session presence.
- The exact SSH command, SSH alias, workspace path, and next commands.

If the VMware-detected IP differs from the configured static IP, ADP still shows the configured static IP as the connection target. This is intentional for static networking and makes local NAT subnet overrides visible after editing `configs\local.json`.

If `status` reports `duplicate VM`, another VMX with the same runtime name is running from another checkout or a stale VM store. Stop or rename the stale duplicate before diagnosing SSH, detected IP, or network drift, because VMware may report IP information for the wrong same-name runtime while the current checkout expects a different VMX path.

When a duplicate is present, `status` reports SSH as `ambiguous-duplicate` because a successful connection to the configured IP does not prove that the current checkout's VMX is the guest that answered.

If `status` reports `network drift`, the VM was created with an older seed network than the current configuration. Editing `configs\local.json` after VM creation does not rewrite guest networking. Use the remediation path that matches the situation:

- Rebuild when the VM can be recreated. Preview first with `.\cli\adp.ps1 destroy <runtime> -Plan`, then recreate with `.\cli\adp.ps1 up <runtime>`.
- Use an in-place guest netplan fix when the seed-era address is reachable. Preview first with `.\cli\adp.ps1 network apply <runtime> -Plan`; then run without `-Plan` only after confirming it will SSH to the expected guest.
- Use an administrator-only temporary host-route workaround only when you must regain SSH to the seed-era address first. ADP does not add, change, or remove host routes automatically.

If `status` reports `auth-pending`, the SSH port is open but the ADP key is not accepted yet. During first-time autoinstall this usually means the installer or first boot is still preparing the target user. Keep waiting until the timeout, or inspect the VMware console if the state does not change.

## SSH Access

```powershell
ssh -i $env:USERPROFILE\.ssh\adp-os\adp-os adp@192.168.242.131
```

Default addresses are documented in `docs\networking.md`. If you use `configs\local.json` to override `topology.<runtime>.static_ip`, use `.\cli\adp.ps1 status <runtime>` after startup and connect to the address shown there.

## Workspace Sync

Place target project clones under the matching Windows workspace root before starting sync. See [Workspaces](workspaces.md) for recommended layouts and dogfooding guidance.

Start sync:

```powershell
.\cli\adp.ps1 sync start frontend
```

Check sync:

```powershell
.\cli\adp.ps1 sync status
```

`sync status` prints an ADP runtime summary before the raw Mutagen session list. The summary compares each `adp-<runtime>` session with the current checkout's expected local workspace path and SSH alias. A session can exist but still be unusable for this checkout, for example when it points at an older workspace, a different remote alias, or Mutagen reports a halted/error state. For a runtime that already exists in the current checkout, ADP reports `wrong-local`, `wrong-remote`, or `unhealthy` and prints the explicit recovery command:

```powershell
.\cli\adp.ps1 sync stop agent
.\cli\adp.ps1 sync start agent
```

If the runtime has not been created in the current checkout yet, ADP reports the stale same-name session as cleanup guidance instead of a current platform-health failure. Stop the old session first, then create the runtime before starting sync:

```powershell
.\cli\adp.ps1 sync stop frontend
.\cli\adp.ps1 up frontend
.\cli\adp.ps1 sync start frontend
```

`sync start <runtime>` will not treat an unusable same-name session as success. It stops before creating or rewriting the runtime SSH alias and asks you to explicitly stop and recreate the session.

Stop sync:

```powershell
.\cli\adp.ps1 sync stop frontend
```

Mutagen sessions are named:

```text
adp-frontend
adp-backend
adp-agent
```

## Frontend Browser Tests

The frontend runtime includes lightweight browser acceptance helpers. They do not install browser binaries during bootstrap.

Check readiness:

```powershell
ssh adp-os-adp-frontend
adp-frontend-browser-check
```

Install Chromium support on demand:

```bash
adp-frontend-browser-install chromium
```

Then run project tests from the synced workspace:

```bash
cd /home/adp/workspace
pnpm install
pnpm exec playwright test
```

Browser downloads stay inside the VM user cache. Generated reports such as `playwright-report`, `test-results`, and `blob-report` are ignored by the frontend sync profile.

## Snapshots and Restore

Create a baseline snapshot:

```powershell
.\cli\adp.ps1 snapshot create frontend clean
```

Restore:

```powershell
.\cli\adp.ps1 restore frontend clean
```

Snapshots are VMware snapshots and may take several minutes on running VMs. ADP verifies snapshot existence after timeout to avoid false failures.

## Destroy a Runtime

```powershell
.\cli\adp.ps1 destroy frontend
```

Destroying a runtime removes the VM files for that runtime. Workspace data under `%USERPROFILE%\adp-workspaces` is separate.

Preview the deletion first:

```powershell
.\cli\adp.ps1 destroy frontend -Plan
```

## Re-apply Networking

```powershell
.\cli\adp.ps1 network apply all
```

Use this after editing `configs\platform.json`, `configs\topology.json`, or the supported `platform`/`topology` sections in `configs\local.json`.

Before any VM exists, use this to align local NAT settings with host `VMnet8` without touching VMs:

```powershell
.\cli\adp.ps1 network configure-local -Plan
.\cli\adp.ps1 network configure-local -Apply
```

`configure-local -Plan` previews the detected host NAT subnet, target gateway/DNS, derived runtime static IPs, and field-level local config changes. A bare `configure-local` is also non-mutating. Use `-Apply` only after reviewing the plan; it writes only `configs\local.json` and backs up an existing file as `configs\local.json.bak.<timestamp>`. If you want to keep ADP's configured subnet instead, change VMware `VMnet8` in Virtual Network Editor rather than applying the local override.

Preview the guest networking changes first:

```powershell
.\cli\adp.ps1 network apply all -Plan
```

When `network apply -Plan` detects seed-network drift, it prints the same remediation split: rebuild path, in-place guest netplan path, and administrator-only host-route workaround. The command only manages guest netplan files over SSH; it does not recreate VMs and does not change host routes.
