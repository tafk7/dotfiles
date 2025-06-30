#!/bin/bash

# General aliases for modern CLI tools and productivity

# Modern replacements for classic commands
alias ls='eza --icons'
alias ll='eza -alF --icons'
alias la='eza -A --icons'
alias l='eza -CF --icons'
alias tree='eza --tree --icons'

# OS-aware aliases for bat and fd
if command -v batcat &> /dev/null; then
    alias cat='batcat'
elif command -v bat &> /dev/null; then
    alias cat='bat'
fi

if command -v fdfind &> /dev/null; then
    alias find='fdfind'
elif command -v fd &> /dev/null; then
    alias find='fd'
fi

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'

# File operations
alias rm='rm -i'
alias mkdir='mkdir -p'

# Grep with color
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# System information
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ps='ps auxf'
alias psg='ps aux | grep -v grep | grep -i -e VSZ -e'

# Network
alias ping='ping -c 5'
alias ports='netstat -tulanp'
alias myip='curl ifconfig.me'
alias localip='hostname -I'

# tmux shortcuts
alias tm='tmux new -s'
alias ta='tmux attach -t'
alias tl='tmux list-sessions'
alias tk='tmux kill-session -t'

# Git shortcut
alias g='git'

# File viewing and editing
alias vi='vim'
alias nano='nano -w'
alias less='less -R'
alias more='less'

# Archive operations
alias untar='tar -zxvf'
alias tar='tar -czf'

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

# Reload shell
alias reload='source ~/.zshrc'
alias zshrc='vim ~/.zshrc'

# Quick file operations
alias count='find . -type f | wc -l'
alias cpv='cp -v'
alias rmv='rm -v'
