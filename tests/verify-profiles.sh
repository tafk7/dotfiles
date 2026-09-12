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

HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    "$ROOT/setup.sh" --config --no-theme --no-hooks \
    --git-name Fixture --git-email fixture@example.com >/dev/null

HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    "$ROOT/bin/verify" --tier config >/dev/null \
    || fail "config-only verification failed"

# Theme includes are nested through the portable Git config, not written
# directly into ~/.gitconfig. Verification must follow include chains.
HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    "$ROOT/setup.sh" --config --theme --no-hooks \
    --git-name Fixture --git-email fixture@example.com >/dev/null
HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    "$ROOT/bin/verify" --tier config > "$TEST_ROOT/theme-verify.log" \
    || fail "theme-enabled config verification failed"
grep -Fq 'delta: ~/.gitconfig includes the XDG theme cache' "$TEST_ROOT/theme-verify.log" \
    || fail "nested Delta include was not verified"
grep -Fq 'user: Fixture <fixture@example.com>' "$TEST_ROOT/theme-verify.log" \
    || fail "identity in the local Git include was not verified"

external_fixture_function() { :; }
export -f external_fixture_function
"$ROOT/bin/verify" --tier config > "$TEST_ROOT/external-functions.log"
grep -Fq 'no dotfiles interactive/private functions leak' "$TEST_ROOT/external-functions.log" \
    || fail "external function was mistaken for a dotfiles startup leak"
reload() { :; }
export -f reload
"$ROOT/bin/verify" --tier config > "$TEST_ROOT/leaked-functions.log"
grep -Fq 'dotfiles interactive/private function(s) in the agent shell' "$TEST_ROOT/leaked-functions.log" \
    || fail "interactive function leak was not diagnosed"
unset -f reload external_fixture_function

# A minimal profile may define no functions; compgen then returns 1.
cat > "$TEST_ROOT/bin/bash" <<'EOF'
#!/bin/bash
if [[ "$1" == -lc ]]; then
    shift
    exec /bin/bash --noprofile --norc -c "$@"
fi
exec /bin/bash "$@"
EOF
chmod +x "$TEST_ROOT/bin/bash"
PATH="$TEST_ROOT/bin:$PATH" "$ROOT/bin/verify" --tier config > "$TEST_ROOT/no-functions.log" \
    || fail "empty function inventory aborted verification"
grep -Fq 'no dotfiles interactive/private functions leak' "$TEST_ROOT/no-functions.log" \
    || fail "empty function inventory was not verified"

ledger_record starship yes dotfiles installed 1 "$HOME/.local/bin/starship" test
if HOME="$HOME" XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" PATH="$TEST_SYSTEM_PATH" \
    "$ROOT/bin/verify" --installed >/dev/null 2>&1; then
    fail "installed verification ignored missing recorded component"
fi

rc=0
HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" PATH="$TEST_SYSTEM_PATH" DOTFILES_TEST_PLATFORM=ubuntu \
    DOTFILES_TEST_OS_VERSION=24.04 DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_SYSTEMD_RUNNING=0 \
    "$ROOT/bin/verify" --tier work --tail > "$TEST_ROOT/work-profile.log" 2>&1 || rc=$?
[[ $rc -ne 64 ]] || fail "composed --tier work --tail verification was rejected by the parser"
grep -Fq 'Work local-execution readiness' "$TEST_ROOT/work-profile.log" || fail "work readiness verification did not run"
grep -Fq 'Tailscale readiness' "$TEST_ROOT/work-profile.log" || fail "Tailscale verification did not run"

rc=0
HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_STATE_HOME="$XDG_STATE_HOME" \
    XDG_CACHE_HOME="$XDG_CACHE_HOME" PATH="$TEST_SYSTEM_PATH" \
    "$ROOT/bin/verify" --tier ai >/dev/null 2>&1 || rc=$?
[[ $rc -ne 64 ]] || fail "legacy --tier ai compatibility alias was rejected"

printf 'verify-profiles: ok\n'
