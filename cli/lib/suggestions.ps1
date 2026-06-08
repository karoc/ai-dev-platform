# ADP-OS CLI typo suggestion helpers.

function Measure-ADPCommandDistance {
    param(
        [string]$Left,
        [string]$Right
    )

    if ($Left -eq $Right) { return 0 }
    if ([string]::IsNullOrEmpty($Left)) { return $Right.Length }
    if ([string]::IsNullOrEmpty($Right)) { return $Left.Length }

    $previous = 0..$Right.Length
    for ($i = 1; $i -le $Left.Length; $i++) {
        $current = New-Object 'int[]' ($Right.Length + 1)
        $current[0] = $i
        for ($j = 1; $j -le $Right.Length; $j++) {
            $cost = if ($Left[$i - 1] -eq $Right[$j - 1]) { 0 } else { 1 }
            $current[$j] = [Math]::Min(
                [Math]::Min($current[$j - 1] + 1, $previous[$j] + 1),
                $previous[$j - 1] + $cost
            )
        }
        $previous = $current
    }

    return $previous[$Right.Length]
}

function Get-ADPCommandSuggestion {
    param(
        [string]$InputCommand,
        [string[]]$CandidateCommands
    )

    if ([string]::IsNullOrWhiteSpace($InputCommand)) {
        return $null
    }

    $prefixMatch = $CandidateCommands | Where-Object { $_.StartsWith($InputCommand, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($prefixMatch) {
        return $prefixMatch
    }

    $best = $CandidateCommands |
        ForEach-Object {
            [pscustomobject]@{
                Command  = $_
                Distance = Measure-ADPCommandDistance -Left $InputCommand.ToLowerInvariant() -Right $_.ToLowerInvariant()
            }
        } |
        Sort-Object Distance, Command |
        Select-Object -First 1

    if ($best -and $best.Distance -le [Math]::Max(2, [Math]::Floor($InputCommand.Length / 3))) {
        return $best.Command
    }

    return $null
}
