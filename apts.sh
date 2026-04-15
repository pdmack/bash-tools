# apts - focused apt search, ranked by relevance
# Usage: apts <query> [max]   (max results, default 20)
apts() {
    local query="${1:-}"
    local max="${2:-20}"

    if [[ -z "$query" ]]; then
        echo "Usage: apts <query> [max]" >&2
        return 1
    fi

    # apt-cache search gives clean "name - description" output
    local results
    results=$(apt-cache search "$query" 2>/dev/null)

    if [[ -z "$results" ]]; then
        echo "apts: no packages found for '$query'"
        return 0
    fi

    # Rank: 1=exact name, 2=name prefix, 3=name substring, 4=description only
    echo "$results" | awk -v q="$query" -v max="$max" '
    BEGIN { IGNORECASE=1; n=0 }
    {
        name=$1
        if (name == q)                      rank=1
        else if (index(name, q) == 1)       rank=2
        else if (index(name, q) > 1)        rank=3
        else                                rank=4

        lines[n] = $0
        ranks[n] = rank
        n++
    }
    END {
        # insertion sort by rank (small n, fine)
        for (i=1; i<n; i++) {
            for (j=i; j>0 && ranks[j-1]>ranks[j]; j--) {
                tmp=lines[j]; lines[j]=lines[j-1]; lines[j-1]=tmp
                tmp=ranks[j]; ranks[j]=ranks[j-1]; ranks[j-1]=tmp
            }
        }
        shown=0
        for (i=0; i<n && shown<max; i++) {
            print lines[i]
            shown++
        }
        if (n > max) printf "\n(%d more — run: apts %s %d)\n", n-max, q, n
    }'
}
