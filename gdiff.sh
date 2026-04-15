# gdiff - show diff between current branch and another
# Usage: gdiff [branch]   (default: main)
gdiff() {
    if ! git rev-parse --git-dir &>/dev/null; then
        echo "gdiff: not a git repository" >&2
        return 1
    fi

    local base="${1:-main}"
    git diff "${base}...HEAD"
}
