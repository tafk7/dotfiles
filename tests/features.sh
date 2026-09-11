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
[[ ! -e "$XDG_CACHE_HOME/dotfiles/theme" ]] || fail "disable unexpectedly rendered theme cache"

"$ROOT/bin/dotfiles-feature" enable theme >/dev/null
"$ROOT/bin/theme-switcher" enabled || fail "theme enable did not persist"
[[ -f "$XDG_STATE_HOME/dotfiles/theme.tsv" ]] || fail "theme state was not initialized"
[[ -f "$XDG_CACHE_HOME/dotfiles/theme/delta.gitconfig" ]] || fail "theme cache was not rendered"

"$ROOT/bin/dotfiles-feature" disable agent-badge >/dev/null
assert_eq "$("$ROOT/bin/dotfiles-feature" status | awk '$1 == "agent-badge" { print $2 }')" disabled

printf 'features: ok\n'
