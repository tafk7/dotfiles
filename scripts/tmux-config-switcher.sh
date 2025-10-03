#!/bin/bash

# Switch between different tmux configurations

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/core.sh"

# Function to show usage
show_usage() {
    echo "Usage: $0 [minimal|full|plugin]"
    echo ""
    echo "Switch between tmux configurations:"
    echo "  minimal - Streamlined config for VS Code workflow (default)"
    echo "  full    - Original full-featured config with plugins"
    echo "  plugin  - Full config with TPM plugins"
    echo ""
    echo "Navigation style:"
    echo "  Set TMUX_NAV_STYLE=wasd for WASD navigation (default is ESDF)"
    echo ""
    echo "Current config: $(readlink ~/.tmux.conf 2>/dev/null || echo 'Unknown')"
    echo "Current nav style: ${TMUX_NAV_STYLE:-ESDF}"
}

# Get the configuration choice
CONFIG="${1:-minimal}"

case "$CONFIG" in
    minimal)
        log_info "Switching to minimal tmux configuration..."
        ln -sf "$DOTFILES_DIR/configs/tmux.conf.minimal" ~/.tmux.conf
        log_success "Switched to minimal configuration"
        ;;
    full)
        log_info "Switching to full tmux configuration..."
        ln -sf "$DOTFILES_DIR/configs/tmux.conf.backup" ~/.tmux.conf
        log_success "Switched to full configuration"
        ;;
    plugin)
        log_info "Switching to original plugin-based configuration..."
        ln -sf "$DOTFILES_DIR/configs/tmux.conf" ~/.tmux.conf
        log_success "Switched to plugin configuration"
        ;;
    *)
        log_error "Unknown configuration: $CONFIG"
        show_usage
        exit 1
        ;;
esac

# Show navigation tip
echo ""
log_info "Navigation style: ${TMUX_NAV_STYLE:-ESDF}"
log_info "To change navigation style, add to your shell config:"
log_info "  export TMUX_NAV_STYLE=wasd  # For WASD navigation"
log_info "  export TMUX_NAV_STYLE=esdf  # For ESDF navigation (default)"
echo ""
log_info "Reload tmux config with: tmux source-file ~/.tmux.conf"
log_info "Or press Ctrl+A, r inside tmux"