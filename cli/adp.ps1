# ADP-OS CLI Entry Point
# Subcommand routing: init, up, stop, sync, snapshot, logs, doctor, destroy
# .SYNOPSIS
#   adp.ps1 <command> [args...]

param(
    [Parameter(Position = 0)]
    [string]$Command,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Arguments
)

$ErrorActionPreference = "Stop"
$script:ProjectRoot = Split-Path $PSScriptRoot -Parent

# --- Load Core ---
. "$script:ProjectRoot\core\config\config.ps1"
. "$script:ProjectRoot\core\logging\logger.ps1"
. "$script:ProjectRoot\adapters\windows\filesystem\filesystem.ps1"
. "$script:ProjectRoot\adapters\windows\vmware\vmware.ps1"

Initialize-Config -ProjectRoot $script:ProjectRoot
Initialize-Logging -LogDirectory (Join-Path $script:ProjectRoot "logs")

# --- Command Router ---
$validCommands = @("init", "up", "stop", "sync", "snapshot", "restore", "logs", "doctor", "destroy", "network", "help")

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

if (-not $Command -or $Command -eq "help") {
    Show-Help
    exit 0
}

$commandFile = Join-Path $script:ProjectRoot "cli\commands\$Command.ps1"

if ($Command -notin $validCommands) {
    Write-ErrorLog -Message "Unknown command: $Command" -Component "cli"
    Write-Host ""
    Write-Host "Valid commands: $($validCommands -join ', ')" -ForegroundColor Yellow
    exit 1
}

if (-not (Test-Path $commandFile)) {
    Write-WarnLog -Message "Command not yet implemented: $Command" -Component "cli"
    Write-Host "  Command '$Command' is reserved for a future phase." -ForegroundColor DarkGray
    exit 1
}

Write-DebugLog -Message "Executing command: $Command with args: $Arguments" -Component "cli"
Invoke-CommandFile -Path $commandFile -RawArguments $Arguments

# --- Help ---
function Show-Help {
    Write-Host ""
    Write-Host "ADP-OS CLI — AI Development Platform OS" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Commands:" -ForegroundColor Yellow
    Write-Host "  adp init                       Initialize platform and VM factory"
    Write-Host "  adp up <runtime> [-Plan]       Start a runtime (frontend|backend|agent)"
    Write-Host "  adp stop <runtime>             Stop a runtime"
    Write-Host "  adp sync status                Show workspace sync status"
    Write-Host "  adp network apply <rt|all> [-Plan]  Apply configured static IP networking"
    Write-Host "  adp snapshot create <rt> <name>  Create runtime snapshot"
    Write-Host "  adp restore <rt> <name>        Restore runtime snapshot"
    Write-Host "  adp logs <runtime>             Show runtime logs"
    Write-Host "  adp doctor [-FirstRun]         Run diagnostics"
    Write-Host "  adp destroy <runtime> [-Plan]  Destroy a runtime"
    Write-Host "  adp help                       Show this help"
    Write-Host ""
}
