# ADP-OS Demo Readiness Guide
# Prints the survival demo readiness path without touching runtime or host state.

[CmdletBinding()]
param(
    [switch]$Plan
)

$ErrorActionPreference = "Stop"

Write-Host ""
Write-UIHost -English "ADP-OS Demo Readiness Plan" -Chinese "ADP-OS 演练就绪计划" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-UIHost `
    -English "Readiness guide only: this command does not run the demo." `
    -Chinese "仅就绪引导：此命令不会运行 demo。" `
    -ForegroundColor Yellow
Write-UIHost `
    -English "No VM, sync session, snapshot, SSH, host configuration, PATH, files, downloads, or registrations will be changed." `
    -Chinese "不会更改 VM、同步会话、快照、SSH、主机配置、PATH、文件、下载或命令注册。" `
    -ForegroundColor DarkGray
Write-Host ""

Write-UIHost -English "Manual readiness checks:" -Chinese "手动就绪检查:" -ForegroundColor Cyan
Write-UIHost -English "  1. adpos precheck" -Chinese "  1. adpos precheck" -ForegroundColor DarkGray
Write-UIHost -English "  2. adpos run agent -Plan" -Chinese "  2. adpos run agent -Plan" -ForegroundColor DarkGray
Write-UIHost -English "  3. adpos doctor" -Chinese "  3. adpos doctor" -ForegroundColor DarkGray
Write-UIHost -English "  4. adpos status agent" -Chinese "  4. adpos status agent" -ForegroundColor DarkGray
Write-UIHost -English "  5. adpos sync status" -Chinese "  5. adpos sync status" -ForegroundColor DarkGray
Write-UIHost -English "  6. adpos workspace recipes -ManifestPath configs\workspace.recipes.example.json" -Chinese "  6. adpos workspace recipes -ManifestPath configs\workspace.recipes.example.json" -ForegroundColor DarkGray
Write-Host ""

Write-UIHost -English "Hard boundaries:" -Chinese "硬性边界:" -ForegroundColor Cyan
Write-UIHost `
    -English "  - If VMware is unavailable, do not run the survival demo." `
    -Chinese "  - 如果 VMware 不可用，不要运行 survival demo。" `
    -ForegroundColor DarkGray
Write-UIHost `
    -English "  - Do not fake VMware, snapshot, restore, SSH, evidence chain, or evidence export output." `
    -Chinese "  - 不要伪造 VMware、snapshot、restore、SSH、evidence chain 或 evidence export 输出。" `
    -ForegroundColor DarkGray
Write-UIHost `
    -English "  - This command does not approve recording, publishing, outreach, user recruitment, testimonials, Discord, or GitHub Discussions." `
    -Chinese "  - 此命令不批准录制、发布、外联、用户招募、testimonial、Discord 或 GitHub Discussions。" `
    -ForegroundColor DarkGray
Write-Host ""

Write-UIHost -English "Docs:" -Chinese "文档:" -ForegroundColor Cyan
Write-UIHost -English "  docs/demo-script.md" -Chinese "  docs/zh-CN/demo-script.md" -ForegroundColor DarkGray
Write-UIHost -English "  docs/survival-validation.md" -Chinese "  docs/zh-CN/survival-validation.md" -ForegroundColor DarkGray
Write-Host ""
Write-UIHost `
    -English "The optional -Plan flag is accepted for clarity; the default command is also guide-only." `
    -Chinese "可使用可选 -Plan 明确只看计划；默认命令同样仅输出引导。" `
    -ForegroundColor DarkGray
