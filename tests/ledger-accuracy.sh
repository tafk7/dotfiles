#!/bin/bash
# The ledger records what is actually there: cleaned version strings, the
# tool's own path rather than a snap launcher, package-manager ownership for
# present APT tools, and zsh as installed only when this run installed it.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
source "$ROOT/setup.sh"

mkdir -p "$HOME/.local/bin" "$TEST_ROOT/usr/lib/snapd" "$TEST_ROOT/usr/bin" "$TEST_ROOT/snap/bin"
# dpkg-query answers from a fixture list of installed packages.
: > "$TEST_ROOT/installed-packages"
{
    printf '#!/bin/sh\n'
    printf 'for package do :; done\n'
    printf 'grep -qx "$package" "%s" || exit 1\n' "$TEST_ROOT/installed-packages"
    printf 'case "$*" in\n'
    printf '    *Status-Status*) printf installed ;;\n'
    printf '    *Version*) printf "1.2.3-1ubuntu1\\n" ;;\n'
    printf 'esac\n'
} > "$TEST_ROOT/bin/dpkg-query"
chmod +x "$TEST_ROOT/bin/dpkg-query"
export PATH="$TEST_ROOT/bin:$TEST_ROOT/snap/bin:$TEST_ROOT/usr/bin:$HOME/.local/bin:$TEST_SYSTEM_PATH"

field() {
    local -a fields
    IFS=$'\t' read -r -a fields <<< "$(ledger_line "$1")"
    printf '%s' "${fields[$2]}"
}

# btop colors its version; eza leads with a banner line.
printf '#!/bin/sh\nprintf "\\033[1;32mbtop version:\\033[0m 1.4.5\\r\\n"\n' > "$HOME/.local/bin/btop"
printf '#!/bin/sh\nprintf "eza - A modern replacement for ls\\nv0.20.0 [+git]\\nhttps://example.invalid\\n"\n' \
    > "$HOME/.local/bin/eza"
chmod +x "$HOME/.local/bin/btop" "$HOME/.local/bin/eza"
track_install btop ok
track_install eza ok
assert_eq "$(field btop 4)" "btop version: 1.4.5" "btop version escapes"
assert_eq "$(field eza 4)" "v0.20.0 [+git]" "eza version banner"

# A snap command resolves through /usr/bin/snap to snapd; record the command.
printf '#!/bin/sh\n[ "$(basename "$0")" = gcloud ] && echo "Google Cloud SDK 500.0.0"\n' \
    > "$TEST_ROOT/usr/lib/snapd/snapd"
chmod +x "$TEST_ROOT/usr/lib/snapd/snapd"
ln -s ../lib/snapd/snapd "$TEST_ROOT/usr/bin/snap"
ln -s "$TEST_ROOT/usr/bin/snap" "$TEST_ROOT/snap/bin/gcloud"
track_install gcloud skip
assert_eq "$(field gcloud 5)" "$TEST_ROOT/snap/bin/gcloud" "gcloud snap path"
assert_eq "$(field gcloud 4)" "Google Cloud SDK 500.0.0" "gcloud snap version"
assert_eq "$(field gcloud 2)/$(field gcloud 3)" "external/present" "snap gcloud ownership"

# rustc is the rustup proxy under another name; record rustc and its version.
mkdir -p "$HOME/.cargo/bin"
printf '#!/bin/sh\ncase "$(basename "$0")" in rustc) echo "rustc 1.92.0 (abc 2026-01-01)" ;; *) echo "rustup 1.29.1" ;; esac\n' \
    > "$HOME/.cargo/bin/rustup"
chmod +x "$HOME/.cargo/bin/rustup"
ln -s rustup "$HOME/.cargo/bin/rustc"
PATH="$HOME/.cargo/bin:$PATH" track_install rust ok
assert_eq "$(field rust 5)" "$HOME/.cargo/bin/rustc" "rustc path through the rustup proxy"
assert_eq "$(field rust 4)" "rustc 1.92.0 (abc 2026-01-01)" "rustc version through the rustup proxy"

# An APT tool found already installed keeps package-manager ownership.
printf '#!/bin/sh\necho 1.2.3\n' > "$TEST_ROOT/usr/bin/tailscale"
chmod +x "$TEST_ROOT/usr/bin/tailscale"
printf 'tailscale\n' >> "$TEST_ROOT/installed-packages"
track_install tailscale skip
assert_eq "$(field tailscale 2)/$(field tailscale 3)" "package-manager/installed" "skipped APT tool ownership"
assert_eq "$(field tailscale 4)" "1.2.3-1ubuntu1" "APT tool version from dpkg"

# zsh is reported installed only when the dev tier's APT step installed it.
install_apt() { printf 'zsh\n' >> "$TEST_ROOT/installed-packages"; }
configure_locale() { :; }
run_installer() { :; }
printf '#!/bin/sh\necho "zsh 5.9"\n' > "$TEST_ROOT/usr/bin/zsh"
chmod +x "$TEST_ROOT/usr/bin/zsh"
INSTALL_OK=() INSTALL_SKIP=()
install_dev_packages >/dev/null
[[ " ${INSTALL_OK[*]} " == *" zsh "* ]] || fail "newly installed zsh not reported installed"
INSTALL_OK=() INSTALL_SKIP=()
install_dev_packages >/dev/null
[[ " ${INSTALL_SKIP[*]} " == *" zsh "* && " ${INSTALL_OK[*]} " != *" zsh "* ]] \
    || fail "present zsh reported as installed by this run"

printf 'ledger-accuracy: ok\n'
