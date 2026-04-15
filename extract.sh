# extract - unpack an archive into the current directory
# Usage: extract <file>
extract() {
    local file="${1:-}"
    if [[ -z "$file" ]]; then
        echo "Usage: extract <file>" >&2
        return 1
    fi
    if [[ ! -f "$file" ]]; then
        echo "extract: '$file' not found" >&2
        return 1
    fi

    # Warn if extraction target already exists
    local target=""
    case "$file" in
        *.tar.gz|*.tgz)   target=$(tar tzf "$file" 2>/dev/null | head -1 | cut -d/ -f1) ;;
        *.tar.bz2|*.tbz2) target=$(tar tjf "$file" 2>/dev/null | head -1 | cut -d/ -f1) ;;
        *.tar.xz|*.txz)   target=$(tar tJf "$file" 2>/dev/null | head -1 | cut -d/ -f1) ;;
        *.tar)             target=$(tar tf  "$file" 2>/dev/null | head -1 | cut -d/ -f1) ;;
        *.zip)             target=$(unzip -qql "$file" 2>/dev/null | head -1 | awk '{print $4}' | cut -d/ -f1) ;;
    esac
    if [[ -n "$target" && -e "$target" ]]; then
        read -r -p "extract: '$target' already exists. Overwrite? [y/N] " confirm
        [[ "${confirm,,}" == "y" ]] || { echo "Aborted." >&2; return 1; }
    fi

    case "$file" in
        *.tar.gz|*.tgz)   tar xzf "$file" ;;
        *.tar.bz2|*.tbz2) tar xjf "$file" ;;
        *.tar.xz|*.txz)   tar xJf "$file" ;;
        *.tar)             tar xf  "$file" ;;
        *.zip)             unzip "$file" ;;
        *.gz)              gunzip "$file" ;;
        *.bz2)             bunzip2 "$file" ;;
        *.xz)              unxz "$file" ;;
        *.7z)              7z x "$file" ;;
        *.rar)             unrar x "$file" ;;
        *) echo "extract: unsupported format '$file'" >&2; return 1 ;;
    esac
}
