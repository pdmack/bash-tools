# peek - list contents of an archive without extracting
# Usage: peek <file>
peek() {
    local file="${1:-}"
    if [[ -z "$file" ]]; then
        echo "Usage: peek <file>" >&2
        return 1
    fi
    if [[ ! -f "$file" ]]; then
        echo "peek: '$file' not found" >&2
        return 1
    fi

    case "$file" in
        *.tar.gz|*.tgz)   tar tzf "$file" ;;
        *.tar.bz2|*.tbz2) tar tjf "$file" ;;
        *.tar.xz|*.txz)   tar tJf "$file" ;;
        *.tar)             tar tf  "$file" ;;
        *.zip)             unzip -l "$file" ;;
        *.gz)              echo "(single compressed file)" ; zcat "$file" | file - ;;
        *.bz2)             echo "(single compressed file)" ; bzcat "$file" | file - ;;
        *.xz)              echo "(single compressed file)" ; xzcat "$file" | file - ;;
        *.7z)              7z l "$file" ;;
        *.rar)             unrar l "$file" ;;
        *) echo "peek: unsupported format '$file'" >&2; return 1 ;;
    esac
}
