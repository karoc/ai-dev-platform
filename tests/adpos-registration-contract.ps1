# ADP-OS adpos registration contract checks.
# Static by design: do not invoke registration helpers because User PATH is real machine state.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

function Read-Text {
    param([string]$RelativePath)
    return Get-Content -LiteralPath (Join-Path $projectRoot $RelativePath) -Raw -Encoding UTF8
}

function Assert-Contains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "$Name did not contain expected pattern: $Pattern"
    }
}

function Assert-NotContains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )

    if ($Text -match $Pattern) {
        throw "$Name contained forbidden pattern: $Pattern"
    }
}

$registration = Read-Text "scripts\adpos-registration.ps1"
$install = Read-Text "install.ps1"
$quickstart = Read-Text "cli\commands\quickstart.ps1"
$uninstall = Read-Text "uninstall.ps1"

Assert-Contains -Name "registration resolves LOCALAPPDATA before USERPROFILE fallback" -Text $registration -Pattern 'function\s+Get-ADPOSLocalAppData[\s\S]*\$env:LOCALAPPDATA[\s\S]*return\s+\$env:LOCALAPPDATA[\s\S]*\$env:USERPROFILE[\s\S]*"AppData\\Local"'
Assert-Contains -Name "registration uses dedicated ADP-OS user bin directory" -Text $registration -Pattern 'function\s+Get-ADPOSCommandBinPath[\s\S]*Join-Path\s+\(Get-ADPOSLocalAppData\)\s+"ADP-OS\\bin"'
Assert-Contains -Name "registration creates adpos command shim" -Text $registration -Pattern 'function\s+Get-ADPOSCommandShimPath[\s\S]*"adpos\.cmd"'
Assert-Contains -Name "registration defines ADPOS_HOME environment variable" -Text $registration -Pattern 'function\s+Get-ADPOSHomeVariableName[\s\S]*return "ADPOS_HOME"'
Assert-Contains -Name "registration detects existing ADPOS_HOME and PATH command homes" -Text $registration -Pattern 'function\s+Get-ADPOSExistingRegistration[\s\S]*GetEnvironmentVariable\(\$homeVariableName, "User"\)[\s\S]*GetEnvironmentVariable\(\$homeVariableName, "Machine"\)[\s\S]*Get-ADPOSPathCommandHomes'
Assert-Contains -Name "registration prompts before replacing another checkout" -Text $registration -Pattern 'function\s+Confirm-ADPOSRegistrationReplacement[\s\S]*Existing:[\s\S]*This one:[\s\S]*Read-Host "Replace the global adpos binding'
Assert-Contains -Name "registration can skip a different global binding" -Text $registration -Pattern 'Install-ADPOSCommandRegistration[\s\S]*\[switch\]\$NonInteractive[\s\S]*\[switch\]\$Force[\s\S]*IsDifferentHome[\s\S]*-not \$Force[\s\S]*Skipped\s+=\s+\$true[\s\S]*kept-existing-global'
Assert-Contains -Name "registration shim identifies ADP ownership" -Text $registration -Pattern 'REM ADP-OS global command shim'
Assert-Contains -Name "registration writes project home to user environment" -Text $registration -Pattern 'SetEnvironmentVariable\(\$homeVariableName, \$resolvedProjectRoot, "User"\)[\s\S]*Set-Item -Path "Env:\$homeVariableName"'
Assert-Contains -Name "registration shim delegates to repo-local adpos.cmd through ADPOS_HOME" -Text $registration -Pattern 'if ""%ADPOS_HOME%""==""""[\s\S]*call ""%ADPOS_HOME%\\adpos\.cmd"" %\*'
Assert-Contains -Name "registration shim self-uninstalls without synchronously deleting itself" -Text $registration -Pattern 'if /i ""%~1""==""uninstall"" goto ADPOS_UNINSTALL_FALLBACK[\s\S]*start """" /min cmd\.exe /d /c'
Assert-Contains -Name "registration shim has missing-repository uninstall fallback" -Text $registration -Pattern 'ADPOS_UNINSTALL_FALLBACK[\s\S]*SetEnvironmentVariable\(''ADPOS_HOME'',`\$null,''User''\)'
Assert-Contains -Name "registration writes user PATH only" -Text $registration -Pattern 'GetEnvironmentVariable\("Path", "User"\)[\s\S]*SetEnvironmentVariable\("Path", \$newUserPath, "User"\)'
Assert-Contains -Name "unregistration removes user PATH entry" -Text $registration -Pattern 'function\s+Remove-ADPOSPathEntry[\s\S]*SetEnvironmentVariable\("Path", \(\$keptUserEntries -join '';''\), "User"\)'
Assert-Contains -Name "registration adds only command bin path" -Text $registration -Pattern 'Install-ADPOSCommandRegistration[\s\S]*Add-ADPOSPathEntry -Path \$binPath'
Assert-NotContains -Name "registration does not add project root to PATH" -Text $registration -Pattern 'Add-ADPOSPathEntry\s+-Path\s+\$resolvedProjectRoot|SetEnvironmentVariable\("Path", [^\r\n]*ProjectRoot'
Assert-Contains -Name "unregistration refuses non-ADP shim files" -Text $registration -Pattern 'Refusing to remove non-ADP file'
Assert-Contains -Name "unregistration removes the command bin from PATH" -Text $registration -Pattern 'Uninstall-ADPOSCommandRegistration[\s\S]*Remove-ADPOSPathEntry -Path \$binPath'
Assert-Contains -Name "unregistration removes ADPOS_HOME" -Text $registration -Pattern 'Uninstall-ADPOSCommandRegistration[\s\S]*SetEnvironmentVariable\(\$homeVariableName, \$null, "User"\)'

Assert-Contains -Name "install registers adpos by default" -Text $install -Pattern 'if\s*\(-not\s+\$NoRegisterCommand\)\s*\{[\s\S]*Install-ADPOSCommandRegistration'
Assert-Contains -Name "install passes non-interactive and force registration switches" -Text $install -Pattern '\[switch\]\$NonInteractive[\s\S]*\[switch\]\$RegisterCommandForce[\s\S]*Install-ADPOSCommandRegistration[\s\S]*-NonInteractive:\$NonInteractive[\s\S]*-Force:\$RegisterCommandForce'
Assert-Contains -Name "install supports NoRegisterCommand skip" -Text $install -Pattern '\[switch\]\$NoRegisterCommand[\s\S]*Global command registration skipped by -NoRegisterCommand'
Assert-Contains -Name "quickstart propagates NoRegisterCommand to install" -Text $quickstart -Pattern '\[switch\]\$NoRegisterCommand[\s\S]*\$installArgs\s*\+=\s*"-NoRegisterCommand"'
Assert-Contains -Name "quickstart passes setup mode to registration" -Text $quickstart -Pattern '\$installArgs\s*\+=\s*"-NonInteractive"[\s\S]*\$installArgs\s*\+=\s*"-RegisterCommandForce"[\s\S]*Install-ADPOSCommandRegistration[\s\S]*-NonInteractive:\$NonInteractive[\s\S]*-Force:\$Force'
Assert-Contains -Name "uninstall script delegates to registration uninstaller" -Text $uninstall -Pattern 'scripts\\adpos-registration\.ps1[\s\S]*Uninstall-ADPOSCommandRegistration'
Assert-Contains -Name "uninstall default is non-destructive" -Text $uninstall -Pattern 'No VMs, workspace files, ISO cache, local tools, logs, or repository files were removed'

Write-Output "adpos registration contract tests OK"
