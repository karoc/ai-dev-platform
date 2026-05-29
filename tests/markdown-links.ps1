# ADP-OS Markdown local link checks.
# Verifies local Markdown targets and local heading anchors without adding a dependency.

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

function Test-ExternalTarget {
    param([string]$Target)

    return ($Target -match "^[a-zA-Z][a-zA-Z0-9+.-]*:")
}

function Normalize-MarkdownAnchor {
    param([string]$Text)

    $value = [System.Uri]::UnescapeDataString($Text).Trim().ToLowerInvariant()
    $value = $value -replace '<[^>]+>', ''
    $value = $value -replace '[`*_~\[\]\(\)]', ''
    $value = $value -replace '[^\p{L}\p{Nd}\s_-]', ''
    $value = $value -replace '\s+', '-'
    $value = $value -replace '-+', '-'
    return $value.Trim("-")
}

function Get-MarkdownAnchors {
    param([string]$Path)

    $anchors = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $seen = @{}
    $text = Get-Content -LiteralPath $Path -Raw

    foreach ($match in [regex]::Matches($text, "(?m)^(#{1,6})\s+(.+?)\s*#*\s*$")) {
        $heading = $match.Groups[2].Value.Trim()
        $baseAnchor = Normalize-MarkdownAnchor -Text $heading
        if ([string]::IsNullOrWhiteSpace($baseAnchor)) {
            continue
        }

        if (-not $seen.ContainsKey($baseAnchor)) {
            $seen[$baseAnchor] = 0
            [void]$anchors.Add($baseAnchor)
            continue
        }

        $seen[$baseAnchor] += 1
        [void]$anchors.Add(("{0}-{1}" -f $baseAnchor, $seen[$baseAnchor]))
    }

    return $anchors
}

$anchorCache = @{}

function Test-MarkdownAnchor {
    param(
        [string]$Path,
        [string]$Anchor
    )

    if ([string]::IsNullOrWhiteSpace($Anchor)) {
        return $true
    }

    if (-not $anchorCache.ContainsKey($Path)) {
        $anchorCache[$Path] = Get-MarkdownAnchors -Path $Path
    }

    $normalized = Normalize-MarkdownAnchor -Text $Anchor
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $true
    }

    return $anchorCache[$Path].Contains($normalized)
}

$files = Get-ChildItem -Path $projectRoot -Recurse -Filter *.md -File
foreach ($file in $files) {
    $text = Get-Content -LiteralPath $file.FullName -Raw
    foreach ($match in [regex]::Matches($text, "\[[^\]]+\]\(([^)]+)\)")) {
        $target = $match.Groups[1].Value.Trim()
        if ($target.StartsWith("<") -and $target.EndsWith(">")) {
            $target = $target.Substring(1, $target.Length - 2)
        }

        if ([string]::IsNullOrWhiteSpace($target) -or (Test-ExternalTarget -Target $target)) {
            continue
        }

        $parts = $target -split "#", 2
        $pathOnly = $parts[0]
        $anchor = if ($parts.Count -gt 1) { $parts[1] } else { "" }

        $resolved = $file.FullName
        if (-not [string]::IsNullOrWhiteSpace($pathOnly)) {
            $resolved = [System.IO.Path]::GetFullPath((Join-Path $file.DirectoryName $pathOnly))
            if (-not (Test-Path -LiteralPath $resolved)) {
                $failed = $true
                "Missing link in {0}: {1} -> {2}" -f $file.FullName, $target, $resolved
                continue
            }
        }

        if ([string]::IsNullOrWhiteSpace($anchor)) {
            continue
        }

        if ($resolved -notmatch '\.md$') {
            continue
        }

        if (-not (Test-MarkdownAnchor -Path $resolved -Anchor $anchor)) {
            $failed = $true
            $sourceRelative = Get-RelativePath -BasePath $projectRoot -TargetPath $file.FullName
            $targetRelative = Get-RelativePath -BasePath $projectRoot -TargetPath $resolved
            "Missing Markdown anchor in {0}: {1} -> {2}#{3}" -f $sourceRelative, $target, $targetRelative, $anchor
        }
    }
}

if ($failed) {
    exit 1
}

Write-Output "Markdown local links OK"
