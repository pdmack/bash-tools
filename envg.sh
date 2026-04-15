# envg - grep environment variables
# Usage: envg <pattern>
envg() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: envg <pattern>" >&2
        return 1
    fi
    env | grep -i "$1"
}
