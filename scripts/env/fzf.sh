#!/bin/bash
# FZF Essential Configuration
# Minimal setup for FZF with sensible defaults

# ==============================================================================
# FZF Core Settings
# ==============================================================================

# Default options - simple and fast
export FZF_DEFAULT_OPTS="
    --height 60%
    --layout=reverse
    --border=rounded
    --preview-window=right:60%:wrap
    --bind 'ctrl-/:change-preview-window(down|hidden|)'
    --bind 'ctrl-p:toggle-preview'"

# ==============================================================================
# File Search Configuration
# ==============================================================================

# Use fd/fdfind if available for better performance
if command -v fd >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
elif command -v fdfind >/dev/null 2>&1; then
    export FZF_DEFAULT_COMMAND='fdfind --type f --hidden --follow --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_ALT_C_COMMAND='fdfind --type d --hidden --follow --exclude .git'
fi

# ==============================================================================
# Preview Configuration
# ==============================================================================

# Ctrl-T: File preview with syntax highlighting
if command -v bat >/dev/null 2>&1; then
    export FZF_CTRL_T_OPTS="
        --preview 'bat --style=numbers --color=always --line-range :500 {}'
        --bind 'ctrl-p:toggle-preview'"
elif command -v batcat >/dev/null 2>&1; then
    export FZF_CTRL_T_OPTS="
        --preview 'batcat --style=numbers --color=always --line-range :500 {}'
        --bind 'ctrl-p:toggle-preview'"
else
    export FZF_CTRL_T_OPTS="
        --preview 'cat {}'
        --bind 'ctrl-p:toggle-preview'"
fi

# Alt-C: Directory preview
if command -v eza >/dev/null 2>&1; then
    export FZF_ALT_C_OPTS="
        --preview 'eza --tree --color=always --level=2 {} | head -200'
        --bind 'ctrl-p:toggle-preview'"
elif command -v tree >/dev/null 2>&1; then
    export FZF_ALT_C_OPTS="
        --preview 'tree -C {} | head -200'
        --bind 'ctrl-p:toggle-preview'"
fi

# Ctrl-R: Better history search
export FZF_CTRL_R_OPTS="
    --preview 'echo {}'
    --preview-window down:3:hidden:wrap
    --bind 'ctrl-p:toggle-preview'
    --exact"

# ==============================================================================
# Integration with zoxide
# ==============================================================================

# Interactive mode with fzf
if command -v zoxide >/dev/null 2>&1; then
    alias zi='zoxide query -i'
fi

# ==============================================================================
# Optional: Load advanced FZF functions
# ==============================================================================
# To enable advanced FZF functions (git integrations, ripgrep, etc.):
# Uncomment the following line in your ~/.zshrc.local or ~/.bashrc.local
# source "$DOTFILES_DIR/scripts/functions/fzf-extras.sh"
