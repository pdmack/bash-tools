# bash-tools loader - source this from ~/.bashrc
#
# Conflict detection
#   At load time, bash-tools warns if any of its functions would shadow a
#   $PATH command or be shadowed by an existing alias. To suppress warnings
#   for known-intentional overrides, set in site.sh before sourcing load.sh:
#
#     BASH_TOOLS_IGNORE_CONFLICTS="git json"   # space-separated names
#
#   "git" is pre-ignored — grebase.sh intentionally wraps it to intercept
#   merge commands. Add other names only if you've reviewed the override.
#   To silence all conflict warnings: BASH_TOOLS_IGNORE_CONFLICTS="*"

BASH_TOOLS_IGNORE_CONFLICTS="${BASH_TOOLS_IGNORE_CONFLICTS-git}"

_bash_tools_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_bash_tools_pre_fns=$(declare -F | awk '{print $3}')

source "$_bash_tools_dir/cr.sh"
source "$_bash_tools_dir/ssha.sh"
source "$_bash_tools_dir/extract.sh"
source "$_bash_tools_dir/peek.sh"
source "$_bash_tools_dir/mkcd.sh"
source "$_bash_tools_dir/up.sh"
source "$_bash_tools_dir/gclean.sh"
source "$_bash_tools_dir/grebase.sh"
source "$_bash_tools_dir/bak.sh"
source "$_bash_tools_dir/serve.sh"
source "$_bash_tools_dir/ports.sh"
source "$_bash_tools_dir/hist.sh"
source "$_bash_tools_dir/json.sh"
source "$_bash_tools_dir/jwt.sh"
source "$_bash_tools_dir/gdiff.sh"
source "$_bash_tools_dir/path.sh"
source "$_bash_tools_dir/envg.sh"
source "$_bash_tools_dir/calc.sh"
source "$_bash_tools_dir/epoch.sh"
source "$_bash_tools_dir/mkpr.sh"
source "$_bash_tools_dir/fff.sh"
source "$_bash_tools_dir/jlog.sh"
source "$_bash_tools_dir/dmsg.sh"
source "$_bash_tools_dir/cpu.sh"
source "$_bash_tools_dir/gpu.sh"
source "$_bash_tools_dir/fsof.sh"
source "$_bash_tools_dir/cdpath.sh"
source "$_bash_tools_dir/apts.sh"
source "$_bash_tools_dir/pss.sh"
source "$_bash_tools_dir/maas.sh"
source "$_bash_tools_dir/cdf.sh"
source "$_bash_tools_dir/psk.sh"
source "$_bash_tools_dir/memback.sh"
source "$_bash_tools_dir/memrestore.sh"
source "$_bash_tools_dir/grepos.sh"
source "$_bash_tools_dir/hclean.sh"
source "$_bash_tools_dir/ksec.sh"
source "$_bash_tools_dir/tools.sh"

# machine-specific overrides (gitignored)
[[ -f "$_bash_tools_dir/site.sh" ]] && source "$_bash_tools_dir/site.sh"

# Warn about naming conflicts with $PATH commands or existing aliases
_bash_tools_check_conflicts() {
    [[ "$BASH_TOOLS_IGNORE_CONFLICTS" == "*" ]] && return
    local fn
    while IFS= read -r fn; do
        [[ "$fn" == _* ]] && continue
        grep -qxF "$fn" <<< "$_bash_tools_pre_fns" && continue
        # shellcheck disable=SC2076
        [[ " $BASH_TOOLS_IGNORE_CONFLICTS " == *" $fn "* ]] && continue
        if type -P "$fn" &>/dev/null; then
            echo "bash-tools: warning: $fn() shadows $(type -P "$fn")" >&2
        fi
        if alias "$fn" &>/dev/null 2>&1; then
            echo "bash-tools: warning: $fn() is shadowed by alias: $(alias "$fn" 2>/dev/null)" >&2
        fi
    done < <(declare -F | awk '{print $3}')
}
_bash_tools_check_conflicts
unset -f _bash_tools_check_conflicts
unset _bash_tools_pre_fns _bash_tools_dir
