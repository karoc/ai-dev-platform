# Support

[简体中文](SUPPORT.zh-CN.md) | English

AI Dev Platform OS is an early local-development MVP. Support is best-effort and focused on keeping the public project understandable, reproducible, and safe to try.

## Where to Start

Before opening an issue, run the non-destructive checks that match your problem:

```powershell
.\cli\adp.ps1 doctor
.\cli\adp.ps1 doctor -FirstRun
.\cli\adp.ps1 status
.\cli\adp.ps1 sync status
.\tests\validate.ps1 -Quick
```

Use the documentation entry points:

- [Quick Start](README.md#quick-start): first setup and runtime startup.
- [Operations](docs/operations.md): day-to-day commands and troubleshooting.
- [Configuration](docs/configuration.md): platform, topology, sync profiles, and local overrides.
- [Networking](docs/networking.md): VMware NAT, static IPs, and connection troubleshooting.
- [Workspaces](docs/workspaces.md): target-project layout and workspace task flow.
- [Troubleshooting](docs/troubleshooting.md): symptom-to-command checks before opening an issue.
- [Roadmap](docs/roadmap.md): product direction and planned boundaries.

## Open a Public Issue

Use GitHub Issues for reproducible public problems:

- Bug reports for commands, diagnostics, VM lifecycle, networking, sync, bootstrap, browser testing, docs, or workspace behavior.
- Feature requests that describe a user problem and expected workflow.
- Usage questions that can create reusable public knowledge.
- Documentation gaps that make setup, operation, validation, or release readiness unclear.

Include:

- Host OS, PowerShell version, VMware Workstation version, and ADP-OS commit.
- The exact command you ran.
- The smallest reproduction steps.
- Relevant non-sensitive output from `doctor`, `status`, `sync status`, or `tests\validate.ps1`.
- Whether you are using `configs\local.json` and which supported sections are present, without private paths or secrets.

Do not include:

- Secrets, tokens, private SSH keys, cloud credentials, or customer data.
- VM disks, snapshots, ISO images, downloaded tool archives, browser caches, or large logs.
- Private local paths that should not be public.
- Private maintainer context or local assistant state.

## Security Reports

Do not open a public issue with exploit details, secrets, tokens, or private keys.

Follow [Security Policy](SECURITY.md) for vulnerability reporting and security-fix handling.

## Usage Questions

Usage questions are welcome when they produce reusable public knowledge. Prefer questions that include:

- What you are trying to do.
- Which runtime is involved: `frontend`, `backend`, or `agent`.
- Whether the question is about setup, operation, workspace planning, validation, rollback, or release readiness.
- The command output that led to the question, with sensitive information removed.

If the question is about a private target project, reduce it to the ADP-OS command, manifest shape, runtime state, or diagnostic behavior that can be discussed publicly.

Use the GitHub Usage question template for these questions. Use the Bug report template only when you have a reproducible ADP-OS failure.

## Scope Boundaries

Supported public scope:

- Windows 11 host.
- PowerShell 7.
- VMware Workstation Pro.
- Ubuntu Server 26.04 runtime provisioning.
- Mutagen 0.18.x synchronization.
- ADP-OS CLI, configuration, docs, validation, and workspace planning behavior.

Out of current public scope:

- Production or multi-tenant deployment.
- Exposing default ADP-OS runtimes to untrusted networks.
- Hosted service operations.
- Guaranteed response times.
- Private project debugging when the issue cannot be reduced to ADP-OS behavior.
- Legal, licensing, credential, account, or cost-bearing infrastructure decisions.

## Maintainer Expectations

Maintainers should keep support responses aligned with the project boundaries:

- Ask for non-destructive diagnostics first.
- Prefer reproducible command sequences over screenshots.
- Redirect vulnerabilities to the security process.
- Keep English and Simplified Chinese docs aligned when a support answer reveals a documentation gap.
- Convert recurring support friction into diagnostics, docs, validation, or roadmap items.
