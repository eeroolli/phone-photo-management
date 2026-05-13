# find_media_extensions.sh
# After sourcing config.conf, source this file to set FIND_MEDIA_INAME_PREDICATE
# for use inside find: find DIR -type f $FIND_MEDIA_INAME_PREDICATE ...
#
# MEDIA_EXTENSIONS: space-separated list without dots, e.g. "jpg jpeg mp4 heic".
# Case-insensitive matching via -iname.

: "${MEDIA_EXTENSIONS:=jpg jpeg png mp4 mov}"

FIND_MEDIA_INAME_PREDICATE=""
_first_media_ext=1
for _ext in $MEDIA_EXTENSIONS; do
    _e="${_ext#.}"
    _e=$(printf '%s' "$_e" | tr '[:upper:]' '[:lower:]')
    if [[ $_first_media_ext -eq 1 ]]; then
        FIND_MEDIA_INAME_PREDICATE="\( -iname '*.$_e'"
        _first_media_ext=0
    else
        FIND_MEDIA_INAME_PREDICATE="$FIND_MEDIA_INAME_PREDICATE -o -iname '*.$_e'"
    fi
done
FIND_MEDIA_INAME_PREDICATE="$FIND_MEDIA_INAME_PREDICATE \)"

unset _ext _e _first_media_ext
