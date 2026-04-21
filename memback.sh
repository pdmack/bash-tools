# memback  - back up Claude project memories and global config to $MEMBACK_DEST
# memrestore - restore Claude config from $MEMBACK_DEST to this machine
#
# Usage: memback [-n|--dry-run]
#        memrestore [-n|--dry-run] [-f|--force] [--platform linux|macos]
#
# Setup (site.sh):
#   export MEMBACK_DEST="$HOME/your-backup-repo"   # root of your backup git repo
#
# New machine workflow:
#   1. Clone skills repo: git clone <url> $MEMBACK_DEST
#   2. Set MEMBACK_DEST in site.sh and source it
#   3. memrestore
#   4. ln -s $MEMBACK_DEST ~/.claude/skills
#
# What memback does:
#   1. Copies ~/.claude/CLAUDE.md and ~/.claude/settings.json into
#      $MEMBACK_DEST/claude-global/
#   2. Copies ~/.mcp.json into $MEMBACK_DEST/claude-global/
#   3. Copies all *.md files from ~/.claude/projects/*/memory/ into
#      $MEMBACK_DEST/claude-memories/<project-name>/
#   Then commits and pushes. Safe to run repeatedly — only commits when
#   something changed.
#
# What memrestore does:
#   1. Installs claude-global/{CLAUDE.md,settings.json} → ~/.claude/
#   2. Installs claude-global/.mcp.json → ~/
#   3. For settings.json: rewrites backed-up home path to $HOME; on macOS
#      also strips Linux-only /proc entries from sandbox.filesystem.denyRead
#   Prompts before overwriting existing files (--force to skip).
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

_memback_project_walk() {
    # Walk $HOME to resolve an encoded Claude project key segment.
    # Outputs two lines: the resolved parent path, then the unresolved remainder
    # (the project name / final path component).
    local encoded="$1"
    local current="$HOME"
    local remaining="$encoded"

    while [[ -n "$remaining" ]]; do
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

    echo "$current"
    echo "$remaining"
}

_memback_project_name() {
    local encoded="$1"
    local info
    mapfile -t info < <(_memback_project_walk "$encoded")
    echo "${info[1]}"
}

_memback_project_path() {
    # Returns the full reconstructed project path (parent + name).
    local encoded="$1"
    local info
    mapfile -t info < <(_memback_project_walk "$encoded")
    echo "${info[0]}/${info[1]}"
}

memback() {
    local dry_run=false
    [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]] && dry_run=true

    local skills_dir="${MEMBACK_DEST:-}"
    if [[ -z "$skills_dir" ]]; then
        echo "memback: set MEMBACK_DEST in site.sh to your backup repo path" >&2
        return 1
    fi
    local dest_memories="$skills_dir/claude-memories"
    local dest_global="$skills_dir/claude-global"
    local claude_dir="$HOME/.claude"
    local claude_projects="$claude_dir/projects"

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

    # 1. Global claude config (~/.claude/*.md and settings.json)
    while IFS= read -r f; do
        local dst="$dest_global/$(basename "$f")"
        if $dry_run; then
            echo "  $f → $dst"
        else
            mkdir -p "$dest_global"
            cp "$f" "$dst"
        fi
        (( copied++ ))
    done < <(find "$claude_dir" -maxdepth 1 -type f \( -name "*.md" -o -name "settings.json" \) 2>/dev/null)

    # 1b. Global MCP config (~/.mcp.json)
    if [[ -f "$HOME/.mcp.json" ]]; then
        local dst="$dest_global/.mcp.json"
        if $dry_run; then
            echo "  $HOME/.mcp.json → $dst"
        else
            mkdir -p "$dest_global"
            cp "$HOME/.mcp.json" "$dst"
        fi
        (( copied++ ))
    fi

    # 2. Project memories (~/.claude/projects/*/memory/*.md)
    for memory_dir in "$claude_projects"/*/memory; do
        [[ -d "$memory_dir" ]] || continue

        local project_key
        project_key=$(basename "$(dirname "$memory_dir")")
        local encoded
        encoded=$(echo "$project_key" | sed 's/^-home-[^-]*-//')
        local project_name
        project_name=$(_memback_project_name "$encoded")
        local project_path
        project_path=$(_memback_project_path "$encoded")

        local target="$dest_memories/$project_name"

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

        # Save git metadata for cross-machine restore
        if [[ -d "$project_path/.git" ]]; then
            local remote_url
            remote_url=$(git -C "$project_path" remote get-url origin 2>/dev/null)
            if [[ -n "$remote_url" ]]; then
                local meta_dst="$target/.meta.json"
                if $dry_run; then
                    echo "  .meta.json → $meta_dst"
                else
                    mkdir -p "$target"
                    jq -n --arg url "$remote_url" --arg path "$project_path" \
                        '{"remote_url": $url, "local_path": $path}' > "$meta_dst"
                fi
                (( copied++ ))
            fi
        fi
    done

    if $dry_run; then
        echo "dry run: $copied file(s) would be copied"
        return 0
    fi

    if (( copied == 0 )); then
        echo "memback: no files found"
        return 0
    fi

    echo "copied $copied file(s)"

    # Commit and push
    local changed=false
    ! git -C "$skills_dir" diff --quiet && changed=true
    [[ -n "$(git -C "$skills_dir" ls-files --others --exclude-standard claude-memories/ claude-global/)" ]] && changed=true
    if $changed; then
        git -C "$skills_dir" add claude-memories/ claude-global/
        git -C "$skills_dir" commit -m "memback: $(date '+%Y-%m-%d %H:%M')"
        git -C "$skills_dir" push
    else
        echo "memback: nothing changed"
    fi
}

# memrestore - restore Claude global config from $MEMBACK_DEST to this machine
#
# Usage: memrestore [-n|--dry-run] [--platform linux|macos]
#
# What it does:
#   1. Installs claude-global/{CLAUDE.md,settings.json} into ~/.claude/
#   2. Installs claude-global/.mcp.json into ~/
#   3. For settings.json: rewrites the backed-up home path to $HOME, and on
#      macOS strips Linux-only /proc entries from sandbox.filesystem.denyRead
#   4. Reminds you to set up ~/.claude/skills → $MEMBACK_DEST if not present
#
# It does NOT overwrite files without prompting — use --force to skip prompts.
#
# Typical new-machine workflow:
#   1. Clone your skills repo to $MEMBACK_DEST (e.g. ~/github/pdmack/skills)
#   2. Set MEMBACK_DEST in site.sh and source it
#   3. Run: memrestore
#   4. Symlink skills: ln -s $MEMBACK_DEST ~/.claude/skills

_memrestore_transform_settings() {
    local src="$1" platform="$2"

    # Detect the source home path from denyRead entries
    local old_home
    old_home=$(jq -r '
        (.sandbox.filesystem.denyRead // [])[]
        | select(test("^/(home|Users)/"))
        | capture("^(?P<h>/(home|Users)/[^/]+)").h
    ' "$src" 2>/dev/null | sort -u | head -1)

    if [[ "$platform" == "macos" ]]; then
        jq \
            --arg old "${old_home:-__NO_MATCH__}" \
            --arg new "$HOME" \
            'walk(if type == "string" then gsub($old; $new) else . end)
             | if .sandbox.filesystem.denyRead then
                 .sandbox.filesystem.denyRead |= map(select(startswith("/proc") | not))
               else . end' \
            "$src"
    else
        jq \
            --arg old "${old_home:-__NO_MATCH__}" \
            --arg new "$HOME" \
            'walk(if type == "string" then gsub($old; $new) else . end)' \
            "$src"
    fi
}

memrestore() {
    local dry_run=false force=false platform=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run|-n) dry_run=true; shift ;;
            --force|-f)   force=true;   shift ;;
            --platform)   platform="$2"; shift 2 ;;
            *) echo "memrestore: unknown option: $1" >&2; return 1 ;;
        esac
    done

    if [[ -z "$platform" ]]; then
        case "$(uname -s)" in
            Darwin) platform="macos" ;;
            Linux)  platform="linux" ;;
            *) echo "memrestore: unsupported platform: $(uname -s)" >&2; return 1 ;;
        esac
    fi

    local skills_dir="${MEMBACK_DEST:-}"
    if [[ -z "$skills_dir" ]]; then
        echo "memrestore: set MEMBACK_DEST in site.sh to your backup repo path" >&2
        return 1
    fi
    if [[ ! -d "$skills_dir" ]]; then
        echo "memrestore: MEMBACK_DEST not found: $skills_dir" >&2
        echo "  clone your skills repo there first" >&2
        return 1
    fi

    local src_global="$skills_dir/claude-global"
    if [[ ! -d "$src_global" ]]; then
        echo "memrestore: $src_global not found — run memback on source machine first" >&2
        return 1
    fi

    local claude_dir="$HOME/.claude"
    local installed=0

    # Install a single file, prompting if destination exists (unless --force)
    _memrestore_cp() {
        local src="$1" dst="$2"
        if [[ -e "$dst" ]] && ! $force; then
            printf "memrestore: %s exists — overwrite? [y/N] " "$dst"
            read -r ans
            [[ "$ans" =~ ^[Yy]$ ]] || { echo "  skipped"; return 0; }
        fi
        mkdir -p "$(dirname "$dst")"
        if cp "$src" "$dst" 2>/dev/null; then
            echo "  installed $dst"
            (( installed++ ))
        else
            echo "  ERROR: failed to write $dst" >&2
        fi
    }

    echo "memrestore: platform=$platform src=$src_global"

    # CLAUDE.md
    if [[ -f "$src_global/CLAUDE.md" ]]; then
        if $dry_run; then
            echo "  $src_global/CLAUDE.md → $claude_dir/CLAUDE.md"
        else
            _memrestore_cp "$src_global/CLAUDE.md" "$claude_dir/CLAUDE.md"
        fi
    fi

    # .mcp.json (all HTTP URLs — no transform needed)
    if [[ -f "$src_global/.mcp.json" ]]; then
        if $dry_run; then
            echo "  $src_global/.mcp.json → $HOME/.mcp.json"
        else
            _memrestore_cp "$src_global/.mcp.json" "$HOME/.mcp.json"
        fi
    fi

    # settings.json — platform-aware transform
    if [[ -f "$src_global/settings.json" ]]; then
        if $dry_run; then
            echo "  $src_global/settings.json → $claude_dir/settings.json"
            echo "    transforms: home path → \$HOME"
            [[ "$platform" == "macos" ]] && echo "    transforms: strip /proc denyRead entries"
        else
            local tmp
            tmp=$(mktemp)
            if _memrestore_transform_settings "$src_global/settings.json" "$platform" > "$tmp" 2>&1; then
                if $force || [[ ! -e "$claude_dir/settings.json" ]]; then
                    mkdir -p "$claude_dir"
                    cp "$tmp" "$claude_dir/settings.json"
                    echo "  installed $claude_dir/settings.json"
                    (( installed++ ))
                else
                    printf "memrestore: %s exists — overwrite? [y/N] " "$claude_dir/settings.json"
                    read -r ans
                    if [[ "$ans" =~ ^[Yy]$ ]]; then
                        mkdir -p "$claude_dir"
                        cp "$tmp" "$claude_dir/settings.json"
                        echo "  installed $claude_dir/settings.json"
                        (( installed++ ))
                    else
                        echo "  skipped $claude_dir/settings.json"
                    fi
                fi
            else
                echo "memrestore: failed to transform settings.json:" >&2
                cat "$tmp" >&2
            fi
            rm -f "$tmp"
        fi
    fi

    # Memories — prompt per project
    local src_memories="$skills_dir/claude-memories"
    if [[ -d "$src_memories" ]]; then
        echo ""
        echo "memrestore: project memories"

        for memory_src in "$src_memories"/*/; do
            [[ -d "$memory_src" ]] || continue
            local project_name
            project_name=$(basename "$memory_src")

            # Find matching project key in ~/.claude/projects/ — key must end with -<project_name>
            local matched_key=""
            for proj_dir in "$claude_dir/projects"/*/; do
                [[ -d "$proj_dir" ]] || continue
                local key
                key=$(basename "$proj_dir")
                if [[ "$key" == *"-${project_name}" ]]; then
                    matched_key="$key"
                    break
                fi
            done

            local file_count
            file_count=$(find "$memory_src" -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')

            if [[ -n "$matched_key" ]]; then
                printf "  %-35s [found]      restore %s file(s)? [Y/n] " "$project_name" "$file_count"
            else
                printf "  %-35s [not found]  restore %s file(s)? [y/N] " "$project_name" "$file_count"
            fi

            if $dry_run; then
                echo "(dry run)"
                continue
            fi

            local ans
            read -r ans
            if [[ -n "$matched_key" ]]; then
                ans="${ans:-y}"
            else
                ans="${ans:-n}"
            fi
            [[ "$ans" =~ ^[Yy]$ ]] || continue

            # Determine target memory dir
            local target_dir=""
            if [[ -n "$matched_key" ]]; then
                target_dir="$claude_dir/projects/$matched_key/memory"
            else
                # Try metadata for git clone offer
                local meta_file="$memory_src/.meta.json"
                local remote_url="" orig_path=""
                if [[ -f "$meta_file" ]]; then
                    remote_url=$(jq -r '.remote_url // ""' "$meta_file")
                    orig_path=$(jq -r '.local_path // ""' "$meta_file" \
                        | sed "s|^/home/[^/]*/|$HOME/|; s|^/Users/[^/]*/|$HOME/|")
                fi

                local proj_path=""
                if [[ -n "$remote_url" && -n "$orig_path" ]]; then
                    printf "    clone %s\n    → %s? [Y/n] " "$remote_url" "$orig_path"
                    local clone_ans
                    read -r clone_ans
                    clone_ans="${clone_ans:-y}"
                    if [[ "$clone_ans" =~ ^[Yy]$ ]]; then
                        mkdir -p "$(dirname "$orig_path")"
                        if git clone "$remote_url" "$orig_path"; then
                            proj_path="$orig_path"
                        else
                            echo "    clone failed — skipped" >&2
                            continue
                        fi
                    fi
                fi

                if [[ -z "$proj_path" ]]; then
                    printf "    path on this machine (e.g. %s/github/pdmack/%s): " "$HOME" "$project_name"
                    read -r proj_path
                fi
                if [[ -z "$proj_path" ]]; then
                    echo "    skipped"
                    continue
                fi
                local encoded_key
                encoded_key=$(echo "$proj_path" | sed 's|/|-|g')
                target_dir="$claude_dir/projects/$encoded_key/memory"
            fi

            local mem_copied=0
            while IFS= read -r f; do
                local rel="${f#${memory_src}}"
                local dst="$target_dir/$rel"
                mkdir -p "$(dirname "$dst")"
                cp "$f" "$dst"
                (( mem_copied++ ))
            done < <(find "$memory_src" -name "*.md" -type f 2>/dev/null)

            echo "    restored $mem_copied file(s) → $target_dir"
            (( installed += mem_copied ))
        done
    fi

    # Skills directory hint
    local skills_link="$claude_dir/skills"
    if [[ ! -e "$skills_link" ]]; then
        echo ""
        echo "memrestore: note: $skills_link not set up"
        echo "  to use your skills repo as the skills dir:"
        echo "    ln -s $skills_dir $skills_link"
    fi

    if $dry_run; then
        echo "dry run complete (platform: $platform)"
    else
        echo "memrestore: done — $installed file(s) installed"
    fi
}
