# ADP-OS survival validation and public demo documentation contracts.

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
        throw "Missing survival validation docs contract: $Name"
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
        throw "Forbidden survival validation docs text found: $Name"
    }
}

$readme = Read-RepoText -RelativePath "README.md"
$readmeZh = Read-RepoText -RelativePath "README.zh-CN.md"
$docsIndex = Read-RepoText -RelativePath "docs\README.md"
$docsIndexZh = Read-RepoText -RelativePath "docs\zh-CN\README.md"
$demoScript = Read-RepoText -RelativePath "docs\demo-script.md"
$demoScriptZh = Read-RepoText -RelativePath "docs\zh-CN\demo-script.md"
$demoCast = Read-RepoText -RelativePath "docs\demo.cast"
$survival = Read-RepoText -RelativePath "docs\survival-validation.md"
$survivalZh = Read-RepoText -RelativePath "docs\zh-CN\survival-validation.md"
$workspaces = Read-RepoText -RelativePath "docs\workspaces.md"
$workspacesZh = Read-RepoText -RelativePath "docs\zh-CN\workspaces.md"
$changelog = Read-RepoText -RelativePath "CHANGELOG.md"
$changelogZh = Read-RepoText -RelativePath "CHANGELOG.zh-CN.md"

$demoDocs = @(
    $demoScript,
    $demoScriptZh,
    $demoCast,
    $survival,
    $survivalZh
) -join "`n"

Assert-Contains `
    -Name "English demo script defines public-only recording checklist" `
    -Text $demoScript `
    -Pattern '## Public-Only Recording Checklist[\s\S]*public ADP-OS checkout[\s\S]*`adpos`[\s\S]*private maintainer[\s\S]*evidence ZIP[\s\S]*No public posting, automated outreach, scraping, bulk messages'

Assert-Contains `
    -Name "English demo checklist requires evidence ZIP entries" `
    -Text $demoScript `
    -Pattern 'README\.txt`?, `snapshot-hashes\.json`?, `operation-log\.json`?, `workspace-report\.md`?, and `adp-workspace\.json`?'

Assert-Contains `
    -Name "English recording setup requires privacy review" `
    -Text $demoScript `
    -Pattern 'Privacy review[\s\S]*Rewatch the recording[\s\S]*private maintainer context[\s\S]*private feedback notes'

Assert-Contains `
    -Name "Chinese demo script defines public recording checklist" `
    -Text $demoScriptZh `
    -Pattern '## 录制前公开核对[\s\S]*公开 ADP-OS checkout[\s\S]*`adpos`[\s\S]*私有维护者[\s\S]*evidence ZIP[\s\S]*不要公开发布、自动外联、爬取、群发'

Assert-Contains `
    -Name "Chinese demo checklist requires evidence ZIP entries" `
    -Text $demoScriptZh `
    -Pattern 'README\.txt`?、`snapshot-hashes\.json`?、`operation-log\.json`?、`workspace-report\.md`? 和 `adp-workspace\.json`?'

Assert-Contains `
    -Name "English survival guide links public-only checklist" `
    -Text $survival `
    -Pattern 'Pass the \[Public-Only Recording Checklist\]\(demo-script\.md#public-only-recording-checklist\)'

Assert-Contains `
    -Name "Chinese survival guide links public checklist" `
    -Text $survivalZh `
    -Pattern '先通过\[录制前公开核对\]\(demo-script\.md#录制前公开核对\)'

Assert-Contains `
    -Name "English survival demo readiness requires Windows 11" `
    -Text $survival `
    -Pattern 'Run the demo on a real Windows 11 host with VMware Workstation available and reachable'

Assert-Contains `
    -Name "Chinese survival demo readiness requires Windows 11" `
    -Text $survivalZh `
    -Pattern '在真实 Windows 11 主机上运行，且 VMware Workstation 可用并可访问'

Assert-Contains `
    -Name "English feedback record distinguishes unsupported Windows versions" `
    -Text $survival `
    -Pattern 'os: "Windows 11\|Unsupported Windows version\|Other"'

Assert-Contains `
    -Name "Chinese feedback record distinguishes unsupported Windows versions" `
    -Text $survivalZh `
    -Pattern 'os: "Windows 11\|Unsupported Windows version\|Other"'

Assert-NotContains `
    -Name "survival demo readiness does not advertise Windows 10 host support" `
    -Text (@($survival, $survivalZh) -join "`n") `
    -Pattern 'Windows 10/11|Windows 10\|Windows 11'

Assert-Contains `
    -Name "English root docs index exposes demo checklist" `
    -Text $readme `
    -Pattern '## Documentation[\s\S]*10-Minute Survival Value Demo / Recording Checklist'

Assert-Contains `
    -Name "Chinese root docs index exposes demo checklist" `
    -Text $readmeZh `
    -Pattern '## 文档[\s\S]*10 分钟生存价值演示 / 录制前核对'

Assert-Contains `
    -Name "English docs home exposes demo checklist in start section" `
    -Text $docsIndex `
    -Pattern '## Start Here[\s\S]*10-Minute Survival Value Demo / Recording Checklist'

Assert-Contains `
    -Name "Chinese docs home exposes demo checklist in start section" `
    -Text $docsIndexZh `
    -Pattern '## 从这里开始[\s\S]*10 分钟生存价值演示 / 录制前核对'

Assert-Contains `
    -Name "English README documents status Json flag" `
    -Text $readme `
    -Pattern 'adpos status \[frontend\|backend\|agent\|sandbox\] \[-Json\]'

Assert-Contains `
    -Name "Chinese README documents status Json flag" `
    -Text $readmeZh `
    -Pattern 'adpos status \[frontend\|backend\|agent\|sandbox\] \[-Json\]'

Assert-Contains `
    -Name "English README task mark states include validation_failed" `
    -Text $readme `
    -Pattern 'adpos workspace task mark <task-name> <prepared\|checkpointed\|checkpoint-waived\|running\|validated\|validation_failed\|reviewed\|rollback\|committed>'

Assert-Contains `
    -Name "Chinese README task mark states include validation_failed" `
    -Text $readmeZh `
    -Pattern 'adpos workspace task mark <task-name> <prepared\|checkpointed\|checkpoint-waived\|running\|validated\|validation_failed\|reviewed\|rollback\|committed>'

Assert-Contains `
    -Name "English workspace task state list includes validation_failed" `
    -Text $workspaces `
    -Pattern 'marked a task as `prepared`[\s\S]*`validation_failed`[\s\S]*`committed`'

Assert-Contains `
    -Name "Chinese workspace task state list includes validation_failed" `
    -Text $workspacesZh `
    -Pattern '任务标记为 `prepared`[\s\S]*`validation_failed`[\s\S]*`committed`'

Assert-Contains `
    -Name "English changelog records public demo checklist guardrails" `
    -Text $changelog `
    -Pattern 'Added public-only recording and live-demo checklist guardrails'

Assert-Contains `
    -Name "Chinese changelog records public demo checklist guardrails" `
    -Text $changelogZh `
    -Pattern '新增仅公开材料录制和现场演示核对护栏'

Assert-Contains `
    -Name "English changelog records dry-run readiness alignment" `
    -Text $changelog `
    -Pattern 'Aligned public demo dry-run readiness docs around the Windows 11 host requirement'

Assert-Contains `
    -Name "Chinese changelog records dry-run readiness alignment" `
    -Text $changelogZh `
    -Pattern '对齐公开 demo dry-run 就绪文档，明确 Windows 11 host 要求'

Assert-Contains `
    -Name "demo cast uses HTTPS clone" `
    -Text $demoCast `
    -Pattern 'git clone https://github\.com/karoc/ai-dev-platform\.git'

Assert-Contains `
    -Name "demo cast uses current Ubuntu ISO name" `
    -Text $demoCast `
    -Pattern 'ubuntu-26\.04-live-server-amd64\.iso'

Assert-Contains `
    -Name "demo cast previews agent runtime without explicit local ISO path" `
    -Text $demoCast `
    -Pattern 'adpos run agent -Plan'

Assert-Contains `
    -Name "demo cast uses current public agent sizing" `
    -Text $demoCast `
    -Pattern 'CPU/RAM:\s+6 vCPUs / 16384 MB[\s\S]*Disk:\s+160 GB'

Assert-NotContains `
    -Name "demo cast avoids SSH clone onboarding" `
    -Text $demoCast `
    -Pattern 'git@github\.com:karoc/ai-dev-platform\.git'

Assert-NotContains `
    -Name "demo cast avoids stale Ubuntu ISO name and local ISO path" `
    -Text $demoCast `
    -Pattern 'ubuntu-26\.04-server\.iso|D:\\\\iso\\\\ubuntu-26\.04\.iso'

Assert-NotContains `
    -Name "demo docs do not expose private maintainer repo path" `
    -Text $demoDocs `
    -Pattern 'ai-dev-platform-maintainer|/home/karoc|D:\\Dev'

Assert-NotContains `
    -Name "demo docs do not expose retired adp shell command" `
    -Text $demoDocs `
    -Pattern '(^|[^A-Za-z0-9_.-])(\.\\|\./)?adp\s+(setup|uninstall|iso|quickstart|init|up|status|capabilities|isolate|stop|sync|workspace|network|snapshot|restore|logs|doctor|destroy|precheck|help|version|validate|completion|serve|run|sandbox)\b'

Write-Output "Survival validation documentation contracts OK"
