#!/bin/bash
# Always-fresh exports — safe to re-source on every shell start and on `reload`.
#
# Two categories live here:
#   1. PATH normalization shared by login and interactive startup.
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

# ==============================================================================
# PATH hygiene
# ==============================================================================
#
# Defined here (un-guarded, sourced by entry/profile.sh for every bash/zsh shell
# and again by shell/init.sh) so the interactive and agent paths share one
# implementation. Two callers, because duplicates get introduced at two points:
#   - entry/profile.sh, right after env.sh: catches /etc/profile.d scripts that
#     append unconditionally. /etc/profile.d/rocm.sh re-adds three /opt/rocm
#     dirs on EVERY login shell, so `bash -lc` — the shape coding agents run
#     per tool call — accumulated them without this.
#   - shell/init.sh, after ~/.shell.local: catches vendor scripts you source
#     yourself (Xilinx settings64.sh), which must be deduped after they run.
#
# Keeps first occurrence, so precedence is unchanged. Empty entries are dropped:
# an empty PATH element means "current directory".
#
# Splits with each shell's native mechanism. Walking the string by hand
# (`${rest%%:*}` / `${rest#*:}` in a loop) is O(n^2) over a 16KB value and
# measured ~680ms per call here — far worse than the duplication it fixes.
_dotfiles_dedupe_path() {
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        # zsh ties $path to $PATH; -U makes it unique-on-assignment, so this
        # both dedupes now and prevents re-duplication for the rest of the
        # session. -U keeps one empty element if present, hence the :# strip.
        # shellcheck disable=SC2296,SC2298  # zsh typeset/array syntax
        typeset -gU path PATH
        # shellcheck disable=SC2296,SC2298
        path=("${(@)path:#}")
        return 0
    fi
    local -a parts=()
    local entry out="" had_noglob=0
    local -A seen=()
    local IFS=:
    # Word-split on IFS with globbing off: no forks, no herestring temp file.
    # Without `set -f`, a PATH entry containing * or ? would expand.
    [[ $- == *f* ]] && had_noglob=1
    set -f
    # shellcheck disable=SC2206  # deliberate IFS word split, globbing off
    parts=($PATH)
    (( had_noglob )) || set +f
    for entry in "${parts[@]}"; do
        [[ -z "$entry" ]] && continue
        [[ -n "${seen[$entry]:-}" ]] && continue
        seen[$entry]=1
        out="${out:+$out:}$entry"
    done
    [[ -n "$out" ]] && export PATH="$out"
    return 0
}

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
