# ksec - decode a Kubernetes docker registry secret, with fuzzy name match
# Usage: ksec <pattern> [-n namespace]
ksec() {
    local pattern="" namespace=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n) namespace="$2"; shift 2 ;;
            *)  pattern="$1"; shift ;;
        esac
    done

    if [[ -z "$pattern" ]]; then
        echo "Usage: ksec <pattern> [-n namespace]" >&2
        return 1
    fi

    local ns_args=()
    [[ -n "$namespace" ]] && ns_args=(-n "$namespace") || ns_args=(--all-namespaces)

    # Find docker secrets matching the pattern
    local matches
    matches=$(kubectl get secrets "${ns_args[@]}" \
        --field-selector type=kubernetes.io/dockerconfigjson \
        -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" \
        --no-headers 2>/dev/null \
        | grep -i "$pattern")

    if [[ -z "$matches" ]]; then
        # Fall back to any secret type matching the pattern
        matches=$(kubectl get secrets "${ns_args[@]}" \
            -o custom-columns="NS:.metadata.namespace,NAME:.metadata.name" \
            --no-headers 2>/dev/null \
            | grep -i "$pattern")
    fi

    if [[ -z "$matches" ]]; then
        echo "ksec: no secret found matching '$pattern'" >&2
        return 1
    fi

    local count
    count=$(echo "$matches" | wc -l)
    local ns name

    if (( count == 1 )); then
        ns=$(echo "$matches" | awk '{print $1}')
        name=$(echo "$matches" | awk '{print $2}')
    else
        echo "Multiple matches:"
        echo "$matches" | nl -w2 -s') '
        echo
        read -r -p "Pick a number: " pick
        ns=$(echo "$matches"   | sed -n "${pick}p" | awk '{print $1}')
        name=$(echo "$matches" | sed -n "${pick}p" | awk '{print $2}')
        if [[ -z "$name" ]]; then
            echo "ksec: invalid selection" >&2
            return 1
        fi
    fi

    echo "→ $ns/$name"
    echo

    # Try .dockerconfigjson first, then decode all data keys
    local docker_json
    docker_json=$(kubectl get secret "$name" -n "$ns" \
        -o jsonpath='{.data.\.dockerconfigjson}' 2>/dev/null | tr -d '[:space:]')

    if [[ -n "$docker_json" ]]; then
        echo "$docker_json" | base64 -d 2>/dev/null | python3 -m json.tool
    else
        # Generic: decode all data fields
        kubectl get secret "$name" -n "$ns" -o json 2>/dev/null \
            | python3 -c "
import sys, json, base64
s = json.load(sys.stdin)
for k, v in s.get('data', {}).items():
    print(f'--- {k} ---')
    try:
        decoded = base64.b64decode(v).decode('utf-8')
        try:    print(json.dumps(json.loads(decoded), indent=2))
        except: print(decoded)
    except:
        print(v)
"
    fi
}
