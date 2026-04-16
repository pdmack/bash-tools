# cr - cd to a project and resume its latest Claude session
# Usage: cr [name]   fuzzy substring match against project dir names in CDPATH
#                    no arg = use current directory
cr() {
    local query="${1:-}"
    local match=""

    if [[ -z "$query" ]]; then
        match="$(pwd)"
    else
        # derive search dirs from CDPATH, falling back to sensible defaults
        local search_dirs=()
        if [[ -n "$CDPATH" ]]; then
            IFS=: read -ra search_dirs <<< "$CDPATH"
        else
            search_dirs=("$HOME/github/pdmack" "$HOME/fun-projects" "$HOME")
        fi
        local matches=() seen_real=()
        for dir in "${search_dirs[@]}"; do
            [[ -d "$dir" ]] || continue
            while IFS= read -r d; do
                local base real
                base=$(basename "$d")
                real=$(realpath "$d" 2>/dev/null || echo "$d")
                if [[ "${base,,}" == *"${query,,}"* ]]; then
                    # skip duplicates (e.g. ./foo vs /abs/path/foo from CDPATH)
                    local dup=false
                    for s in "${seen_real[@]}"; do [[ "$s" == "$real" ]] && dup=true && break; done
                    $dup || { matches+=("$real"); seen_real+=("$real"); }
                fi
            done < <(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
        done

        if (( ${#matches[@]} == 0 )); then
            echo "cr: no project found matching '$query'" >&2
            return 1
        elif (( ${#matches[@]} == 1 )); then
            match="${matches[0]}"
        else
            echo "Multiple matches:"
            local i
            for i in "${!matches[@]}"; do
                printf "  [%d] %s\n" "$i" "${matches[$i]}"
            done
            echo
            read -r -p "Pick a number: " pick
            if [[ -z "${matches[$pick]:-}" ]]; then
                echo "cr: invalid selection" >&2
                return 1
            fi
            match="${matches[$pick]}"
        fi
    fi

    local project_key="${match//\//-}"
    local claude_dir="$HOME/.claude/projects/${project_key}"

    if [[ ! -d "$claude_dir" ]]; then
        echo "cr: no Claude sessions found for $match" >&2
        return 1
    fi

    local uuid
    uuid=$(ls -t "$claude_dir"/*.jsonl 2>/dev/null | head -1 | xargs basename 2>/dev/null | sed 's/\.jsonl$//')

    if [[ -z "$uuid" ]]; then
        echo "cr: no sessions in $claude_dir" >&2
        return 1
    fi

    echo "→ $match"
    echo "→ resuming $uuid"
    cd "$match" && claude --resume "$uuid"
}
