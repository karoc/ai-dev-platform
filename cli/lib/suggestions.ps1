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

    return Get-ADPValueSuggestion -InputValue $InputCommand -CandidateValues $CandidateCommands
}

function Get-ADPValueSuggestion {
    param(
        [string]$InputValue,
        [string[]]$CandidateValues
    )

    if ([string]::IsNullOrWhiteSpace($InputValue)) {
        return $null
    }

    $prefixMatch = $CandidateValues | Where-Object { $_.StartsWith($InputValue, [System.StringComparison]::OrdinalIgnoreCase) } | Select-Object -First 1
    if ($prefixMatch) {
        return $prefixMatch
    }

    $best = $CandidateValues |
        ForEach-Object {
            [pscustomobject]@{
                Value    = $_
                Distance = Measure-ADPCommandDistance -Left $InputValue.ToLowerInvariant() -Right $_.ToLowerInvariant()
            }
        } |
        Sort-Object Distance, Value |
        Select-Object -First 1

    if ($best -and $best.Distance -le [Math]::Max(2, [Math]::Floor($InputValue.Length / 3))) {
        return $best.Value
    }

    return $null
}

function Write-ADPUnknownRuntimeError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuntimeName,

        [Parameter(Mandatory = $true)]
        [string]$CommandText,

        [string[]]$ValidRuntimeNames = (Get-AllRuntimeNames),

        [string]$Component = "cli",

        [string]$HelpEnglish,

        [string]$HelpChinese
    )

    $validText = $ValidRuntimeNames -join ', '
    Write-ErrorLog -Message (Get-UIText -English "Unknown runtime: $RuntimeName. Valid: $validText" -Chinese "未知运行时: $RuntimeName。可用: $validText") -Component $Component

    $suggestion = Get-ADPValueSuggestion -InputValue $RuntimeName -CandidateValues $ValidRuntimeNames
    if ($suggestion) {
        Write-UIHost -English "Did you mean: adpos $CommandText $suggestion" -Chinese "你是不是想运行: adpos $CommandText $suggestion" -ForegroundColor Cyan
    }

    if ([string]::IsNullOrWhiteSpace($HelpEnglish)) {
        $HelpEnglish = "Run 'adpos $CommandText --help' for usage."
    }
    if ([string]::IsNullOrWhiteSpace($HelpChinese)) {
        $HelpChinese = "运行 'adpos $CommandText --help' 查看用法。"
    }
    Write-UIHost -English $HelpEnglish -Chinese $HelpChinese -ForegroundColor DarkGray
}
