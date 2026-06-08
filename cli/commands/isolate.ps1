# ADP-OS checkout isolation planner command.
# Renders read-only local override guidance for running multiple checkouts.

param(
    [switch]$Plan,
    [string]$Namespace,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

if ($Apply) {
    Write-ErrorLog -Message (Get-UIText -English "-Apply is not implemented for isolate yet. Use: adpos isolate -Plan" -Chinese "isolate 暂不支持 -Apply。请使用: adpos isolate -Plan") -Component "cli.isolate"
    exit 1
}

. (Join-Path (Get-ProjectRoot) "core\diagnostics\resource-conflicts.ps1")
. (Join-Path (Get-ProjectRoot) "core\diagnostics\checkout-isolation.ps1")

$isolationPlan = Get-ADPCheckoutIsolationPlan -RequestedNamespace $Namespace
$commandContext = Get-ADPCheckoutCommandContext
$commandPrefix = if ($commandContext.CommandPrefix) { [string]$commandContext.CommandPrefix } else { ".\adpos.cmd" }
$validationRuntime = $isolationPlan.ValidationRuntime

Write-Host ""
Write-UIHost -English "ADP-OS Checkout Isolation Plan" -Chinese "ADP-OS checkout 隔离计划" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-ADPCheckoutBindingSummary -CommandContext $commandContext
Write-UIHost -English "Local config: $($isolationPlan.LocalConfigPath)" -Chinese "本机配置: $($isolationPlan.LocalConfigPath)" -ForegroundColor DarkGray
Write-UIHost -English "Local config status: $(if ($isolationPlan.LocalConfigStatus.Exists) { 'exists' } else { 'not created' })" -Chinese "本机配置状态: $(if ($isolationPlan.LocalConfigStatus.Exists) { '已存在' } else { '尚未创建' })" -ForegroundColor DarkGray
Write-UIHost -English "Namespace:    $($isolationPlan.Namespace) ($($isolationPlan.NamespaceSource))" -Chinese "Namespace:    $($isolationPlan.Namespace) ($($isolationPlan.NamespaceSource))" -ForegroundColor DarkGray

Write-Host ""
Write-UIHost -English "Proposed local config changes:" -Chinese "建议的本机配置变更:" -ForegroundColor Yellow
foreach ($change in @($isolationPlan.Changes)) {
    Write-Host "  $($change.Path) [$($change.Status)]:" -ForegroundColor DarkGray
    Write-Host "    $($change.Current) -> $($change.Target)" -ForegroundColor DarkGray
    Write-Host "    reason: $($change.Reason)" -ForegroundColor DarkGray
}

Write-Host ""
Write-UIHost -English "Runtime resource preview:" -Chinese "Runtime 资源预览:" -ForegroundColor Yellow
foreach ($runtimePlan in @($isolationPlan.RuntimePlans)) {
    Write-Host "  $($runtimePlan.Runtime): resource=$($runtimePlan.RuntimeResourceName), VM=$($runtimePlan.VmName)" -ForegroundColor DarkGray
    Write-Host "    static_ip:       $($runtimePlan.CurrentIp) -> $($runtimePlan.TargetIp)" -ForegroundColor DarkGray
    Write-Host "    VMX:             $($runtimePlan.VmxPath)" -ForegroundColor DarkGray
    Write-Host "    workspace:       $($runtimePlan.WorkspacePath)" -ForegroundColor DarkGray
    Write-Host "    SSH alias:       $($runtimePlan.SshAlias) (port $($runtimePlan.SshPort))" -ForegroundColor DarkGray
    Write-Host "    Mutagen session: $($runtimePlan.MutagenSession)" -ForegroundColor DarkGray
    Write-Host "    remote:          $($runtimePlan.ExpectedRemoteUrl)" -ForegroundColor DarkGray
}

Write-Host ""
Write-UIHost -English "configs\\local.json snippet:" -Chinese "configs\\local.json 片段:" -ForegroundColor Yellow
ConvertTo-ADPCheckoutIsolationLocalJson -IsolationPlan $isolationPlan

Write-Host ""
Write-UIHost -English "Validation commands after editing configs\\local.json:" -Chinese "编辑 configs\\local.json 后的验收命令:" -ForegroundColor Yellow
Write-Host "  $commandPrefix doctor" -ForegroundColor DarkGray
Write-Host "  $commandPrefix status $validationRuntime" -ForegroundColor DarkGray
Write-Host "  $commandPrefix sync status" -ForegroundColor DarkGray
Write-Host "  $commandPrefix up $validationRuntime -Plan" -ForegroundColor DarkGray

Write-Host ""
Write-UIHost -English "Plan only: configs\\local.json will not be changed." -Chinese "仅预览：不会修改 configs\\local.json。" -ForegroundColor Cyan
Write-UIHost -English "No files, VMs, SSH aliases, sync sessions, PATH entries, or global adpos bindings were changed." -Chinese "未修改任何文件、VM、SSH alias、sync session、PATH 项或全局 adpos 绑定。" -ForegroundColor Cyan
Write-Host ""
