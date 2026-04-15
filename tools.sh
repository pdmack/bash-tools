# tools - list all available bash-tools with usage
tools() {
    local dir
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    {
    echo "bash-tools:"
    echo
    for f in "$dir"/*.sh; do
        [[ "$(basename "$f")" == "load.sh" || "$(basename "$f")" == "tools.sh" || "$(basename "$f")" == "site.sh" ]] && continue
        # grab the first comment line and the Usage line
        local desc usage
        desc=$(grep -m1 '^# [^!]' "$f" | sed 's/^# //')
        usage=$(grep -m1 '# Usage:' "$f" | sed 's/^# //')
        printf "  %-12s %s\n" "$(basename "$f" .sh)" "$desc"
        [[ -n "$usage" ]] && printf "  %-12s %s\n" "" "$usage"
    done
    } | "${PAGER:-less}"
}
