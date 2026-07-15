#!/bin/bash
# build_import_index.sh
# Walk LIGHTROOM_IMPORTED_ROOT (and optional LIGHTROOM_IMPORTED_ROOT_EXTRA), hash media files,
# and upsert into per-pipeline registry under PHOTO_HASH_STATE_DIR.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJ_DIR/config.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error: $CONFIG_FILE not found${NC}"
    exit 1
fi

source "$CONFIG_FILE"
source "$PROJ_DIR/lib/find_media_extensions.sh"
source "$PROJ_DIR/lib/photo_hash_state.sh"

if [[ -z "${LIGHTROOM_IMPORTED_ROOT:-}" ]]; then
    echo -e "${RED}Error: LIGHTROOM_IMPORTED_ROOT must be set in config.conf${NC}"
    exit 1
fi
if ! photo_hash_state_enabled; then
    echo -e "${RED}Error: PHOTO_HASH_STATE_DIR and HASH_PIPELINE_SLUG must be set${NC}"
    exit 1
fi
if ! command -v sha256sum >/dev/null 2>&1; then
    echo -e "${RED}Error: sha256sum not found in PATH${NC}"
    exit 1
fi

if [[ ! -d "$LIGHTROOM_IMPORTED_ROOT" ]]; then
    echo -e "${RED}Error: LIGHTROOM_IMPORTED_ROOT is not a directory: $LIGHTROOM_IMPORTED_ROOT${NC}"
    exit 1
fi

if [[ -n "${LIGHTROOM_IMPORTED_ROOT_EXTRA:-}" && ! -d "$LIGHTROOM_IMPORTED_ROOT_EXTRA" ]]; then
    echo -e "${RED}Error: LIGHTROOM_IMPORTED_ROOT_EXTRA is not a directory: $LIGHTROOM_IMPORTED_ROOT_EXTRA${NC}"
    exit 1
fi

if ! photo_hash_state_ensure_writable; then
    echo -e "${RED}Error: cannot create or write hash state directory (check PHOTO_HASH_STATE_DIR in config.conf)${NC}"
    exit 1
fi

photo_hash_state_init

_interval="${PHOTO_HASH_INDEX_PROGRESS_INTERVAL:-100}"
_processed=0

echo -e "${WHITE}Building import index for pipeline: ${HASH_PIPELINE_SLUG}${NC}"
echo -e "${WHITE}Registry: $(photo_hash_registry_path)${NC}"
echo -e "${WHITE}Roots:${NC} $LIGHTROOM_IMPORTED_ROOT"
[[ -n "${LIGHTROOM_IMPORTED_ROOT_EXTRA:-}" ]] && echo "         $LIGHTROOM_IMPORTED_ROOT_EXTRA"
echo ""

process_file() {
    local f="$1"
    local sha size
    sha=$(photo_hash_local_file "$f") || return 1
    size=$(stat -c%s "$f" 2>/dev/null || echo 0)
    photo_hash_registry_put_sha256 "$sha" "import" "$f"
    _processed=$((_processed + 1))
    if [[ $((_processed % _interval)) -eq 0 ]]; then
        echo -e "${GREEN}  hashed $_processed files (latest: $(basename "$f"))${NC}"
    fi
}

# Export for subshell if we used one — keep inline loop
while IFS= read -r -d '' f; do
    process_file "$f"
done < <(
    find "$LIGHTROOM_IMPORTED_ROOT" -type f "${FIND_MEDIA_FIND_ARGS[@]}" -print0
    if [[ -n "${LIGHTROOM_IMPORTED_ROOT_EXTRA:-}" ]]; then
        find "$LIGHTROOM_IMPORTED_ROOT_EXTRA" -type f "${FIND_MEDIA_FIND_ARGS[@]}" -print0
    fi
)

echo ""
if [[ $_processed -eq 0 ]]; then
    _probe=$(find "$LIGHTROOM_IMPORTED_ROOT" -type f -iname '*.jpg' 2>/dev/null | head -1 || true)
    if [[ -n "$_probe" ]]; then
        echo -e "${YELLOW}Warning: 0 media files hashed, but jpg files exist under the import root.${NC}"
        echo -e "${YELLOW}         Check MEDIA_EXTENSIONS in config.conf or find errors above.${NC}"
    fi
fi
echo -e "${GREEN}Done. Total files hashed: $_processed${NC}"
