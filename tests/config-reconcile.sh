#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

# GitHub's hosted Ubuntu image includes Azure CLI. Its `az --version` command
# creates ~/.azure state and writes telemetry asynchronously, which made the
# whole-HOME idempotence snapshot race after external-component discovery.
# Provide a deterministic stand-in and assert that APT metadata is used instead
# of executing the external CLI for its version.
printf '%s\n' \
    '#!/bin/bash' \
    'mkdir -p "$HOME/.azure/logs"' \
    'printf "unexpected version probe\n" >> "$HOME/.azure/logs/telemetry.log"' \
    'printf "azure-cli 99.0\n"' \
    > "$TEST_ROOT/bin/az"
printf '%s\n' \
    '#!/bin/bash' \
    'if [[ "${*: -1}" == azure-cli ]]; then' \
    '    printf "99.0\n"' \
    'else' \
    '    exec /usr/bin/dpkg-query "$@"' \
    'fi' \
    > "$TEST_ROOT/bin/dpkg-query"
chmod +x "$TEST_ROOT/bin/az" "$TEST_ROOT/bin/dpkg-query"
export PATH="$TEST_ROOT/bin:$PATH"

printf '[custom]\n    preserved = yes\n' > "$HOME/.gitconfig"

run_setup() {
    HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
        XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" \
        DOTFILES_BACKUP_PREFIX="$DOTFILES_BACKUP_PREFIX" \
        "$ROOT/setup.sh" --config --no-hooks --no-theme \
        --git-name 'Fixture User' --git-email fixture@example.com >/dev/null
}

run_setup
[[ ! -e "$HOME/.azure" ]] || fail "external Azure CLI was executed during component discovery"
[[ ! -d "$DOTFILES_BACKUP_PREFIX" ]] || fail "fresh config created an unnecessary backup directory"
grep -q 'preserved = yes' "$HOME/.gitconfig" || fail "existing Git config was overwritten"
grep -Fq "$XDG_CONFIG_HOME/dotfiles/gitconfig" "$HOME/.gitconfig" || fail "portable Git include missing"
grep -Fq "$XDG_CONFIG_HOME/dotfiles/gitconfig-azure" "$XDG_CONFIG_HOME/dotfiles/gitconfig" \
    || fail "existing Azure CLI did not activate portable Azure include"
[[ "$(grep -c '^\[credential ' "$XDG_CONFIG_HOME/dotfiles/gitconfig" || true)" == 0 ]] \
    || fail "Azure credential helpers remained duplicated in the portable base"
[[ "$(grep -c '^\[credential ' "$XDG_CONFIG_HOME/dotfiles/gitconfig-azure")" == 2 ]] \
    || fail "Azure credential include is incomplete or duplicated"
[[ -L "$HOME/.local/bin/git-credential-azdo" ]] || fail "Azure credential helper was not linked"
assert_eq "$(stat -c %a "$HOME/.ssh")" 700 "SSH directory permissions"
assert_eq "$(stat -c %a "$HOME/.ssh/sockets")" 700 "SSH socket directory permissions"
[[ ! -e "$XDG_CACHE_HOME/dotfiles/theme" ]] || fail "--no-theme generated theme artifacts"
grep -Fq 'delta.gitconfig' "$XDG_CONFIG_HOME/dotfiles/gitconfig" \
    && fail "--no-theme left the Delta theme include enabled"
source "$ROOT/lib/runtime.sh"
source "$ROOT/lib/registry.sh"
source "$ROOT/lib/state.sh"
ledger_record docker yes package-manager installed 1 /usr/bin/docker apt-in-place
first_manifest="$(fixture_managed_manifest)"
first="$(fixture_managed_snapshot)"
run_setup
second_manifest="$(fixture_managed_manifest)"
second="$(fixture_managed_snapshot)"
if [[ "$second" != "$first" ]]; then
    diff -u <(printf '%s\n' "$first_manifest") <(printf '%s\n' "$second_manifest") >&2 || true
    fail "expected '$first', got '$second' (second config run was not idempotent)"
fi
[[ "$(ledger_line docker)" == $'docker\tyes\tpackage-manager\tinstalled\t1\t/usr/bin/docker\tapt-in-place\t'* ]] \
    || fail "lower-tier reconciliation erased higher-tier ledger history"

rm "$TEST_ROOT/bin/az"
export DOTFILES_TEST_AZURE_PRESENT=0
run_setup
grep -Fq "$XDG_CONFIG_HOME/dotfiles/gitconfig-azure" "$XDG_CONFIG_HOME/dotfiles/gitconfig" \
    && fail "Azure include stayed active after Azure CLI was no longer applicable"

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
