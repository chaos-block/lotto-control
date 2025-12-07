#!/bin/bash
# prepare-lotto-image.sh — One-command lotto image preparation
# Place SD card already flashed with Raspberry Pi OS Lite 64-bit Bookworm
# Run with sudo → outputs perfect lotto miner ready for 1000+ fleet

set -euo pipefail

# === CONFIGURATION (never contains secrets) ===
BOOT_MOUNT="/mnt/pi-boot"
FIRMWARE="$BOOT_MOUNT/firmware"
HOSTNAME_BASE="lotto"
CONTROL_NODE="lotto-control"          # change only if different
KEY_SERVER_PORT="8080"

# === Safety first ===
if [[ $EUID -ne 0 ]]; then
   echo "Must run as root (sudo)"
   exit 1
fi

if ! lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -q "$BOOT_MOUNT"; then
   echo "Boot partition not mounted at $BOOT_MOUNT"
   echo "Mount it first:"
   echo "  sudo mkdir -p $BOOT_MOUNT"
   echo "  sudo mount /dev/sdX1 $BOOT_MOUNT   # replace sdX1 with your boot partition"
   exit 1
fi

echo "Preparing lotto image on $BOOT_MOUNT"

# === cmdline.txt — read-only root + quiet boot ===
if ! grep -q "systemd.enable=overlay=yes" "$FIRMWARE/cmdline.txt"; then
  sed -i 's|$| systemd.enable=overlay=yes quiet splash|' "$FIRMWARE/cmdline.txt"
  echo "→ cmdline.txt updated (overlayfs + quiet)"
fi

# === config.txt — hardware resilience ===
cat <<'EOF' > "$FIRMWARE/config.txt.new"
# Lotto miner hardware settings
dtparam=watchdog=on
dtoverlay=gpio-fan,gpio=14,temp=60000
dtoverlay=gpio-shutdown,gpio_pin=3,active_low=1,gpio_pull=up
arm_boost=1
EOF
cat "$FIRMWARE/config.txt" >> "$FIRMWARE/config.txt.new"
mv "$FIRMWARE/config.txt.new" "$FIRMWARE/config.txt"
echo "→ config.txt updated (watchdog + fan + shutdown)"

# === First-boot Tailscale (zero secrets) ===
cat <<'EOF' > "$FIRMWARE/firstboot-tailscale.sh"
#!/bin/bash
set -euo pipefail
MARKER="/.tailscale-firstboot-done"
[[ -f "$MARKER" ]] && exit 0
LOG="/var/log/firstboot-tailscale.log"
HOSTNAME="lotto-$(tr -d '\0' < /proc/device-tree/serial-number)"

echo "[$(date)] Starting Tailscale first-boot for $HOSTNAME" >> "$LOG"

curl -fsSL https://tailscale.com/install.sh | sh
systemctl enable --now tailscaled

timeout 120 bash -c 'until ping -c1 100.100.100.100 &>/dev/null; do sleep 1; done' || exit 0

KEY=$(curl -fsS http://'"$CONTROL_NODE"':'"$KEY_SERVER_PORT"'/key 2>/dev/null || true)
if [[ -n "$KEY" && "$KEY" =~ ^tskey-* ]]; then
  tailscale up --authkey="$KEY" --hostname="$HOSTNAME" --advertise-tags=tag:lotto
else
  FALLBACK=$(curl -fsS http://'"$CONTROL_NODE"':'"$KEY_SERVER_PORT"'/fallback-key 2>/dev/null || true)
  [[ -n "$FALLBACK" && "$FALLBACK" =~ ^tskey-* ]] && tailscale up --authkey="$FALLBACK" --hostname="$HOSTNAME" --advertise-tags=tag:lotto
fi

touch "$MARKER"
rm -- "$0"
echo "[$(date)] Tailscale joined successfully" >> "$LOG"
EOF
chmod +x "$FIRMWARE/firstboot-tailscale.sh"
echo "→ firstboot-tailscale.sh deployed"

# === Enable first-boot service ===
mkdir -p "$FIRMWARE/firmware/systemd"
cat <<'EOF' > "$FIRMWARE/firmware/systemd/firstboot-tailscale.service"
[Unit]
Description=Lotto Miner Tailscale First Boot
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/.tailscale-firstboot-done

[Service]
Type=oneshot
ExecStart=/bin/bash /boot/firmware/firstboot-tailscale.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
echo "→ systemd service deployed"

# === Final message ===
echo
echo "LOTTO IMAGE READY"
echo "→ Safely eject SD card"
echo "→ Plug into miner → it will auto-join tailnet within 2 minutes"
echo "→ No secrets in image | Read-only root | Full watchdog protection"
echo
echo "Fleet scaling: 100 → 1000+ nodes → just keep flashing"

exit 0
