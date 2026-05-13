#!/bin/bash
# overview_device_photos.sh
# Overview of files on device and duplicate detection (by file size).
# Use to inspect a folder (e.g. Album Adidas) and see how many files are likely duplicates.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$PROJ_DIR/config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Config file $CONFIG_FILE not found!${NC}"
    exit 1
fi

source "$CONFIG_FILE"
source "$PROJ_DIR/lib/find_media_extensions.sh"
source "$PROJ_DIR/lib/resolve_staging_dir.sh"

# Optional: search in Pictures as well (e.g. for "Album Adidas")
DEVICE_PICTURES_DIR="${DEVICE_PICTURES_DIR:-/storage/emulated/0/Pictures}"

echo -e "${CYAN}=== Device photo overview & duplicate check ===${NC}"
echo ""

# Test SSH connection
echo -e "${WHITE}Testing connection to device...${NC}"
if ! ssh -i "$SSH_KEY" -p "$DEVICE_PORT" -o ConnectTimeout=5 "$DEVICE_USER@$DEVICE_IP" 'echo "Connection OK"' >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to device${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Connected${NC}"
echo ""

# List folders from DEVICE_PHOTO_DIR (usually DCIM)
echo -e "${WHITE}Folders in $DEVICE_PHOTO_DIR:${NC}"
FOLDERS_DCIM=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "ls -1 $DEVICE_PHOTO_DIR/ 2>/dev/null" | grep -v "^\." | sort || true)

# Optionally list folders from Pictures (e.g. Adidas album)
FOLDERS_PICTURES=""
if ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "test -d $DEVICE_PICTURES_DIR" 2>/dev/null; then
    FOLDERS_PICTURES=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "ls -1 $DEVICE_PICTURES_DIR/ 2>/dev/null" | grep -v "^\." | sort || true)
fi

# Build menu: DCIM folders, then Pictures folders (with prefix), then "All (DCIM)"
FOLDER_LIST=""
FOLDER_PATHS=()
for f in $FOLDERS_DCIM; do
    FOLDER_LIST="$FOLDER_LIST $f"
    FOLDER_PATHS+=("$DEVICE_PHOTO_DIR/$f")
done
for f in $FOLDERS_PICTURES; do
    FOLDER_LIST="$FOLDER_LIST ${f}@Pictures"
    FOLDER_PATHS+=("$DEVICE_PICTURES_DIR/$f")
done

if [[ -z "$FOLDER_LIST" ]]; then
    echo -e "${YELLOW}No folders found in $DEVICE_PHOTO_DIR${NC}"
    if [[ -n "$FOLDERS_PICTURES" ]]; then
        echo "Pictures folders: $FOLDERS_PICTURES"
    fi
    exit 1
fi

# Allow folder name as first argument (e.g. "Adidas" or "Adidas@Pictures")
SELECTED_PATH=""
if [[ -n "$1" ]]; then
    for i in "${!FOLDER_PATHS[@]}"; do
        base=$(basename "${FOLDER_PATHS[$i]}")
        if [[ "$1" == "$base" || "$1" == "$base@Pictures" ]]; then
            SELECTED_PATH="${FOLDER_PATHS[$i]}"
            break
        fi
    done
    if [[ -z "$SELECTED_PATH" ]]; then
        echo -e "${YELLOW}Folder '$1' not found. Showing menu.${NC}"
    fi
fi

if [[ -z "$SELECTED_PATH" ]]; then
    echo "Select folder (number):"
    FOLDER_ARR=($FOLDER_LIST)
    i=1
    for name in "${FOLDER_ARR[@]}"; do
        echo "  $i) $name"
        ((i++)) || true
    done
    echo -n "#? "
    read choice
    idx=$((choice - 1))
    if [[ $idx -lt 0 || $idx -ge ${#FOLDER_PATHS[@]} ]]; then
        echo -e "${RED}Invalid selection${NC}"
        exit 1
    fi
    SELECTED_PATH="${FOLDER_PATHS[$idx]}"
fi

FOLDER_NAME=$(basename "$SELECTED_PATH")
echo -e "${GREEN}Folder: $FOLDER_NAME${NC} ($SELECTED_PATH)"
echo ""

EXT_FIND="$FIND_MEDIA_INAME_PREDICATE"

# Get file list with sizes: one line per file "SIZE\tFULLPATH"
# Prefer find -printf (GNU); fallback to find + stat
echo -e "${WHITE}Scanning files (this may take a moment for large folders)...${NC}"
INVENTORY=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" \
    "find '$SELECTED_PATH' -type f $EXT_FIND -printf '%s\t%p\n' 2>/dev/null" || true)

if [[ -z "$INVENTORY" ]]; then
    # Fallback: no -printf (e.g. busybox find)
    INVENTORY=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" \
        "find '$SELECTED_PATH' -type f $EXT_FIND -exec sh -c 'printf \"%s\t%s\n\" \$(stat -c %s \"\$1\" 2>/dev/null || echo 0) \"\$1\"' _ {} \;" 2>/dev/null) || true
fi

TOTAL_FILES=$(echo "$INVENTORY" | grep -c . 2>/dev/null || true)
TOTAL_FILES=${TOTAL_FILES:-0}

if [[ $TOTAL_FILES -eq 0 ]]; then
    echo -e "${YELLOW}No photo/video files found in $FOLDER_NAME${NC}"
    exit 0
fi

echo -e "${GREEN}Total files: $TOTAL_FILES${NC}"
echo ""

# Duplicate detection by size: group by size, find sizes that appear more than once
DUP_SIZES=$(mktemp)
trap "rm -f $DUP_SIZES" EXIT

echo "$INVENTORY" | awk -F'\t' '
    NF >= 2 { count[$1]++; total++ }
    END {
        total_dup_files=0
        unique_dup_groups=0
        for (s in count) {
            if (count[s] > 1) {
                unique_dup_groups++
                total_dup_files += count[s]
                print s, count[s]
            }
        }
        print "SUMMARY", total_dup_files, unique_dup_groups
    }
' > "$DUP_SIZES"

SUMMARY_LINE=$(grep "^SUMMARY " "$DUP_SIZES" 2>/dev/null || true)
TOTAL_DUP_FILES=$(echo "$SUMMARY_LINE" | awk '{print $2}')
UNIQUE_DUP_GROUPS=$(echo "$SUMMARY_LINE" | awk '{print $3}')
TOTAL_DUP_FILES=${TOTAL_DUP_FILES:-0}
UNIQUE_DUP_GROUPS=${UNIQUE_DUP_GROUPS:-0}

# Redundant = duplicate copies beyond one per size (could remove these if confirmed duplicates)
REDUNDANT_COPIES=$((TOTAL_DUP_FILES - UNIQUE_DUP_GROUPS))

echo -e "${WHITE}--- Duplicate analysis (by file size) ---${NC}"
echo "  Total files:              $TOTAL_FILES"
echo "  Duplicate size groups:    $UNIQUE_DUP_GROUPS (sizes that appear more than once)"
echo "  Files in those groups:    $TOTAL_DUP_FILES"
echo "  Likely redundant copies:  $REDUNDANT_COPIES (files that could be removed if duplicates)"
echo "  Likely unique (by size):  $((TOTAL_FILES - REDUNDANT_COPIES))"
echo ""

if [[ $UNIQUE_DUP_GROUPS -gt 0 ]]; then
    echo -e "${WHITE}Sample duplicate groups (same size = possible duplicates):${NC}"
    while read -r size count; do
        [[ "$size" == SUMMARY* ]] && continue
        echo -e "${BLUE}  Size $size bytes: $count files${NC}"
        echo "$INVENTORY" | awk -F'\t' -v s="$size" 'NF>=2 && $1==s {print "    " $2}' | head -5
        [[ $count -gt 5 ]] && echo "    ... and $((count - 5)) more"
        echo ""
    done < "$DUP_SIZES" | head -40
    echo -e "${YELLOW}Note: Same size does not guarantee same content. For certainty, run a hash-based check.${NC}"
else
    echo -e "${GREEN}No duplicate sizes found — all files have unique sizes (no obvious duplicates).${NC}"
fi

echo ""
echo -e "${GREEN}Overview complete.${NC}"
