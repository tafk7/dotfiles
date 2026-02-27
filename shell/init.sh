#!/bin/bash
# Single shared initialization sequence for all shells.
# Sourced by entry/bash.sh and entry/zsh.sh after bridge.sh.
# Defines the canonical order. No shell-specific code.

if [[ -z "${DOTFILES_DIR:-}" ]]; then
    echo "Warning: DOTFILES_DIR not set." >&2
    return 0
fi

# Static exports (fast, no evals)
source "$DOTFILES_DIR/shell/env.sh"

# Tool initialization (interactive only — evals)
[[ $- == *i* ]] && source "$DOTFILES_DIR/shell/tool-init.sh"

# Theme (must load before fzf.sh to set FZF_THEME_COLORS)
for _theme_loader in "$DOTFILES_DIR/generated/theme-loader.sh" "$HOME/.config/dotfiles/theme.sh"; do
    if [[ -f "$_theme_loader" ]]; then
        source "$_theme_loader"
        break
    fi
done
unset _theme_loader

# FZF configuration
[[ -f "$DOTFILES_DIR/shell/fzf.sh" ]] && source "$DOTFILES_DIR/shell/fzf.sh"

# Tool modules (co-located functions + aliases per domain)
for _tool_file in "$DOTFILES_DIR"/shell/tools/*.sh; do
    [[ -r "$_tool_file" ]] && source "$_tool_file"
done
unset _tool_file

# WSL-specific (conditional)
if [[ "${DOTFILES_WSL:-0}" == "1" ]] || command -v wslpath >/dev/null 2>&1; then
    [[ -f "$DOTFILES_DIR/shell/platform/wsl.sh" ]] && \
        source "$DOTFILES_DIR/shell/platform/wsl.sh"
fi

# Local overrides (not tracked)
[[ -f ~/.shell.local ]] && source ~/.shell.local
