# hist - search command history
# Usage: hist <pattern>
hist() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: hist <pattern>" >&2
        return 1
    fi
    history | grep -i "$1"
}
