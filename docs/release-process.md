# Release Process

[简体中文](zh-CN/release-process.md) | English

This process describes how ADP-OS changes should move from local work to a public update. It is intentionally lightweight: ADP-OS has a `v1.0.0` release tag, but public updates still need validation, evidence, safety checks, and repository-owner authorization before publication.

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
   adpos workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
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

## Versioned Releases

ADP-OS uses [Semantic Versioning](https://semver.org/) (`MAJOR.MINOR.PATCH`):

- **MAJOR**: breaking changes (e.g., VMware → Hyper-V switch, public API renames).
- **MINOR**: new features (new commands, new runtime profiles, localization expansion, MCP server tools).
- **PATCH**: bug fixes, documentation corrections, non-breaking diagnostic improvements.

The current version is recorded in the `VERSION` file at the repository root. The changelog is organized by release version, then by date within the version.

### Publishing a Release

1. Ensure the `VERSION` file contains the correct SemVer version.
2. Ensure `CHANGELOG.md` and `CHANGELOG.zh-CN.md` are updated for the release.
3. Run the full validation suite:
   ```powershell
   .\tests\validate.ps1
   ```
4. Run the release script:
   ```powershell
   .\scripts\release.ps1
   ```
   This validates the repository, confirms the tag name, and pushes a `v<version>` Git tag.
   Use `-DryRun` to preview without tagging:
   ```powershell
   .\scripts\release.ps1 -DryRun
   ```
5. Pushing the `v<version>` tag triggers the GitHub Actions release workflow (`.github/workflows/release.yml`), which:
   - Runs the full validation suite on `windows-latest`.
   - Creates a GitHub Release with the changelog as release notes.
6. Monitor the workflow at `https://github.com/karoc/ai-dev-platform/actions`.

### After a Release

- Bump the version in `VERSION` for the next development cycle.
- Add a new version header in `CHANGELOG.md` and `CHANGELOG.zh-CN.md` for upcoming changes.
