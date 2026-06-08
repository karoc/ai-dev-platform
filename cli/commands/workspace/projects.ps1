function Quote-PosixSingleArgument {
    param([string]$Value)

    return "'" + ($Value -replace "'", "'""'""'") + "'"
}

function Quote-WorkspacePowerShellArgument {
    param([string]$Value)

    return "'" + ($Value -replace "'", "''") + "'"
}

function Find-WorkspaceProject {
    param(
        [object]$Manifest,
        [string]$Name
    )

    $projects = Get-WorkspaceArray $Manifest.projects
    if ($projects.Count -eq 0) {
        throw "Workspace manifest has no projects[]. Add a project before using workspace open."
    }

    if ([string]::IsNullOrWhiteSpace($Name)) {
        if ($projects.Count -eq 1) {
            return $projects[0]
        }

        $available = @($projects | ForEach-Object { if ($_.name) { [string]$_.name } else { "(unnamed)" } })
        throw "Project name required because the workspace has multiple projects. Available projects: $($available -join ', ')"
    }

    foreach ($project in $projects) {
        if ($project.name -eq $Name) {
            return $project
        }
    }

    $availableNames = @($projects | ForEach-Object { if ($_.name) { [string]$_.name } else { "(unnamed)" } })
    throw "Workspace project not found: $Name. Available projects: $($availableNames -join ', ')"
}

function Find-WorkspaceProjectForTask {
    param(
        [object]$Manifest,
        [object]$Task
    )

    $projects = Get-WorkspaceArray $Manifest.projects
    $taskProjectName = if ($Task.PSObject.Properties.Name -contains "project") { [string]$Task.project } else { "" }

    if (-not [string]::IsNullOrWhiteSpace($taskProjectName)) {
        foreach ($project in $projects) {
            if ($project.name -eq $taskProjectName) {
                return $project
            }
        }

        throw "Workspace task '$($Task.name)' references project '$taskProjectName', but no matching projects[].name exists."
    }

    $runtimeProjects = @($projects | Where-Object { $_.runtime -eq $Task.runtime })
    if ($runtimeProjects.Count -eq 1) {
        return $runtimeProjects[0]
    }

    if ($runtimeProjects.Count -eq 0) {
        throw "Workspace task '$($Task.name)' has no matching project for runtime '$($Task.runtime)'. Set tasks[].project before executing validation."
    }

    throw "Workspace task '$($Task.name)' matches multiple projects for runtime '$($Task.runtime)'. Set tasks[].project before executing validation."
}

function Resolve-WorkspaceRemoteProjectPath {
    param([object]$Project)

    if (-not $Project.path) {
        throw "Workspace project '$($Project.name)' is missing projects[].path."
    }

    $projectPath = ([string]$Project.path).Replace("\", "/").Trim()
    if ([string]::IsNullOrWhiteSpace($projectPath)) {
        throw "Workspace project '$($Project.name)' has an empty projects[].path."
    }

    if ($projectPath.StartsWith("/") -or $projectPath -match '^[A-Za-z]:') {
        throw "Workspace project '$($Project.name)' must use a relative projects[].path before remote validation execution."
    }

    $segments = @($projectPath -split "/" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($segments -contains "." -or $segments -contains "..") {
        throw "Workspace project '$($Project.name)' path cannot contain '.' or '..' segments before remote validation execution."
    }

    return "/home/adp/workspace/$($segments -join '/')"
}

function Resolve-WorkspaceLocalProjectPath {
    param(
        [object]$Project,
        [string]$ManifestPath
    )

    if (-not $Project.path) {
        throw "Workspace project '$($Project.name)' is missing projects[].path."
    }

    $projectPath = ([string]$Project.path).Replace("\", "/").Trim()
    if ([string]::IsNullOrWhiteSpace($projectPath)) {
        throw "Workspace project '$($Project.name)' has an empty projects[].path."
    }

    # If absolute, use as-is
    if ([System.IO.Path]::IsPathRooted($projectPath)) {
        return $projectPath
    }

    # Resolve relative to manifest directory
    $manifestDir = if ($ManifestPath) {
        (Split-Path -Parent ([System.IO.Path]::GetFullPath($ManifestPath)))
    } else {
        (Get-Location).Path
    }

    $localPath = Join-Path $manifestDir $projectPath
    return [System.IO.Path]::GetFullPath($localPath)
}


function Resolve-ProjectWorkspacePath {
    param([object]$Project)

    if (-not $Project.path) {
        return $null
    }

    if ([System.IO.Path]::IsPathRooted([string]$Project.path)) {
        return [string]$Project.path
    }

    if ($Project.runtime -and (Test-RuntimeExists $Project.runtime)) {
        $runtime = Get-RuntimeConfig $Project.runtime
        $workspaceRoot = Resolve-Path "workspace_root"
        return (Join-Path (Join-Path $workspaceRoot $runtime.workspace) $Project.path)
    }

    return [System.IO.Path]::GetFullPath($Project.path)
}

function Get-WorkspaceProjectCreateEntries {
    param([object]$Manifest)

    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($project in (Get-WorkspaceArray $Manifest.projects)) {
        $projectName = if ($project.name) { [string]$project.name } else { "(unnamed)" }
        $runtimeName = if ($project.runtime) { [string]$project.runtime } else { "not configured" }
        $localPath = $null
        $fullPath = $null
        $exists = $false
        $isDirectory = $false
        $valid = $true
        $status = "planned"
        $detail = ""
        $level = "WARN"

        try {
            $localPath = Resolve-ProjectWorkspacePath -Project $project
            if ([string]::IsNullOrWhiteSpace($localPath)) {
                throw "projects[].path missing"
            }

            $fullPath = [System.IO.Path]::GetFullPath($localPath)
            $root = [System.IO.Path]::GetPathRoot($fullPath)
            $trimmedFull = $fullPath.TrimEnd('\', '/')
            $trimmedRoot = if ($root) { $root.TrimEnd('\', '/') } else { "" }
            if (-not [string]::IsNullOrWhiteSpace($trimmedRoot) -and $trimmedFull -eq $trimmedRoot) {
                throw "refusing to create a filesystem root"
            }

            $exists = Test-Path -LiteralPath $fullPath
            if ($exists) {
                $isDirectory = Test-Path -LiteralPath $fullPath -PathType Container
                if (-not $isDirectory) {
                    throw "path exists and is not a directory"
                }

                $level = "OK"
                $status = "exists"
                $detail = "directory already exists"
            } else {
                $level = "WARN"
                $status = "missing"
                $detail = "directory can be created"
            }
        } catch {
            $valid = $false
            $level = "FAIL"
            $status = "blocked"
            $detail = "$_"
        }

        $entries.Add([pscustomobject]@{
                ProjectName = $projectName
                RuntimeName = $runtimeName
                LocalPath   = $localPath
                FullPath    = $fullPath
                Exists      = $exists
                IsDirectory = $isDirectory
                Valid       = $valid
                Level       = $level
                Status      = $status
                Detail      = $detail
            }) | Out-Null
    }

    return @($entries)
}

function Write-WorkspaceCreate {
    param(
        [object]$Manifest,
        [string]$ManifestPath,
        [switch]$PlanOnly
    )

    Write-UIHost -English "Workspace create: $($Manifest.name)" -Chinese "工作区创建: $($Manifest.name)" -ForegroundColor Cyan
    if ($PlanOnly) {
        Write-UIHost -English "Plan only: no directories will be created, no projects cloned, no sync sessions changed, no runtimes started, no SSH connections opened, no snapshots created, no validation or evaluation commands run, and no Git commands run." -Chinese "仅计划：不会创建任何目录、不会 clone 任何项目、不会更改任何同步会话、不会启动任何运行时、不会打开 SSH 连接、不会创建快照、不会运行验证或评估命令、不会运行 Git 命令。" -ForegroundColor DarkGray
    } else {
        Write-UIHost -English "Create only: local project directories may be created. No projects will be cloned, no sync sessions changed, no runtimes started, no SSH connections opened, no snapshots created, no validation or evaluation commands run, and no Git commands run." -Chinese "仅创建：可能会创建本地项目目录。不会 clone 任何项目、不会更改同步会话、不会启动运行时、不会打开 SSH 连接、不会创建快照、不会运行验证或评估命令、不会运行 Git 命令。" -ForegroundColor DarkGray
    }

    $entries = Get-WorkspaceProjectCreateEntries -Manifest $Manifest
    $invalidEntries = @($entries | Where-Object { -not $_.Valid })
    $missingEntries = @($entries | Where-Object { $_.Valid -and -not $_.Exists })
    $existingEntries = @($entries | Where-Object { $_.Valid -and $_.Exists })

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Project directories:" -Chinese "项目目录:" -ForegroundColor Yellow
    if ($entries.Count -eq 0) {
        Write-WorkspaceCheck -Level "WARN" -Name "projects" -Detail "(none configured)"
    }

    foreach ($entry in $entries) {
        Write-WorkspaceCheck -Level $entry.Level -Name $entry.ProjectName -Detail "(runtime: $($entry.RuntimeName); status: $($entry.Status); path: $(if ($entry.FullPath) { $entry.FullPath } else { 'not available' }); detail: $($entry.Detail))"
        if ($entry.Valid) {
            Write-UIHost -English "       open:      adpos workspace open $($entry.ProjectName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       打开:      adpos workspace open $($entry.ProjectName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
            Write-UIHost -English "       lifecycle: adpos workspace project $($entry.ProjectName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "       生命周期:  adpos workspace project $($entry.ProjectName) -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
        }
    }

    if ($invalidEntries.Count -gt 0) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Create blocked: fix invalid project paths before creating workspace directories. No directories were created." -Chinese "创建被阻止：在创建工作区目录之前，请先修复无效的项目路径。未创建任何目录。" -ForegroundColor Red
        exit 1
    }

    if ($PlanOnly) {
        Write-UIHost -English "" -Chinese ""
        Write-UIHost -English "Plan summary: $($missingEntries.Count) directories would be created; $($existingEntries.Count) already exist." -Chinese "计划摘要：将创建 $($missingEntries.Count) 个目录；$($existingEntries.Count) 个已存在。" -ForegroundColor Yellow
        return
    }

    $created = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $missingEntries) {
        New-Item -ItemType Directory -Path $entry.FullPath -Force | Out-Null
        $created.Add($entry.FullPath) | Out-Null
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Create summary:" -Chinese "创建摘要:" -ForegroundColor Yellow
    Write-UIHost -English "  created: $(if ($created.Count -gt 0) { $created.Count } else { 0 })" -Chinese "  已创建: $(if ($created.Count -gt 0) { $created.Count } else { 0 })" -ForegroundColor DarkGray
    foreach ($path in $created) {
        Write-UIHost -English "    $path" -Chinese "    $path" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  already existed: $($existingEntries.Count)" -Chinese "  已存在: $($existingEntries.Count)" -ForegroundColor DarkGray
    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Next:" -Chinese "下一步:" -ForegroundColor Yellow
    Write-UIHost -English "  adpos workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adpos workspace status -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -Chinese "  adpos workspace dashboard -ManifestPath $(Quote-WorkspacePowerShellArgument $ManifestPath)" -ForegroundColor DarkGray
}
