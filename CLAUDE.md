# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Single-file Python CLI tool (`maintenance.py`) that orchestrates system maintenance tasks on macOS. It sequentially offers to update: Homebrew formulae, Homebrew casks (auto-updating only), Rust toolchain + cargo binaries, Volta-managed Node/JS tools, and global pre-commit hooks. Installable globally via `uv tool install .`.

## Installation

```bash
uv venv && uv pip install -e .   # editable dev install
uv tool install .                 # global install
```

## Running

```bash
# Interactive mode — prompts y/N before each section
maintenance

# Auto-pilot mode — runs all sections without prompts
maintenance --all

# Run specific section(s) only
maintenance --section rust
maintenance --section rust,volta

# Log output to file (ANSI-stripped)
maintenance --all --log
maintenance --all --log /tmp/maintenance.log

# Show help / version
maintenance --help
maintenance --version
```

## CLI Flags

| Flag | Description |
|---|---|
| `--all` | Run all sections without y/N prompts |
| `--section <name,...>` | Run only named section(s) without prompts; comma-separated. Names: `brew-formulae`, `brew-casks`, `rust`, `volta`, `pre-commit`. Alias: `brew` = `brew-formulae,brew-casks` |
| `--log [path]` | Tee output to log file (default: `~/maintenance-<timestamp>.log`); ANSI codes stripped in log |
| `--version` | Print version and exit |
| `--help` | Show usage text and exit |

## Key Design Details

- **Python 3.12+, stdlib only**: No runtime dependencies. Uses `subprocess`, `json`, `argparse`, `shutil`, etc.
- **Version**: Read from package metadata via `importlib.metadata.version("maintenance")`.
- **Section functions**: Each section (`do_brew_formulae`, `do_brew_casks`, `do_rust`, `do_volta`, `do_pre_commit`) is a standalone function dispatched through `run_section`.
- **`run_section(id, label, fn)` dispatcher**: Handles confirm gating, section filtering, timing, and status tracking. Returns a `SectionResult` dataclass.
- **`require_cmd(cmd, label)`**: Uses `shutil.which()` to check command existence; prints error and returns `False` if missing.
- **`confirm()` helper**: Gates each section behind a y/N prompt; bypassed in `--auto` mode.
- **Cask filtering**: Uses `brew info --cask --json=v2` parsed with `json.loads()` — no `jq` dependency needed.
- **Volta tools discovery**: Dynamically discovers installed tools via `volta list all --format plain` and reinstalls them — no hardcoded list.
- **Pre-commit**: Operates on `~/.config/pre-commit/global-config.yaml`; self-heals by creating a `.git` dir if missing.
- **TeeWriter**: Custom class wrapping stdout/stderr to also write ANSI-stripped text to a log file.
- **Summary table**: Printed at the end showing each section's status (success/failed/skipped) and elapsed time.
- **Exit code**: Exits `1` if any section failed; `0` otherwise.
