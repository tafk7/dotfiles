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
alias ports='netstat -tulanp'
alias myip='curl ifconfig.me'
alias localip='hostname -I'

# File viewing and editing
alias nano='nano -w'
alias less='less -R'

# Process management
alias killall='killall -v'

# Disk usage
alias du1='du -h --max-depth=1'
alias ducks='du -cks * | sort -rn | head'

# History
alias h='history'
alias hgrep='history | grep'

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
