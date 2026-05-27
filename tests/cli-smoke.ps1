# ADP-OS CLI smoke tests
# Non-destructive behavior checks for command dispatch, preview paths, and input errors.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$cli = Join-Path $projectRoot "cli\adp.ps1"

function Invoke-Cli {
    param([string[]]$Arguments)

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $processArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $cli) + $Arguments
        $process = Start-Process -FilePath "pwsh" `
            -ArgumentList $processArguments `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr

        $outText = Get-Content -LiteralPath $stdout -Raw -ErrorAction SilentlyContinue
        $errText = Get-Content -LiteralPath $stderr -Raw -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = "$outText`n$errText"
        }
    } finally {
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
        [string[]]$Patterns
    )

    $result = Invoke-Cli -Arguments $Arguments
    Assert-ExitCode -Name $Name -Result $result -Expected $ExitCode
    foreach ($pattern in $Patterns) {
        Assert-OutputContains -Name $Name -Result $result -Pattern $pattern
    }
}

Assert-Command `
    -Name "help" `
    -Arguments @("help") `
    -ExitCode 0 `
    -Patterns @("ADP-OS CLI", "adp up <runtime>")

Assert-Command `
    -Name "unknown command" `
    -Arguments @("not-a-command") `
    -ExitCode 1 `
    -Patterns @("Unknown command: not-a-command", "Valid commands:")

Assert-Command `
    -Name "up unknown runtime" `
    -Arguments @("up", "not-a-runtime", "-Plan") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent")

Assert-Command `
    -Name "up plan" `
    -Arguments @("up", "agent", "-Plan", "-IsoPath", "D:\Share\ubuntu-26.04-live-server-amd64.iso") `
    -ExitCode 0 `
    -Patterns @("Plan only: no VM will be created", "Runtime:\s+agent", "ISO:\s+D:\\Share\\ubuntu-26\.04-live-server-amd64\.iso")

Assert-Command `
    -Name "sync unknown subcommand" `
    -Arguments @("sync", "nope") `
    -ExitCode 1 `
    -Patterns @("Unknown sync command: nope", "status, start, stop, list")

Assert-Command `
    -Name "sync unknown runtime" `
    -Arguments @("sync", "stop", "not-a-runtime") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent")

Assert-Command `
    -Name "logs unknown runtime" `
    -Arguments @("logs", "not-a-runtime") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent")

Assert-Command `
    -Name "destroy plan unknown runtime" `
    -Arguments @("destroy", "not-a-runtime", "-Plan") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime")

Write-Output "CLI smoke tests OK"
