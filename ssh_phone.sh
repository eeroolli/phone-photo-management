#!/bin/bash
# ssh_phone.sh — SSH into the phone using config (Termux).
# Usage: bash ssh_phone.sh [command...]
#   No args: start interactive shell.
#   With args: run command on phone and exit.

set -e

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$PROJ_DIR/config.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Error: $CONFIG_FILE not found. Copy config.example.conf to config.conf and set DEVICE_IP, DEVICE_USER, SSH_KEY, DEVICE_PORT."
    exit 1
fi

source "$CONFIG_FILE"

exec ssh -i "$SSH_KEY" -p "${DEVICE_PORT:-8022}" -o ConnectTimeout=10 "$DEVICE_USER@$DEVICE_IP" "$@"
