#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH"
mkdir -p "$HOME/.local/bin"

cat > "$HOME/.local/bin/eget" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then echo 'eget 1.3.4'; exit 0; fi
[ "${EGET_TEST_FAIL:-0}" = 0 ] || exit 42
[ -d "$HOME/.local/bin" ] || exit 43
cat > "$HOME/.local/bin/demo" <<'BIN'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'demo new'
BIN
chmod +x "$HOME/.local/bin/demo"
EOF
chmod +x "$HOME/.local/bin/eget"
cat > "$HOME/.local/bin/demo" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'demo old'
EOF
chmod +x "$HOME/.local/bin/demo"
old_hash="$(sha256sum "$HOME/.local/bin/demo" | awk '{print $1}')"

source "$ROOT/lib/install.sh"
run_installer() { return 0; }
TOOL_METHOD=(['demo']=eget)
TOOL_BINARY=(['demo']=demo)
TOOL_TIER=(['demo']=bash)
TOOL_EGET_REPO=(['demo']=example/demo)
TOOL_PLATFORM=(['demo']=ubuntu)
TOOL_ARCHES=(['demo']='x86_64,aarch64')
TOOL_OWNERSHIP_ROOTS=(['demo']="$HOME/.local/bin")
tier_includes() { return 0; }
config="$TEST_ROOT/eget.toml"
cat > "$config" <<'EOF'
[global]
target = "~/.local/bin"
["example/demo"]
tag = "v1"
EOF
DOTFILES_DIR="$TEST_ROOT/repo"
mkdir -p "$DOTFILES_DIR"
cp "$config" "$DOTFILES_DIR/eget.toml"
FORCE_REINSTALL=true
ledger_record demo yes dotfiles installed old "$HOME/.local/bin/demo" test

export EGET_TEST_FAIL=1
if install_eget_tools >/dev/null 2>&1; then fail "failed staged download reported success"; fi
assert_eq "$(sha256sum "$HOME/.local/bin/demo" | awk '{print $1}')" "$old_hash" "failed update replaced working binary"
assert_eq "$("$HOME/.local/bin/demo" --version)" "demo old"
failed_line="$(ledger_line demo)"
[[ "$failed_line" == $'demo\tyes\tdotfiles\tupdate-failed\t'* ]] \
    || fail "failed update did not retain observed working component"

export EGET_TEST_FAIL=0
INSTALL_OK=() INSTALL_SKIP=() INSTALL_FAIL=()
FORCE_REINSTALL=false
install_eget_tools >/dev/null
assert_eq "$("$HOME/.local/bin/demo" --version)" "demo new"
[[ "$(ledger_line demo)" == *'pin=v1 sha256='* ]] || fail "staged artifact pin/hash not recorded"

# A bundled/private rg elsewhere on PATH is not a durable system installation.
# It must not suppress installation of the pinned dotfiles-owned ripgrep.
private_bin="$TEST_ROOT/.codex/private/bin"
mkdir -p "$private_bin"
cat > "$private_bin/rg" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'ripgrep private'
EOF
chmod +x "$private_bin/rg"
cat > "$HOME/.local/bin/eget" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then echo 'eget 1.3.4'; exit 0; fi
[ -d "$HOME/.local/bin" ] || exit 43
cat > "$HOME/.local/bin/rg" <<'BIN'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'ripgrep 15.2.0'
BIN
chmod +x "$HOME/.local/bin/rg"
EOF
chmod +x "$HOME/.local/bin/eget"
PATH="$private_bin:$HOME/.local/bin:$TEST_SYSTEM_PATH"
TOOL_METHOD=(['ripgrep']=eget)
TOOL_BINARY=(['ripgrep']=rg)
TOOL_TIER=(['ripgrep']=bash)
TOOL_PLATFORM=(['ripgrep']=ubuntu)
TOOL_ARCHES=(['ripgrep']='x86_64,aarch64')
TOOL_OWNERSHIP_ROOTS=(['ripgrep']="$HOME/.local/bin")
TOOL_UPDATE_CONTRACT=(['ripgrep']=staged-release)
cat > "$DOTFILES_DIR/eget.toml" <<'EOF'
[global]
target = "~/.local/bin"
["BurntSushi/ripgrep"]
tag = "15.2.0"
EOF
INSTALL_OK=() INSTALL_SKIP=() INSTALL_FAIL=()
install_eget_tools >/dev/null
[[ -x "$HOME/.local/bin/rg" ]] || fail "private Codex rg suppressed managed ripgrep"
assert_eq "$("$HOME/.local/bin/rg" --version)" "ripgrep 15.2.0"
PATH="$private_bin:$HOME/.local/bin:$TEST_SYSTEM_PATH"
eval "$(tool_verify_command ripgrep)" || fail "managed ripgrep was hidden by private PATH entry"
INSTALL_OK=() INSTALL_SKIP=() INSTALL_FAIL=()
install_eget_tools >/dev/null
[[ "$(ledger_line ripgrep)" == $'ripgrep\tyes\tdotfiles\tinstalled\t'* ]] \
    || fail "managed ripgrep ownership was not retained"

# Multi-line version output (eza/ShellCheck) must still match the pin and avoid
# an unnecessary download.
cat > "$HOME/.local/bin/eza" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then
    echo 'eza - A modern replacement for ls'
    echo 'v0.23.4 [+git]'
fi
EOF
chmod +x "$HOME/.local/bin/eza"
cat > "$HOME/.local/bin/eget" <<EOF
#!/bin/sh
if [ "\${1:-}" = --version ]; then echo 'eget 1.3.4'; exit 0; fi
touch "$TEST_ROOT/unnecessary-download"
exit 42
EOF
chmod +x "$HOME/.local/bin/eget"
PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH"
TOOL_METHOD=(['eza']=eget)
TOOL_BINARY=(['eza']=eza)
TOOL_TIER=(['eza']=bash)
TOOL_PLATFORM=(['eza']=ubuntu)
TOOL_ARCHES=(['eza']='x86_64,aarch64')
TOOL_OWNERSHIP_ROOTS=(['eza']="$HOME/.local/bin")
TOOL_UPDATE_CONTRACT=(['eza']=staged-release)
cat > "$DOTFILES_DIR/eget.toml" <<'EOF'
[global]
target = "~/.local/bin"
["eza-community/eza"]
tag = "v0.23.4"
EOF
INSTALL_OK=() INSTALL_SKIP=() INSTALL_FAIL=()
install_eget_tools >/dev/null
[[ ! -e "$TEST_ROOT/unnecessary-download" ]] || fail "multi-line pinned version triggered a download"

mkdir -p "$HOME/.local/demo/bin" "$TEST_ROOT/bad-tree"
printf '#!/bin/sh\necho old-tree\n' > "$HOME/.local/demo/bin/demo"
chmod +x "$HOME/.local/demo/bin/demo"
before_tree="$(sha256sum "$HOME/.local/demo/bin/demo" | awk '{print $1}')"
if atomic_replace_tree demo "$TEST_ROOT/bad-tree" "$HOME/.local/demo" bin/demo >/dev/null 2>&1; then
    fail "invalid staged tree was accepted"
fi
assert_eq "$(sha256sum "$HOME/.local/demo/bin/demo" | awk '{print $1}')" "$before_tree" "invalid tree replaced working install"

printf 'eget-staging: ok\n'
