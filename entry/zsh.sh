# shellcheck shell=bash
# Zsh configuration (linted as bash since shellcheck has no native zsh mode;
# zsh-only constructs below carry per-line `shellcheck disable` directives)
# Owns: zsh options, history, completion, keybindings

# DOTFILES_DIR + env are normally established by ~/.zshenv (entry/zshenv).
# This block is a defensive fallback for installs where .zshenv was opted
# out of or symlinked manually but .zshrc wasn't. Profile sourcing is
# idempotent via _PROFILE_LOADED.
if [[ -z "${DOTFILES_DIR:-}" ]]; then
    DOTFILES_DIR="$(dirname "$(dirname "$(readlink -f ~/.zshrc)")")"
    export DOTFILES_DIR
    [[ -f "$DOTFILES_DIR/generated/bridge.sh" ]] && source "$DOTFILES_DIR/generated/bridge.sh"
    [[ -f "$HOME/.profile" ]] && source "$HOME/.profile"
fi

# ==============================================================================
# Zsh Options
# ==============================================================================

# History
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=100000

setopt EXTENDED_HISTORY          # ":start:elapsed;command" format
setopt INC_APPEND_HISTORY        # Write immediately
setopt SHARE_HISTORY             # Share between sessions
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY               # Don't execute on expansion

# Navigation
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT

# Globbing
setopt EXTENDED_GLOB
setopt GLOB_DOTS

# Completion behavior
setopt COMPLETE_IN_WORD
setopt ALWAYS_TO_END
setopt AUTO_LIST
setopt AUTO_PARAM_SLASH

# ==============================================================================
# Shared initialization sequence
# ==============================================================================

SHELL_NAME=zsh
source "$DOTFILES_DIR/shell/init.sh"

# ==============================================================================
# Completion System (must be after init.sh)
# ==============================================================================

autoload -Uz compinit
compinit

zstyle ':completion:*' completer _complete _ignored
# shellcheck disable=SC2296  # zsh-specific (s.:.) parameter expansion flag
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu select
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache

zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes

# Tool completions (must be after compinit)
if command -v uv >/dev/null 2>&1; then
    eval "$(uv generate-shell-completion zsh 2>/dev/null || true)"
fi
if command -v poetry >/dev/null 2>&1; then
    eval "$(poetry completions zsh 2>/dev/null | sed '/_poetry_[a-f0-9]*_complete "\$@"/d' || true)"
fi

# ==============================================================================
# Key Bindings
# ==============================================================================

bindkey -e

bindkey '^[[1;5C' forward-word    # Ctrl+Right
bindkey '^[[1;5D' backward-word   # Ctrl+Left

autoload -U edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# FZF integration (after compinit + keybindings so it can wrap completion and bind ^R)
command -v fzf >/dev/null 2>&1 && eval "$(fzf --zsh)"
