# Release Process

[简体中文](zh-CN/release-process.md) | English

This process describes how ADP-OS changes should move from local work to a public update. It is intentionally lightweight because the project does not publish versioned release tags yet.

## Release Boundary

A release or public update should have:

- A focused change set.
- Passing repository validation.
- Updated public documentation for user-facing behavior.
- Simplified Chinese documentation updated with the English documentation when translated material exists.
- Workspace release evidence when the change affects workflows, runtimes, validation, documentation, or release readiness.
- A final safety check for local artifacts, credentials, generated state, and private maintainer material.

## Maintainer Flow

Use this order before committing, pushing, or publishing a public update:

1. Review the working tree with `git status --short --branch` and `git diff --stat`.
2. Run fast local validation while iterating:

   ```powershell
   .\tests\validate.ps1 -Quick
   ```

3. Run the full non-destructive validation gate before release:

   ```powershell
   .\tests\validate.ps1
   ```

4. Generate release evidence when workflows, runtimes, validation, docs, or release readiness are affected:

   ```powershell
   .\cli\adp.ps1 workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
   ```

   `configs\workspace.recipes.example.json` is an example manifest. Use the manifest that describes the actual task bundle for a real release decision.

5. Resolve any `release blocked`, `validation required`, `review required`, or `governance incomplete` decision before treating the change as releasable.
6. Confirm documentation links and language context through the shared validation gate.
7. Check that no local state, logs, VM disks, ISO files, downloaded tools, credentials, or private maintainer files are included.
8. Commit only after validation, documentation, evidence, and safety checks are complete.
9. Push or publish only when the repository owner has authorized publication.

## Evidence Expectations

For changes that affect workflows or release readiness, attach or paste the Markdown report output into the pull request, release note, or maintainer handoff.

The evidence should show:

- The release decision.
- Blockers, validation-required tasks, review-required tasks, and release candidates.
- Governance gaps.
- Sync hygiene status, including any `review sync ignore` tasks that must be reviewed before release.
- Validation status for relevant tasks.
- Snapshot gates for high-risk agent work.
- Handoff commands for review, rollback, and commit.

The Markdown report is non-destructive. It reads the manifest and ignored local state only. It does not clone projects, change sync sessions, create snapshots, run validation commands, stage files, or commit files. Repository paths are shown relative to the repository when possible; paths outside the repository are reduced to `outside repository: <file>` so copyable evidence does not expose local machine directories.

## Safety Checks

Before publishing, verify the public repository does not contain:

- Secrets, tokens, private keys, internal hostnames, or customer data.
- VM disks, snapshots, logs, ISO files, downloaded archives, or local tool binaries.
- `adp-workspace.state.json` or other ignored local runtime state.
- Private maintainer notes, roadmaps, protocols, or local maintainer repository paths.

If a release needs destructive operations, credential changes, legal decisions, account changes, or cost-bearing infrastructure, stop and get explicit owner approval first.

## Version Tags

The project currently records public changes in the changelog by date. When versioned release tags are introduced, this process should be extended with tag naming, release-note, and rollback expectations.
