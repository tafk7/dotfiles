#!/bin/bash
# Single shared initialization sequence for all shells.
# Sourced by entry/bash.sh and entry/zsh.sh after bridge.sh.
# Entry files set SHELL_NAME before sourcing this.

if [[ -z "${DOTFILES_DIR:-}" ]]; then
    echo "Warning: DOTFILES_DIR not set." >&2
    return 0
fi

# Static exports (fast, no evals)
source "$DOTFILES_DIR/shell/env.sh"

# Tool initialization (interactive only — evals)
[[ $- == *i* ]] && source "$DOTFILES_DIR/shell/tool-init.sh"

# Theme (must load before fzf.sh to set FZF_THEME_COLORS)
[[ -f "$DOTFILES_DIR/generated/theme.sh" ]] && source "$DOTFILES_DIR/generated/theme.sh"

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

# Prompt
if command -v starship >/dev/null 2>&1; then
    eval "$(starship init "$SHELL_NAME")"
elif [[ "$SHELL_NAME" == "zsh" ]]; then
    PS1='%F{cyan}%~%f %# '
else
    PS1='\[\e[38;5;108m\]\u\[\e[0m\]@\[\e[38;5;214m\]\h\[\e[0m\]:\[\e[38;5;108m\]\w\[\e[0m\] \$ '
fi

# FZF key bindings (shell-specific paths)
if command -v fzf >/dev/null 2>&1; then
    if [[ "$SHELL_NAME" == "zsh" ]]; then
        [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && \
            source /usr/share/doc/fzf/examples/key-bindings.zsh
        [[ -f /usr/share/doc/fzf/examples/completion.zsh ]] && \
            source /usr/share/doc/fzf/examples/completion.zsh
    else
        [[ -f /usr/share/doc/fzf/examples/key-bindings.bash ]] && \
            source /usr/share/doc/fzf/examples/key-bindings.bash
        [[ -f /usr/share/doc/fzf/examples/completion.bash ]] && \
            source /usr/share/doc/fzf/examples/completion.bash
    fi
fi

# Zoxide
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init "$SHELL_NAME")"

# NVM lazy loader
source "$DOTFILES_DIR/shell/lazy/nvm.sh"

# Local overrides (not tracked)
[[ -f ~/.shell.local ]] && source ~/.shell.local
