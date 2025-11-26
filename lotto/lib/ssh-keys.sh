sshkeys::rotate_all() {
    miners::discover
    jq -r '.[].hostname' "$MINERS_JSON" | while read -r host; do
        echo "Rotating SSH keys on $host"
        ssh -o ConnectTimeout=10 "$host" '
            sudo mv /home/miner/.ssh/authorized_keys.B /home/miner/.ssh/authorized_keys
            sudo systemctl restart ssh
        ' || echo "$host offline – will catch up on next boot"
    done
    telegram::send "SSH keys rotated fleet-wide"
}
