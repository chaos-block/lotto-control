#!/bin/bash
set -euo pipefail

# === Pure Lotto Fleet Bootstrap Launcher ===
# Pulls repo fresh, handles secure vars, execs main script

REPO="https://github.com/chaos-block/lotto-control-drafts.git"
BRANCH="main"
TEMP_DIR="$(mktemp -d)"
MAIN_SCRIPT="pi-imager/lotto-imaging.sh"  # ← Rename/move your full logic script to this

echo "=== Pulling latest from GitHub – 19 Dec 2025 ==="
git clone --depth 1 --branch "$BRANCH" "$REPO" "$TEMP_DIR"

if [ ! -f "$TEMP_DIR/$MAIN_SCRIPT" ]; then
    echo "Error: Main imaging script not found! Check repo path."
    exit 1
fi

# Secure variable input (runtime only)
if [ -z "${TAILSCALE_AUTHKEY:-}" ]; then
    read -s -p "Enter reusable Tailscale auth key (90-day, reuse=500): " TAILSCALE_AUTHKEY
    echo
    export TAILSCALE_AUTHKEY
fi

chmod +x "$TEMP_DIR/$MAIN_SCRIPT"

echo "Launching full imaging script with secure vars..."
exec "$TEMP_DIR/$MAIN_SCRIPT"
