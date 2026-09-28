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

# Optional features begin here. Layer 0 above remains independent of theme
# state, rendering, tmux, and plugins.
source "$DOTFILES_DIR/shell/interactive/theme-env.sh"

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

# Existing interactive shells adopt scoped changes at the next prompt. The
# signature check avoids rebuilding or re-exporting anything when state is
# unchanged; the only steady-state work in tmux is reading one user option.
if [[ "${_DOTFILES_THEME_ACTIVE:-0}" == 1 && -f "$DOTFILES_DIR/shell/theme-runtime.sh" ]]; then
    source "$DOTFILES_DIR/shell/theme-runtime.sh"
fi
unset _DOTFILES_THEME_ACTIVE

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
