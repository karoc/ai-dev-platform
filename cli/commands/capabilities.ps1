# ADP-OS Capabilities Command
# Reports supported and planned host/runtime capabilities without changing state.

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "ADP-OS Capabilities" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Capabilities only: no VMs, sync sessions, snapshots, guest files, workspace files, downloads, or host networking will be changed." -ForegroundColor DarkGray
Write-Host ""

Write-Host "Current support:" -ForegroundColor Yellow
Write-Host "  Host control plane: Windows PowerShell" -ForegroundColor DarkGray
Write-Host "  Runtime carrier:    VMware Workstation" -ForegroundColor DarkGray
Write-Host "  Guest OS profile:   Ubuntu Server 26.04" -ForegroundColor DarkGray
Write-Host "  Runtime profiles:   frontend, backend, agent" -ForegroundColor DarkGray
Write-Host "  Workspace sync:     Mutagen over SSH" -ForegroundColor DarkGray
Write-Host "  Runtime lifecycle:  up, status, stop, logs, destroy, network apply" -ForegroundColor DarkGray
Write-Host "  Rollback lifecycle: snapshot create, restore" -ForegroundColor DarkGray
Write-Host "  Evidence workflow:  workspace dashboard, report, report -Markdown, task validation recording" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Runtime carrier matrix:" -ForegroundColor Yellow
Write-Host "  [supported] vmware-workstation" -ForegroundColor Green
Write-Host "      host: Windows" -ForegroundColor DarkGray
Write-Host "      lifecycle: create/start/status/stop/snapshot/restore/destroy/network/bootstrap" -ForegroundColor DarkGray
Write-Host "      boundary: full VM runtime with static NAT, SSH bootstrap, Docker-capable guest, and VMware snapshots" -ForegroundColor DarkGray
Write-Host "  [planned] hyper-v" -ForegroundColor Yellow
Write-Host "      status: not implemented; no Hyper-V VM creation or lifecycle commands are available" -ForegroundColor DarkGray
Write-Host "  [planned] kvm-libvirt" -ForegroundColor Yellow
Write-Host "      status: not implemented; Linux adapter is a stub" -ForegroundColor DarkGray
Write-Host "  [planned] macos-vm" -ForegroundColor Yellow
Write-Host "      status: not implemented; macOS adapter is a stub" -ForegroundColor DarkGray
Write-Host "  [exploratory] container-backed" -ForegroundColor Yellow
Write-Host "      status: not implemented as an ADP outer runtime carrier" -ForegroundColor DarkGray
Write-Host "      boundary: Docker and dev containers are runtime-internal project tools today, not the ADP outer lifecycle" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Host adapter matrix:" -ForegroundColor Yellow
Write-Host "  [supported] windows" -ForegroundColor Green
Write-Host "      adapters: filesystem, VMware, SSH, Mutagen" -ForegroundColor DarkGray
Write-Host "  [planned] linux" -ForegroundColor Yellow
Write-Host "      adapters/linux/linux.ps1 exists as a stub and returns unavailable" -ForegroundColor DarkGray
Write-Host "  [planned] macos" -ForegroundColor Yellow
Write-Host "      adapters/mac/mac.ps1 exists as a stub and returns unavailable" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Inner environment integrations:" -ForegroundColor Yellow
Write-Host "  Docker:       installed inside bootstrapped Ubuntu runtimes; not a replacement for the ADP outer runtime lifecycle" -ForegroundColor DarkGray
Write-Host "  Devcontainer: detected non-destructively as project metadata in workspace views; not executed by ADP workspace planning commands" -ForegroundColor DarkGray
Write-Host "  Browser tests: frontend helper can install browser dependencies on demand inside the runtime; browser binaries are not committed" -ForegroundColor DarkGray
Write-Host ""

Write-Host "Expansion rules:" -ForegroundColor Yellow
Write-Host "  Keep host-specific behavior behind adapters." -ForegroundColor DarkGray
Write-Host "  Preserve the same user-facing lifecycle before adding a new runtime carrier." -ForegroundColor DarkGray
Write-Host "  Do not label a carrier supported until create/start/status/stop/snapshot or equivalent rollback behavior is documented and tested." -ForegroundColor DarkGray
Write-Host "  Do not hide security tradeoffs behind a uniform runtime label." -ForegroundColor DarkGray
Write-Host ""
Write-Host "Docs: docs/capabilities.md" -ForegroundColor DarkGray
