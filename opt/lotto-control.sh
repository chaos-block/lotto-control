#!/bin/bash
set -euo pipefail
BASEDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASEDIR"

# Load config & libraries
source "$BASEDIR/config/config.sh"
for lib in tailscale ssh-keys wifi-push telegram miners logging; do
    source "$BASEDIR/lib/${lib}.sh"
done

usage() {
    cat <<EOF
Lotto-Control Fleet Manager (Modular Edition – 25 Nov 2025)

Usage: $(basename "$0") <command>

Commands:
  generate-key            Create new 15-day ephemeral Tailscale key
  rotate-ssh              Rotate all miner SSH keys (28-day cadence)
  push-wifi               Push updated Wi-Fi policy to entire fleet
  alert <msg>             Send Telegram alert (internal)
  discover                Refresh miners.json inventory
  pull-logs               Rsync all miner logs centrally
  status                  Show fleet overview
  onboard <hostname>      Manual onboard of a new miner (rare)
EOF
    exit 1
}

[[ $# -ge 1 ]] || usage

case "$1" in
    generate-key)  tailscale::generate_ephemeral_key ;;
    rotate-ssh)    sshkeys::rotate_all ;;
    push-wifi)     wifi::push_to_fleet ;;
    alert)         shift; telegram::send "$*" ;;
    discover)      miners::discover ;;
    pull-logs)     logging::pull_all ;;
    status)        miners::status_overview ;;
    onboard)       shift; miners::manual_onboard "$1" ;;
    *)             echo "Unknown command: $1"; usage ;;
esac
