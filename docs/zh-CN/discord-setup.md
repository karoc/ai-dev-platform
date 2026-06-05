# Discord 社区搭建指南

> **状态**: 准备启动。所有前置条件已就位 — issue 模板、CONTRIBUTING.md、README 引用均已完善。

## 服务器邀请链接（创建服务器后更新）

<!-- 创建 Discord 服务器后，请将本节替换为实际的邀请链接。 -->

> [!IMPORTANT]
> Discord 服务器**尚未创建**。README badge 目前链接到此搭建指南。
>
> **创建服务器后：**
> 1. 将本节替换为邀请链接：`https://discord.gg/YOUR_INVITE_CODE`
> 2. 更新 [README.md](../README.md)（第 7 行）和 [README.zh-CN.md](../README.zh-CN.md)（第 7 行）中的 badge 链接：
>    - 将 `(docs/discord-setup.md)` 改为 `(https://discord.gg/YOUR_INVITE_CODE)`
>    - 删除关于替换链接的 HTML 注释
> 3. 更新两个 README 的社区部分中的 Discord 链接

## 为什么选择 Discord？

ADP-OS 是面向 Windows-first AI agent 开发的开发者工具。Discord 是 AI/开发者社区的聚集地——它提供：

- **实时帮助**：安装和配置问题快速得到解答。
- **开发者协作**：贡献者讨论功能、PR 和架构。
- **发布公告**：用户获取新版本通知。
- **社区建设**：用户分享他们的配置、脚本和工作流。

## 推荐频道结构

```
📢 信息
├── #welcome          — 服务器规则、入门链接、角色选择
├── #announcements    — 发布、破坏性变更、维护通知
└── #showcase         — 社区项目、配置和工作流展示

💬 社区
├── #general          — ADP-OS 和 AI 开发工具开放讨论
├── #help             — 安装帮助、故障排查、使用问题
└── #ideas            — 功能建议、路线图反馈、头脑风暴

🔧 开发
├── #dev              — 贡献者讨论、架构、PR 协调
├── #ci               — CI/CD 状态、测试结果（仅 bot，成员只读）
└── #mcp              — MCP 服务器开发、SDK 使用、agent 集成

📦 发布
└── #releases         — GitHub 发布通知、changelog 亮点
```

### 频道说明

#### #welcome
**用途**：第一接触点。新成员到达此处。
**内容**：置顶消息包含：
- [README](https://github.com/karoc/ai-dev-platform#readme) 链接
- [快速入门](getting-started.md) 链接
- [贡献指南](../../CONTRIBUTING.zh-CN.md) 链接
- 服务器规则（尊重他人、禁止垃圾信息、求助问题发在 #help）
- 角色选择（见下方角色部分）

#### #announcements
**用途**：官方项目公告。
**权限**：仅维护者可发帖。
**内容**：新版本、破坏性变更、安全通知、社区活动。

#### #showcase
**用途**：社区成员分享用 ADP-OS 构建的作品。
**内容**：工作空间配置、agent 工作流、自定义 bootstrap 脚本、MCP 集成。

#### #general
**用途**：开放讨论空间。
**内容**：AI 开发工具、ADP-OS 使用体验、一般闲聊。

#### #help
**用途**：安装和使用支持。
**指南**：
- 提问前先搜索——查看[故障排查指南](troubleshooting.md)和置顶 FAQ。
- 包含你的环境信息：Windows 版本、PowerShell 版本、VMware 版本。
- 安装问题附上 `adp doctor` 输出。
- 持续性问题使用[安装帮助 issue 模板](https://github.com/karoc/ai-dev-platform/issues/new?template=install_help.yml)。

#### #ideas
**用途**：功能请求和路线图讨论。
**指南**：具体提案请同时发起 [Feature Request issue](https://github.com/karoc/ai-dev-platform/issues/new?template=feature_request.yml)。

#### #dev
**用途**：贡献者协作。
**内容**：PR 审查、架构决策、实现讨论。

#### #ci
**用途**：自动化 CI/CD 状态。
**设置**：GitHub webhook → Discord bot 发布工作流运行结果。
**权限**：成员只读；bot 有写入权限。

#### #mcp
**用途**：MCP 服务器和 agent 集成讨论。
**内容**：SDK 使用、工具开发、agent 配置、Claude/Copilot/Cursor 集成模式。

#### #releases
**用途**：发布通知。
**设置**：GitHub webhook → Discord bot 发布新版本详情。
**权限**：成员只读；bot 有写入权限。

## 角色

| 角色 | 适用对象 | 权限 |
|---|---|---|
| @Admin | 项目所有者 | 完整服务器管理 |
| @Maintainer | 可信贡献者 | 管理消息、置顶、审核 |
| @Contributor | 定期贡献者 | 在 #dev 发帖、提交 PR |
| @Member | 接受规则的所有人 | 在社区频道发帖 |
| @Bot | GitHub 集成 bot | 在 #ci 和 #releases 发帖 |

## 如何创建 Discord 服务器

1. 访问 [discord.com](https://discord.com) 并登录。
2. 点击左侧边栏的 `+` 按钮 → 「亲自创建」→ 「仅供我和朋友使用」或「供俱乐部或社区使用」。
3. 名称：`ADP-OS`（或 `AI Dev Platform OS`）。
4. 上传服务器图标（如有项目 logo 可用）。
5. 按顺序创建上述列出的频道。
6. 将 **Welcome** 频道设为默认登录频道（服务器设置 → 概览 → 默认频道）。
7. 配置**规则筛选**（服务器设置 → 安全设置 → 规则筛选），内容：
   - 保持尊重和建设性。
   - 求助问题发在 #help。
   - 禁止垃圾信息、广告或 NSFW 内容。
   - 遵循项目的[安全政策](../../SECURITY.zh-CN.md)——不要发布 secrets、tokens 或私钥。
8. 将 **@Member** 设为默认角色，权限为仅在社区频道读写。
9. 将 #announcements、#ci、#releases 限制为 @Admin/@Maintainer/@Bot 发帖权限。
10. 启用**社区服务器**功能（服务器设置 → 启用社区）以获得更好的发现和审核工具。

## GitHub 集成

### CI 通知发到 #ci

1. 在你的 Discord 服务器中，为 #ci 创建 webhook（频道设置 → 集成 → Webhooks）。
2. 复制 webhook URL。
3. 添加 `DISCORD_CI_WEBHOOK` 为 GitHub Actions secret。
4. 在 `.github/workflows/ci.yml` 中添加通知步骤：

```yaml
- name: Notify Discord
  if: always()
  uses: sarisia/actions-status-discord@v1
  with:
    webhook: ${{ secrets.DISCORD_CI_WEBHOOK }}
    title: "CI ${{ job.status }}"
    description: "Commit ${{ github.sha }} on ${{ github.ref }}"
```

### 发布通知发到 #releases

1. 为 #releases 创建单独的 webhook。
2. 添加 `DISCORD_RELEASE_WEBHOOK` 为 GitHub Actions secret。
3. 在 `.github/workflows/release.yml` 中，发布成功时发送通知。

## 社区准则

### 给成员

1. **友好包容**——ADP-OS 欢迎初学者和专家。
2. **保持主题**——频道讨论应与其用途相关。
3. **使用讨论串**——在 #help 和 #dev 中的深入讨论请使用 Discord 讨论串，保持频道整洁。
4. **先搜索**——提问前检查已有讨论串、故障排查指南和 GitHub issues。
5. **不泄露秘密**——永远不要发布 tokens、私钥、密码或 VM 磁盘内容。

### 给贡献者

1. **先讨论再写代码**——进行大变更前发起 issue 或在 #dev 发起讨论串。
2. **遵循 PR 流程**——参见 [CONTRIBUTING.zh-CN.md](../../CONTRIBUTING.zh-CN.md)。
3. **认真审查**——关注正确性、安全性和可维护性。

### 给维护者

1. **48 小时内响应**——及时确认 issues 和 PR。
2. **保持 #announcements 更新**——发布版本说明和破坏性变更。
3. **公正审核**——违规行为先警告，再禁言，重复违规则封禁。

## 启动时机

Discord 服务器应在以下条件满足后创建：

- [x] 所有 issue 模板就位（Bug Report、Feature Request、安装帮助、使用问题）
- [x] CONTRIBUTING.md 包含完整的开发环境搭建说明
- [x] README 和文档中引用了 Discord 服务器
- [ ] GitHub Discussions 已启用（推荐——在仓库 Settings → General → Features 中启用）

**推荐启动时机**：与首次公开发布公告同步。GitHub Discussions 应在启动前启用，作为 Discord 旁的轻量级异步讨论空间。

## 已考虑的替代方案

- **仅 GitHub Discussions**：适合异步，但实时帮助需要聊天平台。Discord + GitHub Discussions 互补。
- **Slack**：开发者友好，但在 AI/开源社区中不如 Discord 流行。Discord 的 bot 集成和社区发现更优。
- **Matrix/Element**：开放协议，但目标受众中用户基数较小。

选择 Discord 是因为它是 AI 开发者工具的主流社区平台（Claude、Cursor、Copilot 以及大多数开源 AI 项目都使用 Discord）。
