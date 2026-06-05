# Contributing

[简体中文](CONTRIBUTING.zh-CN.md) | English

Thank you for helping improve AI Dev Platform OS.

For support questions, reproducible bug reports, feature requests, and diagnostic expectations, see [Support](SUPPORT.md).

## Setting Up Your Development Environment

### 1. Clone the repository

```powershell
git clone git@github.com:karoc/ai-dev-platform.git
cd ai-dev-platform
```

### 2. Install required dependencies

| Dependency | Minimum version | How to install |
|---|---|---|
| Windows 11 | — | Your host OS |
| PowerShell 7 | 7.0 | `winget install Microsoft.PowerShell` |
| VMware Workstation Pro | 17.x | [VMware Download](https://www.vmware.com/products/workstation-pro.html) (free for personal use since May 2024) |
| WSL | — | `wsl --install` (Windows feature) |
| xorriso (in WSL) | — | `wsl -u root bash -lc "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y xorriso"` |
| Mutagen | 0.18.x | [Mutagen releases](https://github.com/mutagen-io/mutagen/releases). Place `mutagen.exe` on `PATH` or under `.tools\mutagen\`. |
| OpenSSH client | — | `Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0` |

### 3. Download Ubuntu Server ISO

Download the [Ubuntu Server 26.04 live server ISO](https://releases.ubuntu.com/26.04/) and place it where ADP-OS can find it. The default path is configured in `configs/platform.json`.

### 4. Run first-time diagnostics

```powershell
.\cli\adp.ps1 doctor -FirstRun
```

This checks all dependencies and reports any missing pieces with remediation guidance. Fix any issues before continuing.

### 5. Configure local networking (if needed)

If your VMware NAT subnet differs from the default, preview and apply local overrides:

```powershell
.\cli\adp.ps1 network configure-local -Plan
.\cli\adp.ps1 network configure-local -Apply
```

### 6. Verify the dev environment

```powershell
.\tests\validate.ps1 -Quick
```

This runs syntax checks, CLI smoke tests, and documentation validation. It takes ~10 seconds. All checks should pass with `Repository validation OK`.

## Development Workflow

### Making Changes

1. Create a focused branch: `git checkout -b my-change`
2. Make your changes following the [coding guidelines](#coding-guidelines)
3. Run validation frequently during development:

```powershell
.\tests\validate.ps1 -Quick
```

### Testing with Real VMs

To test VM lifecycle changes end-to-end:

```powershell
.\cli\adp.ps1 up agent -IsoPath D:\path\to\ubuntu-26.04-live-server-amd64.iso -Plan
.\cli\adp.ps1 up agent -IsoPath D:\path\to\ubuntu-26.04-live-server-amd64.iso
.\cli\adp.ps1 status agent
.\cli\adp.ps1 doctor
```

> VM creation requires ~10-15 minutes for Ubuntu autoinstall plus ~5 minutes for bootstrap. Use `-Plan` first to preview the operation.

### Before Submitting Changes

For workspace task templates, release-readiness expectations, and maintainer review flow, see [Contributor Workflows](docs/contributor-workflows.md) and [Release Readiness](docs/release-readiness.md).

Run the full validation gate:

```powershell
.\tests\validate.ps1
.\test-integration.ps1
.\deploy-check.ps1
.\cli\adp.ps1 doctor
```

Use `.\tests\validate.ps1 -Quick` for local iteration before running the full validation gate.

For bootstrap shell scripts:

```powershell
$repo = (Get-Location).Path -replace '\\', '/'
$drive = $repo.Substring(0, 1).ToLowerInvariant()
$path = "/mnt/$drive" + $repo.Substring(2)
wsl bash -lc "bash -n '$path/bootstrap/base/setup-base.sh' '$path/bootstrap/frontend/setup-frontend.sh' '$path/bootstrap/frontend/browser-tools.sh' '$path/bootstrap/backend/setup-backend.sh' '$path/bootstrap/agent/setup-agent.sh' '$path/bootstrap/common/common.sh'"
```

## Pull Request Process

1. **Push your branch** and open a pull request against `main`.
2. **CI will run** the full validation suite automatically. Fix any failures.
3. **Include context** in the PR description:
   - Which problem this solves (link to an issue if available)
   - Which files changed and why
   - Testing performed (commands run, output)
4. **Keep PRs focused** — one logical change per PR. If your work touches multiple areas, split into separate PRs.
5. **Documentation** — if your change affects user-visible behavior, commands, or configuration, update the relevant docs. Keep English and Simplified Chinese docs synchronized.
6. **Release evidence** — include `workspace report -Markdown` output when the change affects workflows, runtime behavior, validation, documentation, or release readiness.
7. **Review** — a maintainer will review your PR. Address feedback in new commits or by amending.

### PR Readiness Checklist

- [ ] Full validation passes: `.\tests\validate.ps1`
- [ ] Integration tests pass: `.\test-integration.ps1`
- [ ] Deploy check passes: `.\deploy-check.ps1`
- [ ] Documentation updated (English + Chinese if user-facing)
- [ ] Changelog entry added if user-visible
- [ ] No secrets, credentials, VM disks, ISOs, logs, or tool binaries committed
- [ ] High-risk agent work includes snapshot gate or explicit maintainer waiver

## Coding Guidelines

- Keep host-specific operations under `adapters`.
- Keep runtime creation logic under `runtimes`.
- Keep command entry points thin and route through adapters/core modules.
- Prefer idempotent bootstrap scripts.
- Avoid committing local VM data, logs, ISOs, tool binaries, SSH keys, or local assistant settings.
- Keep PowerShell compatible with PowerShell 7 on Windows.

## Commit Hygiene

Use focused commits. Mention which runtime path was affected, for example:

```text
vmware: make guest IP detection resilient
network: add static IP apply command
docs: add configuration guide
```

## Community

- **Issues**: Use the [issue templates](https://github.com/karoc/ai-dev-platform/issues/new/choose) — Bug Report, Feature Request, Installation Help, or Usage Question.
- **Discord**: Join the [ADP-OS Discord server](docs/discord-setup.md) for real-time discussion, help, and development coordination.
- **Discussions**: For open-ended ideas and questions that don't fit an issue template, use [GitHub Discussions](https://github.com/karoc/ai-dev-platform/discussions). To enable Discussions, go to repo Settings → General → Features and check "Discussions".

## Security

The MVP uses local development defaults. Do not add real credentials, private SSH keys, tokens, internal hostnames, or customer data to the repository.
