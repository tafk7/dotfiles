# ~/.profile: login shell baseline — locale, XDG, terminal.
# Does NOT source bashrc/zshrc — that's the terminal's job.
# Login bash gets bashrc via ~/.bash_profile; login zsh gets zshrc via ~/.zprofile.
#
# PATH composition lives in shell/env.sh (single source of truth).
# This file sources it, then adds login-only settings.

# Double-source guard
[[ -n "$_PROFILE_LOADED" ]] && return
_PROFILE_LOADED=1

# PATH and static exports (single source of truth)
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
[[ -f "$DOTFILES_DIR/shell/env.sh" ]] && source "$DOTFILES_DIR/shell/env.sh"

# Locale
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
[ -z "$TZ" ] && export TZ="UTC"

# XDG directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

# Terminal (don't override TERM if already set — tmux sets tmux-256color)
export TERM="${TERM:-xterm-256color}"
export PAGER=less
export LESS='-F -g -i -M -R -S -w -X -z-4'
