# epoch - convert between epoch timestamps and human-readable dates
# Usage: epoch            print current epoch
#        epoch <number>   convert epoch to local datetime
#        epoch <date>     convert date string to epoch  e.g. epoch "2026-01-15 09:00"
epoch() {
    if [[ -z "${1:-}" ]]; then
        date +%s
        return
    fi

    if [[ "$1" =~ ^[0-9]+$ ]]; then
        if [[ "$(uname)" == "Darwin" ]]; then
            date -r "$1"
        else
            date -d "@$1"
        fi
    else
        if [[ "$(uname)" == "Darwin" ]]; then
            date -j -f "%Y-%m-%d %H:%M:%S" "$*" +%s 2>/dev/null \
                || date -j -f "%Y-%m-%d %H:%M" "$*" +%s 2>/dev/null \
                || { echo "epoch: unrecognized date format" >&2; return 1; }
        else
            date -d "$*" +%s
        fi
    fi
}
