# jlog - journalctl with fuzzy unit matching and time in minutes
# Usage: jlog <minutes>            all logs from last N minutes
#        jlog <unit> [minutes]     logs for a fuzzy-matched unit, optionally last N minutes
jlog() {
    local arg1="${1:-}"
    local arg2="${2:-}"

    if [[ -z "$arg1" ]]; then
        echo "Usage: jlog <minutes> | jlog <unit> [minutes]" >&2
        return 1
    fi

    # If arg1 is a plain number, show all logs for last N minutes
    if [[ "$arg1" =~ ^[0-9]+$ ]]; then
        journalctl --since "${arg1} minutes ago" --no-pager
        return
    fi

    # Otherwise treat arg1 as a unit pattern
    local pattern="$arg1"
    local minutes="$arg2"

    # Search active units first, then unit files
    local matches
    matches=$(
        { systemctl list-units --all --no-legend --no-pager 2>/dev/null | awk '{print $1}'
          systemctl list-unit-files --no-legend --no-pager 2>/dev/null | awk '{print $1}'
        } | grep -i "$pattern" | sort -u
    )

    if [[ -z "$matches" ]]; then
        echo "jlog: no unit found matching '$pattern'" >&2
        return 1
    fi

    local count
    count=$(echo "$matches" | wc -l)
    local unit

    if (( count == 1 )); then
        unit="$matches"
    else
        echo "Multiple matches:"
        echo "$matches" | nl -w2 -s') '
        echo
        read -r -p "Pick a number: " pick
        unit=$(echo "$matches" | sed -n "${pick}p")
        if [[ -z "$unit" ]]; then
            echo "jlog: invalid selection" >&2
            return 1
        fi
    fi

    echo "→ $unit${minutes:+ (last ${minutes}m)}"
    if [[ -n "$minutes" ]]; then
        journalctl -u "$unit" --since "${minutes} minutes ago" --no-pager
    else
        journalctl -u "$unit"
    fi
}
