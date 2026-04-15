# mkpr - create a GitHub issue then open a PR referencing it
# Usage: mkpr
# Follows the workflow: gh issue create -> gh pr create with Fixes #n
mkpr() {
    if ! git rev-parse --git-dir &>/dev/null; then
        echo "mkpr: not a git repository" >&2
        return 1
    fi
    if ! gh auth status &>/dev/null; then
        echo "mkpr: not authenticated with gh — run 'gh auth login'" >&2
        return 1
    fi

    echo "=== Step 1: Create GitHub issue ==="
    gh issue create
    echo
    read -r -p "Issue number (from URL above): #" issue_num
    if ! [[ "$issue_num" =~ ^[0-9]+$ ]]; then
        echo "mkpr: invalid issue number" >&2
        return 1
    fi

    echo
    echo "=== Step 2: Create PR (Fixes #${issue_num}) ==="
    gh pr create --body "Fixes #${issue_num}"
}
