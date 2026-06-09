# ADP-OS Run Command
# One-command runtime creation: combines init + up + sync start + status.
# Like "docker run" or "daytona create" — a single command to get a working agent VM.

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$RuntimeName,
    [switch]$Plan,
    [switch]$NoBootstrap,
    [switch]$NoProvision,
    [switch]$NoSync,
    [string]$IsoPath
)

$ErrorActionPreference = "Stop"

if (-not $RuntimeName) {
    $validRuntimes = (Get-AllRuntimeNames) -join ', '
    Write-ErrorLog -Message (Get-UIText -English "Usage: adpos run <runtime> ($validRuntimes) [-IsoPath <path>] [-Plan] [-NoBootstrap] [-NoProvision] [-NoSync]" -Chinese "用法: adpos run <runtime> ($validRuntimes) [-IsoPath <path>] [-Plan] [-NoBootstrap] [-NoProvision] [-NoSync]") -Component "cli.run"
    Write-UIHost -English "Run 'adpos run --help' for usage." -Chinese "运行 'adpos run --help' 查看用法。" -ForegroundColor DarkGray
    exit 1
}

if (-not (Test-RuntimeExists $RuntimeName)) {
    Write-ADPUnknownRuntimeError -RuntimeName $RuntimeName -CommandText "run" -Component "cli.run"
    exit 1
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  ADP-OS Run: One-command $RuntimeName" -Chinese "  ADP-OS Run: 一键启动 $RuntimeName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-UIHost -English "  Combines: init -> up -> sync start -> status" -Chinese "  流程: init -> up -> sync start -> status" -ForegroundColor DarkGray
Write-Host ""

$cliDir = Join-Path (Get-ProjectRoot) "cli\commands"

if ($Plan) {
    Write-UIHost -English "Plan only — no changes will be made." -Chinese "仅预览 — 不会执行任何变更。" -ForegroundColor Cyan
    Write-Host ""

    # Show what would happen
    Write-UIHost -English "[1/4] Would run: adpos init" -Chinese "[1/4] 将运行: adpos init" -ForegroundColor Yellow
    Write-UIHost -English "       Verify VMware, ISO, SSH keys, directories, VM factory" -Chinese "       验证 VMware、ISO、SSH 密钥、目录、VM factory" -ForegroundColor DarkGray
    Write-Host ""
    $upArgs = @("-Plan")
    if ($IsoPath) { $upArgs += "-IsoPath"; $upArgs += $IsoPath }
    if ($NoBootstrap) { $upArgs += "-NoBootstrap" }
    if ($NoProvision) { $upArgs += "-NoProvision" }
    Write-UIHost -English "[2/4] Would run: adpos up $RuntimeName $($upArgs -join ' ')" -Chinese "[2/4] 将运行: adpos up $RuntimeName $($upArgs -join ' ')" -ForegroundColor Yellow
    Write-UIHost -English "       Create/start VM, autoinstall, bootstrap" -Chinese "       创建/启动 VM、autoinstall、bootstrap" -ForegroundColor DarkGray
    Write-Host ""
    if (-not $NoSync) {
        Write-UIHost -English "[3/4] Would run: adpos sync start $RuntimeName" -Chinese "[3/4] 将运行: adpos sync start $RuntimeName" -ForegroundColor Yellow
        Write-UIHost -English "       Start Mutagen file sync between local workspace and VM" -Chinese "       启动 Mutagen 文件同步（本地工作区 ↔ VM）" -ForegroundColor DarkGray
        Write-Host ""
    }
    Write-UIHost -English "[4/4] Would run: adpos status $RuntimeName" -Chinese "[4/4] 将运行: adpos status $RuntimeName" -ForegroundColor Yellow
    Write-UIHost -English "       Show runtime status and connection details" -Chinese "       显示运行时状态和连接信息" -ForegroundColor DarkGray
    Write-Host ""
    Write-UIHost -English "To execute: run without -Plan" -Chinese "要执行: 不加 -Plan 运行" -ForegroundColor Cyan
    return
}

# --- Step 1: Init (ensure platform is ready) ---
Write-UIHost -English "[1/4] Initializing platform..." -Chinese "[1/4] 正在初始化平台..." -ForegroundColor Yellow
$initScript = Join-Path $cliDir "init.ps1"
$initArgs = @{}
if ($RuntimeName) { $initArgs.RuntimeName = $RuntimeName }
if ($IsoPath) { $initArgs.IsoPath = $IsoPath }
if ($NoProvision) { $initArgs.NoProvision = $true }

try {
    $initExit = & $initScript @initArgs
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE) {
        Write-ErrorLog -Message "Init step failed with exit code $LASTEXITCODE" -Component "cli.run"
        exit $LASTEXITCODE
    }
} catch {
    Write-WarnLog -Message "Init had non-fatal issues: $_" -Component "cli.run"
}
$global:LASTEXITCODE = 0

# --- Step 2: Up (create/start VM) ---
Write-Host ""
Write-UIHost -English "[2/4] Starting/creating VM..." -Chinese "[2/4] 正在启动/创建 VM..." -ForegroundColor Yellow
$upScript = Join-Path $cliDir "up.ps1"
$upArgs = @{
    RuntimeName = $RuntimeName
}
if ($IsoPath) { $upArgs.IsoPath = $IsoPath }
if ($NoBootstrap) { $upArgs.NoBootstrap = $true }
if ($NoProvision) { $upArgs.NoProvision = $true }

try {
    $upExit = & $upScript @upArgs
    if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE) {
        Write-ErrorLog -Message "Up step failed with exit code $LASTEXITCODE" -Component "cli.run"
        Write-UIHost -English "VM is running but may need manual attention. Run: adpos status $RuntimeName" -Chinese "VM 可能在运行但需要手动处理。运行: adpos status $RuntimeName" -ForegroundColor Yellow
        exit $LASTEXITCODE
    }
} catch {
    Write-ErrorLog -Message "Up step failed: $_" -Component "cli.run"
    exit 1
}
$global:LASTEXITCODE = 0

# --- Step 3: Sync Start (optional) ---
if (-not $NoSync) {
    Write-Host ""
    Write-UIHost -English "[3/4] Starting file sync..." -Chinese "[3/4] 正在启动文件同步..." -ForegroundColor Yellow
    $syncScript = Join-Path $cliDir "sync.ps1"
    try {
        & $syncScript "start" $RuntimeName
        if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE) {
            Write-WarnLog -Message "Sync start had issues (exit $LASTEXITCODE). VM is running — try: adpos sync start $RuntimeName" -Component "cli.run"
        }
    } catch {
        Write-WarnLog -Message "Sync start had issues: $_" -Component "cli.run"
        Write-UIHost -English "Sync could not start. VM is running. Try manually: adpos sync start $RuntimeName" -Chinese "无法启动同步。VM 已在运行。手动尝试: adpos sync start $RuntimeName" -ForegroundColor Yellow
    }
    $global:LASTEXITCODE = 0
}

# --- Step 4: Status (show connection info) ---
Write-Host ""
Write-UIHost -English "[4/4] Runtime ready — status:" -Chinese "[4/4] 运行时已就绪 — 状态:" -ForegroundColor Yellow
$statusScript = Join-Path $cliDir "status.ps1"
& $statusScript -RuntimeName $RuntimeName
$global:LASTEXITCODE = 0

Write-Host ""
Write-UIHost -English "Runtime '$RuntimeName' is ready. Happy building!" -Chinese "运行时 '$RuntimeName' 已就绪。开始构建吧！" -ForegroundColor Green
