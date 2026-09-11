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

ledger_record starship yes dotfiles installed 1 "$HOME/.local/bin/starship" test
if HOME="$HOME" XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" PATH="$TEST_SYSTEM_PATH" \
    "$ROOT/bin/verify" --installed >/dev/null 2>&1; then
    fail "installed verification ignored missing recorded component"
fi

printf 'verify-profiles: ok\n'
