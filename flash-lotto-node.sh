#!/bin/bash
# flash-lotto-node.sh — Bootstrap: Download latest lotto_flash. sh and execute
# Usage: sudo bash flash-lotto-node. sh <image.img[.xz]> <SD device>

REPO_OWNER="chaos-block"
REPO_NAME="lotto-control-drafts"
BRANCH="main"
SCRIPT_URL="https://raw.githubusercontent.com/$REPO_OWNER/$REPO_NAME/$BRANCH/lotto_flash.sh"

echo "🔗 Fetching lotto_flash.sh from $REPO_OWNER/$REPO_NAME..."
SCRIPT=$(curl -fsSL "$SCRIPT_URL")

if [[ -z "$SCRIPT" ]]; then
  echo "❌ ERROR: Could not fetch script from GitHub."
  exit 1
fi

echo "✓ Downloaded.  Running..."
echo "$$ SCRIPT" | sudo bash -s " $$@"
