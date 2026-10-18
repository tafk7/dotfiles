#!/bin/bash
# Setup logs: both streams reach the terminal and one color-free log, the exit
# status survives, the footer lists ledger changes, and old logs are pruned.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
unset DOTFILES_SETUP_LOG
LOGS="$XDG_STATE_HOME/dotfiles/logs"

mkdir -p "$LOGS"
for stamp in 20260101T000000Z 20260102T000000Z 20260103T000000Z; do
    : > "$LOGS/setup-$stamp.log"
done
printf 'schema\t1\nzsh\tyes\tpackage-manager\tinstalled\tzsh 5.9\t/usr/bin/zsh\tapt-in-place\t100\n' \
    > "$XDG_STATE_HOME/dotfiles/components.tsv"

rc=0
(
    source "$ROOT/lib/runtime.sh"
    source "$ROOT/lib/state.sh"
    source "$ROOT/lib/setup-log.sh"
    DOTFILES_LOG_KEEP=2
    setup_log_start --dev --dry-run
    printf 'to stdout\n'
    printf '\033[0;31mto stderr\033[0m\n' >&2
    printf 'progress 10%%\rprogress 100%%\n'
    printf 'schema\t1\nzsh\tyes\tpackage-manager\tinstalled\tzsh 5.9\t/usr/bin/zsh\tapt-in-place\t200\nharper-ls\tyes\tdotfiles\tinstalled\t2.12.0\t/x\tstaged-release\t200\n' \
        > "$DOTFILES_LEDGER_FILE"
    exit 3
) > "$TEST_ROOT/out" 2> "$TEST_ROOT/err" || rc=$?

assert_eq "$rc" 3 "exit status survives the log trap"
grep -qx 'to stdout' "$TEST_ROOT/out" || fail "stdout missing from the terminal"
grep -q 'to stderr' "$TEST_ROOT/err" || fail "stderr missing from the terminal"
grep -q '^Setup log: ' "$TEST_ROOT/err" || fail "log path not reported"

log="$LOGS/latest.log"
[[ -f "$log" ]] || fail "latest.log does not resolve"
grep -qx 'command:  ./setup.sh --dev --dry-run' "$log" || fail "command header: $(head -n4 "$log")"
grep -qx 'to stdout' "$log" || fail "stdout missing from the log"
grep -qx 'to stderr' "$log" || fail "stderr missing or uncleaned in the log"
grep -qx 'progress 100%' "$log" || fail "carriage-return redraw not collapsed"
grep -q $'\033' "$log" && fail "escape sequences left in the log"
grep -q '^# finished: .*(exit 3, ' "$log" || fail "footer exit status: $(tail -n3 "$log")"
grep -q '^+ harper-ls' "$log" || fail "new ledger row not listed"
grep -q 'zsh' <(sed -n '/^# ledger changes/,$p' "$log") && fail "timestamp-only change listed"
assert_eq "$(stat -c %a "$LOGS")" 700 "log directory mode"
assert_eq "$(stat -L -c %a "$log")" 600 "log file mode"

assert_eq "$(find "$LOGS" -name 'setup-*.log' | wc -l)" 2 "retention keeps DOTFILES_LOG_KEEP logs"
[[ -e "$LOGS/setup-20260103T000000Z.log" ]] || fail "pruned the newest older log"

rc=0
( source "$ROOT/lib/runtime.sh"; source "$ROOT/lib/state.sh"; source "$ROOT/lib/setup-log.sh"
  DOTFILES_SETUP_LOG=0; setup_log_start --config; printf 'quiet\n' ) > "$TEST_ROOT/out" 2>&1 || rc=$?
assert_eq "$rc" 0 "disabled log run"
grep -q 'Setup log' "$TEST_ROOT/out" && fail "DOTFILES_SETUP_LOG=0 still logged"

printf 'setup-log: ok\n'
