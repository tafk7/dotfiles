#!/bin/bash
# General aliases — modern CLI tools and productivity

# Modern CLI tool aliases
if command -v eza >/dev/null 2>&1; then
    alias ll='eza -l --color=auto --group-directories-first --time-style=long-iso'
    alias la='eza -la --color=auto --group-directories-first --time-style=long-iso'
    alias l='eza -CF --color=auto --group-directories-first'
    alias tree='eza --tree --color=auto --group-directories-first'
else
    alias ll='ls -alF --color=auto'
    alias la='ls -A --color=auto'
    alias l='ls -CF --color=auto'
    command -v tree >/dev/null 2>&1 && alias tree='tree -C'
fi

alias ls='ls --color=auto'

# File viewer
command -v bat &>/dev/null && alias view='bat'

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias -- -='cd -'

# Grep with color
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# System information
alias df='df -h'
alias du='du -h'
alias free='free -h'

# Network
alias ports='ss -tulanp'
# Clear the pre-upgrade alias before Bash/Zsh parse the function on reload.
unalias myip 2>/dev/null || true
myip() {
    curl --fail --silent --show-error --max-time 10 --proto '=https' \
        https://ifconfig.me/ip
    printf '\n'
}
alias localip='hostname -I'

# File viewing and editing
alias nano='nano -w'
alias less='less -R'

# Print canonical paths. With no arguments, resolve the current directory;
# otherwise resolve every supplied path.
p() {
    if (( $# == 0 )); then
        pwd -P
    else
        realpath -- "$@"
    fi
}

# Process management
alias killall='killall -v'

# Disk usage
alias du1='du -h --max-depth=1'
alias ducks='du -cks * | sort -rn | head'

# History
alias h='history'
alias hgrep='history | grep'

# Disable terminal mouse-reporting modes that may be left enabled when an SSH
# connection or mouse-aware TUI exits without cleaning up. Safe to run manually
# when pointer movement or scrolling prints escape-sequence garbage.
fixmouse() {
    printf '\033[?9l\033[?1000l\033[?1001l\033[?1002l\033[?1003l\033[?1005l\033[?1006l\033[?1007l\033[?1015l'
}

# Publish explicitly cut command-line text to the tmux server-wide buffer.
# Shell-specific line-editor widgets call this after removing their range.
_tafk_tmux_buffer_set() {
    [[ -n "${TMUX:-}" && -n "${1:-}" ]] || return 0
    printf '%s' "$1" | tmux load-buffer -
}

# Reload shell config. Unsets idempotency guards so the guarded portion of
# env.sh + profile.sh actually re-runs (alias-based 'source ~/.bashrc' would
# skip them entirely — leaving stale PATH/env state).
# Note: stale aliases/functions from removed tool modules persist across a
# `reload`; use `exec $SHELL -l` for a true clean slate.
# `unalias` is defensive for users upgrading from the previous version of
# this file (which defined `reload` as an alias); zsh refuses to define a
# function whose name is an existing alias.
unalias reload 2>/dev/null
reload() {
    unset _DOTFILES_ENV_LOADED _PROFILE_LOADED
    if [[ -n "$ZSH_VERSION" ]]; then
        source ~/.zshrc
    else
        source ~/.bashrc
    fi
}

if [[ -n "$ZSH_VERSION" ]]; then
    alias zshrc='nvim ~/.zshrc'
elif [[ -n "$BASH_VERSION" ]]; then
    alias bashrc='nvim ~/.bashrc'
fi

# Theme management
alias theme='$DOTFILES_DIR/bin/theme-switcher'
alias themes='ls -1 "$DOTFILES_DIR/themes/" 2>/dev/null | sed "s/^/  - /" && echo "" && echo "Use: theme <name>  (or: theme set <target> <name>)"'

# These applications accept a config path at launch, which keeps their theme
# local to this shell's tmux context instead of patching a shared user file.
btop() {
    if [[ -n "${DOTFILES_THEME_BTOP_RESOLVED:-}" && -n "${BTOP_THEME_CONFIG:-}" ]]; then
        "$DOTFILES_DIR/bin/theme-switcher" prepare "$DOTFILES_THEME_BTOP_RESOLVED" >/dev/null
        command btop --config "$BTOP_THEME_CONFIG" --themes-dir "${BTOP_THEME_DIR:?}" "$@"
    else
        command btop "$@"
    fi
}

lazygit() {
    local files="${LAZYGIT_THEME_CONFIG:-}"
    if [[ -n "$files" ]]; then
        [[ -f "$HOME/.config/lazygit/config.yml" ]] && files="$HOME/.config/lazygit/config.yml,$files"
        command lazygit --use-config-file="$files" "$@"
    else
        command lazygit "$@"
    fi
}

# Find and replace utility
alias fr='$DOTFILES_DIR/bin/replace'

# Cheatsheet for keybindings
alias cheat='$DOTFILES_DIR/bin/cheatsheet'

# direnv shortcuts
if command -v direnv >/dev/null 2>&1; then
    alias da='direnv allow'
    alias de='${EDITOR:-nvim} .envrc'
fi

# btop as top replacement
command -v btop >/dev/null 2>&1 && alias top='btop'
