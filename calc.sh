# calc - quick calculator
# Usage: calc <expression>   e.g. calc 2^20  calc 1024*1024*512  calc '(8+2)/3'
calc() {
    if [[ -z "${1:-}" ]]; then
        echo "Usage: calc <expression>" >&2
        return 1
    fi
    python3 -c "print($*)"
}
