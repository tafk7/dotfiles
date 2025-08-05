#!/bin/bash

# General aliases for modern CLI tools and productivity

# Modern replacements for classic commands (standardized)
if command -v eza >/dev/null 2>&1; then
    alias ls='eza --color=always --group-directories-first'
    alias ll='eza -l --color=always --group-directories-first --time-style=long-iso'
    alias la='eza -la --color=always --group-directories-first --time-style=long-iso'
    alias l='eza -CF --color=always --group-directories-first'
    alias tree='eza --tree --color=always --group-directories-first'
else
    alias ls='ls --color=auto'
    alias ll='ls -alF'
    alias la='ls -A'
    alias l='ls -CF'
    alias tree='tree -C'
fi

# OS-aware aliases for bat and fd (safe aliases that don't override system commands)
if command -v batcat &> /dev/null; then
    alias bat='batcat'
    alias view='batcat'
elif command -v bat &> /dev/null; then
    alias view='bat'
fi

if command -v fdfind &> /dev/null; then
    alias fd='fdfind'
fi

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
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
# Process search is now in scripts/functions/process.sh

# Network
alias ports='netstat -tulanp'
alias myip='curl ifconfig.me'
alias localip='hostname -I'

# tmux shortcuts
alias tm='tmux new -s'
alias ta='tmux attach -t'
alias tl='tmux list-sessions'
alias tk='tmux kill-session -t'

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

# Archive operations (safe aliases that don't override tar)
alias untar='tar -zxvf'
alias tarc='tar -czf'  # tar create

# Process management
alias psmem='ps auxf | sort -nr -k 4'
alias pscpu='ps auxf | sort -nr -k 3'
alias killall='killall -v'

# Disk usage
alias du1='du -h --max-depth=1'
alias ducks='du -cks * | sort -rn | head'

# History
alias h='history'
alias hgrep='history | grep'

# Safer alternatives (explicit commands)
alias rmff='rm -rf'   # force remove (double 'f' for safety)
alias rmi='rm -i'     # interactive remove

# Reload shell (works for both bash and zsh)
if [[ -n "$ZSH_VERSION" ]]; then
    alias reload='source ~/.zshrc'
    alias zshrc='vim ~/.zshrc'
elif [[ -n "$BASH_VERSION" ]]; then
    alias reload='source ~/.bashrc'
    alias bashrc='vim ~/.bashrc'
fi

# Theme management
alias theme-switch='$DOTFILES_DIR/scripts/theme-switcher.sh'
alias themes='echo "Available themes: nord, kanagawa, tokyo-night, gruvbox-material, catppuccin-mocha"'

# Quick file operations
alias count='find . -type f | wc -l'
alias cpv='cp -v'
alias rmv='rm -v'

# Markdown viewing - use bat for syntax highlighting
if command -v batcat &> /dev/null; then
    alias md='batcat --style=plain --language=markdown'  # View markdown files
elif command -v bat &> /dev/null; then
    alias md='bat --style=plain --language=markdown'  # View markdown files
fi

# Dotfiles management
alias update-configs='$DOTFILES_DIR/scripts/update-configs.sh'
alias update-configs-force='$DOTFILES_DIR/scripts/update-configs.sh --force'
alias update-claude-commands='$DOTFILES_DIR/scripts/update-claude-commands.sh'

# Find and replace utility
alias fr='$DOTFILES_DIR/scripts/utils/fr.sh'
alias find-replace='$DOTFILES_DIR/scripts/utils/fr.sh'

# Cheatsheet for keybindings
alias cheat='$DOTFILES_DIR/scripts/utils/cheatsheet.sh'
alias shortcuts='cheat'  # Alternative alias
