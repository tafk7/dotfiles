#!/bin/bash
# Test failure handling in the conditional call context used by setup.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
source "$ROOT/lib/install.sh"
mkdir -p "$HOME/.local/bin" "$TEST_ROOT/stage"
fake_command "$HOME/.local/bin/eza" true
fake_command "$TEST_ROOT/stage/eza" echo
export PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH"

record_component_outcome eza skip
[[ "$(ledger_line eza)" == $'eza\tyes\tunknown\tpresent\t'* ]] || fail "skip claimed preexisting binary"
ledger_record eza yes dotfiles installed old "$HOME/.local/bin/eza" test
record_component_outcome eza skip
[[ "$(ledger_line eza)" == $'eza\tyes\tdotfiles\tinstalled\t'* ]] || fail "skip lost recorded ownership"

# A failed replacement gets one bounded reconciliation: the old binary is still
# in place and runnable, so it is recorded, the journal goes, and a later
# replacement proceeds.
mv() {
    case "$*" in *eza.dotfiles-new*) return 73 ;; esac
    command mv "$@"
}
if atomic_replace_binary eza "$TEST_ROOT/stage/eza" "$HOME/.local/bin/eza" 2>/dev/null; then
    fail "failed replacement returned success"
fi
journal_pending && fail "resolved failure kept its journal"
"$HOME/.local/bin/eza" || fail "failed replacement damaged old binary"
[[ "$(ledger_line eza)" == $'eza\tyes\tdotfiles\tinstalled\t'* ]] || fail "resolved failure was not recorded"
unset -f mv
atomic_replace_binary eza "$TEST_ROOT/stage/eza" "$HOME/.local/bin/eza" || fail "replacement after a resolved failure"
fake_command "$TEST_ROOT/stage/eza" echo

# An artifact that does not validate keeps its journal, which blocks only its
# own component; another component's replacement proceeds.
eval "real_ledger_record() $(declare -f ledger_record | tail -n +2)"
ledger_record() { [[ "${7:-}" != *pin=* ]] || return 74; real_ledger_record "$@"; }
fake_command "$TEST_ROOT/stage/broken" false
if atomic_replace_binary eza "$TEST_ROOT/stage/broken" "$HOME/.local/bin/eza" "pin=v1 sha256=0" 2>/dev/null; then
    fail "failed ledger write returned success"
fi
eval "ledger_record() $(declare -f real_ledger_record | tail -n +2)"
journal_pending eza || fail "unresolved failure lost its journal"
if journal_begin eza "$HOME/.local/bin/eza" "$TEST_ROOT/stage/eza" "$HOME/.local/bin/eza" 2>/dev/null; then
    fail "pending journal overwritten"
fi
journal_begin bat "$HOME/.local/bin/bat" "$TEST_ROOT/stage/bat" "$HOME/.local/bin/bat" \
    || fail "an unrelated component was blocked by another's journal"
journal_clear bat
journal_pending eza || fail "clearing one journal removed another"
fake_command "$HOME/.local/bin/eza" true
journal_reconcile
journal_pending && fail "reconciled journal kept"

mkdir -p "$HOME/.local/nvim/bin" "$TEST_ROOT/tree/bin"
fake_command "$HOME/.local/nvim/bin/nvim" true
fake_command "$TEST_ROOT/tree/bin/nvim" echo
mv() {
    [[ "$1" != "$HOME/.local/nvim" ]] || return 76
    command mv "$@"
}
if atomic_replace_tree neovim "$TEST_ROOT/tree" "$HOME/.local/nvim" bin/nvim; then
    fail "failed tree backup reported success"
fi
[[ -x "$HOME/.local/nvim/bin/nvim" && ! -e "$HOME/.local/nvim/tree" ]] || fail "failed backup nested replacement into live tree"
unset -f mv
journal_reconcile

# Ledger failure must not be hidden by successful cleanup.
(
    ledger_record() { return 74; }
    if atomic_replace_binary eza "$TEST_ROOT/stage/eza" "$HOME/.local/bin/eza"; then
        fail "failed ledger write returned success"
    fi
    journal_pending || fail "failed ledger write lost recovery information"
)
journal_reconcile
journal_pending && fail "successful recovery left journal"

# A different executable on PATH cannot stand in for a missing managed artifact.
journal_begin eza "$HOME/.local/bin/missing" "$TEST_ROOT/stage/missing" "$HOME/.local/bin/missing"
if journal_reconcile 2>/dev/null; then fail "recovery accepted unrelated PATH binary"; fi
journal_pending || fail "unrecoverable journal was discarded"
journal_clear

mkdir -p "$TEST_ROOT/source" "$HOME/config-dir"
printf 'user data\n' > "$HOME/config-dir/keep"
mv() { return 75; }
if safe_symlink "$TEST_ROOT/source" "$HOME/config-dir" >/dev/null; then
    fail "failed config backup returned success"
fi
[[ -f "$HOME/config-dir/keep" && ! -L "$HOME/config-dir/source" ]] || fail "backup failure changed user config"
unset -f mv
curl() { return 77; }
if download_https https://example.invalid/artifact "$HOME/.local/bin/eza"; then
    fail "failed download accepted a nonempty prior artifact"
fi
printf 'transaction-failures: ok\n'
