# ADP-OS SSH Adapter (Windows)
# Platform-specific SSH key management and connection helpers

$script:SshKeyDir = "$env:USERPROFILE\.ssh\adp-os"

function Initialize-SSH {
    param([string]$KeyName = "adp-os")

    $script:SshKeyDir = "$env:USERPROFILE\.ssh\adp-os"

    if (-not (Test-Path $script:SshKeyDir)) {
        New-Item -ItemType Directory -Path $script:SshKeyDir -Force | Out-Null
    }

    $keyPath = Join-Path $script:SshKeyDir $KeyName

    if (-not (Test-Path $keyPath)) {
        & ssh-keygen -t ed25519 -f $keyPath -N "" -C "adp-os-runtime" | Out-Null
    }

    return $keyPath
}

function Get-SSHPubKey {
    param([string]$KeyName = "adp-os")

    $keyPath = Join-Path $script:SshKeyDir "$KeyName.pub"

    if (-not (Test-Path $keyPath)) {
        throw "SSH key not found. Run Initialize-SSH first."
    }

    return Get-Content $keyPath -Raw
}

function Connect-Runtime {
    param(
        [string]$Host,
        [int]$Port = 22,
        [string]$User = "adp",
        [string]$KeyName = "adp-os"
    )

    $keyPath = Join-Path $script:SshKeyDir $KeyName

    & ssh -i $keyPath -p $Port "$User@$Host"
}

function Copy-ToRuntime {
    param(
        [string]$Host,
        [string]$LocalPath,
        [string]$RemotePath,
        [int]$Port = 22,
        [string]$User = "adp",
        [string]$KeyName = "adp-os"
    )

    $keyPath = Join-Path $script:SshKeyDir $KeyName

    & scp -i $keyPath -P $Port -r $LocalPath "$User@${Host}:$RemotePath"
}

function Invoke-RuntimeCommand {
    param(
        [string]$Host,
        [string]$Command,
        [int]$Port = 22,
        [string]$User = "adp",
        [string]$KeyName = "adp-os"
    )

    $keyPath = Join-Path $script:SshKeyDir $KeyName

    return & ssh -i $keyPath -p $Port "$User@$Host" $Command
}
