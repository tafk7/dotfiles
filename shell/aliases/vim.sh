#!/bin/bash

# Vim-related aliases and functions

# Quick vim mode switching
alias vim-minimal='$DOTFILES_DIR/bin/vim-config-switcher minimal'
alias vim-full='$DOTFILES_DIR/bin/vim-config-switcher full'
alias vim-mode='$DOTFILES_DIR/bin/vim-config-switcher'

# Quick edit common files
alias vimrc='nvim ~/.config/nvim/init.vim'

# Show current vim mode
vim-status() {
    local mode=$(cat ~/.config/nvim/.vim-mode 2>/dev/null || echo "unknown")
    local config=$(readlink ~/.config/nvim/init.vim 2>/dev/null | xargs basename | sed 's/init.vim.//' || echo 'not set')
    echo "Vim mode: $mode"
    echo "Config file: $config"
}

# Quick plugin management
alias vplug='nvim +PlugInstall +qall'
alias vplugup='nvim +PlugUpdate +qall'
alias vplugclean='nvim +PlugClean +qall'

# Launch vim with specific config
vim-with() {
    local config="$1"
    shift
    case "$config" in
        minimal)
            nvim -u "$DOTFILES_DIR/configs/init.vim.minimal" "$@"
            ;;
        full)
            nvim -u "$DOTFILES_DIR/configs/init.vim" "$@"
            ;;
        none)
            nvim -u NONE "$@"
            ;;
        *)
            echo "Usage: vim-with [minimal|full|none] [files...]"
            return 1
            ;;
    esac
}