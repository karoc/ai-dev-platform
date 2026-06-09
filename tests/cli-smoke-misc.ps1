Assert-Command `
    -Name "logs unknown runtime" `
    -Arguments @("logs", "not-a-runtime") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent, sandbox")

Assert-Command `
    -Name "destroy plan unknown runtime" `
    -Arguments @("destroy", "not-a-runtime", "-Plan") `
    -ExitCode 1 `
    -Patterns @("Unknown runtime: not-a-runtime", "frontend, backend, agent, sandbox", "adpos destroy --help")

# --- setup.ps1 smoke tests ---
$setupScript = Join-Path $projectRoot "setup.ps1"

function Invoke-Setup {
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
            $processArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $setupScript) + $Arguments
            $process = Start-Process -FilePath $script:PwshPath `
                -ArgumentList $processArguments `
                -WorkingDirectory $projectRoot `
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

function Assert-Setup {
    param(
        [string]$Name,
        [string[]]$Arguments,
        [int]$ExitCode,
        [string[]]$Patterns,
        [hashtable]$Environment = @{}
    )
    $result = Invoke-Setup -Arguments $Arguments -Environment $Environment
    if ($result.ExitCode -ne $ExitCode) {
        throw "$Name exit code was $($result.ExitCode), expected $ExitCode.`n$($result.Output)"
    }
    foreach ($pattern in $Patterns) {
        if ($result.Output -notmatch $pattern) {
            throw "$Name output did not match: $pattern`n$($result.Output)"
        }
    }
}

Assert-Setup `
    -Name "setup script exists and shows banner" `
    -Arguments @() `
    -ExitCode 1 `
    -Patterns @("ADP-OS One-Click Setup", "AI Development Platform", "Scan prerequisites")

if (Get-Command vmrun.exe -ErrorAction SilentlyContinue) {
    Assert-Setup `
        -Name "setup non-interactive force skip-iso skip-doctor" `
        -Arguments @("-NonInteractive", "-Force", "-SkipIsoDownload", "-SkipDoctor") `
        -ExitCode 0 `
        -Patterns @("ADP-OS Quickstart", "NonInteractive", "Force")
} else {
    Write-Host "SKIP: setup non-interactive test (vmrun.exe not found — CI without VMware)"
}
