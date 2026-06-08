# ============================================================
# Evidence Chain v1 — Snapshot 签名 + 操作日志链 + 证据包导出 + AI 声明
# ============================================================

function Get-EvidenceDirectory {
    param([string]$ManifestPath)

    $workspaceRoot = if (Test-Path -LiteralPath $ManifestPath) {
        $resolvedManifest = Microsoft.PowerShell.Management\Resolve-Path -LiteralPath $ManifestPath
        Split-Path -Path $resolvedManifest.ProviderPath -Parent
    } else {
        (Get-Location).ProviderPath
    }

    $evidenceDir = Join-Path $workspaceRoot ".evidence"
    if (-not (Test-Path -LiteralPath $evidenceDir)) {
        New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
        Write-Verbose "Evidence directory created: $evidenceDir"
    }

    return $evidenceDir
}

function Get-EvidenceWorkspaceName {
    param([string]$ManifestPath)

    if (Test-Path -LiteralPath $ManifestPath) {
        try {
            $manifest = Read-WorkspaceManifest -Path $ManifestPath
            if ($manifest.PSObject.Properties.Name -contains "name" -and -not [string]::IsNullOrWhiteSpace([string]$manifest.name)) {
                return [string]$manifest.name
            }
        } catch {
            Write-Verbose "Could not read workspace name from manifest: $_"
        }
    }

    return Split-Path -Path (Get-Location).Path -Leaf
}

function Get-SHA256Hash {
    param([string]$InputString)

    $tmpFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -LiteralPath $tmpFile -Value $InputString -Encoding utf8 -NoNewline
        $hash = (Get-FileHash -LiteralPath $tmpFile -Algorithm SHA256).Hash
        return $hash
    } finally {
        Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    }
}

function Read-SnapshotHashes {
    param([string]$EvidenceDir)

    $path = Join-Path $EvidenceDir "snapshot-hashes.json"
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{ chain = @() }
    }

    $raw = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ chain = @() }
    }

    $data = $raw | ConvertFrom-Json
    if (-not ($data.PSObject.Properties.Name -contains "chain")) {
        $data | Add-Member -NotePropertyName "chain" -NotePropertyValue @() -Force
    }
    return $data
}

function Write-SnapshotHashes {
    param([string]$EvidenceDir, [object]$Data)

    $path = Join-Path $EvidenceDir "snapshot-hashes.json"
    $Data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
}

function Read-OperationLog {
    param([string]$EvidenceDir)

    $path = Join-Path $EvidenceDir "operation-log.json"
    if (-not (Test-Path -LiteralPath $path)) {
        return [pscustomobject]@{ entries = @() }
    }

    $raw = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{ entries = @() }
    }

    $data = $raw | ConvertFrom-Json
    if (-not ($data.PSObject.Properties.Name -contains "entries")) {
        $data | Add-Member -NotePropertyName "entries" -NotePropertyValue @() -Force
    }
    return $data
}

function Write-OperationLogFile {
    param([string]$EvidenceDir, [object]$Data)

    $path = Join-Path $EvidenceDir "operation-log.json"
    $Data | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding utf8
}

function Get-LastChainHash {
    param([object]$ChainArray)

    if ($ChainArray.Count -eq 0) {
        return "0000000000000000000000000000000000000000000000000000000000000000"
    }

    $last = $ChainArray[$ChainArray.Count - 1]
    if ($last.PSObject.Properties.Name -contains "sha256_hash") {
        return [string]$last.sha256_hash
    }

    return "0000000000000000000000000000000000000000000000000000000000000000"
}

function Get-VMSnapshotMetadata {
    param([object]$Manifest)

    $metadata = [System.Text.StringBuilder]::new()
    $tasks = Get-WorkspaceArray $Manifest.tasks
    $snapshotNames = [System.Collections.Generic.List[string]]::new()
    $seenRuntimes = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($task in $tasks) {
        if ($task.PSObject.Properties.Name -contains "runtime" -and -not [string]::IsNullOrWhiteSpace([string]$task.runtime)) {
            $runtime = [string]$task.runtime
            if ($task.PSObject.Properties.Name -contains "snapshot" -and -not [string]::IsNullOrWhiteSpace([string]$task.snapshot)) {
                [void]$snapshotNames.Add("$runtime/$($task.snapshot)")
            }
            if ($seenRuntimes.Add($runtime)) {
                [void]$metadata.AppendLine("runtime=$runtime")
            }
        }
    }

    $milestones = Get-WorkspaceMilestones -Manifest $Manifest
    foreach ($milestone in $milestones) {
        $msSnapshot = Get-WorkspaceMilestoneSnapshotName -Milestone $milestone
        if ($milestone.PSObject.Properties.Name -contains "name") {
            [void]$snapshotNames.Add("milestone/$($milestone.name)=$msSnapshot")
        }
    }

    if ($snapshotNames.Count -gt 0) {
        [void]$metadata.AppendLine("snapshots=$($snapshotNames -join '; ')")
    }

    if ($Manifest.PSObject.Properties.Name -contains "name") {
        [void]$metadata.AppendLine("workspace=$($Manifest.name)")
    }

    # Try to read actual VMware snapshot details for runtimes listed in manifest
    try {
        $vmStore = Resolve-Path "vm_store"
        foreach ($runtime in $seenRuntimes) {
            $snapshotResult = Get-SnapshotList -Name $runtime
            if ($snapshotResult.Success) {
                $vmSnapshots = @($snapshotResult.Data)
                if ($vmSnapshots.Count -gt 0) {
                    [void]$metadata.AppendLine("vm-$runtime-snapshots=$($vmSnapshots -join ',')")
                }
            }
        }
    } catch {
        [void]$metadata.AppendLine("vmware-metadata-status=unavailable ($($_.Exception.Message))")
    }

    return $metadata.ToString()
}

function New-EvidenceSnapshotEntry {
    param(
        [string]$SnapshotId,
        [string]$Timestamp,
        [string]$MetadataContent,
        [string]$PreviousHash,
        [string]$WorkspaceName
    )

    $contentToHash = "$SnapshotId|$Timestamp|$MetadataContent|$PreviousHash|$WorkspaceName"
    $hash = Get-SHA256Hash -InputString $contentToHash

    return [pscustomobject]@{
        snapshot_id    = $SnapshotId
        timestamp      = $Timestamp
        workspace_name = $WorkspaceName
        sha256_hash    = $hash
        previous_hash  = $PreviousHash
    }
}

function Invoke-EvidenceSnapshot {
    param(
        [object]$Manifest,
        [string]$ManifestPath,
        [switch]$JsonOutput
    )

    $evidenceDir = Get-EvidenceDirectory -ManifestPath $ManifestPath
    $workspaceName = Get-EvidenceWorkspaceName -ManifestPath $ManifestPath
    $snapshotData = Read-SnapshotHashes -EvidenceDir $evidenceDir
    $chain = [System.Collections.Generic.List[object]]::new()
    foreach ($item in (Get-WorkspaceArray $snapshotData.chain)) {
        $chain.Add($item) | Out-Null
    }

    $previousHash = Get-LastChainHash -ChainArray $chain
    $timestamp = (Get-Date).ToUniversalTime().ToString("o")
    $snapshotId = "snap-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
    $metadataContent = Get-VMSnapshotMetadata -Manifest $Manifest

    $entry = New-EvidenceSnapshotEntry `
        -SnapshotId $snapshotId `
        -Timestamp $timestamp `
        -MetadataContent $metadataContent `
        -PreviousHash $previousHash `
        -WorkspaceName $workspaceName

    $chain.Add($entry) | Out-Null
    $snapshotData.chain = @($chain.ToArray())
    Write-SnapshotHashes -EvidenceDir $evidenceDir -Data $snapshotData

    if ($JsonOutput) {
        $entry | ConvertTo-Json -Depth 8 | Write-Host
        return
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Evidence Snapshot Signature" -Chinese "证据快照签名" -ForegroundColor Cyan
    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "  Snapshot ID : $snapshotId" -Chinese "  快照 ID    : $snapshotId" -ForegroundColor Green
    Write-UIHost -English "  SHA-256     : $($entry.sha256_hash)" -Chinese "  SHA-256     : $($entry.sha256_hash)" -ForegroundColor Green
    Write-UIHost -English "  Previous    : $($entry.previous_hash.Substring(0,16))..." -Chinese "  前驱哈希    : $($entry.previous_hash.Substring(0,16))..." -ForegroundColor DarkGray
    Write-UIHost -English "  Chain length: $($chain.Count)" -Chinese "  链长度      : $($chain.Count)" -ForegroundColor DarkGray
    Write-UIHost -English "  Evidence dir: $evidenceDir" -Chinese "  证据目录    : $evidenceDir" -ForegroundColor DarkGray
    Write-UIHost -English "  File        : snapshot-hashes.json" -Chinese "  文件        : snapshot-hashes.json" -ForegroundColor DarkGray
    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "  Evidence chain is append-only. Each new entry links to the previous hash." -Chinese "  证据链仅追加。每个新条目都链接到前一个哈希值。" -ForegroundColor DarkGray
}

function New-EvidenceLogEntry {
    param(
        [string]$Operation,
        [string]$Timestamp,
        [string]$User,
        [string]$Details,
        [string]$PreviousHash
    )

    $contentToHash = "$Operation|$Timestamp|$User|$Details|$PreviousHash"
    $hash = Get-SHA256Hash -InputString $contentToHash

    return [pscustomobject]@{
        operation     = $Operation
        timestamp     = $Timestamp
        user          = $User
        details       = $Details
        sha256_hash   = $hash
        previous_hash = $PreviousHash
    }
}

function Invoke-EvidenceLog {
    param(
        [string]$ManifestPath,
        [string]$OperationName,
        [string]$LogDetails,
        [switch]$JsonOutput
    )

    $evidenceDir = Get-EvidenceDirectory -ManifestPath $ManifestPath
    $logData = Read-OperationLog -EvidenceDir $evidenceDir
    $entries = [System.Collections.Generic.List[object]]::new()
    foreach ($item in (Get-WorkspaceArray $logData.entries)) {
        $entries.Add($item) | Out-Null
    }

    $previousHash = Get-LastChainHash -ChainArray $entries
    $timestamp = (Get-Date).ToUniversalTime().ToString("o")
    $user = if ($env:USERNAME) { $env:USERNAME } else { (whoami) }
    $details = if ($LogDetails) { $LogDetails } else { "" }

    $entry = New-EvidenceLogEntry `
        -Operation $OperationName `
        -Timestamp $timestamp `
        -User $user `
        -Details $details `
        -PreviousHash $previousHash

    $entries.Add($entry) | Out-Null
    $logData.entries = @($entries.ToArray())
    Write-OperationLogFile -EvidenceDir $evidenceDir -Data $logData

    if ($JsonOutput) {
        $entry | ConvertTo-Json -Depth 8 | Write-Host
        return
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Operation Log Entry" -Chinese "操作日志条目" -ForegroundColor Cyan
    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "  Operation   : $OperationName" -Chinese "  操作        : $OperationName" -ForegroundColor Green
    Write-UIHost -English "  SHA-256     : $($entry.sha256_hash)" -Chinese "  SHA-256     : $($entry.sha256_hash)" -ForegroundColor Green
    Write-UIHost -English "  Previous    : $($entry.previous_hash.Substring(0,16))..." -Chinese "  前驱哈希    : $($entry.previous_hash.Substring(0,16))..." -ForegroundColor DarkGray
    Write-UIHost -English "  User        : $user" -Chinese "  用户        : $user" -ForegroundColor DarkGray
    Write-UIHost -English "  Chain length: $($entries.Count)" -Chinese "  链长度      : $($entries.Count)" -ForegroundColor DarkGray
    Write-UIHost -English "  Evidence dir: $evidenceDir" -Chinese "  证据目录    : $evidenceDir" -ForegroundColor DarkGray
    Write-UIHost -English "  File        : operation-log.json" -Chinese "  文件        : operation-log.json" -ForegroundColor DarkGray
    if ($details) {
        Write-UIHost -English "  Details     : $details" -Chinese "  详情        : $details" -ForegroundColor DarkGray
    }
    Write-UIHost -English "" -Chinese ""
}

function Invoke-EvidenceExport {
    param(
        [string]$ManifestPath,
        [string]$ExportPathParam
    )

    $evidenceDir = Get-EvidenceDirectory -ManifestPath $ManifestPath
    $workspaceName = Get-EvidenceWorkspaceName -ManifestPath $ManifestPath

    # Determine output path
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
    $currentPath = (Get-Location).ProviderPath
    if ([string]::IsNullOrWhiteSpace($ExportPathParam)) {
        $outputZip = Join-Path $currentPath "evidence-export-$timestamp.zip"
    } else {
        $exportPath = if ([System.IO.Path]::IsPathRooted($ExportPathParam)) {
            $ExportPathParam
        } else {
            Join-Path $currentPath $ExportPathParam
        }
        $fullPath = [System.IO.Path]::GetFullPath($exportPath)
        if ($fullPath.EndsWith(".zip")) {
            $outputZip = $fullPath
        } else {
            $outputZip = Join-Path $fullPath "evidence-export-$timestamp.zip"
        }
    }

    # Ensure output directory exists
    $outDir = Split-Path -Path $outputZip -Parent
    if (-not [string]::IsNullOrWhiteSpace($outDir) -and -not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    # Collect files to include
    $filesToInclude = [System.Collections.Generic.List[hashtable]]::new()

    # snapshot-hashes.json
    $snapshotPath = Join-Path $evidenceDir "snapshot-hashes.json"
    if (Test-Path -LiteralPath $snapshotPath) {
        $filesToInclude.Add(@{ Source = $snapshotPath; EntryName = "snapshot-hashes.json" }) | Out-Null
    }

    # operation-log.json
    $logPath = Join-Path $evidenceDir "operation-log.json"
    if (Test-Path -LiteralPath $logPath) {
        $filesToInclude.Add(@{ Source = $logPath; EntryName = "operation-log.json" }) | Out-Null
    }

    # workspace-report.md (if exists)
    $workspaceRoot = Split-Path -Path $evidenceDir -Parent
    $reportPath = Join-Path $workspaceRoot "workspace-report.md"
    if (Test-Path -LiteralPath $reportPath) {
        $filesToInclude.Add(@{ Source = $reportPath; EntryName = "workspace-report.md" }) | Out-Null
    }

    # workspace manifest
    if (Test-Path -LiteralPath $ManifestPath) {
        $manifestAbs = Microsoft.PowerShell.Management\Resolve-Path -LiteralPath $ManifestPath
        $filesToInclude.Add(@{ Source = $manifestAbs.ProviderPath; EntryName = "adp-workspace.json" }) | Out-Null
    }

    # Generate README.txt
    $readmeContent = @"
Evidence Export — ADP-OS Workspace: $workspaceName
=====================================================
Exported at: $((Get-Date).ToUniversalTime().ToString("o"))

This ZIP contains the evidence chain for the ADP-OS workspace.
Each file serves as a tamper-evident record of workspace activity.

Files included:
--------------

1. snapshot-hashes.json
   Snapshot signature chain. Each entry captures the SHA-256 hash of
   VMware snapshot metadata at a point in time. Entries form a Merkle
   chain where each new signature links to the previous hash.

2. operation-log.json
   Operation log chain. Records workspace operations (create, sync,
   start, stop, validate, declare, etc.) with SHA-256 hashes forming
   an append-only, tamper-evident chain.

3. workspace-report.md (if present)
   Human-readable workspace report generated by 'adpos workspace report'.

4. adp-workspace.json
   The workspace manifest at the time of export.

Verification:
-------------
Each file uses a hash chain: every entry contains a 'sha256_hash'
and a 'previous_hash' that links to the previous entry. To verify
integrity, recompute the SHA-256 hash of each entry's content and
compare with the recorded value.

Evidence directory: .evidence/
"@

    $readmeTemp = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -LiteralPath $readmeTemp -Value $readmeContent -Encoding utf8

        # Create ZIP
        if (Test-Path -LiteralPath $outputZip) {
            Remove-Item -LiteralPath $outputZip -Force
        }

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::Open($outputZip, [System.IO.Compression.ZipArchiveMode]::Create)

        try {
            # Add README first
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                $archive, $readmeTemp, "README.txt"
            )

            # Add other files
            foreach ($file in $filesToInclude) {
                [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    $archive, $file.Source, $file.EntryName
                )
            }
        } finally {
            $archive.Dispose()
        }
    } finally {
        Remove-Item -LiteralPath $readmeTemp -Force -ErrorAction SilentlyContinue
    }

    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "Evidence Export Complete" -Chinese "证据导出完成" -ForegroundColor Cyan
    Write-UIHost -English "" -Chinese ""
    Write-UIHost -English "  Output      : $outputZip" -Chinese "  输出        : $outputZip" -ForegroundColor Green
    Write-UIHost -English "  Files       : $($filesToInclude.Count + 1)" -Chinese "  文件数      : $($filesToInclude.Count + 1)" -ForegroundColor DarkGray
    Write-UIHost -English "  Evidence dir: $evidenceDir" -Chinese "  证据目录    : $evidenceDir" -ForegroundColor DarkGray
    Write-UIHost -English "" -Chinese ""

    foreach ($file in $filesToInclude) {
        Write-UIHost -English "  - $($file.EntryName)" -Chinese "  - $($file.EntryName)" -ForegroundColor DarkGray
    }
    Write-UIHost -English "  - README.txt (auto-generated)" -Chinese "  - README.txt (自动生成)" -ForegroundColor DarkGray
    Write-UIHost -English "" -Chinese ""
}

function Invoke-EvidenceDeclare {
    param(
        [string]$ManifestPath,
        [switch]$AiAssisted,
        [string]$Reviewer,
        [string]$Notes,
        [switch]$JsonOutput
    )

    $declarationType = if ($AiAssisted) { "ai-assisted" } else { "human-only" }
    $details = "declaration_type=$declarationType"
    if ($Reviewer) {
        $details += "; reviewer=$Reviewer"
    }
    if ($Notes) {
        $details += "; notes=$Notes"
    }

    # Append as a DECLARE operation log entry
    Invoke-EvidenceLog `
        -ManifestPath $ManifestPath `
        -OperationName "DECLARE" `
        -LogDetails $details `
        -JsonOutput:$JsonOutput

    if (-not $JsonOutput) {
        Write-UIHost -English "  Declaration  : $declarationType" -Chinese "  声明类型      : $declarationType" -ForegroundColor Yellow
        if ($Reviewer) {
            Write-UIHost -English "  Reviewer      : $Reviewer" -Chinese "  审查者        : $Reviewer" -ForegroundColor DarkGray
        }
        if ($Notes) {
            Write-UIHost -English "  Notes         : $Notes" -Chinese "  备注          : $Notes" -ForegroundColor DarkGray
        }
        Write-UIHost -English "  This is a formal declaration recorded in the evidence chain." -Chinese "  这是一条记录在证据链中的正式声明。" -ForegroundColor DarkGray
    }
}

function Show-EvidenceUsage {
    Write-ErrorLog -Message "Usage: adpos workspace evidence -Snapshot | -Log | -Export [-Path <path>]" -Component "cli.workspace.evidence"
    Write-Host ""

    Write-UIHost -English "Evidence Chain Commands:" -Chinese "证据链命令:" -ForegroundColor Yellow
    Write-UIHost -English "  adpos workspace evidence -Snapshot                     Sign current snapshot metadata (SHA-256 chain)" -Chinese "  adpos workspace evidence -Snapshot                     签署当前快照元数据 (SHA-256 链)" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace evidence -Log -Operation <op> [-Details <text>]   Record an operation log entry (hash chain)" -Chinese "  adpos workspace evidence -Log -Operation <op> [-Details <text>]   记录操作日志条目 (哈希链)" -ForegroundColor DarkGray
    Write-UIHost -English "  adpos workspace evidence -Export [-Path <path>]        Export all evidence as ZIP" -Chinese "  adpos workspace evidence -Export [-Path <path>]        导出所有证据为 ZIP" -ForegroundColor DarkGray
    Write-Host ""
    Write-UIHost -English "AI Declaration:" -Chinese "AI 开发声明:" -ForegroundColor Yellow
    Write-UIHost -English "  adpos workspace declare -AiAssisted [-Reviewer <name>] [-Notes ""...""]   Declare AI-assisted development" -Chinese "  adpos workspace declare -AiAssisted [-Reviewer <name>] [-Notes ""...""]   声明 AI 辅助开发" -ForegroundColor DarkGray
    Write-Host ""
    Write-UIHost -English "Operations for -Log: create, sync, start, stop, validate, declare, snapshot, export" -Chinese "-Log 支持的操作: create, sync, start, stop, validate, declare, snapshot, export" -ForegroundColor DarkGray
    Write-UIHost -English "Evidence files are stored in <workspace_root>/.evidence/" -Chinese "证据文件存储在 <workspace_root>/.evidence/" -ForegroundColor DarkGray
}
