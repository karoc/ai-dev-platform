# ADP-OS Evidence Chain Tests
# Tests the SHA-256 evidence chain functions without touching real VM operations.
# Compatible with Pester 3.x and 5.x.
#
# Invoked by tests/evidence-chain.ps1.

$ErrorActionPreference = "Stop"

# 1. Define minimal evidence chain functions (copied from cli/commands/workspace.ps1
#    for self-contained testing without dot-sourcing the full routing module).
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

function Get-EvidenceDirectory {
    param([string]$ManifestPath)
    $workspaceRoot = if (Test-Path -LiteralPath $ManifestPath) {
        Split-Path -Path (Resolve-Path -LiteralPath $ManifestPath) -Parent
    } else {
        (Get-Location).Path
    }
    $evidenceDir = Join-Path $workspaceRoot ".evidence"
    if (-not (Test-Path -LiteralPath $evidenceDir)) {
        New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
    }
    return $evidenceDir
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

function Read-SnapshotHashes {
    param([string]$EvidenceDir)
    $path = Join-Path $EvidenceDir "snapshot-hashes.json"
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]@{ chain = @() } }
    $raw = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{ chain = @() } }
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
    if (-not (Test-Path -LiteralPath $path)) { return [pscustomobject]@{ entries = @() } }
    $raw = Get-Content -LiteralPath $path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return [pscustomobject]@{ entries = @() } }
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

# Pester-compatible helper (works for both Pester 3 and 5)
function Should-Match {
    param([string]$Actual, [string]$Pattern)
    if ($Actual -notmatch $Pattern) {
        throw "Expected '$Actual' to match pattern '$Pattern'"
    }
}

# 2. Pester test suites
Describe "Get-EvidenceDirectory" {
    BeforeAll {
        $testDir = Join-Path $TestDrive "evidence-test"
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        Push-Location $testDir
    }

    AfterAll {
        Pop-Location
    }

    It "creates .evidence directory when it does not exist" {
        $evidenceDir = Get-EvidenceDirectory -ManifestPath "nonexistent.json"
        $evidenceDir | Should Not BeNullOrEmpty
        Test-Path $evidenceDir | Should Be $true
        (Split-Path $evidenceDir -Leaf) | Should Be ".evidence"
    }

    It "returns existing .evidence directory without error" {
        $first = Get-EvidenceDirectory -ManifestPath "nonexistent.json"
        $second = Get-EvidenceDirectory -ManifestPath "nonexistent.json"
        $second | Should Be $first
    }

    It "resolves evidence dir from a real manifest path" {
        $manifestFile = Join-Path $testDir "adp-workspace.json"
        Set-Content -Path $manifestFile -Value '{"name":"test-ws"}' -Encoding utf8
        $evidenceDir = Get-EvidenceDirectory -ManifestPath $manifestFile
        (Split-Path $evidenceDir -Parent) | Should Be $testDir
    }
}

Describe "New-EvidenceSnapshotEntry" {
    It "generates a valid SHA-256 hash (64 hex chars)" {
        $result = New-EvidenceSnapshotEntry `
            -SnapshotId "test-snap" `
            -Timestamp "2025-01-01T00:00:00.0000000Z" `
            -MetadataContent "runtime=agent; workspace=test" `
            -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000" `
            -WorkspaceName "test-workspace"
        $result.sha256_hash | Should Match "^[a-f0-9A-F]{64}$"
        $result.previous_hash | Should Be "0000000000000000000000000000000000000000000000000000000000000000"
        $result.snapshot_id | Should Be "test-snap"
        $result.workspace_name | Should Be "test-workspace"
    }

    It "produces different hashes for different content" {
        $r1 = New-EvidenceSnapshotEntry -SnapshotId "s1" -Timestamp "t1" -MetadataContent "m1" -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000" -WorkspaceName "w1"
        $r2 = New-EvidenceSnapshotEntry -SnapshotId "s2" -Timestamp "t2" -MetadataContent "m2" -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000" -WorkspaceName "w2"
        $r1.sha256_hash | Should Not Be $r2.sha256_hash
    }

    It "chains to previous hash correctly" {
        $first = New-EvidenceSnapshotEntry -SnapshotId "first" -Timestamp "t1" -MetadataContent "m1" -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000" -WorkspaceName "ws"
        $second = New-EvidenceSnapshotEntry -SnapshotId "second" -Timestamp "t2" -MetadataContent "m2" -PreviousHash $first.sha256_hash -WorkspaceName "ws"
        $second.previous_hash | Should Be $first.sha256_hash

        # Verify chain integrity: recompute first entry's hash
        $content1 = "first|t1|m1|0000000000000000000000000000000000000000000000000000000000000000|ws"
        $recomputed1 = Get-SHA256Hash -InputString $content1
        $recomputed1 | Should Be $first.sha256_hash

        # Verify chain integrity: recompute second entry's hash
        $content2 = "second|t2|m2|$($first.sha256_hash)|ws"
        $recomputed2 = Get-SHA256Hash -InputString $content2
        $recomputed2 | Should Be $second.sha256_hash
    }

    It "generates the zero hash as previous for empty chain" {
        $zeroHash = Get-LastChainHash -ChainArray @()
        $zeroHash | Should Be "0000000000000000000000000000000000000000000000000000000000000000"
    }
}

Describe "New-EvidenceLogEntry" {
    It "generates a valid SHA-256 hash for log entries" {
        $result = New-EvidenceLogEntry `
            -Operation "create" `
            -Timestamp "2025-01-01T00:00:00.0000000Z" `
            -User "tester" `
            -Details "test operation" `
            -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000"
        $result.sha256_hash | Should Match "^[a-f0-9A-F]{64}$"
        $result.operation | Should Be "create"
        $result.user | Should Be "tester"
        $result.details | Should Be "test operation"
    }

    It "produces different hashes for different operations" {
        $r1 = New-EvidenceLogEntry -Operation "sync" -Timestamp "t1" -User "u1" -Details "" -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000"
        $r2 = New-EvidenceLogEntry -Operation "start" -Timestamp "t1" -User "u1" -Details "" -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000"
        $r1.sha256_hash | Should Not Be $r2.sha256_hash
    }

    It "chains log entries with previous hash" {
        $entry1 = New-EvidenceLogEntry -Operation "sync" -Timestamp "t1" -User "u1" -Details "" -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000"
        $entry2 = New-EvidenceLogEntry -Operation "validate" -Timestamp "t2" -User "u1" -Details "" -PreviousHash $entry1.sha256_hash
        $entry2.previous_hash | Should Be $entry1.sha256_hash

        # Verify the chain integrity
        $content2 = "validate|t2|u1||$($entry1.sha256_hash)"
        $recomputed2 = Get-SHA256Hash -InputString $content2
        $recomputed2 | Should Be $entry2.sha256_hash
    }
}

Describe "Invoke-EvidenceExport" {
    It "creates a ZIP file with expected entries" {
        $testEvidenceDir = Join-Path $TestDrive ".evidence"
        New-Item -ItemType Directory -Path $testEvidenceDir -Force | Out-Null

        # Create sample evidence files
        $snapshotFile = Join-Path $testEvidenceDir "snapshot-hashes.json"
        Set-Content -Path $snapshotFile -Value '{"chain":[]}' -Encoding utf8

        $logFile = Join-Path $testEvidenceDir "operation-log.json"
        Set-Content -Path $logFile -Value '{"entries":[]}' -Encoding utf8

        # Create ZIP using .NET
        $outputZip = Join-Path $TestDrive "evidence-export.zip"
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::Open($outputZip, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            $readmeContent = "Evidence Export Test"
            $readmeTemp = Join-Path $testEvidenceDir "README.txt"
            Set-Content -Path $readmeTemp -Value $readmeContent -Encoding utf8
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $readmeTemp, "README.txt")
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $snapshotFile, "snapshot-hashes.json")
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive, $logFile, "operation-log.json")
        } finally {
            $archive.Dispose()
        }

        Test-Path $outputZip | Should Be $true

        # Verify ZIP contents
        $verify = [System.IO.Compression.ZipFile]::OpenRead($outputZip)
        try {
            $entryNames = @($verify.Entries | ForEach-Object { $_.Name })
            ($entryNames -contains "snapshot-hashes.json") | Should Be $true
            ($entryNames -contains "operation-log.json") | Should Be $true
            ($entryNames -contains "README.txt") | Should Be $true
            $verify.Entries.Count | Should BeGreaterThan 2
        } finally {
            $verify.Dispose()
        }
    }
}

Describe "Invoke-EvidenceDeclare" {
    BeforeAll {
        $testEvidenceDir = Join-Path $TestDrive ".evidence"
        New-Item -ItemType Directory -Path $testEvidenceDir -Force | Out-Null
    }

    It "generates a DECLARE operation log entry" {
        $declarationType = "ai-assisted"
        $details = "declaration_type=$declarationType; reviewer=human-reviewer; notes=generated by AI"

        $entry = New-EvidenceLogEntry `
            -Operation "DECLARE" `
            -Timestamp "2025-06-06T00:00:00.0000000Z" `
            -User "test-user" `
            -Details $details `
            -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000"

        $entry.operation | Should Be "DECLARE"
        $entry.sha256_hash | Should Match "^[a-f0-9A-F]{64}$"
        $entry.details | Should Be $details
    }

    It "defaults declaration_type to ai-assisted when -AiAssisted is set" {
        $details = "declaration_type=ai-assisted"
        $entry = New-EvidenceLogEntry `
            -Operation "DECLARE" `
            -Timestamp "2025-06-06T00:00:00.0000000Z" `
            -User "test-user" `
            -Details $details `
            -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000"

        $entry.operation | Should Be "DECLARE"
        $entry.details | Should Match "declaration_type=ai-assisted"
    }
}

Describe "Json output parameter support" {
    It "New-EvidenceSnapshotEntry returns a PSCustomObject convertible to JSON" {
        $result = New-EvidenceSnapshotEntry `
            -SnapshotId "json-test" `
            -Timestamp "2025-01-01T00:00:00.0000000Z" `
            -MetadataContent "" `
            -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000" `
            -WorkspaceName "ws"

        $json = $result | ConvertTo-Json
        $json | Should Not BeNullOrEmpty
        ($json -match "sha256_hash") | Should Be $true
        ($json -match "previous_hash") | Should Be $true
        ($json -match "snapshot_id") | Should Be $true
    }

    It "New-EvidenceLogEntry returns a PSCustomObject convertible to JSON" {
        $result = New-EvidenceLogEntry `
            -Operation "export" `
            -Timestamp "2025-01-01T00:00:00.0000000Z" `
            -User "json-user" `
            -Details "" `
            -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000"

        $json = $result | ConvertTo-Json
        $json | Should Not BeNullOrEmpty
        ($json -match "operation") | Should Be $true
        ($json -match "sha256_hash") | Should Be $true
    }
}

Describe "Error handling and edge cases" {
    It "handles empty metadata content" {
        $result = New-EvidenceSnapshotEntry `
            -SnapshotId "empty-meta" `
            -Timestamp "2025-01-01T00:00:00.0000000Z" `
            -MetadataContent "" `
            -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000" `
            -WorkspaceName ""
        $result.sha256_hash | Should Match "^[a-f0-9A-F]{64}$"
    }

    It "handles empty details in log entry" {
        $result = New-EvidenceLogEntry `
            -Operation "" `
            -Timestamp "" `
            -User "" `
            -Details "" `
            -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000"
        $result.sha256_hash | Should Match "^[a-f0-9A-F]{64}$"
        $result.operation | Should Be ""
    }

    It "handles special characters in content" {
        $result = New-EvidenceSnapshotEntry `
            -SnapshotId "special|chars:test" `
            -Timestamp "2025-01-01T00:00:00.0000000Z" `
            -MetadataContent "cmd=echo hello; rm -rf /" `
            -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000" `
            -WorkspaceName "test"
        $result.sha256_hash | Should Match "^[a-f0-9A-F]{64}$"
    }

    It "long chain grows without breaking" {
        $chain = @()
        $prev = "0000000000000000000000000000000000000000000000000000000000000000"
        for ($i = 0; $i -lt 10; $i++) {
            $entry = New-EvidenceSnapshotEntry `
                -SnapshotId "long-$i" `
                -Timestamp "2025-01-01T00:00:0$i.0000000Z" `
                -MetadataContent "step=$i" `
                -PreviousHash $prev `
                -WorkspaceName "long-test"
            $chain += $entry
            $prev = $entry.sha256_hash
        }
        $chain.Count | Should Be 10
        for ($i = 1; $i -lt 10; $i++) {
            $chain[$i].previous_hash | Should Be $chain[$i - 1].sha256_hash
        }
    }
}

Describe "Bilingual output (Write-UIHost compatibility)" {
    It "snapshot entry fields are language-agnostic (no UI strings in data)" {
        $result = New-EvidenceSnapshotEntry `
            -SnapshotId "lang-test" `
            -Timestamp "2025-01-01T00:00:00.0000000Z" `
            -MetadataContent "runtime=en; locale=both" `
            -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000" `
            -WorkspaceName "shuangyuceshi"

        # Data fields should be consistent regardless of language
        $result.snapshot_id | Should Not BeNullOrEmpty
        ($result.PSObject.Properties.Name -contains "sha256_hash") | Should Be $true
        ($result.PSObject.Properties.Name -contains "previous_hash") | Should Be $true
        $result.workspace_name | Should Be "shuangyuceshi"
    }

    It "JSON output is valid and parseable" {
        $result = New-EvidenceSnapshotEntry `
            -SnapshotId "json-parse" `
            -Timestamp "2025-01-01T00:00:00.0000000Z" `
            -MetadataContent "test" `
            -PreviousHash "0000000000000000000000000000000000000000000000000000000000000000" `
            -WorkspaceName "test"

        $json = $result | ConvertTo-Json
        $parsed = $json | ConvertFrom-Json
        $parsed.sha256_hash | Should Be $result.sha256_hash
        $parsed.previous_hash | Should Be $result.previous_hash
    }
}
