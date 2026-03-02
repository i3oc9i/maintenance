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

# Run all sections without prompts
maintenance --all

# Run specific section(s) only
maintenance --section rust
maintenance --section rust,volta

# Log output to file (ANSI codes stripped in log)
maintenance --all --log
maintenance --all --log /tmp/maintenance.log
```

## Sections

| Section | What it does |
|---|---|
| `brew` | Alias for `brew-formulae,brew-casks` |
| `brew-formulae` | `brew update && brew upgrade && brew cleanup` |
| `brew-casks` | Upgrades only casks with `auto_updates: true` |
| `rust` | `rustup update` + `cargo install-update -a` |
| `volta` | Reinstalls all currently installed global JS tools |
| `pre-commit` | `pre-commit autoupdate` on global config |

## License

[MIT](LICENSE)
