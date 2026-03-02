#!/bin/zsh

# maintenance.sh — macOS system maintenance orchestrator
VERSION="1.0.0"

# ------------------------------------------------------------------- Defaults
AUTO_MODE=false
DRY_RUN=false
LOG_FILE=""
typeset -a ONLY_SECTIONS
ONLY_SECTIONS=()

# ------------------------------------------------------------------- Argument Parsing
usage() {
    cat <<'EOF'
Usage: maintenance.sh [OPTIONS]

Orchestrates system maintenance tasks on macOS.

Options:
  --auto              Run all sections without prompts
  --dry-run           Show what would run without executing
  --section <name>    Run only named section(s), repeatable
                      Names: brew-formulae, brew-casks, rust, volta, pre-commit
  --log [path]        Tee output to log file (default: ~/maintenance-<timestamp>.log)
  --version           Print version and exit
  --help              Show this help and exit

Examples:
  maintenance.sh                          Interactive mode
  maintenance.sh --auto                   Run everything
  maintenance.sh --auto --dry-run         Preview all sections
  maintenance.sh --section rust           Run only Rust updates
  maintenance.sh --section rust --section volta
  maintenance.sh --auto --log             Auto-run with default log
  maintenance.sh --auto --log /tmp/m.log  Auto-run with custom log
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --auto)    AUTO_MODE=true; shift ;;
        --dry-run) DRY_RUN=true; shift ;;
        --section)
            if [[ -z "$2" || "$2" == --* ]]; then
                echo "Error: --section requires a name" >&2; exit 1
            fi
            ONLY_SECTIONS+=("$2"); shift 2 ;;
        --log)
            if [[ -n "$2" && "$2" != --* ]]; then
                LOG_FILE="$2"; shift 2
            else
                LOG_FILE="$HOME/maintenance-$(date +%Y%m%d-%H%M%S).log"; shift
            fi ;;
        --version) echo "maintenance.sh v$VERSION"; exit 0 ;;
        --help)    usage; exit 0 ;;
        *)         echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

# ------------------------------------------------------------------- Colors
BOLD_BLUE="\033[1;34m"
BOLD_GREEN="\033[1;32m"
BOLD_YELLOW="\033[1;33m"
BOLD_RED="\033[1;31m"
DIM="\033[2m"
RESET="\033[0m"

# ------------------------------------------------------------------- State
typeset -A SECTION_STATUS SECTION_TIMES SECTION_LABELS
SECTION_ORDER=(brew-formulae brew-casks rust volta pre-commit)
SECTION_LABELS[brew-formulae]="Homebrew Formulae"
SECTION_LABELS[brew-casks]="Homebrew Casks"
SECTION_LABELS[rust]="Rust"
SECTION_LABELS[volta]="Volta"
SECTION_LABELS[pre-commit]="Pre-commit"
ANY_FAILED=false

# ------------------------------------------------------------------- Helpers
format_duration() {
    local secs=$1
    if (( secs < 60 )); then
        printf "%ds" "$secs"
    else
        printf "%dm%ds" "$((secs / 60))" "$((secs % 60))"
    fi
}

confirm() {
    if [[ "$AUTO_MODE" == true ]]; then
        return 0
    fi
    echo -n "${BOLD_YELLOW}==> Run $1? (y/N): ${RESET}"
    read -r response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        return 0
    fi
    return 1
}

require_cmd() {
    local cmd=$1 label=$2
    if (( ! ${+commands[$cmd]} )); then
        echo "${BOLD_RED}  ✗ '$cmd' not found — skipping $label${RESET}"
        return 1
    fi
    return 0
}

run_section() {
    local id=$1 label=$2 fn=$3

    # Section filter
    if (( ${#ONLY_SECTIONS[@]} > 0 )); then
        if [[ ${ONLY_SECTIONS[(Ie)$id]} -eq 0 ]]; then
            SECTION_STATUS[$id]="skipped"
            SECTION_TIMES[$id]=0
            return
        fi
    fi

    # Confirm
    if ! confirm "$label"; then
        SECTION_STATUS[$id]="skipped"
        SECTION_TIMES[$id]=0
        return
    fi

    # Dry-run
    if [[ "$DRY_RUN" == true ]]; then
        echo "\n${DIM}[dry-run] Would run: $label${RESET}"
        SECTION_STATUS[$id]="dry-run"
        SECTION_TIMES[$id]=0
        return
    fi

    echo "\n${BOLD_GREEN}Updating $label...${RESET}"
    local start=$SECONDS
    if $fn; then
        SECTION_STATUS[$id]="success"
    else
        SECTION_STATUS[$id]="failed"
        ANY_FAILED=true
    fi
    SECTION_TIMES[$id]=$(( SECONDS - start ))
}

# ------------------------------------------------------------------- Logging
if [[ -n "$LOG_FILE" ]]; then
    exec > >(tee >(sed 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE")) 2>&1
    echo "${DIM}Logging to $LOG_FILE${RESET}"
fi

# ------------------------------------------------------------------- Header
if [[ "$AUTO_MODE" == true ]]; then
    echo "${BOLD_BLUE}--- SYSTEM MAINTENANCE (AUTO-PILOT MODE) ---${RESET}"
else
    echo "${BOLD_BLUE}--- SYSTEM MAINTENANCE ORCHESTRATOR ---${RESET}"
fi
if [[ "$DRY_RUN" == true ]]; then
    echo "${DIM}(dry-run mode — no changes will be made)${RESET}"
fi

# ------------------------------------------------------------------- Section Functions
do_brew_formulae() {
    require_cmd brew "Homebrew Formulae" || return 1
    brew update && brew upgrade && brew cleanup
}

do_brew_casks() {
    require_cmd brew "Homebrew Casks" || return 1
    require_cmd jq "Homebrew Casks" || return 1

    local -a installed_casks
    installed_casks=($(brew ls --cask 2>/dev/null))

    if (( ${#installed_casks[@]} == 0 )); then
        echo "  No casks installed."
        return 0
    fi

    local -a casks
    casks=(${(f)"$(brew info --cask --json=v2 "${installed_casks[@]}" | jq -r '.casks[] | select(.auto_updates == true) | .token')"})

    if (( ${#casks[@]} > 0 )); then
        echo "  Updating ${#casks[@]} auto-updating casks..."
        brew upgrade --cask "${casks[@]}"
    else
        echo "  No auto-updating casks found."
    fi
}

do_rust() {
    require_cmd rustup "Rust" || return 1
    rustup update

    if (( ${+commands[cargo-install-update]} )); then
        cargo install-update -a
    else
        echo "  cargo-update not found — skipping binary updates."
    fi
}

do_volta() {
    require_cmd volta "Volta" || return 1
    volta install node yarn pnpm bun deno vite vitest sv serve \
        typescript-language-server typescript skills repomix \
        get-shit-done-cc ccstatusline
}

do_pre_commit() {
    require_cmd pre-commit "Pre-commit" || return 1

    local pc_dir="$HOME/.config/pre-commit"
    local pc_config="global-config.yaml"

    if [[ -d "$pc_dir" && -f "$pc_dir/$pc_config" ]]; then
        (
            cd "$pc_dir"
            [[ ! -d ".git" ]] && git init -q
            pre-commit autoupdate --config "$pc_config"
        )
    else
        echo "  Global config not found at $pc_dir/$pc_config"
        return 1
    fi
}

# ------------------------------------------------------------------- Dispatch
run_section brew-formulae "Homebrew Formulae"  do_brew_formulae
run_section brew-casks    "Homebrew Casks"      do_brew_casks
run_section rust          "Rust"                do_rust
run_section volta         "Volta"               do_volta
run_section pre-commit    "Pre-commit"          do_pre_commit

# ------------------------------------------------------------------- Summary
echo "\n${BOLD_BLUE}--- Summary ---${RESET}"
printf "  %-22s %-10s %s\n" "Section" "Status" "Time"
printf "  %-22s %-10s %s\n" "───────────────────" "────────" "─────"
for id in $SECTION_ORDER; do
    sect_status=${SECTION_STATUS[$id]:-skipped}
    elapsed=${SECTION_TIMES[$id]:-0}
    color=""
    case $sect_status in
        success) color=$BOLD_GREEN ;;
        failed)  color=$BOLD_RED ;;
        dry-run) color=$DIM ;;
        *)       color=$DIM ;;
    esac
    printf "  %-22s ${color}%-10s${RESET} %s\n" "${SECTION_LABELS[$id]}" "$sect_status" "$(format_duration $elapsed)"
done

echo "\n${BOLD_BLUE}--- Maintenance Complete! ---${RESET}"

if [[ "$ANY_FAILED" == true ]]; then
    exit 1
fi
