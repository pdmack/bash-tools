# memback - back up Claude project memories to $MEMBACK_DEST/claude-memories
# Usage: memback [--dry-run]
# Requires: MEMBACK_DEST set in site.sh (path to your backup git repo)
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

    local copied=0

    for memory_dir in "$claude_projects"/*/memory; do
        [[ -d "$memory_dir" ]] || continue

        # Derive a readable project name from the project key
        local project_key
        project_key=$(basename "$(dirname "$memory_dir")")
        # strip leading -home-<user>- prefix and use last path component
        local project_name
        project_name=$(echo "$project_key" | sed 's/^-home-[^-]*-//' | awk -F- '{print $NF}')

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
