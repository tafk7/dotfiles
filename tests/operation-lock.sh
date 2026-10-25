#!/bin/bash
# The operation lock: concurrent operations are refused, only the top-level
# command holds it, and dotfiles commands inside the operation join it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap 'pkill -P $$ 2>/dev/null || true; [[ -z "${survivor:-}" ]] || kill "$survivor" 2>/dev/null || true; fixture_cleanup' EXIT
fixture_init
unset DOTFILES_OPERATION DOTFILES_OPERATION_TAKING

op="$TEST_ROOT/op.sh"
printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    "source '$ROOT/lib/operation.sh'" \
    'operation_begin "$0" "$@"' \
    'case "$1" in' \
    '    hold) : > "$2"; while [[ ! -e "$3" ]]; do sleep 0.05; done ;;' \
    '    probe) if operation_held_here; then echo holder; elif operation_joined; then echo joined; else echo none; fi ;;' \
    '    nested) bash "$0" probe ;;' \
    '    reexec) exec bash "$0" probe ;;' \
    '    background) sleep 30 >/dev/null 2>&1 & echo "$!" ;;' \
    'esac' > "$op"
chmod +x "$op"

wait_for() { local i; for i in {1..100}; do [[ -e "$1" ]] && return 0; sleep 0.05; done; fail "timed out waiting for $1"; }

assert_eq "$(bash "$op" probe)" holder "a lone command holds the lock"
assert_eq "$(bash "$op" nested)" joined "a nested dotfiles command joins the operation"
assert_eq "$(bash "$op" reexec)" holder "a re-exec keeps holding the operation"

bash "$op" hold "$TEST_ROOT/started" "$TEST_ROOT/release" &
holder=$!
wait_for "$TEST_ROOT/started"
rc=0
message="$(bash "$op" probe 2>&1)" || rc=$?
assert_eq "$rc" 75 "a concurrent operation was not refused"
[[ "$message" == *"Another dotfiles operation is running: op.sh hold"* ]] || fail "refusal did not name the holder: $message"
# An inherited run id that is not the live holder's does not join.
rc=0
DOTFILES_OPERATION=forged bash "$op" probe >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 75 "a forged run id joined the operation"
: > "$TEST_ROOT/release"
wait "$holder"

# A background process that outlives the command does not keep the lock.
survivor="$(bash "$op" background)"
kill -0 "$survivor" 2>/dev/null || fail "background fixture did not survive"
assert_eq "$(bash "$op" probe)" holder "a surviving background child kept the lock"
kill "$survivor"; survivor=""

# Help, listings, checks, and previews do not take the lock.
source "$ROOT/lib/operation.sh"
operation_read_only_args --config --dry-run || fail "--dry-run should not lock"
operation_read_only_args claude --check || fail "--check should not lock"
if operation_read_only_args --full --tail; then fail "a real setup run must lock"; fi

# setup.sh refuses to run beside another operation, but a preview still runs.
bash "$op" hold "$TEST_ROOT/started2" "$TEST_ROOT/release2" &
holder=$!
wait_for "$TEST_ROOT/started2"
rc=0
"$ROOT/setup.sh" --config --no-hooks --no-theme --no-git >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 75 "setup ran beside another operation"
"$ROOT/setup.sh" --config --dry-run --no-hooks --no-theme --no-git >/dev/null 2>&1 \
    || fail "a setup preview was blocked by the operation lock"
: > "$TEST_ROOT/release2"
wait "$holder"

printf 'operation-lock: ok\n'
