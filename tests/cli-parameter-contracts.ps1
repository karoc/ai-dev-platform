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
$ci = Read-Text ".github\workflows\ci.yml"

Assert-Contains -Name "CLI help defined before use" -Text $cli -Pattern 'function\s+Show-Help[\s\S]*if\s*\(-not\s+\$Command\s+-or\s+\$Command\s+-eq\s+"help"\)'
Assert-Contains -Name "CLI propagates command exit codes" -Text $cli -Pattern 'Invoke-CommandFile[\s\S]*if\s*\(\$LASTEXITCODE\)\s*\{[\s\S]*exit\s+\$LASTEXITCODE'
Assert-Contains -Name "CI runs installer smoke tests" -Text $ci -Pattern '\.\\tests\\install-smoke\.ps1'
Assert-Contains -Name "CLI registers workspace command" -Text $cli -Pattern '\$validCommands\s*=\s*@\([\s\S]*"workspace"'
Assert-Contains -Name "CLI help includes workspace command" -Text $cli -Pattern 'adp workspace <init\|show\|plan\|status\|dashboard\|task>'
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
Assert-Contains -Name "doctor supports Mutagen remediation plan" -Text $doctor -Pattern '\[switch\]\$FixMutagen[\s\S]*\[switch\]\$Plan[\s\S]*Install-LocalMutagen[\s\S]*Plan only: no files will be downloaded'
Assert-Contains -Name "doctor rejects plan without Mutagen remediation" -Text $doctor -Pattern '-Plan is only supported with -FixMutagen'
Assert-Contains -Name "mutagen adapter installs local ignored binary" -Text (Read-Text "adapters\windows\mutagen\mutagen.ps1") -Pattern 'function\s+Install-LocalMutagen[\s\S]*mutagen_windows_amd64_v\$Version\.zip[\s\S]*Expand-Archive[\s\S]*Test-MutagenVersionSupported'
Assert-Contains -Name "workspace init uses public example manifest" -Text $workspace -Pattern 'configs\\workspace\.example\.json'
Assert-Contains -Name "workspace plan is non-destructive" -Text $workspace -Pattern 'Plan only: no projects will be cloned, no sync sessions will be changed, and no snapshots will be created'
Assert-Contains -Name "workspace plan suggests previewed runtime startup" -Text $workspace -Pattern 'adp up \$\(\$project\.runtime\) -Plan'
Assert-Contains -Name "workspace status is non-destructive" -Text $workspace -Pattern 'Status only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, and no validation commands will be run'
Assert-Contains -Name "workspace status checks runtime readiness" -Text $workspace -Pattern 'Get-WorkspaceRuntimeStatus'
Assert-Contains -Name "workspace status checks sync readiness" -Text $workspace -Pattern 'Get-WorkspaceSyncStatus'
Assert-Contains -Name "workspace status checks snapshot readiness" -Text $workspace -Pattern 'Get-WorkspaceSnapshotStatus'
Assert-Contains -Name "workspace task risk supports snapshot gating" -Text $workspace -Pattern 'function\s+Get-WorkspaceTaskRisk[\s\S]*function\s+Test-WorkspaceTaskRequiresSnapshot[\s\S]*function\s+Get-WorkspaceSnapshotGate'
Assert-Contains -Name "workspace dashboard is non-destructive" -Text $workspace -Pattern 'Dashboard only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation commands will be run, and no Git commands will be run'
Assert-Contains -Name "workspace dashboard summarizes lifecycle state" -Text $workspace -Pattern 'Task lifecycle:[\s\S]*snapshot required:[\s\S]*execution:[\s\S]*rollback:[\s\S]*commit:'
Assert-Contains -Name "workspace dashboard can block execution on snapshot gate" -Text $workspace -Pattern 'blocked by snapshot gate'
Assert-Contains -Name "workspace run prints snapshot-first gate" -Text $workspace -Pattern 'Snapshot-first gate before broad agent work'
Assert-Contains -Name "workspace state defaults to ignored local path" -Text $workspace -Pattern 'adp-workspace\.state\.json'
Assert-Contains -Name "workspace task mark records local state only" -Text $workspace -Pattern 'Recorded local lifecycle state only\. No VM, sync, snapshot, file, Git, or validation command was run'
Assert-Contains -Name "workspace task lifecycle is plan-only" -Text $workspace -Pattern 'Task lifecycle output is plan-only\. No VM, sync, snapshot, file, Git, or validation command will be changed or run'
Assert-Contains -Name "workspace task lifecycle supports prepare" -Text $workspace -Pattern '"prepare"[\s\S]*Write-WorkspaceTaskPrepare'
Assert-Contains -Name "workspace task lifecycle supports snapshot" -Text $workspace -Pattern '"snapshot"[\s\S]*Write-WorkspaceTaskSnapshot'
Assert-Contains -Name "workspace task lifecycle supports run" -Text $workspace -Pattern '"run"[\s\S]*Write-WorkspaceTaskRun'
Assert-Contains -Name "workspace task lifecycle supports validate" -Text $workspace -Pattern '"validate"[\s\S]*Write-WorkspaceTaskValidate'
Assert-Contains -Name "workspace task lifecycle supports review" -Text $workspace -Pattern '"review"[\s\S]*Write-WorkspaceTaskReview'
Assert-Contains -Name "workspace task lifecycle supports rollback" -Text $workspace -Pattern '"rollback"[\s\S]*Write-WorkspaceTaskRollback'
Assert-Contains -Name "workspace task lifecycle supports commit" -Text $workspace -Pattern '"commit"[\s\S]*Write-WorkspaceTaskCommit'
Assert-Contains -Name "workspace task lifecycle supports mark" -Text $workspace -Pattern '"mark"[\s\S]*Write-WorkspaceTaskMark'

Write-Output "CLI parameter contracts OK"
