# ADP-OS bounded SSH probe contract checks
# Uses local command mocks so no real SSH connection is attempted.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $projectRoot "adapters\windows\ssh\ssh.ps1")

$originalUserProfile = $env:USERPROFILE
$env:USERPROFILE = "C:\Users\adp-test"

function Assert-Equal {
    param(
        [string]$Name,
        [object]$Actual,
        [object]$Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name expected '$Expected' but got '$Actual'"
    }
}

function Assert-True {
    param(
        [string]$Name,
        [bool]$Condition
    )

    if (-not $Condition) {
        throw "$Name expected true"
    }
}

function New-MockProcess {
    param(
        [bool]$Completed,
        [int]$ExitCode = 0
    )

    $process = [pscustomobject]@{
        Completed = $Completed
        ExitCode  = $ExitCode
        Killed    = $false
    }

    $process | Add-Member -MemberType ScriptMethod -Name WaitForExit -Value {
        param([int]$Milliseconds)
        $script:ObservedWaitMilliseconds = $Milliseconds
        return $this.Completed
    }

    $process | Add-Member -MemberType ScriptMethod -Name Kill -Value {
        $this.Killed = $true
    }

    return $process
}

function Reset-MockSsh {
    param(
        [bool]$Available = $true,
        [bool]$KeyExists = $true,
        [bool]$Completed = $true,
        [int]$ExitCode = 0,
        [string]$StdOut = "",
        [string]$StdErr = ""
    )

    $script:MockSshAvailable = $Available
    $script:MockKeyExists = $KeyExists
    $script:MockCompleted = $Completed
    $script:MockExitCode = $ExitCode
    $script:MockStdOut = $StdOut
    $script:MockStdErr = $StdErr
    $script:ObservedArgs = @()
    $script:ObservedWaitMilliseconds = 0
    $script:MockOutPath = ""
    $script:MockErrPath = ""
    $script:MockProcess = $null
}

function Get-Command {
    [CmdletBinding()]
    param([Parameter(Position = 0)][string]$Name)

    if ($Name -in @("ssh", "ssh.exe")) {
        if ($script:MockSshAvailable) {
            return [pscustomobject]@{ Source = "C:\mock\ssh.exe"; Name = "ssh.exe" }
        }
        return $null
    }

    return Microsoft.PowerShell.Core\Get-Command @PSBoundParameters
}

function Test-Path {
    [CmdletBinding()]
    param(
        [string]$LiteralPath,
        [string]$Path
    )

    return $script:MockKeyExists
}

function Start-Process {
    [CmdletBinding()]
    param(
        [string]$FilePath,
        [string[]]$ArgumentList,
        [switch]$PassThru,
        [string]$RedirectStandardOutput,
        [string]$RedirectStandardError
    )

    $script:ObservedFilePath = $FilePath
    $script:ObservedArgs = @($ArgumentList)
    $script:MockOutPath = $RedirectStandardOutput
    $script:MockErrPath = $RedirectStandardError
    $script:MockProcess = New-MockProcess -Completed:$script:MockCompleted -ExitCode $script:MockExitCode
    return $script:MockProcess
}

function Get-Content {
    [CmdletBinding()]
    param(
        [string]$LiteralPath,
        [string]$Path,
        [switch]$Raw
    )

    $target = if ($LiteralPath) { $LiteralPath } else { $Path }
    if ($target -eq $script:MockOutPath) { return $script:MockStdOut }
    if ($target -eq $script:MockErrPath) { return $script:MockStdErr }
    return ""
}

function Remove-Item {
    [CmdletBinding()]
    param(
        [string[]]$LiteralPath,
        [string[]]$Path
    )
}

try {
    Reset-MockSsh
    Assert-Equal -Name "empty host state" -Actual (Test-AdpSshReachability -Host "") -Expected "not-configured"

    Reset-MockSsh -Available:$false
    Assert-Equal -Name "missing ssh state" -Actual (Test-AdpSshReachability -Host "192.168.242.135") -Expected "ssh-unavailable"

    Reset-MockSsh -KeyExists:$false
    Assert-Equal -Name "missing key state" -Actual (Test-AdpSshReachability -Host "192.168.242.135") -Expected "key-missing"

    Reset-MockSsh -ExitCode 0 -StdOut "ok"
    Assert-Equal -Name "reachable state" -Actual (Test-AdpSshReachability -Host "192.168.242.135") -Expected "reachable"
    Assert-Equal -Name "bounded wait milliseconds" -Actual $script:ObservedWaitMilliseconds -Expected 12000
    Assert-True -Name "uses ssh.exe" -Condition ($script:ObservedFilePath -eq "C:\mock\ssh.exe")
    Assert-True -Name "sets BatchMode" -Condition ($script:ObservedArgs -contains "BatchMode=yes")
    Assert-True -Name "sets ConnectionAttempts" -Condition ($script:ObservedArgs -contains "ConnectionAttempts=1")
    Assert-True -Name "sets ADP known_hosts boundary" -Condition ($script:ObservedArgs -contains "UserKnownHostsFile=NUL")

    Reset-MockSsh -ExitCode 255 -StdErr "Permission denied (publickey)."
    Assert-Equal -Name "auth pending state" -Actual (Test-AdpSshReachability -Host "192.168.242.135") -Expected "auth-pending"

    Reset-MockSsh -Completed:$false
    $timeoutProbe = Invoke-AdpSshCommand -Host "192.168.242.135" -Command "echo ok" -TimeoutSeconds 7
    Assert-Equal -Name "timeout state" -Actual $timeoutProbe.State -Expected "ssh-timeout"
    Assert-Equal -Name "timeout wait milliseconds" -Actual $script:ObservedWaitMilliseconds -Expected 7000
    Assert-True -Name "timeout kills process" -Condition $script:MockProcess.Killed
    Assert-Equal -Name "timeout does not leak exit code" -Actual $global:LASTEXITCODE -Expected 0

    Reset-MockSsh -ExitCode 1 -StdErr "missing marker"
    $failedProbe = Invoke-AdpSshCommand -Host "192.168.242.135" -Command "test -f /home/adp/.adp-provisioned"
    Assert-Equal -Name "command failure state" -Actual $failedProbe.State -Expected "command-failed"
} finally {
    $env:USERPROFILE = $originalUserProfile
}

Write-Output "bounded SSH probe contract OK"
