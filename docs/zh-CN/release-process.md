# 发布流程

简体中文 | [English](../release-process.md)

本文描述 ADP-OS 变更如何从本地工作进入公开更新。当前项目尚未发布版本化 release tag，因此流程有意保持轻量。

## 发布边界

一次 release 或公开更新应具备：

- 聚焦的 change set。
- 仓库验证通过。
- 用户可见行为变化已更新公开文档。
- 当已有翻译内容时，英文和简体中文文档同步更新。
- 当变更影响 workflow、runtime、validation、documentation 或 release readiness 时，提供 workspace release evidence。
- 最后检查 local artifacts、credentials、generated state 和 private maintainer material。

## 维护者流程

提交、推送或发布公开更新前，按此顺序处理：

1. 使用 `git status --short --branch` 和 `git diff --stat` 检查 working tree。
2. 本地迭代时先运行快速验证：

   ```powershell
   .\tests\validate.ps1 -Quick
   ```

3. 发布前运行完整的非破坏性验证 gate：

   ```powershell
   .\tests\validate.ps1
   ```

4. 当变更影响 workflow、runtime、validation、docs 或 release readiness 时，生成 release evidence：

   ```powershell
   .\cli\adp.ps1 workspace report -Markdown -ManifestPath configs\workspace.recipes.example.json
   ```

   `configs\workspace.recipes.example.json` 是示例 manifest。真实 release decision 应使用描述当前 task bundle 的 manifest。

5. 在把变更视为可发布前，解决所有 `release blocked`、`validation required`、`review required` 或 `governance incomplete` decision。
6. 通过共享验证 gate 确认文档链接和语言上下文。
7. 确认没有包含 local state、logs、VM disks、ISO files、downloaded tools、credentials 或 private maintainer files。
8. 只有 validation、documentation、evidence 和 safety checks 都完成后才 commit。
9. 只有 repository owner 授权发布后才 push 或 publish。

## 证据预期

当变更影响 workflow 或 release readiness 时，把 Markdown report 输出附加或粘贴到 pull request、release note 或 maintainer handoff。

Evidence 应显示：

- Release decision。
- Blockers、validation-required tasks、review-required tasks 和 release candidates。
- Governance gaps。
- 相关 task 的 validation status。
- 高风险 agent work 的 snapshot gates。
- Review、rollback 和 commit 的 handoff commands。

Markdown report 是非破坏性的。它只读取 manifest 和被忽略的本地 state。它不会 clone projects、修改 sync sessions、创建 snapshots、运行 validation commands、stage 文件或 commit 文件。仓库内路径会尽量显示为仓库相对路径；仓库外路径会缩减成 `outside repository: <file>`，避免可复制 evidence 暴露本机目录。

## 安全检查

发布前，确认公开仓库不包含：

- Secrets、tokens、private keys、internal hostnames 或 customer data。
- VM disks、snapshots、logs、ISO files、downloaded archives 或 local tool binaries。
- `adp-workspace.state.json` 或其他被忽略的本地 runtime state。
- Private maintainer notes、roadmaps、protocols 或本地维护仓库路径。

如果一次 release 需要破坏性操作、credential changes、legal decisions、account changes 或 cost-bearing infrastructure，应先停止并取得 owner 明确授权。

## 版本标签

当前项目仍按日期在 changelog 中记录公开变更。引入版本化 release tag 后，应扩展本流程，补充 tag naming、release-note 和 rollback expectations。
