# fff - fat file finder, sorted by size descending
# Stops automatically at a 10x size drop between consecutive files
# Usage: fff <dir> [max]   (max = hard cap on results, default 50)
fff() {
    local dir="${1:-.}"
    local max="${2:-50}"

    if [[ ! -d "$dir" ]]; then
        echo "fff: '$dir' is not a directory" >&2
        return 1
    fi

    find "$dir" -type f -exec du -k {} + 2>/dev/null \
        | sort -rn \
        | head -"$max" \
        | awk '{
            kb = $1
            path = $2
            if (NR == 1) {
                prev = kb
            } else if (prev > 0 && prev / kb >= 10) {
                exit
            }
            prev = kb
            if (kb >= 1048576)      printf "%.1fG\t%s\n", kb/1048576, path
            else if (kb >= 1024)    printf "%.1fM\t%s\n", kb/1024,    path
            else                    printf "%dK\t%s\n",   kb,          path
        }'
}
