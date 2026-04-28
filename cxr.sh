# cxr - cd to a project and resume its latest Codex session
# Usage: cxr [name]   fuzzy substring match against project dir names in CDPATH
#                     no arg = use current directory
cxr() {
    if ! command -v codex &>/dev/null; then
        echo "cxr: codex not found — install Codex CLI first" >&2
        return 1
    fi

    local query="${1:-}"
    local match=""

    if [[ -z "$query" ]]; then
        match="$(pwd)"
    else
        local raw_dirs=()
        if [[ -n "$CDPATH" ]]; then
            IFS=: read -ra raw_dirs <<< "$CDPATH"
        else
            raw_dirs=("$HOME/github/pdmack" "$HOME/fun-projects" "$HOME")
        fi
        local search_dirs=()
        for d in "${raw_dirs[@]}"; do
            [[ "$d" = /* ]] && search_dirs+=("$d") || search_dirs+=("$HOME/${d#./}")
        done

        local matches=() seen_real=()
        for dir in "${search_dirs[@]}"; do
            [[ -d "$dir" ]] || continue
            while IFS= read -r d; do
                local base real
                base=$(basename "$d")
                real=$(realpath "$d" 2>/dev/null || echo "$d")
                if [[ "${base,,}" == *"${query,,}"* ]]; then
                    local dup=false
                    for s in "${seen_real[@]}"; do [[ "$s" == "$real" ]] && dup=true && break; done
                    $dup || { matches+=("$real"); seen_real+=("$real"); }
                fi
            done < <(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
        done

        if (( ${#matches[@]} == 0 )); then
            echo "cxr: no project found matching '$query'" >&2
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
                echo "cxr: invalid selection" >&2
                return 1
            fi
            match="${matches[$pick]}"
        fi
    fi

    echo "→ $match"
    cd "$match" && codex resume --last
}
