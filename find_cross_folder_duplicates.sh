#!/bin/bash
# find_cross_folder_duplicates.sh
# Find files in a target folder (e.g. Adidas) that have the same name as a file elsewhere on the device.
# Uses filenames only (no hashing) so it's fast even for thousands of files.
#
# Use case: You accidentally copied 2000 files into Adidas; find which ones exist elsewhere by name
# so you can safely delete or move the duplicates from Adidas.
#
# Options: --dry-run, -n  Simulate cleanup (log actions only, no delete/move on device).
# Config: CROSS_DUP_TARGET_DIR, CROSS_DUP_REFERENCE_DIRS, CROSS_DUP_LOG. Pattern → destination rules are defined in the script when you apply cleanup.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

DRY_RUN=0
for arg in "$@"; do
    if [[ "$arg" == --dry-run || "$arg" == -n ]]; then
        DRY_RUN=1
        break
    fi
done

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$PROJ_DIR/config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Config file $CONFIG_FILE not found!${NC}"
    exit 1
fi

source "$CONFIG_FILE"
source "$PROJ_DIR/lib/find_media_extensions.sh"

# Target folder to clean (files here that exist elsewhere by name can be removed)
TARGET_DIR="${CROSS_DUP_TARGET_DIR:-/storage/emulated/0/Pictures/Gallery/owner/Adidas}"

# Log file for cleanup actions (append)
CROSS_DUP_LOG="${CROSS_DUP_LOG:-$PROJ_DIR/cross_dup_$(date +%Y%m%d).log}"

# Space-separated list of directories to compare against (where "originals" live)
CROSS_DUP_REFERENCE_DIRS="${CROSS_DUP_REFERENCE_DIRS:-$DEVICE_PHOTO_DIR}"
REFERENCE_DIRS=($CROSS_DUP_REFERENCE_DIRS)

FIND_EXTS="$FIND_MEDIA_INAME_PREDICATE"

# Output file: paths in TARGET that are duplicates (one per line), for use with a delete script
OUTPUT_LIST="${CROSS_DUP_OUTPUT_LIST:-$PROJ_DIR/duplicates_to_remove.txt}"

echo -e "${CYAN}=== Cross-folder duplicate finder (by filename) ===${NC}"
[[ $DRY_RUN -eq 1 ]] && echo -e "${YELLOW}(dry-run: no changes will be made)${NC}"
echo ""
echo -e "${WHITE}Target folder (to clean):${NC}  $TARGET_DIR"
echo -e "${WHITE}Reference folders (originals):${NC}  ${REFERENCE_DIRS[*]}"
echo ""

# Test SSH connection
echo -e "${WHITE}Testing connection to device...${NC}"
if ! ssh -i "$SSH_KEY" -p "$DEVICE_PORT" -o ConnectTimeout=5 "$DEVICE_USER@$DEVICE_IP" 'echo "OK"' >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to device${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Connected${NC}"
echo ""

# Build find command for multiple dirs (output full path)
build_find_paths() {
    local dirs=("$@")
    local first=1
    local cmd=""
    for d in "${dirs[@]}"; do
        [[ -z "$d" ]] && continue
        if [[ $first -eq 1 ]]; then
            cmd="find '$d' -type f $FIND_EXTS -print 2>/dev/null"
            first=0
        else
            cmd="$cmd; find '$d' -type f $FIND_EXTS -print 2>/dev/null"
        fi
    done
    echo "$cmd"
}

# Step 1: List all files in TARGET_DIR (full paths)
# On some devices (e.g. Redmi/Xiaomi) Gallery uses "Owner" (capital O) not "owner"
echo -e "${WHITE}[1/3] Listing files in target folder...${NC}"
TARGET_PATHS=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" \
    "find '$TARGET_DIR' -type f $FIND_EXTS -print 2>/dev/null" | sort -u || true)

TARGET_COUNT=$(echo "$TARGET_PATHS" | grep -c . 2>/dev/null || true)
TARGET_COUNT=${TARGET_COUNT:-0}

FOUND_VIA_ALT=0
# If 0 files, try alternate casing (Gallery often uses "Owner" not "owner")
if [[ $TARGET_COUNT -eq 0 ]] && [[ "$TARGET_DIR" == *"/owner/"* ]]; then
    TARGET_DIR_ALT="${TARGET_DIR//\/owner\//\/Owner\/}"
    echo -e "${YELLOW}  No files in $TARGET_DIR; trying Gallery 'Owner' path...${NC}"
    TARGET_PATHS=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" \
        "find '$TARGET_DIR_ALT' -type f $FIND_EXTS -print 2>/dev/null" | sort -u || true)
    TARGET_COUNT=$(echo "$TARGET_PATHS" | grep -c . 2>/dev/null || true)
    TARGET_COUNT=${TARGET_COUNT:-0}
    if [[ $TARGET_COUNT -gt 0 ]]; then
        TARGET_DIR="$TARGET_DIR_ALT"
        FOUND_VIA_ALT=1
        echo -e "${GREEN}  Found $TARGET_COUNT files using: $TARGET_DIR${NC}"
        echo -e "${YELLOW}  Tip: set CROSS_DUP_TARGET_DIR=\"$TARGET_DIR\" in config to use this path directly.${NC}"
    fi
fi
# If still 0 files, try path with trailing space (Redmi Gallery uses "Adidas ", "owner " etc.)
if [[ $TARGET_COUNT -eq 0 ]] && [[ "${TARGET_DIR: -1}" != " " ]]; then
    for try in "${TARGET_DIR} " "${TARGET_DIR%/*} /${TARGET_DIR##*/} "; do
        [[ $TARGET_COUNT -gt 0 ]] && break
        echo -e "${YELLOW}  Trying path with trailing space: \"$try\"${NC}"
        TARGET_PATHS=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" \
            "find '$try' -type f $FIND_EXTS -print 2>/dev/null" | sort -u || true)
        TARGET_COUNT=$(echo "$TARGET_PATHS" | grep -c . 2>/dev/null || true)
        TARGET_COUNT=${TARGET_COUNT:-0}
        if [[ $TARGET_COUNT -gt 0 ]]; then
            TARGET_DIR="$try"
            FOUND_VIA_ALT=1
            echo -e "${GREEN}  Found $TARGET_COUNT files using: \"$TARGET_DIR\"${NC}"
            echo -e "${YELLOW}  Tip: set CROSS_DUP_TARGET_DIR=\"$TARGET_DIR\" in config (path has trailing space).${NC}"
        fi
    done
fi

if [[ $TARGET_COUNT -eq 0 ]]; then
    echo -e "${GREEN}  Found $TARGET_COUNT files in target.${NC}"
    echo ""
    echo -e "${YELLOW}No files in target folder. Nothing to compare.${NC}"
    echo ""
    echo -e "${WHITE}Diagnostic: running find again (errors shown):${NC}"
    ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "find '$TARGET_DIR' -type f $FIND_EXTS -print 2>&1" | head -20 | sed 's/^/    /' || true
    echo ""
    echo -e "${WHITE}Path discovery (actual folders on device):${NC}"
    GALLERY_PARENT="${TARGET_DIR%/*/*}"   # e.g. /storage/emulated/0/Pictures/Gallery
    echo "  Contents of $GALLERY_PARENT:"
    ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "ls -la $GALLERY_PARENT 2>/dev/null" | sed 's/^/    /' || true
    PARENT_OF_TARGET="${TARGET_DIR%/*}"   # e.g. .../Gallery/owner or .../Gallery/Owner
    if [[ "$PARENT_OF_TARGET" != "$GALLERY_PARENT" ]]; then
        echo "  Contents of $PARENT_OF_TARGET:"
        ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "ls -la $PARENT_OF_TARGET 2>/dev/null" | sed 's/^/    /' || true
    fi
    echo "  Sample files in target (ls):"
    ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "ls '$TARGET_DIR' 2>&1 | head -5" | sed 's/^/    /' || true
    echo ""
    echo -e "${YELLOW}If you see 'Permission denied': Gallery folders are often owned by root and only readable by the Gallery app.${NC}"
    echo -e "${YELLOW}In Termux, run: termux-setup-storage and ensure storage permission is granted; or use File Manager / Settings to fix media permissions.${NC}"
    echo -e "${YELLOW}Otherwise set CROSS_DUP_TARGET_DIR to a folder your SSH user can read (check casing, e.g. Owner vs owner).${NC}"
    exit 0
fi

[[ $FOUND_VIA_ALT -eq 0 ]] && echo -e "${GREEN}  Found $TARGET_COUNT files in target.${NC}"
echo ""

# Step 2: List basenames (filenames) in REFERENCE dirs — these are the "existing" names
echo -e "${WHITE}[2/3] Listing filenames in reference folders...${NC}"
REF_CMD=$(build_find_paths "${REFERENCE_DIRS[@]}")
REF_PATHS=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "$REF_CMD" | sort -u || true)

# Exclude paths under TARGET_DIR so we don't match target against itself
REF_NAMES=$(mktemp)
REF_NAME_TO_PATH=$(mktemp)
trap "rm -f $REF_NAMES $REF_NAME_TO_PATH" EXIT
while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    [[ "$path" == "$TARGET_DIR"* ]] && continue
    name=$(basename "$path")
    echo "$name" >> "$REF_NAMES"
    # Keep first path we see for this name (for report)
    if ! grep -q "^${name}|" "$REF_NAME_TO_PATH" 2>/dev/null; then
        echo "$name|$path" >> "$REF_NAME_TO_PATH"
    fi
done <<< "$REF_PATHS"

# Build unique set of reference names for fast lookup
sort -u "$REF_NAMES" > "${REF_NAMES}.tmp" && mv "${REF_NAMES}.tmp" "$REF_NAMES"
echo -e "${GREEN}  Found $(wc -l < "$REF_NAMES") unique filenames in reference.${NC}"
echo ""

# Step 3: Find target files whose basename exists in reference; collect all non-duplicates (pattern→dest chosen later)
echo -e "${WHITE}[3/3] Comparing by filename...${NC}"
> "$OUTPUT_LIST"
NON_DUP_LIST=$(mktemp)
trap "rm -f $REF_NAMES $REF_NAME_TO_PATH $NON_DUP_LIST" EXIT
DUP_COUNT=0
NON_DUP_COUNT=0
DUP_SAMPLE=""

while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    name=$(basename "$path")
    if grep -qFx "$name" "$REF_NAMES" 2>/dev/null; then
        ((DUP_COUNT++)) || true
        echo "$path" >> "$OUTPUT_LIST"
        if [[ $DUP_COUNT -le 10 ]]; then
            ref_path=$(grep "^${name}|" "$REF_NAME_TO_PATH" 2>/dev/null | head -1 | cut -d'|' -f2-)
            DUP_SAMPLE="$DUP_SAMPLE  → $path"$'\n'"    same name as: $ref_path"$'\n'
        fi
    else
        ((NON_DUP_COUNT++)) || true
        echo "$path" >> "$NON_DUP_LIST"
    fi
done <<< "$TARGET_PATHS"

# Duplicates only within target (same basename appears 2+ times in target)
WITHIN_STATS=$(echo "$TARGET_PATHS" | while IFS= read -r p; do basename "$p"; done | sort | uniq -c | awk '$1>1 {extra+=$1-1; groups++} END {print groups+0, extra+0}')
WITHIN_COUNT=$(echo "$WITHIN_STATS" | awk '{print $1}')
WITHIN_EXTRA=$(echo "$WITHIN_STATS" | awk '{print $2}')
WITHIN_COUNT=${WITHIN_COUNT:-0}
WITHIN_EXTRA=${WITHIN_EXTRA:-0}

# --- Report ---
echo ""
echo -e "${CYAN}--- Result ---${NC}"
echo ""
echo -e "  Total files in target:     $TARGET_COUNT"
echo -e "  Same name in reference:    $DUP_COUNT (filename exists in reference folders)"
echo -e "  Non-duplicates:            $NON_DUP_COUNT (you define pattern → destination when you apply)"
echo -e "  Same name only in target:  $WITHIN_EXTRA (repeated name within target; keep one, remove $WITHIN_EXTRA)"
echo ""

if [[ $DUP_COUNT -gt 0 ]]; then
    echo -e "${GREEN}These $DUP_COUNT files in the target folder have the same name as a file in reference. Safe to delete from target.${NC}"
    echo ""
    echo -e "${WHITE}Paths written to: $OUTPUT_LIST${NC}"
    echo "  (One path per line; use for a delete script or manual review.)"
    echo ""
    if [[ -n "$DUP_SAMPLE" ]]; then
        echo -e "${WHITE}Sample (first few):${NC}"
        echo "$DUP_SAMPLE" | head -22
    fi
else
    echo -e "${YELLOW}No files in target had the same name as any file in reference folders.${NC}"
fi

if [[ $WITHIN_EXTRA -gt 0 ]]; then
    echo ""
    echo -e "${WHITE}Within target: $WITHIN_EXTRA files share a name with another file in the same folder.${NC}"
    echo "  (You can keep one per name and remove the rest.)"
fi

# Option: delete duplicates and move non-duplicates (define pattern → destination in a loop)
if [[ $DUP_COUNT -gt 0 || $NON_DUP_COUNT -gt 0 ]]; then
    echo ""
    echo -e "${CYAN}--- Cleanup option ---${NC}"
    echo "  Duplicates (same name in reference):  delete from target"
    echo "  Non-duplicates: define one pattern at a time and where it goes; files not matching any pattern stay in target"
    [[ $DRY_RUN -eq 1 ]] && echo -e "  ${YELLOW}Dry-run: actions will be logged only, no changes on device.${NC}"
    echo ""
    echo -e "  Will delete: ${RED}$DUP_COUNT${NC} files"
    echo -e "  Non-duplicates: ${GREEN}$NON_DUP_COUNT${NC} (you'll add pattern → destination rules when you apply)"
    echo ""
    echo -ne "Apply cleanup? Delete duplicates and define move rules (y/N): "
    read apply
    if [[ "$apply" =~ ^[Yy]$ ]]; then
        # Collect pattern → destination pairs (interactive loop)
        MOVE_PATTERNS=()
        MOVE_DESTS=()
        if [[ $NON_DUP_COUNT -gt 0 ]]; then
            echo ""
            echo -e "${WHITE}Add move rules: pattern (filename glob) then destination folder. Empty pattern to finish.${NC}"
            while true; do
                echo -ne "  Pattern (e.g. IMG* or VID* or Screenshot*; empty to finish): "
                read pat
                pat=$(echo "$pat" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [[ -z "$pat" ]] && break
                echo -ne "  Destination folder for files matching $pat: "
                read dest
                dest=$(echo "$dest" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                [[ -z "$dest" ]] && echo "  Skipped (empty destination)." && continue
                MOVE_PATTERNS+=("$pat")
                MOVE_DESTS+=("$dest")
                echo -e "  ${GREEN}Rule: $pat → $dest${NC}"
            done
        fi
        echo ""

        # Log file: append with header and one line per action
        LOG_HEADER="$(date '+%Y-%m-%dT%H:%M:%S%z') target=$TARGET_DIR dry_run=$DRY_RUN"
        echo "--- $LOG_HEADER ---" >> "$CROSS_DUP_LOG"
        ACTION_PREFIX=""
        [[ $DRY_RUN -eq 1 ]] && ACTION_PREFIX="would_"

        if [[ $DUP_COUNT -gt 0 ]]; then
            echo -e "${WHITE}Deleting $DUP_COUNT duplicates on device...${NC}"
            if [[ $DRY_RUN -eq 1 ]]; then
                while IFS= read -r p; do
                    [[ -z "$p" ]] && continue
                    echo "${ACTION_PREFIX}delete	$p" >> "$CROSS_DUP_LOG"
                    echo "  Would delete: $p"
                done < "$OUTPUT_LIST"
                echo -e "${GREEN}  (dry-run) Logged $DUP_COUNT deletes.${NC}"
            else
                while IFS= read -r p; do
                    [[ -z "$p" ]] && continue
                    echo "delete	$p" >> "$CROSS_DUP_LOG"
                done < "$OUTPUT_LIST"
                cat "$OUTPUT_LIST" | ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" \
                    'while IFS= read -r p; do [ -n "$p" ] && rm -f "$p"; done'
                echo -e "${GREEN}  Deleted.${NC}"
            fi
        fi

        if [[ $NON_DUP_COUNT -gt 0 ]] && [[ ${#MOVE_PATTERNS[@]} -gt 0 ]]; then
            # Assign each non-dup to first matching pattern; build per-dest lists
            MOVE_TMP=$(mktemp -d)
            for i in "${!MOVE_DESTS[@]}"; do
                : > "$MOVE_TMP/move_$i.list"
            done
            ASSIGNED=$(mktemp)
            trap "rm -f $REF_NAMES $REF_NAME_TO_PATH $NON_DUP_LIST $ASSIGNED; rm -rf $MOVE_TMP" EXIT
            while IFS= read -r path; do
                [[ -z "$path" ]] && continue
                name=$(basename "$path")
                for i in "${!MOVE_PATTERNS[@]}"; do
                    if [[ "$name" == ${MOVE_PATTERNS[i]} ]]; then
                        echo "$path" >> "$MOVE_TMP/move_$i.list"
                        echo "$path" >> "$ASSIGNED"
                        break
                    fi
                done
            done < "$NON_DUP_LIST"
            # Execute moves per destination
            for i in "${!MOVE_DESTS[@]}"; do
                list="$MOVE_TMP/move_$i.list"
                dest="${MOVE_DESTS[i]}"
                cnt=$(grep -c . "$list" 2>/dev/null || true)
                cnt=${cnt:-0}
                [[ "$cnt" -eq 0 ]] && continue
                echo -e "${WHITE}Moving $cnt files matching ${MOVE_PATTERNS[i]} to $dest ...${NC}"
                if [[ $DRY_RUN -eq 1 ]]; then
                    while IFS= read -r p; do
                        [[ -z "$p" ]] && continue
                        echo "${ACTION_PREFIX}move	$p	$dest" >> "$CROSS_DUP_LOG"
                        echo "  Would move: $p -> $dest/"
                    done < "$list"
                    echo -e "${GREEN}  (dry-run) Logged.${NC}"
                else
                    while IFS= read -r p; do
                        [[ -z "$p" ]] && continue
                        echo "move	$p	$dest" >> "$CROSS_DUP_LOG"
                    done < "$list"
                    DEST_QUOTED=$(printf '%q' "$dest")
                    cat "$list" | ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" \
                        "mkdir -p $DEST_QUOTED; while IFS= read -r p; do [ -n \"\$p\" ] && mv -f \"\$p\" $DEST_QUOTED/; done"
                    echo -e "${GREEN}  Moved.${NC}"
                fi
            done
        elif [[ $NON_DUP_COUNT -gt 0 ]] && [[ ${#MOVE_PATTERNS[@]} -eq 0 ]]; then
            echo -e "${YELLOW}No move rules defined; $NON_DUP_COUNT non-duplicates left in target.${NC}"
        fi
        echo -e "${WHITE}Log: $CROSS_DUP_LOG${NC}"
        echo -e "${GREEN}Cleanup done.${NC}"
    else
        echo "No changes made."
    fi
fi

echo ""
echo -e "${GREEN}Done.${NC}"
