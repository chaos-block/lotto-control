miners::discover() {
    tailscale status --json > /tmp/ts.json
    jq -r '.Peer[] | select(.Tags? // [] | index("tag:lotto")) | .DNSName' /tmp/ts.json |
    sed 's/\.$//' > /tmp/lotto-hosts.txt

    echo '[]' > "$MINERS_JSON"
    while read -r fqdn; do
        host="${fqdn%%.*}"
        serial=$(ssh -o ConnectTimeout=10 "$fqdn" 'cat /proc/cpuinfo | grep Serial | cut -d: -f2 | xargs')
        nickname="Lucky-${serial: -4}"
        jq --arg h "$fqdn" --arg n "$nickname" '. += [{hostname: $h, nickname: $n, last_seen: now}]' "$MINERS_JSON" > "$MINERS_JSON.new"
        mv "$MINERS_JSON.new" "$MINERS_JSON"
    done < /tmp/lotto-hosts.txt
}
