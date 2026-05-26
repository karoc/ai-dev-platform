#!/bin/bash
# ADP-OS Bootstrap: Agent Runtime Setup
# AI Agent Runtime — high IO tuning, sandbox prep, dangerous runtime config

set -euo pipefail

LOG_FILE="/var/log/adp-agent-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "  ADP-OS Agent Runtime Bootstrap"
echo "========================================="

if [ ! -f /home/adp/.adp-base-done ]; then
    echo "ERROR: Base bootstrap must be run first (setup-base.sh)"
    exit 1
fi

# --- AI Runtime Tuning ---
echo "Applying AI Runtime kernel tuning..."

cat >> /etc/sysctl.d/99-adp-agent.conf << 'SYSCTL'
# ADP-OS Agent Runtime Tuning
# Optimized for high-frequency IO (ripgrep, AST indexing, watchers, git)

fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 1024
fs.inotify.max_queued_events = 32768

fs.file-max = 2097152

vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

kernel.pid_max = 4194304

net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
SYSCTL

sysctl --system

# Set up dedicated ext4 workspace for agent
if mount | grep -q "/home/adp/workspace"; then
    echo "Workspace already has dedicated mount."
else
    echo "NOTE: For optimal IO, use a separate ext4 partition for /home/adp/workspace"
    echo "  Current filesystem: $(df -T /home/adp/workspace | tail -1 | awk '{print $2}')"
fi

# Docker tuning for agent
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'DOCKER'
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65535,
      "Soft": 65535
    }
  }
}
DOCKER

systemctl restart docker 2>/dev/null || true

# Watchman for better file watching
apt-get install -y -qq watchman 2>/dev/null || true

# Sandbox preparation
mkdir -p /home/adp/sandbox
chmod 700 /home/adp/sandbox

echo "WARNING: Agent runtime is configured for dangerous mode" > /home/adp/AGENT_DANGER_MODE.txt

touch /home/adp/.adp-agent-done
echo "Agent runtime bootstrap complete."
