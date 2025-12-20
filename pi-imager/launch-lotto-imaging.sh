#!/bin/bash
set -euo pipefail

# === Lotto Fleet Imaging Launcher – Full Edition ===
# Pulled dynamically by bootstrap launcher.sh
# Auto-installs rpi-imager, builds custom zip from repo, embeds Tailscale key, enables SSH, flashes

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"  # Repo root (temp clone)
CUSTOM_DIR="$REPO_DIR/pi-imager/custom"                        # Future files here (add subdir)
TEMP_CUSTOM="lotto-custom-os"
OS_IMAGE="raspios-lite-arm64.img.xz"
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"

echo "=== Lotto Fleet Imaging Launcher – 19 Dec 2025 ==="

# Prompt for Tailscale reusable key if not set via env
if [ -z "$TAILSCALE_AUTHKEY" ]; then
    read -s -p "Enter your reusable Tailscale auth key (90-day, reuse=500): " TAILSCALE_AUTHKEY
    echo
fi

# Auto-install rpi-imager if missing
if ! command -v rpi-imager &> /dev/null; then
    echo "Installing rpi-imager..."
    sudo apt update
    sudo apt install -y rpi-imager
fi

# Download latest Raspberry Pi OS Lite if not present
if [ ! -f "$OS_IMAGE" ]; then
    echo "Downloading latest Raspberry Pi OS Lite 64-bit..."
    OS_URL=$(wget -qO- https://downloads.raspberrypi.com/os_images.json | grep -A5 '"name":"Raspberry Pi OS Lite (64-bit)"' | grep '"url"' | cut -d'"' -f4)
    wget "https://downloads.raspberrypi.com/$OS_URL" -O "$OS_IMAGE"
fi

# Build custom structure from repo files
rm -rf "$TEMP_CUSTOM" && mkdir -p "$TEMP_CUSTOM"/{boot,firmware,root/usr/local/bin,root/etc/systemd/system}

# Core overlays (hardcoded minimal + pull future from custom/)
cat > "$TEMP_CUSTOM/boot/cmdline.txt" <<EOF
systemd.enable=overlay=yes quiet splash
EOF

cat > "$TEMP_CUSTOM/boot/config.txt" <<EOF
dtparam=watchdog=on
dtoverlay=gpio-fan,gpio=14,temp=60000
dtoverlay=gpio-shutdown,gpio_pin=3,active_low=1,gpio_pull=up
arm_boost=1
EOF
cp "$TEMP_CUSTOM/boot/config.txt" "$TEMP_CUSTOM/firmware/config.txt"

# Copy future custom files if custom/ subdir exists
if [ -d "$CUSTOM_DIR" ]; then
    cp -r "$CUSTOM_DIR"/* "$TEMP_CUSTOM/" || echo "No additional custom files found – using minimal"
fi

# Generate firstboot.sh with embedded Tailscale key
cat > "$TEMP_CUSTOM/root/usr/local/bin/firstboot.sh" <<EOF
#!/bin/bash
set -euo pipefail

SERIAL=\$(awk '/Serial/ {print \$3}' /proc/cpuinfo)
hostnamectl set-hostname "lotto-\${SERIAL: -4}"

# Pull miner scripts from dedicated repo (add your miner repo here)
git clone https://github.com/chaos-block/lotto-miner-scripts.git /home/miner/lotto
cd /home/miner/lotto
chmod +x install-deps.sh *.sh
./install-deps.sh

# Join Tailscale with embedded reusable key
tailscale up --authkey=$TAILSCALE_AUTHKEY --accept-risks=all --advertise-tags=tag:lotto

# Self-delete
systemctl disable firstboot.service
rm /usr/local/bin/firstboot.sh /etc/systemd/system/firstboot.service

reboot
EOF
chmod +x "$TEMP_CUSTOM/root/usr/local/bin/firstboot.sh"

# firstboot service
cat > "$TEMP_CUSTOM/root/etc/systemd/system/firstboot.service" <<EOF
[Unit]
Description=Lotto First Boot Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/firstboot.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

# Zip custom
zip -r "lotto-custom-os.zip" "$TEMP_CUSTOM/"

# List drives & flash
echo "Available drives:"
lsblk -d -o NAME,SIZE,MODEL

read -p "Enter target device (e.g., sdb): " TARGET_DEV
TARGET="/dev/$TARGET_DEV"

read -p "Flash to $TARGET with SSH enabled? Type YES: " CONFIRM
if [ "$CONFIRM" != "YES" ]; then exit 1; fi

rpi-imager --cli \
    --custom "lotto-custom-os.zip" \
    --ssh-enable \
    --ssh-key ~/.ssh/id_rsa.pub \
    "$OS_IMAGE" "$TARGET"

echo "=== Flash complete – deploy miner! ==="
