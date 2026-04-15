# memback - back up Claude project memories to $MEMBACK_DEST/claude-memories
# Usage: memback [--dry-run]
#
# Setup (site.sh):
#   export MEMBACK_DEST="$HOME/your-backup-repo"   # root of your backup git repo
#
# What it does:
#   Copies all *.md files from ~/.claude/projects/*/memory/ into
#   $MEMBACK_DEST/claude-memories/<project-name>/, then commits and pushes.
#   Safe to run repeatedly — only commits when something changed.
#
# Project naming:
#   Claude stores projects under ~/.claude/projects/ using a key that encodes
#   the full project path with '/' replaced by '-'. For example:
#     /home/alice/github/myorg/physics-study-usa
#     → -home-alice-github-myorg-physics-study-usa
#   Since directory names can also contain '-', the separator and the name
#   character are identical and can't be distinguished textually. memback
#   resolves this by probing the filesystem: it walks $HOME looking for the
#   deepest existing parent directory, then uses the remainder as the project
#   name. This gives "physics-study-usa" rather than just "usa".
#
#   Caveat: if the project directory has been deleted or moved, the walk stops
#   early and the name falls back to the full encoded string (still usable,
#   just less clean). If two active projects share the same final directory
#   name they will collide into one folder — rename one to disambiguate.
#
# Privacy / safety:
#   Memories may contain sensitive context. memback requires the backup
#   destination to be a hosted git repo (must have a remote origin configured).
#   For GitHub remotes it verifies the repo is private via the gh CLI and
#   refuses to run if it is not. For other hosts (GitLab, Gitea, etc.) it
#   cannot verify visibility automatically and emits a warning instead —
#   it is your responsibility to ensure the repo is private.

_memback_project_name() {
    # Reconstruct the project directory name from the encoded portion of a
    # Claude project key (after stripping the -home-<user>- prefix).
    local encoded="$1"
    local current="$HOME"
    local remaining="$encoded"

    while [[ -n "$remaining" ]]; do
        # Try prefixes from longest to shortest; only consume a segment if
        # something remains after it (so we don't eat the project name itself).
        local candidate="$remaining"
        local found=""
        while [[ -n "$candidate" ]]; do
            local after="${remaining#"${candidate}"}"
            after="${after#-}"
            if [[ -n "$after" && -d "$current/$candidate" ]]; then
                found="$candidate"
                break
            fi
            [[ "$candidate" == *-* ]] || break
            candidate="${candidate%-*}"
        done
        [[ -n "$found" ]] || break
        current="$current/$found"
        remaining="${remaining#"${found}-"}"
    done

    echo "$remaining"
}

memback() {
    local dry_run=false
    [[ "${1:-}" == "--dry-run" ]] && dry_run=true

    local skills_dir="${MEMBACK_DEST:-}"
    if [[ -z "$skills_dir" ]]; then
        echo "memback: set MEMBACK_DEST in site.sh to your backup repo path" >&2
        return 1
    fi
    local dest="$skills_dir/claude-memories"
    local claude_projects="$HOME/.claude/projects"

    if [[ ! -d "$skills_dir" ]]; then
        echo "memback: MEMBACK_DEST directory not found: $skills_dir" >&2
        return 1
    fi

    # Safety: backup destination must be a real remote repo, and private if on GitHub
    local remote_url
    remote_url=$(git -C "$skills_dir" remote get-url origin 2>/dev/null)
    if [[ -z "$remote_url" ]]; then
        echo "memback: $skills_dir has no git remote — must be a hosted repo" >&2
        return 1
    fi
    if [[ "$remote_url" == *github.com* ]]; then
        if ! command -v gh &>/dev/null; then
            echo "memback: gh CLI required to verify GitHub repo visibility" >&2
            return 1
        fi
        local is_private
        is_private=$(cd "$skills_dir" && gh repo view --json isPrivate -q '.isPrivate' 2>/dev/null)
        if [[ "$is_private" != "true" ]]; then
            echo "memback: backup repo must be private" >&2
            echo "  check: cd $skills_dir && gh repo view --json isPrivate" >&2
            return 1
        fi
    else
        echo "memback: warning: cannot verify visibility for non-GitHub remote — ensure $remote_url is private" >&2
    fi

    local copied=0

    for memory_dir in "$claude_projects"/*/memory; do
        [[ -d "$memory_dir" ]] || continue

        local project_key
        project_key=$(basename "$(dirname "$memory_dir")")
        local encoded
        encoded=$(echo "$project_key" | sed 's/^-home-[^-]*-//')
        local project_name
        project_name=$(_memback_project_name "$encoded")

        local target="$dest/$project_name"

        # Copy memory files
        while IFS= read -r f; do
            local rel="${f#$memory_dir/}"
            local dst="$target/$rel"
            if $dry_run; then
                echo "  $f → $dst"
            else
                mkdir -p "$(dirname "$dst")"
                cp "$f" "$dst"
            fi
            (( copied++ ))
        done < <(find "$memory_dir" -type f -name "*.md" 2>/dev/null)
    done

    if $dry_run; then
        echo "dry run: $copied file(s) would be copied"
        return 0
    fi

    if (( copied == 0 )); then
        echo "memback: no memory files found"
        return 0
    fi

    echo "copied $copied file(s)"

    # Commit and push
    if ! git -C "$skills_dir" diff --quiet || [[ -n "$(git -C "$skills_dir" ls-files --others --exclude-standard claude-memories/)" ]]; then
        git -C "$skills_dir" add claude-memories/
        git -C "$skills_dir" commit -m "memback: $(date '+%Y-%m-%d %H:%M')"
        git -C "$skills_dir" push
    else
        echo "memback: nothing changed"
    fi
}
