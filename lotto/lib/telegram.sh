telegram::send() {
    local message="$*"
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        -d chat_id="$TELEGRAM_CHAT_ID" \
        -d parse_mode="HTML" \
        -d text="<b>Lotto Fleet</b> $(hostname): $message" > /dev/null
}
