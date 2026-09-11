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
mkdir -p "$HOME/.local/bin"
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

export EGET_TEST_FAIL=1
if install_eget_tools >/dev/null 2>&1; then fail "failed staged download reported success"; fi
assert_eq "$(sha256sum "$HOME/.local/bin/demo" | awk '{print $1}')" "$old_hash" "failed update replaced working binary"
assert_eq "$("$HOME/.local/bin/demo" --version)" "demo old"
failed_line="$(ledger_line demo)"
[[ "$failed_line" == $'demo\tyes\tdotfiles\tupdate-failed\t'* ]] \
    || fail "failed update did not retain observed working component"

export EGET_TEST_FAIL=0
INSTALL_OK=() INSTALL_SKIP=() INSTALL_FAIL=()
install_eget_tools >/dev/null
assert_eq "$("$HOME/.local/bin/demo" --version)" "demo new"

mkdir -p "$HOME/.local/demo/bin" "$TEST_ROOT/bad-tree"
printf '#!/bin/sh\necho old-tree\n' > "$HOME/.local/demo/bin/demo"
chmod +x "$HOME/.local/demo/bin/demo"
before_tree="$(sha256sum "$HOME/.local/demo/bin/demo" | awk '{print $1}')"
if atomic_replace_tree demo "$TEST_ROOT/bad-tree" "$HOME/.local/demo" bin/demo >/dev/null 2>&1; then
    fail "invalid staged tree was accepted"
fi
assert_eq "$(sha256sum "$HOME/.local/demo/bin/demo" | awk '{print $1}')" "$before_tree" "invalid tree replaced working install"

printf 'eget-staging: ok\n'
