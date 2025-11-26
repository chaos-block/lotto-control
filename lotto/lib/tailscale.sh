tailscale::generate_ephemeral_key() {
    local key expiry
    expiry=15d
    key=$(tailscale key create --expiry $expiry --reuse=0 || true)
    if [[ -z "$key" ]]; then
        echo "Tailscale down → falling back to 90-day reusable key"
        key="$REUSABLE_KEY1"
    fi
    echo "$key"
}
