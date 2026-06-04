# Demo Video Plan

> **Status**: Planning only. Assessment complete — video IS recommended but should be recorded after the Discord server and issue templates are live. This document provides the script and storyboard for when recording begins.

## Assessment: Is a Demo Video Needed?

**Yes.** Here's why:

1. **ADP-OS has a high setup bar** — users need Windows + VMware + WSL + Ubuntu ISO + Mutagen. A video showing the full flow from `git clone` to `adp up agent` operating would:
   - Prove the tool actually works end-to-end
   - Reduce installation fear ("this looks complicated, does it even work?")
   - Serve as a visual getting-started guide

2. **Competitors have demo videos** — microsandbox, Daytona, and E2B all have short demo GIFs or videos on their READMEs. ADP-OS currently has only text and ASCII screenshots.

3. **Agent-native MCP is hard to visualize from text** — showing an agent connecting to the ADP-OS MCP server and managing sandboxes in real-time is persuasive.

4. **Low cost, high impact** — a 3-5 minute terminal recording requires no expensive production. OBS Studio is free. A clear script + clean terminal is all that's needed.

### When to Record

- **Not yet** — record after the Discord server and community infrastructure are live. The video should end with "Join us on Discord" and show where to find help.
- **Recommended timing**: Together with the first v1.0 public announcement or README showcase push.

## Video Structure

**Duration**: 4-5 minutes
**Style**: Terminal screen recording with voiceover or text overlays. Clean white-on-black terminal. No face cam.

### Part 1: What Is ADP-OS? (30 seconds)

> Text overlay / voiceover introducing the project.

"ADP-OS is a self-hosted, programmable code execution sandbox for AI agent development on Windows. It provisions isolated Linux runtimes with VMware, syncs your workspace, and exposes everything through an MCP server that AI agents can use directly."

Screen: Show README header and key features bullet list briefly.

### Part 2: First-Time Setup (90 seconds)

```
Shot 1: git clone and cd
Shot 2: adp doctor -FirstRun — all checks pass (7/7)
Shot 3: Download Ubuntu ISO (fast-forward)
Shot 4: adp network configure-local -Plan → -Apply
```

Key commands shown:
```powershell
git clone git@github.com:karoc/ai-dev-platform.git
cd ai-dev-platform
.\cli\adp.ps1 doctor -FirstRun
.\cli\adp.ps1 network configure-local -Apply
```

### Part 3: Creating a Runtime (90 seconds)

```
Shot 1: adp up agent -Plan (show the plan output)
Shot 2: adp up agent -IsoPath D:\path\to\ubuntu.iso (fast-forward through VM creation)
Shot 3: adp status agent (show SSH reachable, sync watching)
Shot 4: adp doctor (show all checks green)
```

Key commands shown:
```powershell
.\cli\adp.ps1 up agent -IsoPath D:\Download\ubuntu-26.04-live-server-amd64.iso -Plan
.\cli\adp.ps1 up agent -IsoPath D:\Download\ubuntu-26.04-live-server-amd64.iso
.\cli\adp.ps1 status agent
.\cli\adp.ps1 doctor
```

### Part 4: Workspace Sync (45 seconds)

```
Shot 1: Create a small project in the workspace directory
Shot 2: adp sync status (show bidirectional sync active)
Shot 3: SSH into the VM and show the synced files
Shot 4: Make a change on the VM, show it appears on Windows
```

Key commands shown:
```powershell
echo "Hello from Windows" > $env:USERPROFILE\adp-workspaces\agent\hello.txt
.\cli\adp.ps1 sync status
ssh adp@192.168.242.135 "cat /home/adp/workspace/hello.txt"
```

### Part 5: MCP Server — Agent-Native Sandbox Control (60 seconds)

```
Shot 1: Show the MCP server running
Shot 2: Configure Claude Desktop or Hermes with the MCP config
Shot 3: Ask Claude to check ADP-OS status
Shot 4: Agent lists runtimes, checks doctor, reports health
```

Key config shown:
```json
{
  "mcpServers": {
    "adp-os": {
      "command": "python3",
      "args": ["cli/mcp/server.py"],
      "env": { "ADP_HOME": "D:\\Dev\\ai-dev-platform" }
    }
  }
}
```

Agent interaction shown:
```
User: What's the status of my ADP-OS runtimes?
Agent: [calls adp_status] → agent runtime is running, SSH reachable at 192.168.242.135, sync healthy.
```

### Part 6: Community & Next Steps (30 seconds)

```
Shot 1: Show the GitHub repo with issue templates
Shot 2: Show Discord server invite
Shot 3: Show CONTRIBUTING.md
```

"ADP-OS is open source under MIT. Join us on Discord for help, check out the contributing guide to get involved, and star the repo if you find it useful."

## Shot List (Storyboard)

| # | Duration | Screen Content | Audio / Overlay |
|---|---|---|---|
| 1 | 15s | README hero section | "ADP-OS: self-hosted code execution sandbox for AI agents on Windows" |
| 2 | 10s | `git clone` + `cd` | "Clone the repo and enter the directory" |
| 3 | 20s | `adp doctor -FirstRun` output — 7/7 passing | "Run first-time diagnostics. All dependencies check out." |
| 4 | 5s | ISO download in browser (fast-forward) | "Download Ubuntu Server 26.04 ISO" |
| 5 | 15s | `adp network configure-local -Apply` | "Configure local networking to match your VMware NAT" |
| 6 | 20s | `adp up agent -Plan` → preview output | "Preview the VM creation plan" |
| 7 | 5s | `adp up agent` — fast-forward through VM creation (~10 min compressed to 5s with text: "~10 minutes later") | "Create the agent runtime. This takes about 10 minutes for Ubuntu autoinstall." |
| 8 | 15s | `adp status agent` — running, connected, sync watching | "Agent runtime is up. SSH reachable, sync active." |
| 9 | 15s | `adp doctor` — all green | "Full diagnostics confirm everything is healthy" |
| 10 | 15s | Create file → `sync status` → SSH → file visible on VM | "Workspace sync is bidirectional. Changes propagate instantly." |
| 11 | 15s | Start MCP server + Claude Desktop config | "ADP-OS exposes an MCP server with 18 tools for AI agents" |
| 12 | 30s | Claude Desktop calling ADP-OS tools | "Ask Claude to check sandbox status. Claude calls adp_status, adp_doctor, reports health." |
| 13 | 15s | GitHub repo with issue templates + Discord | "Open source. Join us on Discord. Star the repo." |

**Total**: ~3.5 minutes of real-time content + compressed VM creation = ~4-5 minutes.

## Recording Setup

### Tools
- **Screen recording**: [OBS Studio](https://obsproject.com/) (free, Windows)
- **Terminal**: Windows Terminal with PowerShell 7, clean profile (no custom prompts)
- **Font**: Cascadia Code or Consolas, 14pt
- **Resolution**: 1920x1080 or 1280x720

### Pre-recording Checklist
- [ ] Clean terminal — no previous output, no custom PS1
- [ ] Close all non-relevant windows and notifications
- [ ] Ensure `adp doctor` passes (7/7)
- [ ] Have a working VM ready OR prepare to fast-forward VM creation
- [ ] Pre-configure MCP server in Claude Desktop or Hermes
- [ ] Have the Discord invite link ready for Part 6
- [ ] Test all commands in the exact order of the script

### Post-production
- Add text overlays for command labels
- Speed up VM creation section (10x)
- Add lower-third captions for key concepts
- Add end screen with: GitHub URL, Discord invite, CONTRIBUTING.md link
- Export as 1080p MP4, upload to YouTube (unlisted or public)

## Alternatives Considered

- **GIF instead of video**: A short animated GIF for the README would complement the video. Consider creating a 30-second GIF of `adp status` + `adp doctor` for the README header.
- **Live stream**: Not recommended for first demo. A polished, edited video is more discoverable and reusable.
- **Multiple short videos**: Could split into "Installation" and "MCP Server" separate videos. Start with one combined video and split later if needed.

## Next Steps

1. [ ] Set up Discord server (see `docs/discord-setup.md`)
2. [ ] Enable GitHub Discussions
3. [ ] Prepare a clean VM snapshot for recording
4. [ ] Record the demo following this script
5. [ ] Upload to YouTube, embed in README
6. [ ] Announce on Discord + social media
