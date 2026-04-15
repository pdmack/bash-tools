# cpu - concise host hardware and OS summary
# Usage: cpu
cpu() {
    local os kernel arch cpu_model physical logical ram_total ram_avail

    arch=$(uname -m)
    kernel=$(uname -r)

    if [[ "$(uname)" == "Darwin" ]]; then
        os=$(sw_vers -productName)" "$(sw_vers -productVersion)
        cpu_model=$(sysctl -n machdep.cpu.brand_string)
        physical=$(sysctl -n hw.physicalcpu)
        logical=$(sysctl -n hw.logicalcpu)
        local bytes
        bytes=$(sysctl -n hw.memsize)
        ram_total=$(awk "BEGIN { printf \"%.0fG\", $bytes/1073741824 }")
        ram_avail="n/a"
    else
        os=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
        cpu_model=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed 's/^ //')
        physical=$(grep "^cpu cores" /proc/cpuinfo | head -1 | awk '{print $NF}')
        logical=$(nproc)
        ram_total=$(free -h | awk '/^Mem:/ {print $2}')
        ram_avail=$(free -h | awk '/^Mem:/ {print $7}')
    fi

    printf "%-10s %s\n" "hostname:" "$(hostname)"
    printf "%-10s %s\n" "os:"       "$os"
    printf "%-10s %s\n" "kernel:"   "$kernel"
    printf "%-10s %s\n" "arch:"     "$arch"
    printf "%-10s %s\n" "cpu:"      "$cpu_model"
    printf "%-10s %s physical / %s logical\n" "cores:" "$physical" "$logical"
    printf "%-10s %s total / %s available\n"  "ram:"   "$ram_total" "$ram_avail"
}
