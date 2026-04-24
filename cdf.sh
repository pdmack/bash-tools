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
    abs_root=$(cd "$root" 2>/dev/null && pwd || echo "$root")

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

    # Build prune list: hidden dirs always pruned (unless --hidden), plus non-project dirs.
    # macOS: also prune Library and Applications which contain huge non-project subtrees.
    # User can extend via BASH_TOOLS_CDF_PRUNE (space-separated names) in site.sh.
    local -a prune_names=()
    $hidden || prune_names+=(".*")
    prune_names+=("node_modules" "site-packages")
    [[ "$(uname -s)" == "Darwin" ]] && prune_names+=("Library" "Applications")
    [[ -n "${BASH_TOOLS_CDF_PRUNE:-}" ]] && read -ra _extra <<< "$BASH_TOOLS_CDF_PRUNE" && prune_names+=("${_extra[@]}")

    # Build: '(' -name n1 -o -name n2 ... ')' -prune -o '(' -type d -iname "*query*" -print -prune ')'
    local -a prune_expr=('(')
    local _n
    for _n in "${prune_names[@]}"; do
        (( ${#prune_expr[@]} > 1 )) && prune_expr+=(-o)
        prune_expr+=(-name "$_n")
    done
    prune_expr+=(')' -prune)

    local find_cmd
    find_cmd=("$abs_root" "${prune_expr[@]}" -o '(' -type d -iname "*${query}*" -print -prune ')')

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
