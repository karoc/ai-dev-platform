# Contributing

Thank you for helping improve AI Dev Platform OS.

## Development Requirements

- Windows 11.
- PowerShell 7+.
- VMware Workstation Pro.
- WSL with `xorriso`.
- OpenSSH client.
- Mutagen 0.18.x.

## Before Submitting Changes

Run:

```powershell
pwsh -NoProfile -Command '$failed = $false; Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object { $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors) > $null; if ($errors) { $failed = $true; $path = $_.FullName; $errors | ForEach-Object { "{0}:{1}: {2}" -f $path, $_.Extent.StartLineNumber, $_.Message } } }; if ($failed) { exit 1 }'
.\test-integration.ps1
.\deploy-check.ps1
.\cli\adp.ps1 doctor
```

For bootstrap shell scripts:

```powershell
$repo = (Get-Location).Path -replace '\\', '/'
$drive = $repo.Substring(0, 1).ToLowerInvariant()
$path = "/mnt/$drive" + $repo.Substring(2)
wsl bash -lc "bash -n '$path/bootstrap/base/setup-base.sh' '$path/bootstrap/frontend/setup-frontend.sh' '$path/bootstrap/backend/setup-backend.sh' '$path/bootstrap/agent/setup-agent.sh'"
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

## Security

The MVP uses local development defaults. Do not add real credentials, private SSH keys, tokens, internal hostnames, or customer data to the repository.
