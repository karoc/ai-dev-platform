## Summary

- 

## Validation

- [ ] PowerShell parser checks pass.
- [ ] JSON config parsing checks pass.
- [ ] Bootstrap shell syntax checks pass.
- [ ] `.\test-integration.ps1` passes when relevant.
- [ ] `.\deploy-check.ps1` passes when relevant.
- [ ] `.\cli\adp.ps1 doctor` passes when relevant.

## Documentation

- [ ] Public docs were updated for user-facing behavior changes.
- [ ] `README.md` and `README.zh-CN.md` were kept in sync when README content changed.
- [ ] Chinese documentation links preserve Chinese context when translated equivalents exist.

## Safety

- [ ] No secrets, private keys, tokens, VM disks, ISO images, logs, local tool binaries, or private maintainer files are included.
- [ ] No destructive VM, workspace, snapshot, or host filesystem operation is required by this change.
