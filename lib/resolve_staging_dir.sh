# resolve_staging_dir.sh
# Resolves effective staging directory based on mount availability.
# Use when LOCAL_STAGING_DIR may be on /mnt/f or /mnt/i (network drives) that are
# unmounted when traveling. Falls back to TRAVELING_STAGING_DIR when needed.
#
# Source this after config.conf. Sets:
#   LOCAL_STAGING_DIR - effective dir to use (may be overwritten)
#   STAGING_MODE - "normal" or "traveling"

# Default traveling dir if not in config
TRAVELING_STAGING_DIR="${TRAVELING_STAGING_DIR:-/mnt/c/Users/droll/framobil}"

_effective_dir="$LOCAL_STAGING_DIR"
_staging_mode="normal"

# Check if LOCAL_STAGING_DIR is under /mnt/f and if /mnt/f is mounted
if [[ "$LOCAL_STAGING_DIR" == /mnt/f/* || "$LOCAL_STAGING_DIR" == /mnt/f ]]; then
    if ! mountpoint -q /mnt/f 2>/dev/null; then
        _effective_dir="$TRAVELING_STAGING_DIR"
        _staging_mode="traveling"
    fi
# Check if LOCAL_STAGING_DIR is under /mnt/i and if /mnt/i is mounted
elif [[ "$LOCAL_STAGING_DIR" == /mnt/i/* || "$LOCAL_STAGING_DIR" == /mnt/i ]]; then
    if ! mountpoint -q /mnt/i 2>/dev/null; then
        _effective_dir="$TRAVELING_STAGING_DIR"
        _staging_mode="traveling"
    fi
fi

# Apply resolution
LOCAL_STAGING_DIR="$_effective_dir"
STAGING_MODE="$_staging_mode"

# Create traveling dir if needed when using it
if [[ "$STAGING_MODE" == "traveling" ]]; then
    mkdir -p "$LOCAL_STAGING_DIR"
    if [[ "${QUIET_MODE:-0}" -eq 0 ]]; then
        echo -e "\033[1;33mTraveling mode: using $LOCAL_STAGING_DIR (i/f mounts not available)\033[0m"
    fi
fi
