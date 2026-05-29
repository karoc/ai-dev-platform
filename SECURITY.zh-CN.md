# 安全策略

简体中文 | [English](SECURITY.md)

AI Dev Platform OS 当前是本地开发 MVP。它会创建本地 VMware 运行时，并同步本地工作区，用于单用户 AI 辅助开发工作流。

## 支持范围

当前安全说明适用于 `main` 分支和 Windows VMware MVP。

项目尚未发布版本化 release。在引入 release 前，请使用最新 `main` 分支获取安全修复。

## 本地开发安全模型

ADP-OS 面向可信工作站上的本地单用户开发场景。

MVP 默认行为包括：

- 默认运行时用户 `adp`。
- 默认 bootstrap 密码 `adp`，用于本地自动 sudo provisioning。
- 从 Windows host 通过 SSH 访问本地 VMware VM。
- 使用 Mutagen 在 host 工作区和 guest 工作区之间同步文件。
- 使用带静态 guest IP 的 VMware NAT 网络。

这些默认值用于让本地 bootstrap 可复现。它们不适合暴露网络、共享环境、生产环境或多租户环境。

## 不要暴露默认运行时

在审查并修改以下内容前，不要把 ADP-OS VM 直接暴露给不可信网络：

- 运行时用户凭据。
- SSH 访问和 authorized keys。
- VMware NAT 和端口转发规则。
- 防火墙策略。
- 工作区同步路径。
- 同步工作区中的项目 secrets。

## 密钥和本地产物

不要提交：

- 私有 SSH keys。
- API tokens、密码或云凭据。
- 本地 VM 磁盘、快照、日志、ISO 镜像或下载的工具二进制。
- 浏览器缓存或生成的浏览器测试报告。
- 私有维护上下文。

仓库 ignore 规则是防御措施，但不能替代提交前审查。

## 报告漏洞

如果你认为发现了安全问题，请不要在公开 issue 中包含利用细节或 secrets。

请通过 GitHub 联系渠道私下报告给仓库所有者，或创建一个不含敏感细节的最小公开 issue，请求私下披露路径。

请包含：

- 问题的简要描述。
- 受影响的命令、脚本或配置。
- Host OS 和 ADP-OS commit。
- 是否涉及凭据、host 文件、VM 文件或网络暴露。
- 不包含真实 secrets 的最小复现步骤。

## 安全修复处理

安全修复应该：

- 尽量减少对本地用户的行为惊讶。
- 尽可能保持本地 bootstrap 可复现。
- 当安全假设或用户操作要求变化时更新文档。
- 避免在 commits 或 issues 中发布 secrets、私有本地路径或利用 payload。
