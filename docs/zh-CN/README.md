# 文档

简体中文 | [English](../README.md)

本文档库覆盖 ADP-OS 的安装、日常操作、配置、网络、浏览器验收测试和架构说明。

## 从这里开始

- **[快速入门](getting-started.md)**：首次设置指南——从零到运行中的开发 VM，约 30-70 分钟。
- **[Copilot SDK 集成指南](copilot-sdk-integration.md)**：在 GitHub Copilot Agent SDK 中加载 ADP-OS 工具。含 Python/TypeScript 快速开始示例、工具参考和权限模式。
- **[Deer-Flow 集成指南](deer-flow-integration.md)**：在 ByteDance/deer-flow（70K⭐）中将 ADP-OS 配置为 MCP 服务器。快速开始指南、26 工具参考、工作流示例及当前限制。
- **[Deer-Flow VM 后端](integrations/deer-flow-backend.md)**：将 ADP-OS 用作 deer-flow 的硬件 VM 沙箱后端。MCP 服务器和直接适配器配置、VM 池预暖、端到端流程。
- [ADP-OS 与 Docker](positioning.md)：ADP-OS 与 Docker 的关系，以及各自适用场景。
- [操作指南](operations.md)：日常运行时命令和工作流。
- [配置说明](configuration.md)：平台、拓扑、同步和本地覆盖配置。
- [工作区](workspaces.md)：目标项目应该放在哪里，以及如何安全地 dogfood ADP-OS。
- [能力边界](capabilities.md)：已支持和计划中的 runtime carriers、host adapters，以及内层环境边界。
- [路线图](roadmap.md)：公开产品方向、当前阶段，以及未来 workspace、agent 和 runtime expansion 方向。
- [发布就绪](release-readiness.md)：release decision policy、task governance 和维护者 checklist。
- [发布流程](release-process.md)：validation、release evidence、safety checks 和 publication boundaries。
- [贡献者工作流](contributor-workflows.md)：task templates、维护者 review ritual 和 pull request expectations。
- [排障](troubleshooting.md)：按症状查命令的 diagnostics、安全预览和支持升级指南。
- [网络说明](networking.md)：静态 VMware NAT 网络和排障。
- [浏览器测试](browser-testing.md)：frontend 运行时的 headless 浏览器验收测试。
- [证据链](evidence.md)：防篡改的 SHA-256 哈希链，用于审计。
- [生存验证](survival-validation.md)：首批用户验证流程、10 分钟 demo 准备、观察清单、反馈表、失败分类和决策标准。

## 社区

- [GitHub Issues](https://github.com/karoc/ai-dev-platform/issues/new/choose)：安装帮助、使用问题、可复现 bug 和功能请求。
- [Discord 搭建计划](discord-setup.md)：计划中的频道结构、角色、设置说明和社区准则。发布真实邀请链接前，Discord 不是当前可用的支持渠道。
- [10 分钟生存价值演示](demo-script.md)：演示脚本，包含前置准备清单、6 阶段流程和故障排除指南。

## 架构

- [架构说明](architecture.md)：控制平面、运行时 fabric、bootstrap、同步和快照模型。

## 项目

- [贡献指南](../../CONTRIBUTING.zh-CN.md)：开发要求、验证和提交规范。
- [支持说明](../../SUPPORT.zh-CN.md)：如何寻求帮助、应提供哪些 diagnostics，以及哪些内容不在范围内。
- [安全策略](../../SECURITY.zh-CN.md)：本地开发安全模型和漏洞报告方式。
- [变更日志](../../CHANGELOG.zh-CN.md)：重要公开变更记录。
- [历史实现简报](../../build.zh-CN.md)：作为历史上下文保留的原始产品和架构意图。
