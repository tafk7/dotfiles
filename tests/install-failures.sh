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
for name in claude codex opencode pi sbx tailscale azure-cli gcloud aws-cli; do
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

python3 - "$TEST_ROOT/unsafe.tar" <<'PY'
import io, sys, tarfile
with tarfile.open(sys.argv[1], "w") as archive:
    info = tarfile.TarInfo("../escape")
    data = b"bad"
    info.size = len(data)
    archive.addfile(info, io.BytesIO(data))
PY
validate_tar_archive "$TEST_ROOT/unsafe.tar" >/dev/null 2>&1 \
    && fail "unsafe archive path was accepted"

# A skipped self-updating CLI keeps ownership after moving within its roots;
# the ledger then records the new path.
mkdir -p "$HOME/.local/share/claude/versions" "$HOME/.local/bin"
cp /usr/bin/true "$HOME/.local/share/claude/versions/2"
ln -sf "$HOME/.local/share/claude/versions/2" "$HOME/.local/bin/claude"
ledger_record claude yes dotfiles installed 1 "$HOME/.local/share/claude/versions/1" test
INSTALL_FAIL=()
PATH="$HOME/.local/bin:$PATH" track_install claude skip
IFS=$'\t' read -r _ _ owner status _ path _ _ <<< "$(ledger_line claude)"
assert_eq "$owner/$status" dotfiles/installed "self-updated claude lost ownership"
assert_eq "$path" "$HOME/.local/share/claude/versions/2" "self-updated claude path not refreshed"

printf 'install-failures: ok\n'
