#!/bin/bash
# dotfiles refresh, and the one refresh that ends every apply: none on a dry
# run or with --no-refresh, and setup leaves tmux and the theme to it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
unset DOTFILES_OPERATION DOTFILES_TMUX_SERVER
export NO_COLOR=1 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
export DOTFILES_TEST_SYSTEMD_RUNNING=0
printf '#!/bin/sh\nexit 1\n' > "$TEST_ROOT/bin/dpkg-query"
chmod +x "$TEST_ROOT/bin/dpkg-query"
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
"$ROOT/setup.sh" --config --no-hooks --no-theme --git-name Fixture --git-email fixture@example.com >/dev/null 2>&1 \
    || fail "fixture setup failed"
run() { local rc=0; OUTPUT="$("$ROOT/bin/dotfiles" "$@" 2>&1)" || rc=$?; RC=$rc; REFRESHES="$(grep -c 'Refreshing running processes' <<< "$OUTPUT" || true)"; }

run refresh
assert_eq "$RC/$REFRESHES" "0/1" "refresh: $OUTPUT"
run refresh -v
[[ "$OUTPUT" == *"ok   server: "* && "$OUTPUT" == *"ok   shells: "* ]] || fail "refresh -v did not list its steps: $OUTPUT"

run apply
assert_eq "$RC/$REFRESHES" "0/1" "apply: $OUTPUT"
[[ "$OUTPUT" == *"refreshed after setup"* && "$OUTPUT" != *"Theme feature disabled"* ]] \
    || fail "setup applied the theme itself under apply: $OUTPUT"
run apply --no-refresh
assert_eq "$RC/$REFRESHES" "0/0" "apply --no-refresh"
[[ "$OUTPUT" == *"Theme feature disabled"* ]] || fail "without a refresh, setup must handle the theme: $OUTPUT"
run apply --dry-run
assert_eq "$RC/$REFRESHES" "0/0" "apply --dry-run"

printf 'dotfiles-refresh: ok\n'
