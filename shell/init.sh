#!/bin/bash
# Shared interactive initialization for bash and zsh. Entry files set
# SHELL_NAME before sourcing this.

if [[ -z "${DOTFILES_DIR:-}" ]]; then
    echo "Warning: DOTFILES_DIR not set." >&2
    return 0
fi

# Always-fresh Layer 0 exports; intentionally unguarded so `reload` refreshes
# project activation.
source "$DOTFILES_DIR/shell/env-runtime.sh"

source "$DOTFILES_DIR/shell/env.sh"

# The previous theme system exported per-shell theme variables, and a tmux
# server started from such a shell hands them to every new pane. Drop them, or
# stale BAT_THEME/STARSHIP_CONFIG values override the palette-based configs.
if [[ -n "${DOTFILES_THEME_CONTEXT_SIGNATURE:-}" ]]; then
    unset DOTFILES_THEME DOTFILES_THEME_CONTEXT_SIGNATURE DOTFILES_THEME_ENABLED \
        DOTFILES_THEME_SESSION_ID DOTFILES_THEME_WINDOW_ID \
        DOTFILES_THEME_VIM_RESOLVED DOTFILES_THEME_BAT_RESOLVED DOTFILES_THEME_DELTA_RESOLVED \
        DOTFILES_THEME_TMUX_RESOLVED DOTFILES_THEME_STARSHIP_RESOLVED DOTFILES_THEME_FZF_RESOLVED \
        DOTFILES_THEME_BTOP_RESOLVED DOTFILES_THEME_LAZYGIT_RESOLVED \
        BAT_THEME BAT_CACHE_PATH STARSHIP_CONFIG STARSHIP_PALETTE DELTA_FEATURE DELTA_FEATURES \
        BTOP_THEME_CONFIG BTOP_THEME_DIR LAZYGIT_THEME_CONFIG FZF_THEME_COLORS \
        THEME_TINT_1 THEME_TINT_2 THEME_TINT_3
fi

[[ $- == *i* ]] && source "$DOTFILES_DIR/shell/tool-init.sh"

[[ -f "$DOTFILES_DIR/shell/fzf.sh" ]] && source "$DOTFILES_DIR/shell/fzf.sh"

for _tool_file in "$DOTFILES_DIR"/shell/tools/*.sh; do
    [[ -r "$_tool_file" ]] && source "$_tool_file"
done
unset _tool_file

# An interrupted SSH/TUI session can leave the client terminal in mouse-report
# mode, causing movement and wheel events to print as escape-sequence garbage.
# Reset only at a fresh interactive SSH prompt outside tmux; tmux will enable
# the modes it needs when attached.
if [[ $- == *i* && -n "${SSH_CONNECTION:-}" && -z "${TMUX:-}" && "${TERM:-dumb}" != dumb ]]; then
    fixmouse
fi

if [[ "${DOTFILES_WSL:-0}" == "1" ]] || command -v wslpath >/dev/null 2>&1; then
    [[ -f "$DOTFILES_DIR/shell/platform/wsl.sh" ]] && \
        source "$DOTFILES_DIR/shell/platform/wsl.sh"
fi

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init "$SHELL_NAME")"
elif [[ "$SHELL_NAME" == "zsh" ]]; then
    PS1='%F{cyan}%~%f %# '
else
    PS1='\[\e[38;5;108m\]\u\[\e[0m\]@\[\e[38;5;214m\]\h\[\e[0m\]:\[\e[38;5;108m\]\w\[\e[0m\] \$ '
fi

# FZF key bindings + completion (fzf >= 0.48 generates its own shell integration)
# zsh: deferred to entry/zsh.sh after compinit so tab completion integrates properly
if command -v fzf >/dev/null 2>&1 && [[ "$SHELL_NAME" != "zsh" ]]; then
    eval "$(fzf --bash)"
fi

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init "$SHELL_NAME")"

source "$DOTFILES_DIR/shell/lazy/nvm.sh"

source "$DOTFILES_DIR/shell/local.sh"

# Must run last: vendor scripts sourced from ~/.shell.local prepend
# unconditionally, and nested shells and `reload` would accumulate them.
command -v _dotfiles_dedupe_path >/dev/null 2>&1 && _dotfiles_dedupe_path

# Leave a clean exit status, or the prompt shows an error on its first render.
true
