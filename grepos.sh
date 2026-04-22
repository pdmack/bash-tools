# grepos - scan git repos from CDPATH and show main branch status
# Usage: grepos [-f|--fetch] [-u|--update]
#   -f|--fetch   run git fetch --all on each repo before checking status
#   -u|--update  offer to update repos that are behind; behavior is per-repo:
#                  upstream remote present + behind upstream →
#                    full fork sync: merge upstream/main locally, push to origin
#                  no upstream remote (or upstream current) + behind origin, clean →
#                    git pull --ff-only from origin
#                Repos with local commits (ahead > 0) or a dirty tree are skipped
#                regardless — those need manual attention.
grepos() {
    local do_fetch=false do_update=false

    for arg in "$@"; do
        case "$arg" in
            -f|--fetch)  do_fetch=true ;;
            -u|--update) do_update=true ;;
            *) echo "Usage: grepos [-f|--fetch] [-u|--update]" >&2; return 1 ;;
        esac
    done

    # Warn if network ops requested but no SSH key loaded
    if $do_fetch || $do_update; then
        if ! ssh-add -l &>/dev/null; then
            echo "grepos: no SSH key loaded — run: ssha 4" >&2
            return 1
        fi
    fi

    local repos=()
    mapfile -t repos < <(_bash_tools_cdpath_repos)

    if (( ${#repos[@]} == 0 )); then
        echo "grepos: no git repos found in CDPATH"
        return 0
    fi

    local to_sync=() to_sync_remotes=() to_ff=()

    for repo in "${repos[@]}"; do
        local name remote_url owner label proto
        name=$(basename "$repo")
        remote_url=$(git -C "$repo" remote get-url origin 2>/dev/null)
        owner=$(sed -n 's|.*[:/]\([^/]*\)/[^/]*\.git$|\1|p' <<< "$remote_url")
        [[ -z "$owner" ]] && owner=$(sed -n 's|.*[:/]\([^/]*\)/[^/]*$|\1|p' <<< "$remote_url")
        [[ -n "$owner" ]] && label="$owner/$name" || label="$name"
        case "$remote_url" in
            git@*|ssh://*) proto="ssh"   ;;
            https://*)     proto="https" ;;
            http://*)      proto="http"  ;;
            "")            proto="local" ;;
            *)             proto="git"   ;;
        esac

        # Fetch if requested
        if $do_fetch; then
            git -C "$repo" fetch --all -q 2>/dev/null
        fi

        # Current branch
        local branch
        branch=$(git -C "$repo" symbolic-ref --short HEAD 2>/dev/null || echo "detached")

        # Determine main branch name
        local main_branch
        main_branch=$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
            | sed 's|.*/||')
        [[ -z "$main_branch" ]] && main_branch="main"

        # Dirty check
        local dirty=""
        [[ -n "$(git -C "$repo" status --porcelain 2>/dev/null)" ]] && dirty=" *"

        # Ahead/behind origin
        local ahead behind status_str
        ahead=$(git -C "$repo" rev-list --count "@{u}..HEAD" 2>/dev/null)
        behind=$(git -C "$repo" rev-list --count "HEAD..@{u}" 2>/dev/null)

        if [[ -z "$ahead" && -z "$behind" ]]; then
            status_str="no tracking"
        elif [[ "$ahead" == "0" && "$behind" == "0" ]]; then
            status_str="up to date"
        else
            status_str=""
            (( ahead  > 0 )) && status_str+="↑${ahead} ahead "
            (( behind > 0 )) && status_str+="↓${behind} behind"
        fi

        # Non-origin remote check (fork parent — nvidia, mafueee, upstream, etc.)
        # Prefer 'nvidia' if multiple non-origin remotes exist.
        local upstream_str="" has_upstream=false u_behind=0 upstream_remote=""
        local non_origin_remotes=()
        mapfile -t non_origin_remotes < <(git -C "$repo" remote | grep -v "^origin$")
        if (( ${#non_origin_remotes[@]} > 0 )); then
            # Pick preferred remote (BASH_TOOLS_UPSTREAM_REMOTE from site.sh) first,
            # else fall back to first in list
            upstream_remote="${non_origin_remotes[0]}"
            local preferred="${BASH_TOOLS_UPSTREAM_REMOTE:-}"
            if [[ -n "$preferred" ]]; then
                for r in "${non_origin_remotes[@]}"; do
                    [[ "$r" == "$preferred" ]] && upstream_remote="$preferred" && break
                done
            fi
            has_upstream=true
            local u_ahead
            u_ahead=$(git -C "$repo" rev-list --count "${upstream_remote}/${main_branch}..HEAD" 2>/dev/null)
            u_behind=$(git -C "$repo" rev-list --count "HEAD..${upstream_remote}/${main_branch}" 2>/dev/null)
            u_behind=${u_behind:-0}
            if [[ "$u_behind" != "0" ]]; then
                upstream_str="  [${upstream_remote} ↓${u_behind}]"
                $do_update && { to_sync+=("$repo"); to_sync_remotes+=("$upstream_remote"); }
            elif [[ -n "$u_ahead" || -n "$u_behind" ]]; then
                upstream_str="  [${upstream_remote} ✓]"
            fi
        fi

        # FF candidate: behind origin, no local commits, not dirty, not detached,
        # and not already queued for a fork sync
        if $do_update && [[ "$branch" != "detached" && -z "$dirty" ]] \
                && [[ -n "$behind" && "$behind" != "0" ]] \
                && [[ "$ahead" == "0" ]] \
                && ! ( $has_upstream && [[ "$u_behind" != "0" ]] ); then
            to_ff+=("$repo")
        fi

        printf "  %-35s %-5s [%s]%s  %s%s\n" \
            "$label" "$proto" "$branch" "$dirty" "$status_str" "$upstream_str"
    done

    # Offer fork sync (non-origin remote present, behind it)
    if $do_update && (( ${#to_sync[@]} > 0 )); then
        echo
        echo "Fork repos behind remote — will merge remote/main and push to origin:"
        for i in "${!to_sync[@]}"; do
            local _repo="${to_sync[$i]}" _remote="${to_sync_remotes[$i]}"
            local _url _owner _name _lbl _ub _mb
            _name=$(basename "$_repo")
            _url=$(git -C "$_repo" remote get-url origin 2>/dev/null)
            _owner=$(sed -n 's|.*[:/]\([^/]*\)/[^/]*\.git$|\1|p' <<< "$_url")
            [[ -z "$_owner" ]] && _owner=$(sed -n 's|.*[:/]\([^/]*\)/[^/]*$|\1|p' <<< "$_url")
            [[ -n "$_owner" ]] && _lbl="$_owner/$_name" || _lbl="$_name"
            _mb=$(git -C "$_repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|.*/||')
            [[ -z "$_mb" ]] && _mb="main"
            _ub=$(git -C "$_repo" rev-list --count "HEAD..${_remote}/${_mb}" 2>/dev/null)
            echo "  $_lbl  (${_remote} ↓${_ub})"
        done
        echo
        read -r -p "Sync these forks? [y/N] " confirm
        [[ "${confirm,,}" != "y" ]] && { (( ${#to_ff[@]} == 0 )) && return 0 || true; }

        if [[ "${confirm,,}" == "y" ]]; then
            for i in "${!to_sync[@]}"; do
                local repo="${to_sync[$i]}" sync_remote="${to_sync_remotes[$i]}"
                local main_branch s_url s_owner s_name
                main_branch=$(git -C "$repo" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
                    | sed 's|.*/||')
                [[ -z "$main_branch" ]] && main_branch="main"
                s_name=$(basename "$repo")
                s_url=$(git -C "$repo" remote get-url origin 2>/dev/null)
                s_owner=$(sed -n 's|.*[:/]\([^/]*\)/[^/]*\.git$|\1|p' <<< "$s_url")
                [[ -z "$s_owner" ]] && s_owner=$(sed -n 's|.*[:/]\([^/]*\)/[^/]*$|\1|p' <<< "$s_url")
                echo "→ syncing ${s_owner:+$s_owner/}$s_name from ${sync_remote}..."
                git -C "$repo" checkout "$main_branch" -q \
                    && git -C "$repo" merge "${sync_remote}/${main_branch}" --ff-only \
                    && git -C "$repo" push origin "$main_branch" \
                    || echo "  failed — may need manual merge"
            done
        fi
    fi

    # Offer fast-forward (no upstream remote, clean, behind origin)
    if $do_update && (( ${#to_ff[@]} > 0 )); then
        echo
        echo "Repos that can be fast-forwarded from origin:"
        for repo in "${to_ff[@]}"; do
            local f_url f_owner f_name f_behind
            f_name=$(basename "$repo")
            f_url=$(git -C "$repo" remote get-url origin 2>/dev/null)
            f_owner=$(sed -n 's|.*[:/]\([^/]*\)/[^/]*\.git$|\1|p' <<< "$f_url")
            [[ -z "$f_owner" ]] && f_owner=$(sed -n 's|.*[:/]\([^/]*\)/[^/]*$|\1|p' <<< "$f_url")
            f_behind=$(git -C "$repo" rev-list --count "HEAD..@{u}" 2>/dev/null)
            echo "  ${f_owner:+$f_owner/}$f_name  (↓${f_behind})"
        done
        echo
        read -r -p "Fast-forward these? [y/N] " confirm
        [[ "${confirm,,}" != "y" ]] && return 0

        for repo in "${to_ff[@]}"; do
            local f_url f_owner f_name
            f_name=$(basename "$repo")
            f_url=$(git -C "$repo" remote get-url origin 2>/dev/null)
            f_owner=$(sed -n 's|.*[:/]\([^/]*\)/[^/]*\.git$|\1|p' <<< "$f_url")
            [[ -z "$f_owner" ]] && f_owner=$(sed -n 's|.*[:/]\([^/]*\)/[^/]*$|\1|p' <<< "$f_url")
            echo "→ ff ${f_owner:+$f_owner/}$f_name..."
            git -C "$repo" pull --ff-only -q \
                && echo "  done" \
                || echo "  failed"
        done
    fi
}
