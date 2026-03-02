# maintenance

macOS system maintenance orchestrator. Sequentially updates Homebrew formulae, Homebrew casks (auto-updating only), Rust toolchain + cargo binaries, Volta-managed Node/JS tools, and global pre-commit hooks.

## Installation

```bash
uv tool install .
```

## Usage

```bash
# Interactive mode — prompts y/N before each section
maintenance

# Auto-pilot — runs all sections without prompts
maintenance --auto

# Preview what would run
maintenance --auto --dry-run

# Run specific section(s) only
maintenance --section rust
maintenance --section rust --section volta

# Log output to file (ANSI codes stripped in log)
maintenance --auto --log
maintenance --auto --log /tmp/maintenance.log
```

## Sections

| Section | What it does |
|---|---|
| `brew-formulae` | `brew update && brew upgrade && brew cleanup` |
| `brew-casks` | Upgrades only casks with `auto_updates: true` |
| `rust` | `rustup update` + `cargo install-update -a` |
| `volta` | Reinstalls global JS tools (node, yarn, pnpm, bun, deno, etc.) |
| `pre-commit` | `pre-commit autoupdate` on global config |

## License

[MIT](LICENSE)
