# ADP-OS Shell Completion Command
# Generates tab completion scripts for supported shells.

param(
    [Parameter(Position = 0)]
    [string]$Shell
)

$ErrorActionPreference = "Stop"

if (-not $Shell -or $Shell -notin @("powershell", "bash")) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adpos completion <powershell|bash>" -Chinese "用法: adpos completion <powershell|bash>") -Component "cli.completion"
    exit 1
}

$validCommands = @("setup", "init", "up", "run", "status", "stop", "sync", "snapshot", "restore", "logs", "doctor", "destroy", "network", "workspace", "capabilities", "validate", "help", "completion", "version", "iso", "quickstart", "precheck", "sandbox", "serve", "uninstall")

if ($Shell -eq "powershell") {
    # PowerShell Register-ArgumentCompleter script
    @'
# ADP-OS PowerShell Tab Completion
# Source this in your $PROFILE:
#   . .\cli\commands\completion.ps1 powershell | Out-String | Invoke-Expression
# Or install permanently:
#   adpos completion powershell >> $PROFILE

Register-ArgumentCompleter -CommandName adpos,adpos.cmd -ParameterName Command -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $commands = @(
        "setup", "init", "up", "run", "status", "stop", "sync",
        "snapshot", "restore", "logs", "doctor", "destroy",
        "network", "workspace", "capabilities", "validate",
        "help", "completion", "version", "iso", "quickstart",
        "precheck", "sandbox", "serve", "uninstall"
    )
    $commands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, "ParameterValue", $_)
    }
}
'@
} elseif ($Shell -eq "bash") {
# Bash completion script (for WSL users who invoke adpos via bash)
    @'
# ADP-OS Bash Tab Completion
# Source this in your .bashrc to enable tab completion when
# invoking adpos from WSL:
#   eval "$(pwsh.exe -NoProfile -Command ". adpos completion bash")"
# Or install permanently:
#   adpos completion bash >> ~/.bashrc

_adpos_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local commands="setup init up run status stop sync snapshot restore logs doctor destroy network workspace capabilities validate help completion version iso quickstart precheck sandbox serve uninstall"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        return
    fi
}
complete -F _adpos_completion adpos adpos.cmd
'@
}
