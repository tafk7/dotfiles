#!/bin/bash
# Vim/Neovim — aliases and functions

# Neovim as default editor with escape hatches
if command -v nvim >/dev/null 2>&1; then
    alias vim='nvim'
    alias vi='nvim'
    command -v vim >/dev/null 2>&1 && alias vimvim='command vim'
    command -v vi >/dev/null 2>&1 && alias vivim='command vi'
fi

# Quick edit common files
alias vimrc='nvim ~/.config/nvim/init.vim'

# Quick plugin management
alias vplug='nvim +PlugInstall +qall'
alias vplugup='nvim +PlugUpdate +qall'
alias vplugclean='nvim +PlugClean +qall'

# Launch vim with specific config
vim-with() {
    local config="$1"
    shift
    case "$config" in
        full)
            nvim -u "$DOTFILES_DIR/configs/init.vim" "$@"
            ;;
        none)
            nvim -u NONE "$@"
            ;;
        *)
            echo "Usage: vim-with [full|none] [files...]"
            return 1
            ;;
    esac
}
