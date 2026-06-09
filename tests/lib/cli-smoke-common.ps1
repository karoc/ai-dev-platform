$ErrorActionPreference = "Stop"

$script:ProjectRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:Cli = Join-Path $script:ProjectRoot "cli\adp.ps1"
$projectRoot = $script:ProjectRoot
$cli = $script:Cli

function Get-CliSmokeCommandTimeoutSeconds {
    [int]$parsed = 0
    if ($env:ADP_CLI_SMOKE_COMMAND_TIMEOUT_SECONDS -and [int]::TryParse($env:ADP_CLI_SMOKE_COMMAND_TIMEOUT_SECONDS, [ref]$parsed) -and $parsed -gt 0) {
        return $parsed
    }

    return 120
}

$script:CliSmokeCommandTimeoutSeconds = Get-CliSmokeCommandTimeoutSeconds

# Resolve pwsh full path for Start-Process (bare "pwsh" not always in PATH on CI runners)
$script:PwshPath = try { (Get-Process -Id $PID).Path } catch { $null }
if (-not $script:PwshPath) {
    $script:PwshPath = (Get-Command pwsh -ErrorAction Stop).Source
}

function Wait-CliSmokeProcess {
    param(
        [System.Diagnostics.Process]$Process,
        [int]$TimeoutSeconds,
        [string]$Label,
        [string]$StdoutPath,
        [string]$StderrPath
    )

    if (-not $Process.WaitForExit($TimeoutSeconds * 1000)) {
        try {
            $Process.Kill($true)
        } catch {
            try { $Process.Kill() } catch { }
        }

        $outText = Get-Content -LiteralPath $StdoutPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $errText = Get-Content -LiteralPath $StderrPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        throw @(
            "CLI smoke command timed out after $TimeoutSeconds seconds: $Label",
            "STDOUT:",
            $outText,
            "STDERR:",
            $errText
        ) -join "`n"
    }

    $Process.Refresh()
}

function Invoke-Cli {
    param(
        [string[]]$Arguments,
        [hashtable]$Environment = @{},
        [int]$TimeoutSeconds = $script:CliSmokeCommandTimeoutSeconds
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
                -NoNewWindow -PassThru `
                -RedirectStandardOutput $stdout `
                -RedirectStandardError $stderr
            Wait-CliSmokeProcess `
                -Process $process `
                -TimeoutSeconds $TimeoutSeconds `
                -Label "adpos $($Arguments -join ' ')" `
                -StdoutPath $stdout `
                -StderrPath $stderr
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

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Host "SMOKE start: $Name"
    try {
        $result = Invoke-Cli -Arguments $Arguments -Environment $Environment
        Assert-ExitCode -Name $Name -Result $result -Expected $ExitCode
        foreach ($pattern in $Patterns) {
            Assert-OutputContains -Name $Name -Result $result -Pattern $pattern
        }

        $watch.Stop()
        Write-Host ("SMOKE ok: {0} ({1:n1}s)" -f $Name, $watch.Elapsed.TotalSeconds)
    } catch {
        $watch.Stop()
        Write-Host ("SMOKE failed: {0} ({1:n1}s)" -f $Name, $watch.Elapsed.TotalSeconds)
        throw
    }
}
