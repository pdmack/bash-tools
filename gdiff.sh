# gdiff - show diff between current branch and another
# Usage: gdiff [branch] [-a|--all]
#   branch    base branch to diff against (default: main)
#   -a|--all  run across all git repos in CDPATH (default: current repo only)
gdiff() {
    local base="main" do_all=false
    for arg in "$@"; do
        case "$arg" in
            -a|--all) do_all=true ;;
            -*) echo "Usage: gdiff [branch] [-a|--all]" >&2; return 1 ;;
            *)  base="$arg" ;;
        esac
    done

    if $do_all; then
        local raw_dirs=() cdpath_dirs=()
        IFS=: read -ra raw_dirs <<< "${CDPATH:-$HOME}"
        for d in "${raw_dirs[@]}"; do
            [[ "$d" = /* ]] && cdpath_dirs+=("$d") || cdpath_dirs+=("$HOME/${d#./}")
        done
        local repos=() seen=()
        for dir in "${cdpath_dirs[@]}"; do
            [[ -d "$dir" ]] || continue
            while IFS= read -r d; do
                [[ -d "$d/.git" ]] || continue
                local already=false
                for s in "${seen[@]:-}"; do [[ "$s" == "$d" ]] && already=true && break; done
                $already || { repos+=("$d"); seen+=("$d"); }
            done < <(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
        done
        for repo in "${repos[@]}"; do
            local diff
            diff=$(git -C "$repo" diff "${base}...HEAD" 2>/dev/null)
            [[ -n "$diff" ]] || continue
            echo "=== $repo ==="
            echo "$diff"
            echo
        done
    else
        if ! git rev-parse --git-dir &>/dev/null; then
            echo "gdiff: not a git repository" >&2
            return 1
        fi
        git diff "${base}...HEAD"
    fi
}
