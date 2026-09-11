#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
unset NVM_DIR CARGO_HOME RUSTUP_HOME
export PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH"

nvm_installer="$TEST_ROOT/nvm-install.sh"
cat > "$nvm_installer" <<'EOF'
#!/bin/sh
set -eu
mkdir -p "$NVM_DIR"
cat > "$NVM_DIR/nvm.sh" <<'NVM'
nvm() {
    case "$1" in
        install) mkdir -p "$NVM_DIR/versions/node/v22.19.0/bin"; printf '#!/bin/sh\necho v22.19.0\n' > "$NVM_DIR/versions/node/v22.19.0/bin/node"; printf '#!/bin/sh\necho 10.0.0\n' > "$NVM_DIR/versions/node/v22.19.0/bin/npm"; chmod +x "$NVM_DIR/versions/node/v22.19.0/bin/node" "$NVM_DIR/versions/node/v22.19.0/bin/npm" ;;
        use) PATH="$NVM_DIR/versions/node/v22.19.0/bin:$PATH"; export PATH ;;
        alias) : ;;
        --version) echo 0.40.4 ;;
    esac
}
NVM
EOF
chmod +x "$nvm_installer"
DOTFILES_NVM_INSTALLER_SCRIPT="$nvm_installer" "$ROOT/installers/install-nvm.sh" >/dev/null
[[ -s "$HOME/.nvm/nvm.sh" && -L "$HOME/.nvm/default" ]] || fail "NVM fixture install"

printf 'working nvm\n' >> "$HOME/.nvm/nvm.sh"
before="$(sha256sum "$HOME/.nvm/nvm.sh" | awk '{print $1}')"
bad="$TEST_ROOT/bad-installer"; printf '#!/bin/sh\nexit 42\n' > "$bad"; chmod +x "$bad"
if DOTFILES_NVM_INSTALLER_SCRIPT="$bad" "$ROOT/installers/install-nvm.sh" --force >/dev/null 2>&1; then
    fail "failed forced NVM update returned success"
fi
[[ "$(sha256sum "$HOME/.nvm/nvm.sh" | awk '{print $1}')" == "$before" ]] || fail "failed NVM update damaged working install"

rust_installer="$TEST_ROOT/rust-install.sh"
cat > "$rust_installer" <<'EOF'
#!/bin/sh
set -eu
mkdir -p "$CARGO_HOME/bin"
for name in rustup rustc cargo; do
    printf '#!/bin/sh\necho %s-test\n' "$name" > "$CARGO_HOME/bin/$name"
    chmod +x "$CARGO_HOME/bin/$name"
done
EOF
chmod +x "$rust_installer"
DOTFILES_RUSTUP_INSTALLER_SCRIPT="$rust_installer" "$ROOT/installers/install-rust.sh" >/dev/null
[[ -x "$HOME/.cargo/bin/rustc" ]] || fail "Rust fixture install"

printf 'install-toolchains: ok\n'
