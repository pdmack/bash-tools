# typo - intercept unknown commands and suggest the closest match
#
# Hooks into command_not_found_handle. Matches only the command name against
# $PATH executables using Damerau-Levenshtein distance (handles transpositions):
#   distance 1 → runs immediately (echoes the correction)
#   distance 2 → prompts before running
#   distance > 2, or no match → gives up with normal "command not found"
#
# Disable: unset -f command_not_found_handle

command_not_found_handle() {
    local cmd="$1"
    shift
    local args=("$@")

    local result
    result=$(python3 - "$cmd" <<'EOF'
import sys, os

def dl_distance(s, t):
    # Damerau-Levenshtein: transpositions count as 1
    m, n = len(s), len(t)
    d = [[0]*(n+1) for _ in range(m+1)]
    for i in range(m+1): d[i][0] = i
    for j in range(n+1): d[0][j] = j
    for i in range(1, m+1):
        for j in range(1, n+1):
            cost = 0 if s[i-1] == t[j-1] else 1
            d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1]+cost)
            if i > 1 and j > 1 and s[i-1] == t[j-2] and s[i-2] == t[j-1]:
                d[i][j] = min(d[i][j], d[i-2][j-2]+cost)
    return d[m][n]

cmd = sys.argv[1]
dirs = os.environ.get('PATH', '').split(':')
commands = set()
for d in dirs:
    try:
        commands.update(
            f for f in os.listdir(d)
            if os.access(os.path.join(d, f), os.X_OK)
        )
    except OSError:
        pass

def sort_key(c, dist):
    is_anagram = sorted(c) == sorted(cmd)
    common_prefix = len(os.path.commonprefix([cmd, c]))
    return (dist, not is_anagram, -common_prefix, c)

best, best_dist, best_key = None, 3, None
for c in commands:
    dist = dl_distance(cmd, c)
    if dist > 2:
        continue
    key = sort_key(c, dist)
    if best_key is None or key < best_key:
        best, best_dist, best_key = c, dist, key

if best is None or best_dist > 2:
    print('')
else:
    print(f'{"auto" if best_dist == 1 else "ask"} {best}')
EOF
    )

    local confidence="${result%% *}"
    local suggestion="${result#* }"

    if [[ -z "$result" || -z "$suggestion" ]]; then
        echo "bash: $cmd: command not found" >&2
        return 127
    fi

    if [[ "$confidence" == "auto" ]]; then
        echo "typo: running '${suggestion}${args:+ ${args[*]}}'" >&2
    else
        printf "typo: did you mean '%s'? [Y/n] " "${suggestion}${args:+ ${args[*]}}" >&2
        local ans
        read -r ans
        [[ "${ans:-y}" =~ ^[Yy]$ ]] || { echo "bash: $cmd: command not found" >&2; return 127; }
    fi

    "$suggestion" "${args[@]}"
}
