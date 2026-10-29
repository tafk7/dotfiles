#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
source "$ROOT/lib/runtime.sh"
source "$ROOT/lib/registry.sh"
source "$ROOT/lib/state.sh"

preference_set feature.theme disabled & first=$!
preference_set feature.agent-badge enabled & second=$!
wait "$first"; wait "$second"
assert_eq "$(preference_get feature.theme)" disabled "concurrent theme preference"
assert_eq "$(preference_get feature.agent-badge)" enabled "concurrent badge preference"

# Many writers at once each keep their update. The directory lock this
# replaced lost one now and then: a writer judged a just-released lock stale and
# removed the next writer's.
pids=()
for i in $(seq 1 12); do
    preference_set "test.writer-$i" "value-$i" & pids+=($!)
done
for pid in "${pids[@]}"; do wait "$pid" || fail "a concurrent writer failed"; done
for i in $(seq 1 12); do
    assert_eq "$(preference_get "test.writer-$i")" "value-$i" "concurrent writer $i"
done

state_validate || fail "valid state rejected"
THEME_REQUEST=""
feature_enabled theme && fail "disabled theme preference did not persist"
THEME_REQUEST=enabled
feature_enabled theme || fail "explicit theme enable did not override stored preference"
THEME_REQUEST=""

# hold_lock SECONDS: hold the state lock in one process, as a writer would.
hold_lock() { ( exec {fd}>>"$DOTFILES_STATE_LOCK"; flock "$fd"; exec sleep "$1" ) & holder=$!; sleep 0.2; }

# A held lock makes a writer wait, and give up at its timeout with the value
# unchanged. A writer with time to spare waits it out, however long it is held:
# the directory lock this replaced broke a lock it judged stale after a second
# or two, and a writer stalled that long lost its update.
hold_lock 2.5
DOTFILES_STATE_LOCK_TIMEOUT=0.3 preference_set feature.theme enabled >/dev/null 2>&1 \
    && fail "live state lock was stolen"
assert_eq "$(preference_get feature.theme)" disabled "write under a live lock"
DOTFILES_STATE_LOCK_TIMEOUT=10 preference_set feature.theme enabled || fail "a waiting writer gave up"
kill -0 "$holder" 2>/dev/null && fail "a lock held for 2.5 s was broken"
assert_eq "$(preference_get feature.theme)" enabled "write after a long-held lock"
wait "$holder" 2>/dev/null || true

# A holder killed outright leaves nothing behind: the next writer goes ahead.
hold_lock 30
kill -9 "$holder"; wait "$holder" 2>/dev/null || true
DOTFILES_STATE_LOCK_TIMEOUT=1 preference_set feature.theme disabled || fail "a killed holder kept the lock"
assert_eq "$(preference_get feature.theme)" disabled "write after a killed holder"

# The old directory lock, left by an earlier version, doesn't block.
mkdir -p "$DOTFILES_STATE_DIR/.lock" && printf '%s\n' "$$" > "$DOTFILES_STATE_DIR/.lock/pid"
DOTFILES_STATE_LOCK_TIMEOUT=1 preference_set feature.theme enabled || fail "the old lock directory blocked a write"
rm -rf -- "$DOTFILES_STATE_DIR/.lock"

ledger_record demo yes dotfiles installed 1.0 "$HOME/.local/bin/demo" ok
line="$(ledger_line demo)"
[[ "$line" == $'demo\tyes\tdotfiles\tinstalled\t1.0\t'* ]] || fail "ledger record malformed"

TOOL_BINARY[demo]=demo
TOOL_OWNERSHIP_ROOTS[demo]="$HOME/.local/bin"
journal_begin demo "$HOME/.local/bin/demo" "$TEST_ROOT/staged/demo" "$HOME/.local/bin/demo"
journal_pending || fail "journal was not recorded"
journal_clear
journal_pending && fail "journal was not cleared"

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/recovered" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'recovered 1'
EOF
chmod +x "$HOME/.local/bin/recovered"
TOOL_BINARY=(['recovered']=recovered)
TOOL_OWNERSHIP_ROOTS=(['recovered']="$HOME/.local/bin")
PATH="$HOME/.local/bin:$PATH"
journal_begin recovered "$HOME/.local/bin/recovered" "$TEST_ROOT/staged" "$HOME/.local/bin/recovered"
journal_reconcile
line="$(ledger_line recovered)"
[[ "$line" == $'recovered\tyes\tdotfiles\tinstalled\t'* ]] || fail "journal recovery did not reconcile ledger"
journal_pending && fail "recovered journal was not cleared"

printf 'schema\t999\ndefault\tbroken\n' > "$DOTFILES_THEME_STATE_FILE"
assert_eq "$("$ROOT/bin/theme-switcher" --current)" "global: gruvbox" "corrupt theme state did not fall back"

printf 'schema\t1\nfeature.theme\t$(touch %s)\n' "$TEST_ROOT/executed" > "$DOTFILES_PREFERENCES_FILE"
preference_get feature.theme >/dev/null
[[ ! -e "$TEST_ROOT/executed" ]] || fail "state data was evaluated as shell code"

printf 'state: ok\n'
