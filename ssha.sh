# ssha - start ssh-agent and add a key
# Usage: ssha [hours] [gl]
#   hours  number of hours to keep key loaded (default: 1)
#   gl     use $SSHA_GL_KEY (set in local.sh) instead of id_rsa
ssha() {
    local hours=1
    local key="rsa"

    for arg in "$@"; do
        case "$arg" in
            gl|gitlab) key="gitlab" ;;
            ''|*[!0-9]*) echo "ssha: ignoring unrecognized arg '$arg'" >&2 ;;
            *) hours="$arg" ;;
        esac
    done

    local seconds=$(( hours * 3600 ))
    # reuse existing agent if alive, otherwise start a new one
    if ! ssh-add -l &>/dev/null && [[ -z "$SSH_AUTH_SOCK" ]]; then
        eval $(ssh-agent -s)
    fi

    case "$key" in
        gitlab)
            local gl_key="${SSHA_GL_KEY:-$HOME/.ssh/id_gitlab}"
            ssh-add -t "$seconds" "$gl_key"
            ;;
        *)
            ssh-add -t "$seconds" ~/.ssh/id_rsa
            ;;
    esac
}
