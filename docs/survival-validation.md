# Survival Validation

[简体中文](zh-CN/survival-validation.md) | English

This guide turns the ADP-OS survival thesis into a repeatable validation workflow. It is for maintainers, early users, and reviewers who want to test whether ADP-OS solves a real Windows AI coding agent workflow problem before the project expands.

## Purpose

The current thesis is intentionally narrow:

> ADP-OS is a Windows-first local AI coding agent task lifecycle layer with rollback and evidence.

The validation question is:

> Do Windows-first AI coding agent users need a local task lifecycle layer with checkpoint, rollback, and evidence, or are WSL2, Docker, and Git already enough?

This is not a feature tour. It is not a pitch for a generic cloud development environment, Docker replacement, WSL replacement, VM manager, or multi-tenant platform.

Use this guide with the [10-Minute Survival Value Demo](demo-script.md). The demo script remains the command-by-command source of truth; this document defines who should participate, what to observe, what feedback to record, and how to classify the result.

This does not validate production readiness, enterprise governance, security guarantees, or every planned runtime carrier. It also does not count unless the rollback and evidence path is run or closely inspected from a real Windows + VMware setup.

## What Counts

Useful validation is based on behavior, not politeness.

Strong signals:

- A Windows AI coding agent user can describe a real task where Git rollback is not enough.
- A reviewer can explain why ADP-OS is an agent task lifecycle and evidence layer, not a WSL2 or Docker replacement.
- A user runs or closely follows the 10-minute demo and gives specific feedback.
- A user opens a GitHub issue, writes detailed feedback, or attempts an MCP or agent workflow integration.

Weak signals:

- "Looks interesting" with no follow-up.
- A star with no feedback.
- General curiosity about VMs, sandboxes, or MCP without a concrete workflow.

Negative signals:

- Users consistently say WSL2, Docker, and Git are enough.
- The evidence export is viewed as nice-to-have but not worth the setup cost.
- The demo succeeds technically but users cannot say when they would use ADP-OS.

## Target Reviewers

Prioritize people who can judge the problem directly:

| Priority | Reviewer | What to learn |
| --- | --- | --- |
| P0 | Windows developers who use Cursor, Claude Code, Codex, Cline, Hermes, or similar coding agents | Whether they already worry about agent mistakes, generated files, Docker state, package installs, or audit trails |
| P1 | MCP tool authors and agent framework maintainers | Whether ADP-OS can serve as a Windows local sandbox backend |
| P2 | Chinese Windows AI developers and independent builders | Whether local-first, bilingual, Windows-first tooling lowers adoption friction |
| P3 | AI code governance, DevEx, or platform engineers | Whether evidence exports map to review or audit workflows |

Do not optimize the first validation round for generic developers, Linux/macOS-first sandbox users, or enterprise procurement cycles.

## Validation Flow

1. **Problem interview**
   Ask how the user currently lets agents edit local code, what they fear, whether Git rollback is enough, and whether local or cloud sandboxes fit their work.

2. **Demo rehearsal**
   Run the full presenter script on the exact Windows + VMware host that will be shown to users. Record wall-clock time, command output mismatches, and whether rollback restores the expected files.

3. **10-minute demo**
   Use [10-Minute Survival Value Demo](demo-script.md). The demo must show a task checkpoint, a simulated agent mistake, evidence recording, rollback, and evidence export.

4. **Feedback capture**
   Record the user's environment, current workflow, whether they understood the difference from WSL2/Docker/Git, and the next action they chose.

5. **Decision summary**
   Classify the result as continue, pause, pivot, or stop only after enough real behavior signals exist.

## Demo Readiness Checklist

Before showing the demo to a user:

- Run the demo on a real Windows 10/11 host with VMware Workstation available and reachable.
- Use PowerShell 7 for the control plane. From a stock Windows shell, use `.\adp.cmd`; if only built-in Windows PowerShell 5.1 is available, run `.\setup.cmd` first so the user gets the PowerShell 7 install path instead of a broken ADP command.
- Use an ADP-OS checkout with public docs and recipes available.
- Pre-provision the `agent` runtime; first VM creation is not part of the 10-minute window.
- Confirm `adp doctor` reports 0 issues before the demo.
- Confirm `adp status agent` reports the runtime as running and SSH reachable.
- Confirm `adp sync status` reports the `agent` session as healthy or watching before the demo. Stop and recreate stale `adp-agent` sessions before starting the user-facing run.
- Confirm the presenter script fences sync before VM mutation and rollback: stop `agent` sync before the destructive task, keep it stopped through restore, and restart it only after choosing the host or VM workspace as the source of truth.
- Confirm post-restore readiness is observable through public ADP commands: after restore, `adp status agent` must return a bounded state; if the runtime is stopped, `adp up agent -NoBootstrap` must return and the following `adp status agent` must reach running + SSH reachable before direct SSH file checks.
- Create or confirm the snapshot named by the demo script.
- Confirm `workspace-report.md` is generated in the manifest workspace root before evidence export. For the public recipe manifest, that is `configs\workspace-report.md`.
- Export a real evidence ZIP with `adp workspace evidence -Export`, then verify it contains `README.txt`, `snapshot-hashes.json`, `operation-log.json`, `workspace-report.md`, and `adp-workspace.json`.
- Verify rollback restores `README.md`, removes `generated/output.json`, and reverts the `src/main.ts` demo mutation. If restore leaves the runtime stopped, run `adp up agent -NoBootstrap` and `adp status agent` before SSH file checks.
- Record real restore, `up`, `status`, and SSH verification durations. If the run needs undocumented VMware intervention, private cleanup, or manual host-key surgery beyond the public troubleshooting path, it is rehearsal evidence, not valid 10-minute demo evidence.
- Keep the actual elapsed time. Do not round away slow snapshot or restore behavior.

If a pre-provisioned `agent` VM is shown as still installing, stop treating the run as a normal first install. Run `adp status agent`, `adp doctor`, and `adp network apply agent -Plan`. A common stale-VM failure is an old guest that was already provisioned but was created before static network seed injection, so it boots on an old VMware NAT address while ADP-OS targets the current static IP. That is a network drift/product-readiness issue, not valid 10-minute demo evidence.

If `adp snapshot create agent <name>` appears stuck, do not continue the user demo until the snapshot is confirmed. Check `vmrun listSnapshots` or rerun `adp snapshot create` after the command returns. A snapshot that exists but left the CLI hanging should be recorded as a product failure for the rehearsal, because rollback and evidence are the core survival path.

Hard rule: if VMware is unavailable, do not run the survival demo. Do not fake VMware, snapshot, restore, SSH, evidence chain, or evidence export output.

## Observer Checklist

During the demo, record whether:

- The environment precheck passed.
- VMware was actually reachable.
- `doctor` reported 0 issues before the user-facing run.
- The `agent` runtime was already running.
- The `agent` sync session was healthy before the demo and fenced/stopped during VM mutation and restore.
- A real snapshot was created or reused.
- Evidence was recorded before and after the agent-style task.
- The task changed something Git alone would not fully clean up.
- Rollback restored the expected runtime and workspace state; if the runtime stopped after restore, it was restarted with `adp up agent -NoBootstrap` before SSH verification.
- Post-restore readiness completed through documented ADP commands, and any `ssh-timeout`, `auth-pending`, `unreachable`, or recovery state was recorded instead of being hidden.
- An evidence ZIP was exported and contained the expected five entries.
- The participant could explain the difference from Git reset, Docker, WSL2, and Dev Containers.
- Any command output differed from the presenter script.

## Participant Questions

Prefer concrete answers over compliments:

1. What AI coding agent do you use today?
2. What OS and local development setup do you use?
3. What do you currently do before allowing an agent to modify a project?
4. What agent failure are you most worried about?
5. When is `git reset` enough for you?
6. When is `git reset` not enough?
7. Did the rollback demo solve a real problem for you?
8. Did the evidence report solve a real problem for you?
9. Could you imagine using ADP-OS in one real workflow?
10. What would block you from trying it?

## Feedback Record

Use one record per session. Private notes may live outside the public repository if they identify a person.

```yaml
session_id: "YYYYMMDD-NN"
date: "2026-MM-DD"
persona: "P0|P1|P2|P3"
channel: "github|discord|v2ex|call|referral|other"
os: "Windows 10|Windows 11|Other"
agent_tool: "Cursor|Claude Code|Codex|Cline|Hermes|Other|None"
current_sandbox: "none|wsl2|docker|manual-vm-snapshot|manual-backup|cloud-sandbox|other"

pain_agent_mistakes: "high|medium|low|none"
git_enough: "yes|no|sometimes"
wsl2_docker_enough: "yes|no|conditional"
needs_evidence: "high|medium|low|none"

demo_ran: true
demo_duration_minutes: 10
understood_difference: "yes|partial|no"
own_use_case: "specific use case or empty"
top_friction: "setup|vmware|concept|docs|missing integration|not needed|other"

action_star: false
action_issue: false
action_integration_attempt: false
action_detailed_feedback: false
action_requested_followup: false

signal: "strong|moderate|weak|negative"
notes: "Short summary. Avoid secrets, tokens, private code, and personal data."
```

## Decision Gates

Treat these as maintainer decision inputs. Continue beyond this validation round only when the evidence supports it:

- At least 10 relevant target users are identified and contacted or queued for contact.
- At least 3 real users run or closely inspect the 10-minute demo.
- At least 2 external feedback artifacts exist, such as GitHub issues, detailed comments, or concrete private feedback notes.
- At least 1 third-party MCP, agent, or workflow integration attempt is identified or initiated.
- At least 3 users can restate that ADP-OS is an agent task lifecycle + rollback + evidence layer, not a WSL2 or Docker replacement.

Consider stopping, shrinking, or pivoting when:

- It is not possible to find 10 relevant people willing to look at it.
- Most reviewers say WSL2, Docker, and Git are enough after being shown the rollback and evidence scenario.
- Nobody is willing to run or closely inspect the demo.
- The demo cannot reach value quickly enough even on a prepared machine.
- Evidence reports are consistently perceived as optional paperwork rather than a workflow need.

## Failure Classification

| Failure type | Examples | Interpretation |
| --- | --- | --- |
| Environment failure | VMware missing, ISO missing, Mutagen unavailable, SSH key issue, NAT mismatch | Setup friction is real. This does not by itself prove the product thesis false. |
| Product failure | ADP command fails, evidence hash chain breaks, restore fails while VMware is healthy, post-restore `status` cannot classify readiness, or `stop`/`status`/`up` waits without bounded output | Fix the product before using the run as validation evidence. |
| Positioning failure | The feature works, but the participant does not understand why it matters | Improve the demo, docs, or product framing before expanding scope. |
| Workflow failure | The participant understands the value, but the process is too slow or awkward even though ADP reports bounded states and documented recovery paths | Reduce friction in the existing Windows + VMware path before adding new platforms. |
| Fit failure | The participant only needs a Linux shell, normal Git rollback, or hosted cloud sandbox | Do not count this as a thesis failure for the target user group. |
| Value failure | User says "this is just VM snapshot", cannot explain Git vs ADP rollback, or rejects evidence value | The product thesis or positioning is failing. Treat this as the most serious signal. |

## Outreach Rules

- Contact people manually and only in relevant contexts.
- Do not scrape private contact information.
- Do not use bots or automated comments.
- Do not ask users for tokens, passwords, API keys, private keys, or access to private repositories.
- Do not collect telemetry or phone home from validation sessions.
- Do not fake stars, issues, testimonials, reviews, or user identities.
- Do not publicly name a participant without explicit permission.
- Be honest that ADP-OS is early and under validation.
- Submit feedback through GitHub Discussions or the feedback channel provided by the maintainer for the validation session. Do not present Discord as an active official channel until the server exists.

## Scope Guardrails

During survival validation, do not expand ADP-OS into:

- A generic CDE.
- A Docker, Dev Containers, or WSL2 replacement.
- A broad VM manager.
- A web UI or multi-tenant enterprise platform.
- A cloud sandbox API clone.
- A broad runtime provider abstraction unless user evidence specifically demands it.

Use the existing demo and evidence surfaces first. Product expansion should follow evidence, not precede it.

## Related Docs

- [10-Minute Survival Value Demo](demo-script.md)
- [Evidence Chain](evidence.md)
- [Capabilities](capabilities.md)
- [ADP-OS and Docker](positioning.md)
- [Workspaces](workspaces.md)
- [Operations](operations.md)
- [Troubleshooting](troubleshooting.md)
- [Release Readiness](release-readiness.md)
