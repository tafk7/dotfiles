#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
source "$ROOT/setup.sh"

dpkg() { return 1; }
safe_sudo() { return 55; }
if install_apt injected broken-package >/dev/null 2>&1; then fail "APT failure was swallowed"; fi

fake_repo="$TEST_ROOT/repo"
mkdir -p "$fake_repo/installers"
old_dir="$DOTFILES_DIR"
DOTFILES_DIR="$fake_repo"
for name in claude codex opencode pi; do
    printf '#!/bin/sh\nexit 42\n' > "$fake_repo/installers/install-$name.sh"
    chmod +x "$fake_repo/installers/install-$name.sh"
    INSTALL_FAIL=()
    if run_installer "$name" >/dev/null 2>&1; then fail "$name installer failure was swallowed"; fi
    [[ " ${INSTALL_FAIL[*]} " == *" $name "* ]] || fail "$name failure missing from summary"
done
DOTFILES_DIR="$old_dir"

phase_verify_system() { return 0; }
phase_install_packages() { track_install codex fail; return 1; }
phase_setup_configs() { return 0; }
output="$(run_installation 2>&1)" && fail "failed installation returned zero"
[[ "$output" != *'Dotfiles installation complete!'* ]] || fail "success banner printed after failure"
[[ "$output" == *'Installation Summary'* ]] || fail "failure omitted final summary"

printf 'install-failures: ok\n'
