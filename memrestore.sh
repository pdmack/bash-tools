# memrestore - restore Claude and Codex config from $MEMBACK_DEST to this machine
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
#   5. Installs codex-global/config.toml into ~/.codex/ with project path
#      rewriting (home path transform)
#   6. Installs codex-global/memories/*.md into ~/.codex/memories/
#   7. Installs codex-global/skills/ into ~/.codex/skills/ (user skills only)
#   8. Restores Claude sessions from sessions.tar.gz per project
#   9. Restores Codex sessions from codex-global/sessions.tar.gz
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

_memrestore_detect_old_home() {
    local src_global="$1"
    local old_home=""
    if [[ -f "$src_global/settings.json" ]]; then
        old_home=$(jq -r '
            (.sandbox.filesystem.denyRead // [])[]
            | select(test("^/(home|Users)/"))
            | capture("^(?P<h>/(home|Users)/[^/]+)").h
        ' "$src_global/settings.json" 2>/dev/null | sort -u | head -1)
    fi
    if [[ -z "$old_home" && -f "$src_global/../codex-global/config.toml" ]]; then
        local _proj_path
        _proj_path=$(sed -n 's/.*\[projects\."\(\/[^"]*\)".*/\1/p' "$src_global/../codex-global/config.toml" 2>/dev/null | head -1)
        if [[ "$_proj_path" =~ ^(/home/[^/]+) ]]; then
            old_home="${BASH_REMATCH[1]}"
        elif [[ "$_proj_path" =~ ^(/Users/[^/]+) ]]; then
            old_home="${BASH_REMATCH[1]}"
        fi
    fi
    echo "$old_home"
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

    # Pull latest backup before restoring
    if git -C "$skills_dir" rev-parse --git-dir &>/dev/null; then
        echo "memrestore: pulling latest from $(git -C "$skills_dir" remote get-url origin 2>/dev/null)..."
        if ! git -C "$skills_dir" pull --ff-only 2>&1; then
            echo "memrestore: warning: git pull failed — restoring from local state" >&2
        fi
    fi

    local src_global="$skills_dir/claude-global"
    if [[ ! -d "$src_global" ]]; then
        echo "memrestore: $src_global not found — run memback on source machine first" >&2
        return 1
    fi

    local claude_dir="$HOME/.claude"
    local installed=0

    # Install a single file; skip if identical, prompt if changed and no --force
    _memrestore_cp() {
        local src="$1" dst="$2"
        if [[ -e "$dst" ]] && cmp -s "$src" "$dst"; then
            echo "  up to date: $dst"
            return 0
        fi
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

    local old_home
    old_home=$(_memrestore_detect_old_home "$src_global")

    echo "memrestore: platform=$platform src=$src_global"

    # CLAUDE.md
    if [[ -f "$src_global/CLAUDE.md" ]]; then
        if $dry_run; then
            echo "  $src_global/CLAUDE.md → $claude_dir/CLAUDE.md"
        else
            _memrestore_cp "$src_global/CLAUDE.md" "$claude_dir/CLAUDE.md"
        fi
    fi

    # Global memories (~/.claude/memory/)
    if [[ -d "$src_global/memory" ]]; then
        while IFS= read -r f; do
            local rel="${f#$src_global/memory/}"
            local dst="$claude_dir/memory/$rel"
            if $dry_run; then
                echo "  $f → $dst"
            else
                _memrestore_cp "$f" "$dst"
            fi
        done < <(find "$src_global/memory" -type f -name "*.md" 2>/dev/null)
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
                local dst="$claude_dir/settings.json"
                if [[ -e "$dst" ]] && cmp -s "$tmp" "$dst"; then
                    echo "  up to date: $dst"
                elif $force || [[ ! -e "$dst" ]]; then
                    mkdir -p "$claude_dir"
                    cp "$tmp" "$dst"
                    echo "  installed $dst"
                    (( installed++ ))
                else
                    printf "memrestore: %s exists — overwrite? [y/N] " "$dst"
                    read -r ans
                    if [[ "$ans" =~ ^[Yy]$ ]]; then
                        mkdir -p "$claude_dir"
                        cp "$tmp" "$dst"
                        echo "  installed $dst"
                        (( installed++ ))
                    else
                        echo "  skipped $dst"
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

            # Check if memories need updating
            local memories_up_to_date=false
            if [[ -n "$matched_key" ]]; then
                local target_check="$claude_dir/projects/$matched_key/memory"
                memories_up_to_date=true
                while IFS= read -r f; do
                    local rel="${f#${memory_src}}"
                    [[ -f "$target_check/$rel" ]] && cmp -s "$f" "$target_check/$rel" && continue
                    memories_up_to_date=false
                    break
                done < <(find "$memory_src" -name "*.md" -type f 2>/dev/null)
            fi

            local target_dir=""

            # Resolve target_dir: either from matched key or by prompting
            if [[ -n "$matched_key" ]]; then
                target_dir="$claude_dir/projects/$matched_key/memory"
                if $memories_up_to_date; then
                    printf "  %-35s up to date\n" "$display_name"
                else
                    printf "  %-35s [found]      restore %s file(s)? [Y/n] " "$display_name" "$file_count"
                    if $dry_run; then
                        echo "(dry run)"
                    else
                        local ans
                        read -r ans
                        ans="${ans:-y}"
                        if [[ "$ans" =~ ^[Yy]$ ]]; then
                            local mem_found=0 mem_copied=0
                            while IFS= read -r f; do
                                local rel="${f#${memory_src}}"
                                local dst="$target_dir/$rel"
                                (( mem_found++ ))
                                if [[ -f "$dst" ]] && cmp -s "$f" "$dst"; then
                                    continue
                                fi
                                mkdir -p "$(dirname "$dst")"
                                if cp "$f" "$dst" 2>/dev/null; then
                                    (( mem_copied++ ))
                                else
                                    echo "    ERROR: failed to write $dst" >&2
                                fi
                            done < <(find "$memory_src" -name "*.md" -type f 2>/dev/null)
                            echo "    restored $mem_copied/$mem_found file(s) → $target_dir"
                            (( installed += mem_copied ))
                        fi
                    fi
                fi
            else
                printf "  %-35s [not found]  restore %s file(s)? [y/N] " "$display_name" "$file_count"
                if $dry_run; then
                    echo "(dry run)"
                else
                    local ans
                    read -r ans
                    ans="${ans:-n}"
                    if [[ "$ans" =~ ^[Yy]$ ]]; then
                        local meta_file="$memory_src/.meta.json"
                        local remote_url="" orig_path=""
                        if [[ -f "$meta_file" ]]; then
                            remote_url=$(jq -r '.remote_url // ""' "$meta_file")
                            orig_path=$(jq -r '.local_path // ""' "$meta_file" \
                                | sed "s|^/home/[^/]*/|$HOME/|; s|^/Users/[^/]*/|$HOME/|")
                        fi

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

                        local mem_found=0 mem_copied=0
                        while IFS= read -r f; do
                            local rel="${f#${memory_src}}"
                            local dst="$target_dir/$rel"
                            (( mem_found++ ))
                            if [[ -f "$dst" ]] && cmp -s "$f" "$dst"; then
                                continue
                            fi
                            mkdir -p "$(dirname "$dst")"
                            if cp "$f" "$dst" 2>/dev/null; then
                                (( mem_copied++ ))
                            else
                                echo "    ERROR: failed to write $dst" >&2
                            fi
                        done < <(find "$memory_src" -name "*.md" -type f 2>/dev/null)
                        echo "    restored $mem_copied/$mem_found file(s) → $target_dir"
                        (( installed += mem_copied ))
                    else
                        continue
                    fi
                fi
            fi

            # Sessions — always restore regardless of memory state
            local sessions_archive="$memory_src/sessions.tar.gz"
            if [[ -f "$sessions_archive" && -n "$target_dir" ]]; then
                local sessions_target
                sessions_target=$(dirname "$target_dir")
                if $dry_run; then
                    echo "    sessions.tar.gz → $sessions_target/"
                    [[ -n "$old_home" && "$old_home" != "$HOME" ]] && echo "    transforms: $old_home → $HOME"
                else
                    local tmpdir
                    tmpdir=$(mktemp -d)
                    tar xzf "$sessions_archive" -C "$tmpdir" 2>/dev/null
                    local s_new=0
                    mkdir -p "$sessions_target"
                    while IFS= read -r sf; do
                        local sname
                        sname=$(basename "$sf")
                        if [[ -f "$sessions_target/$sname" ]] && [[ "$sessions_target/$sname" -nt "$sf" ]]; then
                            continue
                        fi
                        if [[ -n "$old_home" && "$old_home" != "$HOME" ]]; then
                            sed "s|$old_home|$HOME|g" "$sf" > "$sessions_target/$sname"
                        else
                            cp "$sf" "$sessions_target/$sname"
                        fi
                        (( s_new++ ))
                    done < <(find "$tmpdir" -name "*.jsonl" -type f 2>/dev/null)
                    rm -rf "$tmpdir"
                    if (( s_new > 0 )); then
                        echo "    restored $s_new new session(s) → $sessions_target/"
                        (( installed += s_new ))
                    fi
                fi
            fi
        done
    fi

    # Codex config
    local src_codex="$skills_dir/codex-global"
    local codex_dir="$HOME/.codex"
    if [[ -d "$src_codex" ]]; then
        echo ""
        echo "memrestore: codex config"

        # config.toml — rewrite home paths in project keys
        if [[ -f "$src_codex/config.toml" ]]; then
            if $dry_run; then
                echo "  $src_codex/config.toml → $codex_dir/config.toml"
                echo "    transforms: home path → \$HOME"
            else
                local tmp
                tmp=$(mktemp)
                local old_home_toml
                local _proj_path
                _proj_path=$(sed -n 's/.*\[projects\."\(\/[^"]*\)".*/\1/p' "$src_codex/config.toml" 2>/dev/null | head -1)
                old_home_toml=""
                if [[ "$_proj_path" =~ ^(/home/[^/]+) ]]; then
                    old_home_toml="${BASH_REMATCH[1]}"
                elif [[ "$_proj_path" =~ ^(/Users/[^/]+) ]]; then
                    old_home_toml="${BASH_REMATCH[1]}"
                fi
                if [[ -n "$old_home_toml" && "$old_home_toml" != "$HOME" ]]; then
                    sed "s|$old_home_toml|$HOME|g" "$src_codex/config.toml" > "$tmp"
                else
                    cp "$src_codex/config.toml" "$tmp"
                fi
                _memrestore_cp "$tmp" "$codex_dir/config.toml"
                rm -f "$tmp"
            fi
        fi

        # memories/*.md
        if [[ -d "$src_codex/memories" ]]; then
            while IFS= read -r f; do
                local dst="$codex_dir/memories/$(basename "$f")"
                if $dry_run; then
                    echo "  $f → $dst"
                else
                    _memrestore_cp "$f" "$dst"
                fi
            done < <(find "$src_codex/memories" -maxdepth 1 -type f -name "*.md" 2>/dev/null)
        fi

        # sessions, skipping those that already exist
        if [[ -f "$src_codex/sessions.tar.gz" ]]; then
            local sessions_dst="$codex_dir/sessions"
            if $dry_run; then
                echo "  $src_codex/sessions.tar.gz → $sessions_dst/"
                [[ -n "$old_home" && "$old_home" != "$HOME" ]] && echo "    transforms: $old_home → $HOME"
            else
                local tmpdir
                tmpdir=$(mktemp -d)
                tar xzf "$src_codex/sessions.tar.gz" -C "$tmpdir" 2>/dev/null
                local s_new=0
                while IFS= read -r sf; do
                    local rel="${sf#$tmpdir/}"
                    local dst="$sessions_dst/$rel"
                    if [[ -f "$dst" ]] && [[ "$dst" -nt "$sf" ]]; then
                        continue
                    fi
                    mkdir -p "$(dirname "$dst")"
                    if [[ -n "$old_home" && "$old_home" != "$HOME" ]]; then
                        sed "s|$old_home|$HOME|g" "$sf" > "$dst"
                    else
                        cp "$sf" "$dst"
                    fi
                    (( s_new++ ))
                done < <(find "$tmpdir" -name "*.jsonl" -type f 2>/dev/null)
                rm -rf "$tmpdir"
                if (( s_new > 0 )); then
                    echo "  restored $s_new new codex session(s) → $sessions_dst/"
                    (( installed += s_new ))
                fi
            fi
        fi

        # user skills (excluding .system/)
        if [[ -d "$src_codex/skills" ]]; then
            while IFS= read -r f; do
                local rel="${f#$src_codex/skills/}"
                local dst="$codex_dir/skills/$rel"
                if $dry_run; then
                    echo "  $f → $dst"
                else
                    _memrestore_cp "$f" "$dst"
                fi
            done < <(find "$src_codex/skills" -not -path '*/.system/*' -type f 2>/dev/null)
        fi
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
