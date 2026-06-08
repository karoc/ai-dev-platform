# ADP-OS SSH Adapter (Windows)
# Platform-specific SSH key management and connection helpers

$script:SshKeyDir = "$env:USERPROFILE\.ssh\adp-os"

function Initialize-SSH {
    param([string]$KeyName = "adp-os")

    $script:SshKeyDir = "$env:USERPROFILE\.ssh\adp-os"

    if (-not (Test-Path $script:SshKeyDir)) {
        New-Item -ItemType Directory -Path $script:SshKeyDir -Force | Out-Null
    }

    $keyPath = Join-Path $script:SshKeyDir $KeyName

    if (-not (Test-Path $keyPath)) {
        & ssh-keygen -t ed25519 -f $keyPath -N "" -C "adp-os-runtime" | Out-Null
    }

    return $keyPath
}

function Get-SSHPubKey {
    param([string]$KeyName = "adp-os")

    $keyPath = Join-Path $script:SshKeyDir "$KeyName.pub"

    if (-not (Test-Path $keyPath)) {
        throw "SSH key not found. Run Initialize-SSH first."
    }

    return Get-Content $keyPath -Raw
}

function Invoke-AdpSshCommand {
    param(
        [Alias("Host")]
        [string]$HostAddress,
        [string]$Command,
        [int]$Port = 22,
        [string]$User = "adp",
        [string]$KeyPath = (Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"),
        [int]$ConnectTimeoutSeconds = 5,
        [int]$TimeoutSeconds = 12
    )

    $result = [ordered]@{
        State     = "unknown"
        ExitCode  = $null
        TimedOut  = $false
        StdOut    = ""
        StdErr    = ""
        Arguments = @()
    }

    if ([string]::IsNullOrWhiteSpace($HostAddress)) {
        $result.State = "not-configured"
        return [pscustomobject]$result
    }

    $sshCommand = Get-Command ssh.exe -ErrorAction SilentlyContinue
    if (-not $sshCommand) {
        $sshCommand = Get-Command ssh -ErrorAction SilentlyContinue
    }
    if (-not $sshCommand) {
        $result.State = "ssh-unavailable"
        return [pscustomobject]$result
    }

    if (-not (Test-Path -LiteralPath $KeyPath)) {
        $result.State = "key-missing"
        return [pscustomobject]$result
    }

    $sshPath = if ($sshCommand.Source) { $sshCommand.Source } else { $sshCommand.Name }
    $sshArgs = @(
        "-i", $KeyPath,
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=NUL",
        "-o", "IdentitiesOnly=yes",
        "-o", "ConnectTimeout=$ConnectTimeoutSeconds",
        "-o", "ConnectionAttempts=1",
        "-o", "BatchMode=yes",
        "-o", "ServerAliveInterval=5",
        "-o", "ServerAliveCountMax=1",
        "-p", "$Port",
        "$User@$HostAddress"
    )
    if (-not [string]::IsNullOrWhiteSpace($Command)) {
        $sshArgs += $Command
    }
    $result.Arguments = @($sshArgs)

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        $proc = Start-Process -FilePath $sshPath `
            -ArgumentList $sshArgs `
            -PassThru `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError $errFile `
            -ErrorAction Stop

        $completed = $proc.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            try {
                $proc.Kill()
            } catch {}
            $result.State = "ssh-timeout"
            $result.ExitCode = -1
            $result.TimedOut = $true
            $result.StdErr = "ssh timed out after ${TimeoutSeconds}s"
            return [pscustomobject]$result
        }

        $stdout = Get-Content -LiteralPath $outFile -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
        $result.StdOut = if ($stdout) { $stdout.Trim() } else { "" }
        $result.StdErr = if ($stderr) { $stderr.Trim() } else { "" }
        $result.ExitCode = if ($null -ne $proc.ExitCode) { [int]$proc.ExitCode } else { -1 }

        $sshText = (@($result.StdOut, $result.StdErr) | Where-Object { $_ }) -join "`n"
        if ($result.ExitCode -eq 0) {
            $result.State = "command-success"
        } elseif ($result.ExitCode -eq 255 -and $sshText -match "Permission denied") {
            $result.State = "auth-pending"
        } elseif ($result.ExitCode -eq 255) {
            $result.State = "unreachable"
        } else {
            $result.State = "command-failed"
        }
        return [pscustomobject]$result
    } catch {
        $result.State = "unreachable"
        $result.ExitCode = -1
        $result.StdErr = "Start-Process failed: $_"
        return [pscustomobject]$result
    } finally {
        Remove-Item -LiteralPath $outFile, $errFile -ErrorAction SilentlyContinue
        $global:LASTEXITCODE = 0
    }
}

function Test-AdpSshReachability {
    param(
        [Alias("Host")]
        [string]$HostAddress,
        [int]$Port = 22,
        [string]$User = "adp",
        [string]$KeyPath = (Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"),
        [int]$ConnectTimeoutSeconds = 5,
        [int]$TimeoutSeconds = 12
    )

    $probe = Invoke-AdpSshCommand `
        -Host $HostAddress `
        -Port $Port `
        -User $User `
        -KeyPath $KeyPath `
        -Command "echo ok" `
        -ConnectTimeoutSeconds $ConnectTimeoutSeconds `
        -TimeoutSeconds $TimeoutSeconds

    if ($probe.State -eq "command-success") {
        return "reachable"
    }
    if ($probe.State -in @("not-configured", "ssh-unavailable", "key-missing", "auth-pending", "ssh-timeout")) {
        return $probe.State
    }
    return "unreachable"
}

function Connect-Runtime {
    param(
        [string]$Host,
        [int]$Port = 22,
        [string]$User = "adp",
        [string]$KeyName = "adp-os"
    )

    $keyPath = Join-Path $script:SshKeyDir $KeyName

    & ssh -i $keyPath -p $Port "$User@$Host"
}

function Copy-ToRuntime {
    param(
        [string]$Host,
        [string]$LocalPath,
        [string]$RemotePath,
        [int]$Port = 22,
        [string]$User = "adp",
        [string]$KeyName = "adp-os"
    )

    $keyPath = Join-Path $script:SshKeyDir $KeyName

    & scp -i $keyPath -P $Port -r $LocalPath "$User@${Host}:$RemotePath"
}

function Invoke-RuntimeCommand {
    param(
        [string]$Host,
        [string]$Command,
        [int]$Port = 22,
        [string]$User = "adp",
        [string]$KeyName = "adp-os"
    )

    $keyPath = Join-Path $script:SshKeyDir $KeyName

    return & ssh -i $keyPath -p $Port "$User@$Host" $Command
}
