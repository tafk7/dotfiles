#!/bin/bash
# Always-fresh exports — safe to re-source on every shell start and on `reload`.
#
# Two categories live here:
#   1. Generated/ artifacts (STARSHIP_CONFIG, BAT_CACHE_PATH,
#      theme-overrides) that may be created or rewritten AFTER the
#      first source of env.sh (e.g., by theme-switcher). `reload` needs
#      to re-evaluate them so the shell picks up new generated paths
#      instead of cached-empty values.
#   2. CWD-sensitive exports (direnv .envrc activation) that must
#      re-fire in every subprocess. The exported guard on env.sh causes
#      child shells to skip env.sh's body entirely, so direnv has to
#      live outside that guard or non-interactive subprocesses
#      (e.g., `zsh -c "cmd"` from a project directory) wouldn't get
#      their .envrc activated.
#
# Static, write-once exports (PATH, EDITOR, language settings) live in
# shell/env.sh, which IS guarded by the exported _DOTFILES_ENV_LOADED.
#
# Sourced by:
#   - entry/profile.sh   (login + non-interactive bash & zsh)
#   - shell/init.sh      (interactive shells)
# Always immediately before env.sh.

if [[ -n "${DOTFILES_DIR:-}" ]]; then
    if [[ -f "$DOTFILES_DIR/generated/starship.toml" ]]; then
        export STARSHIP_CONFIG="$DOTFILES_DIR/generated/starship.toml"
    elif [[ -f "$DOTFILES_DIR/configs/starship.toml" ]] \
         && ! grep -q '__DOTFILES_PALETTE__' "$DOTFILES_DIR/configs/starship.toml" 2>/dev/null; then
        # Only fall back to the base config if it doesn't contain the
        # placeholder marker (would otherwise cause starship warnings).
        export STARSHIP_CONFIG="$DOTFILES_DIR/configs/starship.toml"
    fi

    if [[ -d "$DOTFILES_DIR/generated/bat/cache" ]]; then
        export BAT_CACHE_PATH="$DOTFILES_DIR/generated/bat/cache"
    fi

    # Per-component theme overrides — sourced after generated/theme.sh emits
    # the global DOTFILES_THEME, so DOTFILES_THEME_<GROUP|SURFACE>=... overrides
    # the global default. Cascade applied at apply-time by bin/theme-switcher.
    # Read by lib/theme-resolve.sh and consumed by tools (BAT_THEME etc.) that
    # generated/theme.sh emits per-surface based on the cascade.
    [[ -f "$DOTFILES_DIR/generated/theme-overrides.sh" ]] \
        && source "$DOTFILES_DIR/generated/theme-overrides.sh"
fi

# ==============================================================================
# direnv .envrc activation (every shell, including subprocesses)
# ==============================================================================
#
# `direnv hook` only fires before each interactive prompt, so non-
# interactive subprocesses (`zsh -c "cmd"` via ~/.zshenv, scripts)
# never get their project venv activated by the hook. `direnv export
# <shell>` is the standalone equivalent — walks up from $PWD, honors
# the shared allow-list, and emits the .envrc's exports immediately.
# Lives in env-runtime.sh (not env.sh) because env.sh's exported guard
# would skip it in subprocesses, defeating the purpose. Safe no-op when
# no .envrc applies. `|| true` avoids aborting startup under `set -e`
# if an .envrc errors. Quiet log format keeps tool output clean.
#
# Shell-aware: zsh and bash use different export syntax (zsh's `typeset`
# vs bash's `declare`/plain assignment); using the wrong one silently
# leaks malformed quoting into the parent shell. Detect via the version
# vars each shell sets natively. Default to bash for POSIX `sh`.
#
# Interactive shells still get the hook from tool-init.sh on top —
# that handles the `cd into another project` case mid-session.
#
# Note: bash subprocesses (`bash -c "cmd"`) do NOT read ~/.bashrc by
# default, so they don't hit this file and won't auto-activate .envrc.
# Setting BASH_ENV=~/.bashrc would close that gap symmetrically with
# zsh's ~/.zshenv, but is a deliberate behavior expansion left out of
# this refactor — flip it on in ~/.shell.local if you want it.
if command -v direnv >/dev/null 2>&1; then
    export DIRENV_LOG_FORMAT=""
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        eval "$(direnv export zsh 2>/dev/null)" || true
    else
        eval "$(direnv export bash 2>/dev/null)" || true
    fi
fi
