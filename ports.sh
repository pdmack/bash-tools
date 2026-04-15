# ports - show listening ports and the processes using them
# Usage: ports [filter]
ports() {
    local filter="${1:-}"
    if [[ "$(uname)" == "Darwin" ]]; then
        if [[ -n "$filter" ]]; then
            lsof -i -P -n | grep -i LISTEN | grep -i "$filter"
        else
            lsof -i -P -n | grep -i LISTEN
        fi
    else
        if [[ -n "$filter" ]]; then
            ss -tlnp | grep -E "Local|$filter"
        else
            ss -tlnp
        fi
    fi
}
