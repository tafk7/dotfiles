#!/bin/bash
# NVM, the pinned Node release and its bundled npm, rustup with the pinned
# default toolchain, and the pinned AWS CLI download.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
unset NVM_DIR CARGO_HOME RUSTUP_HOME RUSTUP_TOOLCHAIN
export DOTFILES_TEST_ARCH=x86_64
export PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH"
source "$ROOT/lib/install.sh"
mkdir -p "$TEST_ROOT/bin"

# --- NVM: installed once, never damaged by a failed update, and only from the
# locked install.sh.
nvm_installer="$TEST_ROOT/nvm-install.sh"
cat > "$nvm_installer" <<'EOF'
#!/bin/sh
set -eu
mkdir -p "$NVM_DIR"
cp "$NVM_FIXTURE" "$NVM_DIR/nvm.sh"
EOF
chmod +x "$nvm_installer"
# The fake nvm installs the fixture Node release with its bundled npm, whose
# npm can be upgraded independently, and records what it was asked.
export NVM_FIXTURE="$TEST_ROOT/nvm.sh" NODE_FIXTURE="$TEST_ROOT/node" NVM_LOG="$TEST_ROOT/nvm.log"
cat > "$NVM_FIXTURE" <<'EOF'
nvm() {
    printf '%s\n' "$*" >> "$NVM_LOG"
    case "$1" in
        install)
            local dir="$NVM_DIR/versions/node/v$2"
            mkdir -p "$dir/bin" "$dir/lib/node_modules/npm"
            cp "$NODE_FIXTURE" "$dir/bin/node"
            printf '{\n  "name": "npm",\n  "version": "%s"\n}\n' "${BUNDLED_NPM:-11.19.1}" > "$dir/lib/node_modules/npm/package.json"
            cp "$NPM_FIXTURE" "$dir/bin/npm"
            ;;
        alias) mkdir -p "$NVM_DIR/alias"; printf '%s\n' "$3" > "$NVM_DIR/alias/$2" ;;
    esac
}
EOF
export NPM_FIXTURE="$TEST_ROOT/npm"
cat > "$NPM_FIXTURE" <<'EOF'
#!/bin/sh
echo "npm $*" >> "$NVM_LOG"
for arg; do case "$arg" in npm@*) version="${arg#npm@}" ;; esac; done
printf '{\n  "version": "%s"\n}\n' "$version" > "$(dirname "$0")/../lib/node_modules/npm/package.json"
EOF
printf '#!/bin/sh\necho v24.22.1\n' > "$NODE_FIXTURE"
chmod +x "$NODE_FIXTURE" "$NPM_FIXTURE"

DOTFILES_NVM_INSTALLER_SCRIPT="$nvm_installer" "$ROOT/installers/install-nvm.sh" >/dev/null
[[ -s "$HOME/.nvm/nvm.sh" && ! -e "$HOME/.nvm/versions" ]] || fail "NVM install (without Node)"
rc=0; DOTFILES_NVM_INSTALLER_SCRIPT="$nvm_installer" "$ROOT/installers/install-nvm.sh" >/dev/null || rc=$?
assert_eq "$rc" 2 "an installed NVM"

cp "$HOME/.nvm/nvm.sh" "$TEST_ROOT/nvm.sh.good"
printf '# working nvm\n' >> "$HOME/.nvm/nvm.sh"
before="$(sha256sum "$HOME/.nvm/nvm.sh" | awk '{print $1}')"
bad="$TEST_ROOT/bad-installer"; printf '#!/bin/sh\nexit 42\n' > "$bad"; chmod +x "$bad"
if DOTFILES_NVM_INSTALLER_SCRIPT="$bad" "$ROOT/installers/install-nvm.sh" --force >/dev/null 2>&1; then
    fail "failed forced NVM update returned success"
fi
[[ "$(sha256sum "$HOME/.nvm/nvm.sh" | awk '{print $1}')" == "$before" ]] || fail "failed NVM update damaged working install"

# A downloaded NVM installer that is not the locked install.sh never runs.
printf '#!/bin/bash\nwhile (( $# )); do [[ "$1" == --output ]] && dest="$2"; shift; done\nprintf "#!/bin/sh\\ntouch %s/nvm-ran\\n" > "$dest"\n' \
    "$TEST_ROOT" > "$TEST_ROOT/bin/curl"
chmod +x "$TEST_ROOT/bin/curl"
if PATH="$TEST_ROOT/bin:$PATH" "$ROOT/installers/install-nvm.sh" --force >"$TEST_ROOT/nvm-out" 2>&1; then
    fail "an NVM installer off the lock was accepted"
fi
[[ ! -e "$TEST_ROOT/nvm-ran" && "$(<"$TEST_ROOT/nvm-out")" == *"Checksum mismatch"* ]] || fail "an NVM installer off the lock ran: $(<"$TEST_ROOT/nvm-out")"
rm "$TEST_ROOT/bin/curl"
cp "$TEST_ROOT/nvm.sh.good" "$HOME/.nvm/nvm.sh"

# --- Node: the locked release becomes NVM's default, with its bundled npm.
awk -F '\t' -v OFS='\t' -v d="sha256:$(sha256sum "$NODE_FIXTURE" | awk '{print $1}')" \
    '$1 == "node" && $2 == "x86_64" { $8 = d } 1' "$ROOT/versions.lock" > "$TEST_ROOT/versions.lock"
export DOTFILES_VERSIONS_LOCK="$TEST_ROOT/versions.lock"
node_dir="$HOME/.nvm/versions/node/v24.22.1"
node_installer() { local rc=0; "$ROOT/installers/install-node.sh" > "$TEST_ROOT/node-out" 2>&1 || rc=$?; NODE_RC=$rc; }

# Under an NVM dotfiles does not own, Node is left alone.
node_installer
assert_eq "$NODE_RC" 2 "Node under an unowned NVM: $(<"$TEST_ROOT/node-out")"
[[ ! -e "$NVM_LOG" ]] || fail "Node was installed under an unowned NVM"

ledger_record nvm yes dotfiles installed - "$HOME/.nvm" test
mkdir -p "$HOME/.nvm/versions/node/v22.0.0/bin" "$HOME/.nvm/versions/node/v22.0.0/lib/node_modules/left-pad"
cp "$NODE_FIXTURE" "$HOME/.nvm/versions/node/v22.0.0/bin/node"
ln -s "$HOME/.nvm/versions/node/v22.0.0" "$HOME/.nvm/default"
node_installer
assert_eq "$NODE_RC" 0 "Node install: $(<"$TEST_ROOT/node-out")"
[[ "$(head -n1 "$NVM_LOG")" == "install 24.22.1" ]] || fail "nvm was not asked for the pinned release: $(<"$NVM_LOG")"
assert_eq "$(<"$HOME/.nvm/alias/default")" 24.22.1 "NVM's default alias"
assert_eq "$(readlink -f "$HOME/.nvm/default")" "$node_dir" "the default link"
[[ "$(<"$TEST_ROOT/node-out")" == *"Global packages stay with v22.0.0: left-pad"* ]] \
    || fail "the previous default's global packages were not reported: $(<"$TEST_ROOT/node-out")"
assert_eq "$(node_default_dir)" "$node_dir" "node_default_dir"
node_installer
assert_eq "$NODE_RC" 2 "a current Node"

# An independently upgraded npm is moved back to the bundled version.
printf '{\n  "version": "12.0.2"\n}\n' > "$node_dir/lib/node_modules/npm/package.json"
: > "$NVM_LOG"
node_installer
assert_eq "$NODE_RC" 0 "npm restore: $(<"$TEST_ROOT/node-out")"
grep -Fxq "npm install -g --no-fund --no-audit npm@11.19.1" "$NVM_LOG" || fail "npm was not restored: $(<"$NVM_LOG")"
grep -q '"version": "11.19.1"' "$node_dir/lib/node_modules/npm/package.json" || fail "npm is not the bundled version"

# A release directory that is not the locked build is refused.
printf '#!/bin/sh\necho tampered\n' > "$node_dir/bin/node"
node_installer
assert_eq "$NODE_RC" 1 "a Node off the lock"
[[ "$(<"$TEST_ROOT/node-out")" == *"is not the locked build"* ]] || fail "a Node off the lock was not reported: $(<"$TEST_ROOT/node-out")"
export DOTFILES_VERSIONS_LOCK="$ROOT/versions.lock"

# --- Rust: rustup's default toolchain is the pin, asked from a neutral
# directory without overrides; a rustup dotfiles does not own keeps its own.
export RUSTUP_LOG="$TEST_ROOT/rustup.log"
cat > "$TEST_ROOT/rustup" <<'EOF'
#!/bin/sh
printf '%s|%s|%s|%s\n' "$PWD" "${RUSTUP_TOOLCHAIN-unset}" "${RUSTUP_AUTO_INSTALL-unset}" "$*" >> "$RUSTUP_LOG"
case "$1" in
    --version) echo "rustup 1.29.1" ;;
    default)
        if [ -n "${2:-}" ]; then echo "$2" > "$RUSTUP_HOME/default"
        else echo "$(cat "$RUSTUP_HOME/default")-x86_64-unknown-linux-gnu (default)"; fi ;;
esac
EOF
rust_installer="$TEST_ROOT/rust-install.sh"
cat > "$rust_installer" <<'EOF'
#!/bin/sh
set -eu
echo "rustup-init $*" >> "$RUSTUP_LOG"
mkdir -p "$CARGO_HOME/bin" "$RUSTUP_HOME"
cp "$(dirname "$0")/rustup" "$CARGO_HOME/bin/rustup"
for name in rustc cargo; do printf '#!/bin/sh\necho %s-test\n' "$name" > "$CARGO_HOME/bin/$name"; done
chmod +x "$CARGO_HOME/bin/"*
while [ $# -gt 0 ]; do [ "$1" = --default-toolchain ] && echo "$2" > "$RUSTUP_HOME/default"; shift; done
EOF
chmod +x "$rust_installer"
rust_pin="$(versions_field rust want any)"
DOTFILES_RUSTUP_INSTALLER_SCRIPT="$rust_installer" "$ROOT/installers/install-rust.sh" >/dev/null
grep -q "^rustup-init -y --no-modify-path --default-toolchain $rust_pin$" "$RUSTUP_LOG" || fail "rustup-init without the pinned toolchain: $(<"$RUSTUP_LOG")"
[[ -x "$HOME/.cargo/bin/rustc" ]] || fail "Rust fixture install"

echo stable > "$HOME/.rustup/default"
ledger_record rust yes unknown present - "$HOME/.cargo/bin/rustc" test
rc=0; RUSTUP_TOOLCHAIN=nightly "$ROOT/installers/install-rust.sh" >/dev/null || rc=$?
assert_eq "$rc/$(<"$HOME/.rustup/default")" 2/stable "an unowned rustup kept its default"

ledger_record rust yes dotfiles installed - "$HOME/.cargo/bin/rustc" test
: > "$RUSTUP_LOG"
(cd "$TEST_ROOT" && RUSTUP_TOOLCHAIN=nightly "$ROOT/installers/install-rust.sh" >/dev/null) || fail "moving the default toolchain failed"
assert_eq "$(<"$HOME/.rustup/default")" "$rust_pin" "rustup's default toolchain"
grep -Fxq "/|unset|0|toolchain install $rust_pin --no-self-update" "$RUSTUP_LOG" \
    || fail "the toolchain was not installed from / without overrides: $(<"$RUSTUP_LOG")"
[[ "$(grep -c '|nightly|' "$RUSTUP_LOG" || true)" == 0 ]] || fail "RUSTUP_TOOLCHAIN reached rustup: $(<"$RUSTUP_LOG")"
rc=0; "$ROOT/installers/install-rust.sh" >/dev/null || rc=$?
assert_eq "$rc" 2 "a pinned default toolchain"

# --- AWS CLI: a download that is not the locked archive never reaches the
# signature check or the installer.
printf '#!/bin/sh\necho "sudo $*" >> "%s/sudo.log"\n' "$TEST_ROOT" > "$TEST_ROOT/bin/sudo"
printf '#!/bin/bash\nwhile (( $# )); do [[ "$1" == --output ]] && dest="$2"; shift; done\necho tampered > "$dest"\n' > "$TEST_ROOT/bin/curl"
chmod +x "$TEST_ROOT/bin/sudo" "$TEST_ROOT/bin/curl"
rc=0; PATH="$TEST_ROOT/bin:$PATH" "$ROOT/installers/install-aws-cli.sh" > "$TEST_ROOT/aws-out" 2>&1 || rc=$?
assert_eq "$rc" 1 "an AWS CLI archive off the lock"
[[ "$(<"$TEST_ROOT/aws-out")" == *"Checksum mismatch"* ]] || fail "the AWS CLI checksum was not checked: $(<"$TEST_ROOT/aws-out")"
grep -q "aws/install" "$TEST_ROOT/sudo.log" && fail "the AWS CLI installer ran on an archive off the lock"

printf 'install-toolchains: ok\n'
