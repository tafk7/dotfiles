# shellcheck shell=sh
# ~/.profile: login baseline. Must stay POSIX: dash/sh read it too.
#
# Part 1 (all shells):    locale, XDG, TERM, PAGER.
# Part 2 (bash/zsh only): shell/env-runtime.sh and shell/env.sh.
#
# Never sources bashrc/zshrc; ~/.bash_profile and zsh's own startup do that.

# Not exported: a child shell must re-enter this file so env-runtime.sh can
# re-run `direnv export` for its own CWD. Part 1 has its own exported guard.
[ -n "$_PROFILE_LOADED" ] && return 0
_PROFILE_LOADED=1

# Part 1: POSIX baseline. Guarded by an exported flag because these values are
# inherited, and agents start a login shell per tool call; the `locale -a` fork
# would otherwise run in every one. Set _DOTFILES_BASE_ENV= to force a recompute.
if [ -z "${_DOTFILES_BASE_ENV:-}" ]; then
# Only claim a UTF-8 locale that is actually generated; without sudo for
# locale-gen, a missing locale makes every tool warn. Prefer en_US.UTF-8, then
# C.UTF-8, else leave LANG alone. `case` avoids forking grep per candidate.
    if command -v locale >/dev/null 2>&1; then
        _lang=""
        for _l in $(locale -a 2>/dev/null); do
            case "$_l" in
                en_US.[uU][tT][fF]8|en_US.[uU][tT][fF]-8)
                    _lang=en_US.UTF-8
                    break
                    ;;
                C.[uU][tT][fF]8|C.[uU][tT][fF]-8)
                    # Keep looking — en_US wins if it shows up later in the list.
                    [ -z "$_lang" ] && _lang=C.UTF-8
                    ;;
            esac
        done
        if [ "$_lang" = "en_US.UTF-8" ]; then
            export LANG=en_US.UTF-8
            export LANGUAGE=en_US.UTF-8
        elif [ -n "$_lang" ]; then
            export LANG="$_lang"
        fi
        unset _lang _l
    fi
    # LC_ALL and TZ are deliberately not set: LC_ALL would override every
    # category for child processes, and the OS timezone should apply.

    export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
    export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
    export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
    export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"

    export TERM="${TERM:-xterm-256color}"
    export PAGER=less
    export LESS='-F -g -i -M -R -S -w -X -z-4'

    export _DOTFILES_BASE_ENV=1
fi

# Part 2: bash/zsh only (env.sh is not POSIX).
if [ -n "${BASH_VERSION:-}" ] || [ -n "${ZSH_VERSION:-}" ]; then
    if [ -z "${DOTFILES_DIR:-}" ]; then
        _dotfiles_path_file="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/install-path"
        if [ -r "$_dotfiles_path_file" ]; then
            IFS= read -r DOTFILES_DIR < "$_dotfiles_path_file"
        else
            DOTFILES_DIR="$HOME/dev/dotfiles"
        fi
        export DOTFILES_DIR
        unset _dotfiles_path_file
    fi
    [ -f "$DOTFILES_DIR/shell/env-runtime.sh" ] && . "$DOTFILES_DIR/shell/env-runtime.sh"
    [ -f "$DOTFILES_DIR/shell/env.sh" ] && . "$DOTFILES_DIR/shell/env.sh"

    # The only dedup non-interactive agent shells get; /etc/profile.d scripts
    # can append on every login shell.
    command -v _dotfiles_dedupe_path >/dev/null 2>&1 && _dotfiles_dedupe_path
fi
