# ADP-OS Bootstrap Orchestrator
# Copies and executes bootstrap scripts on remote VMs via SSH.

$script:BootstrapState = @{}

function Initialize-BootstrapOrchestrator {
    param(
        [string]$ProjectRoot
    )

    $script:BootstrapState.ProjectRoot = $ProjectRoot
    $script:BootstrapState.BootstrapDir = Join-Path $ProjectRoot "bootstrap"

    . (Join-Path $ProjectRoot "adapters\windows\ssh\ssh.ps1")
}

function Invoke-RuntimeBootstrap {
    param(
        [string]$RuntimeName,
        [string]$SSHHost,
        [int]$Port = 22,
        [string]$User = "adp",
        [switch]$SkipBase
    )

    $rt = Get-RuntimeConfig $RuntimeName
    $profile = $rt.bootstrap_profile
    $keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"

    function Invoke-BootstrapSSH {
        param([string]$Command)

        & ssh -i $keyPath `
            -o StrictHostKeyChecking=no `
            -o UserKnownHostsFile=NUL `
            -o IdentitiesOnly=yes `
            -o ConnectTimeout=10 `
            -p $Port `
            "${User}@${SSHHost}" `
            $Command
    }

    function Copy-BootstrapFile {
        param(
            [string]$LocalPath,
            [string]$RemotePath
        )

        & scp -i $keyPath `
            -o StrictHostKeyChecking=no `
            -o UserKnownHostsFile=NUL `
            -o IdentitiesOnly=yes `
            -P $Port `
            $LocalPath `
            "${User}@${SSHHost}:$RemotePath"
    }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "  Bootstrapping: $RuntimeName" -ForegroundColor Cyan
    Write-Host "  Profile: $profile" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Host "[0/4] Testing SSH connectivity..." -ForegroundColor Yellow
    $testResult = Invoke-BootstrapSSH -Command "echo SSH_OK" 2>$null
    if ($testResult -ne "SSH_OK") {
        Write-ErrorLog -Message "SSH connection failed for $RuntimeName at $SSHHost" -Component "bootstrap"
        return $false
    }
    Write-Host "  SSH connection OK" -ForegroundColor Green

    Write-Host "[1/4] Uploading bootstrap scripts..." -ForegroundColor Yellow
    $commonScript = Join-Path $script:BootstrapState.BootstrapDir "common\common.sh"
    $setupBase = Join-Path $script:BootstrapState.BootstrapDir "base\setup-base.sh"

    Copy-BootstrapFile -LocalPath $commonScript -RemotePath "/tmp/common.sh" 2>$null
    Copy-BootstrapFile -LocalPath $setupBase -RemotePath "/tmp/setup-base.sh" 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-ErrorLog -Message "Failed to upload bootstrap scripts" -Component "bootstrap"
        return $false
    }
    Write-Host "  Scripts uploaded." -ForegroundColor Green

    if (-not $SkipBase) {
        Write-Host "[2/4] Running base bootstrap..." -ForegroundColor Yellow
        Write-Host "  This installs: git, curl, ripgrep, fd, fzf, jq, Docker, fnm, Node, pnpm, Python, uv, tmux" -ForegroundColor DarkGray

        $result = Invoke-BootstrapSSH -Command "printf '%s\n' 'adp' | sudo -S bash /tmp/setup-base.sh" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog -Message "Base bootstrap failed: $result" -Component "bootstrap"
            Write-WarnLog -Message "Base bootstrap had errors but may be recoverable" -Component "bootstrap"
        } else {
            Write-Host "  Base bootstrap complete." -ForegroundColor Green
        }
    } else {
        Write-Host "[2/4] Base bootstrap skipped." -ForegroundColor DarkGray
    }

    Write-Host "[3/4] Running $profile bootstrap..." -ForegroundColor Yellow
    $profileScript = Join-Path $script:BootstrapState.BootstrapDir "$profile\setup-${profile}.sh"

    if (Test-Path $profileScript) {
        Copy-BootstrapFile -LocalPath $profileScript -RemotePath "/tmp/setup-${profile}.sh" 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-ErrorLog -Message "Failed to upload $profile bootstrap script" -Component "bootstrap"
            return $false
        }

        $result = Invoke-BootstrapSSH -Command "printf '%s\n' 'adp' | sudo -S bash /tmp/setup-${profile}.sh" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-WarnLog -Message "$profile bootstrap had warnings: $result" -Component "bootstrap"
        }
        Write-Host "  $profile bootstrap complete." -ForegroundColor Green
    } else {
        Write-Host "  No specific bootstrap for profile: $profile" -ForegroundColor DarkGray
    }

    Write-Host "[4/4] Verifying installation..." -ForegroundColor Yellow
    $checks = @(
        "git --version",
        "docker --version",
        "node --version 2>/dev/null || echo 'node:missing'",
        "python3 --version",
        "rg --version",
        "fdfind --version 2>/dev/null || fd --version 2>/dev/null || echo 'fd:missing'"
    )

    foreach ($check in $checks) {
        $ver = Invoke-BootstrapSSH -Command $check 2>$null
        Write-Host "  $ver" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Bootstrap complete for: $RuntimeName" -ForegroundColor Green
    return $true
}

function Copy-Workspace {
    param(
        [string]$RuntimeName,
        [string]$SSHHost,
        [string]$LocalWorkspace,
        [string]$RemoteWorkspace = "/home/adp/workspace",
        [int]$Port = 22,
        [string]$User = "adp"
    )

    $keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"

    Write-Host "Copying workspace: $LocalWorkspace -> $RemoteWorkspace" -ForegroundColor Yellow

    scp -i $keyPath `
        -o StrictHostKeyChecking=no `
        -o UserKnownHostsFile=NUL `
        -o IdentitiesOnly=yes `
        -P $Port `
        -r `
        $LocalWorkspace `
        "${User}@${SSHHost}:$RemoteWorkspace" 2>$null

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Workspace copied." -ForegroundColor Green
    } else {
        Write-WarnLog -Message "Workspace copy may have failed; check permissions" -Component "bootstrap"
    }
}

function Get-BootstrapStatus {
    param(
        [string]$RuntimeName,
        [string]$SSHHost,
        [int]$Port = 22,
        [string]$User = "adp"
    )

    $keyPath = Join-Path "$env:USERPROFILE\.ssh\adp-os" "adp-os"
    $markers = @(
        @{Name="base"; File="/home/adp/.adp-base-done"},
        @{Name="frontend"; File="/home/adp/.adp-frontend-done"},
        @{Name="backend"; File="/home/adp/.adp-backend-done"},
        @{Name="agent"; File="/home/adp/.adp-agent-done"}
    )

    $results = @{}
    foreach ($m in $markers) {
        $check = & ssh -i $keyPath `
            -o StrictHostKeyChecking=no `
            -o UserKnownHostsFile=NUL `
            -o IdentitiesOnly=yes `
            -o ConnectTimeout=5 `
            -p $Port `
            "${User}@${SSHHost}" `
            "test -f $($m.File) && echo done || echo missing" 2>$null
        $results[$m.Name] = $check -eq "done"
    }

    return $results
}
