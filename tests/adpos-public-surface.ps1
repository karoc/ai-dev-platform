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
$knownCommands = "setup|uninstall|iso|quickstart|init|up|status|capabilities|stop|sync|workspace|network|snapshot|restore|logs|doctor|destroy|precheck|help|version|validate|completion|serve|run|sandbox"
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

Write-Output "adpos public surface checks OK"
