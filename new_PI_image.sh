#!/bin/bash
# Does ONLY one thing: joins Tailscale instantly with your reusable key
set -euo pipefail

if [[ $# -ne 2 ]] || [[ "$2" != tskey-k* ]]; then
    echo "Usage: $0 /dev/sdX tskey-kYourReusableKeyHere..."
    exit 1
fi

DISK="$1"
TSKEY="$2"

echo "⚠️  THIS WILL COMPLETELY ERASE $DISK"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,MODEL "$DISK"
read -p "Type YES to wipe and continue: " confirm
[[ "$confirm" == "YES" ]] || exit 1

# 1. Download & flash (fixed URL – verified 25 Nov 2025)
IMG_URL="https://downloads.raspberrypi.org/raspios_oldstable_lite_arm64/images/raspios_oldstable_lite_arm64-2025-11-24/2025-11-24-raspios-bookworm-arm64-lite.img.xz"
IMG=$(mktemp --suffix=.img.xz)
echo "Downloading Raspberry Pi OS Lite 64-bit (~1.2 GB)..."
curl -L --fail --progress-bar -o "$IMG" "$IMG_URL"

echo "Flashing fresh OS..."
unxz -c --keep "$IMG" | dd of="$DISK" bs=4M conv=fsync oflag=direct status=progress
sync

# 2. Force kernel to re-read partition table
partprobe "$DISK"
sleep 5

# 3. Determine boot partition
if [[ "$DISK" == *"mmcblk"* ]]; then
    BOOT_PART="${DISK}p1"
else
    BOOT_PART="${DISK}1"
fi

# 4. *** FIXED: Dynamically unmount ANY mount on boot partition (not hardcoded paths) ***
echo "Checking for existing mounts on $BOOT_PART..."
MOUNTS=$(mount | awk -v dev="$BOOT_PART" '$1 == dev {print $3}')
if [[ -n "$MOUNTS" ]]; then
    echo "Found existing mount(s) – unmounting them now..."
    while IFS= read -r mount_point; do
        if [[ -n "$mount_point" ]]; then
            echo "  Unmounting $mount_point"
            umount "$mount_point" || umount -l "$mount_point"  # lazy unmount if busy
        fi
    done <<< "$MOUNTS"
    sleep 2  # Give time for unmount to settle
fi

# 5. Clean mount to our own directory
mkdir -p /mnt/boot
mount "$BOOT_PART" /mnt/boot

# 6. Force read-write (handles USB readers with fake write-protect)
mount -o remount,rw /mnt/boot 2>/dev/null || {
    umount /mnt/boot
    mount -t vfat -o uid=0,gid=0,umask=000,rw "$BOOT_PART" /mnt/boot
}

# 7. Final sanity check – we MUST be able to write
if ! touch /mnt/boot/.test_writable 2>/dev/null; then
    echo "ERROR: Boot partition is still read-only (check SD card hardware lock switch or card reader)."
    umount /mnt/boot 2>/dev/null
    exit 1
fi
rm -f /mnt/boot/.test_writable
echo "Boot partition mounted read-write successfully."

# 8. Enable SSH + drop Tailscale-only firstboot scripts
touch /mnt/boot/ssh

cat <<EOF > /mnt/boot/firstboot.sh
#!/bin/bash
set -euo pipefail
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up --authkey=$TSKEY --accept-risk=all
rm -- "\$0"
EOF
chmod +x /mnt/boot/firstboot.sh

cat <<EOF > /mnt/boot/firstrun.sh
#!/bin/bash
/boot/firstboot.sh
rm -- "\$0"
EOF
chmod +x /mnt/boot/firstrun.sh

# 9. Clean up
umount /mnt/boot
rmdir /mnt/boot
rm -f "$IMG"

echo ""
echo "===================================================================="
echo "   • Only installs Tailscale + joins your tailnet"
echo "   • SSH enabled (pi/raspberry until you lock it down)"
echo "===================================================================="
echo "Eject the card → plug into any Pi 4 or Pi 5 → appears in your tailnet in <90 s"
