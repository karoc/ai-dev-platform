# ADP-OS Shell Completion Command
# Generates tab completion scripts for supported shells.

param(
    [Parameter(Position = 0)]
    [string]$Shell
)

$ErrorActionPreference = "Stop"

if (-not $Shell -or $Shell -notin @("powershell", "bash")) {
    Write-ErrorLog -Message (Get-UIText -English "Usage: adp completion <powershell|bash>" -Chinese "用法: adp completion <powershell|bash>") -Component "cli.completion"
    exit 1
}

$validCommands = @("init", "up", "run", "status", "stop", "sync", "snapshot", "restore", "logs", "doctor", "destroy", "network", "workspace", "capabilities", "validate", "help", "completion")

if ($Shell -eq "powershell") {
    # PowerShell Register-ArgumentCompleter script
    @'
# ADP-OS PowerShell Tab Completion
# Source this in your $PROFILE:
#   . .\cli\commands\completion.ps1 powershell | Out-String | Invoke-Expression
# Or install permanently:
#   adp completion powershell >> $PROFILE

Register-ArgumentCompleter -CommandName adp.ps1 -ParameterName Command -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $commands = @(
        "init", "up", "run", "status", "stop", "sync",
        "snapshot", "restore", "logs", "doctor", "destroy",
        "network", "workspace", "capabilities", "validate",
        "help", "completion"
    )
    $commands | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, "ParameterValue", $_)
    }
}
'@
} elseif ($Shell -eq "bash") {
    # Bash completion script (for WSL users who invoke adp via bash)
    @'
# ADP-OS Bash Tab Completion
# Source this in your .bashrc to enable tab completion when
# invoking adp.ps1 from WSL:
#   eval "$(pwsh.exe -NoProfile -Command ". .\cli\adp.ps1 completion bash")"
# Or install permanently:
#   adp completion bash >> ~/.bashrc

_adp_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local commands="init up run status stop sync snapshot restore logs doctor destroy network workspace capabilities validate help completion"

    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "$commands" -- "$cur"))
        return
    fi
}
complete -F _adp_completion adp
'@
}
