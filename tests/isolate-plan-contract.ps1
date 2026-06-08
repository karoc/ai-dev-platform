# ADP-OS isolate plan contract checks.
# Ensures checkout isolation planning is preview-only and actionable.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$cliPath = Join-Path $projectRoot "cli\adp.ps1"
$localConfigPath = Join-Path $projectRoot "configs\local.json"

function Get-TestPwshPath {
    $processPath = try { (Get-Process -Id $PID).Path } catch { $null }
    if ($processPath) {
        return $processPath
    }

    $pwshCommand = Get-Command pwsh -ErrorAction SilentlyContinue
    if ($pwshCommand) {
        return $pwshCommand.Source
    }

    $pwshExeCommand = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($pwshExeCommand) {
        return $pwshExeCommand.Source
    }

    throw "Cannot resolve pwsh executable path for isolate plan contract checks."
}

function Assert-Contains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "$Name did not contain expected pattern: $Pattern`nOutput:`n$Text"
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

function Assert-ExitCode {
    param(
        [string]$Name,
        [int]$Actual,
        [int]$Expected
    )

    if ($Actual -ne $Expected) {
        throw "$Name expected exit code $Expected but got $Actual"
    }
}

function Get-OptionalFileHash {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return ""
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-ProductionFileAst {
    param([string]$RelativePath)

    $path = Join-Path $projectRoot $RelativePath
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw "$RelativePath has parse errors: $($errors.Message -join '; ')"
    }

    return $ast
}

function Assert-ProductionFileDoesNotCallCommand {
    param(
        [string]$RelativePath,
        [string[]]$ForbiddenCommands
    )

    $ast = Get-ProductionFileAst -RelativePath $RelativePath
    $calls = @(
        $ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $ForbiddenCommands -contains $node.GetCommandName()
        }, $true)
    )

    if ($calls.Count -gt 0) {
        $names = @($calls | ForEach-Object { $_.GetCommandName() } | Sort-Object -Unique)
        throw "$RelativePath calls forbidden write or host-mutation commands: $($names -join ', ')"
    }
}

$isolateCommandText = Get-Content -LiteralPath (Join-Path $projectRoot "cli\commands\isolate.ps1") -Raw -Encoding UTF8
$isolationPlannerText = Get-Content -LiteralPath (Join-Path $projectRoot "core\diagnostics\checkout-isolation.ps1") -Raw -Encoding UTF8
$forbiddenMutationCommands = @(
    "Set-Content",
    "Add-Content",
    "Out-File",
    "Copy-Item",
    "New-Item",
    "Remove-Item",
    "Rename-Item",
    "Move-Item",
    "Set-Item",
    "Set-ItemProperty",
    "New-ItemProperty",
    "Remove-ItemProperty",
    "Install-ADPOSCommandRegistration",
    "Uninstall-ADPOSCommandRegistration",
    "Add-ADPOSPathEntry",
    "Remove-ADPOSPathEntry",
    "Set-LocalNetworkConfig",
    "Initialize-VMware",
    "Start-VM",
    "Stop-VM"
)

Assert-ProductionFileDoesNotCallCommand -RelativePath "cli\commands\isolate.ps1" -ForbiddenCommands $forbiddenMutationCommands
Assert-ProductionFileDoesNotCallCommand -RelativePath "core\diagnostics\checkout-isolation.ps1" -ForbiddenCommands $forbiddenMutationCommands
Assert-NotContains -Name "isolate command does not source VMware adapter" -Text $isolateCommandText -Pattern 'adapters\\windows\\vmware\\vmware\.ps1|Initialize-VMware'
Assert-NotContains -Name "isolate command does not register global command" -Text $isolateCommandText -Pattern 'SetEnvironmentVariable|ADPOS_HOME|Install-ADPOSCommandRegistration'
Assert-NotContains -Name "isolation planner does not register global command" -Text $isolationPlannerText -Pattern 'SetEnvironmentVariable|ADPOS_HOME|Install-ADPOSCommandRegistration'

$pwsh = Get-TestPwshPath
$beforeHash = Get-OptionalFileHash -Path $localConfigPath
$global:LASTEXITCODE = 0
$output = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $cliPath isolate -Plan -Namespace v2 2>&1 | Out-String
$exitCode = $LASTEXITCODE
$afterHash = Get-OptionalFileHash -Path $localConfigPath

Assert-ExitCode -Name "adpos isolate plan" -Actual $exitCode -Expected 0
Assert-Contains -Name "isolate plan title" -Text $output -Pattern "ADP-OS Checkout Isolation Plan"
Assert-Contains -Name "isolate plan local config path" -Text $output -Pattern "configs\\local\.json"
Assert-Contains -Name "isolate plan namespace" -Text $output -Pattern "platform\.runtime_namespace"
Assert-Contains -Name "isolate plan workspace root" -Text $output -Pattern "platform\.paths\.workspace_root"
Assert-Contains -Name "isolate plan VM store" -Text $output -Pattern "platform\.paths\.vm_store"
Assert-Contains -Name "isolate plan provider VM store" -Text $output -Pattern "platform\.provider\.config\.vm_store"
Assert-Contains -Name "isolate plan runtime static IP" -Text $output -Pattern "topology\.agent\.static_ip"
Assert-Contains -Name "isolate plan runtime resource preview" -Text $output -Pattern "Runtime resource preview"
Assert-Contains -Name "isolate plan namespaced resource" -Text $output -Pattern "resource=v2-agent"
Assert-Contains -Name "isolate plan namespaced VM" -Text $output -Pattern "VM=adp-v2-agent"
Assert-Contains -Name "isolate plan namespaced SSH alias" -Text $output -Pattern "adp-os-adp-v2-agent"
Assert-Contains -Name "isolate plan namespaced Mutagen session" -Text $output -Pattern "Mutagen session:\s+adp-v2-agent"
Assert-Contains -Name "isolate plan JSON snippet" -Text $output -Pattern '"runtime_namespace":\s*"v2"'
Assert-Contains -Name "isolate plan validation commands" -Text $output -Pattern "up agent -Plan"
Assert-Contains -Name "isolate plan no mutation statement" -Text $output -Pattern "Plan only: configs\\\\local\.json will not be changed"
Assert-Contains -Name "isolate plan no host mutation statement" -Text $output -Pattern "No files, VMs, SSH aliases, sync sessions, PATH entries, or global adpos bindings were changed"

$global:LASTEXITCODE = 0
$invalidNamespaceOutput = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $cliPath isolate -Plan -Namespace default 2>&1 | Out-String
$invalidNamespaceExitCode = $LASTEXITCODE
Assert-ExitCode -Name "adpos isolate rejects default namespace" -Actual $invalidNamespaceExitCode -Expected 1
Assert-Contains -Name "isolate invalid namespace guidance" -Text $invalidNamespaceOutput -Pattern "Use a specific namespace such as 'v2'"

if ($beforeHash -ne $afterHash) {
    throw "adpos isolate -Plan changed configs/local.json."
}

$finalHash = Get-OptionalFileHash -Path $localConfigPath
if ($beforeHash -ne $finalHash) {
    throw "adpos isolate invalid namespace changed configs/local.json."
}

$backupFiles = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "configs") -Filter "local.json.bak*" -File -ErrorAction SilentlyContinue)
if ($backupFiles.Count -gt 0) {
    throw "adpos isolate -Plan created local config backup files: $($backupFiles.Name -join ', ')"
}

$global:LASTEXITCODE = 0
Write-Output "isolate plan contract OK"
