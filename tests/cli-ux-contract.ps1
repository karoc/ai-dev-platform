# ADP-OS CLI UX contract checks.
# Exercises typo recovery paths without mutating VM or host state.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$cliPath = Join-Path $projectRoot "cli\adp.ps1"
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source

function Invoke-AdposCli {
    param(
        [string[]]$Arguments,
        [hashtable]$Environment = @{}
    )

    $previousEnvironment = @{}
    try {
        foreach ($name in $Environment.Keys) {
            $previousEnvironment[$name] = [System.Environment]::GetEnvironmentVariable($name, "Process")
            [System.Environment]::SetEnvironmentVariable($name, [string]$Environment[$name], "Process")
        }

        $global:LASTEXITCODE = 0
        $output = & $pwsh -NoProfile -ExecutionPolicy Bypass -File $cliPath @Arguments 2>&1 | Out-String
        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = $output
        }
    } finally {
        foreach ($name in $Environment.Keys) {
            [System.Environment]::SetEnvironmentVariable($name, $previousEnvironment[$name], "Process")
        }
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
        throw "$Name contained unexpected pattern: $Pattern`nOutput:`n$Text"
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

$help = Invoke-AdposCli -Arguments @("help")
Assert-ExitCode -Name "adpos help" -Actual $help.ExitCode -Expected 0
Assert-Contains -Name "adpos help shows command overview" -Text $help.Output -Pattern "Commands:"
Assert-Contains -Name "adpos help includes setup" -Text $help.Output -Pattern "adpos setup"
Assert-Contains -Name "adpos help includes isolate" -Text $help.Output -Pattern "adpos isolate"
Assert-Contains -Name "adpos help includes uninstall" -Text $help.Output -Pattern "adpos uninstall"
Assert-Contains -Name "adpos help advertises command-specific help" -Text $help.Output -Pattern "adpos help <command>"
Assert-Contains -Name "adpos help wraps long quickstart usage before summary" -Text $help.Output -Pattern "adpos quickstart .*--help-prereqs\]\s+[\r\n]+\s+Compatibility guided setup entry"

$doctorHelp = Invoke-AdposCli -Arguments @("help", "doctor")
Assert-ExitCode -Name "adpos help doctor" -Actual $doctorHelp.ExitCode -Expected 0
Assert-Contains -Name "adpos help doctor shows command title" -Text $doctorHelp.Output -Pattern "ADP-OS: adpos doctor"
Assert-Contains -Name "adpos help doctor shows normal diagnostic usage" -Text $doctorHelp.Output -Pattern "adpos doctor \[-FirstRun\] \[-Json\]"
Assert-Contains -Name "adpos help doctor scopes plan to fix mutagen" -Text $doctorHelp.Output -Pattern "adpos doctor -FixMutagen \[-Plan\] \[-Json\]"
Assert-Contains -Name "adpos help doctor explains plan scope" -Text $doctorHelp.Output -Pattern "only valid with -FixMutagen"

$doctorFlagHelp = Invoke-AdposCli -Arguments @("doctor", "--help")
Assert-ExitCode -Name "adpos doctor --help" -Actual $doctorFlagHelp.ExitCode -Expected 0
Assert-Contains -Name "adpos doctor --help shows command title" -Text $doctorFlagHelp.Output -Pattern "ADP-OS: adpos doctor"
Assert-Contains -Name "adpos doctor --help shows normal diagnostic usage" -Text $doctorFlagHelp.Output -Pattern "adpos doctor \[-FirstRun\] \[-Json\]"
Assert-Contains -Name "adpos doctor --help scopes plan to fix mutagen" -Text $doctorFlagHelp.Output -Pattern "adpos doctor -FixMutagen \[-Plan\] \[-Json\]"
Assert-Contains -Name "adpos doctor --help explains plan scope" -Text $doctorFlagHelp.Output -Pattern "only valid with -FixMutagen"

$upHelp = Invoke-AdposCli -Arguments @("help", "up")
Assert-ExitCode -Name "adpos help up" -Actual $upHelp.ExitCode -Expected 0
Assert-Contains -Name "adpos help up lists sandbox runtime" -Text $upHelp.Output -Pattern "Runtime name \(frontend, backend, agent, sandbox\)"

$stopHelp = Invoke-AdposCli -Arguments @("stop", "--help")
Assert-ExitCode -Name "adpos stop --help" -Actual $stopHelp.ExitCode -Expected 0
Assert-Contains -Name "adpos stop --help lists sandbox runtime" -Text $stopHelp.Output -Pattern "Runtime name \(frontend, backend, agent, sandbox\)"

$doctorHelpZh = Invoke-AdposCli -Arguments @("help", "doctor") -Environment @{ ADP_LANG = "zh-CN" }
Assert-ExitCode -Name "adpos help doctor zh-CN" -Actual $doctorHelpZh.ExitCode -Expected 0
Assert-Contains -Name "adpos help doctor zh-CN shows mutagen plan usage" -Text $doctorHelpZh.Output -Pattern "adpos doctor -FixMutagen \[-Plan\] \[-Json\]"
Assert-Contains -Name "adpos help doctor zh-CN explains plan scope" -Text $doctorHelpZh.Output -Pattern "仅与 -FixMutagen 一起使用"

$helpTypo = Invoke-AdposCli -Arguments @("help", "doctro")
Assert-ExitCode -Name "adpos help doctro" -Actual $helpTypo.ExitCode -Expected 1
Assert-Contains -Name "adpos help typo reports missing detailed help" -Text $helpTypo.Output -Pattern "Command 'doctro' has no detailed help"
Assert-Contains -Name "adpos help typo suggests command-specific help" -Text $helpTypo.Output -Pattern "Did you mean: adpos help doctor"
Assert-Contains -Name "adpos help typo gives help overview recovery" -Text $helpTypo.Output -Pattern "Run 'adpos help' to see all commands"

$helpTypoZh = Invoke-AdposCli -Arguments @("help", "doctro") -Environment @{ ADP_LANG = "zh-CN" }
Assert-ExitCode -Name "adpos help doctro zh-CN" -Actual $helpTypoZh.ExitCode -Expected 1
Assert-Contains -Name "adpos help typo zh-CN reports missing detailed help" -Text $helpTypoZh.Output -Pattern "命令 'doctro' 没有详细帮助"
Assert-Contains -Name "adpos help typo zh-CN suggests command-specific help" -Text $helpTypoZh.Output -Pattern "你是不是想运行: adpos help doctor"
Assert-Contains -Name "adpos help typo zh-CN gives help overview recovery" -Text $helpTypoZh.Output -Pattern "运行 'adpos help' 查看所有命令"

$precheckHelp = Invoke-AdposCli -Arguments @("precheck", "--help-prereqs")
Assert-ExitCode -Name "adpos precheck --help-prereqs" -Actual $precheckHelp.ExitCode -Expected 0
Assert-Contains -Name "precheck help-prereqs shows prerequisites" -Text $precheckHelp.Output -Pattern "ADP-OS Prerequisites"
Assert-Contains -Name "precheck help-prereqs requires Windows 11" -Text $precheckHelp.Output -Pattern "Requires: Windows 11"

$quickstartHelp = Invoke-AdposCli -Arguments @("quickstart", "--help-prereqs")
Assert-ExitCode -Name "adpos quickstart --help-prereqs" -Actual $quickstartHelp.ExitCode -Expected 0
Assert-Contains -Name "quickstart help-prereqs delegates to prerequisites" -Text $quickstartHelp.Output -Pattern "ADP-OS Prerequisites"

$topLevelTypo = Invoke-AdposCli -Arguments @("hepl")
Assert-ExitCode -Name "adpos hepl" -Actual $topLevelTypo.ExitCode -Expected 1
Assert-Contains -Name "adpos hepl reports unknown command" -Text $topLevelTypo.Output -Pattern "Unknown command: hepl"
Assert-Contains -Name "adpos hepl suggests help" -Text $topLevelTypo.Output -Pattern "Did you mean: adpos help"
Assert-Contains -Name "adpos hepl gives recovery path" -Text $topLevelTypo.Output -Pattern "Run 'adpos help' to see full help"

$doctorPlan = Invoke-AdposCli -Arguments @("doctor", "-Plan")
Assert-ExitCode -Name "adpos doctor -Plan" -Actual $doctorPlan.ExitCode -Expected 1
Assert-Contains -Name "doctor plan without fix mutagen explains valid pairing" -Text $doctorPlan.Output -Pattern "-Plan is only supported with -FixMutagen"

$doctorPlanZh = Invoke-AdposCli -Arguments @("doctor", "-Plan") -Environment @{ ADP_LANG = "zh-CN" }
Assert-ExitCode -Name "adpos doctor -Plan zh-CN" -Actual $doctorPlanZh.ExitCode -Expected 1
Assert-Contains -Name "doctor plan without fix mutagen explains valid pairing zh-CN" -Text $doctorPlanZh.Output -Pattern "-Plan 仅支持与 -FixMutagen 一起使用"

$isoMissingUrl = Invoke-AdposCli -Arguments @("iso", "ubuntu", "-Url")
Assert-ExitCode -Name "adpos iso ubuntu -Url" -Actual $isoMissingUrl.ExitCode -Expected 1
Assert-Contains -Name "iso missing Url reports ADP argument error" -Text $isoMissingUrl.Output -Pattern "Invalid arguments for command: adpos iso"
Assert-Contains -Name "iso missing Url preserves binding detail" -Text $isoMissingUrl.Output -Pattern "Missing an argument for parameter 'Url'"
Assert-Contains -Name "iso missing Url gives command help path" -Text $isoMissingUrl.Output -Pattern "Run 'adpos iso --help' for usage"
Assert-NotContains -Name "iso missing Url hides raw binding type" -Text $isoMissingUrl.Output -Pattern "ParameterBindingException|FullyQualifiedErrorId|At .* char"

$isoBadDistro = Invoke-AdposCli -Arguments @("iso", "ubunut")
Assert-ExitCode -Name "adpos iso ubunut" -Actual $isoBadDistro.ExitCode -Expected 1
Assert-Contains -Name "iso bad distro reports ADP argument error" -Text $isoBadDistro.Output -Pattern "Invalid arguments for command: adpos iso"
Assert-Contains -Name "iso bad distro preserves valid set" -Text $isoBadDistro.Output -Pattern "ubuntu,almalinux,rocky,debian"
Assert-Contains -Name "iso bad distro gives command help path" -Text $isoBadDistro.Output -Pattern "Run 'adpos iso --help' for usage"
Assert-NotContains -Name "iso bad distro hides raw binding type" -Text $isoBadDistro.Output -Pattern "ParameterBindingException|FullyQualifiedErrorId|At .* char"

$workspaceMissingManifest = Invoke-AdposCli -Arguments @("workspace", "status", "-ManifestPath")
Assert-ExitCode -Name "adpos workspace status -ManifestPath" -Actual $workspaceMissingManifest.ExitCode -Expected 1
Assert-Contains -Name "workspace missing ManifestPath reports ADP argument error" -Text $workspaceMissingManifest.Output -Pattern "Invalid arguments for command: adpos workspace"
Assert-Contains -Name "workspace missing ManifestPath preserves binding detail" -Text $workspaceMissingManifest.Output -Pattern "Missing an argument for parameter 'ManifestPath'"
Assert-Contains -Name "workspace missing ManifestPath gives command help path" -Text $workspaceMissingManifest.Output -Pattern "Run 'adpos workspace --help' for usage"
Assert-NotContains -Name "workspace missing ManifestPath hides raw binding type" -Text $workspaceMissingManifest.Output -Pattern "ParameterBindingException|FullyQualifiedErrorId|At .* char"

$setupMissingIsoPathZh = Invoke-AdposCli -Arguments @("setup", "-IsoPath") -Environment @{ ADP_LANG = "zh-CN" }
Assert-ExitCode -Name "adpos setup -IsoPath zh-CN" -Actual $setupMissingIsoPathZh.ExitCode -Expected 1
Assert-Contains -Name "setup missing IsoPath reports ADP argument error zh-CN" -Text $setupMissingIsoPathZh.Output -Pattern "命令参数无效: adpos setup"
Assert-Contains -Name "setup missing IsoPath gives command help path zh-CN" -Text $setupMissingIsoPathZh.Output -Pattern "运行 'adpos setup --help' 查看用法"
Assert-NotContains -Name "setup missing IsoPath hides raw binding type zh-CN" -Text $setupMissingIsoPathZh.Output -Pattern "ParameterBindingException|FullyQualifiedErrorId|At .* char"

$versionBogus = Invoke-AdposCli -Arguments @("version", "-Bogus")
Assert-ExitCode -Name "adpos version -Bogus" -Actual $versionBogus.ExitCode -Expected 1
Assert-Contains -Name "version rejects extra arguments" -Text $versionBogus.Output -Pattern "Invalid arguments for command: adpos version"
Assert-Contains -Name "version extra argument gives command help path" -Text $versionBogus.Output -Pattern "Run 'adpos version --help' for usage"
Assert-NotContains -Name "version extra argument does not print version" -Text $versionBogus.Output -Pattern "ADP-OS version"

$capabilitiesBogus = Invoke-AdposCli -Arguments @("capabilities", "-Bogus")
Assert-ExitCode -Name "adpos capabilities -Bogus" -Actual $capabilitiesBogus.ExitCode -Expected 1
Assert-Contains -Name "capabilities rejects extra arguments" -Text $capabilitiesBogus.Output -Pattern "Invalid arguments for command: adpos capabilities"
Assert-Contains -Name "capabilities extra argument gives command help path" -Text $capabilitiesBogus.Output -Pattern "Run 'adpos capabilities --help' for usage"
Assert-NotContains -Name "capabilities extra argument does not print capabilities" -Text $capabilitiesBogus.Output -Pattern "ADP-OS Capabilities"

$syncTypo = Invoke-AdposCli -Arguments @("sync", "stats")
Assert-ExitCode -Name "adpos sync stats" -Actual $syncTypo.ExitCode -Expected 1
Assert-Contains -Name "adpos sync typo reports unknown subcommand" -Text $syncTypo.Output -Pattern "Unknown sync command: stats"
Assert-Contains -Name "adpos sync typo suggests status" -Text $syncTypo.Output -Pattern "Did you mean: adpos sync status"
Assert-Contains -Name "adpos sync typo gives help path" -Text $syncTypo.Output -Pattern "Run 'adpos sync --help' for sync help"

$networkTypo = Invoke-AdposCli -Arguments @("network", "aplpy")
Assert-ExitCode -Name "adpos network aplpy" -Actual $networkTypo.ExitCode -Expected 1
Assert-Contains -Name "adpos network typo reports unknown subcommand" -Text $networkTypo.Output -Pattern "Unknown network command: aplpy"
Assert-Contains -Name "adpos network typo suggests apply" -Text $networkTypo.Output -Pattern "Did you mean: adpos network apply"
Assert-Contains -Name "adpos network typo gives help path" -Text $networkTypo.Output -Pattern "Run 'adpos network --help' for network help"

$stopBadRuntime = Invoke-AdposCli -Arguments @("stop", "not-a-runtime")
Assert-ExitCode -Name "adpos stop not-a-runtime" -Actual $stopBadRuntime.ExitCode -Expected 1
Assert-Contains -Name "stop bad runtime lists sandbox" -Text $stopBadRuntime.Output -Pattern "Unknown runtime: not-a-runtime\. Valid: frontend, backend, agent, sandbox"
Assert-Contains -Name "stop bad runtime gives help path" -Text $stopBadRuntime.Output -Pattern "Run 'adpos stop --help' for usage"

$networkBadRuntime = Invoke-AdposCli -Arguments @("network", "apply", "not-a-runtime", "-Plan")
Assert-ExitCode -Name "adpos network apply not-a-runtime -Plan" -Actual $networkBadRuntime.ExitCode -Expected 1
Assert-Contains -Name "network bad runtime lists sandbox and all" -Text $networkBadRuntime.Output -Pattern "Unknown runtime: not-a-runtime\. Valid: frontend, backend, agent, sandbox, all"
Assert-Contains -Name "network bad runtime gives help path" -Text $networkBadRuntime.Output -Pattern "Run 'adpos network --help' for network help"

$workspaceTypo = Invoke-AdposCli -Arguments @("workspace", "dashbaord")
Assert-ExitCode -Name "adpos workspace dashbaord" -Actual $workspaceTypo.ExitCode -Expected 1
Assert-Contains -Name "adpos workspace typo reports unknown subcommand" -Text $workspaceTypo.Output -Pattern "Unknown workspace command: dashbaord"
Assert-Contains -Name "adpos workspace typo suggests dashboard" -Text $workspaceTypo.Output -Pattern "Did you mean: adpos workspace dashboard"
Assert-Contains -Name "adpos workspace typo gives help path" -Text $workspaceTypo.Output -Pattern "adpos workspace help"

$workspaceTaskTypo = Invoke-AdposCli -Arguments @("workspace", "task", "revie", "before-large-agent-task", "-ManifestPath", "configs\workspace.example.json")
Assert-ExitCode -Name "adpos workspace task revie" -Actual $workspaceTaskTypo.ExitCode -Expected 1
Assert-Contains -Name "adpos workspace task typo reports unknown subcommand" -Text $workspaceTaskTypo.Output -Pattern "Unknown workspace task command: revie"
Assert-Contains -Name "adpos workspace task typo suggests review" -Text $workspaceTaskTypo.Output -Pattern "Did you mean: adpos workspace task review"

$global:LASTEXITCODE = 0
Write-Output "CLI UX contracts OK"
