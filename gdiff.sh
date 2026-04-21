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
        local repos=()
        mapfile -t repos < <(_bash_tools_cdpath_repos)
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
