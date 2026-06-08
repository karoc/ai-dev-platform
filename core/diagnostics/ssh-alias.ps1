# ADP-OS SSH alias ownership diagnostics.
# Read-only helpers for detecting shared user SSH config conflicts.

function Get-ADPSshConfigPath {
    $userHome = ""
    if ($env:USERPROFILE) {
        $userHome = $env:USERPROFILE
    } elseif ($env:HOME) {
        $userHome = $env:HOME
    }

    if ([string]::IsNullOrWhiteSpace($userHome)) {
        return ""
    }

    return (Join-Path (Join-Path $userHome ".ssh") "config")
}

function Normalize-ADPSshTextValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return $Value.Trim().Trim('"').Trim("'")
}

function Normalize-ADPSshComparablePath {
    param([string]$Path)

    $value = Normalize-ADPSshTextValue -Value $Path
    if ([string]::IsNullOrWhiteSpace($value)) {
        return ""
    }

    $value = [Environment]::ExpandEnvironmentVariables($value)
    if ($value -match '^~[\\/]') {
        $userHome = if ($env:USERPROFILE) { $env:USERPROFILE } else { $env:HOME }
        if ($userHome) {
            $value = Join-Path $userHome $value.Substring(2)
        }
    }

    $value = $value -replace '/', '\'
    try {
        $value = [System.IO.Path]::GetFullPath($value)
    } catch {}

    return $value.TrimEnd('\', '/').ToLowerInvariant()
}

function Get-ADPSshBlockProperties {
    param([string]$BlockText)

    $properties = @{}
    foreach ($line in ($BlockText -split "\r?\n")) {
        if ($line -match '^\s*(?<key>HostName|User|Port|IdentityFile|IdentitiesOnly)\s+(?<value>.+?)\s*$') {
            $properties[$matches.key.ToLowerInvariant()] = Normalize-ADPSshTextValue -Value $matches.value
        }
    }

    return [pscustomobject]@{
        HostName       = if ($properties.ContainsKey("hostname")) { $properties["hostname"] } else { "" }
        User           = if ($properties.ContainsKey("user")) { $properties["user"] } else { "" }
        Port           = if ($properties.ContainsKey("port")) { $properties["port"] } else { "" }
        IdentityFile   = if ($properties.ContainsKey("identityfile")) { $properties["identityfile"] } else { "" }
        IdentitiesOnly = if ($properties.ContainsKey("identitiesonly")) { $properties["identitiesonly"] } else { "" }
    }
}

function Get-ADPSshHostBlock {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HostAlias,
        [string]$ConfigPath,
        [string]$ConfigText
    )

    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $ConfigPath = Get-ADPSshConfigPath
    }

    $text = ""
    $configExists = $false
    if ($PSBoundParameters.ContainsKey("ConfigText")) {
        $text = [string]$ConfigText
        $configExists = $true
    } elseif ($ConfigPath -and (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        $text = Get-Content -LiteralPath $ConfigPath -Raw -ErrorAction SilentlyContinue
        $configExists = $true
    }

    if (-not $configExists) {
        return [pscustomobject]@{
            Exists     = $false
            Source     = "missing-config"
            ConfigPath = $ConfigPath
            HostAlias  = $HostAlias
            BlockText  = ""
        }
    }

    if ([string]::IsNullOrWhiteSpace($text)) {
        return [pscustomobject]@{
            Exists     = $false
            Source     = "missing-alias"
            ConfigPath = $ConfigPath
            HostAlias  = $HostAlias
            BlockText  = ""
        }
    }

    $beginMarker = "# >>> ADP-OS $HostAlias >>>"
    $endMarker = "# <<< ADP-OS $HostAlias <<<"
    $markerPattern = "(?ms)^$([regex]::Escape($beginMarker))\r?\n(?<block>.*?)\r?\n$([regex]::Escape($endMarker))"
    if ($text -match $markerPattern) {
        return [pscustomobject]@{
            Exists     = $true
            Source     = "adp-marker"
            ConfigPath = $ConfigPath
            HostAlias  = $HostAlias
            BlockText  = $matches.block
        }
    }

    $lines = $text -split "\r?\n"
    $collecting = $false
    $blockLines = @()
    foreach ($line in $lines) {
        if ($line -match '^\s*(?<kind>Host|Match)\s+(?<value>.+?)\s*$') {
            if ($collecting) {
                break
            }

            $collecting = $false
            $blockLines = @()
            if ($matches.kind -eq "Host") {
                $aliases = @($matches.value -split '\s+' | Where-Object { $_ })
                if (@($aliases | Where-Object { $_.Equals($HostAlias, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
                    $collecting = $true
                    $blockLines = @($line)
                }
            }
            continue
        }

        if ($collecting) {
            $blockLines += $line
        }
    }

    if ($blockLines.Count -gt 0) {
        return [pscustomobject]@{
            Exists     = $true
            Source     = "unmanaged-host"
            ConfigPath = $ConfigPath
            HostAlias  = $HostAlias
            BlockText  = ($blockLines -join "`n")
        }
    }

    return [pscustomobject]@{
        Exists     = $false
        Source     = "missing-alias"
        ConfigPath = $ConfigPath
        HostAlias  = $HostAlias
        BlockText  = ""
    }
}

function Get-ADPSshAliasOwnershipStatus {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Profile,
        [string]$ExpectedHost,
        [string]$ExpectedUser,
        [int]$ExpectedPort = 0,
        [string]$ExpectedKeyPath,
        [string]$ConfigPath,
        [string]$ConfigText
    )

    $hostAlias = [string]$Profile.SshAlias
    if ([string]::IsNullOrWhiteSpace($ExpectedHost)) {
        $ExpectedHost = [string]$Profile.StaticIp
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedUser)) {
        $ExpectedUser = if ($Profile.SshUser) { [string]$Profile.SshUser } else { "adp" }
    }
    if ($ExpectedPort -le 0) {
        $ExpectedPort = if ($Profile.SshPort) { [int]$Profile.SshPort } else { 22 }
    }
    if ([string]::IsNullOrWhiteSpace($ExpectedKeyPath)) {
        $ExpectedKeyPath = [string]$Profile.SshKeyPath
    }

    $blockArgs = @{
        HostAlias = $hostAlias
    }
    if ($ConfigPath) {
        $blockArgs.ConfigPath = $ConfigPath
    }
    if ($PSBoundParameters.ContainsKey("ConfigText")) {
        $blockArgs.ConfigText = $ConfigText
    }
    $block = Get-ADPSshHostBlock @blockArgs

    $expectedKeyComparable = Normalize-ADPSshComparablePath -Path $ExpectedKeyPath
    $actual = if ($block.Exists) { Get-ADPSshBlockProperties -BlockText $block.BlockText } else { $null }
    $actualPort = if ($actual -and $actual.Port) { [int]$actual.Port } else { 22 }
    $mismatches = @()

    if (-not $block.Exists) {
        return [pscustomobject]@{
            HostAlias             = $hostAlias
            ConfigPath            = $block.ConfigPath
            Source                = $block.Source
            Status                = $block.Source
            OwnedByADP            = $false
            HasConflict           = $false
            ExpectedHost          = $ExpectedHost
            ExpectedUser          = $ExpectedUser
            ExpectedPort          = $ExpectedPort
            ExpectedIdentityFile  = $ExpectedKeyPath
            ActualHost            = ""
            ActualUser            = ""
            ActualPort            = $null
            ActualIdentityFile    = ""
            Mismatches            = @()
        }
    }

    if ($ExpectedHost -and -not $actual.HostName.Equals($ExpectedHost, [System.StringComparison]::OrdinalIgnoreCase)) {
        $mismatches += "HostName"
    }
    if ($ExpectedUser -and -not $actual.User.Equals($ExpectedUser, [System.StringComparison]::OrdinalIgnoreCase)) {
        $mismatches += "User"
    }
    if ($ExpectedPort -gt 0 -and $actualPort -ne $ExpectedPort) {
        $mismatches += "Port"
    }
    if ($expectedKeyComparable -and (Normalize-ADPSshComparablePath -Path $actual.IdentityFile) -ne $expectedKeyComparable) {
        $mismatches += "IdentityFile"
    }

    $ownedByADP = ($block.Source -eq "adp-marker")
    $status = if ($mismatches.Count -gt 0) {
        "alias-mismatch"
    } elseif ($ownedByADP) {
        "current-checkout"
    } else {
        "unmanaged-current"
    }

    return [pscustomobject]@{
        HostAlias             = $hostAlias
        ConfigPath            = $block.ConfigPath
        Source                = $block.Source
        Status                = $status
        OwnedByADP            = $ownedByADP
        HasConflict           = ($mismatches.Count -gt 0)
        ExpectedHost          = $ExpectedHost
        ExpectedUser          = $ExpectedUser
        ExpectedPort          = $ExpectedPort
        ExpectedIdentityFile  = $ExpectedKeyPath
        ActualHost            = $actual.HostName
        ActualUser            = $actual.User
        ActualPort            = $actualPort
        ActualIdentityFile    = $actual.IdentityFile
        Mismatches            = @($mismatches)
    }
}

function ConvertTo-ADPSshAliasOwnershipJson {
    param([object]$AliasStatus)

    if (-not $AliasStatus) {
        return $null
    }

    return [pscustomobject]@{
        HostAlias            = $AliasStatus.HostAlias
        Status               = $AliasStatus.Status
        Source               = $AliasStatus.Source
        OwnedByADP           = [bool]$AliasStatus.OwnedByADP
        HasConflict          = [bool]$AliasStatus.HasConflict
        ConfigPath           = $AliasStatus.ConfigPath
        ExpectedHost         = $AliasStatus.ExpectedHost
        ActualHost           = $AliasStatus.ActualHost
        ExpectedUser         = $AliasStatus.ExpectedUser
        ActualUser           = $AliasStatus.ActualUser
        ExpectedPort         = $AliasStatus.ExpectedPort
        ActualPort           = $AliasStatus.ActualPort
        ExpectedIdentityFile = $AliasStatus.ExpectedIdentityFile
        ActualIdentityFile   = $AliasStatus.ActualIdentityFile
        Mismatches           = @($AliasStatus.Mismatches)
    }
}

function Write-ADPSshAliasOwnershipGuidance {
    param(
        [Parameter(Mandatory = $true)]
        [object]$AliasStatus,
        [object]$CommandContext,
        [string]$Action = "diagnosis"
    )

    if (-not $AliasStatus.HasConflict) {
        return
    }

    if (-not $CommandContext -and (Get-Command Get-ADPCheckoutCommandContext -ErrorAction SilentlyContinue)) {
        $CommandContext = Get-ADPCheckoutCommandContext
    }

    $syncStart = if ($CommandContext) {
        Format-ADPCheckoutCommand -CommandContext $CommandContext -Arguments "sync start $($AliasStatus.HostAlias -replace '^adp-os-adp-', '')"
    } else {
        "adpos sync start"
    }
    $syncStatus = if ($CommandContext) {
        Format-ADPCheckoutCommand -CommandContext $CommandContext -Arguments "sync status"
    } else {
        "adpos sync status"
    }

    Write-UIHost -English "  SSH alias conflict: $($AliasStatus.HostAlias) is not bound to this runtime." -Chinese "  SSH alias 冲突: $($AliasStatus.HostAlias) 未绑定到当前 runtime。" -ForegroundColor Red
    Write-UIHost -English "  blocked/checked action: $Action" -Chinese "  已检查动作: $Action" -ForegroundColor Red
    Write-UIHost -English "  expected: HostName $($AliasStatus.ExpectedHost), User $($AliasStatus.ExpectedUser), Port $($AliasStatus.ExpectedPort), IdentityFile $($AliasStatus.ExpectedIdentityFile)" -Chinese "  期望: HostName $($AliasStatus.ExpectedHost), User $($AliasStatus.ExpectedUser), Port $($AliasStatus.ExpectedPort), IdentityFile $($AliasStatus.ExpectedIdentityFile)" -ForegroundColor DarkGray
    Write-UIHost -English "  actual:   HostName $($AliasStatus.ActualHost), User $($AliasStatus.ActualUser), Port $($AliasStatus.ActualPort), IdentityFile $($AliasStatus.ActualIdentityFile)" -Chinese "  实际:   HostName $($AliasStatus.ActualHost), User $($AliasStatus.ActualUser), Port $($AliasStatus.ActualPort), IdentityFile $($AliasStatus.ActualIdentityFile)" -ForegroundColor Yellow
    Write-UIHost -English "  source:   $($AliasStatus.Source) in $($AliasStatus.ConfigPath)" -Chinese "  来源:   $($AliasStatus.Source) in $($AliasStatus.ConfigPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  next:     run $syncStatus, then run $syncStart from the checkout that should own this runtime's SSH alias." -Chinese "  下一步:  先运行 $syncStatus，再从应该拥有该 runtime SSH alias 的 checkout 运行 $syncStart。" -ForegroundColor Yellow
    Write-UIHost -English "  note:     SSH aliases are global in the Windows user SSH config; two same-named runtimes cannot own the same alias at once." -Chinese "  说明:   SSH alias 位于 Windows 用户级 SSH config；两个同名 runtime 不能同时拥有同一个 alias。" -ForegroundColor Yellow
}
