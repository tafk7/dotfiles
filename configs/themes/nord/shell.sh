#!/bin/bash
# Nord theme for shell (FZF and prompt colors)

# FZF Nord colors
export FZF_DEFAULT_OPTS='
    --height 40% --layout=reverse --border --inline-info
    --color=bg+:#3B4252,bg:#2E3440,spinner:#81A1C1,hl:#616E88
    --color=fg:#D8DEE9,header:#616E88,info:#88C0D0,pointer:#81A1C1
    --color=marker:#81A1C1,fg+:#D8DEE9,prompt:#81A1C1,hl+:#81A1C1
    --preview-window=right:50%:wrap'

# Shell colors for prompts (bash/zsh compatible)
if [[ -n "$BASH_VERSION" ]]; then
    # Bash prompt colors
    export PROMPT_COLOR_USER='\[\e[38;5;109m\]'      # Nord blue
    export PROMPT_COLOR_HOST='\[\e[38;5;143m\]'      # Nord yellow
    export PROMPT_COLOR_PATH='\[\e[38;5;109m\]'      # Nord blue
    export PROMPT_COLOR_GIT_CLEAN='\[\e[38;5;114m\]' # Nord green
    export PROMPT_COLOR_GIT_DIRTY='\[\e[38;5;167m\]' # Nord red
    export PROMPT_COLOR_SUCCESS='\[\e[38;5;114m\]'   # Nord green
    export PROMPT_COLOR_ERROR='\[\e[38;5;167m\]'     # Nord red
    export PROMPT_COLOR_RESET='\[\e[0m\]'
elif [[ -n "$ZSH_VERSION" ]]; then
    # Zsh prompt colors
    export PROMPT_COLOR_USER='%F{109}'      # Nord blue
    export PROMPT_COLOR_HOST='%F{143}'      # Nord yellow
    export PROMPT_COLOR_PATH='%F{109}'      # Nord blue
    export PROMPT_COLOR_GIT_CLEAN='%F{114}' # Nord green
    export PROMPT_COLOR_GIT_DIRTY='%F{167}' # Nord red
    export PROMPT_COLOR_SUCCESS='%F{114}'   # Nord green
    export PROMPT_COLOR_ERROR='%F{167}'     # Nord red
    export PROMPT_COLOR_RESET='%f'
fi