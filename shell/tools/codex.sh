#!/bin/bash

# Codex: whatever `codex` is on PATH. The wrapper applies optional launch
# defaults; an explicit profile argument takes precedence. The VS Code
# extension's bundled binary is deliberately not discovered; finding it cost a
# filesystem scan at every shell start.

# Drop our own wrapper on re-source so `command -v` finds the PATH binary.
# `type -P` would be bash-only.
unset -f codex 2>/dev/null

# A bare `command -v` condition doesn't fork; capturing its output would.
if command -v codex >/dev/null 2>&1; then
    codex() {
        local -a flags=() defaults=()
        local arg explicit_profile=0 default_profile=0 skip=0 raw_flags="${CODEX_FLAGS:-}"
        # Defaults use whitespace-separated words, without shell evaluation.
        if [[ -n "${ZSH_VERSION:-}" ]]; then
            # shellcheck disable=SC2296,SC2206
            flags=( ${=raw_flags} )
        else
            read -r -a flags <<< "$raw_flags"
        fi
        for arg in "$@"; do
            case "$arg" in
                --) break ;;
                -p|--profile|-p?*|--profile=*) explicit_profile=1; break ;;
            esac
        done
        for arg in "${flags[@]}"; do
            if (( skip )); then skip=0; continue; fi
            case "$arg" in
                -p|--profile)
                    if (( explicit_profile )); then skip=1; continue; fi
                    default_profile=1 ;;
                -p?*|--profile=*)
                    if (( explicit_profile )); then continue; fi
                    default_profile=1 ;;
            esac
            defaults+=("$arg")
        done
        if (( !explicit_profile && !default_profile )) && [[ -n "${CODEX_DEFAULT_PROFILE:-}" ]]; then
            defaults+=(--profile "$CODEX_DEFAULT_PROFILE")
        fi
        command codex "${defaults[@]}" "$@"
    }
else
    codex() {
        echo "Codex CLI not found. Install with: ./setup.sh --ai" >&2
        return 1
    }
fi

# Codex CLI shortcuts
alias cx='codex'                       # New session
alias cxr='codex resume'               # Resume (picker)
alias cxc='codex resume --last'        # Continue last session
alias cxp='codex exec'                 # One-off prompt (non-interactive)

# Codex with alternate config dir at ~/.codex-alt (CODEX_HOME override)
alias cxh='CODEX_HOME="$HOME/.codex-alt" codex'
alias cxhr='CODEX_HOME="$HOME/.codex-alt" codex resume'
alias cxhc='CODEX_HOME="$HOME/.codex-alt" codex resume --last'
alias cxhp='CODEX_HOME="$HOME/.codex-alt" codex exec'
