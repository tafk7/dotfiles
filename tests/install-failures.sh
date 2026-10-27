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
fake_command "$HOME/.local/share/claude/versions/2" true
ln -sf "$HOME/.local/share/claude/versions/2" "$HOME/.local/bin/claude"
ledger_record claude yes dotfiles installed 1 "$HOME/.local/share/claude/versions/1" test
INSTALL_FAIL=()
PATH="$HOME/.local/bin:$PATH" track_install claude skip
IFS=$'\t' read -r _ _ owner status _ path _ _ <<< "$(ledger_line claude)"
assert_eq "$owner/$status" dotfiles/installed "self-updated claude lost ownership"
assert_eq "$path" "$HOME/.local/share/claude/versions/2" "self-updated claude path not refreshed"

# Phases run as `phase || failed=true`, which disables errexit inside them, so
# every fallible step needs its own status check.
(
    sources="$TEST_ROOT/apt-sources"; keys="$TEST_ROOT/apt-keys"
    mkdir -p "$sources" "$keys"
    printf 'VERSION_CODENAME=noble\n' > "$TEST_ROOT/os-release"
    export DOTFILES_APT_SOURCES_DIR="$sources" DOTFILES_APT_KEYRINGS_DIR="$keys" DOTFILES_OS_RELEASE="$TEST_ROOT/os-release"
    safe_apt_get() { return 0; }
    update_packages() { return 0; }
    download_https() { printf 'key\n' > "$2"; }
    gpg() {
        case "$*" in
            *--show-keys*) printf 'fpr:::::::::9DC858229FC7DD38854AE2D88D81803C0EBFCD88:\n' ;;
            *--dearmor*) printf 'keyring\n' > "${@: -2:1}" ;;
        esac
    }
    dpkg() { printf 'amd64\n'; }
    failing=""
    safe_sudo() {
        # Only tee reads stdin; draining it for any other command would block.
        [[ "$1" != tee ]] || cat >/dev/null
        [[ "$1" != "$failing" ]]
    }
    failing="chmod"
    if ensure_docker_repo >/dev/null 2>&1; then fail "Docker keyring permission failure was ignored"; fi
    : > "$keys/docker.gpg"
    failing="tee"
    if ensure_docker_repo >/dev/null 2>&1; then fail "Docker source list write failure was ignored"; fi
)
(
    is_wsl() { return 0; }
    mkdir -p "$HOME/.ssh" && : > "$HOME/.ssh/use-windows-agent"
    printf '#!/bin/sh\n' > "$TEST_ROOT/bin/wsl2-ssh-agent"; chmod +x "$TEST_ROOT/bin/wsl2-ssh-agent"
    PATH="$TEST_ROOT/bin:$PATH"
    systemctl() { [[ "$*" != "--user daemon-reload" ]]; }
    if setup_wsl_ssh_agent >/dev/null 2>&1; then fail "systemd user reload failure was ignored"; fi
)
(
    record_install_path() { return 1; }
    if write_dotfiles_env >/dev/null 2>&1; then fail "install path write failure was ignored"; fi
)

printf 'install-failures: ok\n'
