# ADP-OS VMware Adapter (Windows)
# Abstracts VMware Workstation via vmrun.exe
# Platform: Windows only (macOS/Linux reserved for future)

$script:VmrunPath = $null
$script:Verified = $false

function Initialize-VMware {
    param([string]$VmrunExePath)

    if ($VmrunExePath) {
        $script:VmrunPath = $VmrunExePath
    } else {
        $script:VmrunPath = Find-Vmrun
    }

    if (-not (Test-Path $script:VmrunPath)) {
        throw "vmrun.exe not found at: $script:VmrunPath. Please install VMware Workstation."
    }

    $script:Verified = $true
    return $script:VmrunPath
}

function Find-Vmrun {
    $knownPaths = @(
        "C:\Program Files (x86)\VMware\VMware Workstation\vmrun.exe",
        "C:\Program Files\VMware\VMware Workstation\vmrun.exe"
    )

    foreach ($p in $knownPaths) {
        if (Test-Path $p) { return $p }
    }

    $fromPath = (Get-Command vmrun.exe -ErrorAction SilentlyContinue).Source
    if ($fromPath) { return $fromPath }

    return $null
}

function Invoke-Vmrun {
    param(
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 300
    )

    if (-not $script:Verified) {
        throw "VMware adapter not initialized. Call Initialize-VMware first."
    }

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()

    try {
        $proc = Start-Process -FilePath $script:VmrunPath `
            -ArgumentList $Arguments `
            -WindowStyle Hidden -PassThru `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError $errFile `
            -ErrorAction Stop

        $completed = $proc.WaitForExit($TimeoutSeconds * 1000)
        if (-not $completed) {
            try {
                $proc.Kill()
            } catch {}

            return @{
                ExitCode = -1
                StdOut   = ""
                StdErr   = "vmrun timed out after ${TimeoutSeconds}s: $($Arguments -join ' ')"
                Success  = $false
            }
        }

        $stdout = Get-Content $outFile -Raw -ErrorAction SilentlyContinue
        $stderr = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
        $exitCode = if ($proc) { $proc.ExitCode } else { -1 }

        return @{
            ExitCode = $exitCode
            StdOut   = if ($stdout) { $stdout.Trim() } else { "" }
            StdErr   = if ($stderr) { $stderr.Trim() } else { "" }
            Success  = ($exitCode -eq 0)
        }
    } catch {
        return @{
            ExitCode = -1
            StdOut   = ""
            StdErr   = "Start-Process failed: $_"
            Success  = $false
        }
    } finally {
        Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
    }
}

function Get-RegisteredVMs {
    $result = Invoke-Vmrun -Arguments @("list")
    if ($result.Success) {
        return $result.StdOut -split "`n" | Where-Object { $_ -match '\.vmx$' } | ForEach-Object { $_.Trim() }
    }
    return @()
}

function Get-RunningVMs {
    return Get-RegisteredVMs
}

function Get-VMStatus {
    param([string]$VmxPath)

    if (-not (Test-Path $VmxPath)) {
        return "not-created"
    }

    $target = [System.IO.Path]::GetFullPath($VmxPath)
    $running = Get-RunningVMs | ForEach-Object { [System.IO.Path]::GetFullPath($_) }

    if ($running -contains $target) {
        return "running"
    }

    $ipProbe = Invoke-Vmrun -Arguments @("getGuestIPAddress", $VmxPath) -TimeoutSeconds 10
    if ($ipProbe.Success -and (Select-VMIPv4FromText -Text $ipProbe.StdOut)) {
        return "running"
    }

    return "stopped"
}

function Start-VM {
    param(
        [string]$VmxPath,
        [string]$Mode = "gui"
    )

    $flag = if ($Mode -eq "nogui") { "nogui" } else { "gui" }
    return Invoke-Vmrun -Arguments @("start", $VmxPath, $flag)
}

function Stop-VM {
    param(
        [string]$VmxPath,
        [string]$Mode = "soft"
    )

    return Invoke-Vmrun -Arguments @("stop", $VmxPath, $Mode)
}

function Suspend-VM {
    param([string]$VmxPath)
    return Invoke-Vmrun -Arguments @("suspend", $VmxPath)
}

function Reset-VM {
    param([string]$VmxPath)
    return Invoke-Vmrun -Arguments @("reset", $VmxPath)
}

function Test-ValidIPv4 {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    $address = $null
    if (-not [System.Net.IPAddress]::TryParse($Value.Trim(), [ref]$address)) {
        return $false
    }

    if ($address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }

    $text = $address.ToString()
    return ($text -ne "0.0.0.0" -and $text -notlike "169.254.*")
}

function Select-VMIPv4FromText {
    param([string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }

    $matches = [regex]::Matches($Text, '\b(?:\d{1,3}\.){3}\d{1,3}\b')
    foreach ($match in $matches) {
        $candidate = $match.Value
        if (Test-ValidIPv4 $candidate) {
            return $candidate
        }
    }

    return $null
}

function Get-VMMacAddresses {
    param([string]$VmxPath)

    if (-not (Test-Path $VmxPath)) {
        return @()
    }

    $macs = [System.Collections.Generic.List[string]]::new()
    $lines = Get-Content -Path $VmxPath -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -match '^\s*ethernet\d+\.(?:generatedAddress|address)\s*=\s*"([^"]+)"') {
            $mac = $matches[1].Trim().ToLowerInvariant()
            if ($mac -match '^(?:[0-9a-f]{2}:){5}[0-9a-f]{2}$' -and -not $macs.Contains($mac)) {
                $macs.Add($mac) | Out-Null
            }
        }
    }

    return @($macs)
}

function Get-VMIPFromDhcpLeases {
    param([string]$VmxPath)

    $macs = @(Get-VMMacAddresses -VmxPath $VmxPath)
    if ($macs.Count -eq 0) {
        return $null
    }

    $leaseFiles = @(
        "C:\ProgramData\VMware\vmnetdhcp.leases",
        "C:\ProgramData\VMware\vmnetdhcp.leases~"
    ) | Where-Object { Test-Path $_ }

    foreach ($leaseFile in $leaseFiles) {
        $currentIp = $null
        $lines = Get-Content -Path $leaseFile -ErrorAction SilentlyContinue
        foreach ($line in $lines) {
            if ($line -match '^\s*lease\s+((?:\d{1,3}\.){3}\d{1,3})\s*\{') {
                $currentIp = $matches[1]
                continue
            }

            if ($currentIp -and $line -match '^\s*hardware\s+ethernet\s+([0-9a-fA-F:]+)\s*;') {
                $mac = $matches[1].Trim().ToLowerInvariant()
                if ($macs -contains $mac -and (Test-ValidIPv4 $currentIp)) {
                    return $currentIp
                }
            }

            if ($line -match '^\s*\}') {
                $currentIp = $null
            }
        }
    }

    return $null
}

function Get-VMIP {
    param([string]$VmxPath)

    $errors = [System.Collections.Generic.List[string]]::new()

    $quick = Invoke-Vmrun -Arguments @("getGuestIPAddress", $VmxPath) -TimeoutSeconds 15
    if ($quick.Success) {
        $ip = Select-VMIPv4FromText -Text $quick.StdOut
        if ($ip) {
            return $ip
        }
        $errors.Add("getGuestIPAddress returned no usable IPv4: $($quick.StdOut)") | Out-Null
    } else {
        $errors.Add($quick.StdErr) | Out-Null
    }

    $wait = Invoke-Vmrun -Arguments @("getGuestIPAddress", $VmxPath, "-wait") -TimeoutSeconds 60
    if ($wait.Success) {
        $ip = Select-VMIPv4FromText -Text $wait.StdOut
        if ($ip) {
            return $ip
        }
        $errors.Add("getGuestIPAddress -wait returned no usable IPv4: $($wait.StdOut)") | Out-Null
    } else {
        $errors.Add($wait.StdErr) | Out-Null
    }

    $leaseIp = Get-VMIPFromDhcpLeases -VmxPath $VmxPath
    if ($leaseIp) {
        return $leaseIp
    }

    throw "Could not resolve VM IP for $VmxPath. Attempts: $($errors -join '; ')"
}

function Run-GuestCommand {
    param(
        [string]$VmxPath,
        [string]$GuestUser,
        [string]$GuestPassword,
        [string]$Command
    )

    return Invoke-Vmrun -Arguments @(
        "-gu", $GuestUser,
        "-gp", $GuestPassword,
        "runProgramInGuest", $VmxPath,
        "/bin/bash", "-c", $Command
    )
}

function Copy-FileToGuest {
    param(
        [string]$VmxPath,
        [string]$GuestUser,
        [string]$GuestPassword,
        [string]$HostPath,
        [string]$GuestPath
    )

    return Invoke-Vmrun -Arguments @(
        "-gu", $GuestUser,
        "-gp", $GuestPassword,
        "copyFileFromHostToGuest", $VmxPath,
        $HostPath, $GuestPath
    )
}

function Create-VMSnapshot {
    param(
        [string]$VmxPath,
        [string]$SnapshotName
    )

    return Invoke-Vmrun -Arguments @("snapshot", $VmxPath, $SnapshotName)
}

function Restore-VMSnapshot {
    param(
        [string]$VmxPath,
        [string]$SnapshotName
    )

    return Invoke-Vmrun -Arguments @("revertToSnapshot", $VmxPath, $SnapshotName)
}

function List-VMSnapshots {
    param([string]$VmxPath)
    $result = Invoke-Vmrun -Arguments @("listSnapshots", $VmxPath)
    if ($result.Success) {
        return $result.StdOut -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ }
    }
    return @()
}

function Remove-VMSnapshot {
    param(
        [string]$VmxPath,
        [string]$SnapshotName
    )
    return Invoke-Vmrun -Arguments @("deleteSnapshot", $VmxPath, $SnapshotName)
}

function Get-VmrunPath {
    return $script:VmrunPath
}

function Test-VMwareAvailable {
    try {
        $path = Find-Vmrun
        return $null -ne $path
    } catch {
        return $false
    }
}
