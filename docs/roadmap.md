# Roadmap

[简体中文](zh-CN/roadmap.md) | English

This public roadmap explains the product direction for ADP-OS without exposing private maintainer planning. It is directional, not a release promise. Exact timing depends on validation quality, user feedback, platform constraints, and maintainer capacity.

ADP-OS is not a Docker replacement. Its long-term role is the outer lifecycle for local AI development runtimes: provisioning, workspace synchronization, runtime bootstrap, diagnostics, snapshot rollback, validation evidence, and human review boundaries. Docker, Docker Compose, and dev containers remain runtime-internal tools that ADP-managed environments should detect, preserve, and eventually orchestrate safely.

## Product Direction

ADP-OS is moving toward a local, reproducible, agent-native development platform:

- Local-first: keep source code, task execution, runtime state, and review evidence under user control by default.
- Runtime-backed: use VM or VM-like boundaries for workloads that need real operating systems, Docker, package installation, and rollback.
- Workspace-aware: understand projects, runtimes, sync sessions, validation recipes, task state, snapshots, and review gates as one workflow.
- Evidence-driven: make validation output, release readiness, rollback context, and handoff notes easy to collect and review.
- Human-controlled: keep review, commit, publication, credentials, destructive operations, and cost-bearing infrastructure as explicit human-controlled boundaries.
- Compatible: integrate with existing project conventions such as Docker, Docker Compose, and `devcontainer.json` instead of replacing them.

## Current Stage

The current public project is a Windows VMware MVP plus open-source hardening:

- Windows PowerShell control plane.
- VMware Workstation runtime factory.
- Ubuntu Server runtimes for `frontend`, `backend`, and `agent`.
- Mutagen workspace synchronization.
- Static VMware NAT networking.
- SSH bootstrap for common developer tools.
- Snapshot create, restore, stop, logs, status, diagnostics, and plan previews.
- Shared non-destructive validation through `tests\validate.ps1`.
- Bilingual public documentation.
- Workspace manifests, recipes, local directory creation, project open/sync/project views, task lifecycle commands, milestone planning, evaluation planning, sync hygiene checks, validation recording, review gates, commit readiness, and Markdown release evidence.
- Dev container metadata detection as runtime-internal project context.
- A public capability boundary through `adp capabilities`.

## Near-Term Work

Near-term work focuses on making the public project safer and easier to use before expanding the execution surface:

- Improve first-run confidence and diagnostics.
- Keep command output actionable for missing tools, path problems, ISO placement, networking, and runtime connectivity.
- Expand non-destructive validation coverage for CLI behavior, configuration shape, documentation links, and workflow reports.
- Improve workspace report evidence so pull requests, releases, and maintainer handoffs are easier to review.
- Keep bilingual documentation aligned as command behavior changes.
- Tighten artifact hygiene so local state, logs, VM disks, ISOs, downloaded tools, and private maintainer material stay out of public commits.

## Workspace Orchestration

Workspace orchestration is the current major product layer. The goal is to make ADP-OS useful for real projects, not only runtime startup.

Current public surface:

- Workspace manifests with projects, tasks, milestones, evaluations, validation commands, review metadata, and snapshot intent.
- `workspace create [-Plan]` for manifest-declared local project directories. Execution creates missing local directories only; it does not clone repositories, start runtimes, start sync, open SSH, create snapshots, run validation, run evaluation commands, or run Git.
- `workspace open`, `workspace sync`, and `workspace project` views that turn one project entry into explicit local, runtime, sync, validation, and evidence handoff steps without performing those actions.
- `workspace status`, `workspace dashboard`, and `workspace report` views for runtime, project, sync hygiene, validation, evaluation, milestone, task, review, rollback, and commit readiness.
- `workspace report -Markdown` for copyable pull request, release, or maintainer handoff evidence.
- Validation recipes that can be previewed, executed intentionally through `workspace task validate <task> -Execute`, recorded in ignored local state, and reviewed later.
- Snapshot naming tied to tasks, milestones, and rollback intent through non-blocking convention checks.
- Dev container metadata detection for `.devcontainer/devcontainer.json` and `.devcontainer.json` as runtime-internal project context.

Remaining directions:

- Evolve project registration from local directory creation into safer clone/import guidance without hiding Git operations.
- Improve workspace evidence quality as real projects expose gaps in validation, review, rollback, and sync workflows.
- Keep tightening generated-artifact sync defaults and review ergonomics for common stacks.
- Explore stronger project-environment integration while keeping Docker, Docker Compose, and dev containers as inner tools.

Non-goals:

- ADP-OS should not become a container orchestrator.
- Workspace commands should not silently install packages, download large toolchains, create snapshots, run validation, stage files, or commit changes.
- Agent workflows should not bypass source review, rollback checks, or publication approval.

## Agent-Native Development

ADP-OS is designed for AI-assisted and agent-native development, but broad autonomous execution must remain gated by clear safety boundaries.

Current public surface:

- Task lifecycle commands for prepare, snapshot, run guidance, validate, review, rollback guidance, commit guidance, and local state marking.
- Snapshot-first gates for high-risk or destructive tasks, including explicit local `checkpoint-waived` state when a human reviewer accepts missing VM snapshot protection.
- Validation evidence that can be recorded by explicit task validation execution and copied into reports or Markdown release evidence.
- Review bundles that show source-review prompts, sync hygiene, validation results, evaluation links, rollback context, and commit readiness.
- Milestone and evaluation planning surfaces that make broader agent-native review criteria visible without executing evaluation commands.
- Runtime profile language that makes elevated agent IO and snapshot recommendations visible.

Remaining directions:

- Keep broad task execution plan-only until preview, snapshot, validation, review, rollback, and commit boundaries are strong enough across real projects.
- Dogfood evaluation hooks and report evidence against more project shapes before adding evaluation execution.
- Improve human review bundles and release evidence from real maintainer and contributor workflows.
- Explore richer runtime profiles only when their security and rollback boundaries can be explained and tested.

## Runtime Expansion

ADP-OS currently targets Windows plus VMware Workstation. Future runtime expansion should preserve the same user-facing lifecycle while moving host-specific behavior behind adapters.

For the current supported and planned capability boundary, run `.\cli\adp.ps1 capabilities` or see [Capabilities](capabilities.md). That boundary is authoritative for what is available today; this roadmap remains directional.

Candidate directions:

- Linux host support.
- macOS host support.
- Hyper-V adapter.
- KVM adapter.
- Lighter VM-like or container-backed runtimes where they fit the safety model.

Design constraints:

- Keep adapter-specific behavior under adapter boundaries.
- Preserve a coherent runtime lifecycle across hosts.
- Do not hide security tradeoffs behind a uniform label.
- Keep Docker and dev containers as inner development-environment tools unless a future runtime explicitly documents a different boundary.

## Ecosystem Alignment

The roadmap is intentionally aligned with current developer-tooling movement:

- OpenAI Codex describes coding tasks running in isolated environments with repository context, terminal/test evidence, and reviewable outputs: <https://openai.com/index/introducing-codex/>.
- GitHub Copilot cloud agent uses ephemeral development environments, branches, pull-request workflows, and visible logs so developers can review and decide when work is ready: <https://docs.github.com/en/copilot/concepts/agents/cloud-agent/about-cloud-agent>.
- Dev containers provide a widely used project-level environment format through `devcontainer.json`: <https://containers.dev/>.
- Docker Sandboxes highlights isolated microVM environments for coding agents that need package installation, Docker, filesystem boundaries, and host protection: <https://docs.docker.com/ai/sandboxes/>.

These signals support ADP-OS's product direction: local/self-managed runtimes, explicit boundaries, Docker-capable inner environments, validation evidence, rollback, and human review gates.

## Release and Publication

Public updates should follow the release process:

- Run `.\tests\validate.ps1`.
- Update English and Simplified Chinese documentation together when translated docs exist.
- Generate `adp workspace report -Markdown` evidence when workflow, validation, release-readiness, or task behavior changes.
- Check for local artifacts, credentials, generated state, VM files, ISO files, downloaded tools, and private maintainer material.
- Commit only after validation and review.
- Push or publish only after owner authorization.

See [Release Process](release-process.md) and [Release Readiness](release-readiness.md) for the detailed release boundary.
