# bash-tools

Shell functions for daily dev workflow. Source `load.sh` from `.bashrc` and type `tools` to see what's available.

```bash
# ~/.bashrc
source "$HOME/github/pdmack/bash-tools/load.sh"
```

## Setup

Copy `site.sh.example` to `site.sh` for machine-specific config — CDPATH, key paths, etc. It's gitignored and excluded from `tools` output.

```bash
# site.sh
export CDPATH=".:$HOME/github/pdmack:$HOME/work:$HOME"
```

## Tools

### Claude / Codex / workflow
| Tool | Description |
|------|-------------|
| `cr [name]` | cd to a project and resume its latest Claude session |
| `cxr [name]` | cd to a project and resume its latest Codex session |
| `memback [-n]` | back up Claude and Codex config, memories, sessions, and MCP settings to `$MEMBACK_DEST`; sessions compressed as tar.gz, most recent N per project (`MEMBACK_SESSION_COUNT`, default 3) |
| `memrestore [-n] [-f] [--platform linux\|macos]` | restore Claude and Codex config from `$MEMBACK_DEST`; skips up-to-date projects, prompts for changes, offers `git clone` for missing repos |
| `ssha [hours] [gl]` | start ssh-agent and load a key (`gl` = gitlab key) |
| `mkpr` | create a GitHub issue then open a PR referencing it |

### Git
| Tool | Description |
|------|-------------|
| `grepos [--fetch] [--update]` | scan all git repos in CDPATH, show `owner/repo`, ssh/https, branch/ahead/behind, non-origin remote status; `--update` offers fork sync or `pull --ff-only` per repo; set `BASH_TOOLS_UPSTREAM_REMOTE` in `site.sh` to prefer a remote name (e.g. `nvidia`) |
| `gclean` | delete local branches already merged to main |
| `gdiff [branch]` | diff current branch against another (default: main) |

### System info
| Tool | Description |
|------|-------------|
| `cpu` | hostname, OS, arch, CPU model, cores, RAM |
| `gpu` | NVIDIA GPU summary: memory, util, thermal, processes, modules |
| `fsof <listen\|port\|file\|dir\|pid\|net>` | friendly lsof wrapper |
| `ports [filter]` | show listening ports and processes |
| `fff <dir> [max]` | fat file finder, sorted by size, stops at 10x drop |

### Logs
| Tool | Description |
|------|-------------|
| `jlog <unit> [minutes]` | journalctl with fuzzy unit match and time window |
| `dmsg [minutes] [level]` | dmesg with timestamps, optional time/level filter |

### Files / archives
| Tool | Description |
|------|-------------|
| `extract <file>` | unpack any archive format |
| `peek <file>` | list archive contents without extracting |
| `bak <file>` | timestamped backup (`file.bak.20260414_120000`) |

### History
| Tool | Description |
|------|-------------|
| `hclean [--subs] [--trim] [--dry-run]` | dedup, rewrite, and trim bash history |
| `hist <pattern>` | grep command history |

### Navigation
| Tool | Description |
|------|-------------|
| `cdf <query> [root]` | find and cd to a directory by name (fuzzy, interactive picker); set `BASH_TOOLS_CDF_PRUNE` in `site.sh` to skip large non-project trees (e.g. venvs, SDK installs, Go cache) |
| `cdpath <show\|scan\|add\|rm>` | manage CDPATH entries in `site.sh` |
| `mkcd <dir>` | mkdir + cd in one step |
| `up [n]` | go up n directory levels |
| `typo` | auto-corrects mistyped commands via `command_not_found_handle`; distance 1 runs immediately, distance 2 prompts; set `BASH_TOOLS_TYPO_IGNORE` to skip words (default: `all a`) |

### Data / dev
| Tool | Description |
|------|-------------|
| `json [file]` | pretty-print JSON from file or stdin |
| `jwt <token>` | decode a JWT payload (no verification) |
| `calc <expr>` | quick calculator (`calc 2**20`) |
| `epoch [ts\|date]` | convert between epoch and human-readable |
| `serve [port]` | HTTP server in current dir (default: 8000) |
| `apts <query> [max]` | focused apt search ranked by relevance |
| `ksec <pattern> [-n ns]` | decode a Kubernetes docker registry secret |
| `envg <pattern>` | grep environment variables |
| `path` | pretty-print PATH, one entry per line |

## Portability

Works on Linux and macOS (bash). Tools that are Linux-only (`jlog`, `dmsg`) degrade gracefully or skip on macOS.
