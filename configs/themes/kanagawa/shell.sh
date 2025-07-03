#!/bin/bash
# Kanagawa theme for shell (FZF and prompt colors)

# FZF Kanagawa colors
export FZF_DEFAULT_OPTS='
    --height 40% --layout=reverse --border --inline-info
    --color=bg+:#2a2a37,bg:#1f1f28,spinner:#e82424,hl:#363646
    --color=fg:#dcd7ba,header:#363646,info:#7e9cd8,pointer:#e82424
    --color=marker:#e82424,fg+:#c8c093,prompt:#7e9cd8,hl+:#7e9cd8
    --preview-window=right:50%:wrap'

# Shell colors for prompts (bash/zsh compatible)
if [[ -n "$BASH_VERSION" ]]; then
    # Bash prompt colors
    export PROMPT_COLOR_USER='\[\e[38;5;110m\]'      # Kanagawa blue
    export PROMPT_COLOR_HOST='\[\e[38;5;179m\]'      # Kanagawa yellow
    export PROMPT_COLOR_PATH='\[\e[38;5;110m\]'      # Kanagawa blue
    export PROMPT_COLOR_GIT_CLEAN='\[\e[38;5;150m\]' # Kanagawa green
    export PROMPT_COLOR_GIT_DIRTY='\[\e[38;5;167m\]' # Kanagawa red
    export PROMPT_COLOR_SUCCESS='\[\e[38;5;150m\]'   # Kanagawa green
    export PROMPT_COLOR_ERROR='\[\e[38;5;167m\]'     # Kanagawa red
    export PROMPT_COLOR_RESET='\[\e[0m\]'
elif [[ -n "$ZSH_VERSION" ]]; then
    # Zsh prompt colors
    export PROMPT_COLOR_USER='%F{110}'      # Kanagawa blue
    export PROMPT_COLOR_HOST='%F{179}'      # Kanagawa yellow
    export PROMPT_COLOR_PATH='%F{110}'      # Kanagawa blue
    export PROMPT_COLOR_GIT_CLEAN='%F{150}' # Kanagawa green
    export PROMPT_COLOR_GIT_DIRTY='%F{167}' # Kanagawa red
    export PROMPT_COLOR_SUCCESS='%F{150}'   # Kanagawa green
    export PROMPT_COLOR_ERROR='%F{167}'     # Kanagawa red
    export PROMPT_COLOR_RESET='%f'
fi