#!/bin/bash
# ADP-OS Bootstrap: Base Setup
# Must be idempotent, re-runnable, failure-recoverable
# Targeted for Ubuntu Server 26.04 LTS

set -euo pipefail

LOG_FILE="/var/log/adp-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "  ADP-OS Base Bootstrap"
echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "========================================="

export DEBIAN_FRONTEND=noninteractive

wait_for_apt_locks() {
    local waited=0
    local max_wait=900
    local locks=(
        /var/lib/dpkg/lock
        /var/lib/dpkg/lock-frontend
        /var/lib/apt/lists/lock
        /var/cache/apt/archives/lock
    )

    while true; do
        local locked=false

        if command -v fuser >/dev/null 2>&1; then
            for lock in "${locks[@]}"; do
                if [ -e "$lock" ] && fuser "$lock" >/dev/null 2>&1; then
                    locked=true
                    break
                fi
            done
        elif pgrep -x apt >/dev/null 2>&1 || pgrep -x apt-get >/dev/null 2>&1 || pgrep -x dpkg >/dev/null 2>&1; then
            locked=true
        fi

        if [ "$locked" != "true" ]; then
            break
        fi

        if [ "$waited" -ge "$max_wait" ]; then
            echo "ERROR: timed out waiting for apt/dpkg locks"
            exit 1
        fi

        echo "  Waiting for apt/dpkg locks... (${waited}s)"
        sleep 10
        waited=$((waited + 10))
    done

    dpkg --configure -a
}

apt_get() {
    wait_for_apt_locks
    apt-get "$@"
}

# --- Step 1: System Update ---
echo "[1/6] Updating system packages..."
apt_get update -qq
apt_get upgrade -y -qq
echo "  Done."

# --- Step 2: Essential Packages ---
echo "[2/6] Installing essential packages..."
apt_get install -y -qq \
    git curl wget \
    build-essential \
    ca-certificates gnupg lsb-release \
    software-properties-common \
    apt-transport-https \
    unzip jq tree \
    tmux htop iotop \
    openssh-server

# Verify SSH is running
systemctl enable ssh
systemctl start ssh
echo "  Done."

# --- Step 3: Modern CLI Tools ---
echo "[3/6] Installing modern CLI tools..."

# ripgrep
if ! command -v rg &>/dev/null; then
    apt_get install -y -qq ripgrep
fi

# fd-find
if ! command -v fdfind &>/dev/null; then
    apt_get install -y -qq fd-find
    # Link fd to fdfind for compatibility
    ln -sf "$(which fdfind)" /usr/local/bin/fd 2>/dev/null || true
fi

# fzf
if ! command -v fzf &>/dev/null; then
    apt_get install -y -qq fzf
fi

echo "  Done."

# --- Step 4: Docker ---
echo "[4/6] Installing Docker..."

if ! command -v docker &>/dev/null; then
    docker_official_ok=false

    if install -m 0755 -d /etc/apt/keyrings &&
        curl --retry 5 --retry-delay 3 --retry-connrefused -fsSL https://download.docker.com/linux/ubuntu/gpg |
            gpg --dearmor -o /etc/apt/keyrings/docker.gpg; then
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
          https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
          tee /etc/apt/sources.list.d/docker.list > /dev/null

        if apt_get update -qq &&
            apt_get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
            docker_official_ok=true
        fi
    fi

    if [ "$docker_official_ok" != "true" ] && ! command -v docker &>/dev/null; then
        echo "  Docker official repository unavailable; falling back to Ubuntu docker packages."
        rm -f /etc/apt/sources.list.d/docker.list
        apt_get update -qq
        apt_get install -y -qq docker.io docker-compose-v2 || apt_get install -y -qq docker.io
    fi

    if ! command -v docker &>/dev/null; then
        echo "ERROR: Docker installation failed"
        exit 1
    fi

    usermod -aG docker adp
    systemctl enable docker
    systemctl start docker
fi

echo "  Done."

# --- Step 5: Language Runtimes ---
echo "[5/6] Installing language runtimes..."

# fnm (Fast Node Manager) + Node.js
if ! command -v node &>/dev/null; then
    if ! command -v fnm &>/dev/null; then
        if curl -fsSL https://fnm.vercel.app/install | bash -s -- --install-dir /opt/fnm; then
            export FNM_DIR="/opt/fnm"
            [ -s "$FNM_DIR/fnm" ] && eval "$($FNM_DIR/fnm env --use-on-cd)"

            /opt/fnm/fnm install --lts
            /opt/fnm/fnm default lts-latest
        else
            echo "  fnm installer unavailable; falling back to Ubuntu nodejs/npm packages."
            apt_get install -y -qq nodejs npm
        fi
    fi
fi

if command -v fnm &>/dev/null && ! command -v node &>/dev/null; then
    export FNM_DIR="/opt/fnm"
    [ -s "$FNM_DIR/fnm" ] && eval "$($FNM_DIR/fnm env --use-on-cd)"
    /opt/fnm/fnm install --lts
    /opt/fnm/fnm default lts-latest
fi

# pnpm
npm install -g pnpm 2>/dev/null || true

# Python + uv
apt_get install -y -qq python3 python3-pip python3-venv
if ! command -v uv &>/dev/null; then
    curl -LsSf https://astral.sh/uv/install.sh | sh || true
fi

echo "  Done."

# --- Step 6: System Tuning ---
echo "[6/6] System tuning..."

# Workshop directory
mkdir -p /home/adp/workspace
chown adp:adp /home/adp/workspace

if ! id adp >/dev/null 2>&1; then
    echo "ERROR: expected user 'adp' does not exist"
    exit 1
fi

# Shell config
if ! grep -q "ADP-OS Environment" /home/adp/.bashrc; then
cat >> /home/adp/.bashrc << 'SHELLRC'
# ADP-OS Environment
export WORKSPACE=/home/adp/workspace
export FNM_DIR="/opt/fnm"
[ -s "$FNM_DIR/fnm" ] && eval "$($FNM_DIR/fnm env --use-on-cd)"
export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

alias ll='ls -alF'
alias la='ls -A'
alias ..='cd ..'

export EDITOR=nano
SHELLRC
fi

touch /home/adp/.adp-base-done
chown adp:adp /home/adp/.bashrc /home/adp/.adp-base-done

echo "========================================="
echo "  ADP-OS Base Bootstrap Complete"
echo "========================================="
