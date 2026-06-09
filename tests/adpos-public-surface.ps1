# ADP-OS public command surface checks.
# Public docs should teach adpos as the only user-facing shell command.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

function Get-PublicSurfaceFiles {
    $files = @()
    foreach ($relativePath in @(
        "README.md",
        "README.zh-CN.md",
        "CONTRIBUTING.md",
        "CONTRIBUTING.zh-CN.md",
        "SUPPORT.md",
        "SUPPORT.zh-CN.md",
        ".gitignore",
        ".github\pull_request_template.md",
        "setup.cmd",
        "uninstall.cmd",
        "scripts\test.sh",
        "cli\api\README.md",
        "cli\mcp\README.md",
        "extensions\deer_flow\README.md",
        "extensions\deer_flow\deerflow_adp_sandbox.py"
    )) {
        $path = Join-Path $projectRoot $relativePath
        if (Test-Path -LiteralPath $path) {
            $files += Get-Item -LiteralPath $path
        }
    }

    foreach ($relativeDir in @("docs", ".github\ISSUE_TEMPLATE")) {
        $path = Join-Path $projectRoot $relativeDir
        if (Test-Path -LiteralPath $path) {
            $files += Get-ChildItem -LiteralPath $path -Recurse -File | Where-Object { $_.Extension -in @(".md", ".yml", ".yaml") }
        }
    }

    $cliRoot = Join-Path $projectRoot "cli"
    if (Test-Path -LiteralPath $cliRoot) {
        $files += Get-ChildItem -LiteralPath $cliRoot -Recurse -File -Filter "README.md"
    }

    return $files | Sort-Object FullName -Unique
}

function ConvertTo-RelativePath {
    param([string]$Path)

    return [System.IO.Path]::GetRelativePath($projectRoot, $Path)
}

function Test-AllowedInternalCliReference {
    param([string]$Line)

    return ($Line -match "internal|control plane|implementation|User-facing shell commands should still use `?adpos`?|用户入口|面向用户的 shell 命令")
}

$violations = New-Object System.Collections.Generic.List[string]
$knownCommands = "setup|uninstall|iso|quickstart|init|up|status|capabilities|isolate|stop|sync|workspace|network|snapshot|restore|logs|doctor|destroy|precheck|help|version|validate|completion|serve|run|sandbox"
$legacyAdpCmdPattern = '(^|[^A-Za-z0-9_.-])(\.\\|\./)?adp\.cmd(?=\s|`|''|"|$)'
$legacyAdpSubcommandPattern = "(^|[^A-Za-z0-9_.-])(\.\\|\./)?adp\s+($knownCommands)\b"
$legacyAdpScriptCommandPattern = "(^|[^A-Za-z0-9_.-])(\.\\|\./)?(cli[\\/]+)?adp\.ps1\s+($knownCommands)\b"
$legacyAdpCliReferencePattern = '`adp`\s+CLI'
$internalCliPattern = '(^|[^A-Za-z0-9_.-])(\.\\|\./)?cli[\\/]+adp\.ps1(?=\s|`|''|"|$)'

foreach ($file in (Get-PublicSurfaceFiles)) {
    $relativePath = ConvertTo-RelativePath -Path $file.FullName
    $lineNumber = 0
    foreach ($line in (Get-Content -LiteralPath $file.FullName -Encoding UTF8)) {
        $lineNumber++
        if (
            $line -cmatch $legacyAdpCmdPattern -or
            $line -cmatch $legacyAdpSubcommandPattern -or
            $line -cmatch $legacyAdpScriptCommandPattern -or
            $line -cmatch $legacyAdpCliReferencePattern
        ) {
            $violations.Add("$relativePath`:$lineNumber exposes legacy adp shell command: $line")
        }

        if ($line -cmatch $internalCliPattern -and -not (Test-AllowedInternalCliReference -Line $line)) {
            $violations.Add("$relativePath`:$lineNumber exposes internal cli/adp.ps1 without explaining that adpos is the user command: $line")
        }
    }
}

if ($violations.Count -gt 0) {
    throw "Public command surface violations:`n$($violations -join "`n")"
}

function Assert-Contains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "Missing expected public surface contract: $Name"
    }
}

function Get-ChangelogEntry {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Date
    )

    $text = Get-Content -LiteralPath (Join-Path $projectRoot $RelativePath) -Raw -Encoding UTF8
    $pattern = "(?ms)^### $([regex]::Escape($Date))\r?\n(?<entry>.*?)(?=^### \d{4}-\d{2}-\d{2}|\z)"
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) {
        throw "Missing changelog entry $Date in $RelativePath"
    }

    return $match.Groups["entry"].Value
}

$readme = Get-Content -LiteralPath (Join-Path $projectRoot "README.md") -Raw -Encoding UTF8
$readmeZh = Get-Content -LiteralPath (Join-Path $projectRoot "README.zh-CN.md") -Raw -Encoding UTF8
$docsIndex = Get-Content -LiteralPath (Join-Path $projectRoot "docs\README.md") -Raw -Encoding UTF8
$docsIndexZh = Get-Content -LiteralPath (Join-Path $projectRoot "docs\zh-CN\README.md") -Raw -Encoding UTF8
$gettingStarted = Get-Content -LiteralPath (Join-Path $projectRoot "docs\getting-started.md") -Raw -Encoding UTF8
$gettingStartedZh = Get-Content -LiteralPath (Join-Path $projectRoot "docs\zh-CN\getting-started.md") -Raw -Encoding UTF8
$changelog = Get-Content -LiteralPath (Join-Path $projectRoot "CHANGELOG.md") -Raw -Encoding UTF8
$changelogZh = Get-Content -LiteralPath (Join-Path $projectRoot "CHANGELOG.zh-CN.md") -Raw -Encoding UTF8
Assert-Contains -Name "English docs index uses first-setup 30-70 minute timeline" -Text $docsIndex -Pattern 'running development VM in ~30-70 minutes'
Assert-Contains -Name "Chinese docs index uses first-setup 30-70 minute timeline" -Text $docsIndexZh -Pattern '运行中的开发 VM，约 30-70 分钟'
Assert-Contains -Name "English getting started keeps ISO download inside setup timeline" -Text $gettingStarted -Pattern '\| `setup\.cmd` \(guided setup \+ init\) \| 10–30 min \| Scans prerequisites, downloads or reuses the Ubuntu ISO'
Assert-Contains -Name "Chinese getting started keeps ISO download inside setup timeline" -Text $gettingStartedZh -Pattern '\| `setup\.cmd`（引导式设置 \+ 初始化） \| 10–30 分钟 \| 检查前提条件，下载或复用 Ubuntu ISO'
Assert-Contains -Name "English getting started puts seed ISO creation in up stage" -Text $gettingStarted -Pattern 'Creates the seed/autoinstall ISO, VM disk, and VMX configuration'
Assert-Contains -Name "Chinese getting started puts seed ISO creation in up stage" -Text $gettingStartedZh -Pattern '创建 seed/autoinstall ISO、VM 磁盘和 VMX 配置'
Assert-Contains -Name "English README setup options include full setup wrapper parameters" -Text $readme -Pattern '\.\\setup\.cmd -IsoPath[\s\S]*\.\\setup\.cmd -Distro ubuntu[\s\S]*\.\\setup\.cmd -SkipIsoDownload[\s\S]*\.\\setup\.cmd -SkipDoctor[\s\S]*\.\\setup\.cmd -NonInteractive[\s\S]*\.\\setup\.cmd -Force[\s\S]*\.\\setup\.cmd -NoRegisterCommand'
Assert-Contains -Name "Chinese README setup options include full setup wrapper parameters" -Text $readmeZh -Pattern '\.\\setup\.cmd -IsoPath[\s\S]*\.\\setup\.cmd -Distro ubuntu[\s\S]*\.\\setup\.cmd -SkipIsoDownload[\s\S]*\.\\setup\.cmd -SkipDoctor[\s\S]*\.\\setup\.cmd -NonInteractive[\s\S]*\.\\setup\.cmd -Force[\s\S]*\.\\setup\.cmd -NoRegisterCommand'
Assert-Contains -Name "English README command reference includes sandbox runtime" -Text $readme -Pattern 'adpos init <frontend\|backend\|agent\|sandbox>[\s\S]*adpos up <frontend\|backend\|agent\|sandbox>[\s\S]*adpos status \[frontend\|backend\|agent\|sandbox\][\s\S]*adpos stop <frontend\|backend\|agent\|sandbox>[\s\S]*adpos sync start <frontend\|backend\|agent\|sandbox>[\s\S]*adpos network apply <frontend\|backend\|agent\|sandbox\|all>'
Assert-Contains -Name "Chinese README command reference includes sandbox runtime" -Text $readmeZh -Pattern 'adpos init <frontend\|backend\|agent\|sandbox>[\s\S]*adpos up <frontend\|backend\|agent\|sandbox>[\s\S]*adpos status \[frontend\|backend\|agent\|sandbox\][\s\S]*adpos stop <frontend\|backend\|agent\|sandbox>[\s\S]*adpos sync start <frontend\|backend\|agent\|sandbox>[\s\S]*adpos network apply <frontend\|backend\|agent\|sandbox\|all>'
foreach ($case in @(
    @{ Name = "setup full parameters"; Pattern = 'adpos setup \[-Distro <name>\] \[-IsoPath <path>\] \[-SkipIsoDownload\] \[-SkipDoctor\] \[-Force\] \[-NonInteractive\] \[-NoRegisterCommand\]' },
    @{ Name = "quickstart full parameters"; Pattern = 'adpos quickstart \[-Distro <name>\] \[-IsoPath <path>\] \[-SkipIsoDownload\] \[-SkipDoctor\] \[-Force\] \[-NonInteractive\] \[-NoRegisterCommand\] \[--help-prereqs\]' },
    @{ Name = "precheck command"; Pattern = 'adpos precheck \[--help-prereqs\]' },
    @{ Name = "run command"; Pattern = 'adpos run <frontend\|backend\|agent\|sandbox> \[-IsoPath <path>\] \[-Plan\] \[-NoProvision\] \[-NoBootstrap\] \[-NoSync\]' },
    @{ Name = "validate command"; Pattern = 'adpos validate \[-Quick\] \[-SkipCliSmoke\] \[-SkipInstallerSmoke\] \[-SkipShellSyntax\]' },
    @{ Name = "completion command"; Pattern = 'adpos completion <powershell\|bash>' },
    @{ Name = "sandbox command"; Pattern = 'adpos sandbox <command\.\.\.> \[-Distro <name>\] \[-IsoPath <path>\]' },
    @{ Name = "serve command"; Pattern = 'adpos serve \[-Port <port>\] \[-Public\] \[-Json\]' },
    @{ Name = "isolate command"; Pattern = 'adpos isolate \[-Plan\|-Apply\] \[-Namespace <name>\]' },
    @{ Name = "network configure-local command"; Pattern = 'adpos network configure-local \[-Plan\|-Apply\]' },
    @{ Name = "uninstall noninteractive parameter"; Pattern = 'adpos uninstall \[-NonInteractive\] \[-Force\]' },
    @{ Name = "restore safety parameters"; Pattern = 'adpos restore <runtime> <name> \[-Plan\] \[-Force\]' },
    @{ Name = "destroy safety parameters"; Pattern = 'adpos destroy <runtime> \[-Plan\] \[-Force\]' }
)) {
    Assert-Contains -Name "English README command reference covers $($case.Name)" -Text $readme -Pattern $case.Pattern
    Assert-Contains -Name "Chinese README command reference covers $($case.Name)" -Text $readmeZh -Pattern $case.Pattern
}
Assert-Contains -Name "English changelog explains retired adp history" -Text $changelog -Pattern 'user-facing shell commands are `adpos` from 2026-06-08 onward[\s\S]*retired `adp` shell command[\s\S]*use `adpos` for current operations'
Assert-Contains -Name "Chinese changelog explains retired adp history" -Text $changelogZh -Pattern '自 2026-06-08 起，面向用户的 shell 命令为 `adpos`[\s\S]*已退役的 `adp` shell 命令[\s\S]*当前操作请使用 `adpos`'

foreach ($changelog in @("CHANGELOG.md", "CHANGELOG.zh-CN.md")) {
    $entry = Get-ChangelogEntry -RelativePath $changelog -Date "2026-06-08"
    if ($entry -cmatch $legacyAdpSubcommandPattern) {
        throw "$changelog latest public entry exposes legacy adp shell command: $($Matches[0])"
    }
}

Write-Output "adpos public surface checks OK"
