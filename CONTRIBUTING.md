# Contributing

[简体中文](CONTRIBUTING.zh-CN.md) | English

Thank you for helping improve AI Dev Platform OS.

For support questions, reproducible bug reports, feature requests, and diagnostic expectations, see [Support](SUPPORT.md).

## Development Requirements

- Windows 11.
- PowerShell 7+.
- VMware Workstation Pro.
- WSL with `xorriso`.
- OpenSSH client.
- Mutagen 0.18.x.

## Before Submitting Changes

For workspace task templates, release-readiness expectations, and maintainer review flow, see [Contributor Workflows](docs/contributor-workflows.md) and [Release Readiness](docs/release-readiness.md).

Run:

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

## Pull Request Readiness

- Include the workspace task shape used, or explain why no workspace task applies.
- Include `workspace report -Markdown` release evidence when the change affects workflows, runtime behavior, validation, documentation, or release readiness.
- Keep README and Simplified Chinese docs synchronized when README or user-facing docs change.
- Do not mark high-risk agent work ready without a snapshot gate or explicit maintainer waiver.

## Security

The MVP uses local development defaults. Do not add real credentials, private SSH keys, tokens, internal hostnames, or customer data to the repository.
