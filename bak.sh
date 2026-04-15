# bak - create a timestamped backup of a file
# Usage: bak <file>
bak() {
    local file="${1:-}"
    if [[ -z "$file" ]]; then
        echo "Usage: bak <file>" >&2
        return 1
    fi
    if [[ ! -e "$file" ]]; then
        echo "bak: '$file' not found" >&2
        return 1
    fi

    local dest="${file}.bak.$(date +%Y%m%d_%H%M%S)"
    if [[ -e "$dest" ]]; then
        read -r -p "bak: '$dest' already exists. Overwrite? [y/N] " confirm
        [[ "${confirm,,}" == "y" ]] || { echo "Aborted." >&2; return 1; }
    fi

    cp -a "$file" "$dest" && echo "$dest"
}
