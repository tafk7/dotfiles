#!/bin/bash
# Vim/Neovim — aliases and functions

# Neovim as default editor with escape hatches
if command -v nvim >/dev/null 2>&1; then
    alias vim='nvim'  # Neovim
    alias vi='nvim'   # Neovim
    command -v vim >/dev/null 2>&1 && alias vimvim='command vim'  # The real vim, not nvim
    command -v vi >/dev/null 2>&1 && alias vivim='command vi'     # The real vi, not nvim
fi

# Quick edit common files
alias vimrc='nvim "${XDG_CONFIG_HOME:-$HOME/.config}/nvim/init.vim"'  # Edit neovim config

# Quick plugin management
alias vplug='nvim +PlugInstall +qall'     # Install vim plugins
alias vplugup='nvim +PlugUpdate +qall'    # Update vim plugins
alias vplugclean='nvim +PlugClean +qall'  # Remove vim plugins no longer declared

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
