# dmsg - dmesg with human-readable timestamps, optional time window and level filter
# Usage: dmsg [minutes] [level]
#   minutes  show only last N minutes (no-pager); omit for full output (pager)
#   level    filter by log level: emerg,alert,crit,err,warn,notice,info,debug
# Examples:
#   dmsg             full output with pager
#   dmsg 30          last 30 minutes
#   dmsg 30 err      last 30 minutes, errors only
#   dmsg err         all errors with pager
dmsg() {
    local minutes=""
    local level=""

    for arg in "$@"; do
        if [[ "$arg" =~ ^[0-9]+$ ]]; then
            minutes="$arg"
        else
            level="$arg"
        fi
    done

    if [[ "$(uname)" == "Darwin" ]]; then
        # macOS dmesg is limited — no timestamp or level flags
        if [[ -n "$minutes" ]]; then
            dmesg | tail -n 200
        else
            dmesg | less
        fi
        return
    fi

    local args=(-T)
    [[ -n "$minutes" ]] && args+=(--since "-${minutes}min")
    [[ -n "$level"   ]] && args+=(-l "$level")

    local cmd=(dmesg "${args[@]}")
    if [[ -n "$minutes" ]]; then
        cmd+=(--nopager)
    else
        cmd+=(-H)
    fi

    # retry with sudo if permission denied
    if ! "${cmd[@]}" 2>/dev/null; then
        echo "dmsg: retrying with sudo..."
        sudo "${cmd[@]}"
    fi
}
