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

### Claude / workflow
| Tool | Description |
|------|-------------|
| `cr [name]` | cd to a project and resume its latest Claude session |
| `memback [-n]` | back up Claude memories, global config, and MCP settings to `$MEMBACK_DEST` |
| `memrestore [-n] [-f] [--platform linux\|macos]` | restore Claude config from `$MEMBACK_DEST`; prompts per project, offers `git clone` for missing repos |
| `ssha [hours] [gl]` | start ssh-agent and load a key (`gl` = gitlab key) |
| `mkpr` | create a GitHub issue then open a PR referencing it |

### Git
| Tool | Description |
|------|-------------|
| `grepos [--fetch] [--sync]` | scan all git repos in CDPATH, show branch/ahead/behind |
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
| `cdpath <show\|scan\|add\|rm>` | manage CDPATH entries in `site.sh` |
| `mkcd <dir>` | mkdir + cd in one step |
| `up [n]` | go up n directory levels |

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
