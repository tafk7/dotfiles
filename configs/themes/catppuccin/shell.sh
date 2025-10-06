#!/bin/bash
# Catppuccin Mocha theme for shell (FZF and prompt colors)

# FZF Catppuccin Mocha colors
export FZF_DEFAULT_OPTS='
    --height 40% --layout=reverse --border --inline-info
    --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#45475a
    --color=fg:#cdd6f4,header:#45475a,info:#89b4fa,pointer:#f5e0dc
    --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#89b4fa,hl+:#89b4fa
    --preview-window=right:50%:wrap'

# Shell colors for prompts (bash/zsh compatible)
if [[ -n "$BASH_VERSION" ]]; then
    # Bash prompt colors
    export PROMPT_COLOR_USER='\[\e[38;5;147m\]'      # Catppuccin blue
    export PROMPT_COLOR_HOST='\[\e[38;5;223m\]'      # Catppuccin peach
    export PROMPT_COLOR_PATH='\[\e[38;5;147m\]'      # Catppuccin blue
    export PROMPT_COLOR_GIT_CLEAN='\[\e[38;5;151m\]' # Catppuccin green
    export PROMPT_COLOR_GIT_DIRTY='\[\e[38;5;210m\]' # Catppuccin red
    export PROMPT_COLOR_SUCCESS='\[\e[38;5;151m\]'   # Catppuccin green
    export PROMPT_COLOR_ERROR='\[\e[38;5;210m\]'     # Catppuccin red
    export PROMPT_COLOR_RESET='\[\e[0m\]'
elif [[ -n "$ZSH_VERSION" ]]; then
    # Zsh prompt colors
    export PROMPT_COLOR_USER='%F{147}'      # Catppuccin blue
    export PROMPT_COLOR_HOST='%F{223}'      # Catppuccin peach
    export PROMPT_COLOR_PATH='%F{147}'      # Catppuccin blue
    export PROMPT_COLOR_GIT_CLEAN='%F{151}' # Catppuccin green
    export PROMPT_COLOR_GIT_DIRTY='%F{210}' # Catppuccin red
    export PROMPT_COLOR_SUCCESS='%F{151}'   # Catppuccin green
    export PROMPT_COLOR_ERROR='%F{210}'     # Catppuccin red
    export PROMPT_COLOR_RESET='%f'
fi