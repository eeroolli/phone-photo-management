#!/bin/bash
# validate_setup.sh - Quick environment check
PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$PROJ_DIR/config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "❌ Config file not found: $CONFIG_FILE"
    exit 1
fi

source "$CONFIG_FILE"
source "$PROJ_DIR/lib/resolve_staging_dir.sh"

echo "🔍 Validating environment..."
echo "✓ SSH key exists: $(test -f "$SSH_KEY" && echo "YES" || echo "❌ NO")"
echo "✓ SSH key permissions: $(ls -la "$SSH_KEY" 2>/dev/null | cut -d' ' -f1 || echo "N/A")"
echo "✓ Staging dir exists: $(test -d "$LOCAL_STAGING_DIR" && echo "YES" || echo "❌ NO")"
echo "✓ Staging mode: $STAGING_MODE"
_traveling_dir="${TRAVELING_STAGING_DIR:-/mnt/c/Users/droll/framobil}"
echo "✓ Traveling fallback ready: $(test -d "$_traveling_dir" && echo "YES" || echo "❌ NO (create: mkdir -p $_traveling_dir)")"
echo "✓ /mnt/f mounted: $(mountpoint -q /mnt/f 2>/dev/null && echo "YES" || echo "NO")"
echo "✓ /mnt/i mounted: $(mountpoint -q /mnt/i 2>/dev/null && echo "YES" || echo "NO")"
echo "✓ Can ping device: $(ping -c1 -W1 "$DEVICE_IP" &>/dev/null && echo "YES" || echo "❌ NO")"
