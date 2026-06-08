$ErrorActionPreference = "Stop"

$script:ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:Cli = Join-Path $script:ProjectRoot "cli\adp.ps1"
$projectRoot = $script:ProjectRoot
$cli = $script:Cli

# Resolve pwsh full path for Start-Process (bare "pwsh" not always in PATH on CI runners)
$script:PwshPath = try { (Get-Process -Id $PID).Path } catch { $null }
if (-not $script:PwshPath) {
    $script:PwshPath = (Get-Command pwsh -ErrorAction Stop).Source
}

function Invoke-Cli {
    param(
        [string[]]$Arguments,
        [hashtable]$Environment = @{}
    )

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    $previousEnvironment = @{}
    try {
        foreach ($name in $Environment.Keys) {
            $previousEnvironment[$name] = [System.Environment]::GetEnvironmentVariable($name, "Process")
            [System.Environment]::SetEnvironmentVariable($name, [string]$Environment[$name], "Process")
        }

        $savedOutputEncoding = [Console]::OutputEncoding
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
        try {
            $processArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script:Cli) + $Arguments
            $process = Start-Process -FilePath $script:PwshPath `
                -ArgumentList $processArguments `
                -WorkingDirectory $script:ProjectRoot `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $stdout `
                -RedirectStandardError $stderr
        } finally {
            [Console]::OutputEncoding = $savedOutputEncoding
        }

        $outText = Get-Content -LiteralPath $stdout -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $errText = Get-Content -LiteralPath $stderr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = "$outText`n$errText"
        }
    } finally {
        foreach ($name in $Environment.Keys) {
            [System.Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], "Process")
        }
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
}

function Assert-ExitCode {
    param(
        [string]$Name,
        [object]$Result,
        [int]$Expected
    )

    if ($Result.ExitCode -ne $Expected) {
        throw "$Name exit code was $($Result.ExitCode), expected $Expected.`n$($Result.Output)"
    }
}

function Assert-OutputContains {
    param(
        [string]$Name,
        [object]$Result,
        [string]$Pattern
    )

    if ($Result.Output -notmatch $Pattern) {
        throw "$Name output did not match: $Pattern`n$($Result.Output)"
    }
}

function Assert-Command {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [int]$ExitCode,
        [string[]]$Patterns,
        [hashtable]$Environment = @{}
    )

    $result = Invoke-Cli -Arguments $Arguments -Environment $Environment
    Assert-ExitCode -Name $Name -Result $result -Expected $ExitCode
    foreach ($pattern in $Patterns) {
        Assert-OutputContains -Name $Name -Result $result -Pattern $pattern
    }
}
