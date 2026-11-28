#!/bin/bash
# Caller PATH snapshots belong to a live operation's process tree, including
# re-execs and child installers, but not unrelated or surviving processes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap '[[ -z "${peer:-}" ]] || { kill "$peer" 2>/dev/null || true; wait "$peer" 2>/dev/null || true; }; fixture_cleanup' EXIT
fixture_init
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
actual="$PATH"
stale="$HOME/.local/bin:$TEST_SYSTEM_PATH"
failed=false

# The probe does not execute the candidate: the stale PATH would hide an ELF.
cp /bin/false "$TEST_ROOT/bin/agy"
probe="$TEST_ROOT/probe.sh"
cat > "$probe" <<'EOF'
#!/bin/bash
set -euo pipefail
source "$DOTFILES_DIR/lib/install.sh"
[[ "$DOTFILES_CALLER_PATH" == "$EXPECTED_PATH" ]] || { echo "stale snapshot: $DOTFILES_CALLER_PATH"; exit 1; }
[[ "$(external_install_path agy "$HOME/.local/bin/agy")" == "$TEST_ROOT/bin/agy" ]] || { echo 'stale snapshot hid external ELF'; exit 1; }
EOF
export TEST_ROOT EXPECTED_PATH="$actual"

check_stale() {
    local label="$1" owner="$2" out
    if out="$(DOTFILES_CALLER_PATH="$stale" DOTFILES_CALLER_PATH_OWNER="$owner" bash "$probe" 2>&1)"; then
        printf 'caller PATH: %s ok\n' "$label"
    else
        printf 'FAIL: caller PATH %s: %s\n' "$label" "$out" >&2
        failed=true
    fi
}
check_stale no-owner ''
check_stale dead-owner '999999999:1'
# A live sibling is not the taking process or an ancestor.
sleep 30 & peer=$!
ticks="$(awk '{print $22}' "/proc/$peer/stat")"
check_stale non-ancestor "$peer:$ticks"
kill "$peer"; wait "$peer" 2>/dev/null || true; peer=""
# PID reuse or a wrong start time must invalidate an ancestor's identity too.
check_stale wrong-start "$$:0"

driver="$TEST_ROOT/driver.sh"
cat > "$driver" <<'EOF'
#!/bin/bash
set -euo pipefail
source "$DOTFILES_DIR/lib/runtime.sh"
case "$1" in
    child|reexec|locked)
        export EXPECTED_SNAPSHOT="$DOTFILES_CALLER_PATH" EXPECTED_OWNER="$DOTFILES_CALLER_PATH_OWNER"
        export PATH="$HOME/.local/bin:$PATH"
        case "$1" in
            child) bash "$0" check ;;
            reexec) exec bash "$0" check ;;
            locked)
                source "$DOTFILES_DIR/lib/operation.sh"
                operation_begin "$0" check
                ;;
        esac
        ;;
    check)
        [[ "$DOTFILES_CALLER_PATH" == "$EXPECTED_SNAPSHOT" && "$DOTFILES_CALLER_PATH_OWNER" == "$EXPECTED_OWNER" ]]
        ;;
    capture) printf '%s\n' "$DOTFILES_CALLER_PATH_OWNER" ;;
esac
EOF
for mode in child reexec locked; do
    if bash "$driver" "$mode"; then
        printf 'caller PATH: %s ok\n' "$mode"
    else
        printf 'FAIL: caller PATH %s lost its valid snapshot\n' "$mode" >&2
        failed=true
    fi
done
# The capturing subprocess has ended; inherited metadata cannot revive it.
if owner="$(bash "$driver" capture)"; then check_stale ended-operation "$owner"; else failed=true; fi
# A Bash subshell has the parent's $$ but its own BASHPID. Its snapshot must
# expire when that subshell ends, even while the parent is still alive.
if owner="$(source "$ROOT/lib/runtime.sh"; printf '%s\n' "$DOTFILES_CALLER_PATH_OWNER")"; then
    check_stale ended-subshell "$owner"
else
    failed=true
fi
[[ "$failed" == false ]] || fail 'caller PATH cases failed'
printf 'caller-path: ok\n'
