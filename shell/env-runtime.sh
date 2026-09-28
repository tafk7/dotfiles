#!/bin/bash
# Always-fresh exports, re-run on every shell start and on `reload`.
#
# Holds PATH dedup and CWD-sensitive direnv activation. These must run in every
# subprocess, and shell/env.sh is skipped by child shells through its exported
# guard, so they can't live there. Static exports belong in shell/env.sh.
#
# Sourced immediately before env.sh by entry/profile.sh (login and
# non-interactive bash/zsh) and shell/init.sh (interactive shells).

# ==============================================================================
# PATH hygiene
# ==============================================================================
#
# Called from two places, because duplicates enter at two points:
#   - entry/profile.sh: /etc/profile.d scripts that append unconditionally,
#     which would grow PATH in every nested `bash -lc` an agent runs.
#   - shell/init.sh, after ~/.shell.local: vendor scripts sourced there.
#
# Keeps the first occurrence, so precedence is unchanged. Empty entries are
# dropped, since an empty PATH element means "current directory". Splits with
# each shell's native mechanism; walking the string by hand is O(n^2) and very
# slow on long PATHs.
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
# `direnv hook` only fires before interactive prompts, so non-interactive
# subprocesses (`zsh -c` via ~/.zshenv) use `direnv export`, which applies the
# allowed .envrc for $PWD immediately. Interactive shells also get the hook from
# tool-init.sh for mid-session `cd`. `|| true` keeps a failing .envrc from
# aborting startup under `set -e`. Each shell needs its own export syntax; the
# wrong one leaks malformed quoting into the parent.
#
# Plain `bash -c` reads no startup files, so it inherits its parent's
# environment instead of activating .envrc. BASH_ENV=~/.bashrc would change
# that, but is deliberately not set.
if command -v direnv >/dev/null 2>&1; then
    export DIRENV_LOG_FORMAT=""
    if [[ -n "${ZSH_VERSION:-}" ]]; then
        eval "$(direnv export zsh 2>/dev/null)" || true
    else
        eval "$(direnv export bash 2>/dev/null)" || true
    fi
fi
