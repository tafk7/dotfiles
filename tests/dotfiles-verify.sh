#!/bin/bash
# dotfiles verify: sections built from outcome records, the exit status per
# class (convergence 1, incomplete 3, health 2), and -v.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap 'pkill -P $$ 2>/dev/null || true; fixture_cleanup' EXIT
fixture_init
unset DOTFILES_OPERATION
export NO_COLOR=1 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
export DOTFILES_TEST_SYSTEMD_RUNNING=0 DOTFILES_OPERATION_WAIT=1
# Nothing here may consult the host's packages.
printf '#!/bin/sh\nexit 1\n' > "$TEST_ROOT/bin/dpkg-query"
chmod +x "$TEST_ROOT/bin/dpkg-query"
export PATH="$TEST_ROOT/bin:$TEST_SYSTEM_PATH"

verify() {
    local rc=0
    VERIFY_OUTPUT="$("$ROOT/bin/dotfiles" verify "$@" 2>&1)" || rc=$?
    VERIFY_RC="$rc"
}

"$ROOT/setup.sh" --config --no-hooks --no-theme --git-name Fixture --git-email fixture@example.com >/dev/null 2>&1 \
    || fail "fixture setup failed"
verify
assert_eq "$VERIFY_RC" 0 "a converged config-tier machine: $VERIFY_OUTPUT"
[[ "$VERIFY_OUTPUT" != *"  ok "* ]] || fail "passing checks shown without -v"
verify -v
[[ "$VERIFY_OUTPUT" == *$'Configs\n'*"  ok   $HOME/.bashrc"* ]] || fail "-v did not list passing checks: $VERIFY_OUTPUT"

# A missing config is work for setup: exit 1.
rm "$HOME/.editorconfig"
verify
assert_eq "$VERIFY_RC" 1 "missing config"
[[ "$VERIFY_OUTPUT" == *"fix  $HOME/.editorconfig: missing"* ]] || fail "missing config not reported: $VERIFY_OUTPUT"
ln -s "$ROOT/configs/editorconfig" "$HOME/.editorconfig"

# Tailscale that setup cannot finish (not connected) needs the operator: exit 2.
printf '#!/bin/sh\nexit 1\n' > "$TEST_ROOT/bin/tailscale"
chmod +x "$TEST_ROOT/bin/tailscale"
"$ROOT/bin/dotfiles" profile --add tail --no-apply >/dev/null
verify
assert_eq "$VERIFY_RC" 2 "health finding: $VERIFY_OUTPUT"
[[ "$VERIFY_OUTPUT" == *"note tailscale: satisfied by an external install at $TEST_ROOT/bin/tailscale"* ]] \
    || fail "an external install was not an advisory: $VERIFY_OUTPUT"

# A check that cannot be made outranks a health finding: exit 3.
ledger="$XDG_STATE_HOME/dotfiles/components.tsv"
cp "$ledger" "$TEST_ROOT/ledger"
printf 'not a ledger\n' > "$ledger"
verify
assert_eq "$VERIFY_RC" 3 "incomplete check: $VERIFY_OUTPUT"
cp "$TEST_ROOT/ledger" "$ledger"

# Convergence outranks everything: exit 1.
rm "$HOME/.editorconfig"
verify
assert_eq "$VERIFY_RC" 1 "convergence with health findings"
ln -s "$ROOT/configs/editorconfig" "$HOME/.editorconfig"

# Neovim's plugins are checked where the profile expects Neovim (the dev
# tier), not on a config-tier machine that happens to have one.
printf '#!/bin/sh\nprintf "%%s\\n%%s\\n" "$HOME/.config/nvim" "$HOME/.local/share/nvim"\n' > "$TEST_ROOT/bin/nvim"
chmod +x "$TEST_ROOT/bin/nvim"
verify
[[ "$VERIFY_OUTPUT" != *"Editor plugins"* ]] || fail "plugins checked below the dev tier: $VERIFY_OUTPUT"
sed -i 's/^tier\t.*/tier\tdev/' "$XDG_STATE_HOME/dotfiles/profile"
verify
[[ "$VERIFY_OUTPUT" == *$'Editor plugins\n'*"fix  plugins: install vim-plug"* ]] || fail "dev-tier plugins not checked: $VERIFY_OUTPUT"
sed -i 's/^tier\t.*/tier\tconfig/' "$XDG_STATE_HOME/dotfiles/profile"
rm "$TEST_ROOT/bin/nvim"

# An operation in progress makes the result incomplete.
flock "$XDG_STATE_HOME/dotfiles/operation.lock" sleep 20 &
holder=$!
sleep 0.3
verify
[[ "$VERIFY_OUTPUT" == *"?? "*"operation: in progress"* ]] || fail "a running operation was not reported: $VERIFY_OUTPUT"
assert_eq "$VERIFY_RC" 3 "verify during an operation"
kill "$holder"

printf 'dotfiles-verify: ok\n'
