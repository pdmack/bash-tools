# gpu - concise NVIDIA GPU summary with processes, thermal, and module info
# Usage: gpu
gpu() {
    if ! command -v nvidia-smi &>/dev/null; then
        echo "gpu: nvidia-smi not found" >&2
        return 1
    fi

    # Driver and CUDA version
    local driver cuda
    driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | tr -d ' ')
    cuda=$(nvidia-smi 2>/dev/null | grep -o "CUDA Version: [0-9.]*" | awk '{print $3}')

    printf "%-10s %s\n" "driver:"  "$driver"
    printf "%-10s %s\n" "cuda:"    "${cuda:-n/a}"
    echo

    # Per-GPU info
    local count=0
    while IFS=, read -r idx name mem_total mem_used mem_free util_gpu util_mem \
                          temp_gpu temp_mem fan pstate pwr_draw pwr_limit; do
        # trim whitespace
        local v
        for v in idx name mem_total mem_used mem_free util_gpu util_mem \
                  temp_gpu temp_mem fan pstate pwr_draw pwr_limit; do
            printf -v "$v" '%s' "${!v# }"
        done

        printf "  [%s] %s   %s\n" "$idx" "$name" "$pstate"
        printf "      %-10s %s MiB total / %s MiB used / %s MiB free\n" \
            "memory:" "$mem_total" "$mem_used" "$mem_free"
        printf "      %-10s %s%% gpu / %s%% mem\n" "util:" "$util_gpu" "$util_mem"

        # Thermal
        local thermal="${temp_gpu}°C gpu"
        [[ "$temp_mem" != "[N/A]" && -n "$temp_mem" ]] && thermal+="  /  ${temp_mem}°C mem"
        [[ "$fan"      != "[N/A]" && -n "$fan"      ]] && thermal+="  /  fan ${fan}%"
        [[ "$fan"      == "[N/A]"                   ]] && thermal+="  (passive)"
        printf "      %-10s %s\n" "thermal:" "$thermal"
        printf "      %-10s %s W / %s W limit\n" "power:" "$pwr_draw" "$pwr_limit"

        # Processes on this GPU
        local procs
        procs=$(nvidia-smi --query-compute-apps=pid,used_gpu_memory,process_name \
            --format=csv,noheader,nounits 2>/dev/null \
            | awk -F, -v gpu="$idx" '
                NR==FNR { next }
                { pid=$1; mem=$2; name=$3
                  gsub(/ /,"",pid); gsub(/ /,"",mem); gsub(/^ /,"",name)
                  printf "        PID %-8s  %-30s  %s MiB\n", pid, name, mem
                }' /dev/null -)
        # Filter to this GPU's processes via pmon
        local pmon
        pmon=$(nvidia-smi pmon -s m -c 1 2>/dev/null \
            | awk -v gpu="$idx" 'NR>2 && $1==gpu && $3!~/-/ {
                printf "        PID %-8s  %-30s  %s MiB\n", $2, $NF, $4
              }')

        if [[ -n "$pmon" ]]; then
            echo "      processes:"
            echo "$pmon"
        else
            echo "      processes:  none"
        fi

        echo
        (( count++ ))
    done < <(nvidia-smi \
        --query-gpu=index,name,memory.total,memory.used,memory.free,\
utilization.gpu,utilization.memory,temperature.gpu,temperature.memory,\
fan.speed,pstate,power.draw,power.limit \
        --format=csv,noheader,nounits 2>/dev/null)

    printf "%-10s %d\n" "total:" "$count"
    echo

    # Kernel modules
    local modules
    modules=$(lsmod 2>/dev/null | awk 'NR>1 && /nvidia/ {printf "%s ", $1}')
    printf "%-10s %s\n" "modules:" "${modules:-none}"
}
