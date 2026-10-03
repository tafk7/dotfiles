#!/bin/bash
# General aliases — modern CLI tools and productivity

# Modern CLI tool aliases
if command -v eza >/dev/null 2>&1; then
    alias ll='eza -l --color=auto --group-directories-first --time-style=long-iso'
    alias la='eza -la --color=auto --group-directories-first --time-style=long-iso'
    alias l='eza -CF --color=auto --group-directories-first'
    alias tree='eza --tree --color=auto --group-directories-first'
else
    alias ll='ls -alF --color=auto'
    alias la='ls -A --color=auto'
    alias l='ls -CF --color=auto'
    command -v tree >/dev/null 2>&1 && alias tree='tree -C'
fi

alias ls='ls --color=auto'

# File viewer
command -v bat &>/dev/null && alias view='bat'

# Directory navigation
alias ..='cd ..'
alias ...='cd ../..'
alias -- -='cd -'

# Grep with color
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# System information
alias df='df -h'
alias du='du -h'
alias free='free -h'

# Network
alias ports='ss -tulanp'
myip() {
    curl --fail --silent --show-error --max-time 10 --proto '=https' \
        https://ifconfig.me/ip
    printf '\n'
}
alias localip='hostname -I'

# File viewing and editing
alias nano='nano -w'
alias less='less -R'

# Print canonical paths. With no arguments, resolve the current directory;
# otherwise resolve every supplied path.
p() {
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
alias killall='killall -v'

# Disk usage
alias du1='du -h --max-depth=1'
alias ducks='du -cks * | sort -rn | head'

# History
alias h='history'
alias hgrep='history | grep'

# Disable terminal mouse-reporting modes that may be left enabled when an SSH
# connection or mouse-aware TUI exits without cleaning up. Safe to run manually
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

# Reload shell config, unsetting the guards so env.sh and profile.sh re-run.
# Removed aliases/functions persist; use `exec $SHELL -l` for a clean slate.
reload() {
    unset _DOTFILES_ENV_LOADED _PROFILE_LOADED
    if [[ -n "$ZSH_VERSION" ]]; then
        source ~/.zshrc
    else
        source ~/.bashrc
    fi
}

if [[ -n "$ZSH_VERSION" ]]; then
    alias zshrc='nvim ~/.zshrc'
elif [[ -n "$BASH_VERSION" ]]; then
    alias bashrc='nvim ~/.bashrc'
fi

# Theme management
alias theme='$DOTFILES_DIR/bin/theme-switcher'
alias themes='$DOTFILES_DIR/bin/theme-switcher --list'

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
alias fr='$DOTFILES_DIR/bin/replace'

# Cheatsheet for keybindings
alias cheat='$DOTFILES_DIR/bin/cheatsheet'

# direnv shortcuts
if command -v direnv >/dev/null 2>&1; then
    alias da='direnv allow'
    alias de='${EDITOR:-nvim} .envrc'
fi

# btop as top replacement
command -v btop >/dev/null 2>&1 && alias top='btop'
