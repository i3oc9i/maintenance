#!/bin/zsh

# ------------------------------------------------------------------- Setup & Colors
# Handle the --auto flag
AUTO_MODE=false
if [[ "$1" == "--auto" ]]; then
    AUTO_MODE=true
fi

BOLD_BLUE="\033[1;34m"
BOLD_GREEN="\033[1;32m"
BOLD_YELLOW="\033[1;33m"
RESET="\033[0m"

# Helper function for confirmations (Bypassed if AUTO_MODE is true)
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

# 1. Header
if [[ "$AUTO_MODE" == true ]]; then
    echo "${BOLD_BLUE}--- SYSTEM MAINTENANCE (AUTO-PILOT MODE) ---${RESET}\n"
else
    echo "${BOLD_BLUE}--- SYSTEM MAINTENANCE ORCHESTRATOR ---${RESET}\n"
fi

# ------------------------------------------------------------------- HOMEBREW FORMULAE
if confirm "Homebrew (Formulae)"; then
    echo "${BOLD_GREEN}Updating Homebrew Formulae...${RESET}"
    brew update && brew upgrade && brew cleanup
fi

# ------------------------------------------------------------------- HOMEBREW CASKS 
if confirm "Homebrew (Casks)"; then
    echo "\n${BOLD_GREEN}Checking for Auto-Updating Casks...${RESET}"
    
    local -a casks
    casks=(${(f)"$(brew info --cask --json=v2 $(brew ls --cask) | jq -r '.casks[] | select(.auto_updates == true) | .token')"})
    
    if [[ ${#casks[@]} -gt 0 ]]; then
        echo "Updating ${#casks[@]} casks..."
        brew upgrade --cask "${casks[@]}"
    else
        echo "No auto-updating casks found."
    fi
fi

# ------------------------------------------------------------------- RUST
if confirm "Rust (Compiler & Cargo Binaries)"; then
    echo "\n${BOLD_GREEN}Updating Rust...${RESET}"
    if (( ${+commands[rustup]} )); then
        rustup update
    fi
    
    if (( ${+commands[cargo-install-update]} )); then
        cargo install-update -a
    else
        echo "cargo-update not found. Skipping binary updates."
    fi
fi

# ------------------------------------------------------------------- VOLTA
if confirm "Volta (Node, Bun, Deno & Tools)"; then
    echo "\n${BOLD_GREEN}Updating Volta Managed Packages...${RESET}"
    # This list mirrors your desired tools exactly
    volta install node yarn pnpm bun deno vite vitest sv serve \
    typescript-language-server typescript skills repomix \
    get-shit-done-cc ccstatusline
fi

# ------------------------------------------------------------------- PRE-COMMIT
if confirm "Global Pre-commit Hooks"; then
    echo "\n${BOLD_GREEN}Updating Global Pre-commit Hooks...${RESET}"
    
    PC_DIR="$HOME/.config/pre-commit"
    PC_CONFIG="global-config.yaml"

    if [[ -d "$PC_DIR" && -f "$PC_DIR/$PC_CONFIG" ]]; then
        (
            cd "$PC_DIR"
            # Self-healing: Ensure a dummy .git exists for the tool to run
            [[ ! -d ".git" ]] && git init -q
            
            # Simple update - no extra dependencies required
            pre-commit autoupdate --config "$PC_CONFIG"
        )
    else
        echo "Global config not found at $PC_DIR/$PC_CONFIG"
    fi
fi
# ------------------------------------------------------------------- Final Summary
echo "\n${BOLD_BLUE}--- Maintenance Complete! ---${RESET}"
