#!/bin/bash
# Installer-method tools must keep dotfiles ownership when the installer's
# outcome is recorded before ~/.local/bin is on PATH (a fresh machine).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export PATH="$TEST_SYSTEM_PATH"

# Source before ~/.local/bin exists, as setup.sh does on a fresh machine:
# lib/runtime.sh only adds ~/.local/bin to PATH if the directory is present.
source "$ROOT/lib/install.sh"

mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/eget" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'eget version 1.3.4'
EOF
chmod +x "$HOME/.local/bin/eget"
if command -v eget >/dev/null 2>&1; then fail "fixture leaked eget onto PATH"; fi

ledger_field() {
    local field="$1" line
    line="$(ledger_line eget)"
    IFS=$'\t' read -r -a fields <<< "$line"
    printf '%s\n' "${fields[$field]}"
}

# install-eget.sh records ownership through atomic_replace_binary, then
# run_installer reports the outcome. The report must not discard ownership.
ledger_record eget yes dotfiles installed 'eget version 1.3.4' "$HOME/.local/bin/eget" staged-release
INSTALL_OK=() INSTALL_SKIP=() INSTALL_FAIL=()
track_install eget ok
assert_eq "$(ledger_field 2)" dotfiles "installer outcome ownership on a fresh PATH"
assert_eq "$(ledger_field 5)" "$HOME/.local/bin/eget" "installer outcome path on a fresh PATH"

# A later up-to-date run (installer exit 2) keeps the claim.
track_install eget skip
assert_eq "$(ledger_field 2)" dotfiles "up-to-date rerun ownership"
assert_eq "$(ledger_field 3)" installed "up-to-date rerun status"

# Uninstall resolves the managed binary.
assert_eq "$(tool_uninstall_paths eget)" "$HOME/.local/bin/eget" "eget uninstall path"

printf 'eget-ownership: ok\n'
