# Discord Community Setup Guide

> This is a **planning document** for the ADP-OS Discord community. The server has not been created yet — this guide provides the blueprint for when we launch.

## Why Discord?

ADP-OS is a developer tool for Windows-first AI agent development. Discord is where AI/developer communities live — it enables:

- **Real-time help**: Installation and setup questions answered quickly.
- **Developer collaboration**: Contributors discuss features, PRs, and architecture.
- **Release announcements**: Users get notified of new versions.
- **Community building**: Users share their setups, scripts, and workflows.

## Recommended Channel Structure

```
📢 INFORMATION
├── #welcome          — server rules, getting-started links, role selection
├── #announcements    — releases, breaking changes, maintenance notices
└── #showcase         — community projects, setups, and workflows

💬 COMMUNITY
├── #general          — open discussion about ADP-OS and AI dev tooling
├── #help             — installation help, troubleshooting, usage questions
└── #ideas            — feature suggestions, roadmap feedback, brainstorming

🔧 DEVELOPMENT
├── #dev              — contributor discussion, architecture, PR coordination
├── #ci               — CI/CD status, test results (bot-only, read-only for members)
└── #mcp              — MCP server development, SDK usage, agent integration

📦 RELEASES
└── #releases         — GitHub release notifications, changelog highlights
```

### Channel Descriptions

#### #welcome
**Purpose**: First point of contact. New members land here.
**Content**: Pinned message with:
- Link to [README](https://github.com/karoc/ai-dev-platform#readme)
- Link to [Getting Started](getting-started.md)
- Link to [Contributing](../CONTRIBUTING.md)
- Server rules (be respectful, no spam, keep help in #help)
- Role selection (see Roles section below)

#### #announcements
**Purpose**: Official project announcements.
**Permissions**: Only maintainers can post.
**Content**: New releases, breaking changes, security notices, community events.

#### #showcase
**Purpose**: Community members share what they've built with ADP-OS.
**Content**: Workspace setups, agent workflows, custom bootstrap scripts, MCP integrations.

#### #general
**Purpose**: Open discussion space.
**Content**: AI development tooling, ADP-OS experience, general chat.

#### #help
**Purpose**: Installation and usage support.
**Guidelines**:
- Search before asking — check the [troubleshooting guide](troubleshooting.md) and pinned FAQs.
- Include your environment: Windows version, PowerShell version, VMware edition.
- Paste `adp doctor` output for installation issues.
- Use the [Installation Help issue template](https://github.com/karoc/ai-dev-platform/issues/new?template=install_help.yml) for persistent problems.

#### #ideas
**Purpose**: Feature requests and roadmap discussion.
**Guidelines**: For concrete proposals, also open a [Feature Request issue](https://github.com/karoc/ai-dev-platform/issues/new?template=feature_request.yml).

#### #dev
**Purpose**: Contributor coordination.
**Content**: PR reviews, architecture decisions, implementation discussions.

#### #ci
**Purpose**: Automated CI/CD status.
**Setup**: GitHub webhook → Discord bot posts workflow run results.
**Permissions**: Read-only for members; bot has write access.

#### #mcp
**Purpose**: MCP server and agent integration discussion.
**Content**: SDK usage, tool development, agent configuration, Claude/Copilot/Cursor integration patterns.

#### #releases
**Purpose**: Release notifications.
**Setup**: GitHub webhook → Discord bot posts new release details.
**Permissions**: Read-only for members; bot has write access.

## Roles

| Role | Who gets it | Permissions |
|---|---|---|
| @Admin | Project owner | Full server management |
| @Maintainer | Trusted contributors | Manage messages, pin, moderate |
| @Contributor | Regular contributors | Post in #dev, submit PRs |
| @Member | Everyone who accepts rules | Post in community channels |
| @Bot | GitHub integration bot | Post in #ci and #releases |

## How to Create the Discord Server

1. Go to [discord.com](https://discord.com) and sign in.
2. Click the `+` button in the left sidebar → "Create My Own" → "For a club or community".
3. Name: `ADP-OS` (or `AI Dev Platform OS`).
4. Upload a server icon (use the project logo if available).
5. Create the channels listed above in order.
6. Set up the **Welcome** channel as the default landing channel (Server Settings → Overview → Default Channel).
7. Configure **Rules Screening** (Server Settings → Safety Setup → Rules Screening) with:
   - Be respectful and constructive.
   - Keep help questions in #help.
   - No spam, advertising, or NSFW content.
   - Follow the project's [Security policy](../SECURITY.md) — do not post secrets, tokens, or private keys.
8. Set up **@Member** as the default role with permissions to read/write in community channels only.
9. Restrict #announcements, #ci, and #releases to @Admin/@Maintainer/@Bot post permissions.
10. Enable **Community Server** features (Server Settings → Enable Community) for better discovery and moderation tools.

## GitHub Integration

### CI Notifications to #ci

1. In your Discord server, create a webhook for #ci (Channel Settings → Integrations → Webhooks).
2. Copy the webhook URL.
3. Add `DISCORD_CI_WEBHOOK` as a GitHub Actions secret.
4. In `.github/workflows/ci.yml`, add a notification step:

```yaml
- name: Notify Discord
  if: always()
  uses: sarisia/actions-status-discord@v1
  with:
    webhook: ${{ secrets.DISCORD_CI_WEBHOOK }}
    title: "CI ${{ job.status }}"
    description: "Commit ${{ github.sha }} on ${{ github.ref }}"
```

### Release Notifications to #releases

1. Create a separate webhook for #releases.
2. Add `DISCORD_RELEASE_WEBHOOK` as a GitHub Actions secret.
3. In `.github/workflows/release.yml`, notify on successful release.

## Community Guidelines

### For Members

1. **Be welcoming** — ADP-OS welcomes beginners and experts alike.
2. **Stay on topic** — keep channel discussions relevant to their purpose.
3. **Use threads** — for deep discussions in #help and #dev, use Discord threads to keep channels clean.
4. **Search first** — check existing threads, the troubleshooting guide, and GitHub issues before asking.
5. **No secrets** — never post tokens, private keys, passwords, or VM disk contents.

### For Contributors

1. **Discuss before coding** — open an issue or start a thread in #dev before large changes.
2. **Follow the PR process** — see [CONTRIBUTING.md](../CONTRIBUTING.md).
3. **Review with care** — focus on correctness, security, and maintainability.

### For Maintainers

1. **Respond within 48 hours** — acknowledge issues and PRs promptly.
2. **Keep #announcements current** — post release notes and breaking changes.
3. **Moderate fairly** — warn first, then time out, then ban for repeated violations.

## When to Launch

The Discord server should be created when:

- [ ] All issue templates are in place (Bug Report, Feature Request, Installation Help, Usage Question)
- [ ] CONTRIBUTING.md is complete with dev environment setup
- [ ] README and docs reference the Discord server
- [ ] GitHub Discussions is enabled (optional, but recommended)

**Recommended launch timing**: Together with the first public release announcement.

## Alternatives Considered

- **GitHub Discussions only**: Good for async, but real-time help needs a chat platform. Discord + GitHub Discussions complement each other.
- **Slack**: Developer-friendly but less popular in the AI/OSS community. Discord has better bot integration and community discovery.
- **Matrix/Element**: Open protocol, but smaller user base in the target audience.

Discord was chosen because it is the dominant community platform for AI developer tools (Claude, Cursor, Copilot, and most OSS AI projects use Discord).
