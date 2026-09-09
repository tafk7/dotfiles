#!/bin/bash
# agent-shell — guard the shell surface that coding agents actually pay for.
#
# Coding harnesses (Claude Code, Codex, opencode, …) do NOT use your interactive
# profile. They run commands as `bash -lc`, and/or snapshot a non-interactive
# login shell once and source that snapshot on every tool call. So the cost that
# matters is whatever a NON-INTERACTIVE shell drags in.
#
# The failure mode this catches: something (a distro package dropping a file in
# /etc/profile.d, or a careless edit to the non-interactive branch of
# entry/bash.sh) starts defining functions or aliases in that shell. Claude Code
# re-encodes every captured function into its snapshot as
#   eval "$(echo '<base64>' | base64 -d)"
# — a subshell plus an exec PER FUNCTION, paid on every single tool call. Six
# trivial gawk helpers from /etc/profile.d/gawk.sh once cost 30ms of a 40ms
# call (26 clone+execve syscalls, vs 2 without them).
#
# Assertions here are structural, not wall-clock: this box forks in ~1.8ms,
# several times slower than a typical laptop, so any hard millisecond budget
# would be meaningless here or flaky elsewhere. Timings are printed for humans.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
fail() { printf 'FAIL: %s\n' "$*" >&2; failures=$((failures + 1)); }

# These assertions describe the REAL login chain, so they only mean anything
# when this repo is the one actually installed at ~/.bashrc.
if [[ ! -e "$HOME/.bashrc" ]] || [[ "$(readlink -f "$HOME/.bashrc")" != "$ROOT/entry/bash.sh" ]]; then
    printf 'agent-shell: skipped (~/.bashrc does not resolve to %s/entry/bash.sh)\n' "$ROOT"
    exit 0
fi

# ---------------------------------------------------------------------------
# Structural invariants
# ---------------------------------------------------------------------------

# 1. No functions leak into the agent-visible shell.
leaked_fns="$(bash -lc 'declare -F' 2>/dev/null)"
if [[ -n "$leaked_fns" ]]; then
    fail "non-interactive login shell defines functions (every one is re-encoded into each harness snapshot and paid per tool call):
$(printf '%s\n' "$leaked_fns" | sed 's/^/    /')
  Fix: they should be swept by the non-interactive branch of entry/bash.sh."
fi

# 2. No aliases either.
leaked_aliases="$(bash -lc 'alias' 2>/dev/null)"
if [[ -n "$leaked_aliases" ]]; then
    fail "non-interactive login shell defines aliases:
$(printf '%s\n' "$leaked_aliases" | sed 's/^/    /')"
fi

# 3. BASH_ENV must stay unset. Setting it makes even a bare `bash -c` source a
#    file, which taxes every tool call of every harness — including the many
#    that never read a login shell at all.
bash_env="$(bash -lc 'printf %s "${BASH_ENV:-}"' 2>/dev/null)"
[[ -z "$bash_env" ]] || fail "BASH_ENV is set to '$bash_env' in a login shell; this makes every \`bash -c\` source a file"

# 4. PATH stays deduped and free of empty entries (an empty entry means CWD).
agent_path="$(bash -lc 'printf %s "$PATH"' 2>/dev/null)"
# printf '%s\n' (not '%s') on both sides: sort appends a trailing newline, so
# counting one side without it undercounts by one and reports phantom dupes.
path_lines() { printf '%s\n' "$agent_path" | tr ':' '\n'; }
total="$(path_lines | wc -l)"
unique="$(path_lines | sort -u | wc -l)"
[[ "$total" == "$unique" ]] || fail "PATH has duplicates in the agent shell ($total entries, $unique unique) — see _dotfiles_dedupe_path in shell/env-runtime.sh"
if path_lines | grep -qx ''; then
    fail "PATH contains an empty entry (means 'current directory') in the agent shell"
fi

# 5. Negative control: the sweep must be scoped to non-interactive shells only.
#    If this ever reads 0, the sweep has escaped into interactive shells and
#    silently deleted your tooling.
interactive_fns="$(bash -ic 'declare -F | wc -l' 2>/dev/null | tr -d '[:space:]')"
if [[ -z "$interactive_fns" || "$interactive_fns" -lt 1 ]]; then
    fail "interactive bash defines no functions — the non-interactive sweep has leaked into interactive shells"
fi

# ---------------------------------------------------------------------------
# Informational timings (never assertions — see header)
# ---------------------------------------------------------------------------

if [[ "${AGENT_SHELL_TIMINGS:-1}" == "1" ]] && command -v /usr/bin/time >/dev/null 2>&1; then
    t() { /usr/bin/time -f %e "$@" 2>&1 >/dev/null | tail -1; }
    printf 'agent-shell timings (informational):\n'
    printf '  %-38s %ss\n' 'bash -c   (no rc; nested/scripts)'  "$(t bash -c exit)"
    printf '  %-38s %ss\n' 'bash -lc  (login; Codex per call)'  "$(t bash -lc exit)"
    printf '  %-38s %s\n'  'functions in agent shell'           "$(bash -lc 'declare -F | wc -l' 2>/dev/null)"
    printf '  %-38s %s\n'  'PATH entries in agent shell'        "$total"
fi

if (( failures )); then
    printf 'agent-shell: %d failure(s)\n' "$failures" >&2
    exit 1
fi
printf 'agent-shell: ok\n'
