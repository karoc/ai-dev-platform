#!/bin/bash
# ADP-OS Bootstrap: Frontend Runtime Setup
# Focused on Node.js / frontend toolchain optimization

set -euo pipefail

LOG_FILE="/var/log/adp-frontend-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "  ADP-OS Frontend Bootstrap"
echo "========================================="

# Ensure base is done
if [ ! -f /home/adp/.adp-base-done ]; then
    echo "ERROR: Base bootstrap must be run first (setup-base.sh)"
    exit 1
fi

# Frontend-specific tools
npm install -g typescript eslint prettier 2>/dev/null || true

# Node.js memory and GC tuning for frontend builds
cat >> /home/adp/.bashrc << 'SHELLRC'

# Frontend Build Optimizations
export NODE_OPTIONS="--max-old-space-size=4096"
export NODE_ENV=development
SHELLRC

# Install common frontend toolchain
apt-get install -y -qq libvips-dev 2>/dev/null || true

touch /home/adp/.adp-frontend-done
echo "Frontend bootstrap complete."
