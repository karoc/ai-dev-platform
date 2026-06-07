# ADP-OS 10-Minute Survival Value Demo — Presenter Script

> **Purpose**: Prove that ADP-OS delivers value beyond WSL2 + Docker + `git reset`.
> **Duration**: 10 minutes (±2 min for VMware snapshot/restore timing).
> **Audience**: Windows developers who use AI coding agents and worry about agent mistakes.
> **Pre-requisite**: Agent runtime must be pre-provisioned before the session (VM creation takes 15–45 min).
>
> **Status**: Ready for presenter rehearsal. Verify every command on the target Windows + VMware host before recording.

---

## Pre-Demo Setup Checklist

Run these before the session. Do NOT include in the 10-minute window.

- [ ] 1. **Verify VMware** — `adp doctor` shows VMware reachable. If "VMware: unavailable", stop — demo cannot proceed.
- [ ] 2. **Verify agent runtime** — `adp status agent` shows "running, SSH reachable, sync watching".
- [ ] 3. **Pre-create snapshot** — `adp snapshot create agent before-broad-agent-refactor` (VMware snapshot; takes 30–120s). If it already exists, the command reports "Snapshot already exists" and exits fast.
- [ ] 4. **Note agent IP** — `adp status agent -Json | ConvertFrom-Json | Select-Object -ExpandProperty Runtimes | Where-Object {$_.Runtime -eq 'agent'} | Select-Object -ExpandProperty DetectedIp`. Or use SSH alias: `ssh adp-os-adp-agent`.
- [ ] 5. **Clean terminal** — close other windows, disable notifications. Use Windows Terminal with PowerShell 7, clean profile.
- [ ] 6. **Prepare agent workspace** — SSH into agent VM and ensure `/home/adp/workspace/agent-workspace/` has a git repo with README.md, src/main.ts, and a clean working tree.
- [ ] 7. **Verify evidence chain** — `adp workspace evidence -Snapshot -ManifestPath configs\workspace.recipes.example.json` should succeed.

> **Hard constraint**: If VMware is unavailable, the demo CANNOT be run. Do not fake snapshot, restore, or evidence output.

---

## The Demo Flow

### Phase A: Environment Verification (分钟 0–1)

**Goal**: Prove the platform is real and ready.

```powershell
# Step A1 — Precheck (existing command)
adp precheck
```

Expected: 7/7 green (VMware, WSL, Mutagen, SSH, ISO, config, network).

> Narrator: "ADP-OS runs on your Windows machine. Every prerequisite is checked. No hidden surprises."

```powershell
# Step A2 — Agent runtime status (existing command)
adp status agent
```

Expected: `agent: running, SSH reachable, sync watching`.

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
adp workspace recipes -ManifestPath configs\workspace.recipes.example.json
```

Expected: Shows 4 tasks including `broad-agent-refactor` (risk: high, requires_snapshot: true).

> Narrator: "ADP-OS understands tasks, not just VMs. Each task declares risk level, required snapshots, and validation commands."

```powershell
# Step B3 — Create VM snapshot (existing command)
adp snapshot create agent before-broad-agent-refactor
```

Expected: "Snapshot 'before-broad-agent-refactor' created successfully" — or "already exists" if pre-created.

> Narrator: "This is NOT git stash. This is a VMware VM snapshot — the entire filesystem, installed packages, Docker containers, systemd services, caches. Everything."

```powershell
# Step B4 — Sign snapshot in evidence chain (existing command)
adp workspace evidence -Snapshot -ManifestPath configs\workspace.recipes.example.json
```

Expected: "Evidence snapshot entry recorded."

```powershell
# Step B5 — Record operation log entry (existing command)
adp workspace evidence -Log -Operation "snapshot" -Details "before-broad-agent-refactor: clean pre-agent checkpoint" -ManifestPath configs\workspace.recipes.example.json
```

Expected: "Evidence log entry recorded."

> Narrator: "ADP-OS has TWO independent evidence chains: snapshot-hashes (cryptographic VM state proof) and operation-log (human-readable action record). Both use SHA-256 chaining. Tamper with one entry and the entire chain breaks."

---

### Phase C: Agent Executes Task (分钟 4–6)

**Goal**: Run a simulated AI agent task. The agent makes useful changes AND a mistake (deletes README.md).

```powershell
# Step C1 — Mark task as prepared (existing command)
adp workspace task mark broad-agent-refactor prepared -ManifestPath configs\workspace.recipes.example.json
```

```powershell
# Step C2 — Mark checkpoint (existing command)
adp workspace task mark broad-agent-refactor checkpointed -ManifestPath configs\workspace.recipes.example.json
```

> Narrator: "The task lifecycle records every gate. Prepared → Checkpointed → the agent can now work."

```powershell
# Step C3 — Simulate agent modifying project (SSH into agent VM)
# Use the IP noted in pre-demo setup, or SSH alias:
ssh adp-os-adp-agent "cd /home/adp/workspace/agent-workspace && echo '// AI-generated feature' >> src/main.ts && mkdir -p generated && echo 'build artifact' > generated/output.json && rm README.md"
```

> Narrator: "The agent adds a feature to main.ts, generates build artifacts, and — accidentally — deletes README.md. This is a common AI agent mistake."

```powershell
# Step C4 — Simulated validation (SSH)
ssh adp-os-adp-agent "cd /home/adp/workspace/agent-workspace && echo 'FAIL: missing README.md' && git diff --check"
```

> Narrator: "Validation catches the problem: README.md is gone."

```powershell
# Step C5 — Record operation (existing command)
adp workspace evidence -Log -Operation "run" -Details "task=broad-agent-refactor; agent=claude-code; files_changed=2; warnings=1" -ManifestPath configs\workspace.recipes.example.json
```

> Narrator: "Every operation is recorded. The evidence chain now has: snapshot → run. Irreversible. Immutable."

**Pivot moment** — ask the viewer: *"Without ADP-OS, how would you know what the agent did?"*

---

### Phase D: Evidence Report (分钟 6–8)

**Goal**: Show that ADP-OS produces a verifiable evidence report.

```powershell
# Step D1 — Generate workspace report (existing command)
adp workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json | Tee-Object -FilePath workspace-report.md
```

Expected: Markdown report printed in the terminal and saved as `workspace-report.md` for the evidence export.

```powershell
# Step D2 — Declare AI-assisted development (existing command)
adp workspace declare -AiAssisted -Reviewer "presenter" -Notes "demo: agent modified src/main.ts and generated/output.json, accidentally deleted README.md" -ManifestPath configs\workspace.recipes.example.json
```

Expected: "Evidence declare entry recorded."

> Narrator: "The declare command creates a cryptographically-linked record that AI was involved. This answers: 'What did AI change? Who reviewed it? In which environment was it tested?'"

```powershell
# Step D3 — Show dashboard (existing command)
adp workspace dashboard -ManifestPath configs\workspace.recipes.example.json
```

> Narrator: "The dashboard shows the full picture at a glance. But the real proof is in the evidence chain — detailed later."

---

### Phase E: Rollback Decision (分钟 8–9)

**Goal**: Show that ADP-OS rollback is fundamentally different from `git reset`.

```powershell
# Step E1 — Plan the rollback first (existing command)
adp restore agent before-broad-agent-refactor -Plan
```

Expected: "Plan only: no changes will be made" and "Would restore snapshot: 'before-broad-agent-refactor'."

> Narrator: "Safety first — ADP-OS defaults to plan-only. You see exactly what will happen before it happens."

```powershell
# Step E2 — Execute rollback (existing command)
adp restore agent before-broad-agent-refactor -Force
```

Expected: "Restored to snapshot 'before-broad-agent-refactor'."

```powershell
# Step E3 — Verify restoration (SSH)
ssh adp-os-adp-agent "cd /home/adp/workspace/agent-workspace && ls README.md && echo 'README restored. generated/output.json is gone (never existed before agent).'"
```

> Narrator: "Full VM rollback in one command. Let's compare with git reset:"

| What | `git reset HEAD~1` | ADP-OS `restore -Force` |
|------|--------------------|--------------------------|
| README.md | ✓ Recovered (tracked file) | ✓ Recovered |
| `generated/output.json` | ✗ Stays (untracked) | ✓ Removed entirely |
| `src/main.ts` changes | ✗ Stays (unstaged) | ✓ Reverted |
| Docker containers | ✗ Unaffected | ✓ Reverted |
| Installed packages | ✗ Unaffected | ✓ Reverted |
| systemd services | ✗ Unaffected | ✓ Reverted |

> Narrator: **"git reset only protects tracked files. ADP-OS protects the entire machine."**

---

### Phase F: Evidence Export (分钟 9–10)

**Goal**: Produce the portable, verifiable audit trail.

```powershell
# Step F1 — Export evidence ZIP (existing command)
adp workspace evidence -Export -Path evidence-demo-export.zip -ManifestPath configs\workspace.recipes.example.json
```

Expected: "Evidence Export Complete" and `Output      : ...\evidence-demo-export.zip`.

```powershell
# Step F2 — Show ZIP contents (PowerShell)
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::OpenRead("evidence-demo-export.zip").Entries | Select-Object FullName, Length
```

> Narrator: "The ZIP contains: snapshot-hashes.json (cryptographic proof), operation-log.json (immutable action record), workspace-report.md (human-readable summary), adp-workspace.json, and README.txt. This is a self-contained audit trail. A reviewer can verify the SHA-256 chain and confirm nothing was tampered with."

> Narrator: **"This is the artifact that proves value."**

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
| `adp precheck` shows red checks | Missing prerequisite | Follow remediation printed by precheck |
| `adp status agent` shows "VMware: unavailable" | VMware Workstation not running or vmrun not in PATH | Start VMware, verify `vmrun list` |
| `adp snapshot create` hangs | VMware snapshot taking longer than expected | Wait up to 120s; large VM disks take time |
| SSH connection refused | Agent VM IP changed or SSH service down | `adp status agent -Json` to get current IP; `adp up agent` to restart |
| `adp workspace evidence -Export` fails | Evidence directory missing | Run evidence -Snapshot and -Log first |

---

## Recording Setup (for video production)

- **Screen recording**: OBS Studio (free, Windows)
- **Terminal**: Windows Terminal + PowerShell 7, clean profile
- **Font**: Cascadia Code or Consolas, 14pt
- **Resolution**: 1920×1080
- **Style**: Clean white-on-black terminal. No face cam. Text overlays for key concepts.

---

Before recording, rehearse the script once on the exact machine that will appear in the video. Treat any output mismatch as a script bug, not as something to explain away during the demo.
