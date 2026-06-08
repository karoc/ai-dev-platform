# ADP-OS Windows CMD wrapper tests.
# Covers stock-shell entry points without running destructive setup flows.

$ErrorActionPreference = "Stop"

if (-not $IsWindows) {
    Write-Host "SKIP: Windows CMD wrapper tests require Windows." -ForegroundColor Yellow
    exit 0
}

$projectRoot = Split-Path $PSScriptRoot -Parent

if ($projectRoot.StartsWith("\\")) {
    $tempProjectRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adpos-cmd-wrapper-source-{0}" -f ([guid]::NewGuid().ToString("N")))
    $excludedNames = @(".git", "logs", ".tools", ".venv", "node_modules")
    New-Item -ItemType Directory -Path $tempProjectRoot -Force | Out-Null
    try {
        Get-ChildItem -LiteralPath $projectRoot -Force |
            Where-Object { $excludedNames -notcontains $_.Name } |
            Copy-Item -Destination $tempProjectRoot -Recurse -Force

        $pwshPath = (Get-Process -Id $PID).Path
        & $pwshPath -NoProfile -ExecutionPolicy Bypass -File (Join-Path $tempProjectRoot "tests\cmd-wrapper.ps1")
        exit $LASTEXITCODE
    } finally {
        Remove-Item -LiteralPath $tempProjectRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$legacyAdpCmd = Join-Path $projectRoot "adp.cmd"
$adposCmd = Join-Path $projectRoot "adpos.cmd"
$setupCmd = Join-Path $projectRoot "setup.cmd"
$uninstallCmd = Join-Path $projectRoot "uninstall.cmd"

function Invoke-CmdProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory
    )

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $process = Start-Process -FilePath $env:ComSpec `
            -ArgumentList @("/d", "/c", $Command) `
            -WorkingDirectory $WorkingDirectory `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr

        $outText = Get-Content -LiteralPath $stdout -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $errText = Get-Content -LiteralPath $stderr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
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

function New-IsolatedCmdEnvironment {
    param([string]$Root)

    $emptyPath = Join-Path $Root "path"
    $programFiles = Join-Path $Root "program-files"
    $programFilesX86 = Join-Path $Root "program-files-x86"
    $localAppData = Join-Path $Root "local-app-data"
    $userProfile = Join-Path $Root "user-profile"

    New-Item -ItemType Directory -Path $emptyPath, $programFiles, $programFilesX86, $localAppData, $userProfile -Force | Out-Null

    return @(
        "set `"PATH=$emptyPath`"",
        "set `"ProgramFiles=$programFiles`"",
        "set `"ProgramFiles(x86)=$programFilesX86`"",
        "set `"LOCALAPPDATA=$localAppData`"",
        "set `"USERPROFILE=$userProfile`"",
        "set `"__PSLockdownPolicy=0`""
    ) -join " && "
}

if (Test-Path -LiteralPath $legacyAdpCmd) {
    throw "adp.cmd must not be exposed as a repo-local command; use adpos.cmd instead."
}

$adposVersionResult = Invoke-CmdProcess -Command "adpos.cmd --version" -WorkingDirectory $projectRoot
Assert-ExitCode -Name "adpos.cmd --version" -Result $adposVersionResult -Expected 0
Assert-OutputContains -Name "adpos.cmd --version" -Result $adposVersionResult -Pattern "ADP-OS version"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-cmd-wrapper-{0}" -f ([guid]::NewGuid().ToString("N")))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    Copy-Item -LiteralPath $setupCmd -Destination (Join-Path $tempRoot "setup.cmd")
    Set-Content -LiteralPath (Join-Path $tempRoot "setup.ps1") -Encoding UTF8 -Value @'
param(
    [string]$Distro = "ubuntu",
    [string]$IsoPath,
    [switch]$SkipIsoDownload,
    [switch]$SkipDoctor,
    [switch]$NonInteractive,
    [switch]$Force,
    [switch]$NoRegisterCommand
)

Write-Output "SETUP_STUB_OK"
Write-Output "Distro=$Distro"
Write-Output "IsoPath=$IsoPath"
Write-Output "SkipIsoDownload=$SkipIsoDownload"
Write-Output "SkipDoctor=$SkipDoctor"
Write-Output "NonInteractive=$NonInteractive"
Write-Output "Force=$Force"
Write-Output "NoRegisterCommand=$NoRegisterCommand"
'@

    $setupForwardResult = Invoke-CmdProcess `
        -Command "setup.cmd -IsoPath C:\stub.iso -SkipIsoDownload -SkipDoctor -NonInteractive -Force -NoRegisterCommand" `
        -WorkingDirectory $tempRoot
    Assert-ExitCode -Name "setup.cmd forwards arguments" -Result $setupForwardResult -Expected 0
    Assert-OutputContains -Name "setup.cmd forwards arguments" -Result $setupForwardResult -Pattern "SETUP_STUB_OK"
    Assert-OutputContains -Name "setup.cmd forwards arguments" -Result $setupForwardResult -Pattern "IsoPath=C:\\stub\.iso"
    Assert-OutputContains -Name "setup.cmd forwards arguments" -Result $setupForwardResult -Pattern "SkipIsoDownload=True"
    Assert-OutputContains -Name "setup.cmd forwards arguments" -Result $setupForwardResult -Pattern "SkipDoctor=True"
    Assert-OutputContains -Name "setup.cmd forwards arguments" -Result $setupForwardResult -Pattern "NonInteractive=True"
    Assert-OutputContains -Name "setup.cmd forwards arguments" -Result $setupForwardResult -Pattern "Force=True"
    Assert-OutputContains -Name "setup.cmd forwards arguments" -Result $setupForwardResult -Pattern "NoRegisterCommand=True"

    Copy-Item -LiteralPath $uninstallCmd -Destination (Join-Path $tempRoot "uninstall.cmd")
    Set-Content -LiteralPath (Join-Path $tempRoot "uninstall.ps1") -Encoding UTF8 -Value @'
param(
    [switch]$NonInteractive
)

Write-Output "UNINSTALL_STUB_OK"
Write-Output "NonInteractive=$NonInteractive"
'@

    $uninstallForwardResult = Invoke-CmdProcess `
        -Command "uninstall.cmd -NonInteractive" `
        -WorkingDirectory $tempRoot
    Assert-ExitCode -Name "uninstall.cmd forwards arguments" -Result $uninstallForwardResult -Expected 0
    Assert-OutputContains -Name "uninstall.cmd forwards arguments" -Result $uninstallForwardResult -Pattern "UNINSTALL_STUB_OK"
    Assert-OutputContains -Name "uninstall.cmd forwards arguments" -Result $uninstallForwardResult -Pattern "NonInteractive=True"

    $uninstallSubcommandResult = Invoke-CmdProcess `
        -Command "uninstall.cmd uninstall -NonInteractive" `
        -WorkingDirectory $tempRoot
    Assert-ExitCode -Name "uninstall.cmd tolerates leading uninstall subcommand" -Result $uninstallSubcommandResult -Expected 0
    Assert-OutputContains -Name "uninstall.cmd tolerates leading uninstall subcommand" -Result $uninstallSubcommandResult -Pattern "UNINSTALL_STUB_OK"
    Assert-OutputContains -Name "uninstall.cmd tolerates leading uninstall subcommand" -Result $uninstallSubcommandResult -Pattern "NonInteractive=True"

    $isolatedEnv = New-IsolatedCmdEnvironment -Root (Join-Path $tempRoot "isolated")
    Copy-Item -LiteralPath $adposCmd -Destination (Join-Path $tempRoot "adpos.cmd")

    $missingAdposResult = Invoke-CmdProcess -Command "$isolatedEnv && adpos.cmd --version" -WorkingDirectory $tempRoot
    Assert-ExitCode -Name "adpos.cmd missing pwsh" -Result $missingAdposResult -Expected 1
    Assert-OutputContains -Name "adpos.cmd missing pwsh" -Result $missingAdposResult -Pattern "ADP-OS requires PowerShell 7\+"
    Assert-OutputContains -Name "adpos.cmd missing pwsh" -Result $missingAdposResult -Pattern "winget install --id Microsoft\.PowerShell --source winget"

    $missingSetupResult = Invoke-CmdProcess -Command "$isolatedEnv && setup.cmd" -WorkingDirectory $tempRoot
    Assert-ExitCode -Name "setup.cmd missing pwsh" -Result $missingSetupResult -Expected 1
    Assert-OutputContains -Name "setup.cmd missing pwsh" -Result $missingSetupResult -Pattern "ADP-OS requires PowerShell 7\+"
    Assert-OutputContains -Name "setup.cmd missing pwsh" -Result $missingSetupResult -Pattern "https://github\.com/PowerShell/PowerShell/releases"

    $missingUninstallResult = Invoke-CmdProcess -Command "$isolatedEnv && uninstall.cmd -NonInteractive" -WorkingDirectory $tempRoot
    Assert-ExitCode -Name "uninstall.cmd falls back to Windows PowerShell" -Result $missingUninstallResult -Expected 0
    Assert-OutputContains -Name "uninstall.cmd falls back to Windows PowerShell" -Result $missingUninstallResult -Pattern "UNINSTALL_STUB_OK"
    Assert-OutputContains -Name "uninstall.cmd falls back to Windows PowerShell" -Result $missingUninstallResult -Pattern "NonInteractive=True"
} finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "Windows CMD wrapper tests OK" -ForegroundColor Green
