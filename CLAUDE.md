# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of bash shell functions sourced into an interactive shell via `load.sh`. There is no build step and no test suite — all code is loaded at shell startup and exercised manually.

## Development workflow

To load changes into an active shell:
```bash
source load.sh
```

To check what functions are available:
```bash
cat tools.sh
```

To add a new tool:
1. Create `<name>.sh` exporting a single function named `<name>`
2. Add a `source` line in `load.sh` (alphabetical order within its section)
3. Add the function name + description to `tools.sh`

There is no linter configured. Tools are tested interactively.

## Architecture

**Entry point:** `load.sh` sources every tool script, then `site.sh` (machine-local config, gitignored), then runs conflict detection.

**Machine config:** `site.sh` (copy from `site.sh.example`) sets environment variables consumed by multiple tools:
- `CDPATH` — search paths for `cd <name>`, used by `cr`, `grepos`, `gclean`, `gdiff`, `cdf`
- `BASH_TOOLS_UPSTREAM_REMOTE` — preferred non-origin remote (e.g. `nvidia`)
- `BASH_TOOLS_TYPO_IGNORE` — space-separated words typo.sh must never correct
- `BASH_TOOLS_IGNORE_CONFLICTS` — suppress load-time conflict warnings for named commands
- `SSHA_GL_KEY` — path to GitLab SSH key for ssha
- `MEMBACK_DEST` — root of backup git repo for memback/memrestore
- `APTS_UPDATE_TTL` — cache TTL for apt lists in apts (default 3600s)

**Shared utility:** `_bash_tools_cdpath_repos()` is defined in `cdpath.sh` and walks CDPATH to find git repos. It is used by `gclean`, `gdiff`, and `grepos` — do not duplicate it.

**Conflict detection:** At load time, `load.sh` warns if any function name shadows a `$PATH` command or alias. `git` is pre-ignored because `grebase.sh` intentionally wraps it.

## Conventions

- Internal/helper functions use a `_` prefix (`_bash_tools_*` for shared helpers, `_<script>_*` for script-local helpers). The prefix hides them from conflict detection.
- macOS/Linux portability: use `uname` checks where behavior differs (e.g. `sed -i` syntax, `lsof` vs `ss`, `sysctl` vs `/proc`).
- Interactive prompts use `read -r`. Functions that scan multiple repos always confirm destructive actions (e.g. branch deletion, force-pushes).
- `grebase.sh` wraps the `git` command itself to intercept `git merge origin/<trunk>` calls and redirect them through rebase. Any git command not matching the interception is passed through unchanged.
- `typo.sh` hooks `command_not_found_handle`. Only one handler can be active; the script warns if another handler is already set.
