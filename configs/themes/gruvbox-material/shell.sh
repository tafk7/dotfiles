#!/bin/bash
# Gruvbox Material theme for shell (FZF and prompt colors)

# FZF Gruvbox Material colors
export FZF_DEFAULT_OPTS='
    --height 40% --layout=reverse --border --inline-info
    --color=bg+:#3c3836,bg:#282828,spinner:#ea6962,hl:#504945
    --color=fg:#d4be98,header:#504945,info:#7daea3,pointer:#d8a657
    --color=marker:#ea6962,fg+:#d4be98,prompt:#7daea3,hl+:#d8a657
    --preview-window=right:50%:wrap'

# Shell colors for prompts (bash/zsh compatible)
if [[ -n "$BASH_VERSION" ]]; then
    # Bash prompt colors
    export PROMPT_COLOR_USER='\[\e[38;5;108m\]'      # Gruvbox Material aqua
    export PROMPT_COLOR_HOST='\[\e[38;5;214m\]'      # Gruvbox Material yellow
    export PROMPT_COLOR_PATH='\[\e[38;5;108m\]'      # Gruvbox Material aqua
    export PROMPT_COLOR_GIT_CLEAN='\[\e[38;5;142m\]' # Gruvbox Material green
    export PROMPT_COLOR_GIT_DIRTY='\[\e[38;5;167m\]' # Gruvbox Material red
    export PROMPT_COLOR_SUCCESS='\[\e[38;5;142m\]'   # Gruvbox Material green
    export PROMPT_COLOR_ERROR='\[\e[38;5;167m\]'     # Gruvbox Material red
    export PROMPT_COLOR_RESET='\[\e[0m\]'
elif [[ -n "$ZSH_VERSION" ]]; then
    # Zsh prompt colors
    export PROMPT_COLOR_USER='%F{108}'      # Gruvbox Material aqua
    export PROMPT_COLOR_HOST='%F{214}'      # Gruvbox Material yellow
    export PROMPT_COLOR_PATH='%F{108}'      # Gruvbox Material aqua
    export PROMPT_COLOR_GIT_CLEAN='%F{142}' # Gruvbox Material green
    export PROMPT_COLOR_GIT_DIRTY='%F{167}' # Gruvbox Material red
    export PROMPT_COLOR_SUCCESS='%F{142}'   # Gruvbox Material green
    export PROMPT_COLOR_ERROR='%F{167}'     # Gruvbox Material red
    export PROMPT_COLOR_RESET='%f'
fi