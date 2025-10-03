#!/bin/bash

# Install VS Code settings and extensions

set -euo pipefail

# Source common functions
source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/core.sh"

log_info "Setting up VS Code configuration..."

# VS Code config directories (support both Code and Code - OSS)
CODE_DIRS=(
    "$HOME/.config/Code/User"
    "$HOME/.config/Code - OSS/User"
)

# Find the active VS Code config directory
VSCODE_CONFIG_DIR=""
for dir in "${CODE_DIRS[@]}"; do
    if [[ -d "$(dirname "$dir")" ]]; then
        VSCODE_CONFIG_DIR="$dir"
        mkdir -p "$VSCODE_CONFIG_DIR"
        break
    fi
done

if [[ -z "$VSCODE_CONFIG_DIR" ]]; then
    log_error "VS Code configuration directory not found"
    log_info "Please install VS Code first: https://code.visualstudio.com/"
    exit 1
fi

log_info "Using VS Code config directory: $VSCODE_CONFIG_DIR"

# Backup existing settings if they exist
if [[ -f "$VSCODE_CONFIG_DIR/settings.json" ]]; then
    backup_file="$VSCODE_CONFIG_DIR/settings.json.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Backing up existing settings to $backup_file"
    cp "$VSCODE_CONFIG_DIR/settings.json" "$backup_file"
fi

if [[ -f "$VSCODE_CONFIG_DIR/keybindings.json" ]]; then
    backup_file="$VSCODE_CONFIG_DIR/keybindings.json.backup.$(date +%Y%m%d_%H%M%S)"
    log_info "Backing up existing keybindings to $backup_file"
    cp "$VSCODE_CONFIG_DIR/keybindings.json" "$backup_file"
fi

# Copy VS Code settings
log_info "Installing VS Code settings..."
cp "$DOTFILES_DIR/configs/vscode/settings.json" "$VSCODE_CONFIG_DIR/settings.json"
cp "$DOTFILES_DIR/configs/vscode/keybindings.json" "$VSCODE_CONFIG_DIR/keybindings.json"

# Install extensions if VS Code command is available
if command -v code >/dev/null 2>&1; then
    log_info "Installing recommended VS Code extensions..."
    
    # Essential extensions for hybrid vim workflow
    extensions=(
        "vscodevim.vim"
        "eamodio.gitlens"
        "mhutchie.git-graph"
        "arcticicestudio.nord-visual-studio-code"
        "ms-python.python"
        "ms-python.black-formatter"
        "esbenp.prettier-vscode"
        "christian-kohler.path-intellisense"
    )
    
    for ext in "${extensions[@]}"; do
        log_info "Installing extension: $ext"
        code --install-extension "$ext" || log_warning "Failed to install $ext"
    done
    
    # Install theme based on current dotfiles theme
    if [[ -f "$HOME/.config/dotfiles/theme.sh" ]]; then
        source "$HOME/.config/dotfiles/theme.sh"
        case "${DOTFILES_THEME:-nord}" in
            "tokyo-night")
                code --install-extension "enkia.tokyo-night" || true
                ;;
            "catppuccin-mocha")
                code --install-extension "Catppuccin.catppuccin-vsc" || true
                ;;
            "gruvbox-material")
                code --install-extension "sainnhe.gruvbox-material" || true
                ;;
            "kanagawa")
                code --install-extension "metaphore.kanagawa-vscode-color-theme" || true
                ;;
        esac
    fi
else
    log_warning "VS Code command not found. Please install extensions manually."
    log_info "See $DOTFILES_DIR/configs/vscode/extensions.md for the list"
fi

log_success "VS Code configuration completed!"
log_info "Reload VS Code to apply settings"

# Set VS Code as default editor if not already set
if [[ -z "${EDITOR:-}" ]] || [[ "$EDITOR" != *"code"* ]]; then
    log_info "Setting VS Code as default editor..."
    echo "" >> "$HOME/.zshrc.local"
    echo "# VS Code as default editor" >> "$HOME/.zshrc.local"
    echo "export EDITOR='code --wait'" >> "$HOME/.zshrc.local"
    echo "export VISUAL='code --wait'" >> "$HOME/.zshrc.local"
    log_info "Added to ~/.zshrc.local - reload shell to apply"
fi