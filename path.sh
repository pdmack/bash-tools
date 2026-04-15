# path - pretty-print PATH one entry per line
path() {
    echo "$PATH" | tr ':' '\n'
}
