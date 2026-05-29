## Summary

- 

## Validation

- [ ] `.\tests\validate.ps1` passes, or this PR explains why only targeted validation was run.
- [ ] `.\tests\validate.ps1 -Quick` passes for local iteration when the full gate is not run.
- [ ] `.\test-integration.ps1` passes when relevant.
- [ ] `.\deploy-check.ps1` passes when relevant.
- [ ] `.\cli\adp.ps1 doctor` passes when relevant.

## Release Readiness

- [ ] The workspace task shape is listed, or this PR explains why no workspace task applies.
- [ ] `.\cli\adp.ps1 workspace report -Markdown` release evidence is included when this affects workflows, runtimes, validation, docs, or release readiness.
- [ ] Stale-task remediation items are resolved or explicitly called out.
- [ ] High-risk agent work has a ready snapshot gate or an explicit maintainer waiver.

## Documentation

- [ ] Public docs were updated for user-facing behavior changes.
- [ ] `README.md` and `README.zh-CN.md` were kept in sync when README content changed.
- [ ] Chinese documentation links preserve Chinese context when translated equivalents exist.

## Safety

- [ ] No secrets, private keys, tokens, VM disks, ISO images, logs, local tool binaries, or private maintainer files are included.
- [ ] No destructive VM, workspace, snapshot, or host filesystem operation is required by this change.
