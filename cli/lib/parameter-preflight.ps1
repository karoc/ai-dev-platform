# ADP-OS command parameter preflight.
# Parses only the command script parameter block and lets PowerShell bind arguments before provider init.

function Quote-ADPPreflightPowerShellArgument {
    param([string]$Value)

    return "'" + ($Value -replace "'", "''") + "'"
}

function Resolve-ADPPreflightArgumentAlias {
    param([string]$Argument)

    if (Get-Command Resolve-ADPArgumentAlias -CommandType Function -ErrorAction SilentlyContinue) {
        return Resolve-ADPArgumentAlias -Argument $Argument
    }

    if ([string]::IsNullOrWhiteSpace($Argument)) {
        return $Argument
    }

    switch ($Argument.ToLowerInvariant()) {
        "--help-prereqs" { return "-HelpPrereqs" }
        default { return $Argument }
    }
}

function Get-ADPCommandParameterPreflightText {
    param([string]$Path)

    $source = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseInput($source, [ref]$tokens, [ref]$parseErrors)

    if ($parseErrors -and $parseErrors.Count -gt 0) {
        $messages = ($parseErrors | ForEach-Object { $_.Message }) -join "; "
        throw "Cannot parse command parameter block: $Path. $messages"
    }

    if (-not $ast.ParamBlock) {
        return ""
    }

    $attributes = @($ast.ParamBlock.Attributes | ForEach-Object { $_.Extent.Text })
    return (@($attributes) + $ast.ParamBlock.Extent.Text) -join "`n"
}

function Invoke-ADPCommandParameterPreflight {
    param(
        [string]$Path,
        [string[]]$RawArguments
    )

    $preflightText = Get-ADPCommandParameterPreflightText -Path $Path
    if ([string]::IsNullOrWhiteSpace($preflightText)) {
        return
    }

    $preflightScriptBlock = [scriptblock]::Create($preflightText)
    $parts = @('& $preflightScriptBlock')
    foreach ($argument in @($RawArguments)) {
        if ($null -eq $argument) {
            continue
        }

        $argument = Resolve-ADPPreflightArgumentAlias -Argument $argument
        if ($argument -match '^-{1,2}[A-Za-z][A-Za-z0-9_-]*$') {
            $parts += $argument
        } else {
            $parts += (Quote-ADPPreflightPowerShellArgument -Value $argument)
        }
    }

    $invokeScriptBlock = [scriptblock]::Create($parts -join " ")
    & $invokeScriptBlock
}
