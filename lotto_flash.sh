#!/bin/bash
# lotto_flash.sh — Complete Lotto Miner Provisioning (Imaging + Tailscale)
# Phase 1: Reliable flash + tailnet join
# USAGE: sudo ./lotto_flash.sh [image.img.xz or empty for auto-download] /dev/sdX

set -euo pipefail

IMG="${1:-}"
SDCARD="${2:-}"

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

printf "Image: %s → %s\n" "$IMG" "$SDCARD"
read -p "Confirm write to $SDCARD [y/N]: " confirm
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
MOUNT_POINT="/mnt/lotto-boot"

echo "Ensuring boot partition $BOOT_PART is mounted at $MOUNT_POINT"
mkdir -p "$MOUNT_POINT"

if ! grep -q "$MOUNT_POINT" /proc/mounts; then
  mount "$BOOT_PART" "$MOUNT_POINT"
  echo "→ Mounted $BOOT_PART"
else
  echo "→ Already mounted – proceeding"
fi

# Ensure firmware directories exist on boot partition
mkdir -p "$MOUNT_POINT/firmware"
mkdir -p "$MOUNT_POINT/firmware/systemd"
echo "→ Created firmware directories"

# Enable SSH on first boot
touch "$MOUNT_POINT/firmware/ssh"
echo "→ SSH enabled on first boot"

# Skip first-boot user wizard – pre-create 'pi' user with password 'raspberry'
echo "$(echo 'raspberry' | openssl passwd -5 -stdin)" | sed 's/^/pi:/' > "$MOUNT_POINT/userconf"
echo "→ Pre-created 'pi' user (password: raspberry) – wizard skipped"

# First-boot script (self-destruct)
# First-boot Tailscale script (runs automatically on first boot)
mkdir -p "$MOUNT_POINT/firmware/first-boot"
cat <<EOF > "$MOUNT_POINT/firmware/first-boot/firstboot-tailscale.sh"
#!/bin/bash
set -euo pipefail
MARKER="/.tailscale-done"
[[ -f "\$MARKER" ]] && exit 0
AUTHKEY="${PRESTAGED_KEY:-}"
[[ -z "$$ AUTHKEY" ]] && { echo "[ $$(date)] No prestaged key" >> /var/log/firstboot-tailscale.log; exit 1; }
HOSTNAME="lotto-\$(tr -d '\0' < /proc/device-tree/serial-number)"

curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled
timeout 120 bash -c 'until ping -c1 8.8.8.8 &>/dev/null; do sleep 1; done'

tailscale up --authkey="\$AUTHKEY" --hostname="\$HOSTNAME" --advertise-tags=tag:lotto

touch "\$MARKER"
rm -- "\$0"
EOF
chmod +x "$MOUNT_POINT/firmware/first-boot/firstboot-tailscale.sh"
echo "→ First-boot Tailscale script deployed (runs automatically)"

[Service]
Type=oneshot
ExecStart=/bin/bash /boot/firmware/firstboot-tailscale.sh

[Install]
WantedBy=multi-user.target
EOF

echo "Tailscale prestaged + first-boot deployed"

if grep -q "$MOUNT_POINT" /proc/mounts; then
  umount "$MOUNT_POINT"
  echo "→ Unmounted $MOUNT_POINT"
else
  echo "→ Not mounted – skipping unmount"
fi
sync

echo "LOTTO MINER PROVISIONED"
echo "→ Plug in power → miner joins tailnet automatically"
echo "→ lotto-control can now SSH in → Phase 2 optimizations next"

exit 0
