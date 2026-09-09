#!/bin/bash
# Single shared initialization sequence for all shells.
# Sourced by entry/bash.sh and entry/zsh.sh after bridge.sh.
# Entry files set SHELL_NAME before sourcing this.

if [[ -z "${DOTFILES_DIR:-}" ]]; then
    echo "Warning: DOTFILES_DIR not set." >&2
    return 0
fi

# Always-fresh exports (point at generated/; intentionally un-guarded so
# `reload` re-evaluates them after a theme switch)
source "$DOTFILES_DIR/shell/env-runtime.sh"

# Static exports (guarded by _DOTFILES_ENV_LOADED)
source "$DOTFILES_DIR/shell/env.sh"

# Tool initialization (interactive only — evals)
[[ $- == *i* ]] && source "$DOTFILES_DIR/shell/tool-init.sh"

# FZF configuration
[[ -f "$DOTFILES_DIR/shell/fzf.sh" ]] && source "$DOTFILES_DIR/shell/fzf.sh"

# Tool modules (co-located functions + aliases per domain)
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

# Existing interactive shells adopt scoped changes at the next prompt. The
# signature check avoids rebuilding or re-exporting anything when state is
# unchanged; the only steady-state work in tmux is reading one user option.
[[ -f "$DOTFILES_DIR/shell/theme-runtime.sh" ]] && source "$DOTFILES_DIR/shell/theme-runtime.sh"

# FZF key bindings + completion (fzf >= 0.48 generates its own shell integration)
# zsh: deferred to entry/zsh.sh after compinit so tab completion integrates properly
if command -v fzf >/dev/null 2>&1 && [[ "$SHELL_NAME" != "zsh" ]]; then
    eval "$(fzf --bash)"
fi

# Zoxide
command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init "$SHELL_NAME")"

# NVM lazy loader
source "$DOTFILES_DIR/shell/lazy/nvm.sh"

# Local overrides (not tracked)
[[ -f ~/.shell.local ]] && source ~/.shell.local

# Collapse duplicate PATH entries. Must run LAST: vendor scripts sourced from
# ~/.shell.local (e.g. Xilinx settings64.sh) prepend unconditionally, and
# because this file is re-sourced by every nested interactive shell and by
# `reload`, those entries accumulate — 330 entries / 35 unique / 16.8KB was the
# observed steady state. Defined in shell/env-runtime.sh and shared with the
# non-interactive path; see the comment there.
command -v _dotfiles_dedupe_path >/dev/null 2>&1 && _dotfiles_dedupe_path

# Leave a clean exit status. A missing ~/.shell.local (or a non-zero last
# command inside it) would otherwise leave $?=1 after startup, which a status-
# aware prompt (e.g. starship) renders as an error on the very first prompt.
true
