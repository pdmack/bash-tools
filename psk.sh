# psk - show matching processes and kill with confirmation
# Usage: psk <filter> [-15] [all]
#   filter  substring match on user or command
#   -15     use SIGTERM instead of SIGKILL
#   all     kill all matches without picking; still prompts for confirmation
psk() {
    local query="" sig="-9" kill_all=false

    for arg in "$@"; do
        case "$arg" in
            -9)  sig="-9" ;;
            -15) sig="-15" ;;
            all) kill_all=true ;;
            *)   query="$arg" ;;
        esac
    done

    if [[ -z "$query" ]]; then
        echo "Usage: psk <filter> [-15] [all]" >&2
        return 1
    fi

    local pids=() lines=()
    while IFS= read -r line; do
        pids+=("$(awk '{print $2}' <<< "$line")")
        lines+=("$line")
    done < <(pss "$query" | tail -n +2)

    if (( ${#pids[@]} == 0 )); then
        echo "psk: no processes matching '$query'"
        return 0
    fi

    local i
    if $kill_all; then
        printf "    %-10s %6s %5s %5s  %s\n" "USER" "PID" "%CPU" "%MEM" "COMMAND"
        for i in "${!lines[@]}"; do echo "    ${lines[$i]}"; done
    else
        printf "  [#] %-10s %6s %5s %5s  %s\n" "USER" "PID" "%CPU" "%MEM" "COMMAND"
        for i in "${!lines[@]}"; do printf "  [%d] %s\n" "$i" "${lines[$i]}"; done
    fi
    echo

    local targets=()
    if $kill_all; then
        read -r -p "Kill all ${#pids[@]} process(es) with signal $sig? [y/N] " confirm
        [[ "${confirm,,}" == "y" ]] || { echo "psk: aborted"; return 0; }
        targets=("${pids[@]}")
    else
        read -r -p "Pick numbers to kill (e.g. 0 2 3), or 'all', or enter to abort: " picks
        [[ -n "$picks" ]] || { echo "psk: aborted"; return 0; }
        if [[ "$picks" == "all" ]]; then
            targets=("${pids[@]}")
        else
            for pick in $picks; do
                [[ -n "${pids[$pick]:-}" ]] || { echo "psk: invalid selection: $pick" >&2; continue; }
                targets+=("${pids[$pick]}")
            done
        fi
        (( ${#targets[@]} > 0 )) || { echo "psk: nothing selected"; return 0; }
        read -r -p "Kill ${#targets[@]} process(es) with signal $sig? [y/N] " confirm
        [[ "${confirm,,}" == "y" ]] || { echo "psk: aborted"; return 0; }
    fi

    for pid in "${targets[@]}"; do
        kill "$sig" "$pid" 2>/dev/null && echo "killed $pid" || echo "psk: failed to kill $pid"
    done
}
