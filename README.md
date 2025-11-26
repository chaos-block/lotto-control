# Directory structure
/opt/lotto-control/
├── lotto-control.sh                # Main entrypoint (wrapper)
├── config/
│   └── config.sh                   # All configurable values
├── lib/
│   ├── tailscale.sh                # Tailscale key management
│   ├── ssh-keys.sh                 # Per-miner SSH key rotation
│   ├── wifi-push.sh                # Centralized Wi-Fi policy push
│   ├── telegram.sh                 # Alerting
│   ├── miners.sh                   # Miner discovery & inventory
│   └── logging.sh                  # Central log pull
├── data/
│   ├── known-networks.json.enc     # Your encrypted Wi-Fi policy (age encrypt)
│   ├── miners.json                 # Live inventory (auto-generated)
│   ├── reusable-keys/              # Two 90-day reusable Tailscale keys
│   └── offline-recovery-key/       # Key-C (never rotates)
├── bin/
│   └── fleet-manager.sh            # Symlink to ../lotto-control.sh
└── README.md
