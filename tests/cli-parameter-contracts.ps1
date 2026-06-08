# ADP-OS CLI parameter contract checks
# Guards against command switches being accepted but not propagated.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent

function Read-Text {
    param([string]$RelativePath)
    return Get-Content -LiteralPath (Join-Path $projectRoot $RelativePath) -Raw -Encoding UTF8
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

function Assert-NotContains {
    param(
        [string]$Name,
        [string]$Text,
        [string]$Pattern
    )

    if ($Text -match $Pattern) {
        throw "$Name contained retired or forbidden pattern: $Pattern"
    }
}

$up = Read-Text "cli\commands\up.ps1"
$init = Read-Text "cli\commands\init.ps1"
$install = Read-Text "install.ps1"
$setupScript = Read-Text "setup.ps1"
$quickstart = Read-Text "cli\commands\quickstart.ps1"
$setupCommand = Read-Text "cli\commands\setup.ps1"
$uninstallCommand = Read-Text "cli\commands\uninstall.ps1"
$setupCmd = Read-Text "setup.cmd"
$uninstallCmd = Read-Text "uninstall.cmd"
$adposCmd = Read-Text "adpos.cmd"
$registration = Read-Text "scripts\adpos-registration.ps1"
$agentBootstrap = Read-Text "bootstrap\agent\setup-agent.sh"
$factory = Read-Text "runtimes\vmware\vm-factory.ps1"
$factoryLayout = Read-Text "runtimes\vmware\vm-factory-layout.ps1"
$factoryIso = Read-Text "runtimes\vmware\vm-factory-iso.ps1"
$factoryVmx = Read-Text "runtimes\vmware\vm-factory-vmx.ps1"
$vmwareProvider = Read-Text "adapters\windows\vmware\vmware-provider.ps1"
$vmwarePaths = Read-Text "adapters\windows\vmware\vmware-paths.ps1"
$cli = Read-Text "cli\adp.ps1"
$cliHelp = Read-Text "cli\lib\help.ps1"
$suggestions = Read-Text "cli\lib\suggestions.ps1"
$configModule = Read-Text "core\config\config.ps1"
$localConfigEdit = Read-Text "core\config\local-config-edit.ps1"
$logger = Read-Text "core\logging\logger.ps1"
$logs = Read-Text "cli\commands\logs.ps1"
$sync = Read-Text "cli\commands\sync.ps1"
$network = Read-Text "cli\commands\network.ps1"
$isolate = Read-Text "cli\commands\isolate.ps1"
$doctor = Read-Text "cli\commands\doctor.ps1"
$status = Read-Text "cli\commands\status.ps1"
$sshAdapter = Read-Text "adapters\windows\ssh\ssh.ps1"
$runtimeModule = Read-Text "core\runtime\runtime.ps1"
$runtimeIdentity = Read-Text "core\runtime\runtime-identity.ps1"
$resourceConflicts = Read-Text "core\diagnostics\resource-conflicts.ps1"
$sshAliasDiagnostics = Read-Text "core\diagnostics\ssh-alias.ps1"
$workspace = Read-Text "cli\commands\workspace.ps1"
$workspaceGuides = Read-Text "cli\commands\workspace\guides.ps1"
$workspaceTasks = Read-Text "cli\commands\workspace\tasks.ps1"
$workspaceEvidence = Read-Text "cli\commands\workspace\evidence.ps1"
$workspaceSource = @($workspace, $workspaceGuides, $workspaceTasks, $workspaceEvidence) -join "`n"
$destroy = Read-Text "cli\commands\destroy.ps1"
$stop = Read-Text "cli\commands\stop.ps1"
$snapshot = Read-Text "cli\commands\snapshot.ps1"
$restore = Read-Text "cli\commands\restore.ps1"
$capabilities = Read-Text "cli\commands\capabilities.ps1"
$validateCmd = Read-Text "cli\commands\validate.ps1"
$completion = Read-Text "cli\commands\completion.ps1"
$ci = Read-Text ".github\workflows\ci.yml"
$validate = Read-Text "tests\validate.ps1"
$networkingDocs = Read-Text "docs\networking.md"
$networkingDocsZh = Read-Text "docs\zh-CN\networking.md"
$operationsDocs = Read-Text "docs\operations.md"
$operationsDocsZh = Read-Text "docs\zh-CN\operations.md"
$configurationDocs = Read-Text "docs\configuration.md"
$configurationDocsZh = Read-Text "docs\zh-CN\configuration.md"
$workspaceDocs = Read-Text "docs\workspaces.md"
$workspaceDocsZh = Read-Text "docs\zh-CN\workspaces.md"
$capabilitiesDocs = Read-Text "docs\capabilities.md"
$capabilitiesDocsZh = Read-Text "docs\zh-CN\capabilities.md"
$roadmapDocs = Read-Text "docs\roadmap.md"
$roadmapDocsZh = Read-Text "docs\zh-CN\roadmap.md"
$troubleshootingDocs = Read-Text "docs\troubleshooting.md"
$troubleshootingDocsZh = Read-Text "docs\zh-CN\troubleshooting.md"
$releaseReadinessDocs = Read-Text "docs\release-readiness.md"
$releaseReadinessDocsZh = Read-Text "docs\zh-CN\release-readiness.md"
$releaseProcessDocs = Read-Text "docs\release-process.md"
$releaseProcessDocsZh = Read-Text "docs\zh-CN\release-process.md"
$contributorWorkflowDocs = Read-Text "docs\contributor-workflows.md"
$contributorWorkflowDocsZh = Read-Text "docs\zh-CN\contributor-workflows.md"
$pullRequestTemplate = Read-Text ".github\pull_request_template.md"

Assert-Contains -Name "CLI loads help module before use" -Text $cli -Pattern 'cli\\lib\\help\.ps1[\s\S]*if\s*\(-not\s+\$Command\s+-or\s+\$Command\s+-eq\s+"help"\)'
Assert-Contains -Name "CLI help module defines Show-Help" -Text $cliHelp -Pattern 'function\s+Show-Help[\s\S]*function\s+Show-CommandHelp[\s\S]*function\s+Show-Version'
Assert-Contains -Name "CLI propagates command exit codes" -Text $cli -Pattern 'Invoke-CommandFile[\s\S]*if\s*\(\$LASTEXITCODE\s+-gt\s+0\)\s*\{[\s\S]*exit\s+\$LASTEXITCODE'
Assert-Contains -Name "CI runs shared validation entry" -Text $ci -Pattern '\.\\tests\\validate\.ps1'
Assert-Contains -Name "shared validation runs installer smoke tests" -Text $validate -Pattern '\.\\tests\\install-smoke\.ps1'
Assert-Contains -Name "shared validation runs CLI smoke tests" -Text $validate -Pattern '\.\\tests\\cli-smoke\.ps1'
Assert-Contains -Name "shared validation runs documentation language link checks" -Text $validate -Pattern '\.\\tests\\docs-language-links\.ps1'
Assert-Contains -Name "shared validation runs configuration schema checks" -Text $validate -Pattern '\.\\tests\\config-schema\.ps1'
Assert-Contains -Name "shared validation runs artifact hygiene checks" -Text $validate -Pattern '\.\\tests\\artifact-hygiene\.ps1'
Assert-Contains -Name "shared validation checks local config mutation boundaries" -Text $validate -Pattern '\.\\tests\\local-config-boundary\.ps1'
Assert-Contains -Name "shared validation checks Mutagen remediation behavior" -Text $validate -Pattern '\.\\tests\\mutagen-remediation\.ps1'
Assert-Contains -Name "shared validation checks adpos registration contract" -Text $validate -Pattern '\.\\tests\\adpos-registration-contract\.ps1'
Assert-Contains -Name "shared validation checks adpos registration decisions" -Text $validate -Pattern '\.\\tests\\adpos-registration-decision\.ps1'
Assert-Contains -Name "shared validation checks providerless entry routing" -Text $validate -Pattern '\.\\tests\\providerless-routing-contract\.ps1'
Assert-Contains -Name "shared validation checks checkout isolation plan" -Text $validate -Pattern '\.\\tests\\isolate-plan-contract\.ps1'
Assert-Contains -Name "shared validation checks checkout isolation apply" -Text $validate -Pattern '\.\\tests\\isolate-apply-contract\.ps1'
Assert-Contains -Name "shared validation checks resource conflict contracts" -Text $validate -Pattern '\.\\tests\\resource-conflicts-contract\.ps1'
Assert-Contains -Name "shared validation checks VMware runtime layout contracts" -Text $validate -Pattern '\.\\tests\\vmware-runtime-layout-contract\.ps1'
Assert-Contains -Name "shared validation checks SSH alias ownership contracts" -Text $validate -Pattern '\.\\tests\\ssh-alias-contract\.ps1'
Assert-Contains -Name "shared validation checks bounded SSH probe handling" -Text $validate -Pattern '\.\\tests\\ssh-timeout\.ps1'
Assert-Contains -Name "documentation language checks enforce translated doc pairs" -Text (Read-Text "tests\docs-language-links.ps1") -Pattern 'Assert-TranslatedDocPair[\s\S]*README[\s\S]*CHANGELOG[\s\S]*build[\s\S]*docs/zh-CN'
Assert-Contains -Name "shared validation parses workspace recipes example" -Text $validate -Pattern 'configs\\workspace\.recipes\.example\.json'
Assert-Contains -Name "shared validation checks Markdown links" -Text $validate -Pattern 'Check Markdown local links'
Assert-Contains -Name "artifact hygiene ignores local assistant settings" -Text (Read-Text ".gitignore") -Pattern '(?m)^\.claude/[\s\S]*(?m)^\.codex/'
Assert-Contains -Name "artifact hygiene ignores local config backups" -Text (Read-Text ".gitignore") -Pattern '(?m)^configs/local\.json\.bak\*'
Assert-Contains -Name "artifact hygiene covers snapshot state and Windows NUL" -Text (Read-Text "tests\artifact-hygiene.ps1") -Pattern 'snapshots/[\s\S]*NUL'
Assert-Contains -Name "contributing shell syntax docs include common bootstrap script" -Text (Read-Text "CONTRIBUTING.md") -Pattern 'bootstrap/common/common\.sh'
Assert-Contains -Name "Chinese contributing shell syntax docs include common bootstrap script" -Text (Read-Text "CONTRIBUTING.zh-CN.md") -Pattern 'bootstrap/common/common\.sh'
Assert-Contains -Name "troubleshooting validation scope includes artifact hygiene" -Text $troubleshootingDocs -Pattern 'Repository validation fails[\s\S]*artifact hygiene'
Assert-Contains -Name "Chinese troubleshooting validation scope includes artifact hygiene" -Text $troubleshootingDocsZh -Pattern '仓库验证失败[\s\S]*artifact hygiene'
Assert-Contains -Name "operations docs explain SSH alias target diagnostics" -Text $operationsDocs -Pattern 'user SSH config target[\s\S]*SSH alias mismatch[\s\S]*adpos sync status'
Assert-Contains -Name "Chinese operations docs explain SSH alias target diagnostics" -Text $operationsDocsZh -Pattern '用户 SSH config[\s\S]*SSH alias mismatch[\s\S]*adpos sync status'
Assert-Contains -Name "troubleshooting docs explain global SSH alias and Mutagen session limits" -Text $troubleshootingDocs -Pattern 'SSH aliases and Mutagen session names are also user-global resources[\s\S]*does not claim it can prove the original checkout owner'
Assert-Contains -Name "Chinese troubleshooting docs explain global SSH alias and Mutagen session limits" -Text $troubleshootingDocsZh -Pattern 'SSH alias 和 Mutagen session 名称也是用户级全局资源[\s\S]*不会声称能证明原始 checkout owner'
Assert-Contains -Name "shared validation supports quick local validation" -Text $validate -Pattern '\[switch\]\$Quick[\s\S]*if\s*\(\$Quick\)[\s\S]*\$SkipCliSmoke\s*=\s*\$true[\s\S]*\$SkipInstallerSmoke\s*=\s*\$true'
Assert-Contains -Name "shared validation supports local skip switches" -Text $validate -Pattern '\[switch\]\$SkipCliSmoke[\s\S]*\[switch\]\$SkipInstallerSmoke[\s\S]*\[switch\]\$SkipShellSyntax'
Assert-Contains -Name "CLI registers setup command" -Text $cli -Pattern '\$validCommands\s*=\s*@\([\s\S]*"setup"'
Assert-Contains -Name "CLI registers workspace command" -Text $cli -Pattern '\$validCommands\s*=\s*@\([\s\S]*"workspace"'
Assert-Contains -Name "CLI registers status command" -Text $cli -Pattern '\$validCommands\s*=\s*@\([\s\S]*"status"'
Assert-Contains -Name "CLI registers capabilities command" -Text $cli -Pattern '\$validCommands\s*=\s*@\([\s\S]*"capabilities"'
Assert-Contains -Name "CLI registers isolate command" -Text $cli -Pattern '\$validCommands\s*=\s*@\([\s\S]*"isolate"'
Assert-Contains -Name "CLI registers validate command" -Text $cli -Pattern '\$validCommands\s*=\s*@\([\s\S]*"validate"'
Assert-Contains -Name "CLI registers uninstall command" -Text $cli -Pattern '\$validCommands\s*=\s*@\([\s\S]*"uninstall"'
Assert-Contains -Name "validate command delegates to shared validation" -Text $validateCmd -Pattern 'tests\\validate\.ps1'
Assert-Contains -Name "validate command supports bilingual UI output" -Text $validateCmd -Pattern 'Write-UIHost[\s\S]*ADP-OS Repository Validation[\s\S]*ADP-OS 仓库验证'
Assert-Contains -Name "validate command propagates Quick flag" -Text $validateCmd -Pattern '\[switch\]\$Quick[\s\S]*-Quick'
Assert-Contains -Name "CLI help includes setup command in English" -Text $cliHelp -Pattern 'adpos setup"; Summary = "One-click install and register the global adpos command'
Assert-Contains -Name "CLI help includes setup command in Chinese" -Text $cliHelp -Pattern 'adpos setup"; Summary = "一键安装并注册全局 adpos 命令'
Assert-Contains -Name "CLI help includes validate command in English" -Text $cliHelp -Pattern 'adpos validate \[-Quick\] \[-SkipCliSmoke\] \[-SkipInstallerSmoke\] \[-SkipShellSyntax\]"; Summary = "Run repository validation tests'
Assert-Contains -Name "CLI help includes validate command in Chinese" -Text $cliHelp -Pattern 'adpos validate \[-Quick\] \[-SkipCliSmoke\] \[-SkipInstallerSmoke\] \[-SkipShellSyntax\]"; Summary = "运行仓库验证测试'
Assert-Contains -Name "CLI help includes status command" -Text $cliHelp -Pattern 'adpos status \[runtime\]'
Assert-Contains -Name "CLI help includes workspace command" -Text $cliHelp -Pattern 'adpos workspace <command> \[-ManifestPath <path>\] \[-Plan\] \[-Markdown\]'
Assert-Contains -Name "CLI help includes sandbox command" -Text $cliHelp -Pattern 'adpos sandbox <command\.\.\.> \[-Distro <name>\] \[-IsoPath <path>\]'
Assert-Contains -Name "CLI help includes capabilities command" -Text $cliHelp -Pattern 'adpos capabilities \[-Json\]"; Summary = "Show supported and planned runtime capabilities'
Assert-Contains -Name "CLI help includes isolate command" -Text $cliHelp -Pattern 'adpos isolate \[-Plan\|-Apply\] \[-Namespace <name>\]"; Summary = "Plan or apply multi-checkout local isolation settings'
Assert-Contains -Name "CLI help includes local network configuration command" -Text $cliHelp -Pattern 'adpos network configure-local \[-Plan\|-Apply\]"; Summary = "Plan or apply local VMnet8 overrides'
Assert-Contains -Name "CLI help includes uninstall command in English" -Text $cliHelp -Pattern 'adpos uninstall"; Summary = "One-click uninstall of global adpos registration; VMs/workspaces stay untouched'
Assert-Contains -Name "CLI help includes uninstall command in Chinese" -Text $cliHelp -Pattern 'adpos uninstall"; Summary = "一键卸载全局 adpos 命令注册，不删除 VM 或 workspace'
Assert-Contains -Name "completion registers only adpos user commands" -Text $completion -Pattern 'Register-ArgumentCompleter -CommandName adpos,adpos\.cmd'
Assert-Contains -Name "completion includes setup isolate and uninstall commands" -Text $completion -Pattern '"setup"[\s\S]*"isolate"[\s\S]*"uninstall"[\s\S]*complete -F _adpos_completion adpos adpos\.cmd'
Assert-NotContains -Name "completion does not expose retired adp shell aliases" -Text $completion -Pattern 'adp,adp\.cmd|adp\.ps1|complete -F _adpos_completion[^\r\n]*\sadp(\.cmd)?(\s|$)'
Assert-Contains -Name "isolate command supports explicit apply only for local config" -Text $isolate -Pattern 'Use either -Plan or -Apply, not both[\s\S]*Set-ADPCheckoutIsolationLocalConfig[\s\S]*Applied: updated configs\\\\local\.json[\s\S]*Not changed: VMs, SSH aliases, sync sessions, PATH entries, or global adpos bindings'
Assert-Contains -Name "local config edit helper preserves and backs up local config" -Text $localConfigEdit -Pattern 'function\s+Backup-ADPLocalConfig[\s\S]*Copy-Item[\s\S]*function\s+Set-ADPCheckoutIsolationLocalConfig[\s\S]*ChangedFields[\s\S]*Set-Content'
Assert-NotContains -Name "local config edit helper avoids host state mutation" -Text $localConfigEdit -Pattern 'SetEnvironmentVariable|Install-ADPOSCommandRegistration|Uninstall-ADPOSCommandRegistration|Initialize-VMware|Start-VM|Stop-VM|mutagen|ssh'
Assert-Contains -Name "configuration supports UI language preference" -Text $configModule -Pattern 'function\s+Get-UILanguage[\s\S]*ADP_LANG[\s\S]*config\.ui\.language[\s\S]*return "en"'
Assert-Contains -Name "configuration normalizes Simplified Chinese language aliases" -Text $configModule -Pattern 'function\s+Normalize-UILanguage[\s\S]*"zh"\s*\{\s*return "zh-CN"[\s\S]*"zh-cn"\s*\{\s*return "zh-CN"[\s\S]*"zh_cn"\s*\{\s*return "zh-CN"'
Assert-Contains -Name "configuration exposes shared localized UI helpers" -Text $configModule -Pattern 'function\s+Get-UIText[\s\S]*Get-UILanguage[\s\S]*zh-CN[\s\S]*function\s+Write-UIHost[\s\S]*Get-UIText'
Assert-Contains -Name "configuration exposes centralized runtime profile helpers" -Text $configModule -Pattern 'function\s+Get-RuntimeProfileName[\s\S]*profile[\s\S]*agent-high-io[\s\S]*function\s+Get-RuntimeProfileBadge[\s\S]*\[agent/high-IO\][\s\S]*function\s+Get-RuntimeProfileNoticeItems[\s\S]*Agent profile: high-IO runtime'
Assert-Contains -Name "runtime profile helpers keep danger as compatibility fallback only" -Text $configModule -Pattern 'Get-RuntimeProfileName[\s\S]*PSObject\.Properties\.Name -contains "profile"[\s\S]*PSObject\.Properties\.Name -contains "danger"[\s\S]*return "agent-high-io"[\s\S]*return "standard"'
Assert-Contains -Name "up uses centralized runtime profile notice helper" -Text $up -Pattern 'Get-RuntimeProfileNoticeItems -RuntimeName \$RuntimeName -Runtime \$rt[\s\S]*Write-Host \$notice\.Text -ForegroundColor \$notice\.Color'
Assert-Contains -Name "installer uses centralized runtime profile badge helper" -Text $install -Pattern 'Get-RuntimeProfileBadge -RuntimeName \$name -Runtime \$rt'
Assert-Contains -Name "agent bootstrap writes profile marker" -Text $agentBootstrap -Pattern 'Agent runtime profile: high-IO[\s\S]*AGENT_PROFILE\.txt'
Assert-NotContains -Name "installer no longer prints retired runtime danger badge" -Text $install -Pattern 'DANGER|\[高风险\]'
Assert-NotContains -Name "up no longer branches on retired danger field for user-facing notices" -Text $up -Pattern '\$rt\.danger|DANGER|\[高风险\]'
Assert-NotContains -Name "agent bootstrap no longer leaves retired danger-mode marker" -Text $agentBootstrap -Pattern 'dangerous mode|AGENT_DANGER_MODE\.txt|DANGER MODE'
Assert-Contains -Name "installer uses UI language preference after config initialization" -Text $install -Pattern 'Initialize-Config -ProjectRoot \$script:ProjectRoot[\s\S]*function\s+Get-InstallText[\s\S]*Get-UILanguage[\s\S]*function\s+Write-InstallBanner[\s\S]*阶段 1'
$installerSmoke = Read-Text "tests\install-smoke.ps1"
Assert-Contains -Name "installer smoke defaults to NoRegisterCommand" -Text $installerSmoke -Pattern 'if\s*\(\$effectiveArguments\s+-notcontains\s+"-NoRegisterCommand"\)[\s\S]*@\("-NoRegisterCommand"\)\s*\+\s*\$effectiveArguments'
Assert-Contains -Name "installer smoke isolates LOCALAPPDATA" -Text $installerSmoke -Pattern '\$localAppData\s*=\s*Join-Path \$userProfile "AppData\\Local"[\s\S]*LOCALAPPDATA\s*=\s*\$localAppData'
Assert-Contains -Name "installer smoke has Simplified Chinese case" -Text $installerSmoke -Pattern 'install zh-CN skip checks missing ISO guidance'
Assert-Contains -Name "installer smoke sets Simplified Chinese environment" -Text $installerSmoke -Pattern 'ADP_LANG\s*=\s*"zh-CN"'
Assert-Contains -Name "installer smoke expects Simplified Chinese completion" -Text $installerSmoke -Pattern 'ADP-OS 阶段 1 平台引导完成'
Assert-Contains -Name "install supports NoRegisterCommand parameter" -Text $install -Pattern 'param\([\s\S]*\[switch\]\$NoRegisterCommand'
Assert-Contains -Name "install skips command registration when requested" -Text $install -Pattern 'if\s*\(-not\s+\$NoRegisterCommand\)[\s\S]*else\s*\{[\s\S]*Global command registration skipped by -NoRegisterCommand'
Assert-Contains -Name "quickstart supports NoRegisterCommand parameter" -Text $quickstart -Pattern 'param\([\s\S]*\[switch\]\$NoRegisterCommand'
Assert-Contains -Name "quickstart passes NoRegisterCommand to install" -Text $quickstart -Pattern 'if\s*\(\$NoRegisterCommand\)\s*\{[\s\S]*\$installArgs\s*\+=\s*"-NoRegisterCommand"'
Assert-Contains -Name "setup supports NoRegisterCommand parameter" -Text $setupScript -Pattern 'param\([\s\S]*\[switch\]\$NoRegisterCommand'
Assert-Contains -Name "setup forwards NoRegisterCommand to quickstart" -Text $setupScript -Pattern 'if\s*\(\$NoRegisterCommand\)\s*\{[\s\S]*\$quickstartArgs\.NoRegisterCommand\s*=\s*\$true'
Assert-Contains -Name "setup command supports NoRegisterCommand parameter" -Text $setupCommand -Pattern 'param\([\s\S]*\[switch\]\$NoRegisterCommand'
Assert-Contains -Name "setup command forwards NoRegisterCommand to setup script" -Text $setupCommand -Pattern 'if\s*\(\$NoRegisterCommand\)\s*\{[\s\S]*\$setupArgs\s*\+=\s*"-NoRegisterCommand"'
Assert-Contains -Name "uninstall command delegates to uninstall script" -Text $uninstallCommand -Pattern 'uninstall\.ps1[\s\S]*-NonInteractive'
Assert-Contains -Name "setup cmd bootstraps missing PowerShell 7 with winget" -Text $setupCmd -Pattern ':InstallPowerShell7WithWinget[\s\S]*winget install --id Microsoft\.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent'
Assert-Contains -Name "uninstall cmd falls back to Windows PowerShell 5.1" -Text $uninstallCmd -Pattern 'UseWindowsPowerShell[\s\S]*WindowsPowerShell\\v1\.0\\powershell\.exe[\s\S]*uninstall\.ps1'
Assert-Contains -Name "adpos cmd allows uninstall without PowerShell 7" -Text $adposCmd -Pattern 'if /i "%~1"=="uninstall"[\s\S]*uninstall\.cmd'
Assert-Contains -Name "global shim delegates through ADPOS_HOME" -Text $registration -Pattern 'call ""%ADPOS_HOME%\\adpos\.cmd"" %\*'
Assert-Contains -Name "global registration stores project path in ADPOS_HOME environment variable" -Text $registration -Pattern 'SetEnvironmentVariable\(\$homeVariableName, \$resolvedProjectRoot, "User"\)'
Assert-Contains -Name "CLI help supports Simplified Chinese command rows" -Text $cliHelp -Pattern 'Get-ADPTopLevelCommandRows[\s\S]*"zh-CN"[\s\S]*初始化平台[\s\S]*显示运行时状态[\s\S]*显示已支持和计划中的运行时能力'
Assert-Contains -Name "CLI help supports Simplified Chinese command header" -Text $cliHelp -Pattern 'function\s+Show-Help[\s\S]*Get-UILanguage[\s\S]*"zh-CN"[\s\S]*命令:'
Assert-Contains -Name "CLI unknown command supports Simplified Chinese" -Text $cli -Pattern '未知命令: \$Command[\s\S]*可用命令:'
Assert-Contains -Name "CLI loads shared command suggestion helper" -Text $cli -Pattern 'cli\\lib\\suggestions\.ps1[\s\S]*Get-ADPCommandSuggestion'
Assert-Contains -Name "command suggestion helper defines distance-based matching" -Text $suggestions -Pattern 'function\s+Measure-ADPCommandDistance[\s\S]*function\s+Get-ADPCommandSuggestion[\s\S]*StartsWith[\s\S]*Distance'
Assert-Contains -Name "CLI suggests similar unknown commands in English" -Text $cli -Pattern 'Did you mean: adpos \$suggestion'
Assert-Contains -Name "CLI suggests similar unknown commands in Chinese" -Text $cli -Pattern '你是不是想运行: adpos \$suggestion'
Assert-Contains -Name "fresh deployment init supports Simplified Chinese" -Text $init -Pattern 'Write-UIHost[\s\S]*ADP-OS 初始化[\s\S]*SSH 密钥[\s\S]*运行时拓扑[\s\S]*ADP-OS 阶段 2 初始化完成'
Assert-Contains -Name "fresh deployment doctor supports Simplified Chinese" -Text $doctor -Pattern 'Write-UIHost[\s\S]*ADP-OS Doctor — 系统诊断[\s\S]*所有检查通过。平台状态健康。[\s\S]*首次使用检查清单[\s\S]*预计总耗时[\s\S]*平台设置'
Assert-Contains -Name "fresh deployment up plan supports Simplified Chinese" -Text $up -Pattern 'Write-UIHost[\s\S]*ADP-OS: 正在启动 \$RuntimeName[\s\S]*仅预览：不会创建、启动、provision 或 bootstrap 任何 VM[\s\S]*运行时:[\s\S]*工作区:'
Assert-Contains -Name "fresh deployment up NAT mismatch supports Simplified Chinese" -Text $up -Pattern '创建 VM 前检测到 VMware NAT 不匹配[\s\S]*方案 A：将 ADP 本机覆盖对齐到当前 host VMnet8[\s\S]*方案 B：保留 ADP 配置的网段[\s\S]*未创建任何 VM'
Assert-Contains -Name "fresh deployment status header supports Simplified Chinese" -Text $status -Pattern 'Write-UIHost[\s\S]*ADP-OS 状态[\s\S]*仅查看状态：不会修改 VM[\s\S]*本机配置:[\s\S]*网络:[\s\S]*SSH 密钥:'
Assert-Contains -Name "fresh deployment status runtime fields support Simplified Chinese" -Text $status -Pattern '配置 IP:[\s\S]*探测 IP:[\s\S]*工作区:[\s\S]*下一步:'
Assert-Contains -Name "status initializes provider with VM store" -Text $status -Pattern 'Resolve-Path "vm_store"[\s\S]*Initialize-Provider -ProviderType \$providerType -ProjectRoot \$script:ProjectRoot -InitArgs @\{VmStorePath = \$vmStore\}'
Assert-Contains -Name "runtime module initializes provider with VM store" -Text $runtimeModule -Pattern 'Resolve-Path "vm_store"[\s\S]*Initialize-Provider -ProviderType \$providerType -ProjectRoot \$script:ProjectRoot -InitArgs @\{VmStorePath = \$vmStore\}'
Assert-NotContains -Name "doctor uses provider runtime names for VM status" -Text $doctor -Pattern 'Get-VMStatus\s+\$vmxPath'
Assert-NotContains -Name "sync uses provider runtime names for VM status and IP" -Text $sync -Pattern 'Get-VM(?:Status|IP)\s+\$vmxPath'
Assert-NotContains -Name "network uses provider runtime names for VM status and IP" -Text $network -Pattern 'Get-VM(?:Status|IP)\s+\$vmxPath'
Assert-Contains -Name "fresh deployment network configure-local plan supports Simplified Chinese" -Text $network -Pattern '本机 VMware NAT 覆盖计划[\s\S]*本机配置:[\s\S]*当前配置 NAT:[\s\S]*目标本机 NAT:[\s\S]*运行时 static IP'
Assert-Contains -Name "fresh deployment network configure-local boundary supports Simplified Chinese" -Text $network -Pattern '建议的本机配置变更[\s\S]*仅预览：不会修改 configs\\local\.json[\s\S]*未修改任何文件'
Assert-Contains -Name "fresh deployment network configure-local apply supports Simplified Chinese" -Text $network -Pattern '已用 host VMnet8 NAT 设置更新 configs\\local\.json[\s\S]*备份:[\s\S]*下一步:'
Assert-Contains -Name "configuration docs explain UI language preference" -Text $configurationDocs -Pattern 'platform\.ui\.language[\s\S]*installer and CLI language[\s\S]*Supported values are `en` and `zh-CN`[\s\S]*`ADP_LANG` takes precedence'
Assert-Contains -Name "Chinese configuration docs explain UI language preference" -Text $configurationDocsZh -Pattern 'platform\.ui\.language[\s\S]*installer 和 CLI 用户可见语言[\s\S]*当前支持的值为 `en` 和 `zh-CN`[\s\S]*`ADP_LANG` 优先级高于配置'
Assert-Contains -Name "capabilities command documents supported and planned carriers" -Text (Read-Text "cli\commands\capabilities.ps1") -Pattern 'Capabilities only: no VMs[\s\S]*\[supported\] vmware-workstation[\s\S]*\[planned\] hyper-v[\s\S]*\[planned\] kvm-libvirt[\s\S]*\[planned\] macos-vm[\s\S]*Docker and dev containers are runtime-internal project tools today'
Assert-Contains -Name "capabilities docs define support boundary" -Text $capabilitiesDocs -Pattern '## Runtime Carrier Matrix[\s\S]*VMware Workstation[\s\S]*Supported on Windows[\s\S]*Hyper-V[\s\S]*Not implemented[\s\S]*Docker and dev containers are runtime-internal project tools today'
Assert-Contains -Name "Chinese capabilities docs define support boundary" -Text $capabilitiesDocsZh -Pattern '## 运行时承载矩阵[\s\S]*VMware Workstation[\s\S]*Windows 上已支持[\s\S]*Hyper-V[\s\S]*尚未实现[\s\S]*Docker 和 dev containers 当前是 runtime 内部项目工具'
Assert-Contains -Name "roadmap separates current workspace surface from remaining directions" -Text $roadmapDocs -Pattern '## Workspace Orchestration[\s\S]*Current public surface:[\s\S]*workspace create \[-Plan\][\s\S]*workspace open[\s\S]*workspace sync[\s\S]*workspace project[\s\S]*workspace report -Markdown[\s\S]*Remaining directions:[\s\S]*safer clone/import guidance'
Assert-Contains -Name "Chinese roadmap separates current workspace surface from remaining directions" -Text $roadmapDocsZh -Pattern '## 工作区编排[\s\S]*当前公开能力：[\s\S]*workspace create \[-Plan\][\s\S]*workspace open[\s\S]*workspace sync[\s\S]*workspace project[\s\S]*workspace report -Markdown[\s\S]*剩余方向：[\s\S]*clone/import guidance'
Assert-Contains -Name "roadmap separates current agent-native surface from broad execution direction" -Text $roadmapDocs -Pattern '## Agent-Native Development[\s\S]*Current public surface:[\s\S]*Task lifecycle commands[\s\S]*checkpoint-waived[\s\S]*Milestone and evaluation planning surfaces[\s\S]*Remaining directions:[\s\S]*Keep broad task execution plan-only'
Assert-Contains -Name "Chinese roadmap separates current agent-native surface from broad execution direction" -Text $roadmapDocsZh -Pattern '## Agent 原生开发[\s\S]*当前公开能力：[\s\S]*Task lifecycle commands[\s\S]*checkpoint-waived[\s\S]*Milestone 和 evaluation planning surfaces[\s\S]*剩余方向：[\s\S]*broad task execution 保持 plan-only'
Assert-Contains -Name "up -IsoPath propagation" -Text $up -Pattern 'New-RuntimeVM[\s\S]*-IsoPath\s+\$IsoPath'
Assert-Contains -Name "vm factory IsoPath parameter" -Text $factory -Pattern 'function\s+New-RuntimeVM[\s\S]*\[string\]\$IsoPath'
Assert-Contains -Name "vm factory IsoPath resolution" -Text $factory -Pattern '\$resolvedIsoPath\s*=\s*if\s*\(\$IsoPath\)'
Assert-Contains -Name "vm factory loads split helper modules" -Text $factory -Pattern 'vm-factory-layout\.ps1[\s\S]*vm-factory-iso\.ps1[\s\S]*vm-factory-vmx\.ps1'
Assert-Contains -Name "vm factory layout defines resource paths" -Text $factoryLayout -Pattern 'function\s+Get-ADPVMwareRuntimeLayout[\s\S]*RuntimeResourceName[\s\S]*VmPath[\s\S]*VmxPath[\s\S]*SeedSourceDir[\s\S]*AutoinstallIsoPath[\s\S]*CloudInitInstanceId[\s\S]*InstallIsoLabel'
Assert-Contains -Name "vm factory runtime creation uses layout paths" -Text $factory -Pattern 'function\s+New-RuntimeVM[\s\S]*Get-ADPVMwareRuntimeLayout[\s\S]*\$layout\.VmPath[\s\S]*\$layout\.VmxPath[\s\S]*\$layout\.Hostname[\s\S]*\$layout\.SeedSourceDir'
Assert-Contains -Name "vm factory accepts explicit runtime layout" -Text $factory -Pattern 'function\s+New-RuntimeVM[\s\S]*\[object\]\$Layout[\s\S]*\$layout\s*=\s*if\s*\(\$Layout\)[\s\S]*Get-ADPVMwareRuntimeLayout'
Assert-Contains -Name "up builds namespaced factory layout before VM creation" -Text $up -Pattern '\$factoryLayout\s*=\s*Get-ADPVMwareRuntimeLayout[\s\S]*-Namespace\s+\$resourceProfile\.RuntimeNamespace[\s\S]*-RuntimeResourceName\s+\$resourceProfile\.RuntimeResourceName'
Assert-Contains -Name "up passes factory layout into VM creation" -Text $up -Pattern 'New-RuntimeVM[\s\S]*-RuntimeName\s+\$RuntimeName[\s\S]*-IsoPath\s+\$IsoPath[\s\S]*-Layout\s+\$factoryLayout'
Assert-Contains -Name "vm factory seed creation uses layout paths" -Text $factory -Pattern 'function\s+New-SeedISO[\s\S]*\[object\]\$Layout[\s\S]*\$Layout\.SeedSourceDir[\s\S]*\$Layout\.CloudInitInstanceId[\s\S]*\$Layout\.SeedIsoPath'
Assert-Contains -Name "vm factory autoinstall ISO uses layout paths" -Text $factoryIso -Pattern 'function\s+New-AutoinstallISO[\s\S]*\[object\]\$Layout[\s\S]*\$Layout\.AutoinstallIsoPath[\s\S]*\$Layout\.AutoinstallWorkDir[\s\S]*\$Layout\.InstallIsoLabel'
Assert-Contains -Name "vm factory VMX creation uses layout paths" -Text $factoryVmx -Pattern 'function\s+New-VMX[\s\S]*\[object\]\$Layout[\s\S]*\$Layout\.VmName[\s\S]*\$Layout\.VmxPath[\s\S]*\$Layout\.VmdkFileName'
Assert-Contains -Name "VMware provider path helper defines resource path resolver" -Text $vmwarePaths -Pattern 'function\s+Get-ADPVMwareProviderRuntimePath[\s\S]*RuntimeResourceName[\s\S]*VmName[\s\S]*VmxPath'
Assert-Contains -Name "VMware provider consumes path helper" -Text $vmwareProvider -Pattern 'vmware-paths\.ps1[\s\S]*function\s+Resolve-ProviderVmxPath[\s\S]*Get-ADPVMwareProviderRuntimePath[\s\S]*function\s+Get-InternalVMXPath[\s\S]*Get-ADPVMwareProviderRuntimePath'
Assert-Contains -Name "up prints connection summary" -Text $up -Pattern 'function\s+Write-RuntimeConnectionSummary[\s\S]*Connection details:[\s\S]*adpos status \$TargetRuntime'
Assert-Contains -Name "up provisioning wait passes runtime" -Text $up -Pattern 'Wait-AutoinstallComplete\s+-VmxPath\s+\$TargetVmxPath\s+-RuntimeName\s+\$TargetRuntime'
Assert-Contains -Name "vm factory provisioning prefers configured static IP" -Text $factory -Pattern 'function\s+Wait-AutoinstallComplete[\s\S]*Get-RuntimeStaticIP\s+\$RuntimeName[\s\S]*configured.*\$ip'
Assert-Contains -Name "vm factory explains long autoinstall wait" -Text $factory -Pattern 'real guest OS installation[\s\S]*真实的 guest OS 安装[\s\S]*Typical duration: 15-45 minutes[\s\S]*通常需要 15-45 分钟[\s\S]*Installing Ubuntu inside VM \(watched wait, not stuck; repeated signals can be normal\)[\s\S]*正在 VM 内安装 Ubuntu（受监控等待，不是卡住；重复信号可能正常）[\s\S]*Install monitor active: INSTALLING Ubuntu in the VM[\s\S]*安装监视器已启动：正在 VM 内安装 Ubuntu[\s\S]*Watch path: installer boot -> OS install -> reboot -> SSH auth-pending -> provision marker -> bootstrap'
Assert-Contains -Name "vm factory reports localized autoinstall progress instead of vague waiting" -Text $factory -Pattern '\[install monitor\] INSTALLING Ubuntu in VM - watched wait, not stuck[\s\S]*\[安装监视器\] 正在 VM 中安装 Ubuntu - 受监控等待，不是卡住[\s\S]*status: state=installing activity=installing-ubuntu status=watching current-op=readiness-check wait-mode=watched progress=indeterminate user-action=keep-open diagnostics=vmware-console-after-20min phase=ubuntu-autoinstall[\s\S]*time: expected=15-45min timeout=\$\{TimeoutMinutes\}min elapsed=\$\{elapsed\}min remaining=\$\{remaining\}min next-check=\$\{nextCheckSeconds\}s[\s\S]*含义: Ubuntu 仍在安装、重启或准备 installed-system user[\s\S]*就绪信号\(readiness signals\):[\s\S]*下一步: ADP 会在 \$\{nextCheckSeconds\}s 后重新检查就绪状态[\s\S]*操作: 保持此命令运行[\s\S]*Autoinstall 确认在 \$\{TimeoutMinutes\}min 后超时'
Assert-Contains -Name "vm factory uses indeterminate PowerShell progress without fake percentages" -Text $factory -Pattern 'Progress model: indeterminate OS install[\s\S]*不确定时长的 OS 安装[\s\S]*Progress indicator: PowerShell shows an indeterminate activity indicator[\s\S]*Write-Progress[\s\S]*-Activity \(Get-UIText -English "Installing Ubuntu in ADP VM" -Chinese "正在 ADP VM 中安装 Ubuntu"\)[\s\S]*-SecondsRemaining -1'
Assert-Contains -Name "vm factory explains probes as readiness signals" -Text $factory -Pattern 'Readiness signals checked every \$\{CheckIntervalSeconds\}s[\s\S]*每 \$\{CheckIntervalSeconds\}s 检查就绪信号（readiness signals）[\s\S]*IP and SSH probe failures are readiness signals during install[\s\S]*安装期间的 IP 和 SSH probe failure 只是就绪信号（readiness signals）'
Assert-Contains -Name "vm factory tells users when action is needed" -Text $factory -Pattern 'Normal during install: the same signal can repeat[\s\S]*安装期间的正常现象[\s\S]*\[install monitor\] INSTALLING Ubuntu in VM - heartbeat active, repeated signal is normal[\s\S]*\[安装监视器\] 正在 VM 中安装 Ubuntu - 心跳正常，重复信号可能是正常现象[\s\S]*normal=yes[\s\S]*就绪信号（readiness signals）不变化可能是正常现象[\s\S]*same signal has repeated for about \$\{sameMinutes\}min[\s\S]*同一信号已重复约 \$\{sameMinutes\}min'
Assert-Contains -Name "vm factory reports auth-pending as install readiness state" -Text $factory -Pattern 'auth-pending; SSH is up but installed-system user/key or provision marker is not ready'
Assert-Contains -Name "vm factory avoids long blocking IP probes during autoinstall monitor" -Text $factory -Pattern 'Get-VMIPQuick\s+-VmxPath\s+\$VmxPath\s+-TimeoutSeconds\s+5'
Assert-Contains -Name "vm factory captures xorriso output during autoinstall ISO remaster" -Text $factoryIso -Pattern 'function\s+Invoke-CapturedNativeCommand[\s\S]*& \$FilePath @Arguments 2>&1[\s\S]*function\s+New-AutoinstallISO[\s\S]*Invoke-CapturedNativeCommand -FilePath \$tool\.Path -Arguments @\("bash", "-lc", \$command\)[\s\S]*xorriso failed with exit code'
Assert-Contains -Name "vm factory readiness checks configured static IP" -Text $factory -Pattern 'function\s+Test-AutoinstallReady[\s\S]*Get-RuntimeStaticIP\s+\$RuntimeName[\s\S]*candidateIps'
Assert-Contains -Name "vm factory readiness accepts target VMX path" -Text $factory -Pattern 'function\s+Test-AutoinstallReady[\s\S]*\[string\]\$VmxPath[\s\S]*\$resolvedVmxPath\s*=\s*\$VmxPath[\s\S]*Get-VMStatus\s+\$resolvedVmxPath'
Assert-Contains -Name "init -NoProvision propagation" -Text $init -Pattern 'NoProvision\s*=\s*\$NoProvision'
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
Assert-Contains -Name "sync status reports ADP runtime summary before raw Mutagen list" -Text $sync -Pattern 'ADP runtime sync summary:[\s\S]*Write-SyncRuntimeSummary[\s\S]*Sync status:[\s\S]*sync", "list"'
Assert-Contains -Name "sync summary gives stale session remediation" -Text $sync -Pattern 'fix:\s+adpos sync stop \$TargetRuntime; adpos sync start \$TargetRuntime'
Assert-Contains -Name "sync summary treats uncreated runtime stale sessions as cleanup guidance" -Text $sync -Pattern 'Get-VMStatus[\s\S]*stale-session[\s\S]*cleanup:\s+adpos sync stop \$TargetRuntime[\s\S]*next:\s+adpos up \$TargetRuntime; adpos sync start \$TargetRuntime'

# Localization coverage: extended runtime commands use bilingual Write-UIHost
Assert-Contains -Name "destroy uses bilingual UI output" -Text $destroy -Pattern 'Write-UIHost[\s\S]*?-English[\s\S]*?-Chinese[\s\S]*?DESTROY[\s\S]*?Plan only[\s\S]*?PERMANENTLY DELETE'
Assert-Contains -Name "stop uses bilingual UI output" -Text $stop -Pattern 'Write-UIHost[\s\S]*?-English[\s\S]*?-Chinese[\s\S]*?Stopping[\s\S]*?force-stopped'
Assert-Contains -Name "snapshot uses bilingual UI output" -Text $snapshot -Pattern 'Write-UIHost[\s\S]*?-English[\s\S]*?-Chinese[\s\S]*?already exists[\s\S]*?created successfully'
Assert-Contains -Name "restore uses bilingual UI output" -Text $restore -Pattern 'Write-UIHost[\s\S]*?-English[\s\S]*?RESTORE[\s\S]*?-Chinese[\s\S]*?Plan only[\s\S]*?Force.*confirm'
Assert-Contains -Name "logs uses bilingual UI output" -Text $logs -Pattern 'Write-UIHost[\s\S]*?-English[\s\S]*?-Chinese[\s\S]*?Platform Log[\s\S]*?VM console'
Assert-Contains -Name "sync uses bilingual UI output" -Text $sync -Pattern 'Write-UIHost[\s\S]*?-English[\s\S]*?-Chinese[\s\S]*?sync summary[\s\S]*?Starting sync[\s\S]*?Stopping sync'
Assert-Contains -Name "capabilities uses bilingual UI output" -Text $capabilities -Pattern 'Write-UIHost[\s\S]*?-English[\s\S]*?-Chinese[\s\S]*?Current support[\s\S]*?carrier matrix[\s\S]*?adapter matrix'
Assert-Contains -Name "doctor checks WSL xorriso" -Text $doctor -Pattern 'WSL xorriso'
Assert-Contains -Name "doctor checks ISO shape" -Text $doctor -Pattern 'ISO shape'
Assert-Contains -Name "doctor reports VMware NAT prerequisites" -Text $doctor -Pattern 'VMware NAT prerequisites[\s\S]*host VMnet8'
Assert-Contains -Name "doctor compares configured NAT to host VMnet8" -Text $doctor -Pattern 'Test-VMwareNatConfigMatchesHost[\s\S]*VMware NAT host match[\s\S]*VMware NAT gateway host range[\s\S]*Option A: align ADP local overrides[\s\S]*network configure-local -Plan[\s\S]*network configure-local -Apply[\s\S]*Option B: keep ADP'
Assert-Contains -Name "doctor reports VMware running VM count accurately" -Text $doctor -Pattern 'Get-RunningVMs[\s\S]*VMware running VMs[\s\S]*running'
Assert-Contains -Name "up blocks VM creation on NAT mismatch" -Text $up -Pattern 'function\s+Assert-VMwareNatReadyForRuntimeCreate[\s\S]*VMware NAT mismatch detected before VM creation[\s\S]*Option A: Align ADP local overrides[\s\S]*network configure-local -Plan[\s\S]*network configure-local -Apply[\s\S]*Option B: Keep ADP[\s\S]*change VMware VMnet8[\s\S]*No VM was created'
Assert-Contains -Name "status reports seed network drift" -Text (Read-Text "cli\commands\status.ps1") -Pattern 'network drift:[\s\S]*seed uses[\s\S]*Write-StatusNetworkDriftRemediation'
Assert-Contains -Name "status explains stale networking remediation paths" -Text (Read-Text "cli\commands\status.ps1") -Pattern 'function\s+Write-StatusNetworkDriftRemediation[\s\S]*Rebuild when the VM can be recreated[\s\S]*In-place guest fix[\s\S]*Admin-only temporary host-route workaround'
Assert-Contains -Name "status distinguishes SSH auth pending" -Text (Read-Text "cli\commands\status.ps1") -Pattern 'auth-pending[\s\S]*SSH port is open, but the ADP key is not accepted yet'
Assert-Contains -Name "SSH adapter uses bounded process probes" -Text $sshAdapter -Pattern 'function\s+Invoke-AdpSshCommand[\s\S]*UserKnownHostsFile=NUL[\s\S]*ConnectionAttempts=1[\s\S]*WaitForExit\(\$TimeoutSeconds \* 1000\)[\s\S]*Kill\(\)[\s\S]*ssh-timeout'
Assert-Contains -Name "bounded SSH helper does not leak SSH exit code" -Text $sshAdapter -Pattern 'finally\s*\{[\s\S]*\$global:LASTEXITCODE\s*=\s*0'
Assert-Contains -Name "status uses bounded SSH reachability helper" -Text $status -Pattern 'adapters\\windows\\ssh\\ssh\.ps1[\s\S]*function\s+Test-StatusSSHReachable[\s\S]*Test-AdpSshReachability[\s\S]*-TimeoutSeconds 12[\s\S]*ssh-timeout'
Assert-Contains -Name "up uses bounded SSH provision marker helper" -Text $up -Pattern 'adapters\\windows\\ssh\\ssh\.ps1[\s\S]*function\s+Test-RuntimeConnectionProvisionMarkerViaSSH[\s\S]*Invoke-AdpSshCommand[\s\S]*/home/adp/\.adp-provisioned[\s\S]*-TimeoutSeconds 12[\s\S]*ssh-timeout'
Assert-Contains -Name "status reports duplicate running runtime VMs" -Text (Read-Text "cli\commands\status.ps1") -Pattern 'ambiguous-duplicate[\s\S]*duplicate VM:[\s\S]*running ADP runtime resource name also found outside this checkout[\s\S]*other checkout or stale VM'
Assert-Contains -Name "resource conflict helper defines runtime profiles and duplicate VM gates" -Text $resourceConflicts -Pattern 'function\s+Get-ADPRuntimeResourceProfile[\s\S]*Resolve-Path "workspace_root"[\s\S]*Resolve-Path "vm_store"[\s\S]*SshAlias[\s\S]*MutagenSession[\s\S]*function\s+Get-ADPRuntimeDuplicateConflict[\s\S]*targetResourceName[\s\S]*RuntimeResourceName[\s\S]*BlocksRuntimeMutation'
Assert-Contains -Name "runtime identity helper defines runtime namespace resource names" -Text $runtimeIdentity -Pattern 'function\s+Normalize-ADPRuntimeNamespace[\s\S]*platform\.runtime_namespace[\s\S]*function\s+Get-ADPRuntimeResourceNames[\s\S]*RuntimeResourceName[\s\S]*VmName[\s\S]*SshAlias[\s\S]*MutagenSession'
Assert-Contains -Name "resource conflict diagnostics consume runtime identity helper" -Text $resourceConflicts -Pattern 'runtime\\runtime-identity\.ps1[\s\S]*Get-ADPRuntimeResourceNames[\s\S]*RuntimeNamespace[\s\S]*RuntimeResourceName'
Assert-Contains -Name "SSH alias diagnostics parse user SSH config without mutating it" -Text $sshAliasDiagnostics -Pattern 'function\s+Get-ADPSshHostBlock[\s\S]*ADP-OS \$HostAlias[\s\S]*function\s+Get-ADPSshAliasOwnershipStatus[\s\S]*alias-mismatch[\s\S]*function\s+ConvertTo-ADPSshAliasOwnershipJson'
Assert-Contains -Name "status JSON exposes duplicate running VM details" -Text $status -Pattern 'DuplicateRunningVms[\s\S]*ConvertTo-ADPDuplicateVmJson[\s\S]*ResourceProfile'
Assert-Contains -Name "status exposes SSH alias diagnostics" -Text $status -Pattern 'SshAliasDiagnostic[\s\S]*ConvertTo-ADPSshAliasOwnershipJson[\s\S]*ssh alias:[\s\S]*Write-ADPSshAliasOwnershipGuidance'
Assert-Contains -Name "up blocks duplicate running VM before runtime mutation" -Text $up -Pattern 'Get-ADPRuntimeDuplicateConflict[\s\S]*HasDuplicateRunningVm[\s\S]*up runtime start/create[\s\S]*exit 1'
Assert-Contains -Name "up creation path reports namespaced runtime resource" -Text $up -Pattern 'if\s*\(\$resourceProfile\.RuntimeNamespace\)[\s\S]*Namespace: \$\(\$resourceProfile\.RuntimeNamespace\) \(resource: \$\(\$resourceProfile\.RuntimeResourceName\)\)[\s\S]*\$factoryLayout\.VmxPath'
Assert-NotContains -Name "up no longer blocks namespaced first VM creation" -Text $up -Pattern 'first VM creation has not been migrated|will not create the default|wait for the VM factory migration'
Assert-Contains -Name "sync start blocks duplicate running VM before creating session" -Text $sync -Pattern 'Get-ADPRuntimeDuplicateConflict[\s\S]*HasDuplicateRunningVm[\s\S]*Action "sync start"[\s\S]*New-SyncSession'
Assert-Contains -Name "sync uses resource profile session and remote endpoint names" -Text $sync -Pattern 'Get-SyncExpectedEndpoints[\s\S]*Get-ADPRuntimeResourceProfile[\s\S]*MutagenSession[\s\S]*WorkspacePath[\s\S]*ExpectedRemoteUrl'
Assert-Contains -Name "sync reports and blocks stale SSH alias targets around existing sessions" -Text $sync -Pattern 'Get-ADPSshAliasOwnershipStatus[\s\S]*alias:\s+[\s\S]*existingSession\.Exists[\s\S]*Write-ADPSshAliasOwnershipGuidance[\s\S]*New-SyncSession'
Assert-Contains -Name "doctor treats duplicate running VM as a failing check" -Text $doctor -Pattern 'Get-ADPRuntimeDuplicateConflict[\s\S]*Test-Check -Name "\$name duplicate running VM" -Condition \(-not \$hasDuplicateRunningVm\)'
Assert-Contains -Name "doctor skips SSH reachability when duplicate VM makes target ambiguous" -Text $doctor -Pattern 'SSH alias target[\s\S]*duplicate running VM makes SSH target ambiguous'
Assert-Contains -Name "status reports unhealthy sync sessions" -Text (Read-Text "cli\commands\status.ps1") -Pattern 'wrong-local[\s\S]*wrong-remote[\s\S]*unhealthy[\s\S]*Get-SyncSessionRecoveryInfo[\s\S]*sync recovery:[\s\S]*sync step:[\s\S]*sync safety:'
Assert-Contains -Name "status distinguishes stale session before runtime creation" -Text (Read-Text "cli\commands\status.ps1") -Pattern '\$RuntimeCreated[\s\S]*stale-session[\s\S]*Get-SyncSessionRecoveryInfo[\s\S]*sync recovery:[\s\S]*sync step:[\s\S]*sync safety:'
Assert-Contains -Name "doctor reports seed network drift" -Text $doctor -Pattern 'seed network drift[\s\S]*Write-NetworkDriftRemediation'
Assert-Contains -Name "doctor explains stale networking remediation paths" -Text $doctor -Pattern 'function\s+Write-NetworkDriftRemediation[\s\S]*Remediation options for \$TargetRuntime network drift[\s\S]*Rebuild when the VM can be recreated[\s\S]*In-place guest fix[\s\S]*Admin-only temporary host-route workaround'
Assert-Contains -Name "doctor reports duplicate running runtime VMs" -Text $doctor -Pattern 'duplicate running VM[\s\S]*Stop or rename stale duplicate ADP VMs before diagnosing SSH or network issues'
Assert-Contains -Name "doctor reports unhealthy Mutagen sessions" -Text $doctor -Pattern 'Get-SyncSessionRecoveryInfo[\s\S]*\[SYNC\]'
Assert-Contains -Name "doctor treats uncreated runtime stale sync as info cleanup" -Text $doctor -Pattern '\[SYNC\][\s\S]*stale before runtime creation'
Assert-Contains -Name "network apply plan guides stale networking remediation" -Text $network -Pattern 'Network drift detected:[\s\S]*in-place guest netplan fix path only[\s\S]*adpos destroy \$TargetRuntime -Plan[\s\S]*ADP will not add, change, or remove host routes automatically'
Assert-Contains -Name "network apply prefers seed-era SSH target during drift" -Text $network -Pattern 'if\s*\(-not\s+\$currentIp\s+-and\s+\$seedNetwork[\s\S]*\$currentIp\s*=\s*\$seedNetwork\.Address[\s\S]*if\s*\(-not\s+\$currentIp\)\s*\{[\s\S]*\$currentIp\s*=\s*\$network\.Address'
Assert-Contains -Name "network configure-local requires explicit apply for local overrides" -Text $network -Pattern '\[switch\]\$Apply[\s\S]*Use either -Plan or -Apply, not both[\s\S]*Get-VMwareLocalNetworkPlan[\s\S]*Proposed local config changes:[\s\S]*Plan only: configs\\local\.json will not be changed[\s\S]*No files changed[\s\S]*network configure-local -Apply[\s\S]*Set-LocalNetworkConfig[\s\S]*Updated configs\\local\.json with host VMnet8 NAT settings'
Assert-Contains -Name "network configure-local backs up existing local config" -Text $network -Pattern 'function\s+Backup-LocalNetworkConfig[\s\S]*\$backupPath\s*=\s*"\$LocalConfigPath\.bak\.\$timestamp"[\s\S]*Copy-Item[\s\S]*Backup:'
Assert-Contains -Name "network configure-local states preserved and untouched state" -Text $network -Pattern 'Preserved: unrelated configs\\local\.json fields are left unchanged[\s\S]*Not changed: VMware VMnet8, VM files, guest networking, SSH, sync sessions, and runtimes[\s\S]*Alternative: keep ADP'
Assert-Contains -Name "network configure-local avoids SSH initialization before local config repair" -Text $network -Pattern 'if\s*\(\$SubCommand\s+-in\s+@\("configure-local", "local"\)\)[\s\S]*return[\s\S]*Initialize-Provider[\s\S]*Initialize-SSH\s+\| Out-Null'
Assert-Contains -Name "VMware adapter detects host NAT network" -Text (Read-Text "adapters\windows\vmware\vmware.ps1") -Pattern 'function\s+Get-VMwareNatNetwork[\s\S]*function\s+Test-VMwareNatConfigMatchesHost'
Assert-Contains -Name "VMware adapter can derive runtime IPs in detected NAT" -Text (Read-Text "adapters\windows\vmware\vmware.ps1") -Pattern 'function\s+Get-ADPIPv4AddressInCidr[\s\S]*HostOffset'
Assert-Contains -Name "VMware adapter documents vmrun list as running-only" -Text (Read-Text "adapters\windows\vmware\vmware.ps1") -Pattern 'vmrun list returns only running VMs'
Assert-Contains -Name "VMware adapter classifies ADP running runtime VMs" -Text (Read-Text "adapters\windows\vmware\vmware.ps1") -Pattern 'function\s+Get-ADPRuntimeNameFromVmxPath[\s\S]*function\s+Get-ADPRunningRuntimeVMs[\s\S]*IsManagedByCurrentCheckout'
Assert-Contains -Name "VMware adapter exposes quick IP probe for progress loops" -Text (Read-Text "adapters\windows\vmware\vmware.ps1") -Pattern 'function\s+Get-VMIPQuick[\s\S]*getGuestIPAddress[\s\S]*Get-VMIPFromDhcpLeases'
Assert-Contains -Name "VMware adapter uses bounded default operation timeouts" -Text (Read-Text "adapters\windows\vmware\vmware.ps1") -Pattern 'TimeoutSeconds\s*=\s*0[\s\S]*TimeoutSeconds\s*=\s*120[\s\S]*Arguments\[0\]\s+-eq\s+"stop"[\s\S]*soft[\s\S]*30[\s\S]*60'
Assert-Contains -Name "VMware snapshot create has bounded wait" -Text (Read-Text "adapters\windows\vmware\vmware.ps1") -Pattern 'function\s+Create-VMSnapshot[\s\S]*TimeoutSeconds\s*=\s*120[\s\S]*Invoke-Vmrun -Arguments @\("snapshot", \$VmxPath, \$SnapshotName\) -TimeoutSeconds \$TimeoutSeconds'
Assert-Contains -Name "VMware snapshot list skips vmrun summary header" -Text (Read-Text "adapters\windows\vmware\vmware.ps1") -Pattern 'function\s+List-VMSnapshots[\s\S]*Total snapshots:\\s\*\\d\+'
Assert-Contains -Name "snapshot CLI confirms existing snapshot after provider failure" -Text $snapshot -Pattern 'if\s*\(\$result\.Success\)[\s\S]*else\s*\{[\s\S]*Get-SnapshotList -Name \$RuntimeName[\s\S]*Snapshot command reported failure, but snapshot ''\$SnapshotName'' exists[\s\S]*Snapshot ''\$SnapshotName'' exists'
Assert-Contains -Name "networking docs explain NAT prerequisites" -Text $networkingDocs -Pattern '## Prerequisites[\s\S]*Virtual Network Editor[\s\S]*VMware NAT prerequisites'
Assert-Contains -Name "Chinese networking docs explain NAT prerequisites" -Text $networkingDocsZh -Pattern '## 前置条件[\s\S]*Virtual Network Editor[\s\S]*VMware NAT prerequisites'
Assert-Contains -Name "networking docs prefer explicit apply for local NAT overrides" -Text $networkingDocs -Pattern 'network configure-local -Plan[\s\S]*network configure-local -Apply[\s\S]*does not change files[\s\S]*without switches is also non-mutating[\s\S]*backs up an existing local file as `configs\\local\.json\.bak\.<timestamp>`[\s\S]*change VMware `VMnet8`'
Assert-Contains -Name "Chinese networking docs prefer explicit apply for local NAT overrides" -Text $networkingDocsZh -Pattern 'network configure-local -Plan[\s\S]*network configure-local -Apply[\s\S]*不会修改文件[\s\S]*不带任何开关运行 `network configure-local` 同样不会修改文件[\s\S]*备份为 `configs\\local\.json\.bak\.<timestamp>`[\s\S]*修改 `VMnet8`'
Assert-Contains -Name "configuration docs explain explicit configure-local apply" -Text $configurationDocs -Pattern 'network configure-local -Plan[\s\S]*network configure-local -Apply[\s\S]*does not write local configuration unless `-Apply` is explicit[\s\S]*configs\\local\.json\.bak\.<timestamp>[\s\S]*change VMware `VMnet8`'
Assert-Contains -Name "Chinese configuration docs explain explicit configure-local apply" -Text $configurationDocsZh -Pattern 'network configure-local -Plan[\s\S]*network configure-local -Apply[\s\S]*只有显式使用 `-Apply` 时才会写入本地配置[\s\S]*configs\\local\.json\.bak\.<timestamp>[\s\S]*修改 `VMnet8`'
Assert-Contains -Name "operations docs explain duplicate runtime diagnostics" -Text (Read-Text "docs\operations.md") -Pattern 'duplicate running ADP runtime resource names[\s\S]*same runtime resource name[\s\S]*another checkout or a stale VM store'
Assert-Contains -Name "Chinese operations docs explain duplicate runtime diagnostics" -Text (Read-Text "docs\zh-CN\operations.md") -Pattern 'duplicate running ADP runtime resource name[\s\S]*另一个 checkout 或 stale VM store[\s\S]*相同 runtime resource name'
Assert-Contains -Name "operations docs explain ambiguous duplicate SSH" -Text (Read-Text "docs\operations.md") -Pattern 'ambiguous-duplicate[\s\S]*does not prove that the current checkout'
Assert-Contains -Name "Chinese operations docs explain ambiguous duplicate SSH" -Text (Read-Text "docs\zh-CN\operations.md") -Pattern 'ambiguous-duplicate[\s\S]*不能证明响应的是当前 checkout'
Assert-Contains -Name "operations docs explain stale networking remediation paths" -Text (Read-Text "docs\operations.md") -Pattern 'network drift[\s\S]*Rebuild when the VM can be recreated[\s\S]*in-place guest netplan fix[\s\S]*administrator-only temporary host-route workaround[\s\S]*ADP does not add, change, or remove host routes automatically'
Assert-Contains -Name "Chinese operations docs explain stale networking remediation paths" -Text (Read-Text "docs\zh-CN\operations.md") -Pattern 'network drift[\s\S]*rebuild path[\s\S]*in-place guest netplan fix[\s\S]*administrator-only temporary host-route workaround[\s\S]*ADP 不会自动添加、修改或删除 host routes'
Assert-Contains -Name "troubleshooting docs mention duplicate runtime symptom" -Text $troubleshootingDocs -Pattern 'duplicate VM[\s\S]*same runtime resource name'
Assert-Contains -Name "Chinese troubleshooting docs mention duplicate runtime symptom" -Text $troubleshootingDocsZh -Pattern 'duplicate VM[\s\S]*相同 runtime resource name'
Assert-Contains -Name "troubleshooting docs explain multi-checkout resource conflicts" -Text $troubleshootingDocs -Pattern 'Multiple Checkouts and Resource Conflicts[\s\S]*global `adpos`[\s\S]*workspace_root[\s\S]*vm_store[\s\S]*topology\.<runtime>\.static_ip[\s\S]*`up` and `sync start` stop'
Assert-Contains -Name "Chinese troubleshooting docs explain multi-checkout resource conflicts" -Text $troubleshootingDocsZh -Pattern '多 Checkout 与资源冲突[\s\S]*全局 `adpos`[\s\S]*workspace_root[\s\S]*vm_store[\s\S]*topology\.<runtime>\.static_ip[\s\S]*`up` 和 `sync start`'
Assert-Contains -Name "configuration docs explain second-checkout local override isolation" -Text $configurationDocs -Pattern 'second checkout[\s\S]*isolate -Plan -Namespace v2[\s\S]*`runtime_namespace`, `workspace_root`, `vm_store`, provider `vm_store`, and `topology\.<runtime>\.static_ip`[\s\S]*global `adpos` command can point to only one checkout'
Assert-Contains -Name "Chinese configuration docs explain second-checkout local override isolation" -Text $configurationDocsZh -Pattern '第二个 checkout[\s\S]*isolate -Plan -Namespace v2[\s\S]*`runtime_namespace`、`workspace_root`、`vm_store`、provider `vm_store` 和 `topology\.<runtime>\.static_ip`[\s\S]*全局 `adpos` 命令同一时间只能指向一个 checkout'
Assert-Contains -Name "README explains second-checkout local checks" -Text (Read-Text "README.md") -Pattern 'Multiple ADP-OS checkouts can coexist[\s\S]*configs\\local\.json[\s\S]*\.\\adpos\.cmd doctor[\s\S]*duplicate VM[\s\S]*`up` and `sync start` stop'
Assert-Contains -Name "Chinese README explains second-checkout local checks" -Text (Read-Text "README.zh-CN.md") -Pattern '多个 ADP-OS checkout 可以共存[\s\S]*configs\\local\.json[\s\S]*\.\\adpos\.cmd doctor[\s\S]*duplicate VM[\s\S]*`up` 和 `sync start`'
Assert-Contains -Name "getting started explains second checkout isolation" -Text (Read-Text "docs\getting-started.md") -Pattern 'Using a Second Checkout[\s\S]*global `adpos` already points to another checkout[\s\S]*platform\.paths\.workspace_root[\s\S]*\.\\adpos\.cmd up agent -Plan'
Assert-Contains -Name "Chinese getting started explains second checkout isolation" -Text (Read-Text "docs\zh-CN\getting-started.md") -Pattern '使用第二个 Checkout[\s\S]*全局 `adpos` 已经指向另一个 checkout[\s\S]*platform\.paths\.workspace_root[\s\S]*\.\\adpos\.cmd up agent -Plan'
Assert-Contains -Name "configuration docs explain namespaced first VM creation" -Text $configurationDocs -Pattern 'platform\.runtime_namespace[\s\S]*resource `v2-agent`[\s\S]*adpos up agent[\s\S]*creates or starts VM `adp-v2-agent`[\s\S]*does not migrate existing legacy VMs[\s\S]*`workspace_root`, `vm_store`, and each active runtime''s `static_ip`'
Assert-Contains -Name "Chinese configuration docs explain namespaced first VM creation" -Text $configurationDocsZh -Pattern 'platform\.runtime_namespace[\s\S]*资源 `v2-agent`[\s\S]*adpos up agent[\s\S]*创建或启动 VM `adp-v2-agent`[\s\S]*不会迁移已有 legacy VM[\s\S]*`workspace_root`、`vm_store` 和每个活跃 runtime 的 `static_ip`'
Assert-Contains -Name "getting started docs explain namespaced first VM creation" -Text (Read-Text "docs\getting-started.md") -Pattern 'Namespaced runtime resource names are supported for first VM creation[\s\S]*resource `v2-agent` and VM `adp-v2-agent`[\s\S]*does not automatically isolate IPs or paths'
Assert-Contains -Name "Chinese getting started docs explain namespaced first VM creation" -Text (Read-Text "docs\zh-CN\getting-started.md") -Pattern 'Namespaced runtime resource names 已支持首次 VM 创建[\s\S]*资源 `v2-agent` 和 VM `adp-v2-agent`[\s\S]*不会自动隔离 IP 或路径'
Assert-Contains -Name "troubleshooting docs explain namespaced first VM creation target" -Text $troubleshootingDocs -Pattern 'up` first VM creation use that namespaced profile[\s\S]*adpos up agent` now targets a separate `adp-v2-agent`'
Assert-Contains -Name "Chinese troubleshooting docs explain namespaced first VM creation target" -Text $troubleshootingDocsZh -Pattern 'up` 首次 VM 创建都会使用 namespaced profile[\s\S]*adpos up agent` 会指向独立的 `adp-v2-agent`'
Assert-NotContains -Name "public docs do not describe namespaced first creation as blocked" -Text ((Read-Text "README.md") + (Read-Text "docs\getting-started.md") + $configurationDocs + $troubleshootingDocs) -Pattern 'first creation of namespaced VMs is still|VM factory migration stage|do not expect first creation|up` intentionally stops|namespaced first-VM creation is fully migrated'
Assert-NotContains -Name "Chinese public docs do not describe namespaced first creation as blocked" -Text ((Read-Text "README.zh-CN.md") + (Read-Text "docs\zh-CN\getting-started.md") + $configurationDocsZh + $troubleshootingDocsZh) -Pattern 'namespaced VM 的首次创建仍|Namespaced VM 的首次创建仍|VM factory 迁移阶段|不要期待 namespaced VM|尚未迁移'
Assert-Contains -Name "operations docs explain duplicate VM preflight gates" -Text (Read-Text "docs\operations.md") -Pattern 'duplicate-running-VM check is a preflight gate[\s\S]*adpos up <runtime>[\s\S]*adpos sync start <runtime>[\s\S]*Plan mode shows the conflict'
Assert-Contains -Name "Chinese operations docs explain duplicate VM preflight gates" -Text (Read-Text "docs\zh-CN\operations.md") -Pattern 'duplicate-running-VM 检查也是[\s\S]*adpos up <runtime>[\s\S]*adpos sync start <runtime>[\s\S]*Plan mode 会显示冲突'
Assert-Contains -Name "networking docs explain parallel checkout static IP isolation" -Text $networkingDocs -Pattern 'multiple ADP-OS checkouts or versions[\s\S]*must not share a `static_ip`[\s\S]*configs\\local\.json'
Assert-Contains -Name "Chinese networking docs explain parallel checkout static IP isolation" -Text $networkingDocsZh -Pattern '多个 ADP-OS checkout 或版本[\s\S]*不能共用同一个 `static_ip`[\s\S]*configs\\local\.json'
Assert-Contains -Name "operations docs explain localized install monitor and indeterminate progress" -Text (Read-Text "docs\operations.md") -Pattern '\[install monitor\] INSTALLING Ubuntu in VM[\s\S]*\[安装监视器\] 正在 VM 中安装 Ubuntu[\s\S]*PowerShell `Write-Progress`[\s\S]*does not show a percentage progress bar[\s\S]*stable diagnostic terms'
Assert-Contains -Name "Chinese operations docs explain localized install monitor and indeterminate progress" -Text (Read-Text "docs\zh-CN\operations.md") -Pattern '\[install monitor\] INSTALLING Ubuntu in VM[\s\S]*\[安装监视器\] 正在 VM 中安装 Ubuntu[\s\S]*PowerShell `Write-Progress`[\s\S]*不会显示百分比进度条[\s\S]*稳定诊断术语'
Assert-Contains -Name "troubleshooting docs explain install monitor stuck symptom" -Text $troubleshootingDocs -Pattern 'Runtime creation looks stuck[\s\S]*\[install monitor\] INSTALLING Ubuntu[\s\S]*Ubuntu autoinstall'
Assert-Contains -Name "Chinese troubleshooting docs explain install monitor stuck symptom" -Text $troubleshootingDocsZh -Pattern 'Runtime 创建看起来卡住[\s\S]*(\[安装监视器\] 正在 VM 中安装 Ubuntu|\[install monitor\] INSTALLING Ubuntu)[\s\S]*Ubuntu autoinstall'
Assert-Contains -Name "troubleshooting docs explain stale networking remediation paths" -Text $troubleshootingDocs -Pattern 'network drift[\s\S]*network apply <runtime> -Plan[\s\S]*Rebuild the runtime[\s\S]*administrator-only temporary host-route workaround'
Assert-Contains -Name "Chinese troubleshooting docs explain stale networking remediation paths" -Text $troubleshootingDocsZh -Pattern 'network drift[\s\S]*network apply <runtime> -Plan[\s\S]*重建该 runtime[\s\S]*administrator-only temporary host-route workaround'
Assert-Contains -Name "workspace docs mention recipes example" -Text $workspaceDocs -Pattern 'configs/workspace\.recipes\.example\.json'
Assert-Contains -Name "Chinese workspace docs mention recipes example" -Text $workspaceDocsZh -Pattern 'configs/workspace\.recipes\.example\.json'
Assert-Contains -Name "workspace docs define recipes discovery view" -Text $workspaceDocs -Pattern 'workspace recipes -ManifestPath configs\\workspace\.recipes\.example\.json[\s\S]*manifest discovery view[\s\S]*without cloning projects, opening SSH, starting sync, creating snapshots, running validation, running evaluation commands, running Git, or modifying files'
Assert-Contains -Name "Chinese workspace docs define recipes discovery view" -Text $workspaceDocsZh -Pattern 'workspace recipes -ManifestPath configs\\workspace\.recipes\.example\.json[\s\S]*manifest discovery view[\s\S]*不会 clone project、打开 SSH、启动 sync、创建快照、运行 validation、运行 evaluation commands、运行 Git 或修改文件'
Assert-Contains -Name "workspace docs define create boundary" -Text $workspaceDocs -Pattern 'workspace create -Plan[\s\S]*workspace create[\s\S]*creates only missing local project directories[\s\S]*does not clone repositories, start runtimes, start or stop sync, open SSH, create snapshots, run validation, run evaluation commands, run Git, or modify existing project files'
Assert-Contains -Name "Chinese workspace docs define create boundary" -Text $workspaceDocsZh -Pattern 'workspace create -Plan[\s\S]*workspace create[\s\S]*只会创建从 `projects\[\]\.path` 解析出的缺失本地项目目录[\s\S]*不会 clone repository、启动 runtime、启动或停止 sync、打开 SSH、创建快照、运行 validation、运行 evaluation commands、运行 Git'
Assert-Contains -Name "workspace docs define open guide" -Text $workspaceDocs -Pattern 'workspace open app[\s\S]*workspace open frontend-app[\s\S]*non-destructive open guide[\s\S]*does not create directories, open an editor, start a shell, connect over SSH, start sync, start a runtime, or modify files'
Assert-Contains -Name "Chinese workspace docs define open guide" -Text $workspaceDocsZh -Pattern 'workspace open app[\s\S]*workspace open frontend-app[\s\S]*非破坏性的 open guide[\s\S]*不会创建目录、打开编辑器、启动 shell、通过 SSH 连接、启动 sync、启动 runtime 或修改文件'
Assert-Contains -Name "workspace docs define project sync guide" -Text $workspaceDocs -Pattern 'workspace sync app[\s\S]*workspace sync frontend-app[\s\S]*non-destructive project-aware sync guide[\s\S]*does not start or stop Mutagen, create directories, start runtimes, connect over SSH, or modify files'
Assert-Contains -Name "Chinese workspace docs define project sync guide" -Text $workspaceDocsZh -Pattern 'workspace sync app[\s\S]*workspace sync frontend-app[\s\S]*非破坏性的 project-aware sync guide[\s\S]*不会启动或停止 Mutagen、创建目录、启动 runtime、通过 SSH 连接或修改文件'
Assert-Contains -Name "workspace docs define project lifecycle view" -Text $workspaceDocs -Pattern 'workspace project app[\s\S]*workspace project frontend-app[\s\S]*non-destructive lifecycle view[\s\S]*does not open the project, start a runtime, start or stop sync, create snapshots, run validation, run Git, connect over SSH, or modify files'
Assert-Contains -Name "Chinese workspace docs define project lifecycle view" -Text $workspaceDocsZh -Pattern 'workspace project app[\s\S]*workspace project frontend-app[\s\S]*非破坏性 lifecycle view[\s\S]*不会打开项目、启动 runtime、启动或停止 sync、创建快照、运行验证、运行 Git、通过 SSH 连接或修改文件'
Assert-Contains -Name "workspace docs explain shell-only dogfood is enough for first-run lifecycle validation" -Text $workspaceDocs -Pattern 'minimal POSIX shell project[\s\S]*tiny but real project[\s\S]*synced, validated, reviewed, and committed[\s\S]*without browser downloads or package installation'
Assert-Contains -Name "Chinese workspace docs explain shell-only dogfood is enough for first-run lifecycle validation" -Text $workspaceDocsZh -Pattern '一个最小的 POSIX shell 项目[\s\S]*足够小但真实的项目[\s\S]*可以被 sync、验证、review 和 commit[\s\S]*不需要下载浏览器或安装额外 packages'
Assert-Contains -Name "workspace docs define snapshot naming convention" -Text $workspaceDocs -Pattern 'Snapshot names should be tied to task or milestone intent[\s\S]*before-<task-name>[\s\S]*milestone-<name>[\s\S]*non-blocking convention check'
Assert-Contains -Name "Chinese workspace docs define snapshot naming convention" -Text $workspaceDocsZh -Pattern 'Snapshot 名称应该绑定 task 或 milestone 意图[\s\S]*before-<task-name>[\s\S]*milestone-<name>[\s\S]*非阻塞约定检查'
Assert-Contains -Name "workspace docs define milestone planning" -Text $workspaceDocs -Pattern 'Milestones are optional manifest-level planning records[\s\S]*milestones\[\]\.tasks[\s\S]*tasks\[\]\.milestone'
Assert-Contains -Name "workspace docs define milestone default snapshot gate" -Text $workspaceDocs -Pattern 'tasks\[\]\.milestone[\s\S]*defaults to snapshot-first gating'
Assert-Contains -Name "Chinese workspace docs define milestone planning" -Text $workspaceDocsZh -Pattern 'Milestone 是可选的 manifest-level planning record[\s\S]*milestones\[\]\.tasks[\s\S]*tasks\[\]\.milestone'
Assert-Contains -Name "Chinese workspace docs define milestone default snapshot gate" -Text $workspaceDocsZh -Pattern 'tasks\[\]\.milestone[\s\S]*默认触发 snapshot-first gate'
Assert-Contains -Name "workspace docs define evaluation hooks" -Text $workspaceDocs -Pattern 'Evaluations are optional manifest-level planning records[\s\S]*evaluations\[\][\s\S]*Evaluation Queue[\s\S]*evaluations\[\]\.metrics[\s\S]*tasks\[\]\.evaluation'
Assert-Contains -Name "Chinese workspace docs define evaluation hooks" -Text $workspaceDocsZh -Pattern 'Evaluation 是可选的 manifest-level planning record[\s\S]*evaluations\[\][\s\S]*Evaluation Queue[\s\S]*evaluations\[\]\.metrics[\s\S]*tasks\[\]\.evaluation'
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
Assert-Contains -Name "release readiness docs define decision policy" -Text $releaseReadinessDocs -Pattern '## Release Decision Policy[\s\S]*release candidate[\s\S]*sync hygiene is not blocking[\s\S]*release blocked[\s\S]*sync hygiene, a snapshot gate, or failed validation[\s\S]*validation required[\s\S]*review required[\s\S]*governance incomplete'
Assert-Contains -Name "release readiness docs define maintainer checklist" -Text $releaseReadinessDocs -Pattern '## Maintainer Checklist[\s\S]*adpos workspace dashboard[\s\S]*adpos workspace report[\s\S]*review sync ignore[\s\S]*release candidate[\s\S]*sync hygiene reviewed'
Assert-Contains -Name "release readiness docs include snapshot naming convention" -Text $releaseReadinessDocs -Pattern 'Snapshot naming is reviewed as part of rollback clarity[\s\S]*before-<task-name>[\s\S]*milestone-<name>[\s\S]*Naming convention warnings are non-blocking'
Assert-Contains -Name "Chinese release readiness docs define decision policy" -Text $releaseReadinessDocsZh -Pattern '## 发布决策策略[\s\S]*release candidate[\s\S]*sync hygiene 未阻塞[\s\S]*release blocked[\s\S]*sync hygiene、snapshot gate 或失败 validation[\s\S]*validation required[\s\S]*review required[\s\S]*governance incomplete'
Assert-Contains -Name "Chinese release readiness docs define maintainer checklist" -Text $releaseReadinessDocsZh -Pattern '## 维护者检查清单[\s\S]*adpos workspace dashboard[\s\S]*adpos workspace report[\s\S]*review sync ignore[\s\S]*release candidate[\s\S]*sync hygiene 已 review'
Assert-Contains -Name "Chinese release readiness docs include snapshot naming convention" -Text $releaseReadinessDocsZh -Pattern 'Snapshot naming 也是 rollback clarity 的 review 内容[\s\S]*before-<task-name>[\s\S]*milestone-<name>[\s\S]*不阻塞 release'
Assert-Contains -Name "release process docs define maintainer flow" -Text $releaseProcessDocs -Pattern '## Maintainer Flow[\s\S]*\.\\tests\\validate\.ps1 -Quick[\s\S]*\.\\tests\\validate\.ps1[\s\S]*workspace report -Markdown[\s\S]*owner has authorized publication'
Assert-Contains -Name "release process docs include sync hygiene evidence" -Text $releaseProcessDocs -Pattern '## Evidence Expectations[\s\S]*Sync hygiene status[\s\S]*review sync ignore[\s\S]*reviewed before release'
Assert-Contains -Name "release process docs define safety checks" -Text $releaseProcessDocs -Pattern '## Safety Checks[\s\S]*Secrets[\s\S]*adp-workspace\.state\.json[\s\S]*private maintainer'
Assert-Contains -Name "Chinese release process docs define maintainer flow" -Text $releaseProcessDocsZh -Pattern '## 维护者流程[\s\S]*\.\\tests\\validate\.ps1 -Quick[\s\S]*\.\\tests\\validate\.ps1[\s\S]*workspace report -Markdown[\s\S]*repository owner 授权发布'
Assert-Contains -Name "Chinese release process docs include sync hygiene evidence" -Text $releaseProcessDocsZh -Pattern 'Evidence 应显示：[\s\S]*Sync hygiene status[\s\S]*发布前必须 review[\s\S]*review sync ignore'
Assert-Contains -Name "Chinese release process docs define safety checks" -Text $releaseProcessDocsZh -Pattern '## 安全检查[\s\S]*Secrets[\s\S]*adp-workspace\.state\.json[\s\S]*Private maintainer'
Assert-Contains -Name "contributor workflow docs include templates" -Text $contributorWorkflowDocs -Pattern '## Workflow Templates[\s\S]*Documentation or Small Maintenance[\s\S]*Frontend Browser Acceptance[\s\S]*Backend Validation[\s\S]*Broad Agent Refactor'
Assert-Contains -Name "contributor workflow docs include maintainer ritual" -Text $contributorWorkflowDocs -Pattern '## Maintainer Review Ritual[\s\S]*adpos workspace dashboard[\s\S]*adpos workspace report[\s\S]*review sync ignore[\s\S]*release candidate'
Assert-Contains -Name "contributor workflow docs include sync hygiene PR expectation" -Text $contributorWorkflowDocs -Pattern '## Pull Request Expectations[\s\S]*Sync hygiene status[\s\S]*review sync ignore'
Assert-Contains -Name "contributor workflow docs include snapshot naming expectation" -Text $contributorWorkflowDocs -Pattern 'before-<task-name>[\s\S]*milestone-<name>[\s\S]*snapshot name communicates task or milestone rollback intent'
Assert-Contains -Name "Chinese contributor workflow docs include templates" -Text $contributorWorkflowDocsZh -Pattern '## 工作流模板[\s\S]*文档或小型维护[\s\S]*前端浏览器验收[\s\S]*后端验证[\s\S]*大范围 Agent 重构'
Assert-Contains -Name "Chinese contributor workflow docs include maintainer ritual" -Text $contributorWorkflowDocsZh -Pattern '## 维护者评审流程[\s\S]*adpos workspace dashboard[\s\S]*adpos workspace report[\s\S]*review sync ignore[\s\S]*release candidate'
Assert-Contains -Name "Chinese contributor workflow docs include sync hygiene PR expectation" -Text $contributorWorkflowDocsZh -Pattern '## Pull Request 预期[\s\S]*Sync hygiene status[\s\S]*review sync ignore'
Assert-Contains -Name "Chinese contributor workflow docs include snapshot naming expectation" -Text $contributorWorkflowDocsZh -Pattern 'before-<task-name>[\s\S]*milestone-<name>[\s\S]*snapshot 名称是否表达 task 或 milestone rollback 意图'
Assert-Contains -Name "PR template asks for shared validation" -Text $pullRequestTemplate -Pattern '## Validation[\s\S]*\.\\tests\\validate\.ps1[\s\S]*\.\\tests\\validate\.ps1 -Quick'
Assert-Contains -Name "PR template asks for release readiness" -Text $pullRequestTemplate -Pattern '## Release Readiness[\s\S]*workspace task shape[\s\S]*workspace report -Markdown[\s\S]*Stale-task remediation[\s\S]*Sync hygiene[\s\S]*review sync ignore[\s\S]*snapshot gate'
Assert-Contains -Name "doctor supports Mutagen remediation plan" -Text $doctor -Pattern '\[switch\]\$FixMutagen[\s\S]*\[switch\]\$Plan[\s\S]*Install-LocalMutagen[\s\S]*Plan only: no files will be downloaded[\s\S]*Offline archive:[\s\S]*SHA256:[\s\S]*Timeout:[\s\S]*platform\.tools\.mutagen\.download_url'
Assert-Contains -Name "doctor rejects plan without Mutagen remediation" -Text $doctor -Pattern '-Plan is only supported with -FixMutagen'
Assert-Contains -Name "doctor handles Mutagen remediation failures cleanly" -Text $doctor -Pattern 'try\s*\{[\s\S]*Install-LocalMutagen[\s\S]*catch\s*\{[\s\S]*Mutagen remediation failed[\s\S]*Retry:[\s\S]*Manual:[\s\S]*No VMs, sync sessions, SSH config, or configs\\local\.json were changed[\s\S]*exit 1'
Assert-Contains -Name "configuration docs explain Mutagen tool acquisition overrides" -Text $configurationDocs -Pattern 'platform\.tools\.mutagen[\s\S]*download_url[\s\S]*archive_path[\s\S]*sha256[\s\S]*connection_timeout_seconds[\s\S]*download_timeout_seconds[\s\S]*Downloaded archives, copied archives, and `mutagen\.exe` remain under ignored `\.tools\\mutagen`'
Assert-Contains -Name "Chinese configuration docs explain Mutagen tool acquisition overrides" -Text $configurationDocsZh -Pattern 'platform\.tools\.mutagen[\s\S]*download_url[\s\S]*archive_path[\s\S]*sha256[\s\S]*connection_timeout_seconds[\s\S]*download_timeout_seconds[\s\S]*下载的 archive、复制的 archive 和 `mutagen\.exe` 都保留在被忽略的 `\.tools\\mutagen`'
Assert-Contains -Name "operations docs explain offline Mutagen archive and SHA256" -Text (Read-Text "docs\operations.md") -Pattern 'If GitHub release downloads are slow or blocked[\s\S]*platform\.tools\.mutagen[\s\S]*When `sha256` is a 64-character hexadecimal hash'
Assert-Contains -Name "Chinese operations docs explain offline Mutagen archive and SHA256" -Text (Read-Text "docs\zh-CN\operations.md") -Pattern '如果 GitHub release 下载很慢或不可达[\s\S]*platform\.tools\.mutagen[\s\S]*当 `sha256` 是 64 位十六进制 hash'
Assert-Contains -Name "troubleshooting docs explain Mutagen download problems" -Text $troubleshootingDocs -Pattern '## Mutagen Download Problems[\s\S]*platform\.tools\.mutagen\.archive_path[\s\S]*platform\.tools\.mutagen\.download_url[\s\S]*platform\.tools\.mutagen\.sha256'
Assert-Contains -Name "Chinese troubleshooting docs explain Mutagen download problems" -Text $troubleshootingDocsZh -Pattern '## Mutagen 下载问题[\s\S]*platform\.tools\.mutagen\.archive_path[\s\S]*platform\.tools\.mutagen\.download_url[\s\S]*platform\.tools\.mutagen\.sha256'
Assert-Contains -Name "mutagen adapter installs local ignored binary" -Text (Read-Text "adapters\windows\mutagen\mutagen.ps1") -Pattern 'function\s+Install-LocalMutagen[\s\S]*mutagen_windows_amd64_v\$Version\.zip[\s\S]*Expand-Archive[\s\S]*Test-MutagenVersionSupported'
Assert-Contains -Name "mutagen adapter supports configurable acquisition" -Text (Read-Text "adapters\windows\mutagen\mutagen.ps1") -Pattern 'function\s+Get-MutagenInstallSettings[\s\S]*download_url[\s\S]*archive_path[\s\S]*sha256[\s\S]*connection_timeout_seconds[\s\S]*download_timeout_seconds'
Assert-Contains -Name "mutagen adapter verifies configured archive hashes" -Text (Read-Text "adapters\windows\mutagen\mutagen.ps1") -Pattern 'function\s+Assert-MutagenArchiveHash[\s\S]*Get-FileHash[\s\S]*SHA256 mismatch[\s\S]*sha256: verified'
Assert-Contains -Name "mutagen adapter supports offline archive copy" -Text (Read-Text "adapters\windows\mutagen\mutagen.ps1") -Pattern 'function\s+Copy-MutagenArchive[\s\S]*Copying configured Mutagen archive[\s\S]*Configured Mutagen archive was not found'
Assert-Contains -Name "mutagen adapter classifies sync session health" -Text (Read-Text "adapters\windows\mutagen\mutagen.ps1") -Pattern 'function\s+Get-SyncSessionInfo[\s\S]*wrong-local[\s\S]*wrong-remote[\s\S]*unhealthy[\s\S]*healthy'
Assert-Contains -Name "mutagen sync start blocks stale session before rewriting SSH alias" -Text (Read-Text "adapters\windows\mutagen\mutagen.ps1") -Pattern 'Get-SyncSessionInfo[\s\S]*exists but points to a different environment[\s\S]*To fix: adpos sync stop[\s\S]*Set-MutagenSSHHostConfig'
Assert-Contains -Name "mutagen configured archive overrides cached archive" -Text (Read-Text "adapters\windows\mutagen\mutagen.ps1") -Pattern '\$useConfiguredArchive[\s\S]*GetFullPath\(\$settings\.ArchivePath\)[\s\S]*GetFullPath\(\$zipPath\)[\s\S]*Copy-MutagenArchive'
Assert-Contains -Name "mutagen default archive cache falls back to download when missing" -Text (Read-Text "adapters\windows\mutagen\mutagen.ps1") -Pattern 'if\s*\(\$useConfiguredArchive\)[\s\S]*elseif\s*\(Test-Path -LiteralPath \$zipPath\)[\s\S]*else\s*\{[\s\S]*Invoke-MutagenArchiveDownload'
Assert-Contains -Name "mutagen install has watched progress and hard timeout guidance" -Text (Read-Text "adapters\windows\mutagen\mutagen.ps1") -Pattern 'function\s+Invoke-MutagenArchiveDownload[\s\S]*DownloadTimeoutSeconds = 300[\s\S]*Downloading Mutagen archive[\s\S]*ADP will stop the download process if the hard timeout is reached[\s\S]*Start-Process[\s\S]*WaitForExit\(\$DownloadTimeoutSeconds \* 1000\)[\s\S]*Kill\(\$true\)[\s\S]*manually download[\s\S]*Installing Mutagen locally[\s\S]*\[1/5\] Preparing local tool directory[\s\S]*\[5/5\] Verifying Mutagen version'
Assert-Contains -Name "workspace init uses public example manifest" -Text $workspaceSource -Pattern 'configs\\workspace\.example\.json'
Assert-Contains -Name "workspace plan is non-destructive" -Text $workspaceSource -Pattern 'Plan only: no projects will be cloned, no sync sessions will be changed, and no snapshots will be created'
Assert-Contains -Name "workspace plan suggests previewed runtime startup" -Text $workspaceSource -Pattern 'adpos up \$\(\$project\.runtime\) -Plan'
Assert-Contains -Name "workspace plan suggests milestone checkpoints" -Text $workspaceSource -Pattern 'Get-WorkspaceMilestones[\s\S]*Milestone checkpoint.*adpos snapshot create \$\(\$milestoneStatus\.RuntimeName\) \$\(\$milestoneStatus\.SnapshotName\)'
Assert-Contains -Name "workspace recipes is non-destructive" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceRecipes[\s\S]*Recipes only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation or evaluation commands will be run, no SSH connection will be opened, and no Git commands will be run'
Assert-Contains -Name "workspace recipes summarizes projects tasks evaluations and evidence" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceRecipes[\s\S]*Project recipes:[\s\S]*Task recipes:[\s\S]*Milestone recipes:[\s\S]*Evaluation recipes:[\s\S]*Evidence commands:'
Assert-Contains -Name "workspace recipes command route" -Text $workspaceSource -Pattern '"recipes"\s*\{[\s\S]*Write-WorkspaceRecipes\s+-Manifest\s+\$manifest\s+-ManifestPath\s+\$ManifestPath\s+-StatePath\s+\$StatePath'
Assert-Contains -Name "workspace create supports plan and guarded creation" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceCreate[\s\S]*Plan only: no directories will be created[\s\S]*no validation or evaluation commands run[\s\S]*Create only: local project directories may be created[\s\S]*no validation or evaluation commands run[\s\S]*New-Item -ItemType Directory[\s\S]*No projects will be cloned'
Assert-Contains -Name "workspace create blocks invalid paths before creation" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceProjectCreateEntries[\s\S]*refusing to create a filesystem root[\s\S]*path exists and is not a directory[\s\S]*Create blocked: fix invalid project paths before creating workspace directories'
Assert-Contains -Name "workspace create command route" -Text $workspaceSource -Pattern '"create"\s*\{[\s\S]*Write-WorkspaceCreate\s+-Manifest\s+\$manifest\s+-ManifestPath\s+\$ManifestPath\s+-PlanOnly:\$Plan'
Assert-Contains -Name "workspace open is non-destructive" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceOpen[\s\S]*Open guide only: no shell, editor, SSH connection, sync session, runtime, or file will be changed[\s\S]*Local commands:[\s\S]*Runtime commands:[\s\S]*Next:'
Assert-Contains -Name "workspace open resolves project names" -Text $workspaceSource -Pattern 'function\s+Find-WorkspaceProject[\s\S]*Project name required because the workspace has multiple projects[\s\S]*Workspace project not found'
Assert-Contains -Name "workspace open command route" -Text $workspaceSource -Pattern '"open"\s*\{[\s\S]*Write-WorkspaceOpen\s+-Manifest\s+\$manifest\s+-ProjectName\s+\$TaskCommand\s+-ManifestPath\s+\$ManifestPath'
Assert-Contains -Name "workspace sync is non-destructive" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceSyncGuide[\s\S]*Sync guide only: no Mutagen session, runtime, SSH connection, directory, or file will be changed[\s\S]*Runtime sync commands:[\s\S]*adpos sync start \$runtimeName[\s\S]*adpos sync stop \$runtimeName'
Assert-Contains -Name "workspace sync command route" -Text $workspaceSource -Pattern '"sync"\s*\{[\s\S]*Write-WorkspaceSyncGuide\s+-Manifest\s+\$manifest\s+-ProjectName\s+\$TaskCommand\s+-ManifestPath\s+\$ManifestPath'
Assert-Contains -Name "workspace project is non-destructive" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceProjectLifecycle[\s\S]*Lifecycle view only: no project, runtime, sync session, snapshot, validation command, Git command, or file will be changed[\s\S]*Lifecycle gates:[\s\S]*Operational flow:[\s\S]*Linked tasks:'
Assert-Contains -Name "workspace project links tasks" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceTasksForProject[\s\S]*\$taskProject[\s\S]*\$matched\.Add\(\$task\)[\s\S]*function\s+Write-WorkspaceProjectLifecycle[\s\S]*Get-WorkspaceTasksForProject[\s\S]*Get-WorkspaceCommitDecision'
Assert-Contains -Name "workspace project command route" -Text $workspaceSource -Pattern '"project"\s*\{[\s\S]*Write-WorkspaceProjectLifecycle\s+-Manifest\s+\$manifest\s+-ProjectName\s+\$TaskCommand\s+-ManifestPath\s+\$ManifestPath\s+-StatePath\s+\$StatePath'
Assert-Contains -Name "workspace status is non-destructive" -Text $workspaceSource -Pattern 'Status only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, and no validation or evaluation commands will be run'
Assert-Contains -Name "workspace status checks runtime readiness" -Text $workspaceSource -Pattern 'Get-WorkspaceRuntimeStatus'
Assert-Contains -Name "workspace status checks sync readiness" -Text $workspaceSource -Pattern 'Get-WorkspaceSyncStatus'
Assert-Contains -Name "workspace status checks sync hygiene non-destructively" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceSyncHygieneStatus[\s\S]*node_modules[\s\S]*not ignored by sync profile[\s\S]*generated directories ignored by sync profile'
Assert-Contains -Name "workspace sync hygiene checks expanded generated directories" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceSyncHygieneStatus[\s\S]*\.parcel-cache[\s\S]*\.vite[\s\S]*\.playwright[\s\S]*\.mypy_cache[\s\S]*\.ruff_cache'
Assert-Contains -Name "config schema requires expanded default sync profile ignores" -Text (Read-Text "tests\config-schema.ps1") -Pattern 'requiredIgnores[\s\S]*frontend = @\("node_modules", "\.next", "dist", "build", "coverage"[\s\S]*backend\s+= @\("dist", "build", "coverage", "__pycache__", "\.venv"[\s\S]*agent\s+= @\("node_modules", "\.git", "\.venv"[\s\S]*"\.codex", "\.claude", "\.tools", "logs"'
Assert-Contains -Name "configuration docs explain sync profile array replacement" -Text (Read-Text "docs\configuration.md") -Pattern 'Arrays and scalar values replace the default value, so local `sync_profiles\.<name>\.ignore` overrides should include every ignored path'
Assert-Contains -Name "Chinese configuration docs explain sync profile array replacement" -Text (Read-Text "docs\zh-CN\configuration.md") -Pattern '数组和标量值会替换默认值，因此本地 `sync_profiles\.<name>\.ignore` 覆盖应包含你仍然想保留的所有默认忽略路径'
Assert-Contains -Name "workspace status checks snapshot readiness" -Text $workspaceSource -Pattern 'Get-WorkspaceSnapshotStatus'
Assert-Contains -Name "workspace status checks snapshot naming non-destructively" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceRecommendedSnapshotName[\s\S]*return "before-\$taskName"[\s\S]*function\s+Get-WorkspaceSnapshotNamingStatus[\s\S]*Status\s+=\s+"nonstandard"[\s\S]*milestone-<name>'
Assert-Contains -Name "workspace supports milestone checkpoint helpers" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceMilestones[\s\S]*function\s+Get-WorkspaceRecommendedMilestoneSnapshotName[\s\S]*return "milestone-\$name"[\s\S]*function\s+Get-WorkspaceTaskMilestones[\s\S]*function\s+Get-WorkspaceMilestoneStatus'
Assert-Contains -Name "workspace supports evaluation hook helpers" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceEvaluations[\s\S]*function\s+Get-WorkspaceEvaluationTasks[\s\S]*function\s+Get-WorkspaceTaskEvaluations[\s\S]*function\s+Get-WorkspaceEvaluationStatus'
Assert-Contains -Name "workspace milestone tasks default to snapshot gate unless overridden" -Text $workspaceSource -Pattern 'function\s+Test-WorkspaceTaskRequiresSnapshot[\s\S]*requires_snapshot[\s\S]*-contains "milestone"[\s\S]*return \$true[\s\S]*Get-WorkspaceTaskRisk'
Assert-Contains -Name "workspace detects devcontainer metadata non-destructively" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceDevContainerStatus[\s\S]*\.devcontainer/devcontainer\.json[\s\S]*Docker/dev container metadata can still be used inside the ADP runtime'
Assert-Contains -Name "workspace task risk supports snapshot gating" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceTaskRisk[\s\S]*function\s+Test-WorkspaceTaskRequiresSnapshot[\s\S]*function\s+Get-WorkspaceSnapshotGate'
Assert-Contains -Name "workspace checkpoint waiver is local state only" -Text $workspaceSource -Pattern 'function\s+Set-WorkspaceTaskCheckpointWaiver[\s\S]*state\s+=\s+"checkpoint-waived"[\s\S]*checkpoint\s*=\s*\$checkpoint[\s\S]*function\s+Test-WorkspaceCheckpointWaived[\s\S]*checkpoint-waived'
Assert-Contains -Name "workspace snapshot gate treats real snapshot before waiver" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceSnapshotGate[\s\S]*if\s*\(\$SnapshotStatus\.Level\s+-eq\s+"OK"\)[\s\S]*Status\s+=\s+"ready"[\s\S]*if\s*\(Test-WorkspaceCheckpointWaived'
Assert-Contains -Name "workspace checkpointed clears waiver marker" -Text $workspaceSource -Pattern 'function\s+Set-WorkspaceTaskState[\s\S]*if\s*\(\$StateName\s+-eq\s+"checkpointed"[\s\S]*PSObject\.Properties\.Remove\("checkpoint"\)'
Assert-Contains -Name "workspace dashboard is non-destructive" -Text $workspaceSource -Pattern 'Dashboard only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation or evaluation commands will be run, and no Git commands will be run'
Assert-Contains -Name "workspace dashboard includes sync hygiene rollup" -Text $workspaceSource -Pattern 'sync hygiene: \$\(\$syncHygieneStatus\.Status\)'
Assert-Contains -Name "workspace dashboard includes snapshot naming rollup" -Text $workspaceSource -Pattern 'snapshot naming: \$\(\$snapshotNaming\.Status\)'
Assert-Contains -Name "workspace dashboard includes milestone checkpoints" -Text $workspaceSource -Pattern 'Milestone checkpoints:[\s\S]*Get-WorkspaceMilestoneStatus[\s\S]*milestone: \$milestoneText'
Assert-Contains -Name "workspace dashboard includes evaluation hooks" -Text $workspaceSource -Pattern 'Evaluation hooks:[\s\S]*Get-WorkspaceEvaluationStatus[\s\S]*evaluation: \$evaluationText'
Assert-Contains -Name "workspace dashboard summarizes lifecycle state" -Text $workspaceSource -Pattern 'Task lifecycle:[\s\S]*snapshot required:[\s\S]*execution:[\s\S]*rollback:[\s\S]*commit:'
Assert-Contains -Name "workspace dashboard can block execution on snapshot gate" -Text $workspaceSource -Pattern 'blocked by snapshot gate'
Assert-Contains -Name "workspace dashboard reads checkpoint waiver state" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceDashboard[\s\S]*Get-WorkspaceTaskState[\s\S]*Get-WorkspaceSnapshotGate\s+-Task\s+\$task\s+-SnapshotStatus\s+\$snapshotStatus\s+-RecordedState\s+\$recordedState'
Assert-Contains -Name "workspace dashboard uses shared commit readiness gate" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceDashboard[\s\S]*Get-WorkspaceTaskSyncHygieneStatus[\s\S]*Get-WorkspaceCommitDecision[\s\S]*commit: \$commitState'
Assert-Contains -Name "workspace dashboard uses bilingual UI output" -Text $workspaceSource -Pattern 'Write-UIHost[\s\S]*?-English[\s\S]*?-Chinese[\s\S]*?Workspace dashboard:[\s\S]*?工作区仪表盘:[\s\S]*?Dashboard only:[\s\S]*?仅仪表盘查看：[\s\S]*?Overview:[\s\S]*?概览:[\s\S]*?Project readiness:[\s\S]*?项目就绪状态:[\s\S]*?Milestone checkpoints:[\s\S]*?里程碑检查点:[\s\S]*?Evaluation hooks:[\s\S]*?评估钩子:[\s\S]*?Task lifecycle:[\s\S]*?任务生命周期:'
Assert-Contains -Name "workspace dashboard empty states are bilingual" -Text $workspaceSource -Pattern 'Write-WorkspaceCheck[\s\S]*?-ChineseName[\s\S]*?\"清单\"[\s\S]*?\"状态\"[\s\S]*?\"项目\"[\s\S]*?\"里程碑\"[\s\S]*?\"评估\"[\s\S]*?\"任务\"[\s\S]*?none configured[\s\S]*?未配置'
Assert-Contains -Name "workspace report is non-destructive" -Text $workspaceSource -Pattern 'Report only: no projects will be cloned, no sync sessions will be changed, no snapshots will be created, no validation or evaluation commands will be run, and no Git commands will be run'
Assert-Contains -Name "workspace report supports Markdown evidence" -Text $workspaceSource -Pattern '\[switch\]\$Markdown[\s\S]*function\s+Write-WorkspaceReportMarkdown[\s\S]*Workspace Release Evidence[\s\S]*Markdown report only[\s\S]*Task Evidence[\s\S]*Maintainer Checklist'
Assert-Contains -Name "workspace report normalizes Markdown evidence paths" -Text $workspaceSource -Pattern 'function\s+Format-WorkspaceEvidencePath[\s\S]*Get-ProjectRoot[\s\S]*Local state \| \$\(Format-WorkspaceMarkdownValue \(Format-WorkspaceEvidencePath \$resolvedStatePath\)\)'
Assert-Contains -Name "workspace report routes Markdown evidence" -Text $workspaceSource -Pattern '"report"\s*\{[\s\S]*Write-WorkspaceReport\s+-Manifest\s+\$manifest\s+-ManifestPath\s+\$ManifestPath\s+-StatePath\s+\$StatePath\s+-Markdown:\$Markdown'
Assert-Contains -Name "workspace report summarizes task decisions" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceReport[\s\S]*validation result:[\s\S]*review:[\s\S]*rollback:[\s\S]*commit:'
Assert-Contains -Name "workspace report includes sync hygiene release evidence" -Text $workspaceSource -Pattern 'function\s+New-WorkspaceReportItem[\s\S]*Get-WorkspaceTaskSyncHygieneStatus[\s\S]*review sync ignore[\s\S]*release blocked[\s\S]*function\s+Write-WorkspaceReportMarkdown[\s\S]*Sync hygiene[\s\S]*function\s+Write-WorkspaceReport[\s\S]*sync hygiene:'
Assert-Contains -Name "workspace report includes snapshot naming evidence" -Text $workspaceSource -Pattern 'function\s+New-WorkspaceReportItem[\s\S]*Get-WorkspaceSnapshotNamingStatus[\s\S]*SnapshotNaming[\s\S]*Write-WorkspaceReportMarkdown[\s\S]*naming: \$\(\$item\.SnapshotNaming\.Status\)[\s\S]*Write-WorkspaceReport[\s\S]*snapshot naming: \$\(\$item\.SnapshotNaming\.Status\)'
Assert-Contains -Name "workspace report reads checkpoint waiver state" -Text $workspaceSource -Pattern 'function\s+New-WorkspaceReportItem[\s\S]*Get-WorkspaceTaskState[\s\S]*Get-WorkspaceSnapshotGate\s+-Task\s+\$Task\s+-SnapshotStatus\s+\$snapshotStatus\s+-RecordedState\s+\$recordedState'
Assert-Contains -Name "workspace report includes milestone release evidence" -Text $workspaceSource -Pattern 'function\s+New-WorkspaceReportItem[\s\S]*Get-WorkspaceTaskMilestones[\s\S]*MilestoneText[\s\S]*function\s+Write-WorkspaceMilestoneCheckpoints[\s\S]*Milestone checkpoints:[\s\S]*function\s+Get-WorkspaceMilestoneReviewRollups[\s\S]*function\s+Write-WorkspaceMilestoneReviewRollup[\s\S]*Milestone review rollup:[\s\S]*function\s+Write-WorkspaceReportMarkdown[\s\S]*## Milestone Checkpoints[\s\S]*## Milestone Review Rollup[\s\S]*\| Task \| Milestone \| Evaluation \| Owner \| Runtime'
Assert-Contains -Name "workspace report includes evaluation queue evidence" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceEvaluationQueueItems[\s\S]*function\s+Write-WorkspaceEvaluationQueue[\s\S]*Evaluation queue:[\s\S]*Evaluation queue only: no evaluation commands will be run[\s\S]*function\s+Write-WorkspaceReportMarkdown[\s\S]*## Evaluation Queue[\s\S]*No evaluation commands were run[\s\S]*\| Task \| Milestone \| Evaluation \| Owner \| Runtime'
Assert-Contains -Name "workspace report checklist includes sync hygiene gate" -Text $workspaceSource -Pattern 'Maintainer Checklist[\s\S]*Confirm sync hygiene is clean, covered, not requested, or intentionally reviewed before release[\s\S]*commit only after sync hygiene, validation, and human review are all accepted'
Assert-Contains -Name "workspace report has release handoff summary" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceReportSummary[\s\S]*Release handoff summary:[\s\S]*blocked tasks:[\s\S]*ready for review:[\s\S]*ready to commit:[\s\S]*release gate:'
Assert-Contains -Name "workspace report has governance fields" -Text $workspaceSource -Pattern 'function\s+New-WorkspaceReportItem[\s\S]*OwnerName[\s\S]*ReviewCadence[\s\S]*DueStatus[\s\S]*function\s+Write-WorkspaceReportSummary[\s\S]*owner gaps:[\s\S]*cadence gaps:[\s\S]*due attention:'
Assert-Contains -Name "workspace report has governance loop" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceGovernanceLoop[\s\S]*Governance loop:[\s\S]*owner queues:[\s\S]*review cadence:[\s\S]*attention queue:'
Assert-Contains -Name "workspace report has decision queues" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceDecisionQueues[\s\S]*Decision queues:[\s\S]*actions:[\s\S]*release readiness:[\s\S]*action:[\s\S]*release readiness:'
Assert-Contains -Name "workspace report has validation execution queue" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceValidationQueueItems[\s\S]*ready to execute[\s\S]*ExecutePreview[\s\S]*function\s+Write-WorkspaceValidationQueue[\s\S]*Validation execution queue:[\s\S]*execute preview:[\s\S]*function\s+Write-WorkspaceReportMarkdown[\s\S]*## Validation Execution Queue'
Assert-Contains -Name "workspace report has release policy" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceReleasePolicy[\s\S]*Release decision policy:[\s\S]*decision:[\s\S]*blockers:[\s\S]*validation required:[\s\S]*review required:[\s\S]*release candidates:'
Assert-Contains -Name "workspace report has stale remediation" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceStaleTaskRemediation[\s\S]*Stale-task remediation:[\s\S]*owner=.*cadence=.*timing=.*action=.*release='
Assert-Contains -Name "workspace run prints snapshot-first gate" -Text $workspaceSource -Pattern 'Snapshot-first gate before broad agent work'
Assert-Contains -Name "workspace task snapshot prints snapshot naming convention" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceTaskSnapshot[\s\S]*snapshot naming[\s\S]*Explicit command to create the checkpoint'
Assert-Contains -Name "workspace task snapshot prints waiver command" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceTaskSnapshot[\s\S]*If the human reviewer intentionally accepts missing snapshot protection[\s\S]*adpos workspace task mark \$\(\$Task\.name\) checkpoint-waived'
Assert-Contains -Name "workspace validate supports explicit execution" -Text $workspaceSource -Pattern '\[switch\]\$Execute[\s\S]*\[switch\]\$Plan[\s\S]*function\s+Invoke-WorkspaceRemoteValidationCommand[\s\S]*Write-WorkspaceTaskValidate'
Assert-Contains -Name "workspace validate execution is scoped to validate command" -Text $workspaceSource -Pattern '-Execute.*-Local.*-Plan are only supported with: adpos workspace task validate <task-name>'
Assert-Contains -Name "workspace validate execution resolves task project" -Text $workspaceSource -Pattern 'Find-WorkspaceProjectForTask[\s\S]*tasks\[\]\.project'
Assert-Contains -Name "workspace validate execution rejects unsafe project paths" -Text $workspaceSource -Pattern 'Resolve-WorkspaceRemoteProjectPath[\s\S]*path cannot contain'
Assert-Contains -Name "workspace validate execution records validation result" -Text $workspaceSource -Pattern 'Set-WorkspaceTaskValidationResult[\s\S]*validation_failed[\s\S]*Write-WorkspaceValidationResult'
Assert-Contains -Name "workspace validate execution prints readiness gate" -Text $workspaceSource -Pattern 'Readiness gate:[\s\S]*snapshot-first gate[\s\S]*ssh target'
Assert-Contains -Name "workspace dashboard displays validation result" -Text $workspaceSource -Pattern 'Format-WorkspaceValidationState[\s\S]*validation result:'
Assert-Contains -Name "workspace review displays validation result" -Text $workspaceSource -Pattern 'recorded validation:[\s\S]*Write-WorkspaceValidationDetailLines[\s\S]*state file:'
Assert-Contains -Name "workspace review has decision gate" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceReviewDecision[\s\S]*blocked by sync hygiene[\s\S]*validation failed[\s\S]*validation result missing'
Assert-Contains -Name "workspace review prints sync hygiene gate" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceTaskReview[\s\S]*Get-WorkspaceTaskSyncHygieneStatus[\s\S]*Confirm sync hygiene before review[\s\S]*Review should not accept the task until sync hygiene is reviewed'
Assert-Contains -Name "workspace review withholds acceptance until gate passes" -Text $workspaceSource -Pattern 'if\s*\(\$reviewDecision\.Verdict\s+-eq\s+"validation passed"\)[\s\S]*accept:\s+adpos workspace task mark \$\(\$Task\.name\) reviewed[\s\S]*accept:\s+withheld until review decision gate is OK[\s\S]*Commit readiness requires sync hygiene, recorded validation'
Assert-Contains -Name "workspace rollback reads validation and sync hygiene state" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceTaskRollback[\s\S]*Get-WorkspaceTaskSyncHygieneStatus[\s\S]*Decision context:[\s\S]*sync hygiene:[\s\S]*recorded validation:'
Assert-Contains -Name "workspace rollback withholds restore when checkpoint gate blocks" -Text $workspaceSource -Pattern 'Snapshot rollback is not ready:[\s\S]*Resolve the checkpoint gate before using VM snapshot rollback[\s\S]*adpos restore \$\(\$Task\.runtime\) \$\(\$Task\.snapshot\)'
Assert-Contains -Name "workspace rollback withholds restore when checkpoint is waived" -Text $workspaceSource -Pattern 'Snapshot rollback is waived:[\s\S]*No VM restore command is printed because no checkpoint was confirmed[\s\S]*adpos restore \$\(\$Task\.runtime\) \$\(\$Task\.snapshot\)'
Assert-Contains -Name "workspace rollback prints local rollback mark command" -Text $workspaceSource -Pattern 'After rollback is completed manually, record local rollback state:[\s\S]*adpos workspace task mark \$\(\$Task\.name\) rollback'
Assert-Contains -Name "workspace rollback receives manifest and state paths" -Text $workspaceSource -Pattern '"rollback"\s*\{[\s\S]*Write-WorkspaceTaskRollback\s+-Manifest\s+\$Manifest\s+-Task\s+\$task\s+-ManifestPath\s+\$Path\s+-StatePath\s+\$LocalStatePath'
Assert-Contains -Name "workspace commit has readiness gate" -Text $workspaceSource -Pattern 'function\s+Get-WorkspaceCommitDecision[\s\S]*blocked by sync hygiene[\s\S]*blocked by validation[\s\S]*commit ready[\s\S]*review not recorded'
Assert-Contains -Name "workspace commit reads validation and sync hygiene state" -Text $workspaceSource -Pattern 'function\s+Write-WorkspaceTaskCommit[\s\S]*Get-WorkspaceTaskSyncHygieneStatus[\s\S]*Commit readiness gate:[\s\S]*sync hygiene:[\s\S]*recorded validation:'
Assert-Contains -Name "workspace commit withholds git commands until ready" -Text $workspaceSource -Pattern 'if\s*\(\$commitDecision\.Verdict\s+-eq\s+"commit ready"\)[\s\S]*git add <paths>[\s\S]*Commit commands withheld until commit readiness is OK'
Assert-Contains -Name "workspace commit prints local committed mark command" -Text $workspaceSource -Pattern 'After the commit is created manually, record local committed state:[\s\S]*adpos workspace task mark \$\(\$Task\.name\) committed'
Assert-Contains -Name "workspace commit receives manifest and state path" -Text $workspaceSource -Pattern '"commit"\s*\{[\s\S]*Write-WorkspaceTaskCommit\s+-Manifest\s+\$Manifest\s+-Task\s+\$task\s+-ManifestPath\s+\$Path\s+-StatePath\s+\$LocalStatePath'
Assert-Contains -Name "workspace state defaults to ignored local path" -Text $workspaceSource -Pattern 'adp-workspace\.state\.json'
Assert-Contains -Name "workspace task mark records local state only" -Text $workspaceSource -Pattern 'Recorded local lifecycle state only\. No VM, sync, snapshot, file, Git, or validation command was run'
Assert-Contains -Name "workspace task mark supports checkpoint waiver boundary" -Text $workspaceSource -Pattern '\$validStates\s*=\s*@\("prepared", "checkpointed", "checkpoint-waived"[\s\S]*checkpoint-waived records explicit human acceptance of missing VM snapshot protection[\s\S]*does not create a snapshot, prove rollback safety, or restore rollback capability'
Assert-Contains -Name "workspace task lifecycle is plan-only" -Text $workspaceSource -Pattern 'Task lifecycle output is plan-only\. No VM, sync, snapshot, file, Git, or validation command will be changed or run'
Assert-Contains -Name "workspace task run states manual execution boundary" -Text $workspaceSource -Pattern 'Manual execution only: this command does not start an agent, approve broad agent work, record task state, run validation, or make the task commit-ready'
Assert-Contains -Name "workspace task run points running mark to local state" -Text $workspaceSource -Pattern 'After manual execution starts, mark running only as local state:[\s\S]*adpos workspace task mark \$\(\$Task\.name\) running'
Assert-Contains -Name "workspace task mark running boundary" -Text $workspaceSource -Pattern 'running means manual execution began or was attempted; ADP-OS did not start the agent, approve execution, validate output, or satisfy review/commit readiness'
Assert-Contains -Name "workspace task mark reviewed boundary" -Text $workspaceSource -Pattern 'reviewed should be used only after human source review accepts the diff, rollback path, snapshot context, and recorded validation evidence'
Assert-Contains -Name "workspace task mark committed boundary" -Text $workspaceSource -Pattern 'committed is a local lifecycle note only; ADP-OS did not stage files or run git commit'
Assert-Contains -Name "workspace task mark rollback boundary" -Text $workspaceSource -Pattern 'rollback is a local lifecycle note only; ADP-OS did not restore snapshots or modify source files'
Assert-Contains -Name "workspace task mark validated boundary" -Text $workspaceSource -Pattern 'validated records an external validation result \(status: passed\)'
Assert-Contains -Name "workspace task mark validation_failed boundary" -Text $workspaceSource -Pattern 'validation_failed records an external validation result \(status: failed\)'
Assert-Contains -Name "workspace task mark external validation state path" -Text $workspaceSource -Pattern 'Set-WorkspaceTaskExternalValidation[\s\S]*ValidationStatus'
Assert-Contains -Name "workspace task mark validation_failed in validStates" -Text $workspaceSource -Pattern '\$validStates\s*=\s*@\("prepared", "checkpointed", "checkpoint-waived", "running", "validated", "validation_failed"'
Assert-Contains -Name "workspace task lifecycle supports prepare" -Text $workspaceSource -Pattern '"prepare"[\s\S]*Write-WorkspaceTaskPrepare'
Assert-Contains -Name "workspace task lifecycle supports snapshot" -Text $workspaceSource -Pattern '"snapshot"[\s\S]*Write-WorkspaceTaskSnapshot'
Assert-Contains -Name "workspace task lifecycle supports run" -Text $workspaceSource -Pattern '"run"[\s\S]*Write-WorkspaceTaskRun'
Assert-Contains -Name "workspace task lifecycle supports validate" -Text $workspaceSource -Pattern '"validate"[\s\S]*Write-WorkspaceTaskValidate'
Assert-Contains -Name "workspace task lifecycle supports review" -Text $workspaceSource -Pattern '"review"[\s\S]*Write-WorkspaceTaskReview'
Assert-Contains -Name "workspace task lifecycle supports rollback" -Text $workspaceSource -Pattern '"rollback"[\s\S]*Write-WorkspaceTaskRollback'
Assert-Contains -Name "workspace task lifecycle supports commit" -Text $workspaceSource -Pattern '"commit"[\s\S]*Write-WorkspaceTaskCommit'
Assert-Contains -Name "workspace task lifecycle supports mark" -Text $workspaceSource -Pattern '"mark"[\s\S]*Write-WorkspaceTaskMark'

Write-Output "CLI parameter contracts OK"
