#!/bin/bash
# validate_setup.sh - Quick environment check
source config.conf

echo "🔍 Validating environment..."
echo "✓ SSH key exists: $(test -f "$SSH_KEY" && echo "YES" || echo "❌ NO")"
echo "✓ SSH key permissions: $(ls -la "$SSH_KEY" | cut -d' ' -f1)"
echo "✓ Staging dir exists: $(test -d "$LOCAL_STAGING_DIR" && echo "YES" || echo "❌ NO")"
echo "✓ Can ping device: $(ping -c1 -W1 "$DEVICE_IP" &>/dev/null && echo "YES" || echo "❌ NO")"
