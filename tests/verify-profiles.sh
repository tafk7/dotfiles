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

# A cumulative tier includes the subset applicable to the current platform.
# Native Ubuntu must not fail because the bash tier also registers a WSL-only
# SSH bridge.
HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_OS_VERSION=24.04 DOTFILES_TEST_ARCH=x86_64 \
    "$ROOT/bin/verify" --tier bash > "$TEST_ROOT/native-bash.log" 2>&1 || true
if grep -Fq 'wsl2-ssh-agent (requested capability is unsupported' "$TEST_ROOT/native-bash.log"; then
    fail "native bash verification required the WSL-only SSH bridge"
fi

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

# Adoption must not expose a false ownership failure for agent-private rg.
mkdir -p "$HOME/.local/bin" "$TEST_ROOT/.codex/private"
cp /usr/bin/true "$HOME/.local/bin/rg"
cp /usr/bin/true "$TEST_ROOT/.codex/private/rg"
ledger_record ripgrep yes dotfiles installed 1 "$HOME/.local/bin/rg" test
PATH="$TEST_ROOT/.codex/private:$HOME/.local/bin:$PATH" "$ROOT/bin/verify" --installed \
    > "$TEST_ROOT/private-rg.log" 2>&1 || true
# Other discovered host services can fail readiness in this temporary profile.
# Assert the component result rather than unrelated machine-wide readiness.
grep -Fq '✅ ripgrep (rg)' "$TEST_ROOT/private-rg.log" \
    || { cat "$TEST_ROOT/private-rg.log" >&2; fail "private rg shadowed the verified owned installation"; }
grep -Fq 'present outside recorded ownership' "$TEST_ROOT/private-rg.log" \
    && fail "private rg was used for ownership verification"

# Distinguish a missing companion from a missing primary executable.
cp /usr/bin/true "$HOME/.local/bin/uv"
ledger_record uv yes dotfiles installed 1 "$HOME/.local/bin/uv" test
PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH" "$ROOT/bin/verify" --installed \
    > "$TEST_ROOT/missing-uvx.log" 2>&1 && fail "missing companion was accepted"
grep -Fq 'uv (missing companion: uvx)' "$TEST_ROOT/missing-uvx.log" \
    || fail "missing companion was reported as a missing primary"

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
