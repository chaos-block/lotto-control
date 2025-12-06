#!/bin/bash
# lotto_flash.sh — SD Card Imaging + SHA256 Verification
# Lotto Bitcoin Miners Fleet Provisioning
# USAGE: sudo ./lotto_flash. sh <image.img[.xz]> <SD device: /dev/sdX>

set -euo pipefail

IMG="${1:-}"
SDCARD="${2:-}"

usage() {
  cat >&2 <<EOF
USAGE: sudo ./lotto_flash.sh <image.img[.xz]> <SD device>

EXAMPLES:
  sudo ./lotto_flash.sh 2025-11-24-raspios-bookworm-arm64-lite.img.xz /dev/sdc
  sudo ./lotto_flash. sh raspios. img /dev/sdb

NOTES:
  • Run as root/sudo
  • Double-check device (lsblk) — write is destructive
  • Supports . img and .img.xz (auto-detected)
EOF
  exit 1
}

[[ -z "$IMG" || -z "$SDCARD" ]] && usage
[[ ! -e "$IMG" ]] && { echo "❌ ERROR: Image '$IMG' not found. "; exit 2; }
[[ "$EUID" -ne 0 ]] && { echo "❌ ERROR: Must run with sudo."; exit 3; }

# Validate SD device exists and is a block device
if !  [[ -b "$SDCARD" ]]; then
  echo "❌ ERROR: '$SDCARD' is not a valid block device."
  echo "   Run 'lsblk' to find your SD card."
  exit 4
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔧 LOTTO FLEET IMAGING"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Image:  $IMG"
echo "💾 Target: $SDCARD"

# Calculate source hash
echo ""
echo "📊 Computing image SHA256..."
IMG_SHA=$(sha256sum "$IMG" | cut -d' ' -f1)
echo "   $IMG_SHA"

# Confirm before write
echo ""
read -p "⚠️  Ready to write?  Confirm device is correct [y/N]: " -n1 confirm
echo ""
[[ "$confirm" != "y" ]] && { echo "Aborted."; exit 5; }

# Write image
echo ""
echo "⏳ Writing to $SDCARD..."
sync
if [[ "$IMG" == *.xz ]]; then
  xzcat "$IMG" | dd of="$SDCARD" bs=4M status=progress conv=fsync
else
  dd if="$IMG" of="$SDCARD" bs=4M status=progress conv=fsync
fi
sync

# Verify: hash the read-back bytes
echo ""
echo "🔍 Verifying write (SHA256 read-back)..."
IMG_SIZE=$(stat -c%s "$IMG")
if [[ "$IMG" == *.xz ]]; then
  UNCOMPRESSED_SIZE=$(xz -l "$IMG" 2>/dev/null | awk '/Uncompressed/{print $NF}' || echo "$IMG_SIZE")
else
  UNCOMPRESSED_SIZE="$IMG_SIZE"
fi

CARD_HASH=$(dd if="$SDCARD" bs=4M count=$((UNCOMPRESSED_SIZE / 4 / 1024 / 1024 + 1)) 2>/dev/null | \
  head -c "$UNCOMPRESSED_SIZE" | sha256sum | cut -d' ' -f1)

if [[ "$IMG_SHA" == "$CARD_HASH" ]]; then
  echo "✅ VERIFIED: SD card matches image."
  echo "   SHA256: $IMG_SHA"
else
  echo "❌ FAILED: Hash mismatch!"
  echo "   Expected: $IMG_SHA"
  echo "   Got:      $CARD_HASH"
  exit 10
fi

# Eject
echo ""
echo "🔌 Ejecting..."
sync
udisksctl power-off -b "$SDCARD" 2>/dev/null || \
  echo "   (Manual eject: safely remove SD card. )"

echo ""
echo "✅ Complete.  SD card ready for first boot."
