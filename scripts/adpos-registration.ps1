# ADP-OS command registration helpers.
# Registers a user-level `adpos` shim without adding the repository root to PATH.

function Get-ADPOSLocalAppData {
    if ($env:LOCALAPPDATA) {
        return $env:LOCALAPPDATA
    }

    if ($env:USERPROFILE) {
        return (Join-Path $env:USERPROFILE "AppData\Local")
    }

    throw "LOCALAPPDATA and USERPROFILE are both unavailable; cannot resolve ADP-OS command directory."
}

function Get-ADPOSCommandBinPath {
    return (Join-Path (Get-ADPOSLocalAppData) "ADP-OS\bin")
}

function Get-ADPOSCommandShimPath {
    return (Join-Path (Get-ADPOSCommandBinPath) "adpos.cmd")
}

function Get-ADPOSHomeVariableName {
    return "ADPOS_HOME"
}

function Normalize-ADPOSPath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }

    try {
        return ([System.IO.Path]::GetFullPath($Path)).TrimEnd('\', '/')
    } catch {
        return $Path.TrimEnd('\', '/')
    }
}

function Test-ADPOSPathListContains {
    param(
        [string]$PathList,
        [string]$Path
    )

    $target = Normalize-ADPOSPath -Path $Path
    foreach ($entry in (($PathList -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if ([string]::Equals((Normalize-ADPOSPath -Path $entry), $target, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-ADPOSPathCommandHomes {
    param([string]$PathList)

    $homes = @()
    foreach ($entry in (($PathList -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $normalizedEntry = Normalize-ADPOSPath -Path $entry
        if ([string]::IsNullOrWhiteSpace($normalizedEntry)) {
            continue
        }

        $repoCommand = Join-Path $normalizedEntry "adpos.cmd"
        $legacyCli = Join-Path $normalizedEntry "cli\adp.ps1"
        $adposCli = Join-Path $normalizedEntry "cli\adpos.ps1"
        if ((Test-Path -LiteralPath $repoCommand) -and ((Test-Path -LiteralPath $legacyCli) -or (Test-Path -LiteralPath $adposCli))) {
            $homes += $normalizedEntry
        }
    }

    return @($homes | Select-Object -Unique)
}

function Get-ADPOSExistingRegistration {
    param([string]$ProjectRoot)

    $resolvedProjectRoot = Normalize-ADPOSPath -Path $ProjectRoot
    $binPath = Get-ADPOSCommandBinPath
    $shimPath = Get-ADPOSCommandShimPath
    $homeVariableName = Get-ADPOSHomeVariableName
    $userHome = [System.Environment]::GetEnvironmentVariable($homeVariableName, "User")
    $machineHome = [System.Environment]::GetEnvironmentVariable($homeVariableName, "Machine")
    $processHome = [System.Environment]::GetEnvironmentVariable($homeVariableName, "Process")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPathHomes = @(Get-ADPOSPathCommandHomes -PathList $userPath)
    $machinePathHomes = @(Get-ADPOSPathCommandHomes -PathList $machinePath)
    $pathHomes = @($userPathHomes + $machinePathHomes | Where-Object { $_ } | Select-Object -Unique)
    $effectiveHome = $null

    if (-not [string]::IsNullOrWhiteSpace($userHome)) {
        $effectiveHome = $userHome
    } elseif (-not [string]::IsNullOrWhiteSpace($machineHome)) {
        $effectiveHome = $machineHome
    } elseif ($pathHomes.Count -gt 0) {
        $effectiveHome = $pathHomes[0]
    }

    $normalizedEffectiveHome = Normalize-ADPOSPath -Path $effectiveHome
    $shimOwned = $false
    if (Test-Path -LiteralPath $shimPath) {
        $shimContent = Get-Content -LiteralPath $shimPath -Raw -ErrorAction SilentlyContinue
        $shimOwned = ($shimContent -match "ADP-OS global command shim")
    }

    $isDifferentHome = $false
    if (-not [string]::IsNullOrWhiteSpace($normalizedEffectiveHome)) {
        $isDifferentHome = -not [string]::Equals($normalizedEffectiveHome, $resolvedProjectRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }

    return [pscustomobject]@{
        Home              = $normalizedEffectiveHome
        UserHome          = Normalize-ADPOSPath -Path $userHome
        MachineHome       = Normalize-ADPOSPath -Path $machineHome
        ProcessHome       = Normalize-ADPOSPath -Path $processHome
        UserPathHomes     = $userPathHomes
        MachinePathHomes  = $machinePathHomes
        PathHomes         = $pathHomes
        UserPathHasBin    = Test-ADPOSPathListContains -PathList $userPath -Path $binPath
        MachinePathHasBin = Test-ADPOSPathListContains -PathList $machinePath -Path $binPath
        ShimPath          = $shimPath
        ShimExists        = Test-Path -LiteralPath $shimPath
        ShimOwned         = $shimOwned
        IsDifferentHome   = $isDifferentHome
    }
}

function Confirm-ADPOSRegistrationReplacement {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ExistingRegistration,

        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    Write-Host ""
    Write-Host "A global adpos command is already registered for another ADP-OS checkout." -ForegroundColor Yellow
    Write-Host "  Existing: $($ExistingRegistration.Home)" -ForegroundColor DarkGray
    Write-Host "  This one: $ProjectRoot" -ForegroundColor DarkGray
    Write-Host ""
    $answer = Read-Host "Replace the global adpos binding with this checkout? [y/N]"
    return ($answer -match '^(y|yes)$')
}

function Get-ADPOSMultiCheckoutGuidance {
    param([string]$LocalCommand = ".\adpos.cmd")

    return [pscustomobject]@{
        ConfigPath         = "configs\local.json"
        ConfigKeys         = @(
            "platform.runtime_namespace",
            "platform.paths.workspace_root",
            "platform.paths.vm_store",
            "topology.<runtime>.static_ip"
        )
        ValidationCommands = @(
            "$LocalCommand doctor",
            "$LocalCommand status agent",
            "$LocalCommand sync status",
            "$LocalCommand up agent -Plan"
        )
    }
}

function Get-ADPOSRegistrationDecision {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ExistingRegistration,

        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [switch]$NonInteractive,
        [switch]$Force,
        [object]$ReplacementAccepted = $null
    )

    $resolvedProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    $previousHome = $ExistingRegistration.Home
    $isDifferentHome = [bool]$ExistingRegistration.IsDifferentHome
    $registrationEffects = @("create-bin", "write-shim", "set-user-home", "set-process-home", "add-user-path")

    if ($isDifferentHome -and -not $Force -and -not $NonInteractive -and $null -eq $ReplacementAccepted) {
        return [pscustomobject]@{
            Home                 = $resolvedProjectRoot
            PreviousHome         = $previousHome
            ShouldRegister       = $false
            Registered           = $false
            RequiresConfirmation = $true
            Replaced             = $false
            Skipped              = $false
            Reason               = "requires-confirmation"
            Effects              = @()
        }
    }

    if ($isDifferentHome -and -not $Force -and ($NonInteractive -or -not [bool]$ReplacementAccepted)) {
        return [pscustomobject]@{
            Home                 = $resolvedProjectRoot
            PreviousHome         = $previousHome
            ShouldRegister       = $false
            Registered           = $false
            RequiresConfirmation = $false
            Replaced             = $false
            Skipped              = $true
            Reason               = "kept-existing-global"
            Effects              = @()
        }
    }

    return [pscustomobject]@{
        Home                 = $resolvedProjectRoot
        PreviousHome         = $previousHome
        ShouldRegister       = $true
        Registered           = $true
        RequiresConfirmation = $false
        Replaced             = $isDifferentHome
        Skipped              = $false
        Reason               = ""
        Effects              = $registrationEffects
    }
}

function Get-ADPOSUninstallDecision {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ExistingRegistration,

        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [switch]$Force
    )

    $resolvedProjectRoot = Normalize-ADPOSPath -Path ([System.IO.Path]::GetFullPath($ProjectRoot))
    $existingHome = Normalize-ADPOSPath -Path $ExistingRegistration.Home
    $differentHome = $false
    if (-not [string]::IsNullOrWhiteSpace($existingHome)) {
        $differentHome = -not [string]::Equals($existingHome, $resolvedProjectRoot, [System.StringComparison]::OrdinalIgnoreCase)
    }

    if ([bool]$ExistingRegistration.ShimExists -and -not [bool]$ExistingRegistration.ShimOwned) {
        return [pscustomobject]@{
            Home            = $resolvedProjectRoot
            RegisteredHome  = $existingHome
            ShouldUninstall = $false
            Refused         = $true
            Forced          = [bool]$Force
            Reason          = "non-adp-shim"
            Effects         = @()
        }
    }

    if ($differentHome -and -not $Force) {
        return [pscustomobject]@{
            Home            = $resolvedProjectRoot
            RegisteredHome  = $existingHome
            ShouldUninstall = $false
            Refused         = $true
            Forced          = $false
            Reason          = "different-home"
            Effects         = @()
        }
    }

    $effects = @()
    if ([bool]$ExistingRegistration.ShimExists -and [bool]$ExistingRegistration.ShimOwned) {
        $effects += "remove-shim"
    }
    if ([bool]$ExistingRegistration.UserPathHasBin) {
        $effects += "remove-user-path"
    }

    $userHome = Normalize-ADPOSPath -Path $ExistingRegistration.UserHome
    if (-not [string]::IsNullOrWhiteSpace($userHome) -and ($Force -or [string]::Equals($userHome, $resolvedProjectRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
        $effects += "remove-user-home"
    }

    $processHome = Normalize-ADPOSPath -Path $ExistingRegistration.ProcessHome
    if (-not [string]::IsNullOrWhiteSpace($processHome) -and ($Force -or [string]::Equals($processHome, $resolvedProjectRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
        $effects += "remove-process-home"
    }

    $reason = ""
    if ($effects.Count -eq 0) {
        $reason = "not-registered"
    }

    return [pscustomobject]@{
        Home            = $resolvedProjectRoot
        RegisteredHome  = $existingHome
        ShouldUninstall = $true
        Refused         = $false
        Forced          = [bool]$Force
        Reason          = $reason
        Effects         = $effects
    }
}

function Add-ADPOSPathEntry {
    param([string]$Path)

    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    if (-not (Test-ADPOSPathListContains -PathList $userPath -Path $Path)) {
        $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $Path } else { "$userPath;$Path" }
        [System.Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    }

    if (-not (Test-ADPOSPathListContains -PathList $env:Path -Path $Path)) {
        $env:Path = if ([string]::IsNullOrWhiteSpace($env:Path)) { $Path } else { "$env:Path;$Path" }
    }
}

function Remove-ADPOSPathEntry {
    param([string]$Path)

    $target = Normalize-ADPOSPath -Path $Path
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $keptUserEntries = @()
    foreach ($entry in (($userPath -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if (-not [string]::Equals((Normalize-ADPOSPath -Path $entry), $target, [System.StringComparison]::OrdinalIgnoreCase)) {
            $keptUserEntries += $entry
        }
    }
    [System.Environment]::SetEnvironmentVariable("Path", ($keptUserEntries -join ';'), "User")

    $keptProcessEntries = @()
    foreach ($entry in (($env:Path -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        if (-not [string]::Equals((Normalize-ADPOSPath -Path $entry), $target, [System.StringComparison]::OrdinalIgnoreCase)) {
            $keptProcessEntries += $entry
        }
    }
    $env:Path = ($keptProcessEntries -join ';')
}

function Install-ADPOSCommandRegistration {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [switch]$NonInteractive,
        [switch]$Force
    )

    $resolvedProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    $repoCommand = Join-Path $resolvedProjectRoot "adpos.cmd"
    if (-not (Test-Path -LiteralPath $repoCommand)) {
        throw "Cannot register adpos: repo-local adpos.cmd was not found at $repoCommand"
    }

    $binPath = Get-ADPOSCommandBinPath
    $shimPath = Get-ADPOSCommandShimPath
    $homeVariableName = Get-ADPOSHomeVariableName
    $existingRegistration = Get-ADPOSExistingRegistration -ProjectRoot $resolvedProjectRoot
    $decision = Get-ADPOSRegistrationDecision -ExistingRegistration $existingRegistration -ProjectRoot $resolvedProjectRoot -NonInteractive:$NonInteractive -Force:$Force

    if ($decision.RequiresConfirmation) {
        $replacementAccepted = Confirm-ADPOSRegistrationReplacement -ExistingRegistration $existingRegistration -ProjectRoot $resolvedProjectRoot
        $decision = Get-ADPOSRegistrationDecision -ExistingRegistration $existingRegistration -ProjectRoot $resolvedProjectRoot -NonInteractive:$NonInteractive -Force:$Force -ReplacementAccepted $replacementAccepted
    }

    if ($decision.Skipped) {
        return [pscustomobject]@{
            Command      = "adpos"
            BinPath      = $binPath
            ShimPath     = $shimPath
            Home         = $decision.Home
            PreviousHome = $decision.PreviousHome
            Registered   = $false
            Replaced     = $decision.Replaced
            Skipped      = $true
            Reason       = $decision.Reason
        }
    }

    New-Item -ItemType Directory -Path $binPath -Force | Out-Null

    $shimLines = @(
        "@echo off",
        "REM ADP-OS global command shim. Generated by setup.cmd.",
        "setlocal",
        "if ""%ADPOS_HOME%""=="""" (",
        "    if /i ""%~1""==""uninstall"" goto ADPOS_UNINSTALL_FALLBACK",
        "    echo ADP-OS command home is not configured.",
        "    echo Re-run setup.cmd from the cloned ADP-OS repository to repair adpos.",
        "    exit /b 1",
        ")",
        "if not exist ""%ADPOS_HOME%\adpos.cmd"" (",
        "    if /i ""%~1""==""uninstall"" goto ADPOS_UNINSTALL_FALLBACK",
        "    echo ADP-OS command target not found: %ADPOS_HOME%",
        "    echo Re-run setup.cmd from the cloned ADP-OS repository to repair adpos.",
        "    exit /b 1",
        ")",
        "if /i ""%~1""==""uninstall"" goto ADPOS_UNINSTALL_FALLBACK",
        "call ""%ADPOS_HOME%\adpos.cmd"" %*",
        "exit /b %ERRORLEVEL%",
        ":ADPOS_UNINSTALL_FALLBACK",
        "if not defined LOCALAPPDATA if defined USERPROFILE set ""LOCALAPPDATA=%USERPROFILE%\AppData\Local""",
        "set ""ADPOS_BIN=%LOCALAPPDATA%\ADP-OS\bin""",
        "set ""ADPOS_SHIM=%ADPOS_BIN%\adpos.cmd""",
        "set ""ADPOS_WINPS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe""",
        "if not exist ""%ADPOS_WINPS%"" set ""ADPOS_WINPS=powershell.exe""",
        """%ADPOS_WINPS%"" -NoProfile -ExecutionPolicy Bypass -Command ""`$bin=`$env:ADPOS_BIN; `$path=[Environment]::GetEnvironmentVariable('Path','User'); `$new=((`$path -split ';') | Where-Object { `$_ -and ((`$_ -replace '[\\/]+$','') -ine (`$bin -replace '[\\/]+$','')) }) -join ';'; [Environment]::SetEnvironmentVariable('Path',`$new,'User'); [Environment]::SetEnvironmentVariable('ADPOS_HOME',`$null,'User')""",
        "if errorlevel 1 exit /b %ERRORLEVEL%",
        "start """" /min cmd.exe /d /c ""ping 127.0.0.1 -n 2 >nul & del /f /q """"%ADPOS_SHIM%"""" >nul 2>nul & rd """"%ADPOS_BIN%"""" 2>nul""",
        "echo Removed global command: adpos",
        "echo No VMs, workspace files, ISO cache, local tools, logs, or repository files were removed.",
        "exit /b 0"
    )
    Set-Content -LiteralPath $shimPath -Value $shimLines -Encoding ascii

    [System.Environment]::SetEnvironmentVariable($homeVariableName, $resolvedProjectRoot, "User")
    Set-Item -Path "Env:$homeVariableName" -Value $resolvedProjectRoot
    Add-ADPOSPathEntry -Path $binPath

    return [pscustomobject]@{
        Command      = "adpos"
        BinPath      = $binPath
        ShimPath     = $shimPath
        Home         = $resolvedProjectRoot
        PreviousHome = $decision.PreviousHome
        Registered   = $true
        Replaced     = $decision.Replaced
        Skipped      = $false
        Reason       = ""
    }
}

function Uninstall-ADPOSCommandRegistration {
    param(
        [string]$ProjectRoot = (Split-Path $PSScriptRoot -Parent),
        [switch]$Force
    )

    $resolvedProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)
    $binPath = Get-ADPOSCommandBinPath
    $shimPath = Get-ADPOSCommandShimPath
    $homeVariableName = Get-ADPOSHomeVariableName
    $existingRegistration = Get-ADPOSExistingRegistration -ProjectRoot $resolvedProjectRoot
    $decision = Get-ADPOSUninstallDecision -ExistingRegistration $existingRegistration -ProjectRoot $resolvedProjectRoot -Force:$Force

    if ($decision.Refused) {
        if ($decision.Reason -eq "different-home") {
            throw "Refusing to uninstall global adpos registered for another ADP-OS checkout: $($decision.RegisteredHome). Run uninstall from that checkout, or pass -Force to remove this global binding."
        }

        if ($decision.Reason -eq "non-adp-shim") {
            throw "Refusing to remove non-ADP file at $shimPath"
        }

        throw "Refusing to uninstall global adpos registration: $($decision.Reason)"
    }

    $removedShim = $false
    $removedHome = $false

    if (Test-Path -LiteralPath $shimPath) {
        $content = Get-Content -LiteralPath $shimPath -Raw -ErrorAction SilentlyContinue
        if ($content -match "ADP-OS global command shim") {
            Remove-Item -LiteralPath $shimPath -Force
            $removedShim = $true
        } else {
            throw "Refusing to remove non-ADP file at $shimPath"
        }
    }

    Remove-ADPOSPathEntry -Path $binPath
    $userHome = Normalize-ADPOSPath -Path ([System.Environment]::GetEnvironmentVariable($homeVariableName, "User"))
    if (-not [string]::IsNullOrWhiteSpace($userHome) -and ($Force -or [string]::Equals($userHome, (Normalize-ADPOSPath -Path $resolvedProjectRoot), [System.StringComparison]::OrdinalIgnoreCase))) {
        [System.Environment]::SetEnvironmentVariable($homeVariableName, $null, "User")
        $removedHome = $true
    }

    $processHome = Normalize-ADPOSPath -Path (Get-Item -Path "Env:$homeVariableName" -ErrorAction SilentlyContinue).Value
    if (-not [string]::IsNullOrWhiteSpace($processHome) -and ($Force -or [string]::Equals($processHome, (Normalize-ADPOSPath -Path $resolvedProjectRoot), [System.StringComparison]::OrdinalIgnoreCase))) {
        Remove-Item -Path "Env:$homeVariableName" -ErrorAction SilentlyContinue
    }

    if ((Test-Path -LiteralPath $binPath) -and -not (Get-ChildItem -LiteralPath $binPath -Force | Select-Object -First 1)) {
        Remove-Item -LiteralPath $binPath -Force
    }

    return [pscustomobject]@{
        Command     = "adpos"
        BinPath     = $binPath
        ShimPath    = $shimPath
        RemovedShim = $removedShim
        RemovedHome = $removedHome
        Forced      = [bool]$Force
        Reason      = $decision.Reason
    }
}
