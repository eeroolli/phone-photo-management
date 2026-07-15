#!/bin/bash
# sync_traveling_photos.sh
# Sync photos from traveling staging (framobil) to normal staging dir.
# Run when back home with i/f mounts available.
#
# Usage: $0 [--dry-run] [--move] [--quiet]
#   --dry-run  Show what would be synced without copying
#   --move     Move files instead of copy (frees framobil after sync)
#   --quiet    Minimal output

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$PROJ_DIR/config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Config file $CONFIG_FILE not found!${NC}"
    exit 1
fi

source "$CONFIG_FILE"
source "$PROJ_DIR/lib/find_media_extensions.sh"

# Save configured target before resolver may change it
TARGET_DIR="$LOCAL_STAGING_DIR"
SOURCE_DIR="${TRAVELING_STAGING_DIR:-/mnt/c/Users/droll/framobil}"

# Parse options
DRY_RUN=0
MOVE_MODE=0
QUIET_MODE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --move)
            MOVE_MODE=1
            shift
            ;;
        --quiet)
            QUIET_MODE=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--dry-run] [--move] [--quiet]"
            exit 1
            ;;
    esac
done

# Verify target is on a mounted path (we must be at home)
_target_ok=0
if [[ "$TARGET_DIR" == /mnt/f/* || "$TARGET_DIR" == /mnt/f ]]; then
    mountpoint -q /mnt/f 2>/dev/null && _target_ok=1
elif [[ "$TARGET_DIR" == /mnt/i/* || "$TARGET_DIR" == /mnt/i ]]; then
    mountpoint -q /mnt/i 2>/dev/null && _target_ok=1
else
    # Target on C: or other local path - assume OK
    _target_ok=1
fi

if [[ $_target_ok -eq 0 ]]; then
    echo -e "${RED}Error: Target staging dir is on unmounted drive. Connect i/f mounts first (drive_manager connect).${NC}"
    exit 1
fi

# Verify source exists and has content
if [[ ! -d "$SOURCE_DIR" ]]; then
    echo -e "${YELLOW}Source directory empty or missing: $SOURCE_DIR. Nothing to sync.${NC}"
    exit 0
fi

_photo_count=$(find "$SOURCE_DIR" -type f "${FIND_MEDIA_FIND_ARGS[@]}" 2>/dev/null | wc -l)
if [[ $_photo_count -eq 0 ]]; then
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo -e "${YELLOW}No photos found in $SOURCE_DIR. Nothing to sync.${NC}"
    fi
    exit 0
fi

# Verify target is writable
if [[ ! -w "$TARGET_DIR" ]] && [[ -d "$TARGET_DIR" ]]; then
    echo -e "${RED}Error: Target is not writable: $TARGET_DIR${NC}"
    exit 1
fi
mkdir -p "$TARGET_DIR"

if [[ $QUIET_MODE -eq 0 ]]; then
    echo -e "${WHITE}=== Sync Traveling Photos ===${NC}"
    echo "Source: $SOURCE_DIR"
    echo "Target: $TARGET_DIR"
    echo "Photos to sync: $_photo_count"
    [[ $DRY_RUN -eq 1 ]] && echo -e "${YELLOW}(dry-run - no changes)${NC}"
    [[ $MOVE_MODE -eq 1 ]] && echo -e "${YELLOW}(move mode - will delete from source after copy)${NC}"
    echo ""
fi

# Sync with rsync, preserving folder structure
if [[ $DRY_RUN -eq 1 ]]; then
    rsync -avn "$SOURCE_DIR/" "$TARGET_DIR/"
else
    rsync -av --progress "$SOURCE_DIR/" "$TARGET_DIR/"
fi

if [[ $? -ne 0 ]]; then
    echo -e "${RED}Sync failed${NC}"
    exit 1
fi

# If move mode, remove source files after successful sync
if [[ $MOVE_MODE -eq 1 ]] && [[ $DRY_RUN -eq 0 ]]; then
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo -e "${WHITE}Removing synced files from source...${NC}"
    fi
    find "$SOURCE_DIR" -type f "${FIND_MEDIA_FIND_ARGS[@]}" -delete 2>/dev/null || true
    # Remove empty dirs
    find "$SOURCE_DIR" -type d -empty -delete 2>/dev/null || true
fi

# Log
SYNC_LOG="${PROJ_DIR}/sync_log_$(date +%Y).csv"
[[ ! -f "$SYNC_LOG" ]] && echo "timestamp,source,target,files_synced,mode,status" > "$SYNC_LOG"
_timestamp=$(date '+%Y-%m-%d %H:%M:%S')
_mode="copy"; [[ $MOVE_MODE -eq 1 ]] && _mode="move"; [[ $DRY_RUN -eq 1 ]] && _mode="dry-run"
_status="success"; [[ $DRY_RUN -eq 1 ]] && _status="dry-run"
echo "$_timestamp,$SOURCE_DIR,$TARGET_DIR,$_photo_count,$_mode,$_status" >> "$SYNC_LOG"

if [[ $QUIET_MODE -eq 0 ]]; then
    echo -e "${GREEN}Sync complete! $_photo_count files synced to $TARGET_DIR${NC}"
fi
