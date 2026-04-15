# gclean - delete local branches already merged into the current branch
# Usage: gclean
gclean() {
    if ! git rev-parse --git-dir &>/dev/null; then
        echo "gclean: not a git repository" >&2
        return 1
    fi

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
    [[ "${confirm,,}" == "y" ]] || { echo "Aborted." >&2; return 1; }

    echo "$branches" | xargs git branch -d
}
