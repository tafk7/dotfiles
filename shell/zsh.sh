# Zsh configuration
# Owns: zsh options, history, completion, keybindings, prompt

[[ -f "$HOME/.profile" ]] && source "$HOME/.profile"
[[ -f "$HOME/.config/dotfiles/env" ]] && source "$HOME/.config/dotfiles/env"

if [[ -z "${DOTFILES_DIR:-}" ]]; then
    export DOTFILES_DIR="$(dirname "$(dirname "$(readlink -f ~/.zshrc)")")"
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
# Shared sequence (env → theme → fzf → functions → aliases)
# ==============================================================================

source "$DOTFILES_DIR/shell/shared.sh"

# ==============================================================================
# Prompt
# ==============================================================================

if command -v starship >/dev/null 2>&1; then
    eval "$(starship init zsh)"
else
    PS1='%F{cyan}%~%f %# '
fi

# ==============================================================================
# Completion System
# ==============================================================================

autoload -Uz compinit
compinit

zstyle ':completion:*' completer _complete _ignored
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
    # Poetry's completion script ends with a bare call to the completion function
    # (e.g. `_poetry_xxx_complete "$@"`), which executes it immediately at eval time.
    # This triggers _describe → _tags → comptags errors because comptags can only
    # run inside the ZLE completion widget context. Strip that line, keep compdef.
    eval "$(poetry completions zsh 2>/dev/null | sed '/_poetry_[a-f0-9]*_complete "\$@"/d' || true)"
fi

# ==============================================================================
# Key Bindings
# ==============================================================================

bindkey -e

bindkey '^R' history-incremental-search-backward
bindkey '^S' history-incremental-search-forward

bindkey '^[[1;5C' forward-word    # Ctrl+Right
bindkey '^[[1;5D' backward-word   # Ctrl+Left

autoload -U edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# ==============================================================================
# FZF Key Bindings (zsh-specific)
# ==============================================================================

if command -v fzf >/dev/null 2>&1; then
    [[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]] && \
        source /usr/share/doc/fzf/examples/key-bindings.zsh
    [[ -f /usr/share/doc/fzf/examples/completion.zsh ]] && \
        source /usr/share/doc/fzf/examples/completion.zsh
fi

# ==============================================================================
# Zoxide
# ==============================================================================

command -v zoxide >/dev/null 2>&1 && eval "$(zoxide init zsh)"

# ==============================================================================
# NVM (lazy)
# ==============================================================================

source "$DOTFILES_DIR/shell/nvm-lazy.sh"

# ==============================================================================
# Local Overrides (not tracked in git)
# ==============================================================================

[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local
