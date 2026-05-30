# ADP-OS configuration shape checks.
# Keeps committed examples structurally valid without adding a schema dependency.

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path $PSScriptRoot -Parent
$runtimeNames = @("frontend", "backend", "agent")

function Read-ConfigJson {
    param([string]$RelativePath)

    $path = Join-Path $projectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing config file: $RelativePath"
    }

    $raw = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Config file is empty: $RelativePath"
    }

    return $raw | ConvertFrom-Json
}

function Assert-Property {
    param(
        [string]$Name,
        [object]$Object,
        [string]$Property
    )

    if ($null -eq $Object -or -not ($Object.PSObject.Properties.Name -contains $Property)) {
        throw "$Name is missing required property: $Property"
    }
}

function Assert-StringProperty {
    param(
        [string]$Name,
        [object]$Object,
        [string]$Property
    )

    Assert-Property -Name $Name -Object $Object -Property $Property
    if ([string]::IsNullOrWhiteSpace([string]$Object.$Property)) {
        throw "$Name.$Property must be a non-empty string"
    }
}

function Assert-PositiveIntProperty {
    param(
        [string]$Name,
        [object]$Object,
        [string]$Property
    )

    Assert-Property -Name $Name -Object $Object -Property $Property
    $value = $Object.$Property
    if (-not ($value -is [byte] -or $value -is [int16] -or $value -is [int] -or $value -is [long]) -or $value -le 0) {
        throw "$Name.$Property must be a positive integer"
    }
}

function Assert-BooleanProperty {
    param(
        [string]$Name,
        [object]$Object,
        [string]$Property
    )

    Assert-Property -Name $Name -Object $Object -Property $Property
    if (-not ($Object.$Property -is [bool])) {
        throw "$Name.$Property must be a boolean"
    }
}

function Assert-StringArray {
    param(
        [string]$Name,
        [object]$Value,
        [switch]$AllowEmpty
    )

    $items = @($Value)
    if (-not $AllowEmpty -and $items.Count -eq 0) {
        throw "$Name must contain at least one string"
    }

    foreach ($item in $items) {
        if ([string]::IsNullOrWhiteSpace([string]$item)) {
            throw "$Name contains an empty string"
        }
    }
}

function Assert-LanguageValue {
    param(
        [string]$Name,
        [string]$Language
    )

    if ($Language -notin @("en", "zh-CN")) {
        throw "$Name must be one of: en, zh-CN"
    }
}

function Assert-RuntimeName {
    param(
        [string]$Name,
        [string]$Runtime
    )

    if ($Runtime -notin $runtimeNames) {
        throw "$Name references unknown runtime: $Runtime"
    }
}

function Assert-RelativePath {
    param(
        [string]$Name,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw "$Name must be a non-empty relative path"
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        throw "$Name must be relative, not absolute: $Path"
    }

    $segments = $Path -split '[\\/]+' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    if ($segments | Where-Object { $_ -eq "." -or $_ -eq ".." }) {
        throw "$Name cannot contain '.' or '..' segments: $Path"
    }
}

function Assert-OptionalTaskGovernance {
    param(
        [string]$Name,
        [object]$Task
    )

    foreach ($field in @("owner", "review_cadence")) {
        if ($Task.PSObject.Properties.Name -contains $field -and [string]::IsNullOrWhiteSpace([string]$Task.$field)) {
            throw "$Name.tasks[$($Task.name)].$field must be a non-empty string when present"
        }
    }

    if ($Task.PSObject.Properties.Name -contains "due" -and -not [string]::IsNullOrWhiteSpace([string]$Task.due)) {
        $ignored = [datetime]::MinValue
        if (-not [datetime]::TryParse([string]$Task.due, [ref]$ignored)) {
            throw "$Name.tasks[$($Task.name)].due must be a parseable date when present"
        }
    }
}

function Assert-PlatformConfig {
    param([object]$Config)

    Assert-StringProperty -Name "platform.json" -Object $Config -Property "platform"
    Assert-StringProperty -Name "platform.json" -Object $Config -Property "version"
    Assert-Property -Name "platform.json" -Object $Config -Property "paths"
    Assert-Property -Name "platform.json" -Object $Config -Property "defaults"
    Assert-Property -Name "platform.json" -Object $Config -Property "network"
    Assert-Property -Name "platform.json" -Object $Config -Property "ui"
    Assert-Property -Name "platform.json" -Object $Config -Property "features"
    Assert-Property -Name "platform.json" -Object $Config -Property "tools"

    foreach ($pathKey in @("workspace_root", "iso_cache", "vm_store", "logs", "snapshots", "configs")) {
        Assert-StringProperty -Name "platform.json.paths" -Object $Config.paths -Property $pathKey
    }

    foreach ($defaultKey in @("ubuntu_iso", "ubuntu_version", "admin_user", "admin_password")) {
        Assert-StringProperty -Name "platform.json.defaults" -Object $Config.defaults -Property $defaultKey
    }

    foreach ($defaultKey in @("vm_memory_base", "vm_cpu_base", "vm_disk_base", "ssh_port_start")) {
        Assert-PositiveIntProperty -Name "platform.json.defaults" -Object $Config.defaults -Property $defaultKey
    }

    Assert-StringProperty -Name "platform.json.network" -Object $Config.network -Property "mode"
    Assert-Property -Name "platform.json.network" -Object $Config.network -Property "vmware_nat"
    Assert-StringProperty -Name "platform.json.network.vmware_nat" -Object $Config.network.vmware_nat -Property "cidr"
    Assert-PositiveIntProperty -Name "platform.json.network.vmware_nat" -Object $Config.network.vmware_nat -Property "prefix"
    Assert-StringProperty -Name "platform.json.network.vmware_nat" -Object $Config.network.vmware_nat -Property "gateway"
    Assert-StringArray -Name "platform.json.network.vmware_nat.dns" -Value $Config.network.vmware_nat.dns
    Assert-StringProperty -Name "platform.json.network.vmware_nat" -Object $Config.network.vmware_nat -Property "interface_match"

    Assert-StringProperty -Name "platform.json.ui" -Object $Config.ui -Property "language"
    Assert-LanguageValue -Name "platform.json.ui.language" -Language ([string]$Config.ui.language)

    foreach ($feature in @("vmware", "hyperv", "mutagen", "docker")) {
        Assert-BooleanProperty -Name "platform.json.features" -Object $Config.features -Property $feature
    }

    Assert-Property -Name "platform.json.tools" -Object $Config.tools -Property "mutagen"
    Assert-StringProperty -Name "platform.json.tools.mutagen" -Object $Config.tools.mutagen -Property "version"
    Assert-StringProperty -Name "platform.json.tools.mutagen" -Object $Config.tools.mutagen -Property "download_url"
    Assert-PositiveIntProperty -Name "platform.json.tools.mutagen" -Object $Config.tools.mutagen -Property "connection_timeout_seconds"
    Assert-PositiveIntProperty -Name "platform.json.tools.mutagen" -Object $Config.tools.mutagen -Property "download_timeout_seconds"
    Assert-Property -Name "platform.json.tools.mutagen" -Object $Config.tools.mutagen -Property "archive_path"
    Assert-Property -Name "platform.json.tools.mutagen" -Object $Config.tools.mutagen -Property "sha256"

    if ($Config.tools.mutagen.sha256 -and ([string]$Config.tools.mutagen.sha256 -notmatch '^[a-fA-F0-9]{64}$')) {
        throw "platform.json.tools.mutagen.sha256 must be null or a 64-character hexadecimal SHA256"
    }
}

function Assert-TopologyConfig {
    param([object]$Config)

    foreach ($runtimeName in $runtimeNames) {
        Assert-Property -Name "topology.json" -Object $Config -Property $runtimeName
        $runtime = $Config.$runtimeName
        foreach ($field in @("runtime", "os", "workspace", "sync_profile", "bootstrap_profile", "snapshot_policy", "static_ip")) {
            Assert-StringProperty -Name "topology.json.$runtimeName" -Object $runtime -Property $field
        }
        foreach ($field in @("cpu", "memory", "disk", "ssh_port")) {
            Assert-PositiveIntProperty -Name "topology.json.$runtimeName" -Object $runtime -Property $field
        }
        Assert-BooleanProperty -Name "topology.json.$runtimeName" -Object $runtime -Property "danger"
    }
}

function Assert-SyncProfiles {
    param(
        [object]$Config,
        [object]$Topology
    )

    foreach ($runtimeName in $runtimeNames) {
        $profileName = [string]$Topology.$runtimeName.sync_profile
        Assert-Property -Name "sync-profiles.json" -Object $Config -Property $profileName
        $profile = $Config.$profileName
        Assert-StringProperty -Name "sync-profiles.json.$profileName" -Object $profile -Property "mode"
        Assert-StringProperty -Name "sync-profiles.json.$profileName" -Object $profile -Property "watch_mode"
        Assert-PositiveIntProperty -Name "sync-profiles.json.$profileName" -Object $profile -Property "sync_interval_ms"
        Assert-StringArray -Name "sync-profiles.json.$profileName.ignore" -Value $profile.ignore
    }

    $requiredIgnores = @{
        frontend = @("node_modules", ".next", "dist", "build", "coverage", ".turbo", ".cache", ".parcel-cache", ".vite", ".nuxt", ".svelte-kit", "playwright-report", "test-results", "blob-report", ".playwright")
        backend  = @("dist", "build", "coverage", "__pycache__", ".venv", "venv", ".mypy_cache", ".ruff_cache", "*.pyc", ".pytest_cache", ".cache", ".tox", ".nox", ".coverage", "htmlcov")
        agent    = @("node_modules", ".git", ".venv", "venv", "dist", ".next", "build", "coverage", "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".cache", ".turbo", ".parcel-cache", ".vite", ".nuxt", ".svelte-kit", ".playwright", "playwright-report", "test-results", "blob-report", ".codex", ".claude", ".tools", "logs")
    }

    foreach ($profileName in $requiredIgnores.Keys) {
        Assert-Property -Name "sync-profiles.json" -Object $Config -Property $profileName
        $ignore = @($Config.$profileName.ignore | ForEach-Object { [string]$_ })
        foreach ($expected in $requiredIgnores[$profileName]) {
            if ($expected -notin $ignore) {
                throw "sync-profiles.json.$profileName.ignore is missing expected generated-artifact ignore: $expected"
            }
        }
    }
}

function Assert-LocalExample {
    param([object]$Config)

    $supportedSections = @("platform", "topology", "sync_profiles")
    foreach ($section in $Config.PSObject.Properties.Name) {
        if ($section -notin $supportedSections) {
            throw "configs/local.example.json contains unsupported top-level section: $section"
        }
    }

    if ($Config.PSObject.Properties.Name -contains "sync_profiles" -and $Config.sync_profiles.PSObject.Properties.Name -contains "frontend") {
        $frontendIgnore = @($Config.sync_profiles.frontend.ignore | ForEach-Object { [string]$_ })
        foreach ($expected in @("node_modules", ".next", "dist", "build", "coverage", ".turbo", ".cache", "playwright-report", "test-results", "blob-report", ".playwright")) {
            if ($expected -notin $frontendIgnore) {
                throw "configs/local.example.json frontend sync override should demonstrate preserving generated-artifact ignore: $expected"
            }
        }
    }

    if ($Config.PSObject.Properties.Name -contains "platform" -and $Config.platform.PSObject.Properties.Name -contains "ui") {
        Assert-StringProperty -Name "configs/local.example.json.platform.ui" -Object $Config.platform.ui -Property "language"
        Assert-LanguageValue -Name "configs/local.example.json.platform.ui.language" -Language ([string]$Config.platform.ui.language)
    }

    if ($Config.PSObject.Properties.Name -contains "platform" -and $Config.platform.PSObject.Properties.Name -contains "tools") {
        Assert-Property -Name "configs/local.example.json.platform.tools" -Object $Config.platform.tools -Property "mutagen"
        Assert-StringProperty -Name "configs/local.example.json.platform.tools.mutagen" -Object $Config.platform.tools.mutagen -Property "download_url"
        Assert-StringProperty -Name "configs/local.example.json.platform.tools.mutagen" -Object $Config.platform.tools.mutagen -Property "archive_path"
        Assert-PositiveIntProperty -Name "configs/local.example.json.platform.tools.mutagen" -Object $Config.platform.tools.mutagen -Property "connection_timeout_seconds"
        Assert-PositiveIntProperty -Name "configs/local.example.json.platform.tools.mutagen" -Object $Config.platform.tools.mutagen -Property "download_timeout_seconds"
        Assert-Property -Name "configs/local.example.json.platform.tools.mutagen" -Object $Config.platform.tools.mutagen -Property "sha256"
    }
}

function Assert-WorkspaceManifest {
    param(
        [string]$Name,
        [object]$Manifest
    )

    Assert-StringProperty -Name $Name -Object $Manifest -Property "name"
    Assert-PositiveIntProperty -Name $Name -Object $Manifest -Property "version"
    Assert-Property -Name $Name -Object $Manifest -Property "projects"
    Assert-Property -Name $Name -Object $Manifest -Property "tasks"

    $projectNames = [System.Collections.Generic.HashSet[string]]::new()
    $taskNames = [System.Collections.Generic.HashSet[string]]::new()
    $milestoneNames = [System.Collections.Generic.HashSet[string]]::new()
    $evaluationNames = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($project in @($Manifest.projects)) {
        Assert-StringProperty -Name "$Name.projects[]" -Object $project -Property "name"
        Assert-StringProperty -Name "$Name.projects[$($project.name)]" -Object $project -Property "path"
        Assert-RelativePath -Name "$Name.projects[$($project.name)].path" -Path ([string]$project.path)
        Assert-StringProperty -Name "$Name.projects[$($project.name)]" -Object $project -Property "runtime"
        Assert-RuntimeName -Name "$Name.projects[$($project.name)].runtime" -Runtime ([string]$project.runtime)
        Assert-BooleanProperty -Name "$Name.projects[$($project.name)]" -Object $project -Property "sync"
        if ($project.PSObject.Properties.Name -contains "devcontainer" -and [string]::IsNullOrWhiteSpace([string]$project.devcontainer)) {
            throw "$Name.projects[$($project.name)].devcontainer must be a non-empty string when present"
        }
        Assert-StringArray -Name "$Name.projects[$($project.name)].validation" -Value $project.validation
        if (-not $projectNames.Add([string]$project.name)) {
            throw "$Name has duplicate project name: $($project.name)"
        }
    }

    foreach ($task in @($Manifest.tasks)) {
        Assert-StringProperty -Name "$Name.tasks[]" -Object $task -Property "name"
        if (-not $taskNames.Add([string]$task.name)) {
            throw "$Name has duplicate task name: $($task.name)"
        }
        Assert-StringProperty -Name "$Name.tasks[$($task.name)]" -Object $task -Property "runtime"
        Assert-RuntimeName -Name "$Name.tasks[$($task.name)].runtime" -Runtime ([string]$task.runtime)
        Assert-StringArray -Name "$Name.tasks[$($task.name)].validation" -Value $task.validation
        Assert-OptionalTaskGovernance -Name $Name -Task $task

        if ($task.PSObject.Properties.Name -contains "project" -and -not [string]::IsNullOrWhiteSpace([string]$task.project)) {
            if (-not $projectNames.Contains([string]$task.project)) {
                throw "$Name.tasks[$($task.name)].project references unknown project: $($task.project)"
            }
        }

        if ($task.PSObject.Properties.Name -contains "requires_snapshot") {
            Assert-BooleanProperty -Name "$Name.tasks[$($task.name)]" -Object $task -Property "requires_snapshot"
        }

        $requiresSnapshot = ($task.PSObject.Properties.Name -contains "requires_snapshot" -and [bool]$task.requires_snapshot)
        if ($requiresSnapshot) {
            Assert-StringProperty -Name "$Name.tasks[$($task.name)]" -Object $task -Property "snapshot"
        }
    }

    if ($Manifest.PSObject.Properties.Name -contains "milestones") {
        foreach ($milestone in @($Manifest.milestones)) {
            Assert-StringProperty -Name "$Name.milestones[]" -Object $milestone -Property "name"
            if (-not $milestoneNames.Add([string]$milestone.name)) {
                throw "$Name has duplicate milestone name: $($milestone.name)"
            }

            if ($milestone.PSObject.Properties.Name -contains "description" -and [string]::IsNullOrWhiteSpace([string]$milestone.description)) {
                throw "$Name.milestones[$($milestone.name)].description must be a non-empty string when present"
            }

            if ($milestone.PSObject.Properties.Name -contains "runtime") {
                Assert-StringProperty -Name "$Name.milestones[$($milestone.name)]" -Object $milestone -Property "runtime"
                Assert-RuntimeName -Name "$Name.milestones[$($milestone.name)].runtime" -Runtime ([string]$milestone.runtime)
            }

            if ($milestone.PSObject.Properties.Name -contains "snapshot") {
                Assert-StringProperty -Name "$Name.milestones[$($milestone.name)]" -Object $milestone -Property "snapshot"
            }

            if ($milestone.PSObject.Properties.Name -contains "tasks") {
                Assert-StringArray -Name "$Name.milestones[$($milestone.name)].tasks" -Value $milestone.tasks
                foreach ($taskName in @($milestone.tasks)) {
                    if (-not $taskNames.Contains([string]$taskName)) {
                        throw "$Name.milestones[$($milestone.name)].tasks references unknown task: $taskName"
                    }
                }
            }
        }
    }

    if ($Manifest.PSObject.Properties.Name -contains "evaluations") {
        foreach ($evaluation in @($Manifest.evaluations)) {
            Assert-StringProperty -Name "$Name.evaluations[]" -Object $evaluation -Property "name"
            if (-not $evaluationNames.Add([string]$evaluation.name)) {
                throw "$Name has duplicate evaluation name: $($evaluation.name)"
            }

            if ($evaluation.PSObject.Properties.Name -contains "description" -and [string]::IsNullOrWhiteSpace([string]$evaluation.description)) {
                throw "$Name.evaluations[$($evaluation.name)].description must be a non-empty string when present"
            }

            if ($evaluation.PSObject.Properties.Name -contains "project" -and -not [string]::IsNullOrWhiteSpace([string]$evaluation.project)) {
                if (-not $projectNames.Contains([string]$evaluation.project)) {
                    throw "$Name.evaluations[$($evaluation.name)].project references unknown project: $($evaluation.project)"
                }
            }

            if ($evaluation.PSObject.Properties.Name -contains "runtime") {
                Assert-StringProperty -Name "$Name.evaluations[$($evaluation.name)]" -Object $evaluation -Property "runtime"
                Assert-RuntimeName -Name "$Name.evaluations[$($evaluation.name)].runtime" -Runtime ([string]$evaluation.runtime)
            }

            if ($evaluation.PSObject.Properties.Name -contains "cadence" -and [string]::IsNullOrWhiteSpace([string]$evaluation.cadence)) {
                throw "$Name.evaluations[$($evaluation.name)].cadence must be a non-empty string when present"
            }

            Assert-StringArray -Name "$Name.evaluations[$($evaluation.name)].metrics" -Value $evaluation.metrics
            Assert-StringArray -Name "$Name.evaluations[$($evaluation.name)].commands" -Value $evaluation.commands

            if ($evaluation.PSObject.Properties.Name -contains "tasks") {
                Assert-StringArray -Name "$Name.evaluations[$($evaluation.name)].tasks" -Value $evaluation.tasks
                foreach ($taskName in @($evaluation.tasks)) {
                    if (-not $taskNames.Contains([string]$taskName)) {
                        throw "$Name.evaluations[$($evaluation.name)].tasks references unknown task: $taskName"
                    }
                }
            }
        }
    }

    foreach ($task in @($Manifest.tasks)) {
        if ($task.PSObject.Properties.Name -contains "milestone" -and -not [string]::IsNullOrWhiteSpace([string]$task.milestone)) {
            if (-not $milestoneNames.Contains([string]$task.milestone)) {
                throw "$Name.tasks[$($task.name)].milestone references unknown milestone: $($task.milestone)"
            }
        }

        if ($task.PSObject.Properties.Name -contains "evaluation" -and -not [string]::IsNullOrWhiteSpace([string]$task.evaluation)) {
            if (-not $evaluationNames.Contains([string]$task.evaluation)) {
                throw "$Name.tasks[$($task.name)].evaluation references unknown evaluation: $($task.evaluation)"
            }
        }
    }
}

$platform = Read-ConfigJson "configs\platform.json"
$topology = Read-ConfigJson "configs\topology.json"
$syncProfiles = Read-ConfigJson "configs\sync-profiles.json"
$localExample = Read-ConfigJson "configs\local.example.json"
$workspaceExample = Read-ConfigJson "configs\workspace.example.json"
$workspaceRecipes = Read-ConfigJson "configs\workspace.recipes.example.json"

Assert-PlatformConfig -Config $platform
Assert-TopologyConfig -Config $topology
Assert-SyncProfiles -Config $syncProfiles -Topology $topology
Assert-LocalExample -Config $localExample
Assert-WorkspaceManifest -Name "configs/workspace.example.json" -Manifest $workspaceExample
Assert-WorkspaceManifest -Name "configs/workspace.recipes.example.json" -Manifest $workspaceRecipes

Write-Output "Configuration schema checks OK"
