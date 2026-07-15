# find_media_extensions.sh
# After sourcing config.conf, source this file to set:
#   FIND_MEDIA_FIND_ARGS   — bash array for local find (safe unquoted expansion)
#   FIND_MEDIA_INAME_PREDICATE — string for SSH/remote command embedding in quotes
#
# MEDIA_EXTENSIONS: space-separated list without dots, e.g. "jpg jpeg mp4 heic".
# Case-insensitive matching via -iname.

: "${MEDIA_EXTENSIONS:=jpg jpeg png mp4 mov}"

FIND_MEDIA_FIND_ARGS=( '(' )
FIND_MEDIA_INAME_PREDICATE=""
_first_media_ext=1
for _ext in $MEDIA_EXTENSIONS; do
    _e="${_ext#.}"
    _e=$(printf '%s' "$_e" | tr '[:upper:]' '[:lower:]')
    if [[ $_first_media_ext -eq 1 ]]; then
        FIND_MEDIA_FIND_ARGS+=( '-iname' "*.$_e" )
        FIND_MEDIA_INAME_PREDICATE="\( -iname '*.$_e'"
        _first_media_ext=0
    else
        FIND_MEDIA_FIND_ARGS+=( '-o' '-iname' "*.$_e" )
        FIND_MEDIA_INAME_PREDICATE="$FIND_MEDIA_INAME_PREDICATE -o -iname '*.$_e'"
    fi
done
FIND_MEDIA_FIND_ARGS+=( ')' )
FIND_MEDIA_INAME_PREDICATE="$FIND_MEDIA_INAME_PREDICATE \)"

unset _ext _e _first_media_ext
