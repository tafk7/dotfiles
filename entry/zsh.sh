# shellcheck shell=bash
# Zsh configuration (linted as bash since shellcheck has no native zsh mode;
# zsh-only constructs below carry per-line `shellcheck disable` directives)
# Owns: zsh options, history, completion, keybindings

# DOTFILES_DIR + env are normally established by ~/.zshenv (entry/zshenv).
# This block is a defensive fallback for installs where .zshenv was opted
# out of or symlinked manually but .zshrc wasn't. Profile sourcing is
# idempotent via _PROFILE_LOADED.
if [[ -z "${DOTFILES_DIR:-}" ]]; then
    # readlink locates the repo, but a flattened symlink (bind-mount/copy) makes
    # it resolve wrong; let generated/bridge.sh override with the install-time
    # truth — try the derived path, then the conventional location.
    DOTFILES_DIR="$(dirname "$(dirname "$(readlink -f ~/.zshrc)")")"
    export DOTFILES_DIR
    for _bridge in "$DOTFILES_DIR/generated/bridge.sh" "$HOME/dev/dotfiles/generated/bridge.sh"; do
        [[ -f "$_bridge" ]] && { source "$_bridge"; break; }
    done
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
# These files are `#compdef`-style autoload stubs, so compinit only records the
# name; zsh parses the (6000+ line, for uv) body the first time you actually
# complete that command. Sourcing them at startup instead cost ~80ms per shell.
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

# Rebuild the completion dump at most once a day; otherwise trust the cache
# (`-C` skips the security/staleness scan of every fpath entry, ~85ms here).
# Trade-off: a tool installed today may not offer completions until tomorrow —
# run `compinit` by hand after installing something you want to complete now.
# shellcheck disable=SC2296,SC2298  # zsh glob qualifiers
autoload -Uz compinit
# Array assignment, not [[ -n ... ]] — `[[` does NOT perform filename generation
# in zsh, so a glob-qualifier test there is just a non-empty literal string and
# is always true. Qualifiers: N=nullglob, .=plain file, mh+24=mtime over 24h old.
#
# Wrapped in eval so `bash -n` (run by hooks/pre-commit on every *.sh file) can
# parse this file: the bare parenthesised glob qualifier is a bash syntax error.
# Only zsh ever sources this file, so the eval never runs anywhere else.
eval '_zcompdump_stale=(${HOME}/.zcompdump(N.mh+24))'
# A regenerated completion function above means the dump no longer describes
# fpath, so force the full path in that case regardless of the dump's age.
# shellcheck disable=SC2154  # assigned inside the eval above
if (( ${#_zcompdump_stale} || _dotfiles_comp_dirty )); then
    compinit
    # compinit only rewrites the dump when the completion set actually changed,
    # so without this the mtime never advances and every shell takes the slow
    # path forever. Stamping it makes the check a real once-a-day rebuild.
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

# (Tool completion functions are generated into fpath above, before compinit.)

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
