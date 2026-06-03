#!/bin/bash
# ADP-OS WSL → Windows sync + test helper
# Usage: ./scripts/test.sh [quick|full|integration]

set -e

WIN_TARGET="/mnt/d/Dev/ai-dev-platform"
WIN_PATH="D:\\Dev\\ai-dev-platform"

echo "=== Syncing to Windows ===" && rsync -av --delete --exclude='.git' /home/karoc/ai-dev-platform/ "$WIN_TARGET/" || echo "(non-zero rsync exit; continuing)"
echo ""

MODE="${1:-quick}"

case "$MODE" in
  quick)
    echo "=== Quick validation (static tests only) ==="
    pwsh.exe -ExecutionPolicy Bypass -File "$WIN_PATH\\tests\\validate.ps1" -Quick
    ;;
  full)
    echo "=== Full validation (all tests) ==="
    pwsh.exe -ExecutionPolicy Bypass -File "$WIN_PATH\\tests\\validate.ps1"
    ;;
  integration)
    echo "=== Integration test ==="
    pwsh.exe -ExecutionPolicy Bypass -File "$WIN_PATH\\test-integration.ps1"
    ;;
  cli)
    shift
    echo "=== ADP-OS CLI: $@ ==="
    pwsh.exe -ExecutionPolicy Bypass -File "$WIN_PATH\\cli\\adp.ps1" "$@"
    ;;
  doctor)
    echo "=== ADP-OS doctor ==="
    pwsh.exe -ExecutionPolicy Bypass -File "$WIN_PATH\\cli\\adp.ps1" doctor
    ;;
  deploy)
    echo "=== Deploy check ==="
    pwsh.exe -ExecutionPolicy Bypass -File "$WIN_PATH\\deploy-check.ps1"
    ;;
  *)
    echo "Usage: $0 {quick|full|integration|cli|doctor|deploy}"
    exit 1
    ;;
esac
