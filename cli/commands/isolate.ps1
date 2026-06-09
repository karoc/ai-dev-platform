# ADP-OS checkout isolation planner command.
# Renders read-only local override guidance for running multiple checkouts.

[CmdletBinding()]
param(
    [switch]$Plan,
    [string]$Namespace,
    [switch]$Apply
)

$ErrorActionPreference = "Stop"

if ($Plan -and $Apply) {
    Write-ErrorLog -Message (Get-UIText -English "Use either -Plan or -Apply, not both." -Chinese "-Plan 与 -Apply 只能二选一。") -Component "cli.isolate"
    exit 1
}

. (Join-Path (Get-ProjectRoot) "core\diagnostics\resource-conflicts.ps1")
. (Join-Path (Get-ProjectRoot) "core\diagnostics\checkout-isolation.ps1")
. (Join-Path (Get-ProjectRoot) "core\config\local-config-edit.ps1")

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
Write-UIHost -English "Validation commands after the local override is in place:" -Chinese "本机覆盖配置就绪后的验收命令:" -ForegroundColor Yellow
Write-Host "  $commandPrefix doctor" -ForegroundColor DarkGray
Write-Host "  $commandPrefix status $validationRuntime" -ForegroundColor DarkGray
Write-Host "  $commandPrefix sync status" -ForegroundColor DarkGray
Write-Host "  $commandPrefix up $validationRuntime -Plan" -ForegroundColor DarkGray

Write-Host ""
if ($Apply) {
    $applyResult = Set-ADPCheckoutIsolationLocalConfig -IsolationPlan $isolationPlan
    if ($applyResult.Changed) {
        Write-UIHost -English "Applied: updated configs\\local.json with checkout isolation overrides." -Chinese "已应用：已用 checkout 隔离覆盖配置更新 configs\\local.json。" -ForegroundColor Green
        if ($applyResult.BackupPath) {
            Write-UIHost -English "Backup:  $($applyResult.BackupPath)" -Chinese "备份:    $($applyResult.BackupPath)" -ForegroundColor DarkGray
        } else {
            Write-UIHost -English "Backup:  none; configs\\local.json did not exist before apply." -Chinese "备份:    无；apply 前 configs\\local.json 不存在。" -ForegroundColor DarkGray
        }
    } else {
        Write-UIHost -English "Already isolated: configs\\local.json was not changed." -Chinese "已隔离：configs\\local.json 未发生变化。" -ForegroundColor Green
        Write-UIHost -English "Backup:  none; no write was needed." -Chinese "备份:    无；无需写入。" -ForegroundColor DarkGray
    }

    Write-UIHost -English "Preserved: unrelated configs\\local.json fields were left unchanged." -Chinese "保留:    configs\\local.json 中无关字段保持不变。" -ForegroundColor DarkGray
    Write-UIHost -English "Not changed: VMs, SSH aliases, sync sessions, PATH entries, or global adpos bindings." -Chinese "未修改:  VM、SSH alias、sync session、PATH 项或全局 adpos 绑定。" -ForegroundColor Cyan
} else {
    Write-UIHost -English "Plan only: configs\\local.json will not be changed." -Chinese "仅预览：不会修改 configs\\local.json。" -ForegroundColor Cyan
    Write-UIHost -English "No files, VMs, SSH aliases, sync sessions, PATH entries, or global adpos bindings were changed." -Chinese "未修改任何文件、VM、SSH alias、sync session、PATH 项或全局 adpos 绑定。" -ForegroundColor Cyan
    Write-UIHost -English "To apply this local override: $commandPrefix isolate -Apply -Namespace $($isolationPlan.Namespace)" -Chinese "如要应用该本机覆盖: $commandPrefix isolate -Apply -Namespace $($isolationPlan.Namespace)" -ForegroundColor DarkGray
}
Write-Host ""
