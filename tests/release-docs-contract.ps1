# ADP-OS release and security documentation contracts.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

function Read-RepoText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

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
        throw "Missing release docs contract: $Name"
    }
}

function Assert-NotContains {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    if ($Text -match $Pattern) {
        throw "Forbidden stale release docs text found: $Name"
    }
}

$version = (Read-RepoText -RelativePath "VERSION").Trim()
if ($version -ne "1.0.0") {
    throw "Unexpected documented release baseline. Expected VERSION 1.0.0, got $version."
}

$security = Read-RepoText -RelativePath "SECURITY.md"
$securityZh = Read-RepoText -RelativePath "SECURITY.zh-CN.md"
$releaseProcess = Read-RepoText -RelativePath "docs\release-process.md"
$releaseProcessZh = Read-RepoText -RelativePath "docs\zh-CN\release-process.md"
$changelog = Read-RepoText -RelativePath "CHANGELOG.md"
$changelogZh = Read-RepoText -RelativePath "CHANGELOG.zh-CN.md"

$combinedPublicReleaseDocs = @(
    $security,
    $securityZh,
    $releaseProcess,
    $releaseProcessZh
) -join "`n"

Assert-NotContains `
    -Name "release docs do not claim versioned releases are absent" `
    -Text $combinedPublicReleaseDocs `
    -Pattern 'does not yet publish versioned releases|does not publish versioned release tags yet|尚未发布版本化 release|尚未发布版本化 release tag'

Assert-Contains `
    -Name "English security policy acknowledges v1.0.0 release" `
    -Text $security `
    -Pattern 'latest `main` branch, the lightweight `v1\.0\.0` public release'

Assert-Contains `
    -Name "Chinese security policy acknowledges v1.0.0 release" `
    -Text $securityZh `
    -Pattern '最新 `main` 分支、轻量级 `v1\.0\.0` 公开 release'

Assert-Contains `
    -Name "English security policy keeps main branch security-fix guidance" `
    -Text $security `
    -Pattern 'Security fixes are currently handled on the latest `main` branch[\s\S]*Release-branch or patch-release maintenance is not promised'

Assert-Contains `
    -Name "Chinese security policy keeps main branch security-fix guidance" `
    -Text $securityZh `
    -Pattern '安全修复当前在最新 `main` 分支处理[\s\S]*不承诺 release branch 或 patch release 维护'

Assert-Contains `
    -Name "English release process acknowledges v1.0.0 tag" `
    -Text $releaseProcess `
    -Pattern 'ADP-OS has a `v1\.0\.0` release tag'

Assert-Contains `
    -Name "Chinese release process acknowledges v1.0.0 tag" `
    -Text $releaseProcessZh `
    -Pattern 'ADP-OS 已有 `v1\.0\.0` release tag'

Assert-Contains `
    -Name "English changelog records release docs correction" `
    -Text $changelog `
    -Pattern 'Corrected release and security documentation to acknowledge the existing `v1\.0\.0` public release'

Assert-Contains `
    -Name "Chinese changelog records release docs correction" `
    -Text $changelogZh `
    -Pattern '修正 release 和 security 文档，明确项目已有 `v1\.0\.0` 公开 release'

Write-Output "Release documentation contracts OK"
