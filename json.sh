# json - pretty-print JSON from stdin or a file
# Usage: json [file]   or   curl ... | json
json() {
    if [[ -n "${1:-}" ]]; then
        python3 -m json.tool "$1"
    else
        python3 -m json.tool
    fi
}
