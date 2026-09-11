#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

run_setup() {
    HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
        XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        DOTFILES_BACKUP_PREFIX="$DOTFILES_BACKUP_PREFIX" \
        "$ROOT/setup.sh" --config --no-hooks --no-theme \
        --git-name 'Fixture User' --git-email fixture@example.com >/dev/null
}

run_setup
[[ ! -d "$DOTFILES_BACKUP_PREFIX" ]] || fail "fresh config created an unnecessary backup directory"
[[ ! -e "$XDG_CACHE_HOME/dotfiles/theme" ]] || fail "--no-theme generated theme artifacts"
grep -Fq 'delta.gitconfig' "$XDG_CONFIG_HOME/dotfiles/gitconfig" \
    && fail "--no-theme left the Delta theme include enabled"
first="$(fixture_managed_snapshot)"
run_setup
second="$(fixture_managed_snapshot)"
assert_eq "$second" "$first" "second config run was not idempotent"

rm "$HOME/.editorconfig"
printf 'user content\n' > "$HOME/.editorconfig"
run_setup
[[ -L "$HOME/.editorconfig" ]] || fail "divergent config was not reconciled"
backup="$(find "$DOTFILES_BACKUP_PREFIX" -type f -path '*/.editorconfig' -print -quit)"
[[ -n "$backup" ]] || fail "displaced config was not backed up lazily"
grep -qx 'user content' "$backup" || fail "backup content changed"

rm "$HOME/.profile"
ln -s "$TEST_ROOT/missing" "$HOME/.profile"
run_setup
assert_eq "$(readlink -f "$HOME/.profile")" "$(readlink -f "$ROOT/entry/profile.sh")" "broken symlink not repaired"

printf 'config-reconcile: ok\n'
