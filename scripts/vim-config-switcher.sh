#!/bin/bash

# Switch between different vim configurations

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/core.sh"

# Function to show usage
show_usage() {
    echo "Usage: $0 [minimal|full]"
    echo ""
    echo "Switch between vim configurations:"
    echo "  minimal - Fast, lightweight config for quick edits (5 plugins)"
    echo "  full    - Full-featured config with all plugins (18+ plugins)"
    echo ""
    echo "Current config: $(readlink ~/.config/nvim/init.vim 2>/dev/null | xargs basename | sed 's/init.vim.//' || echo 'Unknown')"
    echo ""
    echo "Tip: Use minimal config for quick edits, full config for extended coding sessions"
}

# Get the configuration choice
CONFIG="${1:-}"

if [[ -z "$CONFIG" ]]; then
    show_usage
    exit 0
fi

# Ensure nvim config directory exists
mkdir -p ~/.config/nvim

case "$CONFIG" in
    minimal)
        log_info "Switching to minimal vim configuration..."
        ln -sf "$DOTFILES_DIR/configs/init.vim.minimal" ~/.config/nvim/init.vim
        log_success "Switched to minimal configuration (fast startup)"
        log_info "Run :PlugInstall in vim to install the 5 essential plugins"
        ;;
    full)
        log_info "Switching to full vim configuration..."
        ln -sf "$DOTFILES_DIR/configs/init.vim.full" ~/.config/nvim/init.vim
        log_success "Switched to full configuration (all features)"
        log_info "Run :PlugInstall in vim to install all plugins"
        ;;
    *)
        log_error "Unknown configuration: $CONFIG"
        show_usage
        exit 1
        ;;
esac

# Store preference
echo "$CONFIG" > ~/.config/nvim/.vim-mode

# Show what changed
echo ""
log_info "Key differences:"
if [[ "$CONFIG" == "minimal" ]]; then
    echo "  ✓ Fast startup (<50ms)"
    echo "  ✓ Essential plugins only (surround, commentary, fugitive)"
    echo "  ✓ Single colorscheme (Nord)"
    echo "  ✓ No language servers or linting"
    echo "  ✓ Perfect for quick edits"
else
    echo "  ✓ Full plugin suite (18+ plugins)"
    echo "  ✓ Language servers and linting (ALE)"
    echo "  ✓ Multiple colorschemes"
    echo "  ✓ File fuzzy finding (FZF)"
    echo "  ✓ Extended coding features"
fi