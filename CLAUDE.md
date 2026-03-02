# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Single-file zsh script (`maintenance.sh`) that orchestrates system maintenance tasks on macOS. It sequentially offers to update: Homebrew formulae, Homebrew casks (auto-updating only), Rust toolchain + cargo binaries, Volta-managed Node/JS tools, and global pre-commit hooks.

## Running

```bash
# Interactive mode — prompts y/N before each section
./maintenance.sh

# Auto-pilot mode — runs all sections without prompts
./maintenance.sh --auto

# Preview what would run
./maintenance.sh --auto --dry-run

# Run specific section(s) only
./maintenance.sh --section rust
./maintenance.sh --section rust --section volta

# Log output to file (ANSI-stripped)
./maintenance.sh --auto --log
./maintenance.sh --auto --log /tmp/maintenance.log

# Show help / version
./maintenance.sh --help
./maintenance.sh --version
```

## CLI Flags

| Flag | Description |
|---|---|
| `--auto` | Run all sections without y/N prompts |
| `--dry-run` | Show what would run without executing |
| `--section <name>` | Run only named section(s); repeatable. Names: `brew-formulae`, `brew-casks`, `rust`, `volta`, `pre-commit` |
| `--log [path]` | Tee output to log file (default: `~/maintenance-<timestamp>.log`); ANSI codes stripped in log |
| `--version` | Print version and exit |
| `--help` | Show usage text and exit |

## Key Design Details

- **Shell**: zsh (not bash) — uses zsh-specific features like `local -a`, `(f)` flag, `${+commands[...]}` for command checks, and associative arrays.
- **Section functions**: Each section (`do_brew_formulae`, `do_brew_casks`, `do_rust`, `do_volta`, `do_pre_commit`) is a standalone function dispatched through `run_section`.
- **`run_section(id, label, fn)` dispatcher**: Handles confirm gating, section filtering, dry-run, timing, and status tracking.
- **`require_cmd(cmd, label)`**: Checks command existence before running a section; prints a clear error and skips if missing.
- **`confirm()` helper**: Gates each section behind a y/N prompt; bypassed in `--auto` mode.
- **Cask filtering**: Uses `brew info --cask --json=v2` piped through `jq` to find only casks with `auto_updates == true`. Guards against empty cask list.
- **Volta tools list**: Hardcoded list of tools to reinstall/update — this is the canonical list of desired global JS tooling.
- **Pre-commit**: Operates on `~/.config/pre-commit/global-config.yaml`; self-heals by creating a dummy `.git` dir if missing.
- **Summary table**: Printed at the end showing each section's status (success/failed/skipped/dry-run) and elapsed time.
- **Exit code**: Exits `1` if any section failed; `0` otherwise.
