# serve - start a local HTTP server in the current directory
# Usage: serve [port]   (default: 8000)
serve() {
    local port="${1:-8000}"
    echo "Serving $(pwd) at http://localhost:${port}"
    python3 -m http.server "$port"
}
