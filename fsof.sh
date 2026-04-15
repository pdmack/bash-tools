# fsof - friendly lsof wrapper (files open for/by...)
# Usage: fsof listen      who is listening on what IPv4 port
#        fsof <port>      what process is using this port
#        fsof <file>      what process has this file open
#        fsof <dir>       what processes have files open in this dir
#        fsof <pid>       what files this process has open
#        fsof net         all network connections
fsof() {
    local arg="${1:-}"
    if [[ -z "$arg" ]]; then
        echo "Usage: fsof <listen|port|file|dir|pid|net>" >&2
        return 1
    fi

    case "$arg" in
        listen)
            local out
            out=$(lsof -i4 -P -n | grep LISTEN)
            if [[ -z "$out" ]]; then
                echo "fsof: no IPv4 listeners found"
            else
                echo "$out"
            fi
            ;;
        net)
            lsof -i -P -n
            ;;
        [0-9]*)
            if kill -0 "$arg" 2>/dev/null; then
                lsof -p "$arg"
            else
                lsof -i ":${arg}" -P -n
            fi
            ;;
        *)
            if [[ -d "$arg" ]]; then
                lsof +D "$arg"
            elif [[ -e "$arg" ]]; then
                lsof "$arg"
            else
                echo "fsof: '$arg' not found — use listen, a port number, file, dir, pid, or 'net'" >&2
                return 1
            fi
            ;;
    esac
}
