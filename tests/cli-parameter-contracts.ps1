# ADP-OS CLI parameter contract checks
# Guards against command switches being accepted but not propagated.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

function Read-Text {
    param([string]$RelativePath)
    return Get-Content -LiteralPath (Join-Path $projectRoot $RelativePath) -Raw
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

$up = Read-Text "cli\commands\up.ps1"
$init = Read-Text "cli\commands\init.ps1"
$install = Read-Text "install.ps1"
$factory = Read-Text "runtimes\vmware\vm-factory.ps1"
$cli = Read-Text "cli\adp.ps1"
$logger = Read-Text "core\logging\logger.ps1"
$logs = Read-Text "cli\commands\logs.ps1"
$sync = Read-Text "cli\commands\sync.ps1"
$doctor = Read-Text "cli\commands\doctor.ps1"
$workspace = Read-Text "cli\commands\workspace.ps1"

Assert-Contains -Name "CLI help defined before use" -Text $cli -Pattern 'function\s+Show-Help[\s\S]*if\s*\(-not\s+\$Command\s+-or\s+\$Command\s+-eq\s+"help"\)'
Assert-Contains -Name "CLI propagates command exit codes" -Text $cli -Pattern 'Invoke-CommandFile[\s\S]*if\s*\(\$LASTEXITCODE\)\s*\{[\s\S]*exit\s+\$LASTEXITCODE'
Assert-Contains -Name "CLI registers workspace command" -Text $cli -Pattern '\$validCommands\s*=\s*@\([\s\S]*"workspace"'
Assert-Contains -Name "CLI help includes workspace command" -Text $cli -Pattern 'adp workspace <init\|show\|plan\|status>'
Assert-Contains -Name "up -IsoPath propagation" -Text $up -Pattern 'New-RuntimeVM[\s\S]*-IsoPath\s+\$IsoPath'
Assert-Contains -Name "vm factory IsoPath parameter" -Text $factory -Pattern 'function\s+New-RuntimeVM[\s\S]*\[string\]\$IsoPath'
Assert-Contains -Name "vm factory IsoPath resolution" -Text $factory -Pattern '\$resolvedIsoPath\s*=\s*if\s*\(\$IsoPath\)'
Assert-Contains -Name "init -SkipProvision propagation" -Text $init -Pattern 'NoProvision\s*=\s*\$SkipProvision'
Assert-Contains -Name "init invokes up in shared script scope" -Text $init -Pattern '\.\s+\$upCommand\s+@upArgs'
Assert-Contains -Name "up -NoProvision skips bootstrap after creation" -Text $up -Pattern 'if\s*\(\$NoProvision\)\s*\{[\s\S]*bootstrap were skipped[\s\S]*return'
Assert-Contains -Name "install -SkipDependencyCheck behavior" -Text $install -Pattern 'if\s*\(\$SkipDependencyCheck\)\s*\{[\s\S]*Dependency checks skipped'
Assert-Contains -Name "install -SkipVMValidation behavior" -Text $install -Pattern 'if\s*\(\$SkipVMValidation\)\s*\{[\s\S]*VMware validation skipped'
Assert-Contains -Name "install skipped dependency summary" -Text $install -Pattern 'if\s*\(\$SkipDependencyCheck\)\s*\{[\s\S]*Dependency checks were skipped'
Assert-Contains -Name "install checks WSL xorriso" -Text $install -Pattern 'Test-WSLCommand[\s\S]*WSL xorriso'
Assert-Contains -Name "install checks VMware disk manager" -Text $install -Pattern 'Find-VmwareDiskManager[\s\S]*VMware disk manager'
Assert-Contains -Name "install checks ISO shape" -Text $install -Pattern 'Test-ISOReasonable[\s\S]*ISO warning'
Assert-Contains -Name "logger levels use script scope" -Text $logger -Pattern '\$script:LogLevels[\s\S]*\$levels\s*=\s*if\s*\(\$script:LogLevels\)'
Assert-Contains -Name "logs validates runtime" -Text $logs -Pattern 'Test-RuntimeExists\s+\$RuntimeName'
Assert-Contains -Name "sync start validates runtime" -Text $sync -Pattern '"start"[\s\S]*Test-RuntimeExists\s+\$RuntimeName'
Assert-Contains -Name "sync stop validates runtime" -Text $sync -Pattern '"stop"[\s\S]*Test-RuntimeExists\s+\$RuntimeName'
Assert-Contains -Name "sync validates subcommand before mutagen" -Text $sync -Pattern '\$validSubCommands[\s\S]*Unknown sync command[\s\S]*Initialize-Mutagen'
Assert-Contains -Name "doctor checks WSL xorriso" -Text $doctor -Pattern 'WSL xorriso'
Assert-Contains -Name "doctor checks ISO shape" -Text $doctor -Pattern 'ISO shape'
Assert-Contains -Name "workspace init uses public example manifest" -Text $workspace -Pattern 'configs\\workspace\.example\.json'
Assert-Contains -Name "workspace plan is non-destructive" -Text $workspace -Pattern 'Plan only: no projects will be cloned, no sync sessions will be changed, and no snapshots will be created'
Assert-Contains -Name "workspace plan suggests previewed runtime startup" -Text $workspace -Pattern 'adp up \$\(\$project\.runtime\) -Plan'
Assert-Contains -Name "workspace status is non-destructive" -Text $workspace -Pattern 'Status only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, and no validation commands will be run'
Assert-Contains -Name "workspace status checks runtime readiness" -Text $workspace -Pattern 'Get-WorkspaceRuntimeStatus'
Assert-Contains -Name "workspace status checks sync readiness" -Text $workspace -Pattern 'Get-WorkspaceSyncStatus'
Assert-Contains -Name "workspace status checks snapshot readiness" -Text $workspace -Pattern 'Get-WorkspaceSnapshotStatus'

Write-Output "CLI parameter contracts OK"
