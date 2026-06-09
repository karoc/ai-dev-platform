# ADP-OS quickstart Mutagen remediation contract checks.
# Keeps one-click setup from aborting when Mutagen is the only missing prerequisite.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

function Read-Text {
    param([string]$RelativePath)

    return Get-Content -LiteralPath (Join-Path $projectRoot $RelativePath) -Raw -Encoding UTF8
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
        throw "Missing quickstart Mutagen remediation contract: $Name"
    }
}

$precheck = Read-Text "cli\commands\precheck.ps1"
$quickstart = Read-Text "cli\commands\quickstart.ps1"
$help = Read-Text "cli\lib\help.ps1"
$readme = Read-Text "README.md"
$readmeZh = Read-Text "README.zh-CN.md"
$gettingStarted = Read-Text "docs\getting-started.md"
$gettingStartedZh = Read-Text "docs\zh-CN\getting-started.md"

Assert-Contains `
    -Name "precheck exposes structured results for setup callers" `
    -Text $precheck `
    -Pattern '\$global:PrecheckResults = @\(\$script:checks \| ForEach-Object \{ \[pscustomobject\]\$_ \}\)'

Assert-Contains `
    -Name "quickstart detects Mutagen-only precheck issues" `
    -Text $quickstart `
    -Pattern 'function Test-QuickstartMutagenOnlyPrecheckIssue[\s\S]*Mutagen 0\.18\.x'

Assert-Contains `
    -Name "quickstart remediates Mutagen with doctor" `
    -Text $quickstart `
    -Pattern 'function Invoke-QuickstartMutagenRemediation[\s\S]*\. \$doctorCommand -FixMutagen'

Assert-Contains `
    -Name "quickstart reruns precheck after Mutagen remediation" `
    -Text $quickstart `
    -Pattern 'Test-QuickstartMutagenOnlyPrecheckIssue[\s\S]*Invoke-QuickstartMutagenRemediation[\s\S]*\$mutagenRemediated = \$true[\s\S]*\. \$precheckCommand'

Assert-Contains `
    -Name "help explains setup Mutagen remediation" `
    -Text $help `
    -Pattern 'If Mutagen is the only missing prerequisite, setup installs the tested local Mutagen binary and reruns precheck'

Assert-Contains `
    -Name "English README explains setup Mutagen remediation" `
    -Text $readme `
    -Pattern 'If Mutagen is the only missing prerequisite, setup installs the tested local Mutagen binary'

Assert-Contains `
    -Name "Chinese README explains setup Mutagen remediation" `
    -Text $readmeZh `
    -Pattern '如果 Mutagen 是唯一缺失的前提条件，setup 会把测试过的本地 Mutagen binary 安装到已忽略的 `\.tools\\mutagen` 下'

Assert-Contains `
    -Name "English getting started explains setup Mutagen remediation" `
    -Text $gettingStarted `
    -Pattern 'If this is the only missing prerequisite, `\.\\setup\.cmd` installs the tested local Mutagen binary'

Assert-Contains `
    -Name "Chinese getting started explains setup Mutagen remediation" `
    -Text $gettingStartedZh `
    -Pattern '如果这是唯一缺失的前提条件，`\.\\setup\.cmd` 会把测试过的本地 Mutagen binary 安装到已忽略的 `\.tools\\mutagen` 下'

Write-Output "quickstart Mutagen remediation contract OK"
