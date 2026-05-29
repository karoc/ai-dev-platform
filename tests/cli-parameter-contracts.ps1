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
$validate = Read-Text "tests\validate.ps1"
$networkingDocs = Read-Text "docs\networking.md"
$networkingDocsZh = Read-Text "docs\zh-CN\networking.md"
$workspaceDocs = Read-Text "docs\workspaces.md"
$workspaceDocsZh = Read-Text "docs\zh-CN\workspaces.md"
$troubleshootingDocs = Read-Text "docs\troubleshooting.md"
$troubleshootingDocsZh = Read-Text "docs\zh-CN\troubleshooting.md"
$releaseReadinessDocs = Read-Text "docs\release-readiness.md"
$releaseReadinessDocsZh = Read-Text "docs\zh-CN\release-readiness.md"
$releaseProcessDocs = Read-Text "docs\release-process.md"
$releaseProcessDocsZh = Read-Text "docs\zh-CN\release-process.md"
$contributorWorkflowDocs = Read-Text "docs\contributor-workflows.md"
$contributorWorkflowDocsZh = Read-Text "docs\zh-CN\contributor-workflows.md"
$pullRequestTemplate = Read-Text ".github\pull_request_template.md"

Assert-Contains -Name "CLI help defined before use" -Text $cli -Pattern 'function\s+Show-Help[\s\S]*if\s*\(-not\s+\$Command\s+-or\s+\$Command\s+-eq\s+"help"\)'
Assert-Contains -Name "CLI propagates command exit codes" -Text $cli -Pattern 'Invoke-CommandFile[\s\S]*if\s*\(\$LASTEXITCODE\)\s*\{[\s\S]*exit\s+\$LASTEXITCODE'
Assert-Contains -Name "CI runs shared validation entry" -Text $ci -Pattern '\.\\tests\\validate\.ps1'
Assert-Contains -Name "shared validation runs installer smoke tests" -Text $validate -Pattern '\.\\tests\\install-smoke\.ps1'
Assert-Contains -Name "shared validation runs CLI smoke tests" -Text $validate -Pattern '\.\\tests\\cli-smoke\.ps1'
Assert-Contains -Name "shared validation runs documentation language link checks" -Text $validate -Pattern '\.\\tests\\docs-language-links\.ps1'
Assert-Contains -Name "shared validation runs configuration schema checks" -Text $validate -Pattern '\.\\tests\\config-schema\.ps1'
Assert-Contains -Name "shared validation runs artifact hygiene checks" -Text $validate -Pattern '\.\\tests\\artifact-hygiene\.ps1'
Assert-Contains -Name "documentation language checks enforce translated doc pairs" -Text (Read-Text "tests\docs-language-links.ps1") -Pattern 'Assert-TranslatedDocPair[\s\S]*README[\s\S]*CHANGELOG[\s\S]*build[\s\S]*docs/zh-CN'
Assert-Contains -Name "shared validation parses workspace recipes example" -Text $validate -Pattern 'configs\\workspace\.recipes\.example\.json'
Assert-Contains -Name "shared validation checks Markdown links" -Text $validate -Pattern 'Check Markdown local links'
Assert-Contains -Name "artifact hygiene ignores local assistant settings" -Text (Read-Text ".gitignore") -Pattern '(?m)^\.claude/[\s\S]*(?m)^\.codex/'
Assert-Contains -Name "artifact hygiene covers snapshot state and Windows NUL" -Text (Read-Text "tests\artifact-hygiene.ps1") -Pattern 'snapshots/[\s\S]*NUL'
Assert-Contains -Name "contributing shell syntax docs include common bootstrap script" -Text (Read-Text "CONTRIBUTING.md") -Pattern 'bootstrap/common/common\.sh'
Assert-Contains -Name "Chinese contributing shell syntax docs include common bootstrap script" -Text (Read-Text "CONTRIBUTING.zh-CN.md") -Pattern 'bootstrap/common/common\.sh'
Assert-Contains -Name "troubleshooting validation scope includes artifact hygiene" -Text $troubleshootingDocs -Pattern 'Repository validation fails[\s\S]*artifact hygiene'
Assert-Contains -Name "Chinese troubleshooting validation scope includes artifact hygiene" -Text $troubleshootingDocsZh -Pattern '仓库验证失败[\s\S]*artifact hygiene'
Assert-Contains -Name "shared validation supports quick local validation" -Text $validate -Pattern '\[switch\]\$Quick[\s\S]*if\s*\(\$Quick\)[\s\S]*\$SkipCliSmoke\s*=\s*\$true[\s\S]*\$SkipInstallerSmoke\s*=\s*\$true'
Assert-Contains -Name "shared validation supports local skip switches" -Text $validate -Pattern '\[switch\]\$SkipCliSmoke[\s\S]*\[switch\]\$SkipInstallerSmoke[\s\S]*\[switch\]\$SkipShellSyntax'
Assert-Contains -Name "CLI registers workspace command" -Text $cli -Pattern '\$validCommands\s*=\s*@\([\s\S]*"workspace"'
Assert-Contains -Name "CLI registers status command" -Text $cli -Pattern '\$validCommands\s*=\s*@\([\s\S]*"status"'
Assert-Contains -Name "CLI help includes status command" -Text $cli -Pattern 'adp status \[runtime\]'
Assert-Contains -Name "CLI help includes workspace command" -Text $cli -Pattern 'adp workspace <init\|show\|plan\|status\|dashboard\|report\|task>'
Assert-Contains -Name "up -IsoPath propagation" -Text $up -Pattern 'New-RuntimeVM[\s\S]*-IsoPath\s+\$IsoPath'
Assert-Contains -Name "vm factory IsoPath parameter" -Text $factory -Pattern 'function\s+New-RuntimeVM[\s\S]*\[string\]\$IsoPath'
Assert-Contains -Name "vm factory IsoPath resolution" -Text $factory -Pattern '\$resolvedIsoPath\s*=\s*if\s*\(\$IsoPath\)'
Assert-Contains -Name "up prints connection summary" -Text $up -Pattern 'function\s+Write-RuntimeConnectionSummary[\s\S]*Connection details:[\s\S]*adp status \$TargetRuntime'
Assert-Contains -Name "up provisioning wait passes runtime" -Text $up -Pattern 'Wait-AutoinstallComplete\s+-VmxPath\s+\$TargetVmxPath\s+-RuntimeName\s+\$TargetRuntime'
Assert-Contains -Name "vm factory provisioning prefers configured static IP" -Text $factory -Pattern 'function\s+Wait-AutoinstallComplete[\s\S]*Get-RuntimeStaticIP\s+\$RuntimeName[\s\S]*Testing configured static IP'
Assert-Contains -Name "vm factory readiness checks configured static IP" -Text $factory -Pattern 'function\s+Test-AutoinstallReady[\s\S]*Get-RuntimeStaticIP\s+\$RuntimeName[\s\S]*candidateIps'
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
Assert-Contains -Name "doctor reports VMware NAT prerequisites" -Text $doctor -Pattern 'VMware NAT prerequisites[\s\S]*Virtual Network Editor'
Assert-Contains -Name "networking docs explain NAT prerequisites" -Text $networkingDocs -Pattern '## Prerequisites[\s\S]*Virtual Network Editor[\s\S]*VMware NAT prerequisites'
Assert-Contains -Name "Chinese networking docs explain NAT prerequisites" -Text $networkingDocsZh -Pattern '## 前置条件[\s\S]*Virtual Network Editor[\s\S]*VMware NAT prerequisites'
Assert-Contains -Name "workspace docs mention recipes example" -Text $workspaceDocs -Pattern 'configs/workspace\.recipes\.example\.json'
Assert-Contains -Name "Chinese workspace docs mention recipes example" -Text $workspaceDocsZh -Pattern 'configs/workspace\.recipes\.example\.json'
Assert-Contains -Name "docs index links release readiness" -Text (Read-Text "docs\README.md") -Pattern 'Release Readiness\]\(release-readiness\.md\)'
Assert-Contains -Name "Chinese docs index links release readiness" -Text (Read-Text "docs\zh-CN\README.md") -Pattern '发布就绪\]\(release-readiness\.md\)'
Assert-Contains -Name "docs index links release process" -Text (Read-Text "docs\README.md") -Pattern 'Release Process\]\(release-process\.md\)'
Assert-Contains -Name "Chinese docs index links release process" -Text (Read-Text "docs\zh-CN\README.md") -Pattern '发布流程\]\(release-process\.md\)'
Assert-Contains -Name "docs index links contributor workflows" -Text (Read-Text "docs\README.md") -Pattern 'Contributor Workflows\]\(contributor-workflows\.md\)'
Assert-Contains -Name "Chinese docs index links contributor workflows" -Text (Read-Text "docs\zh-CN\README.md") -Pattern '贡献者工作流\]\(contributor-workflows\.md\)'
Assert-Contains -Name "README links release readiness" -Text (Read-Text "README.md") -Pattern 'Release Readiness\]\(docs/release-readiness\.md\)'
Assert-Contains -Name "Chinese README links release readiness" -Text (Read-Text "README.zh-CN.md") -Pattern '发布就绪\]\(docs/zh-CN/release-readiness\.md\)'
Assert-Contains -Name "README links release process" -Text (Read-Text "README.md") -Pattern 'Release Process\]\(docs/release-process\.md\)'
Assert-Contains -Name "Chinese README links release process" -Text (Read-Text "README.zh-CN.md") -Pattern '发布流程\]\(docs/zh-CN/release-process\.md\)'
Assert-Contains -Name "README links contributor workflows" -Text (Read-Text "README.md") -Pattern 'Contributor Workflows\]\(docs/contributor-workflows\.md\)'
Assert-Contains -Name "Chinese README links contributor workflows" -Text (Read-Text "README.zh-CN.md") -Pattern '贡献者工作流\]\(docs/zh-CN/contributor-workflows\.md\)'
Assert-Contains -Name "release readiness docs define decision policy" -Text $releaseReadinessDocs -Pattern '## Release Decision Policy[\s\S]*release candidate[\s\S]*release blocked[\s\S]*validation required[\s\S]*review required[\s\S]*governance incomplete'
Assert-Contains -Name "release readiness docs define maintainer checklist" -Text $releaseReadinessDocs -Pattern '## Maintainer Checklist[\s\S]*adp workspace dashboard[\s\S]*adp workspace report[\s\S]*release candidate'
Assert-Contains -Name "Chinese release readiness docs define decision policy" -Text $releaseReadinessDocsZh -Pattern '## 发布决策策略[\s\S]*release candidate[\s\S]*release blocked[\s\S]*validation required[\s\S]*review required[\s\S]*governance incomplete'
Assert-Contains -Name "Chinese release readiness docs define maintainer checklist" -Text $releaseReadinessDocsZh -Pattern '## 维护者检查清单[\s\S]*adp workspace dashboard[\s\S]*adp workspace report[\s\S]*release candidate'
Assert-Contains -Name "release process docs define maintainer flow" -Text $releaseProcessDocs -Pattern '## Maintainer Flow[\s\S]*\.\\tests\\validate\.ps1 -Quick[\s\S]*\.\\tests\\validate\.ps1[\s\S]*workspace report -Markdown[\s\S]*owner has authorized publication'
Assert-Contains -Name "release process docs define safety checks" -Text $releaseProcessDocs -Pattern '## Safety Checks[\s\S]*Secrets[\s\S]*adp-workspace\.state\.json[\s\S]*private maintainer'
Assert-Contains -Name "Chinese release process docs define maintainer flow" -Text $releaseProcessDocsZh -Pattern '## 维护者流程[\s\S]*\.\\tests\\validate\.ps1 -Quick[\s\S]*\.\\tests\\validate\.ps1[\s\S]*workspace report -Markdown[\s\S]*repository owner 授权发布'
Assert-Contains -Name "Chinese release process docs define safety checks" -Text $releaseProcessDocsZh -Pattern '## 安全检查[\s\S]*Secrets[\s\S]*adp-workspace\.state\.json[\s\S]*Private maintainer'
Assert-Contains -Name "contributor workflow docs include templates" -Text $contributorWorkflowDocs -Pattern '## Workflow Templates[\s\S]*Documentation or Small Maintenance[\s\S]*Frontend Browser Acceptance[\s\S]*Backend Validation[\s\S]*Broad Agent Refactor'
Assert-Contains -Name "contributor workflow docs include maintainer ritual" -Text $contributorWorkflowDocs -Pattern '## Maintainer Review Ritual[\s\S]*adp workspace dashboard[\s\S]*adp workspace report[\s\S]*release candidate'
Assert-Contains -Name "Chinese contributor workflow docs include templates" -Text $contributorWorkflowDocsZh -Pattern '## 工作流模板[\s\S]*文档或小型维护[\s\S]*前端浏览器验收[\s\S]*后端验证[\s\S]*大范围 Agent 重构'
Assert-Contains -Name "Chinese contributor workflow docs include maintainer ritual" -Text $contributorWorkflowDocsZh -Pattern '## 维护者评审流程[\s\S]*adp workspace dashboard[\s\S]*adp workspace report[\s\S]*release candidate'
Assert-Contains -Name "PR template asks for shared validation" -Text $pullRequestTemplate -Pattern '## Validation[\s\S]*\.\\tests\\validate\.ps1[\s\S]*\.\\tests\\validate\.ps1 -Quick'
Assert-Contains -Name "PR template asks for release readiness" -Text $pullRequestTemplate -Pattern '## Release Readiness[\s\S]*workspace task shape[\s\S]*workspace report -Markdown[\s\S]*Stale-task remediation[\s\S]*snapshot gate'
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
Assert-Contains -Name "workspace detects devcontainer metadata non-destructively" -Text $workspace -Pattern 'function\s+Get-WorkspaceDevContainerStatus[\s\S]*\.devcontainer/devcontainer\.json[\s\S]*Docker/dev container metadata can still be used inside the ADP runtime'
Assert-Contains -Name "workspace task risk supports snapshot gating" -Text $workspace -Pattern 'function\s+Get-WorkspaceTaskRisk[\s\S]*function\s+Test-WorkspaceTaskRequiresSnapshot[\s\S]*function\s+Get-WorkspaceSnapshotGate'
Assert-Contains -Name "workspace dashboard is non-destructive" -Text $workspace -Pattern 'Dashboard only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation commands will be run, and no Git commands will be run'
Assert-Contains -Name "workspace dashboard summarizes lifecycle state" -Text $workspace -Pattern 'Task lifecycle:[\s\S]*snapshot required:[\s\S]*execution:[\s\S]*rollback:[\s\S]*commit:'
Assert-Contains -Name "workspace dashboard can block execution on snapshot gate" -Text $workspace -Pattern 'blocked by snapshot gate'
Assert-Contains -Name "workspace report is non-destructive" -Text $workspace -Pattern 'Report only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation commands will be run, and no Git commands will be run'
Assert-Contains -Name "workspace report supports Markdown evidence" -Text $workspace -Pattern '\[switch\]\$Markdown[\s\S]*function\s+Write-WorkspaceReportMarkdown[\s\S]*Workspace Release Evidence[\s\S]*Markdown report only[\s\S]*Task Evidence[\s\S]*Maintainer Checklist'
Assert-Contains -Name "workspace report normalizes Markdown evidence paths" -Text $workspace -Pattern 'function\s+Format-WorkspaceEvidencePath[\s\S]*Get-ProjectRoot[\s\S]*Local state \| \$\(Format-WorkspaceMarkdownValue \(Format-WorkspaceEvidencePath \$resolvedStatePath\)\)'
Assert-Contains -Name "workspace report routes Markdown evidence" -Text $workspace -Pattern '"report"\s*\{[\s\S]*Write-WorkspaceReport\s+-Manifest\s+\$manifest\s+-ManifestPath\s+\$ManifestPath\s+-StatePath\s+\$StatePath\s+-Markdown:\$Markdown'
Assert-Contains -Name "workspace report summarizes task decisions" -Text $workspace -Pattern 'function\s+Write-WorkspaceReport[\s\S]*validation result:[\s\S]*review:[\s\S]*rollback:[\s\S]*commit:'
Assert-Contains -Name "workspace report has release handoff summary" -Text $workspace -Pattern 'function\s+Write-WorkspaceReportSummary[\s\S]*Release handoff summary:[\s\S]*blocked tasks:[\s\S]*ready for review:[\s\S]*ready to commit:[\s\S]*release gate:'
Assert-Contains -Name "workspace report has governance fields" -Text $workspace -Pattern 'function\s+New-WorkspaceReportItem[\s\S]*OwnerName[\s\S]*ReviewCadence[\s\S]*DueStatus[\s\S]*function\s+Write-WorkspaceReportSummary[\s\S]*owner gaps:[\s\S]*cadence gaps:[\s\S]*due attention:'
Assert-Contains -Name "workspace report has governance loop" -Text $workspace -Pattern 'function\s+Write-WorkspaceGovernanceLoop[\s\S]*Governance loop:[\s\S]*owner queues:[\s\S]*review cadence:[\s\S]*attention queue:'
Assert-Contains -Name "workspace report has decision queues" -Text $workspace -Pattern 'function\s+Write-WorkspaceDecisionQueues[\s\S]*Decision queues:[\s\S]*actions:[\s\S]*release readiness:[\s\S]*action:[\s\S]*release readiness:'
Assert-Contains -Name "workspace report has release policy" -Text $workspace -Pattern 'function\s+Write-WorkspaceReleasePolicy[\s\S]*Release decision policy:[\s\S]*decision:[\s\S]*blockers:[\s\S]*validation required:[\s\S]*review required:[\s\S]*release candidates:'
Assert-Contains -Name "workspace report has stale remediation" -Text $workspace -Pattern 'function\s+Write-WorkspaceStaleTaskRemediation[\s\S]*Stale-task remediation:[\s\S]*owner=.*cadence=.*timing=.*action=.*release='
Assert-Contains -Name "workspace run prints snapshot-first gate" -Text $workspace -Pattern 'Snapshot-first gate before broad agent work'
Assert-Contains -Name "workspace validate supports explicit execution" -Text $workspace -Pattern '\[switch\]\$Execute[\s\S]*\[switch\]\$Plan[\s\S]*function\s+Invoke-WorkspaceRemoteValidationCommand[\s\S]*Write-WorkspaceTaskValidate'
Assert-Contains -Name "workspace validate execution is scoped to validate command" -Text $workspace -Pattern '-Execute and -Plan are only supported with: adp workspace task validate <task-name>'
Assert-Contains -Name "workspace validate execution resolves task project" -Text $workspace -Pattern 'Find-WorkspaceProjectForTask[\s\S]*tasks\[\]\.project'
Assert-Contains -Name "workspace validate execution rejects unsafe project paths" -Text $workspace -Pattern 'Resolve-WorkspaceRemoteProjectPath[\s\S]*path cannot contain'
Assert-Contains -Name "workspace validate execution records validation result" -Text $workspace -Pattern 'Set-WorkspaceTaskValidationResult[\s\S]*validation_failed[\s\S]*Write-WorkspaceValidationResult'
Assert-Contains -Name "workspace validate execution prints readiness gate" -Text $workspace -Pattern 'Readiness gate:[\s\S]*snapshot-first gate[\s\S]*ssh target'
Assert-Contains -Name "workspace dashboard displays validation result" -Text $workspace -Pattern 'Format-WorkspaceValidationState[\s\S]*validation result:'
Assert-Contains -Name "workspace review displays validation result" -Text $workspace -Pattern 'recorded validation:[\s\S]*Write-WorkspaceValidationDetailLines[\s\S]*state file:'
Assert-Contains -Name "workspace review has decision gate" -Text $workspace -Pattern 'function\s+Get-WorkspaceReviewDecision[\s\S]*validation failed[\s\S]*validation result missing'
Assert-Contains -Name "workspace rollback reads validation state" -Text $workspace -Pattern 'function\s+Write-WorkspaceTaskRollback[\s\S]*Resolve-WorkspaceStatePath[\s\S]*recorded validation:'
Assert-Contains -Name "workspace rollback receives state path" -Text $workspace -Pattern '"rollback"\s*\{[\s\S]*Write-WorkspaceTaskRollback\s+-Task\s+\$task\s+-StatePath\s+\$LocalStatePath'
Assert-Contains -Name "workspace commit has readiness gate" -Text $workspace -Pattern 'function\s+Get-WorkspaceCommitDecision[\s\S]*blocked by validation[\s\S]*commit ready[\s\S]*review not recorded'
Assert-Contains -Name "workspace commit reads validation state" -Text $workspace -Pattern 'function\s+Write-WorkspaceTaskCommit[\s\S]*Resolve-WorkspaceStatePath[\s\S]*Commit readiness gate:[\s\S]*recorded validation:'
Assert-Contains -Name "workspace commit receives state path" -Text $workspace -Pattern '"commit"\s*\{[\s\S]*Write-WorkspaceTaskCommit\s+-Task\s+\$task\s+-ManifestPath\s+\$Path\s+-StatePath\s+\$LocalStatePath'
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
