# photo_hash_state.sh
# Plain-file hash registry + append-only audit (per pipeline under PHOTO_HASH_STATE_DIR).
# Source after config.conf; requires HASH_PIPELINE_SLUG and PHOTO_HASH_STATE_DIR when used.
#
# Registry: tab-separated registry_known.tsv (sha256, source, path) — avoids CSV quoting issues.
# Audit:    tab-separated rows in audit/transfer_audit_YYYY_<slug>.csv (tabs for path safety; opens in spreadsheets)

photo_hash_state_enabled() {
    [[ -n "${PHOTO_HASH_STATE_DIR:-}" && -n "${HASH_PIPELINE_SLUG:-}" ]]
}

photo_hash_state_pipeline_root() {
    if [[ -z "${PHOTO_HASH_STATE_DIR:-}" || -z "${HASH_PIPELINE_SLUG:-}" ]]; then
        return 1
    fi
    printf '%s' "${PHOTO_HASH_STATE_DIR%/}/${HASH_PIPELINE_SLUG}"
}

photo_hash_state_init() {
    local root
    root="$(photo_hash_state_pipeline_root)" || return 1
    mkdir -p "$root/audit"
    local reg="$root/registry_known.tsv"
    if [[ ! -f "$reg" ]]; then
        printf '%s\t%s\t%s\n' "sha256" "source" "path" > "$reg"
    fi
}

# stdout: lowercase hex sha256
photo_hash_local_file() {
    local f="$1"
    if ! command -v sha256sum >/dev/null 2>&1; then
        echo "photo_hash_state: sha256sum not found" >&2
        return 1
    fi
    sha256sum "$f" | awk '{print $1}'
}

photo_hash_registry_path() {
    local root
    root="$(photo_hash_state_pipeline_root)" || return 1
    printf '%s/registry_known.tsv' "$root"
}

# Match sha256 in first column (exact); skip header
photo_hash_registry_has_sha256() {
    local sha="$1"
    local reg
    reg="$(photo_hash_registry_path)" || return 1
    [[ -f "$reg" ]] || return 1
    grep -qE "^${sha}	" "$reg"
}

# Upsert row for sha256 (tab-separated)
photo_hash_registry_put_sha256() {
    local sha="$1" source="$2" path="${3:-}"
    local reg root tmp
    root="$(photo_hash_state_pipeline_root)" || return 1
    reg="$root/registry_known.tsv"
    tmp="$(mktemp)"
    [[ -f "$reg" ]] || photo_hash_state_init || return 1
    awk -F'\t' -v s="$sha" 'BEGIN{OFS="\t"} NR==1{print; next} $1!=s{print}' "$reg" > "$tmp"
    printf '%s\t%s\t%s\n' "$sha" "$source" "$path" >> "$tmp"
    mv -f "$tmp" "$reg"
}

photo_hash_audit_path() {
    local y="${1:-$(date +%Y)}"
    local root
    root="$(photo_hash_state_pipeline_root)" || return 1
    printf '%s/audit/transfer_audit_%s_%s.csv' "$root" "$y" "${HASH_PIPELINE_SLUG}"
}

# Append one audit row (tab-separated). Creates file with header if missing.
photo_hash_append_transfer_audit() {
    local op="$1" src="$2" dst="$3" sha="$4" size_bytes="$5"
    local audit y
    y=$(date +%Y)
    audit="$(photo_hash_audit_path "$y")" || return 1
    mkdir -p "$(dirname "$audit")"
    if [[ ! -f "$audit" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
            "timestamp" "pipeline" "op" "source_path" "dest_path" "sha256" "size_bytes" > "$audit"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "${HASH_PIPELINE_SLUG}" "$op" "$src" "$dst" "$sha" "$size_bytes" >> "$audit"
}
