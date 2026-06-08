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

function Get-PowerShellAst {
    param([string]$RelativePath)

    $tokens = $null
    $errors = $null
    $path = Join-Path $projectRoot $RelativePath
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors) {
        throw "$RelativePath had parser errors: $($errors[0].Message)"
    }

    return $ast
}

function Assert-LocalADPOSCommandReferencesResolve {
    param(
        [string]$Name,
        [System.Management.Automation.Language.Ast]$Ast
    )

    $defined = @{}
    $Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object {
        $defined[$_.Name] = $true
    }

    $Ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object {
        $commandName = $_.GetCommandName()
        if ($commandName -match '^(Get|Set|Add|Remove|Test|Install|Uninstall|Confirm|Resolve|New)-ADPOS' -and -not $defined.ContainsKey($commandName)) {
            throw "$Name referenced undefined local command '$commandName' at line $($_.Extent.StartLineNumber)"
        }
    }
}

function Assert-FunctionBodyNotContains {
    param(
        [string]$Name,
        [System.Management.Automation.Language.Ast]$Ast,
        [string]$FunctionName,
        [string[]]$ForbiddenPatterns
    )

    $functionAst = $Ast.Find({
        param($node)
        $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $FunctionName
    }, $true)
    if (-not $functionAst) {
        throw "$Name could not find function '$FunctionName'"
    }

    foreach ($pattern in $ForbiddenPatterns) {
        if ($functionAst.Extent.Text -match $pattern) {
            throw "$Name function '$FunctionName' contained forbidden pattern: $pattern"
        }
    }
}

$registration = Read-Text "scripts\adpos-registration.ps1"
$install = Read-Text "install.ps1"
$quickstart = Read-Text "cli\commands\quickstart.ps1"
$uninstall = Read-Text "uninstall.ps1"
$registrationAst = Get-PowerShellAst "scripts\adpos-registration.ps1"

Assert-LocalADPOSCommandReferencesResolve -Name "registration local ADPOS command references" -Ast $registrationAst
Assert-FunctionBodyNotContains -Name "registration pure decision helper" -Ast $registrationAst -FunctionName "Get-ADPOSRegistrationDecision" -ForbiddenPatterns @(
    '\[System\.Environment\]::SetEnvironmentVariable',
    '\[System\.Environment\]::GetEnvironmentVariable',
    '\bSet-Item\b',
    '\bRemove-Item\b',
    '\bNew-Item\b',
    '\bSet-Content\b',
    '\bRead-Host\b',
    '\bTest-Path\b',
    '\bGet-Content\b',
    '\$env:Path',
    '\bAdd-ADPOSPathEntry\b',
    '\bRemove-ADPOSPathEntry\b',
    '\bGet-ADPOSExistingRegistration\b'
)

Assert-Contains -Name "registration resolves LOCALAPPDATA before USERPROFILE fallback" -Text $registration -Pattern 'function\s+Get-ADPOSLocalAppData[\s\S]*\$env:LOCALAPPDATA[\s\S]*return\s+\$env:LOCALAPPDATA[\s\S]*\$env:USERPROFILE[\s\S]*"AppData\\Local"'
Assert-Contains -Name "registration uses dedicated ADP-OS user bin directory" -Text $registration -Pattern 'function\s+Get-ADPOSCommandBinPath[\s\S]*Join-Path\s+\(Get-ADPOSLocalAppData\)\s+"ADP-OS\\bin"'
Assert-Contains -Name "registration creates adpos command shim" -Text $registration -Pattern 'function\s+Get-ADPOSCommandShimPath[\s\S]*"adpos\.cmd"'
Assert-Contains -Name "registration defines ADPOS_HOME environment variable" -Text $registration -Pattern 'function\s+Get-ADPOSHomeVariableName[\s\S]*return "ADPOS_HOME"'
Assert-Contains -Name "registration detects existing ADPOS_HOME and PATH command homes" -Text $registration -Pattern 'function\s+Get-ADPOSExistingRegistration[\s\S]*GetEnvironmentVariable\(\$homeVariableName, "User"\)[\s\S]*GetEnvironmentVariable\(\$homeVariableName, "Machine"\)[\s\S]*Get-ADPOSPathCommandHomes'
Assert-Contains -Name "registration prompts before replacing another checkout" -Text $registration -Pattern 'function\s+Confirm-ADPOSRegistrationReplacement[\s\S]*Existing:[\s\S]*This one:[\s\S]*Read-Host "Replace the global adpos binding'
Assert-Contains -Name "registration exposes multi-checkout isolation guidance" -Text $registration -Pattern 'function\s+Get-ADPOSMultiCheckoutGuidance[\s\S]*configs\\local\.json[\s\S]*platform\.runtime_namespace[\s\S]*platform\.paths\.workspace_root[\s\S]*platform\.paths\.vm_store[\s\S]*topology\.<runtime>\.static_ip[\s\S]*doctor[\s\S]*status agent[\s\S]*sync status[\s\S]*up agent -Plan'
Assert-Contains -Name "registration exposes pure decision helper" -Text $registration -Pattern 'function\s+Get-ADPOSRegistrationDecision[\s\S]*RequiresConfirmation[\s\S]*Effects[\s\S]*kept-existing-global'
Assert-Contains -Name "registration can skip a different global binding" -Text $registration -Pattern 'Install-ADPOSCommandRegistration[\s\S]*\[switch\]\$NonInteractive[\s\S]*\[switch\]\$Force[\s\S]*Get-ADPOSRegistrationDecision[\s\S]*RequiresConfirmation[\s\S]*Confirm-ADPOSRegistrationReplacement[\s\S]*Get-ADPOSRegistrationDecision[\s\S]*if\s*\(\$decision\.Skipped\)'
Assert-Contains -Name "registration shim identifies ADP ownership" -Text $registration -Pattern 'REM ADP-OS global command shim'
Assert-Contains -Name "registration writes project home to user environment" -Text $registration -Pattern 'SetEnvironmentVariable\(\$homeVariableName, \$resolvedProjectRoot, "User"\)[\s\S]*Set-Item -Path "Env:\$homeVariableName"'
Assert-Contains -Name "registration shim delegates to repo-local adpos.cmd through ADPOS_HOME" -Text $registration -Pattern 'if ""%ADPOS_HOME%""==""""[\s\S]*call ""%ADPOS_HOME%\\adpos\.cmd"" %\*'
Assert-Contains -Name "registration shim self-uninstalls without synchronously deleting itself" -Text $registration -Pattern 'if /i ""%~1""==""uninstall"" goto ADPOS_UNINSTALL_FALLBACK[\s\S]*start """" /min cmd\.exe /d /c'
Assert-Contains -Name "registration shim has missing-repository uninstall fallback" -Text $registration -Pattern 'ADPOS_UNINSTALL_FALLBACK[\s\S]*SetEnvironmentVariable\(''ADPOS_HOME'',`\$null,''User''\)'
Assert-Contains -Name "registration writes user PATH only" -Text $registration -Pattern 'GetEnvironmentVariable\("Path", "User"\)[\s\S]*SetEnvironmentVariable\("Path", \$newUserPath, "User"\)'
Assert-Contains -Name "unregistration removes user PATH entry" -Text $registration -Pattern 'function\s+Remove-ADPOSPathEntry[\s\S]*SetEnvironmentVariable\("Path", \(\$keptUserEntries -join '';''\), "User"\)'
Assert-Contains -Name "unregistration normalizes target PATH entry" -Text $registration -Pattern 'function\s+Remove-ADPOSPathEntry[\s\S]*\$target\s*=\s*Normalize-ADPOSPath -Path \$Path'
Assert-Contains -Name "registration adds only command bin path" -Text $registration -Pattern 'Install-ADPOSCommandRegistration[\s\S]*Add-ADPOSPathEntry -Path \$binPath'
Assert-NotContains -Name "registration does not add project root to PATH" -Text $registration -Pattern 'Add-ADPOSPathEntry\s+-Path\s+\$resolvedProjectRoot|SetEnvironmentVariable\("Path", [^\r\n]*ProjectRoot'
Assert-Contains -Name "unregistration refuses non-ADP shim files" -Text $registration -Pattern 'Refusing to remove non-ADP file'
Assert-Contains -Name "unregistration removes the command bin from PATH" -Text $registration -Pattern 'Uninstall-ADPOSCommandRegistration[\s\S]*Remove-ADPOSPathEntry -Path \$binPath'
Assert-Contains -Name "unregistration removes ADPOS_HOME" -Text $registration -Pattern 'Uninstall-ADPOSCommandRegistration[\s\S]*SetEnvironmentVariable\(\$homeVariableName, \$null, "User"\)'

Assert-Contains -Name "install registers adpos by default" -Text $install -Pattern 'if\s*\(-not\s+\$NoRegisterCommand\)\s*\{[\s\S]*Install-ADPOSCommandRegistration'
Assert-Contains -Name "install passes non-interactive and force registration switches" -Text $install -Pattern '\[switch\]\$NonInteractive[\s\S]*\[switch\]\$RegisterCommandForce[\s\S]*Install-ADPOSCommandRegistration[\s\S]*-NonInteractive:\$NonInteractive[\s\S]*-Force:\$RegisterCommandForce'
Assert-Contains -Name "install supports NoRegisterCommand skip" -Text $install -Pattern '\[switch\]\$NoRegisterCommand[\s\S]*Global command registration skipped by -NoRegisterCommand'
Assert-Contains -Name "install guides kept global binding to local multi-checkout validation" -Text $install -Pattern 'if\s*\(\$Registration\.Skipped\)[\s\S]*Use this checkout locally: \.\\adpos\.cmd[\s\S]*Write-InstallMultiCheckoutGuidance[\s\S]*Get-ADPOSMultiCheckoutGuidance[\s\S]*Multi-checkout isolation[\s\S]*Validate this checkout'
Assert-Contains -Name "quickstart propagates NoRegisterCommand to install" -Text $quickstart -Pattern '\[switch\]\$NoRegisterCommand[\s\S]*\$installArgs\s*\+=\s*"-NoRegisterCommand"'
Assert-Contains -Name "quickstart passes setup mode to registration" -Text $quickstart -Pattern '\$installArgs\s*\+=\s*"-NonInteractive"[\s\S]*\$installArgs\s*\+=\s*"-RegisterCommandForce"[\s\S]*Install-ADPOSCommandRegistration[\s\S]*-NonInteractive:\$NonInteractive[\s\S]*-Force:\$Force'
Assert-Contains -Name "quickstart guides kept global binding to local multi-checkout validation" -Text $quickstart -Pattern 'if\s*\(\$Registration\.Skipped\)[\s\S]*Use this checkout locally: \.\\adpos\.cmd[\s\S]*Write-QuickstartMultiCheckoutGuidance[\s\S]*Get-ADPOSMultiCheckoutGuidance[\s\S]*Multi-checkout isolation[\s\S]*Validate this checkout'
Assert-Contains -Name "uninstall script delegates to registration uninstaller" -Text $uninstall -Pattern 'scripts\\adpos-registration\.ps1[\s\S]*Uninstall-ADPOSCommandRegistration'
Assert-Contains -Name "uninstall default is non-destructive" -Text $uninstall -Pattern 'No VMs, workspace files, ISO cache, local tools, logs, or repository files were removed'

Write-Output "adpos registration contract tests OK"
