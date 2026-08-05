# orgclone - clone all repos from a GitHub org or GitLab group
# Usage: orgclone <org> [--dest <dir>] [--gitlab [host]] [--update] [--archived] [-n]
#   --gitlab [host]  use GitLab instead of GitHub (host defaults to gitlab.com)
#   --dest <dir>     destination directory (default: current dir)
#   -u|--update      pull repos that already exist locally (default: skip)
#   --archived       include archived repos (default: excluded)
#   -n|--dry-run     list repos without cloning
#
# Auth:
#   GitHub  — gh CLI (run 'gh auth login'; SSO orgs need token authorized at
#             github.com/settings/tokens after login)
#   GitLab  — glab CLI preferred; falls back to GITLAB_TOKEN env var + curl
orgclone() {
    local org="" dest="." provider="github" gitlab_host="gitlab.com"
    local do_update=false do_archived=false dry_run=false
    local USAGE="Usage: orgclone <org> [--dest <dir>] [--gitlab [host]] [--update] [--archived] [-n]"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --gitlab)
                provider="gitlab"; shift
                [[ $# -gt 0 && "$1" != -* ]] && { gitlab_host="$1"; shift; }
                ;;
            --github)     provider="github"; shift ;;
            --dest)       dest="$2"; shift 2 ;;
            -u|--update)  do_update=true; shift ;;
            --archived)   do_archived=true; shift ;;
            -n|--dry-run) dry_run=true; shift ;;
            -*)
                echo "orgclone: unknown option: $1" >&2
                echo "$USAGE" >&2; return 1 ;;
            *)
                [[ -z "$org" ]] && { org="$1"; shift; } \
                    || { echo "orgclone: unexpected argument: $1" >&2; return 1; }
                ;;
        esac
    done

    if [[ -z "$org" ]]; then
        echo "$USAGE" >&2; return 1
    fi

    local urls=()

    if [[ "$provider" == "github" ]]; then
        if ! command -v gh &>/dev/null; then
            echo "orgclone: gh CLI not found" >&2; return 1
        fi
        if ! gh auth status &>/dev/null 2>&1; then
            echo "orgclone: not authenticated — run: gh auth login" >&2; return 1
        fi

        local extra=()
        $do_archived || extra+=(--no-archived)

        local gh_json gh_rc
        gh_json=$(gh repo list "$org" --limit 1000 "${extra[@]}" --json sshUrl 2>&1)
        gh_rc=$?

        if (( gh_rc != 0 )); then
            echo "orgclone: gh repo list failed:" >&2
            echo "$gh_json" >&2
            if grep -qi "sso\|saml\|authoriz\|403" <<< "$gh_json"; then
                echo >&2
                echo "orgclone: hint — your token may need SSO authorization for '${org}'." >&2
                echo "  After 'gh auth login', visit github.com/settings/tokens and" >&2
                echo "  click 'Authorize' next to the token for the ${org} org." >&2
            fi
            return 1
        fi

        mapfile -t urls < <(
            python3 -c "import sys,json; [print(r['sshUrl']) for r in json.load(sys.stdin)]" \
                <<< "$gh_json"
        )

        if (( ${#urls[@]} == 0 )); then
            echo "orgclone: no repos returned for '${org}'" >&2
            echo "orgclone: if the org exists, your token may need SSO authorization." >&2
            echo "  Visit github.com/settings/tokens and authorize it for the ${org} org." >&2
            return 1
        fi

    else
        # GitLab — paginate groups API
        # Normalize gitlab_host to a plain hostname (strip ssh://, port, user, trailing slash)
        gitlab_host=$(python3 -c "
import urllib.parse, sys
h = sys.argv[1]
parsed = urllib.parse.urlparse(h)
print(parsed.hostname if parsed.hostname else h.rstrip('/'))
" "$gitlab_host")

        local encoded_org
        encoded_org=$(python3 -c \
            "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$org")
        local archived_param=""
        $do_archived || archived_param="&archived=false"

        local _gl_fetch
        local _gl_parse='
import sys, json
raw = sys.stdin.read()
if not raw.strip():
    sys.exit(1)
try:
    data = json.loads(raw)
except json.JSONDecodeError as e:
    print("orgclone: invalid JSON from API:", e, file=sys.stderr)
    sys.exit(1)
if not isinstance(data, list):
    print("orgclone: API error:", data.get("message", data), file=sys.stderr)
    sys.exit(1)
for p in data:
    print(p["ssh_url_to_repo"])
'
        if command -v glab &>/dev/null; then
            _gl_fetch() {
                GITLAB_HOST="$gitlab_host" glab api \
                    "groups/${encoded_org}/projects?per_page=100&page=${1}${archived_param}" \
                    | python3 -c "$_gl_parse"
            }
        elif [[ -n "${GITLAB_TOKEN:-}" ]]; then
            _gl_fetch() {
                curl -fsSL -H "PRIVATE-TOKEN: $GITLAB_TOKEN" \
                    "https://${gitlab_host}/api/v4/groups/${encoded_org}/projects?per_page=100&page=${1}${archived_param}" \
                    | python3 -c "$_gl_parse"
            }
        else
            echo "orgclone: GitLab auth required — install glab or set GITLAB_TOKEN" >&2
            return 1
        fi

        local page=1 batch
        while true; do
            mapfile -t batch < <(_gl_fetch "$page")
            (( ${#batch[@]} == 0 )) && break
            urls+=("${batch[@]}")
            (( page++ ))
        done
        unset -f _gl_fetch

        if (( ${#urls[@]} == 0 )); then
            echo "orgclone: no repos returned for '${org}' on ${gitlab_host}" >&2
            echo "orgclone: check the group path and your token's access permissions" >&2
            return 1
        fi
    fi

    echo "orgclone: found ${#urls[@]} repo(s) in ${org}"

    if $dry_run; then
        printf '  %s\n' "${urls[@]}"
        return 0
    fi

    local preview=5
    printf '  %s\n' "${urls[@]:0:$preview}"
    (( ${#urls[@]} > preview )) && echo "  ... and $(( ${#urls[@]} - preview )) more"
    echo

    mkdir -p "$dest" || return 1
    read -r -p "Clone ${#urls[@]} repos into ${dest}? [y/N] " confirm
    [[ "${confirm,,}" != "y" ]] && { echo "Aborted."; return 0; }
    echo

    local cloned=0 updated=0 skipped=0 failed=0
    local failed_repos=()

    for url in "${urls[@]}"; do
        local name target
        name=$(basename "$url" .git)
        target="${dest}/${name}"

        if [[ -d "$target/.git" ]]; then
            if $do_update; then
                printf '→ pull  %s\n' "$name"
                if git -C "$target" pull --ff-only -q 2>/dev/null; then
                    (( updated++ ))
                else
                    echo "  failed (dirty or not fast-forwardable)"
                    (( failed++ )); failed_repos+=("$name")
                fi
            else
                printf '  skip  %s\n' "$name"
                (( skipped++ ))
            fi
        else
            printf '→ clone %s\n' "$name"
            if git clone -q "$url" "$target" 2>/dev/null; then
                (( cloned++ ))
            else
                echo "  failed"
                (( failed++ )); failed_repos+=("$name")
            fi
        fi
    done

    echo
    printf 'orgclone: done — cloned %d, updated %d, skipped %d, failed %d\n' \
        "$cloned" "$updated" "$skipped" "$failed"

    if (( ${#failed_repos[@]} > 0 )); then
        echo "orgclone: failed:"
        printf '  %s\n' "${failed_repos[@]}"
    fi
}
