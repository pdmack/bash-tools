# maas - browse and authenticate to MaaS MCP servers
# Usage: maas                   list MCP catalog with auth requirements
#        maas auth [server]     open auth URL; server = auth key or MCP name
#        maas check [server]    check if auth endpoint is reachable
# Configure in site.sh: MAAS_SERVERS (auth endpoints), MAAS_MCP (catalog)

_maas_open_url() {
    local server="$1" url="$2"
    echo "Opening auth for $server:"
    echo "  $url"
    if [[ "$(uname)" == "Darwin" ]]; then
        open "$url" 2>/dev/null
    elif [[ -n "$DISPLAY" || -n "$WAYLAND_DISPLAY" ]]; then
        xdg-open "$url" 2>/dev/null
    else
        echo "  (headless — copy URL above to authenticate)"
    fi
}

_maas_resolve_auth() {
    # Given a name, return the auth key — checks auth keys first, then MCP catalog
    local name="$1"
    if [[ -n "${MAAS_SERVERS[$name]:-}" ]]; then
        echo "$name"
    elif [[ -n "${MAAS_MCP[$name]:-}" ]]; then
        echo "${MAAS_MCP[$name]}" | cut -d'|' -f3
    fi
}

_maas_pick_auth() {
    local keys=()
    while IFS= read -r k; do keys+=("$k"); done < <(echo "${!MAAS_SERVERS[@]}" | tr ' ' '\n' | sort)
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

    if [[ ${#MAAS_SERVERS[@]} -eq 0 ]]; then
        echo "maas: MAAS_SERVERS not configured — add to site.sh" >&2
        return 1
    fi

    case "$cmd" in
        auth)
            local name="${2:-}"
            if [[ -z "$name" ]]; then
                name=$(_maas_pick_auth) || return 1
            fi
            local auth_key
            auth_key=$(_maas_resolve_auth "$name")
            if [[ -z "$auth_key" ]]; then
                echo "maas: unknown server '$name'" >&2; return 1
            fi
            local url="${MAAS_SERVERS[$auth_key]:-}"
            if [[ -z "$url" ]]; then
                echo "maas: no auth URL configured for '$auth_key'" >&2; return 1
            fi
            _maas_open_url "$auth_key" "$url"
            ;;
        check)
            local name="${2:-}"
            if [[ -z "$name" ]]; then
                name=$(_maas_pick_auth) || return 1
            fi
            local auth_key
            auth_key=$(_maas_resolve_auth "$name")
            if [[ -z "$auth_key" ]]; then
                echo "maas: unknown server '$name'" >&2; return 1
            fi
            local url="${MAAS_SERVERS[$auth_key]:-}"
            local code
            code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
            case "$code" in
                200|302|303) echo "maas: $auth_key reachable (HTTP $code)" ;;
                401|403)     echo "maas: $auth_key reachable but not authenticated (HTTP $code)" ;;
                000)         echo "maas: $auth_key unreachable (no response)" ;;
                *)           echo "maas: $auth_key HTTP $code" ;;
            esac
            ;;
        "")
            if [[ ${#MAAS_MCP[@]} -gt 0 ]]; then
                printf "%-14s %-20s %-s\n" "NAME" "DISPLAY" "AUTH"
                printf "%-14s %-20s %-s\n" "----" "-------" "----"
                for key in $(echo "${!MAAS_MCP[@]}" | tr ' ' '\n' | sort); do
                    IFS='|' read -r display _ auth_key <<< "${MAAS_MCP[$key]}"
                    printf "%-14s %-20s %s\n" "$key" "$display" "$auth_key"
                done
            else
                printf "%-16s %s\n" "AUTH SERVER" "URL"
                printf "%-16s %s\n" "-----------" "---"
                for k in $(echo "${!MAAS_SERVERS[@]}" | tr ' ' '\n' | sort); do
                    printf "%-16s %s\n" "$k" "${MAAS_SERVERS[$k]}"
                done
            fi
            ;;
        *)
            echo "Usage: maas [auth|check] [server]" >&2
            return 1
            ;;
    esac
}
