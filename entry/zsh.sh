# shellcheck shell=bash
# Zsh configuration (linted as bash since shellcheck has no native zsh mode;
# zsh-only constructs below carry per-line `shellcheck disable` directives)
# Owns: zsh options, history, completion, keybindings

# ~/.zshenv normally establishes DOTFILES_DIR and the environment; this is the
# fallback when only .zshrc is linked.
if [[ -z "${DOTFILES_DIR:-}" ]]; then
    # A flattened copy or bind mount defeats readlink; fall back to the recorded
    # install path. generated/bridge.sh is legacy, read-only compatibility.
    DOTFILES_DIR="$(dirname "$(dirname "$(readlink -f ~/.zshrc)")")"
    if [[ ! -f "$DOTFILES_DIR/shell/env.sh" ]]; then
        _dotfiles_path_file="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/install-path"
        if [[ -r "$_dotfiles_path_file" ]]; then
            IFS= read -r DOTFILES_DIR < "$_dotfiles_path_file"
        else
            DOTFILES_DIR="$HOME/dev/dotfiles"
        fi
        unset _dotfiles_path_file
    fi
    export DOTFILES_DIR
    _bridge="$DOTFILES_DIR/generated/bridge.sh"
    [[ -f "$_bridge" ]] && source "$_bridge"
    unset _bridge
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

# Vendored completion functions, generated on demand into a private fpath dir.
# MUST come before compinit — compinit scans fpath and registers what it finds.
#
# They are `#compdef` autoload stubs, so zsh parses the (large) body only on
# first use instead of at every startup.
_dotfiles_compdir="${DOTFILES_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles}/zsh/completions"
_dotfiles_comp_dirty=0

# uv: regenerate only when the binary is newer than the cached function.
# shellcheck disable=SC2154  # $commands is a zsh builtin hash (name -> path)
if command -v uv >/dev/null 2>&1; then
    if [[ ! -s "$_dotfiles_compdir/_uv" || "${commands[uv]}" -nt "$_dotfiles_compdir/_uv" ]]; then
        mkdir -p "$_dotfiles_compdir"
        if uv generate-shell-completion zsh >"$_dotfiles_compdir/_uv" 2>/dev/null; then
            _dotfiles_comp_dirty=1
        else
            rm -f "$_dotfiles_compdir/_uv"
        fi
    fi
fi

# shellcheck disable=SC2206  # zsh array splat; $fpath is already an array here
[[ -d "$_dotfiles_compdir" ]] && fpath=("$_dotfiles_compdir" $fpath)
unset _dotfiles_compdir

# Rebuild the completion dump at most once a day; otherwise `-C` skips the slow
# scan of every fpath entry. A tool installed today may lack completions until
# tomorrow; run `compinit` by hand if needed.
# shellcheck disable=SC2296,SC2298  # zsh glob qualifiers
autoload -Uz compinit
# Array assignment, because `[[` does not glob in zsh. Qualifiers: N=nullglob,
# .=plain file, mh+24=older than 24h. The eval keeps the file parseable by
# `bash -n` in the pre-commit hook.
eval '_zcompdump_stale=(${HOME}/.zcompdump(N.mh+24))'
# A regenerated completion function above means the dump no longer describes
# fpath, so force the full path in that case regardless of the dump's age.
# shellcheck disable=SC2154  # assigned inside the eval above
if (( ${#_zcompdump_stale} || _dotfiles_comp_dirty )); then
    compinit
    # compinit only rewrites the dump when completions changed; stamp it so the
    # slow path runs at most once a day.
    touch ~/.zcompdump
else
    compinit -C
fi
unset _zcompdump_stale _dotfiles_comp_dirty

zstyle ':completion:*' completer _complete _ignored
# shellcheck disable=SC2296  # zsh-specific (s.:.) parameter expansion flag
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' menu select
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path ~/.zsh/cache

zstyle ':completion:*:*:docker:*' option-stacking yes
zstyle ':completion:*:*:docker-*:*' option-stacking yes

# ==============================================================================
# Key Bindings
# ==============================================================================

bindkey -e

bindkey '^[[1;5C' forward-word    # Ctrl+Right
bindkey '^[[1;5D' backward-word   # Ctrl+Left
bindkey '^H' backward-kill-word   # Ctrl+Backspace (Backspace remains ^?)
bindkey '^[[3;5~' kill-word       # Ctrl+Delete
bindkey $'\e\x08' backward-kill-line # Alt+Backspace (BS encoding)
bindkey $'\e\x7f' backward-kill-line # Alt+Backspace (DEL encoding)
bindkey '^[[3;3~' kill-line          # Alt+Delete
bindkey '^[[Z' spell-word         # Shift+Tab

# Shift means the removed range is also published to tmux's shared buffer.
# Windows Terminal transports these chords as virtual F13-F16 sequences.
_tafk_cut_backward_word() {
    local before="$LBUFFER" removed
    zle backward-kill-word
    removed=${before[${#LBUFFER}+1,-1]}
    _tafk_tmux_buffer_set "$removed"
}

_tafk_cut_forward_word() {
    local before="$RBUFFER" removed count
    zle kill-word
    count=$(( ${#before} - ${#RBUFFER} ))
    (( count > 0 )) && removed=${before[1,count]}
    _tafk_tmux_buffer_set "$removed"
}

_tafk_cut_backward_line() {
    local before="$LBUFFER"
    zle backward-kill-line
    _tafk_tmux_buffer_set "$before"
}

_tafk_cut_forward_line() {
    local before="$RBUFFER"
    zle kill-line
    _tafk_tmux_buffer_set "$before"
}

zle -N tafk-cut-backward-word _tafk_cut_backward_word
zle -N tafk-cut-forward-word _tafk_cut_forward_word
zle -N tafk-cut-backward-line _tafk_cut_backward_line
zle -N tafk-cut-forward-line _tafk_cut_forward_line

bindkey $'\e[1;2P' tafk-cut-backward-word # Ctrl+Shift+Backspace
bindkey $'\e[1;2Q' tafk-cut-forward-word  # Ctrl+Shift+Delete
bindkey $'\e[1;2R' tafk-cut-backward-line # Alt+Shift+Backspace
bindkey $'\e[1;2S' tafk-cut-forward-line  # Alt+Shift+Delete

autoload -U edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# FZF integration (after compinit + keybindings so it can wrap completion and bind ^R)
command -v fzf >/dev/null 2>&1 && eval "$(fzf --zsh)"
