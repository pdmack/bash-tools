# hclean - clean and rewrite bash history
# Usage: hclean [-s|--subs] [-t|--trim] [-n|--dry-run]
#   -s|--subs     apply bash-tools rewrites (cr, ssha, etc.)
#   -t|--trim     remove boring commands listed in histignore.txt
#   -n|--dry-run  show what would change without writing
hclean() {
    local do_subs=false do_trim=false dry_run=false

    for arg in "$@"; do
        case "$arg" in
            -s|--subs)    do_subs=true ;;
            -t|--trim)    do_trim=true ;;
            -n|--dry-run) dry_run=true ;;
            *) echo "Usage: hclean [-s|--subs] [-t|--trim] [-n|--dry-run]" >&2; return 1 ;;
        esac
    done

    local histfile="${HISTFILE:-$HOME/.bash_history}"
    local tools_dir
    tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local ignorefile="$tools_dir/histignore.txt"

    if [[ ! -f "$histfile" ]]; then
        echo "hclean: history file not found: $histfile" >&2
        return 1
    fi

    local backup="${histfile}.bak.$(date +%Y%m%d_%H%M%S)"
    cp "$histfile" "$backup"
    echo "backup: $backup"

    python3 - "$histfile" "$do_subs" "$do_trim" "$dry_run" "$ignorefile" <<'EOF'
import re, sys, os

histfile, do_subs, do_trim, dry_run, ignorefile = \
    sys.argv[1], sys.argv[2]=="true", sys.argv[3]=="true", sys.argv[4]=="true", sys.argv[5]

with open(histfile) as f:
    lines = [l.rstrip('\n') for l in f]

original_count = len(lines)

# Substitutions
if do_subs:
    subs = [
        (r"eval \$\(ssh-agent -s\) && ssh-add -t \d+ ~/\.ssh/id_rsa$",          "ssha"),
        (r"eval \$\(ssh-agent -s\) && ssh-add -t \d+ ~/.ssh/id_rsa$",            "ssha"),
        (r"eval \$\(ssh-agent -s\) && ssh-add -t \d+ ~/\.ssh/id_gitlab$", "ssha gl"),
        (r"eval \$\(ssh-agent -s\) && ssh-add -t \d+ ~/.ssh/id_gitlab$",  "ssha gl"),
        (r"claude --resume [a-f0-9-]+\s+#\s*(\S+).*$", lambda m: f"cr {m.group(1)}"),
        (r"^\s*claude --resume [a-f0-9-]+\s*$",        "cr"),
    ]
    rewritten = []
    for line in lines:
        for pattern, replacement in subs:
            line = re.sub(pattern, replacement if not callable(replacement) else replacement, line) \
                if not callable(replacement) else re.sub(pattern, replacement, line)
        rewritten.append(line)
    lines = rewritten

# Trim boring commands
if do_trim and os.path.exists(ignorefile):
    with open(ignorefile) as f:
        boring = {l.strip() for l in f if l.strip() and not l.startswith('#')}
    lines = [l for l in lines if l.strip() not in boring]

# Remove blank lines
lines = [l for l in lines if l.strip()]

# Dedup — keep last occurrence, preserve order
seen = {}
for i, line in enumerate(lines):
    seen[line] = i
deduped = [line for i, line in enumerate(lines) if seen[line] == i]

removed = original_count - len(deduped)
print(f"lines:   {original_count} → {len(deduped)}  ({removed} removed)")

if dry_run:
    print("(dry run — no changes written)")
else:
    with open(histfile, 'w') as f:
        f.write('\n'.join(deduped) + '\n')
    print("done.")
EOF
}
