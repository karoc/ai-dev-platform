# Security Policy

[简体中文](SECURITY.zh-CN.md) | English

AI Dev Platform OS is currently a local-development MVP. It provisions local VMware runtimes and synchronizes local workspaces for single-user AI-assisted development workflows.

## Supported Scope

Security guidance currently applies to the `main` branch and the Windows VMware MVP.

The project does not yet publish versioned releases. Until releases are introduced, use the latest `main` branch for security fixes.

## Local Development Security Model

ADP-OS is designed for local, single-user development on a trusted workstation.

Default MVP behavior includes:

- A default runtime user named `adp`.
- A default bootstrap password of `adp` for automated local sudo provisioning.
- SSH access from the Windows host into local VMware VMs.
- Mutagen synchronization between host workspaces and guest workspaces.
- VMware NAT networking with static guest IPs.

These defaults are intended to make local bootstrap reproducible. They are not intended for exposed, shared, production, or multi-tenant environments.

## Do Not Expose Default Runtimes

Do not expose ADP-OS VMs directly to untrusted networks without first reviewing and changing:

- Runtime user credentials.
- SSH access and authorized keys.
- VMware NAT and port-forwarding rules.
- Firewall policy.
- Workspace synchronization paths.
- Any project secrets stored in synchronized workspaces.

## Secrets and Local Artifacts

Do not commit:

- Private SSH keys.
- API tokens, passwords, or cloud credentials.
- Local VM disks, snapshots, logs, ISO images, or downloaded tool binaries.
- Browser caches or generated browser test reports.
- Private maintainer context.

The repository ignore rules are defensive, but they are not a substitute for review before committing.

## Reporting a Vulnerability

If you believe you found a security issue, do not open a public issue with exploit details or secrets.

Report it privately to the repository owner through GitHub contact channels or by opening a minimal public issue that asks for a private disclosure path without including sensitive details.

Please include:

- A concise description of the issue.
- The affected command, script, or configuration.
- Host OS and ADP-OS commit.
- Whether credentials, host files, VM files, or network exposure are involved.
- Minimal reproduction steps that do not include real secrets.

## Security Fix Handling

Security fixes should:

- Minimize behavioral surprise for local users.
- Preserve reproducible local bootstrap where possible.
- Update documentation when security assumptions or required user actions change.
- Avoid publishing secrets, private local paths, or exploit payloads in commits or issues.
