# ADP-OS command semantic preflight.
# Catches command-specific argument combinations before provider init or command body execution.

function Invoke-ADPCommandSemanticPreflight {
    param(
        [string]$CommandName,
        [string[]]$RawArguments
    )

    if ([string]::IsNullOrWhiteSpace($CommandName)) {
        return $true
    }

    $normalizedCommand = $CommandName.ToLowerInvariant()
    if ($normalizedCommand -eq "doctor") {
        $planRequested = Test-ADPArgumentSwitchPresent -RawArguments $RawArguments -Name "Plan"
        $fixMutagenRequested = Test-ADPArgumentSwitchPresent -RawArguments $RawArguments -Name "FixMutagen"
        if ($planRequested -and -not $fixMutagenRequested) {
            Write-ErrorLog -Message (Get-UIText -English "-Plan is only supported with -FixMutagen. Use: adpos doctor -FixMutagen -Plan" -Chinese "-Plan 仅支持与 -FixMutagen 一起使用。用法: adpos doctor -FixMutagen -Plan") -Component "cli.doctor"
            Write-UIHost -English "Run 'adpos doctor --help' for usage." -Chinese "运行 'adpos doctor --help' 查看用法。" -ForegroundColor DarkGray
            Write-UIHost -English "Run 'adpos help' to see all commands." -Chinese "运行 'adpos help' 查看所有命令。" -ForegroundColor DarkGray
            return $false
        }
    }

    return $true
}
