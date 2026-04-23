# cdpath - manage CDPATH entries in site.sh
# Usage: cdpath show               list current CDPATH entries
#        cdpath scan               suggest candidate dirs from home
#        cdpath add <dir>          add a dir to CDPATH in site.sh
#        cdpath rm <dir>           remove a dir from CDPATH in site.sh
cdpath() {
    local cmd="${1:-show}"
    local local_sh
    local_sh="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/site.sh"

    case "$cmd" in
        show)
            echo "CDPATH entries:"
            echo "$CDPATH" | tr ':' '\n' | grep -v '^$' | while read -r d; do
                if [[ -d "$d" ]]; then
                    echo "  $d"
                else
                    echo "  $d  (missing)"
                fi
            done
            ;;

        scan)
            local candidates=()
            local counts=()
            while IFS= read -r d; do
                local count
                count=$(find "$d" -maxdepth 2 -mindepth 2 -name ".git" -type d 2>/dev/null | wc -l)
                if (( count >= 2 )); then
                    candidates+=("$d")
                    counts+=("$count")
                fi
            done < <(find "$HOME" -maxdepth 2 -mindepth 1 -type d -not -path '*/\.*' 2>/dev/null | sort)

            if (( ${#candidates[@]} == 0 )); then
                echo "No candidates found."
                return 0
            fi

            echo "Candidate dirs (contain 2+ git repos):"
            echo
            for i in "${!candidates[@]}"; do
                local already=""
                [[ ":$CDPATH:" == *":${candidates[$i]}:"* ]] && already="  (already in CDPATH)"
                printf "  [%d] %s  (%s repos)%s\n" "$i" "${candidates[$i]}" "${counts[$i]}" "$already"
            done
            echo
            read -r -p "Add which? (space-separated numbers, or 'a' for all, enter to skip): " selection
            [[ -z "$selection" ]] && return 0

            local indices=()
            if [[ "$selection" == "a" ]]; then
                indices=( "${!candidates[@]}" )
            else
                read -ra indices <<< "$selection"
            fi

            for i in "${indices[@]}"; do
                if [[ -n "${candidates[$i]:-}" ]]; then
                    cdpath add "${candidates[$i]}"
                else
                    echo "cdpath scan: invalid selection '$i'" >&2
                fi
            done
            ;;

        add)
            local dir="${2:-}"
            if [[ -z "$dir" ]]; then
                echo "Usage: cdpath add <dir>" >&2
                return 1
            fi
            dir="$(cd "$dir" 2>/dev/null && pwd)"
            if [[ -z "$dir" ]]; then
                echo "cdpath add: directory not found" >&2
                return 1
            fi
            # Replace $HOME with $HOME literal for portability
            local entry="${dir/#$HOME/\$HOME}"

            if [[ ":$CDPATH:" == *":${dir}:"* ]]; then
                echo "cdpath add: already in CDPATH: $dir"
                return 0
            fi
            if grep -q "CDPATH=" "$local_sh" 2>/dev/null; then
                # Append to existing CDPATH line
                sed -i.bak "s|export CDPATH=\"\(.*\)\"|export CDPATH=\"\1:${entry}\"|" "$local_sh" \
                    && rm -f "${local_sh}.bak"
            else
                echo "export CDPATH=\".:${entry}\"" >> "$local_sh"
            fi
            export CDPATH="${CDPATH}:${dir}"
            echo "Added: $dir"
            ;;

        rm)
            local dir="${2:-}"
            if [[ -z "$dir" ]]; then
                echo "Usage: cdpath rm <dir>" >&2
                return 1
            fi
            dir="$(cd "$dir" 2>/dev/null && pwd || echo "$dir")"
            local entry="${dir/#$HOME/\$HOME}"

            sed -i.bak "s|:${entry}||g; s|${entry}:||g" "$local_sh" \
                && rm -f "${local_sh}.bak"
            export CDPATH="$(echo "$CDPATH" | tr ':' '\n' | grep -v "^${dir}$" | tr '\n' ':' | sed 's/:$//')"
            echo "Removed: $dir"
            ;;

        *)
            echo "Usage: cdpath show|scan|add|rm" >&2
            return 1
            ;;
    esac
}

# Private helper used by gclean, gdiff, grepos.
_bash_tools_cdpath_repos() {
    local raw_dirs=() cdpath_dirs=() seen=()
    IFS=: read -ra raw_dirs <<< "${CDPATH:-$HOME}"
    for d in "${raw_dirs[@]}"; do
        [[ "$d" = /* ]] && cdpath_dirs+=("$d") || cdpath_dirs+=("$HOME/${d#./}")
    done
    for dir in "${cdpath_dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r d; do
            [[ -d "$d/.git" ]] || continue
            local already=false
            for s in "${seen[@]:-}"; do [[ "$s" == "$d" ]] && already=true && break; done
            if ! $already; then
                echo "$d"
                seen+=("$d")
            fi
        done < <(find "$dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort)
    done
}
