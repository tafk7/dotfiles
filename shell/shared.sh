#!/bin/bash
# Shared shell startup sequence — sourced by both bash.sh and zsh.sh
# Defines the canonical order: env → theme → fzf → functions → aliases → local

# Validate DOTFILES_DIR
if [[ -z "${DOTFILES_DIR:-}" ]]; then
    echo "Warning: DOTFILES_DIR not set." >&2
    return 0
fi

# Tool initialization (version managers, EDITOR, tool-specific settings, WSL env)
[[ -f "$DOTFILES_DIR/shell/env.sh" ]] && source "$DOTFILES_DIR/shell/env.sh"

# Theme (must load before fzf.sh to set FZF_THEME_COLORS)
[[ -f "$HOME/.config/dotfiles/theme.sh" ]] && source "$HOME/.config/dotfiles/theme.sh"

# FZF configuration
[[ -f "$DOTFILES_DIR/shell/fzf.sh" ]] && source "$DOTFILES_DIR/shell/fzf.sh"

# Functions (domain-split)
for _fn_file in "$DOTFILES_DIR"/shell/functions/*.sh; do
    [[ -r "$_fn_file" ]] && source "$_fn_file"
done
unset _fn_file

# Aliases
for _alias_file in "$DOTFILES_DIR"/shell/aliases/*.sh; do
    [[ -r "$_alias_file" ]] && source "$_alias_file"
done
unset _alias_file

# Local overrides (not tracked)
[[ -f ~/.shell.local ]] && source ~/.shell.local
