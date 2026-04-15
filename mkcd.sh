# mkcd - mkdir and cd in one step
# Usage: mkcd <dir>
mkcd() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: mkcd <dir>" >&2
        return 1
    fi
    mkdir -p "$1" && cd "$1"
}
