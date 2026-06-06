# Documentation

[简体中文](zh-CN/README.md) | English

This documentation covers how to install, operate, configure, and understand ADP-OS.

[简体中文文档](zh-CN/README.md)

## Start Here

- **[Getting Started](getting-started.md)** ([简体中文](zh-CN/getting-started.md)): first-time setup walkthrough — from nothing to a running development VM in ~30 minutes.
- **[Copilot SDK Integration](copilot-sdk-integration.md)** ([简体中文](zh-CN/copilot-sdk-integration.md)): load ADP-OS tools into the GitHub Copilot Agent SDK. Python and TypeScript quick-start examples, tool reference, and permission patterns.
- **[Deer-Flow Integration](deer-flow-integration.md)** ([简体中文](zh-CN/deer-flow-integration.md)): configure ADP-OS as an MCP server in ByteDance/deer-flow (70K⭐). Quick-start guide, 18-tool reference, workflow examples, and current limitations.
- **[Deer-Flow VM Backend](integrations/deer-flow-backend.md)** ([简体中文](zh-CN/integrations/deer-flow-backend.md)): use ADP-OS as deer-flow's hardware-VM sandbox backend. MCP server and Direct Adapter configuration, VM pool pre-warming, end-to-end flow.
- [ADP-OS and Docker](positioning.md): how ADP-OS relates to Docker and when to use each.
- [Operations](operations.md): day-to-day runtime commands and workflows.
- [Configuration](configuration.md): platform, topology, sync, and local override configuration.
- [Workspaces](workspaces.md): where to put target projects and how to dogfood ADP-OS safely.
- [Capabilities](capabilities.md): supported and planned runtime carriers, host adapters, and inner environment boundaries.
- [Roadmap](roadmap.md): public product direction, current stage, and future workspace, agent, and runtime expansion tracks.
- [Release Readiness](release-readiness.md): release decision policy, task governance, and maintainer checklist.
- [Release Process](release-process.md): validation, release evidence, safety checks, and publication boundaries.
- [Contributor Workflows](contributor-workflows.md): task templates, maintainer review ritual, and pull request expectations.
- [Troubleshooting](troubleshooting.md): symptom-to-command guidance for diagnostics, safe previews, and support escalation.
- [Networking](networking.md): static VMware NAT networking and troubleshooting.
- [Browser Testing](browser-testing.md): headless frontend browser acceptance testing.
- [Evidence Chain](evidence.md): tamper-evident SHA-256 hash chains for audits.

## Community

- [Discord Setup Guide](discord-setup.md) ([简体中文](zh-CN/discord-setup.md)): channel structure, roles, setup instructions, and community guidelines for the ADP-OS Discord server.
- [10-Minute Survival Value Demo](demo-script.md): presenter script with pre-demo checklist, 6-phase flow, and troubleshooting guide.

## Architecture

- [Architecture](architecture.md): control plane, runtime fabric, bootstrap, sync, and snapshots.

## Project

- [Contributing](../CONTRIBUTING.md): development requirements, validation, and commit hygiene.
- [Support](../SUPPORT.md): where to ask for help, what diagnostics to include, and what is out of scope.
- [Security](../SECURITY.md): local development security model and vulnerability reporting.
- [Changelog](../CHANGELOG.md): notable public changes.
- [Historical Implementation Brief](../build.md): original product and architecture intent, retained as historical context.
