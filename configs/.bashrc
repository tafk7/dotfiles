# Bash Configuration
# Interactive shell configuration for bash

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Shell options
shopt -s histappend        # Append to history, don't overwrite
shopt -s checkwinsize      # Check window size after each command
shopt -s cdspell          # Correct minor spelling errors in cd
shopt -s dirspell         # Correct spelling errors in directory names

# Enable programmable completion features
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# History configuration
HISTFILE=~/.bash_history
HISTSIZE=50000
HISTFILESIZE=50000
HISTCONTROL=ignoreboth:erasedups  # Ignore duplicates and lines starting with space
HISTTIMEFORMAT="%F %T "           # Add timestamps to history

# User configuration
export LANG=en_US.UTF-8
export EDITOR='vim'
# VISUAL is set in .profile

# PATH additions
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/bin:$PATH"

# Development environment variables are set in .profile

# WSL specific configuration
if [[ -n "$WSL_DISTRO_NAME" ]]; then
    export BROWSER=wslview
    # WSL2 GUI support (WSLg)
    if [[ -n "$WAYLAND_DISPLAY" ]]; then
        # WSLg is available
        export DISPLAY=:0
    fi
fi

# FZF configuration
[ -f ~/.fzf.bash ] && source ~/.fzf.bash
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

# Node Version Manager (if installed)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Load dotfiles functions and aliases
DOTFILES_DIR="$HOME/dotfiles"
if [[ -d "$DOTFILES_DIR" ]]; then
    # Load functions
    for file in "$DOTFILES_DIR"/scripts/functions/*.sh; do
        [[ -r "$file" ]] && source "$file"
    done
    
    # Load aliases  
    for file in "$DOTFILES_DIR"/scripts/aliases/*.sh; do
        [[ -r "$file" ]] && source "$file"
    done
fi

# Local configuration (not tracked in git)
[[ -f ~/.bashrc.local ]] && source ~/.bashrc.local