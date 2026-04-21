# gclean - delete local branches already merged into main/master
# Usage: gclean [-a|--all]
#   -a|--all  run across all git repos in CDPATH (default: current repo only)
gclean() {
    local do_all=false
    for arg in "$@"; do
        case "$arg" in
            -a|--all) do_all=true ;;
            *) echo "Usage: gclean [-a|--all]" >&2; return 1 ;;
        esac
    done

    if $do_all; then
        local repos=()
        mapfile -t repos < <(_bash_tools_cdpath_repos)
        for repo in "${repos[@]}"; do
            echo "=== $repo ==="
            (cd "$repo" && _gclean_repo)
            echo
        done
    else
        if ! git rev-parse --git-dir &>/dev/null; then
            echo "gclean: not a git repository" >&2
            return 1
        fi
        _gclean_repo
    fi
}

_gclean_repo() {
    local current main_branch
    current=$(git branch --show-current)
    if git rev-parse --verify main &>/dev/null; then
        main_branch="main"
    elif git rev-parse --verify master &>/dev/null; then
        main_branch="master"
    fi

    # Check if current branch is merged into main/master
    if [[ -n "$main_branch" && "$current" != "$main_branch" ]]; then
        if git merge-base --is-ancestor HEAD "$main_branch" 2>/dev/null; then
            local unstaged untracked
            unstaged=$(git diff --name-only 2>/dev/null)
            untracked=$(git ls-files --others --exclude-standard 2>/dev/null)
            if [[ -n "$unstaged" || -n "$untracked" ]]; then
                echo "gclean: current branch '$current' is merged into $main_branch but has uncommitted changes — skipping"
            else
                echo "Current branch '$current' is merged into $main_branch."
                read -r -p "Switch to $main_branch and delete '$current'? [y/N] " confirm
                if [[ "${confirm,,}" == "y" ]]; then
                    git checkout "$main_branch" && git branch -d "$current"
                fi
            fi
        fi
    fi

    # Delete other merged branches
    local branches
    branches=$(git branch --merged | grep -v '^\*' | grep -v '^\s*main$' | grep -v '^\s*master$')

    if [[ -z "$branches" ]]; then
        echo "gclean: no merged branches to delete"
        return 0
    fi

    echo "Branches to delete:"
    echo "$branches"
    echo
    read -r -p "Delete these branches? [y/N] " confirm
    [[ "${confirm,,}" == "y" ]] || { echo "Aborted."; return 1; }

    echo "$branches" | xargs git branch -d
}
