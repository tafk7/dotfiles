#!/bin/bash
# Tokyo Night theme for shell (FZF and prompt colors)

# FZF Tokyo Night colors
export FZF_DEFAULT_OPTS='
    --height 40% --layout=reverse --border --inline-info
    --color=bg+:#292e42,bg:#1a1b26,spinner:#f7768e,hl:#3b4261
    --color=fg:#a9b1d6,header:#3b4261,info:#7aa2f7,pointer:#f7768e
    --color=marker:#f7768e,fg+:#c0caf5,prompt:#7aa2f7,hl+:#7aa2f7
    --preview-window=right:50%:wrap'

# Shell colors for prompts (bash/zsh compatible)
if [[ -n "$BASH_VERSION" ]]; then
    # Bash prompt colors
    export PROMPT_COLOR_USER='\[\e[38;5;111m\]'      # Tokyo Night blue
    export PROMPT_COLOR_HOST='\[\e[38;5;221m\]'      # Tokyo Night yellow
    export PROMPT_COLOR_PATH='\[\e[38;5;111m\]'      # Tokyo Night blue
    export PROMPT_COLOR_GIT_CLEAN='\[\e[38;5;150m\]' # Tokyo Night green
    export PROMPT_COLOR_GIT_DIRTY='\[\e[38;5;210m\]' # Tokyo Night red
    export PROMPT_COLOR_SUCCESS='\[\e[38;5;150m\]'   # Tokyo Night green
    export PROMPT_COLOR_ERROR='\[\e[38;5;210m\]'     # Tokyo Night red
    export PROMPT_COLOR_RESET='\[\e[0m\]'
elif [[ -n "$ZSH_VERSION" ]]; then
    # Zsh prompt colors
    export PROMPT_COLOR_USER='%F{111}'      # Tokyo Night blue
    export PROMPT_COLOR_HOST='%F{221}'      # Tokyo Night yellow
    export PROMPT_COLOR_PATH='%F{111}'      # Tokyo Night blue
    export PROMPT_COLOR_GIT_CLEAN='%F{150}' # Tokyo Night green
    export PROMPT_COLOR_GIT_DIRTY='%F{210}' # Tokyo Night red
    export PROMPT_COLOR_SUCCESS='%F{150}'   # Tokyo Night green
    export PROMPT_COLOR_ERROR='%F{210}'     # Tokyo Night red
    export PROMPT_COLOR_RESET='%f'
fi