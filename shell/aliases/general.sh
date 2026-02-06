#!/bin/bash

# General aliases for modern CLI tools and productivity

# Modern CLI tool aliases
# Note: 'ls' kept as system default for compatibility (muscle memory for -ltr, etc.)
# Use eza variants (ll, la, l, tree) for enhanced features
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

# Keep ls as system default
alias ls='ls --color=auto'

# OS-aware aliases for bat and fd (safe aliases that don't override system commands)
if command -v batcat &> /dev/null; then
    alias bat='batcat'
    alias view='batcat'
elif command -v bat &> /dev/null; then
    alias view='bat'
fi

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias -- -='cd -'

# File operations

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

# tmux shortcuts
alias tm='tmux new -s'
alias ta='tmux attach -t'
alias tl='tmux list-sessions'
alias tk='tmux kill-session -t'

# tmux config switching
alias tmux-minimal='$DOTFILES_DIR/bin/tmux-config-switcher minimal'
alias tmux-full='$DOTFILES_DIR/bin/tmux-config-switcher full'
alias tmux-mode='$DOTFILES_DIR/bin/tmux-config-switcher'

# File viewing and editing
# Neovim as default editor with escape hatches to real vim/vi
if command -v nvim >/dev/null 2>&1; then
    alias vim='nvim'
    alias vi='nvim'
    # Escape hatches to use actual vim/vi if needed
    command -v vim >/dev/null 2>&1 && alias vimvim='command vim'
    command -v vi >/dev/null 2>&1 && alias vivim='command vi'
fi
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

# Reload shell (works for both bash and zsh)
if [[ -n "$ZSH_VERSION" ]]; then
    alias reload='source ~/.zshrc'
    alias zshrc='nvim ~/.zshrc'
elif [[ -n "$BASH_VERSION" ]]; then
    alias reload='source ~/.bashrc'
    alias bashrc='nvim ~/.bashrc'
fi

# Theme management
alias theme-switch='$DOTFILES_DIR/bin/theme-switcher'
# Dynamic theme listing from configs/themes directory
alias themes='ls -1 "$DOTFILES_DIR/configs/themes/" 2>/dev/null | sed "s/^/  - /" && echo "" && echo "Use: theme-switch <name>"'

# Dotfiles management
alias update-claude-commands='$DOTFILES_DIR/bin/update-claude'

# Find and replace utility
alias fr='$DOTFILES_DIR/bin/fr'

# Cheatsheet for keybindings
alias cheat='$DOTFILES_DIR/bin/cheatsheet'

# Claude CLI shortcuts
alias cl='claude'                # New session
alias clc='claude --continue'    # Continue last session
alias clp='claude --print'       # One-off command (non-interactive)

# direnv shortcuts
if command -v direnv >/dev/null 2>&1; then
    alias da='direnv allow'
    alias de='${EDITOR:-nvim} .envrc'
fi

# btop as top replacement
if command -v btop >/dev/null 2>&1; then
    alias top='btop'
fi
