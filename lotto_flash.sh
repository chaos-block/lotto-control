#!/bin/bash
# lotto_flash.sh — Complete Lotto Miner Provisioning (Imaging + Tailscale)
# Phase 1: Reliable flash + tailnet join
# USAGE: sudo ./lotto_flash.sh [image.img.xz or empty for auto-download] /dev/sdX

set -euo pipefail

IMG="${1:-}"
SDCARD="${2:-}"

# === Prestaged reusable Tailscale key (REPLACE WITH YOUR KEY) ===
PRESTAGED_KEY="tskey-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"  # Generate: tailscale key create --expiry=2160h --reuse=500

usage() {
  cat >&2 <<EOF
USAGE: sudo ./lotto_flash.sh [image.img.xz] <SD device>

If image omitted: auto-downloads latest Raspberry Pi OS Lite 64-bit Bookworm
EOF
  exit 1
}

[[ -z "$SDCARD" ]] && usage
[[ "$EUID" -ne 0 ]] && { echo "ERROR: Run with sudo"; exit 3; }
[[ ! -b "$SDCARD" ]] && { echo "ERROR: '$SDCARD' not valid block device"; exit 4; }

# Auto-download if no image
if [[ -z "$IMG" ]]; then
  echo "No image provided – downloading latest Raspberry Pi OS Lite 64-bit Bookworm..."
  IMG="latest-raspios-bookworm-arm64-lite.img.xz"
  curl -L -o "$IMG" https://downloads.raspberrypi.com/raspios_lite_arm64/images/$(curl -s https://downloads.raspberrypi.com/raspios_lite_arm64 | tail -n5 | grep -o 'href="[^"]*"' | cut -d'"' -f2 | tail -1)latest
fi

[[ ! -e "$IMG" ]] && { echo "ERROR: Image not found"; exit 2; }

echo "Image: $IMG → $SDCARD"
read -p "Confirm write to $SDCARD [y/N]: " -n1 confirm
echo "1"
[[ "$confirm" != "y" ]] && { echo "Aborted"; exit 5; }

# Write + verify (existing logic)
sync
if [[ "$IMG" == *.xz ]]; then
  xzcat "$IMG" | dd of="$SDCARD" bs=4M conv=fsync status=progress
else
  dd if="$IMG" of="$SDCARD" bs=4M conv=fsync status=progress
fi
sync

# === Mount boot + deploy Tailscale prestaged ===
BOOT_PART="${SDCARD}1"
echo "Mounting boot partition $BOOT_PART"
mkdir -p /mnt/lotto-boot
mount "$BOOT_PART" /mnt/lotto-boot

# Deploy prestaged key
echo "$PRESTAGED_KEY" > /mnt/lotto-boot/firmware/tailscale-authkey.txt
chmod 600 /mnt/lotto-boot/firmware/tailscale-authkey.txt

# First-boot script (self-destruct)
cat <<'EOF' > /mnt/lotto-boot/firmware/firstboot-tailscale.sh
#!/bin/bash
set -euo pipefail
MARKER="/.tailscale-done"
[[ -f "$MARKER" ]] && exit 0
AUTHKEY=$(cat /boot/firmware/tailscale-authkey.txt)
HOSTNAME="lotto-$(tr -d '\0' < /proc/device-tree/serial-number)"

curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
timeout 120 bash -c 'until ping -c1 8.8.8.8 &>/dev/null; do sleep 1; done'

tailscale up --authkey="$AUTHKEY" --hostname="$HOSTNAME" --advertise-tags=tag:lotto

touch "$MARKER"
rm -- "$0" /boot/firmware/tailscale-authkey.txt
EOF
chmod +x /mnt/lotto-boot/firmware/firstboot-tailscale.sh

# Enable via systemd (simple oneshot)
mkdir -p /mnt/lotto-boot/firmware/systemd
cat <<'EOF' > /mnt/lotto-boot/firmware/systemd/firstboot-tailscale.service
[Unit]
Description=Lotto Tailscale First Boot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/bin/bash /boot/firmware/firstboot-tailscale.sh

[Install]
WantedBy=multi-user.target
EOF

echo "Tailscale prestaged + first-boot deployed"

umount /mnt/lotto-boot
sync

echo "LOTTO MINER PROVISIONED"
echo "→ Plug in power → miner joins tailnet automatically"
echo "→ lotto-control can now SSH in → Phase 2 optimizations next"

exit 0
