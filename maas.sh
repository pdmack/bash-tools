# maas - browse and authenticate to MaaS MCP servers
# Usage: maas                   list configured servers and auth URLs
#        maas auth <server>     open auth URL in browser
#        maas check <server>    check if auth endpoint is reachable
# Configure servers in site.sh:
#   declare -A MAAS_SERVERS=([jira]="https://..." [gitlab]="https://..." ...)
maas() {
    local cmd="${1:-}"

    if [[ ${#MAAS_SERVERS[@]} -eq 0 ]]; then
        echo "maas: MAAS_SERVERS not configured — add to site.sh" >&2
        return 1
    fi

    case "$cmd" in
        auth)
            local server="${2:-}"
            if [[ -z "$server" ]]; then
                echo "Usage: maas auth <server>" >&2
                echo "Servers: $(echo "${!MAAS_SERVERS[@]}" | tr ' ' '\n' | sort | tr '\n' ' ')" >&2
                return 1
            fi
            local url="${MAAS_SERVERS[$server]:-}"
            if [[ -z "$url" ]]; then
                echo "maas: unknown server '$server'" >&2
                echo "Servers: $(echo "${!MAAS_SERVERS[@]}" | tr ' ' '\n' | sort | tr '\n' ' ')" >&2
                return 1
            fi
            echo "Opening auth for $server:"
            echo "  $url"
            if [[ "$(uname)" == "Darwin" ]]; then
                open "$url" 2>/dev/null
            elif [[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]]; then
                xdg-open "$url" 2>/dev/null
            else
                echo "  (headless — copy URL above to authenticate)"
            fi
            ;;
        check)
            local server="${2:-}"
            if [[ -z "$server" ]]; then
                echo "Usage: maas check <server>" >&2
                return 1
            fi
            local url="${MAAS_SERVERS[$server]:-}"
            if [[ -z "$url" ]]; then
                echo "maas: unknown server '$server'" >&2
                return 1
            fi
            local code
            code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
            case "$code" in
                200|302|303) echo "maas: $server reachable (HTTP $code)" ;;
                401|403)     echo "maas: $server reachable but not authenticated (HTTP $code)" ;;
                000)         echo "maas: $server unreachable (no response)" ;;
                *)           echo "maas: $server HTTP $code" ;;
            esac
            ;;
        "")
            printf "%-16s %s\n" "SERVER" "AUTH URL"
            printf "%-16s %s\n" "------" "--------"
            for server in $(echo "${!MAAS_SERVERS[@]}" | tr ' ' '\n' | sort); do
                printf "%-16s %s\n" "$server" "${MAAS_SERVERS[$server]}"
            done
            ;;
        *)
            echo "Usage: maas [auth|check] <server>" >&2
            return 1
            ;;
    esac
}
