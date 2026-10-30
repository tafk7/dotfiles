#!/bin/bash
# General aliases — modern CLI tools and productivity

# Modern CLI tool aliases
if command -v eza >/dev/null 2>&1; then
    alias ll='eza -l --color=auto --group-directories-first --time-style=long-iso'  # Long listing with timestamps
    alias la='eza -la --color=auto --group-directories-first --time-style=long-iso'  # Long listing including hidden files
    alias l='eza -CF --color=auto --group-directories-first'  # Compact column listing
    alias tree='eza --tree --color=auto --group-directories-first'  # Recursive directory tree
else
    alias ll='ls -alF --color=auto'
    alias la='ls -A --color=auto'
    alias l='ls -CF --color=auto'
    command -v tree >/dev/null 2>&1 && alias tree='tree -C'
fi

alias ls='ls --color=auto'  # List with colors

# File viewer
command -v bat &>/dev/null && alias view='bat'  # Syntax-highlighted file viewer (bat)

# Directory navigation. `.. N` goes up N directories (default 1).
unalias .. 2>/dev/null
..() {  # Go up N directories (default 1)
    local n="${1:-1}" dir=..
    [[ "$n" =~ ^[1-9][0-9]*$ ]] || { printf 'usage: .. [N]\n' >&2; return 2; }
    while (( --n > 0 )); do dir+=/..; done
    cd -- "$dir" || return
}
alias ...='cd ../..'  # Go up two directories
alias -- -='cd -'     # Return to previous directory

# Grep with color
alias grep='grep --color=auto'    # grep in color
alias fgrep='fgrep --color=auto'  # fgrep in color
alias egrep='egrep --color=auto'  # egrep in color

# System information
alias df='df -h'      # Disk space (human readable)
alias du='du -h'      # Directory size (human readable)
alias free='free -h'  # Memory usage (human readable)

# Network
alias ports='ss -tulanp'  # List open network ports
myip() {  # Show public IP address
    curl --fail --silent --show-error --max-time 10 --proto '=https' \
        https://ifconfig.me/ip
    printf '\n'
}
alias localip='hostname -I'  # Show local network IP

# File viewing and editing
alias nano='nano -w'  # nano without hard-wrapping long lines
alias less='less -R'  # less that shows colors

# Print canonical paths. With no arguments, resolve the current directory;
# otherwise resolve every supplied path.
p() {  # Print the canonical current directory, or resolve the paths given
    if (( $# == 0 )); then
        pwd -P
    else
        realpath -- "$@"
    fi
}

# Print a command's stdout as it runs and copy the same output to the clipboard.
# Use the client clipboard from a remote tmux session when no local clipboard
# tool is available. A private temporary file lets us wait for the copy to
# finish and preserve the wrapped command's exit status in both Bash and Zsh.
yo() (
    if (( $# == 0 )); then
        printf 'Usage: yo <command> [args...]\n' >&2
        return 64
    fi

    local clipboard=() output_file command_status copy_status
    if command -v pbcopy >/dev/null 2>&1; then
        clipboard=(pbcopy)
    elif [[ -n "${TMUX:-}" && -x "${DOTFILES_DIR:-}/bin/tmux-copy" ]]; then
        clipboard=("$DOTFILES_DIR/bin/tmux-copy")
    elif [[ -n "${WAYLAND_DISPLAY:-}" ]] && command -v wl-copy >/dev/null 2>&1; then
        clipboard=(wl-copy)
    elif [[ -n "${DISPLAY:-}" ]] && command -v xclip >/dev/null 2>&1; then
        clipboard=(xclip -selection clipboard)
    else
        printf 'yo: no clipboard available (pbcopy, tmux, wl-copy, or xclip)\n' >&2
        return 127
    fi

    output_file=$(mktemp) || return 1
    trap 'rm -f -- "$output_file"' EXIT
    set -o pipefail
    if "$@" | tee "$output_file"; then
        command_status=0
    else
        command_status=$?
    fi
    if "${clipboard[@]}" < "$output_file"; then
        copy_status=0
    else
        copy_status=$?
        printf 'yo: clipboard copy failed\n' >&2
    fi
    (( command_status == 0 )) || return "$command_status"
    return "$copy_status"
)

# Process management
alias killall='killall -v'  # killall that names what it signals

# Disk usage
alias du1='du -h --max-depth=1'            # Directory size one level deep
alias ducks='du -cks * | sort -rn | head'  # Show largest items in current directory

# History
alias h='history'             # Show command history
alias hgrep='history | grep'  # Search command history

# Reset stale terminal mouse-reporting modes: an SSH connection or mouse-aware
# TUI that exits without cleaning up can leave them on. Safe to run by hand
# when pointer movement or scrolling prints escape-sequence garbage.
fixmouse() {
    printf '\033[?9l\033[?1000l\033[?1001l\033[?1002l\033[?1003l\033[?1005l\033[?1006l\033[?1007l\033[?1015l'
}

# Publish explicitly cut command-line text to the tmux server-wide buffer.
# Shell-specific line-editor widgets call this after removing their range.
_tafk_tmux_buffer_set() {
    [[ -n "${TMUX:-}" && -n "${1:-}" ]] || return 0
    printf '%s' "$1" | tmux load-buffer -
}

# Replace this shell with a fresh login shell of the same kind, in the same
# directory, so removed aliases, functions, and options are gone too. Unexported
# variables and anything defined by hand are lost; refuses while jobs exist.
# `reload --soft` re-sources the startup files in place instead: it adds and
# changes definitions but cannot remove them.
reload() {  # Restart the shell in place with fresh config (--soft re-sources instead)
    local shell_path
    case "${1:-}" in
        --soft)
            unset _DOTFILES_ENV_LOADED _DOTFILES_BASE_ENV _PROFILE_LOADED
            # Keeps this shell's load time: a soft reload cannot remove old
            # definitions, so it stays stale (shell/staleness.sh).
            _DOTFILES_SOFT_RELOAD=1
            if [[ -n "${ZSH_VERSION:-}" ]]; then
                source ~/.zshenv
                source ~/.zshrc
            else
                source ~/.bashrc
            fi
            return
            ;;
        '') ;;
        *) printf 'usage: reload [--soft]\n' >&2; return 2 ;;
    esac
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        zmodload zsh/parameter 2>/dev/null
        # shellcheck disable=SC2154  # zsh/parameter's job table
        if (( ${#jobstates} )); then
            printf 'reload: background jobs exist; finish them or use reload --soft\n' >&2
            return 1
        fi
        fc -AI 2>/dev/null
        shell_path="$(command -v zsh)"
    else
        if [[ -n "$(jobs -p)" ]]; then
            printf 'reload: background jobs exist; finish them or use reload --soft\n' >&2
            return 1
        fi
        history -a
        shell_path="$BASH"
    fi
    unset _DOTFILES_ENV_LOADED _DOTFILES_BASE_ENV _PROFILE_LOADED
    exec "$shell_path" -l
}

if [[ -n "$ZSH_VERSION" ]]; then
    alias zshrc='nvim ~/.zshrc'    # Edit ~/.zshrc
elif [[ -n "$BASH_VERSION" ]]; then
    alias bashrc='nvim ~/.bashrc'  # Edit ~/.bashrc
fi

# Theme management
alias theme='$DOTFILES_DIR/bin/theme-switcher'          # Set the global theme / interactive picker
alias themes='$DOTFILES_DIR/bin/theme-switcher --list'  # List available themes

# btop's built-in TTY theme draws with ANSI colors, which tmux maps to the
# window's theme. Launch with a copy of the user's config that selects it, so
# their own btop.conf is never rewritten.
btop() {
    local base="${XDG_CONFIG_HOME:-$HOME/.config}/btop/btop.conf"
    local config="${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/btop.conf"
    if [[ ! -f "$config" || ( -f "$base" && "$base" -nt "$config" ) ]]; then
        mkdir -p "${config%/*}" || return
        {
            [[ -f "$base" ]] && grep -Ev '^[[:space:]]*(color_theme|theme_background)[[:space:]]*=' "$base"
            printf 'color_theme = "TTY"\ntheme_background = False\n'
        } > "$config" || return
    fi
    command btop --config "$config" "$@"
}

# Find and replace utility
alias fr='$DOTFILES_DIR/bin/replace'  # Find and replace text across files

# Cheatsheet for keybindings
alias cheat='$DOTFILES_DIR/bin/cheatsheet'  # Show this interactive cheatsheet

# direnv shortcuts
if command -v direnv >/dev/null 2>&1; then
    alias da='direnv allow'            # Allow direnv in current directory
    alias de='${EDITOR:-nvim} .envrc'  # Edit .envrc for current directory
fi

# btop as top replacement
command -v btop >/dev/null 2>&1 && alias top='btop'  # System monitor (btop)
