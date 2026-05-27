# ADP-OS Workspace Command
# Non-destructive workspace manifest helpers.

param(
    [string]$SubCommand,
    [string]$ManifestPath = "adp-workspace.json"
)

$ErrorActionPreference = "Stop"

function Show-WorkspaceUsage {
    Write-ErrorLog -Message "Usage: adp workspace <init|show|plan> [-ManifestPath <path>]" -Component "cli.workspace"
}

function Read-WorkspaceManifest {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Workspace manifest not found: $Path. Run: adp workspace init"
    }

    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "Workspace manifest is empty: $Path"
    }

    return $raw | ConvertFrom-Json
}

function Write-WorkspaceSummary {
    param([object]$Manifest)

    Write-Host "Workspace: $($Manifest.name)" -ForegroundColor Cyan
    if ($Manifest.description) {
        Write-Host "  $($Manifest.description)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Projects:" -ForegroundColor Yellow
    foreach ($project in @($Manifest.projects)) {
        $runtime = if ($project.runtime) { $project.runtime } else { "not configured" }
        $sync = if ($null -ne $project.sync) { $project.sync } else { "not configured" }
        Write-Host "  - $($project.name): $($project.path) -> $runtime (sync: $sync)" -ForegroundColor DarkGray
        foreach ($command in @($project.validation)) {
            Write-Host "      validate: $command" -ForegroundColor DarkGray
        }
    }

    if ($Manifest.tasks) {
        Write-Host ""
        Write-Host "Tasks:" -ForegroundColor Yellow
        foreach ($task in @($Manifest.tasks)) {
            $runtime = if ($task.runtime) { $task.runtime } else { "not configured" }
            $snapshot = if ($task.snapshot) { $task.snapshot } else { "not configured" }
            Write-Host "  - $($task.name): runtime=$runtime snapshot=$snapshot" -ForegroundColor DarkGray
            foreach ($command in @($task.validation)) {
                Write-Host "      validate: $command" -ForegroundColor DarkGray
            }
        }
    }
}

if (-not $SubCommand) {
    Show-WorkspaceUsage
    exit 1
}

switch ($SubCommand) {
    "init" {
        if (Test-Path -LiteralPath $ManifestPath) {
            Write-Host "Workspace manifest already exists: $ManifestPath" -ForegroundColor Yellow
            Write-Host "  No changes made." -ForegroundColor DarkGray
            return
        }

        $examplePath = Join-Path (Get-ProjectRoot) "configs\workspace.example.json"
        if (-not (Test-Path -LiteralPath $examplePath)) {
            throw "Workspace example missing: $examplePath"
        }

        Copy-Item -LiteralPath $examplePath -Destination $ManifestPath
        Write-Host "Workspace manifest created: $ManifestPath" -ForegroundColor Green
        Write-Host "  Edit project paths, runtimes, validation commands, and task snapshots before use." -ForegroundColor DarkGray
    }
    "show" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-WorkspaceSummary -Manifest $manifest
    }
    "plan" {
        $manifest = Read-WorkspaceManifest -Path $ManifestPath
        Write-Host "Plan only: no projects will be cloned, no sync sessions will be changed, and no snapshots will be created." -ForegroundColor Cyan
        Write-Host ""
        Write-WorkspaceSummary -Manifest $manifest
        Write-Host ""
        Write-Host "Suggested next steps:" -ForegroundColor Yellow
        foreach ($project in @($manifest.projects)) {
            if ($project.runtime) {
                Write-Host "  - Preview runtime: adp up $($project.runtime) -Plan" -ForegroundColor DarkGray
                if ($project.sync) {
                    Write-Host "  - Start sync when ready: adp sync start $($project.runtime)" -ForegroundColor DarkGray
                }
            }
        }
        foreach ($task in @($manifest.tasks)) {
            if ($task.runtime -and $task.snapshot) {
                Write-Host "  - Snapshot before task '$($task.name)': adp snapshot create $($task.runtime) $($task.snapshot)" -ForegroundColor DarkGray
            }
        }
    }
    default {
        Write-ErrorLog -Message "Unknown workspace command: $SubCommand. Valid: init, show, plan" -Component "cli.workspace"
        exit 1
    }
}
