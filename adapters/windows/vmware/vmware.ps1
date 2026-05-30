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
    # vmrun list returns only running VMs. Keep Get-RegisteredVMs as a compatibility alias for older callers.
    return Get-RegisteredVMs
}

function Normalize-VMXPath {
    param([string]$VmxPath)

    if ([string]::IsNullOrWhiteSpace($VmxPath)) {
        return ""
    }

    try {
        return [System.IO.Path]::GetFullPath($VmxPath)
    } catch {
        return $VmxPath
    }
}

function Get-ADPRuntimeNameFromVmxPath {
    param([string]$VmxPath)

    if ([string]::IsNullOrWhiteSpace($VmxPath)) {
        return ""
    }

    $leaf = [System.IO.Path]::GetFileName($VmxPath)
    if ($leaf -match '^adp-(.+)\.vmx$') {
        return $matches[1]
    }

    return ""
}

function Get-ADPRunningRuntimeVMs {
    param(
        [string[]]$RunningVmxPaths,
        [string]$RuntimeName = "",
        [string]$ManagedVmxPath = ""
    )

    $managedFull = Normalize-VMXPath -VmxPath $ManagedVmxPath
    $items = [System.Collections.Generic.List[object]]::new()

    foreach ($path in @($RunningVmxPaths)) {
        $runtime = Get-ADPRuntimeNameFromVmxPath -VmxPath $path
        if (-not $runtime) {
            continue
        }

        if ($RuntimeName -and $runtime -ne $RuntimeName) {
            continue
        }

        $full = Normalize-VMXPath -VmxPath $path
        $items.Add([pscustomobject]@{
            RuntimeName                = $runtime
            VmxPath                    = $path
            NormalizedVmxPath          = $full
            IsManagedByCurrentCheckout = ($managedFull -and $full -eq $managedFull)
        }) | Out-Null
    }

    return @($items)
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

function ConvertTo-ADPIPv4UInt32 {
    param([string]$Address)

    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($Address, [ref]$ip)) {
        throw "Invalid IPv4 address: $Address"
    }
    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Not an IPv4 address: $Address"
    }

    $bytes = $ip.GetAddressBytes()
    [array]::Reverse($bytes)
    return [BitConverter]::ToUInt32($bytes, 0)
}

function ConvertFrom-ADPIPv4UInt32 {
    param([uint32]$Value)

    $bytes = [BitConverter]::GetBytes($Value)
    [array]::Reverse($bytes)
    return ([System.Net.IPAddress]::new($bytes)).ToString()
}

function Get-ADPIPv4MaskUInt32 {
    param([int]$PrefixLength)

    if ($PrefixLength -lt 0 -or $PrefixLength -gt 32) {
        throw "Invalid IPv4 prefix length: $PrefixLength"
    }

    if ($PrefixLength -eq 0) {
        return [uint32]0
    }

    return [uint32]([uint32]::MaxValue -shl (32 - $PrefixLength))
}

function Get-ADPIPv4NetworkCidr {
    param(
        [string]$Address,
        [int]$PrefixLength
    )

    $ipInt = ConvertTo-ADPIPv4UInt32 -Address $Address
    $mask = Get-ADPIPv4MaskUInt32 -PrefixLength $PrefixLength
    $network = $ipInt -band $mask
    return "$(ConvertFrom-ADPIPv4UInt32 -Value $network)/$PrefixLength"
}

function Test-ADPIPv4InCidr {
    param(
        [string]$Address,
        [string]$Cidr
    )

    if ([string]::IsNullOrWhiteSpace($Address) -or [string]::IsNullOrWhiteSpace($Cidr)) {
        return $false
    }

    $parts = $Cidr -split '/', 2
    if ($parts.Count -ne 2) {
        return $false
    }

    $prefix = 0
    if (-not [int]::TryParse($parts[1], [ref]$prefix)) {
        return $false
    }

    try {
        $ipInt = ConvertTo-ADPIPv4UInt32 -Address $Address
        $networkInt = ConvertTo-ADPIPv4UInt32 -Address $parts[0]
        $mask = Get-ADPIPv4MaskUInt32 -PrefixLength $prefix
        return (($ipInt -band $mask) -eq ($networkInt -band $mask))
    } catch {
        return $false
    }
}

function Get-VMwareVMnet8HostNetwork {
    if (-not $IsWindows) {
        return $null
    }

    try {
        $addresses = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object {
            $_.InterfaceAlias -like "*VMnet8*" -and
            $_.IPAddress -and
            (Test-ValidIPv4 $_.IPAddress)
        })

        if ($addresses.Count -eq 0) {
            return $null
        }

        $selected = $addresses | Sort-Object SkipAsSource, PrefixLength | Select-Object -First 1
        $cidr = Get-ADPIPv4NetworkCidr -Address $selected.IPAddress -PrefixLength ([int]$selected.PrefixLength)

        return [pscustomobject]@{
            Source         = "host-adapter"
            InterfaceAlias = $selected.InterfaceAlias
            Address        = $selected.IPAddress
            Prefix         = [int]$selected.PrefixLength
            Cidr           = $cidr
        }
    } catch {
        return $null
    }
}

function Get-VMwareNatConfigNetwork {
    $natConfig = "C:\ProgramData\VMware\vmnetnat.conf"
    if (-not (Test-Path -LiteralPath $natConfig)) {
        return $null
    }

    try {
        $lines = Get-Content -LiteralPath $natConfig -ErrorAction Stop
        $inVmnet8 = $false
        foreach ($line in $lines) {
            if ($line -match '^\s*\[host\s+VMnet8\]\s*$') {
                $inVmnet8 = $true
                continue
            }

            if ($inVmnet8 -and $line -match '^\s*\[host\s+') {
                $inVmnet8 = $false
            }

            if ($inVmnet8 -and $line -match '^\s*ip\s*=\s*((?:\d{1,3}\.){3}\d{1,3})/(\d{1,2})\s*$') {
                $gateway = $matches[1]
                $prefix = [int]$matches[2]
                return [pscustomobject]@{
                    Source         = "vmnetnat.conf"
                    InterfaceAlias = "VMnet8"
                    Address        = $gateway
                    Prefix         = $prefix
                    Cidr           = Get-ADPIPv4NetworkCidr -Address $gateway -PrefixLength $prefix
                }
            }
        }
    } catch {
        return $null
    }

    return $null
}

function Get-VMwareNatNetwork {
    $hostNetwork = Get-VMwareVMnet8HostNetwork
    if ($hostNetwork) {
        return $hostNetwork
    }

    return Get-VMwareNatConfigNetwork
}

function Test-VMwareNatConfigMatchesHost {
    param([object]$ConfiguredNat)

    if (-not $ConfiguredNat -or [string]::IsNullOrWhiteSpace($ConfiguredNat.cidr)) {
        return [pscustomobject]@{
            Checked          = $false
            Matches          = $false
            Reason           = "missing configured VMware NAT CIDR"
            ConfiguredCidr   = ""
            HostCidr         = ""
            HostSource       = ""
            HostAddress      = ""
            HostInterface    = ""
            GatewayInHostCidr = $false
        }
    }

    $hostNetwork = Get-VMwareNatNetwork
    if (-not $hostNetwork) {
        return [pscustomobject]@{
            Checked          = $false
            Matches          = $false
            Reason           = "VMnet8 host network not detected"
            ConfiguredCidr   = [string]$ConfiguredNat.cidr
            HostCidr         = ""
            HostSource       = ""
            HostAddress      = ""
            HostInterface    = ""
            GatewayInHostCidr = $false
        }
    }

    $gateway = if ($ConfiguredNat.gateway) { [string]$ConfiguredNat.gateway } else { "" }
    $gatewayInHostCidr = if ($gateway) { Test-ADPIPv4InCidr -Address $gateway -Cidr $hostNetwork.Cidr } else { $false }

    return [pscustomobject]@{
        Checked          = $true
        Matches          = ([string]$ConfiguredNat.cidr -eq [string]$hostNetwork.Cidr)
        Reason           = ""
        ConfiguredCidr   = [string]$ConfiguredNat.cidr
        HostCidr         = [string]$hostNetwork.Cidr
        HostSource       = [string]$hostNetwork.Source
        HostAddress      = [string]$hostNetwork.Address
        HostInterface    = [string]$hostNetwork.InterfaceAlias
        GatewayInHostCidr = $gatewayInHostCidr
    }
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

function Get-VMIPQuick {
    param(
        [string]$VmxPath,
        [int]$TimeoutSeconds = 5
    )

    $probe = Invoke-Vmrun -Arguments @("getGuestIPAddress", $VmxPath) -TimeoutSeconds $TimeoutSeconds
    if ($probe.Success) {
        $ip = Select-VMIPv4FromText -Text $probe.StdOut
        if ($ip) {
            return $ip
        }
    }

    return Get-VMIPFromDhcpLeases -VmxPath $VmxPath
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
