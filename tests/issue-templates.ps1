# ADP-OS GitHub issue template checks.
# Keeps public support routing, safety prompts, and required issue forms intact.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$templateRoot = Join-Path $projectRoot ".github\ISSUE_TEMPLATE"

function Read-YamlText {
    param([string]$RelativePath)

    $path = Join-Path $projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing issue template file: $RelativePath"
    }

    $text = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Issue template file is empty: $RelativePath"
    }

    return $text
}

function Assert-Contains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )

    if ($Text -notmatch $Pattern) {
        throw "$Name is missing expected pattern: $Pattern"
    }
}

function Assert-TemplateHasSafetyPrompt {
    param(
        [string]$Name,
        [string]$Text
    )

    foreach ($term in @("secrets", "private keys", "tokens", "VM disks", "ISO files", "private local paths")) {
        Assert-Contains -Name $Name -Text $Text -Pattern ([regex]::Escape($term))
    }
}

if (-not (Test-Path -LiteralPath $templateRoot)) {
    throw "Missing issue template directory: .github\ISSUE_TEMPLATE"
}

$config = Read-YamlText ".github\ISSUE_TEMPLATE\config.yml"
$bug = Read-YamlText ".github\ISSUE_TEMPLATE\bug_report.yml"
$feature = Read-YamlText ".github\ISSUE_TEMPLATE\feature_request.yml"
$question = Read-YamlText ".github\ISSUE_TEMPLATE\usage_question.yml"

Assert-Contains -Name "config.yml" -Text $config -Pattern "blank_issues_enabled:\s*false"
Assert-Contains -Name "config.yml" -Text $config -Pattern "Support guide"
Assert-Contains -Name "config.yml" -Text $config -Pattern "SUPPORT\.md"
Assert-Contains -Name "config.yml" -Text $config -Pattern "Security policy"
Assert-Contains -Name "config.yml" -Text $config -Pattern "SECURITY\.md"

Assert-Contains -Name "bug_report.yml" -Text $bug -Pattern "name:\s*Bug report"
Assert-Contains -Name "bug_report.yml" -Text $bug -Pattern "title:\s*`"\[Bug\]: "
Assert-Contains -Name "bug_report.yml" -Text $bug -Pattern "id:\s*steps"
Assert-Contains -Name "bug_report.yml" -Text $bug -Pattern "id:\s*diagnostics"
Assert-Contains -Name "bug_report.yml" -Text $bug -Pattern "tests\\validate\.ps1 -Quick"
Assert-Contains -Name "bug_report.yml" -Text $bug -Pattern "id:\s*safety"
Assert-Contains -Name "bug_report.yml" -Text $bug -Pattern "required:\s*true"
Assert-TemplateHasSafetyPrompt -Name "bug_report.yml" -Text $bug

Assert-Contains -Name "feature_request.yml" -Text $feature -Pattern "name:\s*Feature request"
Assert-Contains -Name "feature_request.yml" -Text $feature -Pattern "id:\s*problem"
Assert-Contains -Name "feature_request.yml" -Text $feature -Pattern "id:\s*proposal"
Assert-Contains -Name "feature_request.yml" -Text $feature -Pattern "agent-native-workflow"
Assert-Contains -Name "feature_request.yml" -Text $feature -Pattern "docker-or-devcontainer"
Assert-Contains -Name "feature_request.yml" -Text $feature -Pattern "id:\s*safety"
Assert-TemplateHasSafetyPrompt -Name "feature_request.yml" -Text $feature

Assert-Contains -Name "usage_question.yml" -Text $question -Pattern "name:\s*Usage question"
Assert-Contains -Name "usage_question.yml" -Text $question -Pattern "labels:\s*\[`"question`"\]"
Assert-Contains -Name "usage_question.yml" -Text $question -Pattern "id:\s*goal"
Assert-Contains -Name "usage_question.yml" -Text $question -Pattern "id:\s*runtime"
Assert-Contains -Name "usage_question.yml" -Text $question -Pattern "id:\s*commands"
Assert-Contains -Name "usage_question.yml" -Text $question -Pattern "workspace-planning"
Assert-Contains -Name "usage_question.yml" -Text $question -Pattern "release-readiness"
Assert-Contains -Name "usage_question.yml" -Text $question -Pattern "id:\s*safety"
Assert-TemplateHasSafetyPrompt -Name "usage_question.yml" -Text $question

Write-Output "Issue template checks OK"
