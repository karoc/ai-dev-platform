# ADP-OS Health Check HTTP Server
# Starts a lightweight HTTP server exposing a /health endpoint
# for external monitoring to verify the ADP-OS platform is alive.
#
# Usage:
#   adpos serve                  Start on default port 9080 (localhost only)
#   adpos serve -Port 8080       Custom port
#   adpos serve -Public          Listen on all interfaces (requires admin or URL reservation)

param(
    [int]$Port = 9080,

    [switch]$Public,

    [switch]$Json
)

$ErrorActionPreference = "Stop"

# Merge -Json flag from both local param and global (set in adp.ps1)
if ($Json -or $global:ADPOutputJson) {
    $Json = $true
}

. (Join-Path (Get-ProjectRoot) "adapters\windows\mutagen\mutagen.ps1")
. (Join-Path (Get-ProjectRoot) "runtimes\vmware\vm-factory.ps1")

$script:startTime = Get-Date

function Get-ServeVMStatus {
    param([string]$RuntimeName)

    $statusResult = Get-VMStatus -Name $RuntimeName
    $vmStatus = if ($statusResult.Success) { $statusResult.Data } else { "unknown" }

    if ($vmStatus -eq "not-created" -or $vmStatus -eq "unknown") {
        return [pscustomobject]@{
            Runtime = $RuntimeName
            Status  = if ($vmStatus -eq "not-created") { "not-created" } else { "unknown" }
            Ip      = ""
        }
    }

    if ($vmStatus -eq "running") {
        $ip = ""
        try {
            $ipResult = Get-VMIP -Name $RuntimeName
            if ($ipResult.Success) { $ip = $ipResult.Data }
        } catch { $ip = "" }
        return [pscustomobject]@{
            Runtime = $RuntimeName
            Status  = "running"
            Ip      = if ($ip) { $ip } else { "" }
        }
    }

    return [pscustomobject]@{
        Runtime = $RuntimeName
        Status  = "stopped"
        Ip      = ""
    }
}

function Get-ServeSyncStatus {
    param([string]$RuntimeName)

    $syncName = "adp-$RuntimeName"
    try {
        $session = Get-SyncSessionInfo -SessionName $syncName -ExpectedLocalPath "" -ExpectedRemoteUrl ""
        return [pscustomobject]@{
            Runtime = $RuntimeName
            Health  = $session.Health
            Detail  = $session.Detail
        }
    } catch {
        return [pscustomobject]@{
            Runtime = $RuntimeName
            Health  = "not-started"
            Detail  = "Sync session not found"
        }
    }
}

function Get-HealthReport {
    $runtimes = Get-AllRuntimeNames
    $vmStatuses = @()
    $syncStatuses = @()
    $allHealthy = $true
    $anyRunning = $false
    $anyCreated = $false

    foreach ($rt in $runtimes) {
        $vm = Get-ServeVMStatus -RuntimeName $rt
        $sync = Get-ServeSyncStatus -RuntimeName $rt
        $vmStatuses += $vm
        $syncStatuses += $sync

        if ($vm.Status -eq "running") { $anyRunning = $true }
        if ($vm.Status -ne "not-created") { $anyCreated = $true }
        if ($vm.Status -eq "stopped" -or $sync.Health -eq "unhealthy") { $allHealthy = $false }
    }

    $overall = "healthy"
    if (-not $anyCreated) { $overall = "no-runtimes" }
    elseif (-not $anyRunning) { $overall = "unhealthy" }
    elseif (-not $allHealthy) { $overall = "degraded" }

    $report = [ordered]@{
        status    = $overall
        timestamp = (Get-Date -Format "o")
        uptime    = [math]::Round(((Get-Date) - $script:startTime).TotalSeconds, 1)
        runtimes  = @{}
        sync      = @{}
    }

    foreach ($vm in $vmStatuses) {
        $report.runtimes[$vm.Runtime] = [ordered]@{
            status = $vm.Status
            ip     = $vm.Ip
        }
    }

    foreach ($s in $syncStatuses) {
        $report.sync[$s.Runtime] = [ordered]@{
            health = $s.Health
            detail = $s.Detail
        }
    }

    return $report
}

function Write-HealthJsonResponse {
    param($Response)

    $report = Get-HealthReport
    $json = $report | ConvertTo-Json -Depth 4 -Compress
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($json)

    $Response.StatusCode = 200
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

function Write-NotFoundResponse {
    param($Response)

    $body = @{ error = "not found"; endpoint = "/health" } | ConvertTo-Json -Compress
    $buffer = [System.Text.Encoding]::UTF8.GetBytes($body)

    $Response.StatusCode = 404
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentLength64 = $buffer.Length
    $Response.OutputStream.Write($buffer, 0, $buffer.Length)
    $Response.OutputStream.Close()
}

function Start-HealthServer {
    $prefix = if ($Public) { "http://+:$Port/" } else { "http://localhost:$Port/" }

    $listener = New-Object System.Net.HttpListener

    try {
        $listener.Prefixes.Add($prefix)
        $listener.Start()
    } catch [System.Net.HttpListenerException] {
        if ($_.Exception.Message -match "Access is denied") {
            Write-ErrorLog -Message (Get-UIText `
                -English "Cannot listen on $prefix (Access denied). Run as Administrator for -Public, or omit -Public for localhost-only." `
                -Chinese "无法监听 $prefix (权限不足)。-Public 需要管理员权限，或不使用 -Public 以仅监听 localhost。") `
                -Component "cli.serve"
            exit 1
        }
        throw
    }

    $displayUrl = if ($Public) { "http://localhost:$Port/" } else { $prefix }
    Write-Host ""
    Write-UIHost -English "ADP-OS Health Server" -Chinese "ADP-OS 健康检查服务" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-UIHost -English "Listening on: $displayUrl" -Chinese "监听地址: $displayUrl" -ForegroundColor Green
    Write-UIHost -English "Health check: $($displayUrl)health" -Chinese "健康检查: $($displayUrl)health" -ForegroundColor Yellow
    Write-Host ""
    Write-UIHost -English "Press Ctrl+C to stop" -Chinese "按 Ctrl+C 停止服务" -ForegroundColor DarkGray
    Write-Host ""

    Write-InfoLog -Message "Health server started on $prefix" -Component "cli.serve"

    while ($listener.IsListening) {
        try {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response

            # Add CORS header
            $response.Headers.Add("Access-Control-Allow-Origin", "*")

            if ($request.HttpMethod -eq "OPTIONS") {
                $response.Headers.Add("Access-Control-Allow-Methods", "GET, OPTIONS")
                $response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
                $response.StatusCode = 204
                $response.Close()
                continue
            }

            if ($request.Url.AbsolutePath -eq "/health" -and $request.HttpMethod -eq "GET") {
                Write-HealthJsonResponse -Response $response
            } else {
                Write-NotFoundResponse -Response $response
            }
        } catch [System.Net.HttpListenerException] {
            if ($_.Exception.ErrorCode -eq 995) {
                # Listener stopped (Ctrl+C)
                break
            }
            Write-ErrorLog -Message "Server error: $($_.Exception.Message)" -Component "cli.serve"
        } catch {
            Write-ErrorLog -Message "Server error: $($_.Exception.Message)" -Component "cli.serve"
        }
    }

    $listener.Stop()
    $listener.Close()
    Write-Host ""
    Write-UIHost -English "Health server stopped." -Chinese "健康检查服务已停止。" -ForegroundColor Cyan
}

# --- Main ---
if ($Json) {
    # --json mode: output one-shot health report, don't start server
    $report = Get-HealthReport
    $report | ConvertTo-Json -Depth 4
    exit 0
}

Start-HealthServer
