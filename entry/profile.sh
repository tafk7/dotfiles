# shellcheck shell=sh
# ~/.profile: login shell baseline — POSIX-clean.
# Sourced by every login shell, including dash/sh on minimal systems.
#
# Layer 1 (always):       locale, XDG, TERM, PAGER. Pure POSIX.
# Layer 2 (bash/zsh only): source shell/env.sh for full PATH + direnv.
# Dash/sh users get a working — if minimal — login without crashing on
# bash-only constructs ([[, source, arrays, etc.).
#
# Does NOT source bashrc/zshrc — that's the terminal's job.
# Login bash gets bashrc via ~/.bash_profile; login zsh gets zshrc via ~/.zprofile.

# Double-source guard
[ -n "$_PROFILE_LOADED" ] && return 0
_PROFILE_LOADED=1

# Layer 1: POSIX baseline (works in dash, sh, ash, bash, zsh)
export LANG=en_US.UTF-8
export LANGUAGE=en_US.UTF-8
# LC_ALL is intentionally NOT set — it's a temporary override that forces every
# locale category and prevents tools/child shells from selecting their own.
# LANG provides the default; set per-category LC_* vars if you need finer control.
# TZ is intentionally NOT forced — the OS timezone applies. Set TZ in
# ~/.shell.local (or configure the OS) if you want a fixed zone such as UTC.

export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

export TERM="${TERM:-xterm-256color}"
export PAGER=less
export LESS='-F -g -i -M -R -S -w -X -z-4'

# Layer 2: bash/zsh get the rich environment (env.sh uses [[ extensively)
if [ -n "${BASH_VERSION:-}" ] || [ -n "${ZSH_VERSION:-}" ]; then
    DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"
    [ -f "$DOTFILES_DIR/shell/env-runtime.sh" ] && . "$DOTFILES_DIR/shell/env-runtime.sh"
    [ -f "$DOTFILES_DIR/shell/env.sh" ] && . "$DOTFILES_DIR/shell/env.sh"
fi
