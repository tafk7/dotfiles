#!/bin/bash

# Vim-related aliases and functions

# Quick vim mode switching
alias vim-minimal='$DOTFILES_DIR/scripts/vim-config-switcher.sh minimal'
alias vim-full='$DOTFILES_DIR/scripts/vim-config-switcher.sh full'
alias vim-mode='$DOTFILES_DIR/scripts/vim-config-switcher.sh'

# Quick edit common files
alias vimrc='vim ~/.config/nvim/init.vim'
alias vimconfig='vim ~/.config/nvim/init.vim'

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
            nvim -u "$DOTFILES_DIR/configs/init.vim.full" "$@"
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

# Benchmark vim startup time
vim-bench() {
    local config="${1:-current}"
    local count="${2:-10}"
    
    echo "Benchmarking vim startup time ($count runs)..."
    
    case "$config" in
        current)
            hyperfine --warmup 3 --runs "$count" 'nvim --headless +quit'
            ;;
        minimal)
            hyperfine --warmup 3 --runs "$count" "nvim --headless -u $DOTFILES_DIR/configs/init.vim.minimal +quit"
            ;;
        full)
            hyperfine --warmup 3 --runs "$count" "nvim --headless -u $DOTFILES_DIR/configs/init.vim.full +quit"
            ;;
        *)
            echo "Usage: vim-bench [current|minimal|full] [run_count]"
            return 1
            ;;
    esac
}