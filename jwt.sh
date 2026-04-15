# jwt - decode and pretty-print a JWT payload (no signature verification)
# Usage: jwt <token>   or   echo <token> | jwt
jwt() {
    local token="${1:-}"
    if [[ -z "$token" && ! -t 0 ]]; then
        token=$(cat)
    fi
    if [[ -z "$token" ]]; then
        echo "Usage: jwt <token>" >&2
        return 1
    fi

    local payload
    payload=$(echo "$token" | cut -d. -f2)

    # Use Python for base64 decoding to avoid Linux/macOS flag differences
    python3 -c "
import base64, json, sys
payload = sys.argv[1]
# add padding
payload += '=' * (4 - len(payload) % 4)
decoded = base64.urlsafe_b64decode(payload).decode('utf-8')
print(json.dumps(json.loads(decoded), indent=2))
" "$payload"
}
