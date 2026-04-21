# _bash_tools_cdpath_repos - print deduped git repo paths from CDPATH, one per line
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
