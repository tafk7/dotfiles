#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init

# Seed more backups than retention would keep. A dry-run must not rotate them.
/bin/mkdir -p "$DOTFILES_BACKUP_PREFIX"
for n in $(seq 1 12); do /bin/mkdir -p "$DOTFILES_BACKUP_PREFIX/backup-20260101-0000$n"; done
/bin/mkdir -p "$XDG_STATE_HOME/dotfiles"
printf 'schema\t1\ncomponent\tdemo\nold_path\t-\nstaged_path\t-\nnew_path\t-\n' \
    > "$XDG_STATE_HOME/dotfiles/transaction.tsv"

install_mutation_spies
repo_before="$(fixture_snapshot "$ROOT")"
home_before="$(fixture_snapshot "$TEST_ROOT")"

run_dry() {
    local output rc=0
    output="$(HOME="$HOME" XDG_CONFIG_HOME="$XDG_CONFIG_HOME" XDG_DATA_HOME="$XDG_DATA_HOME" \
        XDG_STATE_HOME="$XDG_STATE_HOME" XDG_CACHE_HOME="$XDG_CACHE_HOME" TMPDIR="$TMPDIR" \
        DOTFILES_BACKUP_PREFIX="$DOTFILES_BACKUP_PREFIX" PATH="$PATH" \
        "$ROOT/setup.sh" "$@" --dry-run --no-hooks --no-git 2>&1)" || rc=$?
    [[ $rc -eq 0 ]] || fail "dry-run failed ($rc): $output"
}

run_dry --config
run_dry --config --no-theme
run_dry --bash
run_dry --bash --no-theme
run_dry --dev
run_dry --work
run_dry --ai
run_dry --rdp --no-theme
run_dry --full --no-theme --no-agent-badge

[[ ! -s "$DOTFILES_MUTATION_LOG" ]] || fail "dry-run invoked mutating commands: $(cat "$DOTFILES_MUTATION_LOG")"
assert_eq "$(fixture_snapshot "$ROOT")" "$repo_before" "repository changed during dry-run"
assert_eq "$(fixture_snapshot "$TEST_ROOT")" "$home_before" "fixture changed during dry-run"
assert_eq "$(find "$DOTFILES_BACKUP_PREFIX" -mindepth 1 -maxdepth 1 -type d | wc -l)" 12 "backup retention ran"

printf 'setup-safety: ok\n'
