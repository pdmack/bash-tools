# grebase - rebase current feature/fix branch onto origin/main
# Usage: grebase
#   Fetches origin and rebases onto origin/main (or origin/master).
#   Refuses to run on trunk branches. Auto-stashes uncommitted changes.
#
# Also wraps `git` to intercept "git merge origin/main" on feature branches
# and redirect to grebase. Use `command git merge ...` to bypass.

# intercept git merge origin/[trunk] on feature branches
git() {
    if [[ "$1" == "merge" ]] && _grebase_is_origin_trunk "${@:2}"; then
        local current trunk=""
        current=$(command git branch --show-current 2>/dev/null)
        for b in main master develop; do
            if command git rev-parse --verify "$b" &>/dev/null 2>&1; then
                trunk="$b"; break
            fi
        done
        if [[ -n "$trunk" && "$current" != "$trunk" ]]; then
            echo "git merge: use 'grebase' to sync '$current' with origin/$trunk (keeps history clean)" >&2
            read -r -p "Run grebase now? [y/N] " _grebase_confirm </dev/tty
            if [[ "${_grebase_confirm,,}" == "y" ]]; then
                unset _grebase_confirm
                grebase; return
            else
                unset _grebase_confirm
                echo "Aborted. To force the merge: command git merge $*" >&2
                return 1
            fi
        fi
    fi
    command git "$@"
}

_grebase_is_origin_trunk() {
    local arg
    for arg in "$@"; do
        [[ "$arg" == -* ]] && continue
        [[ "$arg" =~ ^origin(/main|/master|/develop)?$ ]] && return 0
    done
    return 1
}

grebase() {
    if ! command git rev-parse --git-dir &>/dev/null; then
        echo "grebase: not a git repository" >&2
        return 1
    fi

    local current
    current=$(git branch --show-current)

    if [[ -z "$current" ]]; then
        echo "grebase: detached HEAD — checkout a branch first" >&2
        return 1
    fi

    local trunk=""
    for b in main master develop; do
        if git rev-parse --verify "$b" &>/dev/null; then
            trunk="$b"
            break
        fi
    done

    if [[ -z "$trunk" ]]; then
        echo "grebase: could not detect trunk branch (main/master/develop)" >&2
        return 1
    fi

    if [[ "$current" == "$trunk" ]]; then
        echo "grebase: on '$trunk' — use 'git pull --rebase' instead" >&2
        return 1
    fi

    local stashed=false
    if ! git diff --quiet || ! git diff --cached --quiet; then
        echo "grebase: uncommitted changes on '$current'"
        read -r -p "Stash and continue? [y/N] " confirm </dev/tty
        if [[ "${confirm,,}" == "y" ]]; then
            git stash push -m "grebase auto-stash" || return 1
            stashed=true
        else
            echo "Aborted."
            return 1
        fi
    fi

    echo "grebase: fetching origin..."
    if ! git fetch origin; then
        $stashed && git stash pop
        return 1
    fi

    if ! git rev-parse --verify "origin/$trunk" &>/dev/null; then
        echo "grebase: origin/$trunk not found" >&2
        $stashed && git stash pop
        return 1
    fi

    echo "grebase: rebasing '$current' onto origin/$trunk..."
    if git rebase "origin/$trunk"; then
        if $stashed; then
            echo "grebase: restoring stash..."
            git stash pop
        fi
        echo "grebase: done"
    else
        echo >&2
        echo "grebase: conflicts — resolve them, then:" >&2
        echo "  git add <files> && git rebase --continue" >&2
        echo "  or: git rebase --abort" >&2
        $stashed && echo "  (stash saved — pop it after rebase completes)" >&2
        return 1
    fi
}
