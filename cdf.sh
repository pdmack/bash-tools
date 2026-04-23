# cdf - find and cd to a directory by name
# Usage: cdf <query> [root] [-h|--hidden]
#   root        search root, defaults to . (current directory)
#   -h|--hidden include hidden directories (excluded by default)
# Warns strongly if root is / or a first-tier system directory.
cdf() {
    local query="" root="." hidden=false

    for arg in "$@"; do
        case "$arg" in
            -h|--hidden) hidden=true ;;
            -*) echo "cdf: unknown option '$arg'" >&2; return 1 ;;
            *)  [[ -z "$query" ]] && query="$arg" || root="$arg" ;;
        esac
    done

    if [[ -z "$query" ]]; then
        echo "Usage: cdf <query> [root] [-h|--hidden]" >&2
        return 1
    fi

    local abs_root
    abs_root=$(realpath "$root" 2>/dev/null || echo "$root")

    # Warn against searching from / or first-tier dirs
    local -a danger=("/" "/usr" "/bin" "/sbin" "/lib" "/lib64" "/etc"
                     "/home" "/var" "/opt" "/tmp" "/proc" "/sys" "/dev"
                     "/run" "/boot" "/srv" "/snap")
    for d in "${danger[@]}"; do
        if [[ "$abs_root" == "$d" ]]; then
            echo "cdf: WARNING: searching from '$abs_root' will be extremely slow and noisy." >&2
            echo "     Specify a narrower root, e.g.: cdf $query ~/github" >&2
            read -r -p "     Continue anyway? [y/N] " confirm
            [[ "${confirm,,}" == "y" ]] || { echo "cdf: aborted"; return 1; }
            break
        fi
    done

    local matches=()
    # -prune stops descent into matched dirs; hidden exclusion uses ( -name ".*" -prune ) -o
    # so hidden dirs are pruned rather than just filtered, which avoids traversing .git etc.
    local find_cmd
    if $hidden; then
        find_cmd=("$abs_root" -type d -iname "*${query}*" -print -prune)
    else
        find_cmd=("$abs_root" '(' -name ".*" -prune ')' -o '(' -type d -iname "*${query}*" -print -prune ')')
    fi

    while IFS= read -r d; do
        matches+=("$d")
    done < <(find "${find_cmd[@]}" 2>/dev/null | sort)

    if (( ${#matches[@]} == 0 )); then
        echo "cdf: no directory matching '$query' under $abs_root" >&2
        return 1
    elif (( ${#matches[@]} == 1 )); then
        cd "${matches[0]}"
    else
        local i
        for i in "${!matches[@]}"; do
            printf "  [%d] %s\n" "$i" "${matches[$i]}"
        done
        echo
        read -r -p "Pick a number: " pick
        if [[ -z "${matches[$pick]:-}" ]]; then
            echo "cdf: invalid selection" >&2
            return 1
        fi
        cd "${matches[$pick]}"
    fi
}
