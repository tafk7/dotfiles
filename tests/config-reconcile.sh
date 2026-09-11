#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
printf '[custom]\n    preserved = yes\n' > "$HOME/.gitconfig"

run_setup() {
    HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
        XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        DOTFILES_BACKUP_PREFIX="$DOTFILES_BACKUP_PREFIX" \
        "$ROOT/setup.sh" --config --no-hooks --no-theme \
        --git-name 'Fixture User' --git-email fixture@example.com >/dev/null
}

run_setup
[[ ! -d "$DOTFILES_BACKUP_PREFIX" ]] || fail "fresh config created an unnecessary backup directory"
grep -q 'preserved = yes' "$HOME/.gitconfig" || fail "existing Git config was overwritten"
grep -Fq "$XDG_CONFIG_HOME/dotfiles/gitconfig" "$HOME/.gitconfig" || fail "portable Git include missing"
assert_eq "$(stat -c %a "$HOME/.ssh")" 700 "SSH directory permissions"
assert_eq "$(stat -c %a "$HOME/.ssh/sockets")" 700 "SSH socket directory permissions"
[[ ! -e "$XDG_CACHE_HOME/dotfiles/theme" ]] || fail "--no-theme generated theme artifacts"
grep -Fq 'delta.gitconfig' "$XDG_CONFIG_HOME/dotfiles/gitconfig" \
    && fail "--no-theme left the Delta theme include enabled"
source "$ROOT/lib/runtime.sh"
source "$ROOT/lib/registry.sh"
source "$ROOT/lib/state.sh"
ledger_record docker yes package-manager installed 1 /usr/bin/docker apt-in-place
first="$(fixture_managed_snapshot)"
run_setup
second="$(fixture_managed_snapshot)"
assert_eq "$second" "$first" "second config run was not idempotent"
[[ "$(ledger_line docker)" == $'docker\tyes\tpackage-manager\tinstalled\t1\t/usr/bin/docker\tapt-in-place\t'* ]] \
    || fail "lower-tier reconciliation erased higher-tier ledger history"

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

HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    DOTFILES_BACKUP_PREFIX="$DOTFILES_BACKUP_PREFIX" \
    "$ROOT/setup.sh" --config --theme --no-hooks \
    --git-name 'Fixture User' --git-email fixture@example.com >/dev/null
themed_first="$(fixture_managed_snapshot)"
run_setup_theme_output="$(HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
    DOTFILES_BACKUP_PREFIX="$DOTFILES_BACKUP_PREFIX" \
    "$ROOT/setup.sh" --config --no-hooks \
    --git-name 'Fixture User' --git-email fixture@example.com)"
themed_second="$(fixture_managed_snapshot)"
assert_eq "$themed_second" "$themed_first" "default-theme setup rerun was not idempotent"
: "$run_setup_theme_output"

printf 'config-reconcile: ok\n'
