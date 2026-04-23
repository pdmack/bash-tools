# memrestore - restore Claude global config from $MEMBACK_DEST to this machine
#
# Usage: memrestore [-n|--dry-run] [-f|--force] [--platform linux|macos]
#
# Setup (site.sh):
#   export MEMBACK_DEST="$HOME/your-backup-repo"
#
# New machine workflow:
#   1. Clone skills repo: git clone <url> $MEMBACK_DEST
#   2. Set MEMBACK_DEST in site.sh and source it
#   3. memrestore
#   4. ln -s $MEMBACK_DEST ~/.claude/skills
#
# What it does:
#   1. Installs claude-global/{CLAUDE.md,settings.json} into ~/.claude/
#   2. Installs claude-global/.mcp.json into ~/
#   3. For settings.json: rewrites backed-up home path to $HOME; on macOS
#      also strips Linux-only /proc entries from sandbox.filesystem.denyRead
#   4. Prompts per project memory, offers git clone for repos not found locally
#   Prompts before overwriting existing files (--force to skip).
#
# Requires memback.sh to be sourced first (uses _memback_project_walk helpers).

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

            local display_name="$project_name"
            (( ${#project_name} > 35 )) && display_name="${project_name:0:34}…"
            if [[ -n "$matched_key" ]]; then
                printf "  %-35s [found]      restore %s file(s)? [Y/n] " "$display_name" "$file_count"
            else
                printf "  %-35s [not found]  restore %s file(s)? [y/N] " "$display_name" "$file_count"
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

                # Prefer SSH for GitHub/GitLab HTTPS URLs — avoids credential prompts
                local clone_url="$remote_url"
                if [[ "$clone_url" =~ ^https://github\.com/(.+)$ ]]; then
                    clone_url="git@github.com:${BASH_REMATCH[1]}"
                elif [[ "$clone_url" =~ ^https://gitlab\.com/(.+)$ ]]; then
                    clone_url="git@gitlab.com:${BASH_REMATCH[1]}"
                fi

                local proj_path=""
                if [[ -n "$clone_url" && -n "$orig_path" ]]; then
                    printf "    clone %s\n    → %s? [Y/n] " "$clone_url" "$orig_path"
                    local clone_ans
                    read -r clone_ans
                    clone_ans="${clone_ans:-y}"
                    if [[ "$clone_ans" =~ ^[Yy]$ ]]; then
                        mkdir -p "$(dirname "$orig_path")"
                        if git clone "$clone_url" "$orig_path"; then
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
                if cp "$f" "$dst" 2>/dev/null; then
                    (( mem_copied++ ))
                else
                    echo "    ERROR: failed to write $dst" >&2
                fi
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
