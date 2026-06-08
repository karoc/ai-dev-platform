# ADP-OS CLI Entry Point
# Subcommand routing: init, up, status, stop, sync, snapshot, logs, doctor, destroy, capabilities, run, completion, iso, quickstart
# .SYNOPSIS
#   adp.ps1 <command> [args...] [-Json]

param(
    [Parameter(Position = 0)]
    [string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments,
    [switch]$Json
)

$ErrorActionPreference = "Stop"
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent

# --- Global JSON output mode ---
if ($Json) {
    $global:ADPOutputJson = $true
} else {
    $global:ADPOutputJson = $false
}

# --- Load Core ---
. "$script:ProjectRoot\core\config\config.ps1"
. "$script:ProjectRoot\core\logging\logger.ps1"
. "$script:ProjectRoot\core\utility\circuit-breaker.ps1"
. "$script:ProjectRoot\adapters\windows\filesystem\filesystem.ps1"
. "$script:ProjectRoot\core\provider\provider-result.ps1"
. "$script:ProjectRoot\core\provider\provider-discovery.ps1"

Initialize-Config -ProjectRoot $script:ProjectRoot
Initialize-Logging -LogDirectory (Join-Path $script:ProjectRoot "logs")

# Phase 4: Provider initialization — feature-flagged via provider.mode
# vmware-provider (default): use IVMProvider contract via vmware-provider.ps1
# vmware-classic:             use legacy vmware.ps1 adapter directly
#
# Initialization is best-effort at entry-point level: on real systems with
# VMware it succeeds; on CI / test runners it logs a warning so basic
# commands (help, version, validate) remain usable without a hypervisor.
$script:ProviderMode = Get-ProviderMode
if ($script:ProviderMode -eq "vmware-provider") {
    . "$script:ProjectRoot\adapters\windows\vmware\vmware-provider.ps1"
    try {
        $vmStore = Resolve-Path "vm_store"
        Initialize-Provider -ProviderType "vmware-workstation" -ProjectRoot $script:ProjectRoot -InitArgs @{VmStorePath = $vmStore} | Out-Null
    } catch {
        Write-WarnLog -Message "Provider init skipped (VMware not available): $_" -Component "cli"
    }
} else {
    # Legacy path — kept as emergency fallback
    . "$script:ProjectRoot\adapters\windows\vmware\vmware.ps1"
    try {
        Initialize-VMware | Out-Null
    } catch {
        Write-WarnLog -Message "VMware adapter init skipped (vmware not available): $_" -Component "cli"
    }
}

# --- Command Router ---
$validCommands = @("setup", "init", "up", "status", "stop", "sync", "snapshot", "restore", "logs", "doctor", "destroy", "network", "workspace", "capabilities", "validate", "help", "run", "completion", "version", "iso", "quickstart", "precheck", "sandbox", "serve", "uninstall")

function Quote-PowerShellArgument {
    param([string]$Value)

    return "'" + ($Value -replace "'", "''") + "'"
}

function Invoke-CommandFile {
    param(
        [string]$Path,
        [string[]]$RawArguments
    )

    $parts = @(". $(Quote-PowerShellArgument $Path)")
    foreach ($arg in $RawArguments) {
        if ($arg -match '^-{1,2}[A-Za-z][A-Za-z0-9_-]*$') {
            $parts += $arg
        } else {
            $parts += (Quote-PowerShellArgument $arg)
        }
    }

    $scriptBlock = [scriptblock]::Create($parts -join " ")
    & $scriptBlock
}

. (Join-Path $script:ProjectRoot "cli\lib\suggestions.ps1")
. (Join-Path $script:ProjectRoot "cli\lib\help.ps1")

# --- Help / Version flag detection ---
$helpFlags = @('--help', '-Help', '-?')

# Bare --help or --version as command
if ($Command -and ($helpFlags -contains $Command)) {
    Show-Help
    exit 0
}
if ($Command -eq '--version') {
    Show-Version
    exit 0
}

# Subcommand --help: "adpos up --help"
if ($Command -and $Command -in $validCommands -and $Arguments -and ($helpFlags -contains $Arguments[0])) {
    Show-Help -CommandName $Command
    exit 0
}

if (-not $Command -or $Command -eq "help") {
    Show-Help
    exit 0
}

$commandFile = Join-Path $script:ProjectRoot "cli\commands\$Command.ps1"

if ($Command -notin $validCommands) {
    $unknownCommandMessage = if ((Get-UILanguage) -eq "zh-CN") { "未知命令: $Command" } else { "Unknown command: $Command" }
    Write-ErrorLog -Message $unknownCommandMessage -Component "cli"
    Write-Host ""
    $suggestion = Get-ADPCommandSuggestion -InputCommand $Command -CandidateCommands $validCommands
    if ((Get-UILanguage) -eq "zh-CN") {
        if ($suggestion) {
            Write-Host "你是不是想运行: adpos $suggestion" -ForegroundColor Cyan
        }
        Write-Host "可用命令: $($validCommands -join ', ')" -ForegroundColor Yellow
        Write-Host "运行 'adpos help' 查看完整帮助。" -ForegroundColor DarkGray
    } else {
        if ($suggestion) {
            Write-Host "Did you mean: adpos $suggestion" -ForegroundColor Cyan
        }
        Write-Host "Valid commands: $($validCommands -join ', ')" -ForegroundColor Yellow
        Write-Host "Run 'adpos help' to see full help." -ForegroundColor DarkGray
    }
    exit 1
}

if (-not (Test-Path $commandFile)) {
    $reservedLogMessage = if ((Get-UILanguage) -eq "zh-CN") { "命令尚未实现: $Command" } else { "Command not yet implemented: $Command" }
    Write-WarnLog -Message $reservedLogMessage -Component "cli"
    if ((Get-UILanguage) -eq "zh-CN") {
        Write-Host "  命令 '$Command' 已为未来阶段保留。" -ForegroundColor DarkGray
    } else {
        Write-Host "  Command '$Command' is reserved for a future phase." -ForegroundColor DarkGray
    }
    exit 1
}

Write-DebugLog -Message "Executing command: $Command with args: $Arguments" -Component "cli"
$global:LASTEXITCODE = 0
Invoke-CommandFile -Path $commandFile -RawArguments $Arguments
if ($LASTEXITCODE -gt 0) {
    exit $LASTEXITCODE
}
