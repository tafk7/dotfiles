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

# Double-source guard. Deliberately NOT exported: a child shell must re-enter
# this file so Layer 2's env-runtime.sh can re-run `direnv export` for its own
# CWD. Layer 1 carries its own exported guard instead (see below).
[ -n "$_PROFILE_LOADED" ] && return 0
_PROFILE_LOADED=1

# Layer 1: POSIX baseline (works in dash, sh, ash, bash, zsh)
#
# Guarded by an EXPORTED flag because everything here is write-once and
# inheritable — a child shell already has LANG/XDG_*/TERM/PAGER/LESS in its
# environment, so recomputing them is pure waste. That waste is not theoretical:
# coding agents run `bash -lc` per tool call (Codex) and this block, dominated
# by the `locale -a` fork, cost ~10ms of every one. Mirrors the exported
# _DOTFILES_ENV_LOADED guard in shell/env.sh.
#
# Set _DOTFILES_BASE_ENV= (empty) to force a recompute in a child shell.
if [ -z "${_DOTFILES_BASE_ENV:-}" ]; then
# Only claim a UTF-8 locale that's actually generated. On a managed box where the
# bash tier can't sudo locale-gen, forcing LANG to a missing locale makes every
# tool spew `setlocale: LC_*: cannot change locale` warnings. Prefer en_US.UTF-8,
# fall back to C.UTF-8 (always UTF-8, no region), else leave LANG as the OS set it
# — a working, if non-UTF-8, default. `locale -a` is POSIX; guard on availability
# so this stays dash-safe on minimal systems.
# Matched with `case` rather than `printf | grep -qiE`, which forked a pipeline
# (two processes) per candidate to search ~250 bytes. The bracket expressions
# reproduce grep -i exactly; the `-?` in the old regex becomes the two branches.
# Locale names never contain whitespace, so word-splitting the list is safe.
# Still POSIX — this file must stay dash-safe.
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

    export _DOTFILES_BASE_ENV=1
fi

# Layer 2: bash/zsh get the rich environment (env.sh uses [[ extensively)
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

    # Dedupe here as well as in shell/init.sh. This is the only dedup the agent
    # path gets: /etc/profile.d/rocm.sh appends three /opt/rocm dirs on every
    # login shell whether or not they are already present, so `bash -lc` — the
    # shape coding agents run per tool call — grew its PATH on every nesting.
    # Defined in shell/env-runtime.sh above.
    command -v _dotfiles_dedupe_path >/dev/null 2>&1 && _dotfiles_dedupe_path
fi
