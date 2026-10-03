#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

status="$("$ROOT/bin/dotfiles-feature" status)"
[[ "$status" == *'theme          enabled'* ]] || fail "theme default is not enabled"
[[ "$status" == *'agent-badge    enabled'* ]] || fail "agent-badge default is not enabled"

"$ROOT/bin/dotfiles-feature" disable theme >/dev/null
"$ROOT/bin/theme-switcher" enabled && fail "theme disable did not persist"
"$ROOT/bin/theme-switcher" kanagawa >/dev/null 2>&1 && fail "disabled theme feature accepted a theme"

"$ROOT/bin/dotfiles-feature" enable theme >/dev/null
"$ROOT/bin/theme-switcher" enabled || fail "theme enable did not persist"
"$ROOT/bin/theme-switcher" kanagawa >/dev/null || fail "enabled theme feature rejected a theme"
assert_eq "$("$ROOT/bin/theme-switcher" --current)" "global: kanagawa" "theme state was not written"

"$ROOT/bin/dotfiles-feature" disable agent-badge >/dev/null
assert_eq "$("$ROOT/bin/dotfiles-feature" status | awk '$1 == "agent-badge" { print $2 }')" disabled

printf 'features: ok\n'
