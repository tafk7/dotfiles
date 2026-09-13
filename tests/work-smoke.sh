#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/runtime.sh"; source "$ROOT/lib/work-host.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
DOTFILES_TEST_KVM_DEVICE=present; DOTFILES_TEST_KVM_ACCESS=yes; DOTFILES_SBX_SMOKE_NAME=dotfiles-smoke-test
state=absent; calls=""; cleanup_fail=false; create_fail=false; exec_fail=false; signal_kind=""; cleanup_marker=""
host_timeout() { shift; "$@"; }
sbx() {
    calls+="|$*"
    case "$1" in
        diagnose|version) return 0 ;;
        ls) [[ "$state" == present ]] && echo dotfiles-smoke-test ;;
        create)
            state=present
            [[ -z "$signal_kind" ]] || kill -"$signal_kind" "$BASHPID"
            [[ "$create_fail" == false ]]
            ;;
        exec) [[ "$exec_fail" == false ]] ;;
        rm) [[ "$cleanup_fail" == false ]] || return 8; state=absent; [[ -z "$cleanup_marker" ]] || : > "$cleanup_marker" ;;
    esac
}

state=present; rc=0; work_smoke_test >/dev/null 2>&1 || rc=$?; [[ $rc -ne 0 ]] || fail "collision accepted"
[[ "$calls" != *"create"* ]] || fail "collision test created a sandbox"

state=absent; calls=""; create_fail=true; rc=0; work_smoke_test >/dev/null 2>&1 || rc=$?
[[ $rc -ne 0 && "$state" == absent && "$calls" == *"rm --force dotfiles-smoke-test"* ]] \
    || fail "partial creation was not precisely cleaned up"

state=absent; calls=""; create_fail=false; exec_fail=true; cleanup_fail=true; rc=0
work_smoke_test >/dev/null 2>&1 || rc=$?
[[ $rc -eq 1 && "$state" == present ]] || fail "cleanup failure replaced the original execution failure"
[[ "$calls" != *"--cloud"* && "$calls" != *"--all"* && "$calls" != *"prune"* && "$calls" != *"reset"* ]] \
    || fail "smoke test used a broad or cloud operation"

for signal_kind in INT TERM; do
    cleanup_marker="${TMPDIR:-/tmp}/work-smoke-cleanup-${signal_kind}-$$"
    state=absent; cleanup_fail=false; create_fail=false; exec_fail=false; rc=0
    ( work_smoke_test >/dev/null 2>&1 ) || rc=$?
    expected=130; [[ "$signal_kind" == TERM ]] && expected=143
    [[ $rc -eq $expected && -f "$cleanup_marker" ]] || fail "$signal_kind did not preserve status and clean partial creation"
    rm -f "$cleanup_marker"
done

printf 'work-smoke: ok\n'
