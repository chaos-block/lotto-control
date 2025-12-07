#!/bin/bash
# flash-lotto-node.sh — Bootstrap: Download latest lotto_flash. sh and execute
# Usage: sudo bash flash-lotto-node. sh <image.img[.xz]> <SD device>

REPO_OWNER="chaos-block"
REPO_NAME="lotto-control-drafts"
BRANCH="main"
SCRIPT_URL="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH/lotto_flash.sh"

# === Prestaged reusable Tailscale key (REPLACE WITH YOUR REAL KEY) ===
PRESTAGED_KEY="tskey-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # Generate on lotto-control: tailscale key create --expiry=2160h --reuse=500

if [[ "$PRESTAGED_KEY" == "tskey-xxxx"* || -z "$PRESTAGED_KEY" ]]; then
  echo "ERROR: Replace PRESTAGED_KEY in flash-lotto-node.sh with your real reusable Tailscale auth key"
  exit 1
fi

echo "🔗 Fetching lotto_flash.sh from $REPO_OWNER/$REPO_NAME..."
SCRIPT=$(curl -fsSL "$SCRIPT_URL")

if [[ -z "$SCRIPT" ]]; then
  echo "❌ ERROR: Could not fetch script from GitHub."
  exit 1
fi

# Clean fetched script: strip markdown + CRLF
CLEAN_SCRIPT=$(echo "$SCRIPT" | sed '/^```/d; s/\r$//g')

# Embed PRESTAGED_KEY and run (pass as env var)
echo "Downloaded, cleaned, and key embedded. Running..."
PRESTAGED_KEY="$PRESTAGED_KEY" echo "$CLEAN_SCRIPT" | sudo bash -s "$@"
