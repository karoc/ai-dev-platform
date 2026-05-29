# ADP-OS documentation language-context link checks.
# Keeps translated docs from accidentally sending readers back to the default language.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$failed = $false

function Get-RelativePath {
    param(
        [string]$BasePath,
        [string]$TargetPath
    )

    return [System.IO.Path]::GetRelativePath($BasePath, $TargetPath).Replace("\", "/")
}

function Test-LanguageSwitchLink {
    param(
        [string]$Label,
        [string]$SourceLanguage
    )

    if ($SourceLanguage -eq "zh-CN" -and $Label -match "English") {
        return $true
    }

    if ($SourceLanguage -eq "en" -and $Label -match "简体中文|Chinese|中文") {
        return $true
    }

    return $false
}

function Get-DocumentLanguage {
    param([string]$Path)

    $relative = Get-RelativePath -BasePath $projectRoot -TargetPath $Path
    if ($relative -match '(^|/)zh-CN/' -or $relative -match '\.zh-CN\.md$') {
        return "zh-CN"
    }

    return "en"
}

function Get-TranslatedEquivalent {
    param(
        [string]$Path,
        [string]$TargetLanguage
    )

    $relative = Get-RelativePath -BasePath $projectRoot -TargetPath $Path

    if ($TargetLanguage -eq "zh-CN") {
        if ($relative -match '^docs/([^/]+\.md)$') {
            return (Join-Path $projectRoot ("docs/zh-CN/{0}" -f $Matches[1]))
        }

        if ($relative -match '^([^/]+)\.md$') {
            return (Join-Path $projectRoot ("{0}.zh-CN.md" -f $Matches[1]))
        }
    }

    if ($TargetLanguage -eq "en") {
        if ($relative -match '^docs/zh-CN/([^/]+\.md)$') {
            return (Join-Path $projectRoot ("docs/{0}" -f $Matches[1]))
        }

        if ($relative -match '^([^/]+)\.zh-CN\.md$') {
            return (Join-Path $projectRoot ("{0}.md" -f $Matches[1]))
        }
    }

    return $null
}

function Test-MarkdownPath {
    param([string]$Path)

    return $Path -match '\.md$'
}

function Assert-TranslatedDocPair {
    param(
        [string]$EnglishRelative,
        [string]$ChineseRelative
    )

    $englishPath = Join-Path $projectRoot $EnglishRelative
    $chinesePath = Join-Path $projectRoot $ChineseRelative

    if (-not (Test-Path -LiteralPath $englishPath)) {
        $script:failed = $true
        "Missing English documentation pair: $EnglishRelative"
    }

    if (-not (Test-Path -LiteralPath $chinesePath)) {
        $script:failed = $true
        "Missing Simplified Chinese documentation pair for {0}: {1}" -f $EnglishRelative, $ChineseRelative
    }
}

foreach ($rootDoc in @("README", "CHANGELOG", "CONTRIBUTING", "SECURITY", "SUPPORT", "build")) {
    Assert-TranslatedDocPair -EnglishRelative "$rootDoc.md" -ChineseRelative "$rootDoc.zh-CN.md"
}

foreach ($englishDoc in Get-ChildItem -Path (Join-Path $projectRoot "docs") -Filter *.md -File) {
    $relative = Get-RelativePath -BasePath $projectRoot -TargetPath $englishDoc.FullName
    $chineseRelative = "docs/zh-CN/$($englishDoc.Name)"
    Assert-TranslatedDocPair -EnglishRelative $relative -ChineseRelative $chineseRelative
}

foreach ($chineseDoc in Get-ChildItem -Path (Join-Path $projectRoot "docs/zh-CN") -Filter *.md -File) {
    $relative = Get-RelativePath -BasePath $projectRoot -TargetPath $chineseDoc.FullName
    $englishRelative = "docs/$($chineseDoc.Name)"
    Assert-TranslatedDocPair -EnglishRelative $englishRelative -ChineseRelative $relative
}

$files = Get-ChildItem -Path $projectRoot -Recurse -Filter *.md -File
foreach ($file in $files) {
    $sourceLanguage = Get-DocumentLanguage -Path $file.FullName
    $text = Get-Content -LiteralPath $file.FullName -Raw

    foreach ($match in [regex]::Matches($text, "\[([^\]]+)\]\(([^)]+)\)")) {
        $label = $match.Groups[1].Value.Trim()
        $target = $match.Groups[2].Value.Trim()

        if ($target.StartsWith("<") -and $target.EndsWith(">")) {
            $target = $target.Substring(1, $target.Length - 2)
        }

        if ($target -match "^[a-zA-Z][a-zA-Z0-9+.-]*:" -or $target.StartsWith("#")) {
            continue
        }

        $pathOnly = ($target -split "#", 2)[0]
        if ([string]::IsNullOrWhiteSpace($pathOnly) -or -not (Test-MarkdownPath -Path $pathOnly)) {
            continue
        }

        $resolved = [System.IO.Path]::GetFullPath((Join-Path $file.DirectoryName $pathOnly))
        if (-not (Test-Path -LiteralPath $resolved)) {
            continue
        }

        if (Test-LanguageSwitchLink -Label $label -SourceLanguage $sourceLanguage) {
            continue
        }

        $targetLanguage = Get-DocumentLanguage -Path $resolved
        if ($sourceLanguage -eq $targetLanguage) {
            continue
        }

        $expected = Get-TranslatedEquivalent -Path $resolved -TargetLanguage $sourceLanguage
        if (-not [string]::IsNullOrWhiteSpace($expected) -and (Test-Path -LiteralPath $expected)) {
            $failed = $true
            $sourceRelative = Get-RelativePath -BasePath $projectRoot -TargetPath $file.FullName
            $targetRelative = Get-RelativePath -BasePath $projectRoot -TargetPath $resolved
            $expectedRelative = Get-RelativePath -BasePath $projectRoot -TargetPath $expected
            "Language-context link mismatch in {0}: [{1}]({2}) resolves to {3}; use {4} or mark it as an explicit language switch." -f $sourceRelative, $label, $target, $targetRelative, $expectedRelative
        }
    }
}

if ($failed) {
    exit 1
}

Write-Output "Documentation language links OK"
