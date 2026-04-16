# pss - ps scan with compact commands
# Usage: pss [filter]   case-insensitive substring match on user or command
# Strips kernel threads, shortens deep paths to …/basename, collapses -classpath
pss() {
    local query="${1:-}"
    local cols
    cols=$(tput cols 2>/dev/null || echo 120)

    ps auxwww | awk -v q="$query" -v cols="$cols" '
    function shorten(w,    n, parts) {
        if (w ~ /^\/[^\/]+\//) {
            n = split(w, parts, "/")
            return "…/" parts[n]
        }
        return w
    }

    NR == 1 {
        printf "%-10s %6s %5s %5s  %s\n", "USER", "PID", "%CPU", "%MEM", "COMMAND"
        next
    }

    $11 ~ /^\[/ { next }
    /function shorten/ { next }

    {
        user=$1; pid=$2; cpu=$3; mem=$4
        full_cmd = ""
        for (i = 11; i <= NF; i++) full_cmd = full_cmd (i > 11 ? " " : "") $i

        if (q != "" && index(tolower(full_cmd " " user), tolower(q)) == 0) next

        cmd = ""; skip_next = 0
        for (i = 11; i <= NF; i++) {
            if (skip_next) { skip_next = 0; continue }
            word = $i
            if (word == "-classpath" || word == "-cp") {
                cmd = cmd (cmd == "" ? "" : " ") "[cp]"
                skip_next = 1
            } else {
                cmd = cmd (cmd == "" ? "" : " ") shorten(word)
            }
        }

        line = sprintf("%-10s %6s %5s %5s  %s", user, pid, cpu, mem, cmd)
        if (length(line) > cols) line = substr(line, 1, cols - 1) "…"
        print line
    }'
}
