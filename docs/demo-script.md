# ADP-OS 10-Minute Survival Value Demo — Presenter Script

> **Purpose**: Prove that ADP-OS delivers value beyond WSL2 + Docker + `git reset`.
> **Duration**: 10 minutes (±2 min for VMware snapshot/restore timing).
> **Audience**: Windows developers who use AI coding agents and worry about agent mistakes.
> **Pre-requisite**: Agent runtime must be pre-provisioned before the session (VM creation takes 15–45 min).
>
> **Status**: Corrected after controlled Windows + VMware rehearsal. Re-run this exact script on the target host before recording.

---

## Public-Only Recording Checklist

Before recording or showing a public demo, the run must be reproducible from the public repository only.

- Use only the public ADP-OS checkout, public docs, public recipe manifest, public issue templates, and artifacts produced by public ADP-OS commands.
- The user-facing shell command is `adpos`; from the repository root, `.\adpos.cmd` is the local wrapper before `PATH` refresh. Do not introduce an `adp` shell command.
- Do not rely on private maintainer scripts, private cleanup notes, private repositories, private feedback records, unpublished support channels, or undocumented VMware intervention.
- Use `configs\workspace.recipes.example.json`, `broad-agent-refactor`, `before-broad-agent-refactor`, and `/home/adp/workspace/agent-workspace` as the public demo baseline.
- Do not start the timed recording until VMware is reachable, `agent` is pre-provisioned, `adpos doctor`, `adpos status agent`, and `adpos sync status` report the expected public readiness.
- Keep the sync fence explicit: stop `agent` sync before VM mutation, keep it stopped through restore, and restart it only after choosing the host or VM workspace as the source of truth.
- Generate `configs\workspace-report.md` before evidence export and verify the evidence ZIP contains `README.txt`, `snapshot-hashes.json`, `operation-log.json`, `workspace-report.md`, and `adp-workspace.json`.
- Stop the recording and classify it as rehearsal or product-readiness evidence if restore readiness cannot be shown through public ADP commands, if direct SSH needs undocumented host-key surgery, if private cleanup is needed, or if secrets or private local paths are visible.
- Recording prep does not include outreach. No public posting, automated outreach, scraping, bulk messages, testimonials, queued contacts, Discord, GitHub Discussions, or target-user contact is approved or official until the maintainer explicitly enables or approves it.

## Pre-Demo Setup Checklist

Run these before the session. Do NOT include in the 10-minute window.

- Start with `adpos demo -Plan` to print the providerless readiness guide. It is guidance only: it does not run the demo, create or start VMs, change sync sessions, create snapshots, open SSH, change host configuration, change PATH, write files, publish recordings, or approve outreach.
- [ ] 1. **Verify VMware** — `adpos doctor` shows VMware reachable. If "VMware: unavailable", stop — demo cannot proceed.
- [ ] 2. **Verify agent runtime** — `adpos status agent` shows the VM running, SSH reachable, and sync healthy.
- [ ] 3. **Pre-create snapshot** — `adpos snapshot create agent before-broad-agent-refactor` (VMware snapshot; takes 30–120s). If it already exists, confirm it was created from the exact workspace baseline for this recording. If the baseline changed, replace it during pre-demo setup with VMware Workstation/`vmrun`, or choose a fresh snapshot name before rehearsing.
- [ ] 4. **Note agent IP** — `adpos status agent -Json | ConvertFrom-Json | Select-Object -ExpandProperty Runtimes | Where-Object {$_.Runtime -eq 'agent'} | Select-Object -ExpandProperty DetectedIp`. Or use SSH alias: `ssh adp-os-adp-agent`.
- [ ] 5. **Clean terminal** — close other windows and disable notifications. Use Windows Terminal with a clean profile. From stock Windows shells, run ADP-OS through `.\adpos.cmd`; if it reports missing PowerShell 7, run `.\setup.cmd` and install PowerShell 7 before recording.
- [ ] 6. **Prepare agent workspace** — SSH into agent VM and ensure `/home/adp/workspace/agent-workspace/` has a `.git` directory, README.md, src/main.ts, and a clean working tree. Mutagen sync does not copy `.git`; if sync recreated the files without git metadata, initialize the VM workspace and commit the clean demo baseline inside the VM before creating the snapshot.
- [ ] 7. **Plan the sync fence** — start the demo with sync healthy, then stop `agent` sync before mutating the VM. Do not restart sync after restore until you have chosen the host or VM workspace as the source of truth and reconciled the other side.
- [ ] 8. **Verify evidence chain** — `adpos workspace evidence -Snapshot -ManifestPath configs\workspace.recipes.example.json` should succeed.

> **Hard constraint**: If VMware is unavailable, the demo CANNOT be run. Do not fake snapshot, restore, or evidence output.

---

## The Demo Flow

### Phase A: Environment Verification (分钟 0–1)

**Goal**: Prove the platform is real and ready.

```powershell
# Step A1 — Precheck (existing command)
adpos precheck
```

Expected: all precheck rows OK, for example `6 OK, 0 WARN, 0 MISSING` on a fully prepared host.

> Narrator: "ADP-OS runs on your Windows machine. Every prerequisite is checked. No hidden surprises."

```powershell
# Step A2 — Agent runtime status (existing command)
adpos status agent
```

Expected: `agent` is running, SSH is reachable, and sync is healthy.

> Narrator: "The agent runtime is already provisioned — a full Ubuntu VM, isolated from your host, with bidirectional file sync."

---

### Phase B: Checkpoint and Begin Recording (分钟 1–4)

**Goal**: Show that ADP-OS checkpoints the ENTIRE VM, not just git. Begin cryptographic evidence chain.

```powershell
# Step B1 — Confirm the public recipe manifest is present
Test-Path configs\workspace.recipes.example.json
```

Expected: `True`.

```powershell
# Step B2 — Show available recipes (existing command)
adpos workspace recipes -ManifestPath configs\workspace.recipes.example.json
```

Expected: Shows 4 tasks including `broad-agent-refactor` (risk: high, requires_snapshot: true).

> Narrator: "ADP-OS understands tasks, not just VMs. Each task declares risk level, required snapshots, and validation commands."

```powershell
# Step B3 — Create VM snapshot (existing command)
adpos snapshot create agent before-broad-agent-refactor
```

Expected: "Snapshot 'before-broad-agent-refactor' created successfully" — or "already exists" if pre-created.

> Narrator: "This is NOT git stash. This is a VMware VM snapshot — the entire filesystem, installed packages, Docker containers, systemd services, caches. Everything."

```powershell
# Step B4 — Sign snapshot in evidence chain (existing command)
adpos workspace evidence -Snapshot -ManifestPath configs\workspace.recipes.example.json
```

Expected: "Evidence snapshot entry recorded."

```powershell
# Step B5 — Record operation log entry (existing command)
adpos workspace evidence -Log -Operation "snapshot" -Details "snapshot=before-broad-agent-refactor;state=clean-pre-agent-checkpoint" -ManifestPath configs\workspace.recipes.example.json
```

Expected: "Evidence log entry recorded."

> Narrator: "ADP-OS has TWO independent evidence chains: snapshot-hashes (cryptographic VM state proof) and operation-log (human-readable action record). Both use SHA-256 chaining. Tamper with one entry and the entire chain breaks."

---

### Phase C: Agent Executes Task (分钟 4–6)

**Goal**: Run a simulated AI agent task. The agent makes useful changes AND a mistake (deletes README.md).

```powershell
# Step C1 — Mark task as prepared (existing command)
adpos workspace task mark broad-agent-refactor prepared -ManifestPath configs\workspace.recipes.example.json
```

```powershell
# Step C2 — Mark checkpoint (existing command)
adpos workspace task mark broad-agent-refactor checkpointed -ManifestPath configs\workspace.recipes.example.json
```

> Narrator: "The task lifecycle records every gate. Prepared → Checkpointed → the agent can now work."

```powershell
# Step C3 — Stop sync before mutating the VM
adpos sync stop agent
adpos sync status
adpos workspace evidence -Log -Operation "sync" -Details "runtime=agent;action=stop;reason=restore-demo-fence" -ManifestPath configs\workspace.recipes.example.json
```

Expected: the `agent` sync session is stopped or no longer watching.

> Narrator: "The demo deliberately fences sync before the agent mutates files. This prevents two-way sync from copying a bad VM state back to the host, or copying a stale host state back into the VM after restore."

```powershell
# Step C4 — Simulate agent modifying project (SSH into agent VM)
# Use the IP noted in pre-demo setup, or SSH alias:
ssh adp-os-adp-agent "cd /home/adp/workspace/agent-workspace && echo '// AI-generated feature' >> src/main.ts && mkdir -p generated && echo 'build artifact' > generated/output.json && rm README.md"
```

> Narrator: "The agent adds a feature to main.ts, generates build artifacts, and — accidentally — deletes README.md. This is a common AI agent mistake."

```powershell
# Step C5 — Simulated validation (SSH)
ssh adp-os-adp-agent "cd /home/adp/workspace/agent-workspace && test -f README.md || { echo 'FAIL: missing README.md'; exit 1; } && git diff --check"
```

Expected: prints `FAIL: missing README.md` and exits non-zero.

> Narrator: "Validation catches the problem: README.md is gone. This is a real failing check, not just a message printed before a passing command."

```powershell
# Step C6 — Record operation (existing command)
adpos workspace evidence -Log -Operation "validate" -Details "task=broad-agent-refactor;agent=claude-code;files_changed=2;warnings=1;result=failed" -ManifestPath configs\workspace.recipes.example.json
```

```powershell
# Step C7 — Record failed validation in task lifecycle
adpos workspace task mark broad-agent-refactor validation_failed -ManifestPath configs\workspace.recipes.example.json
```

Expected: ADP records the external validation result as failed.

> Narrator: "Every operation is recorded. The evidence chain now has: snapshot → sync fence → failed validation. Irreversible. Immutable."

**Pivot moment** — ask the viewer: *"Without ADP-OS, how would you know what the agent did?"*

---

### Phase D: Evidence Report (分钟 6–8)

**Goal**: Show that ADP-OS produces a verifiable evidence report.

```powershell
# Step D1 — Generate workspace report (existing command)
adpos workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json | Tee-Object -FilePath configs\workspace-report.md
```

Expected: Markdown report printed in the terminal and saved as `configs\workspace-report.md` for the evidence export. The export uses the manifest directory as the workspace root.

```powershell
# Step D2 — Declare AI-assisted development (existing command)
adpos workspace declare -AiAssisted -Reviewer "presenter" -Notes "demo-agent-modified-src-main-ts-generated-output-json-deleted-readme" -ManifestPath configs\workspace.recipes.example.json
```

Expected: "Evidence declare entry recorded."

> Narrator: "The declare command creates a cryptographically-linked record that AI was involved. This answers: 'What did AI change? Who reviewed it? In which environment was it tested?'"

```powershell
# Step D3 — Show dashboard (existing command)
adpos workspace dashboard -ManifestPath configs\workspace.recipes.example.json
```

> Narrator: "The dashboard shows the full picture at a glance. But the real proof is in the evidence chain — detailed later."

---

### Phase E: Rollback Decision (分钟 8–9)

**Goal**: Show that ADP-OS rollback is fundamentally different from `git reset`.

```powershell
# Step E1 — Plan the rollback first (existing command)
adpos restore agent before-broad-agent-refactor -Plan
```

Expected: "Plan only: no changes will be made" and "Would restore snapshot: 'before-broad-agent-refactor'."

> Narrator: "Safety first — ADP-OS defaults to plan-only. You see exactly what will happen before it happens."

```powershell
# Step E2 — Execute rollback (existing command)
adpos restore agent before-broad-agent-refactor -Force
```

Expected: "Restored to snapshot 'before-broad-agent-refactor'."

```powershell
# Step E3 — Post-restore readiness gate
adpos status agent
```

Expected: ADP returns a bounded, classified status. The runtime may be stopped after restore. If it is stopped, restart it without bootstrapping:

```powershell
adpos up agent -NoBootstrap
adpos status agent
```

Expected: `agent: running, SSH reachable`. Continue only after `adpos status agent` reaches that state. If `status` reports `ssh-timeout`, `auth-pending`, `unreachable`, or any recovery state after the restart, stop the recording and treat the run as rehearsal/product-readiness evidence, not a successful public demo. Keep sync stopped until host and VM workspace state are reconciled.

```powershell
# Step E4 — Verify restoration inside the VM (SSH)
ssh adp-os-adp-agent "cd /home/adp/workspace/agent-workspace && test -f README.md && echo README_OK && test ! -e generated/output.json && echo GENERATED_GONE && ! grep -q 'AI-generated feature' src/main.ts && echo MAIN_TS_REVERTED"
```

If direct OpenSSH reports a stale host-key warning after restore, refresh only the ADP runtime alias/IP entry, rerun `adpos status agent`, and continue only when status is running and SSH reachable.

> Narrator: "Full VM rollback in one command. Let's compare with git reset:"

| What | `git reset HEAD~1` | ADP-OS `restore -Force` |
|------|--------------------|--------------------------|
| README.md | ✓ Recovered (tracked file) | ✓ Recovered |
| `generated/output.json` | ✗ Stays (untracked) | ✓ Removed entirely |
| `src/main.ts` changes | ✗ Stays (unstaged) | ✓ Reverted |
| Docker containers | ✗ Unaffected | ✓ Reverted |
| Installed packages | ✗ Unaffected | ✓ Reverted |
| systemd services | ✗ Unaffected | ✓ Reverted |

> Narrator: **"git reset only protects tracked files. ADP-OS restores the ADP-managed VM runtime state, including files and services inside that VM."**

---

### Phase F: Evidence Export (分钟 9–10)

**Goal**: Produce the portable, verifiable demo evidence package.

```powershell
# Step F1 — Export evidence ZIP (existing command)
adpos workspace evidence -Export -Path evidence-demo-export.zip -ManifestPath configs\workspace.recipes.example.json
```

Expected: "Evidence Export Complete" and `Output      : ...\evidence-demo-export.zip`.

```powershell
# Step F2 — Show ZIP contents (PowerShell)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zipPath = (Resolve-Path "evidence-demo-export.zip").Path
$zip = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
try {
    $entries = $zip.Entries | Select-Object FullName, Length
    $entries
    $names = $entries.FullName
    "README.txt", "snapshot-hashes.json", "operation-log.json", "workspace-report.md", "adp-workspace.json" | ForEach-Object {
        if ($names -notcontains $_) { throw "Missing ZIP entry: $_" }
    }
} finally {
    $zip.Dispose()
}
```

> Narrator: "The ZIP contains: snapshot-hashes.json (hash-chained checkpoint evidence), operation-log.json (hash-chained action record), workspace-report.md (human-readable summary), adp-workspace.json, and README.txt. This is a self-contained demo evidence package. A reviewer can verify the recorded SHA-256 chain and check for tampering in the exported evidence."

> Narrator: **"This is the artifact that shows the value."**

---

## The "So What" Test

After the demo, the viewer should be able to answer: *"When would I use ADP-OS instead of just git reset?"*

**Expected answer**: "When an AI agent does something that git reset can't undo — installing packages, modifying Docker containers, generating files, or running commands I need to audit later."

### Honest Admission

For simple use cases (small edits, tracked files only), `git reset` IS enough. ADP-OS is not for every task — it's for high-risk agent work.

> "If your agent only edits `.ts` files in a clean repo, git reset is fine. ADP-OS is for when the agent installs things, runs Docker, generates artifacts, or you need to prove what happened."

---

## What ADP-OS Does NOT Prove

The demo must honestly disclose:
- Does NOT prove VM isolation (VMware hypervisor property)
- Does NOT prove no external side effects (network calls, API writes)
- Does NOT prove no data exfiltration (evidence chain records VM-internal actions only)

> "Rollback is a runtime safety net, not a security guarantee."

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `adpos precheck` shows red checks | Missing prerequisite | Follow remediation printed by precheck |
| `adpos status agent` shows "VMware: unavailable" | VMware Workstation not running or vmrun not in PATH | Start VMware, verify `vmrun list` |
| `adpos snapshot create` reaches the command timeout but the snapshot exists | VMware snapshot creation crossed ADP's 120s command boundary | Treat this as pre-demo setup friction: confirm the snapshot exists before recording, and do not start the timed flow until the baseline snapshot is ready |
| SSH connection refused | Agent VM IP changed or SSH service down | `adpos status agent -Json` to get current IP; `adpos up agent` to restart |
| Restore succeeds but readiness does not settle | Restore left the VM stopped or guest SSH/control plane is still settling | Run `adpos status agent`; if stopped, run `adpos up agent -NoBootstrap`; continue only after status is running and SSH reachable |
| `status` reports `ssh-timeout` after restore | ADP bounded probe could not classify SSH readiness in time | Stop the recording, wait briefly, rerun `adpos status agent`, and record this as rehearsal/product-readiness evidence if it persists |
| Direct SSH reports host identification changed | OpenSSH has a stale `known_hosts` entry for the restored/recreated runtime | Refresh only the ADP runtime alias/IP entry, rerun `adpos status agent`, then continue only when ADP reports SSH reachable |
| VM restore reintroduces or loses unexpected files | Two-way sync was left running or restarted before reconciliation | Stop `agent` sync before mutation/restore; restart only after choosing host or VM as source of truth |
| `workspace-report.md` is missing from the ZIP | Report was written outside the manifest workspace root | Generate the report at `configs\workspace-report.md` before export |
| `adpos workspace evidence -Export` fails | Evidence directory or required evidence files missing | Run `evidence -Snapshot`, record `evidence -Log`, and generate `configs\workspace-report.md` first |

---

## Recording Setup (for video production)

- **Screen recording**: OBS Studio (free, Windows)
- **Terminal**: Windows Terminal, clean profile. From the repository root, `.\adpos.cmd ...` is the stock Windows shell entry point; if PowerShell 7 is missing, run `.\setup.cmd` first so it can attempt the `winget` bootstrap before recording. The ADP-OS control plane still runs on PowerShell 7.
- **Font**: Cascadia Code or Consolas, 14pt
- **Resolution**: 1920×1080
- **Style**: Clean white-on-black terminal. No face cam. Text overlays for key concepts.
- **Privacy review**: Rewatch the recording before publication. Discard and re-record if credentials, private local paths, private maintainer context, private feedback notes, or unrelated notifications are visible.

---

Before recording, rehearse the script once on the exact machine that will appear in the video. Treat any output mismatch as a script bug, not as something to explain away during the demo.
