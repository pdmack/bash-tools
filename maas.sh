# maas - browse MaaS MCP server catalog and check reachability
# Usage: maas                   list MCP catalog
#        maas check [server]    check if MCP server is reachable
# Configure in site.sh: MAAS_MCP catalog
# To authenticate: ask Claude Code to authenticate to the MCP server by name
#
# Note: assumes a centralized MCP-as-a-Service (MaaS) platform where multiple
# MCP servers share a common base URL and auth provider. Not applicable to
# individually-configured MCP servers.

_maas_pick_server() {
    local keys=()
    while IFS= read -r k; do keys+=("$k"); done < <(echo "${!MAAS_MCP[@]}" | tr ' ' '\n' | sort)
    local i
    for i in "${!keys[@]}"; do
        printf "  [%d] %s\n" "$i" "${keys[$i]}" >&2
    done
    printf "\n" >&2
    read -r -p "Pick a number: " pick </dev/tty
    [[ -n "${keys[$pick]:-}" ]] || { echo "maas: invalid selection" >&2; return 1; }
    echo "${keys[$pick]}"
}

maas() {
    local cmd="${1:-}"

    if [[ ${#MAAS_MCP[@]} -eq 0 ]]; then
        echo "maas: MAAS_MCP not configured — add to site.sh" >&2
        return 1
    fi

    case "$cmd" in
        check)
            local name="${2:-}"
            if [[ -z "$name" ]]; then
                name=$(_maas_pick_server) || return 1
            fi
            if [[ -z "${MAAS_MCP[$name]:-}" ]]; then
                echo "maas: unknown server '$name'" >&2; return 1
            fi
            local url
            url=$(echo "${MAAS_MCP[$name]}" | cut -d'|' -f2)
            local code
            code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
            case "$code" in
                200|302|303) echo "maas: $name reachable (HTTP $code)" ;;
                405)         echo "maas: $name reachable (HTTP 405 — MCP endpoint expects POST)" ;;
                401|403)     echo "maas: $name reachable but not authenticated (HTTP $code)" ;;
                000)         echo "maas: $name unreachable (no response)" ;;
                *)           echo "maas: $name HTTP $code" ;;
            esac
            ;;
        "")
            printf "%-14s %-20s %-s\n" "NAME" "DISPLAY" "AUTH"
            printf "%-14s %-20s %-s\n" "----" "-------" "----"
            for key in $(echo "${!MAAS_MCP[@]}" | tr ' ' '\n' | sort); do
                IFS='|' read -r display _ auth_key <<< "${MAAS_MCP[$key]}"
                printf "%-14s %-20s %s\n" "$key" "$display" "$auth_key"
            done
            ;;
        *)
            echo "Usage: maas [check [server]]" >&2
            return 1
            ;;
    esac
}
