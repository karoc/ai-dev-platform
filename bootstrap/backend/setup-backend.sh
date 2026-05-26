#!/bin/bash
# ADP-OS Bootstrap: Backend Runtime Setup
# Optimized for Python / Node.js backend toolchain

set -euo pipefail

LOG_FILE="/var/log/adp-backend-bootstrap.log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "  ADP-OS Backend Bootstrap"
echo "========================================="

if [ ! -f /home/adp/.adp-base-done ]; then
    echo "ERROR: Base bootstrap must be run first (setup-base.sh)"
    exit 1
fi

# Python dev tools
pip3 install ipython pytest black ruff mypy 2>/dev/null || true

# Generic WSGI
pip3 install gunicorn uvicorn 2>/dev/null || true

touch /home/adp/.adp-backend-done
echo "Backend bootstrap complete."
