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
- Workspace manifests, task recipes, validation recording, review gates, commit readiness, and Markdown release evidence.
- Dev container metadata detection as runtime-internal project context.

## Near-Term Work

Near-term work focuses on making the public project safer and easier to use before expanding the execution surface:

- Improve first-run confidence and diagnostics.
- Keep command output actionable for missing tools, path problems, ISO placement, networking, and runtime connectivity.
- Expand non-destructive validation coverage for CLI behavior, configuration shape, documentation links, and workflow reports.
- Improve workspace report evidence so pull requests, releases, and maintainer handoffs are easier to review.
- Keep bilingual documentation aligned as command behavior changes.
- Tighten artifact hygiene so local state, logs, VM disks, ISOs, downloaded tools, and private maintainer material stay out of public commits.

## Workspace Orchestration

Workspace orchestration is the next major product layer. The goal is to make ADP-OS useful for real projects, not only runtime startup.

Planned directions:

- Workspace creation and project registration commands.
- Per-project sync lifecycle views.
- Runtime, project, validation, and task dashboards.
- Validation recipes that can be previewed, executed intentionally, recorded, and reviewed.
- Snapshot naming tied to tasks, milestones, and rollback intent.
- Clear separation between planning, execution, review, rollback, and commit.
- Better support for existing project environment metadata, including `.devcontainer/devcontainer.json` and `.devcontainer.json`.

Non-goals:

- ADP-OS should not become a container orchestrator.
- Workspace commands should not silently install packages, download large toolchains, create snapshots, run validation, stage files, or commit changes.
- Agent workflows should not bypass source review, rollback checks, or publication approval.

## Agent-Native Development

ADP-OS is designed for AI-assisted and agent-native development, but broad autonomous execution must remain gated by clear safety boundaries.

Planned directions:

- Task lifecycle commands that make preparation, execution, validation, review, rollback, and commit state explicit.
- Snapshot-first gates for high-risk or destructive tasks.
- Validation evidence that can be copied into pull requests or release notes.
- Review bundles that show source-review prompts, validation results, rollback context, and commit readiness.
- Runtime profiles that make it clear when a workload has elevated IO, package installation, Docker access, or broad filesystem access.
- Future task execution support only after preview, snapshot, validation, review, and rollback boundaries are strong enough.

## Runtime Expansion

ADP-OS currently targets Windows plus VMware Workstation. Future runtime expansion should preserve the same user-facing lifecycle while moving host-specific behavior behind adapters.

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
