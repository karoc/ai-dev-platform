#!/bin/bash
# ADP-OS Frontend Browser Test Helpers
#
# This file is installed into frontend runtimes by setup-frontend.sh.
# It intentionally does not vendor browsers or package caches into the
# repository. Browser binaries are downloaded on demand inside the VM.

set -euo pipefail

DEFAULT_BROWSER="${ADP_BROWSER:-chromium}"
WORKSPACE="${WORKSPACE:-/home/adp/workspace}"

print_usage() {
    cat <<'USAGE'
ADP frontend browser helpers

Usage:
  adp-frontend-browser-check
  adp-frontend-browser-install [chromium|firefox|webkit|all]

What this does:
  - Checks whether common system browsers and Playwright are available.
  - Installs Playwright Linux dependencies and browser binaries on demand.
  - Keeps browser downloads in the VM user cache, not in this repository.

Recommended first install:
  adp-frontend-browser-install chromium

Then from a project workspace:
  pnpm exec playwright test
USAGE
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

detect_browser() {
    local name="$1"

    case "$name" in
        chromium)
            has_command chromium || has_command chromium-browser || has_command google-chrome || has_command google-chrome-stable
            ;;
        firefox)
            has_command firefox
            ;;
        *)
            return 1
            ;;
    esac
}

print_check() {
    local label="$1"
    shift

    if "$@"; then
        printf '  [OK]   %s\n' "$label"
    else
        printf '  [MISS] %s\n' "$label"
    fi
}

run_check() {
    echo "ADP frontend browser readiness"
    echo "========================================"
    echo

    print_check "Node.js" has_command node
    print_check "npm" has_command npm
    print_check "pnpm" has_command pnpm
    print_check "npx" has_command npx
    print_check "Chromium or Chrome" detect_browser chromium
    print_check "Firefox" detect_browser firefox

    echo
    echo "Workspace: $WORKSPACE"
    if [ -f "$WORKSPACE/package.json" ]; then
        echo "  [OK]   package.json"
    else
        echo "  [INFO] package.json not found in workspace"
    fi

    if [ -d "$WORKSPACE/node_modules/@playwright/test" ]; then
        echo "  [OK]   @playwright/test in workspace"
    else
        echo "  [INFO] @playwright/test not installed in workspace"
    fi

    echo
    echo "Playwright CLI:"
    if [ -x "$WORKSPACE/node_modules/.bin/playwright" ]; then
        "$WORKSPACE/node_modules/.bin/playwright" --version || true
    elif has_command playwright; then
        playwright --version || true
    else
        echo "  [INFO] Playwright CLI is not available yet."
    fi

    echo
    echo "To install a lightweight default browser test stack:"
    echo "  adp-frontend-browser-install chromium"
}

ensure_node_tools() {
    if ! has_command node || ! has_command npm; then
        echo "ERROR: Node.js and npm are required. Re-run ADP frontend bootstrap first." >&2
        exit 1
    fi
}

install_browser() {
    local browser="${1:-$DEFAULT_BROWSER}"

    case "$browser" in
        chromium|firefox|webkit|all)
            ;;
        -h|--help|help)
            print_usage
            exit 0
            ;;
        *)
            echo "ERROR: unsupported browser '$browser'. Use chromium, firefox, webkit, or all." >&2
            exit 1
            ;;
    esac

    ensure_node_tools

    echo "Installing Playwright browser dependencies for: $browser"
    echo "Downloads stay inside the VM, usually under /home/adp/.cache/ms-playwright."
    echo

    if has_command sudo; then
        if [ "$browser" = "all" ]; then
            printf '%s\n' "${ADP_SUDO_PASSWORD:-adp}" | sudo -S npx --yes playwright install-deps
        else
            printf '%s\n' "${ADP_SUDO_PASSWORD:-adp}" | sudo -S npx --yes playwright install-deps "$browser"
        fi
    else
        echo "WARNING: sudo is not available; skipping Playwright system dependency installation." >&2
    fi

    if [ "$browser" = "all" ]; then
        npx --yes playwright install
    else
        npx --yes playwright install "$browser"
    fi

    echo
    echo "Browser test stack is ready."
    echo "From a project workspace, run:"
    echo "  pnpm exec playwright test"
}

main() {
    local invoked
    invoked="$(basename "$0")"

    case "$invoked" in
        adp-frontend-browser-check)
            run_check
            ;;
        adp-frontend-browser-install)
            install_browser "${1:-$DEFAULT_BROWSER}"
            ;;
        *)
            case "${1:-check}" in
                check)
                    run_check
                    ;;
                install)
                    shift || true
                    install_browser "${1:-$DEFAULT_BROWSER}"
                    ;;
                -h|--help|help)
                    print_usage
                    ;;
                *)
                    print_usage
                    exit 1
                    ;;
            esac
            ;;
    esac
}

main "$@"
