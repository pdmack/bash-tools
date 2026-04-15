# memback - back up Claude project memories to $MEMBACK_DEST/claude-memories
# Usage: memback [--dry-run]
# Requires: MEMBACK_DEST set in site.sh (path to your backup git repo)
#
# Project naming: Claude encodes project paths by replacing '/' with '-', and
# directory names may also contain '-', making them indistinguishable in the key.
# We probe the filesystem to find the deepest existing parent prefix; the
# remainder becomes the project name (e.g. "physics-study-usa", not "usa").
# If the project directory no longer exists the full encoded string is used.
# Collision risk: two projects whose dirs resolve to the same name will share a
# folder — rename one if that happens.
#
# Safety: memback refuses to run if the backup repo is not confirmed private
# (checked via gh CLI).

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

    # Safety: refuse to back up memories to a public repo
    if ! command -v gh &>/dev/null; then
        echo "memback: gh CLI required to verify repo visibility" >&2
        return 1
    fi
    local is_private
    is_private=$(cd "$skills_dir" && gh repo view --json isPrivate -q '.isPrivate' 2>/dev/null)
    if [[ "$is_private" != "true" ]]; then
        echo "memback: backup repo must be private" >&2
        echo "  check: cd $skills_dir && gh repo view --json isPrivate" >&2
        return 1
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
