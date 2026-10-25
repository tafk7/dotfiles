#!/bin/bash
# Outcome records: format, per-command exit precedence, convergence, display.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/harness.sh"
source "$ROOT/lib/outcomes.sh"

assert_eq "$(outcome health tmux "server" $'two\tparts\nline')" $'health\ttmux\tserver\ttwo parts line' "record fields are cleaned"
if outcome bogus s x 2>/dev/null; then fail "an invalid class was accepted"; fi

records() { local class; for class in "$@"; do outcome "$class" section "$class subject" ""; done; }
check_exit() {
    local command="$1" expected="$2"; shift 2
    assert_eq "$(records "$@" | outcome_exit "$command")" "$expected" "$command exit for: $*"
}
# verify: convergence 1, incomplete 3, health 2, else 0.
check_exit verify 0
check_exit verify 0 ok advisory
check_exit verify 2 health advisory
check_exit verify 3 health incomplete
check_exit verify 1 health incomplete convergence
# apply, update, profile: health is reported, not an exit status.
for command in apply update profile; do
    check_exit "$command" 0 health advisory
    check_exit "$command" 3 health incomplete
    check_exit "$command" 1 incomplete convergence
done
# refresh: only an incomplete check fails it.
check_exit refresh 0 convergence health
check_exit refresh 3 incomplete
if records ok | outcome_exit nonesuch 2>/dev/null; then fail "unknown command accepted"; fi

# Converged requires every check to have completed.
records ok health advisory | outcome_converged || fail "health findings blocked convergence"
if records ok incomplete | outcome_converged; then fail "an incomplete check counted as converged"; fi
if records convergence | outcome_converged; then fail "convergence work counted as converged"; fi
records | outcome_converged || fail "no checks should count as converged"

rendered="$( { outcome ok Components eza ""; outcome convergence Components bat "off its pin"; outcome health Tailscale enrollment "run: sudo tailscale up"; } | outcome_render)"
assert_eq "$rendered" $'Components\n  fix  bat: off its pin\n\nTailscale\n  warn enrollment: run: sudo tailscale up' "default render"
verbose="$( { outcome ok Components eza ""; outcome ok Configs .bashrc ""; } | outcome_render -v)"
assert_eq "$verbose" $'Components\n  ok   eza\n\nConfigs\n  ok   .bashrc' "verbose render"
assert_eq "$( { outcome ok Configs a ""; } | outcome_render)" "" "a section of passing checks is hidden"
assert_eq "$(records ok ok health incomplete | outcome_summary)" "2 ok, 0 to converge, 1 health, 1 incomplete, 0 advisory" "summary"

printf 'outcomes: ok\n'
