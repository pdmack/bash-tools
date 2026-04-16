# grepos - scan git repos from CDPATH and show main branch status
# Usage: grepos [-f|--fetch] [-s|--sync]
#   -f|--fetch  run git fetch --all on each repo before checking status
#   -s|--sync   offer to sync fork mains (repos with an 'upstream' remote)
grepos() {
    local do_fetch=false do_sync=false

    for arg in "$@"; do
        case "$arg" in
            -f|--fetch) do_fetch=true ;;
            -s|--sync)  do_sync=true ;;
            *) echo "Usage: grepos [-f|--fetch] [-s|--sync]" >&2; return 1 ;;
        esac
    done

    # Collect unique git repos from CDPATH
    local seen=()
    local repos=()
    IFS=: read -ra cdpath_dirs <<< "${CDPATH:-$HOME}"
    for dir in "${cdpath_dirs[@]}"; do
        [[ -d "$dir" && "$dir" != "." ]] || continue
        while IFS= read -r d; do
            [[ -d "$d/.git" ]] || continue
            # deduplicate
            local already=false
            for s in "${seen[@]:-}"; do [[ "$s" == "$d" ]] && already=true && break; done
            $already || { repos+=("$d"); seen+=("$d"); }
        done < <(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
    done

    if (( ${#repos[@]} == 0 )); then
        echo "grepos: no git repos found in CDPATH"
        return 0
    fi

    local to_sync=()

    for repo in "${repos[@]}"; do
        local name
        name=$(basename "$repo")

        # Fetch if requested
        if $do_fetch; then
            git -C "$repo" fetch --all -q 2>/dev/null
        fi

        # Current branch
        local branch
        branch=$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo "detached")

        # Determine main branch name
        local main_branch
        main_branch=$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
            | sed 's|.*/||')
        [[ -z "$main_branch" ]] && main_branch="main"

        # Dirty check
        local dirty=""
        [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]] && dirty=" *"

        # Ahead/behind origin
        local ahead behind status_str
        ahead=$(git -C "$repo" rev-list --count "@{u}..HEAD" 2>/dev/null)
        behind=$(git -C "$repo" rev-list --count "HEAD..@{u}" 2>/dev/null)

        if [[ -z "$ahead" && -z "$behind" ]]; then
            status_str="no tracking"
        elif [[ "$ahead" == "0" && "$behind" == "0" ]]; then
            status_str="up to date"
        else
            status_str=""
            (( ahead  > 0 )) && status_str+="↑${ahead} ahead "
            (( behind > 0 )) && status_str+="↓${behind} behind"
        fi

        # Upstream (fork) check
        local upstream_str=""
        if git -C "$repo" remote | grep -q "^upstream$"; then
            local u_ahead u_behind
            u_ahead=$(git -C "$repo" rev-list --count "upstream/${main_branch}..HEAD" 2>/dev/null)
            u_behind=$(git -C "$repo" rev-list --count "HEAD..upstream/${main_branch}" 2>/dev/null)
            if [[ -n "$u_behind" && "$u_behind" != "0" ]]; then
                upstream_str="  [upstream ↓${u_behind}]"
                $do_sync && to_sync+=("$repo")
            elif [[ -n "$u_ahead" || -n "$u_behind" ]]; then
                upstream_str="  [upstream ✓]"
            fi
        fi

        printf "  %-30s [%s]%s  %s%s\n" \
            "$name" "$branch" "$dirty" "$status_str" "$upstream_str"
    done

    # Offer sync
    if $do_sync && (( ${#to_sync[@]} > 0 )); then
        echo
        echo "Repos with upstream main ahead:"
        for repo in "${to_sync[@]}"; do
            echo "  $(basename "$repo")"
        done
        echo
        read -r -p "Sync these forks? [y/N] " confirm
        [[ "${confirm,,}" != "y" ]] && return 0

        for repo in "${to_sync[@]}"; do
            local main_branch
            main_branch=$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
                | sed 's|.*/||')
            [[ -z "$main_branch" ]] && main_branch="main"
            echo "→ syncing $(basename "$repo")..."
            git -C "$repo" checkout "$main_branch" -q \
                && git -C "$repo" merge "upstream/${main_branch}" --ff-only \
                && git -C "$repo" push origin "$main_branch" \
                || echo "  failed — may need manual merge"
        done
    fi
}
