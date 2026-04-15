# up - go up n directory levels
# Usage: up [n]   (default: 1)
up() {
    local n="${1:-1}"
    if ! [[ "$n" =~ ^[0-9]+$ ]] || (( n < 1 )); then
        echo "Usage: up [n]" >&2
        return 1
    fi
    local path=""
    for (( i = 0; i < n; i++ )); do
        path="../$path"
    done
    cd "$path"
}
