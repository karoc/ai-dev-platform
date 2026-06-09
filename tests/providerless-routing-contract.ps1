# ADP-OS providerless entry routing contract checks.
# Ensures guide/read-only commands do not initialize the VMware provider at entry.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$sentinel = "ENTRY PROVIDER SENTINEL"

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

    throw "Cannot resolve pwsh executable path for providerless routing checks."
}

function New-ProviderlessRoutingSandbox {
    $sandboxRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("adp-providerless-routing-{0}" -f ([guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Path $sandboxRoot -Force | Out-Null

    $files = & git -C $projectRoot ls-files --cached --others --exclude-standard
    if ($LASTEXITCODE -ne 0) {
        throw "git ls-files failed while preparing providerless routing sandbox."
    }

    foreach ($relativePath in $files) {
        $source = Join-Path $projectRoot $relativePath
        if (-not (Test-Path -LiteralPath $source)) {
            continue
        }

        $target = Join-Path $sandboxRoot $relativePath
        $targetDirectory = Split-Path $target -Parent
        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $target -Force
    }

    $localConfig = @{
        platform = @{
            paths = @{
                workspace_root = '${project:root}\test-workspaces'
                vm_store       = '${project:root}\test-vms'
            }
            provider = @{
                config = @{
                    vm_store = '${project:root}\test-vms'
                }
            }
        }
    } | ConvertTo-Json -Depth 8
    Set-Content -LiteralPath (Join-Path $sandboxRoot "configs\local.json") -Value $localConfig -Encoding utf8

    $vmxDirectory = Join-Path $sandboxRoot "test-vms\adp-agent"
    New-Item -ItemType Directory -Path $vmxDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $vmxDirectory "adp-agent.vmx") -Value 'config.version = "8"' -Encoding utf8

    return $sandboxRoot
}

function Set-ProviderSentinel {
    param([string]$SandboxRoot)

    $throwingModule = "throw '$sentinel'"
    foreach ($relativePath in @(
        "adapters\windows\vmware\vmware-provider.ps1",
        "adapters\windows\vmware\vmware.ps1",
        "adapters\windows\mutagen\mutagen.ps1"
    )) {
        Set-Content -LiteralPath (Join-Path $SandboxRoot $relativePath) -Value $throwingModule -Encoding utf8
    }
}

function Invoke-SandboxAdpos {
    param(
        [string]$SandboxRoot,
        [string[]]$Arguments
    )

    $stdout = [System.IO.Path]::GetTempFileName()
    $stderr = [System.IO.Path]::GetTempFileName()
    try {
        $processArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $SandboxRoot "cli\adp.ps1")) + $Arguments
        $process = Start-Process -FilePath (Get-TestPwshPath) `
            -ArgumentList $processArguments `
            -WorkingDirectory $SandboxRoot `
            -NoNewWindow -Wait -PassThru `
            -RedirectStandardOutput $stdout `
            -RedirectStandardError $stderr

        $outText = Get-Content -LiteralPath $stdout -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        $errText = Get-Content -LiteralPath $stderr -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Output   = "$outText`n$errText"
        }
    } finally {
        Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
    }
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
        throw "$Name touched the entry provider sentinel: $Pattern`nOutput:`n$Text"
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

$cliText = Get-Content -LiteralPath (Join-Path $projectRoot "cli\adp.ps1") -Raw -Encoding UTF8
$workspaceText = Get-Content -LiteralPath (Join-Path $projectRoot "cli\commands\workspace.ps1") -Raw -Encoding UTF8
$workspaceProbeText = Get-Content -LiteralPath (Join-Path $projectRoot "cli\lib\workspace-probes.ps1") -Raw -Encoding UTF8
$parameterPreflightText = Get-Content -LiteralPath (Join-Path $projectRoot "cli\lib\parameter-preflight.ps1") -Raw -Encoding UTF8
$semanticPreflightText = Get-Content -LiteralPath (Join-Path $projectRoot "cli\lib\semantic-preflight.ps1") -Raw -Encoding UTF8
Assert-Contains -Name "entry routing has provider requirement gate" -Text $cliText -Pattern 'function\s+Test-ADPCommandRequiresEntryProvider'
Assert-Contains -Name "entry routing has workspace provider gate" -Text $cliText -Pattern 'function\s+Test-ADPWorkspaceCommandRequiresEntryProvider'
Assert-Contains -Name "entry provider is initialized after command file validation" -Text $cliText -Pattern 'if\s+\(-not\s+\(Test-Path\s+\$commandFile\)\)[\s\S]*if\s+\(Test-ADPCommandRequiresEntryProvider'
Assert-Contains -Name "entry parameter preflight runs before provider init" -Text $cliText -Pattern 'if\s+\(-not\s+\(Test-Path\s+\$commandFile\)\)[\s\S]*Invoke-ADPCommandParameterPreflight[\s\S]*if\s+\(Test-ADPCommandRequiresEntryProvider'
Assert-Contains -Name "entry semantic preflight runs before provider init" -Text $cliText -Pattern 'Invoke-ADPCommandParameterPreflight[\s\S]*Invoke-ADPCommandSemanticPreflight[\s\S]*if\s+\(Test-ADPCommandRequiresEntryProvider'
Assert-Contains -Name "entry provider remains available by default" -Text $cliText -Pattern 'if\s+\(\$normalizedCommand\s+-in\s+\$providerlessCommands\)[\s\S]*return \$true'
Assert-Contains -Name "parameter preflight parses only command param block" -Text $parameterPreflightText -Pattern 'Parser\]::ParseInput[\s\S]*\$ast\.ParamBlock[\s\S]*\[scriptblock\]::Create\(\$preflightText\)'
Assert-NotContains -Name "parameter preflight never dot-sources command files" -Text $parameterPreflightText -Pattern '\. \$Path|\. \(Quote|Invoke-CommandFile'
Assert-Contains -Name "semantic preflight catches doctor plan pairing" -Text $semanticPreflightText -Pattern '\$normalizedCommand\s+-eq\s+"doctor"[\s\S]*-Name "Plan"[\s\S]*-Name "FixMutagen"[\s\S]*-Plan is only supported with -FixMutagen'
Assert-Contains -Name "workspace snapshot evidence keeps entry provider" -Text $cliText -Pattern '\$workspaceCommand\s+-eq\s+"evidence"[\s\S]*Test-ADPArgumentSwitchPresent[\s\S]*-Name "Snapshot"'
Assert-Contains -Name "workspace loads probe policy" -Text $workspaceText -Pattern 'Set-ADPWorkspaceExternalProbePolicy'
Assert-Contains -Name "workspace runtime probes can be skipped" -Text $workspaceProbeText -Pattern 'Test-ADPWorkspaceExternalProbeAllowed[\s\S]*New-ADPWorkspaceProbeSkippedStatus -Kind "runtime"'
Assert-Contains -Name "workspace sync probes can be skipped" -Text $workspaceProbeText -Pattern 'Test-ADPWorkspaceExternalProbeAllowed[\s\S]*New-ADPWorkspaceProbeSkippedStatus -Kind "sync"'
Assert-Contains -Name "workspace snapshot probes can be skipped" -Text $workspaceProbeText -Pattern 'Test-ADPWorkspaceExternalProbeAllowed[\s\S]*New-ADPWorkspaceProbeSkippedStatus -Kind "snapshot"'
Assert-Contains -Name "workspace probe policy only allows explicit remote validation" -Text $workspaceProbeText -Pattern 'task.*validate[\s\S]*ExecuteValidation[\s\S]*-not \$LocalExecution'
if ($cliText -notmatch '\$providerlessCommands\s*=\s*@\((?<commands>[\s\S]*?)\)\s*[\r\n]+\s*if\s+\(\$normalizedCommand\s+-in\s+\$providerlessCommands\)') {
    throw "Could not find entry providerless command block in cli/adp.ps1."
}
$entryProviderlessCommands = $matches.commands
Assert-NotContains -Name "sync is not providerless at entry" -Text $entryProviderlessCommands -Pattern '"sync"'
Assert-NotContains -Name "serve is not providerless at entry" -Text $entryProviderlessCommands -Pattern '"serve"'
Assert-NotContains -Name "up is not providerless at entry" -Text $entryProviderlessCommands -Pattern '"up"'
Assert-NotContains -Name "status is not providerless at entry" -Text $entryProviderlessCommands -Pattern '"status"'
Assert-NotContains -Name "snapshot is not providerless at entry" -Text $entryProviderlessCommands -Pattern '"snapshot"'
Assert-Contains -Name "run plan is providerless by flag" -Text $cliText -Pattern '\$normalizedCommand\s+-eq\s+"run"[\s\S]*-Name "Plan"'
Assert-Contains -Name "prerequisite help alias is normalized" -Text $cliText -Pattern 'function\s+Resolve-ADPArgumentAlias[\s\S]*"--help-prereqs"[\s\S]*"-HelpPrereqs"'
Assert-Contains -Name "precheck help is providerless by flag" -Text $cliText -Pattern '\$normalizedCommand\s+-eq\s+"precheck"[\s\S]*-Name "HelpPrereqs"'
Assert-Contains -Name "quickstart help and plan are providerless by flag" -Text $cliText -Pattern '\$normalizedCommand\s+-eq\s+"quickstart"[\s\S]*-Name "HelpPrereqs"[\s\S]*-Name "Plan"'

. (Join-Path $projectRoot "cli\lib\parameter-preflight.ps1")
Invoke-ADPCommandParameterPreflight -Path (Join-Path $projectRoot "cli\commands\sandbox.ps1") -RawArguments @("curl", "--silent")
Invoke-ADPCommandParameterPreflight -Path (Join-Path $projectRoot "cli\commands\workspace.ps1") -RawArguments @("evidence", "-Export", "-Path", "out.zip")

$sandboxRoot = New-ProviderlessRoutingSandbox
try {
    Set-ProviderSentinel -SandboxRoot $sandboxRoot

    $cases = @(
        @{ Name = "help"; Args = @("help"); ExitCode = 0; Pattern = "ADP-OS CLI" },
        @{ Name = "help doctor"; Args = @("help", "doctor"); ExitCode = 0; Pattern = "ADP-OS: adpos doctor" },
        @{ Name = "precheck help prereqs"; Args = @("precheck", "--help-prereqs"); ExitCode = 0; Pattern = "ADP-OS Prerequisites" },
        @{ Name = "quickstart plan"; Args = @("quickstart", "-Plan", "-SkipIsoDownload", "-SkipDoctor", "-NoRegisterCommand"); ExitCode = 0; Pattern = "ADP-OS Quickstart Plan" },
        @{ Name = "unknown command"; Args = @("hepl"); ExitCode = 1; Pattern = "Unknown command: hepl" },
        @{ Name = "capabilities"; Args = @("capabilities"); ExitCode = 0; Pattern = "Capabilities only: no VMs" },
        @{ Name = "isolate plan"; Args = @("isolate", "-Plan", "-Namespace", "v2"); ExitCode = 0; Pattern = "Plan only: configs\\\\local\.json will not be changed" },
        @{ Name = "workspace status"; Args = @("workspace", "status", "-ManifestPath", "configs\workspace.example.json"); ExitCode = 0; Pattern = "external provider probe skipped" },
        @{ Name = "workspace dashboard"; Args = @("workspace", "dashboard", "-ManifestPath", "configs\workspace.example.json"); ExitCode = 0; Pattern = "runtime: created, not checked; sync: not checked" },
        @{ Name = "workspace report"; Args = @("workspace", "report", "-ManifestPath", "configs\workspace.example.json"); ExitCode = 0; Pattern = "snapshot: not checked" },
        @{ Name = "workspace sync guide"; Args = @("workspace", "sync", "app", "-ManifestPath", "configs\workspace.example.json"); ExitCode = 0; Pattern = "external sync probe skipped" },
        @{ Name = "workspace task snapshot"; Args = @("workspace", "task", "snapshot", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json"); ExitCode = 0; Pattern = "external snapshot probe skipped" },
        @{ Name = "workspace task validate plan"; Args = @("workspace", "task", "validate", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json"); ExitCode = 0; Pattern = "Validation plan:" }
    )

    foreach ($case in $cases) {
        $result = Invoke-SandboxAdpos -SandboxRoot $sandboxRoot -Arguments $case.Args
        Assert-ExitCode -Name $case.Name -Actual $result.ExitCode -Expected $case.ExitCode
        Assert-Contains -Name $case.Name -Text $result.Output -Pattern $case.Pattern
        Assert-NotContains -Name $case.Name -Text $result.Output -Pattern $sentinel
        Assert-NotContains -Name $case.Name -Text $result.Output -Pattern 'Get-VMStatus|Get-SnapshotList|Initialize-Mutagen|Test-SyncSessionExists'
    }

    $invalidArgumentCases = @(
        @{ Name = "doctor unknown parameter"; Args = @("doctor", "-Bogus"); Detail = "Bogus" },
        @{ Name = "up missing iso path value"; Args = @("up", "agent", "-IsoPath"); Detail = "IsoPath" },
        @{ Name = "up typo parameter"; Args = @("up", "agent", "-NoBootstrp"); Detail = "NoBootstrp" },
        @{ Name = "status typo parameter"; Args = @("status", "-RuntimName", "agent"); Detail = "RuntimName" },
        @{ Name = "sync typo parameter"; Args = @("sync", "start", "agent", "-RuntimName"); Detail = "RuntimName" },
        @{ Name = "network typo parameter"; Args = @("network", "apply", "agent", "-Plna"); Detail = "Plna" },
        @{ Name = "serve invalid port"; Args = @("serve", "-Port", "abc"); Detail = "Port" },
        @{ Name = "serve missing port"; Args = @("serve", "-Port"); Detail = "Port" },
        @{ Name = "precheck typo parameter"; Args = @("precheck", "-Jsson"); Detail = "Jsson" },
        @{ Name = "quickstart typo parameter"; Args = @("quickstart", "-SkpDoctor"); Detail = "SkpDoctor" },
        @{ Name = "quickstart missing iso path value"; Args = @("quickstart", "-IsoPath"); Detail = "IsoPath" },
        @{ Name = "run typo parameter"; Args = @("run", "agent", "-NoBootstrp"); Detail = "NoBootstrp" },
        @{ Name = "sandbox missing distro value"; Args = @("sandbox", "-Distro"); Detail = "Distro" }
    )

    foreach ($case in $invalidArgumentCases) {
        $result = Invoke-SandboxAdpos -SandboxRoot $sandboxRoot -Arguments $case.Args
        Assert-ExitCode -Name $case.Name -Actual $result.ExitCode -Expected 1
        Assert-Contains -Name $case.Name -Text $result.Output -Pattern "Invalid arguments for command: adpos"
        Assert-Contains -Name $case.Name -Text $result.Output -Pattern $case.Detail
        Assert-Contains -Name $case.Name -Text $result.Output -Pattern "Run 'adpos .+ --help' for usage"
        Assert-NotContains -Name $case.Name -Text $result.Output -Pattern $sentinel
        Assert-NotContains -Name $case.Name -Text $result.Output -Pattern 'Provider init skipped|VMware adapter init skipped|Get-VMStatus|Initialize-Mutagen'
    }

    $doctorPlan = Invoke-SandboxAdpos -SandboxRoot $sandboxRoot -Arguments @("doctor", "-Plan")
    Assert-ExitCode -Name "doctor plan semantic preflight" -Actual $doctorPlan.ExitCode -Expected 1
    Assert-Contains -Name "doctor plan semantic preflight" -Text $doctorPlan.Output -Pattern "-Plan is only supported with -FixMutagen"
    Assert-Contains -Name "doctor plan semantic preflight help path" -Text $doctorPlan.Output -Pattern "Run 'adpos doctor --help' for usage"
    Assert-NotContains -Name "doctor plan semantic preflight" -Text $doctorPlan.Output -Pattern $sentinel
    Assert-NotContains -Name "doctor plan semantic preflight" -Text $doctorPlan.Output -Pattern 'Provider init skipped|VMware adapter init skipped|Initialize-Mutagen|Running: adpos doctor'
} finally {
    $tempRoot = [System.IO.Path]::GetTempPath()
    if ($sandboxRoot -and (Test-Path -LiteralPath $sandboxRoot) -and [System.IO.Path]::GetFullPath($sandboxRoot).StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $sandboxRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$global:LASTEXITCODE = 0
Write-Output "providerless routing contract OK"
