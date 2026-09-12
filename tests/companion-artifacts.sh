#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
mkdir -p "$HOME/.local/bin" "$TEST_ROOT/repo"
export PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH"
source "$ROOT/lib/install.sh"
DOTFILES_DIR="$TEST_ROOT/repo"
cp "$ROOT/eget.toml" "$DOTFILES_DIR/eget.toml"
run_installer() { return 0; }
TOOL_METHOD=(['uv']=eget)
tier_includes() { return 0; }
cat > "$HOME/.local/bin/eget" <<'EOF'
#!/bin/bash
[[ "$1" == --all ]] || exit 71
for name in uv uvx; do
    [[ "$name" != uvx || "${OMIT_COMPANION:-0}" != 1 ]] || continue
    printf '#!/bin/sh\necho "%s 0.10.0"\n' "$name" > "$HOME/.local/bin/$name"
    chmod +x "$HOME/.local/bin/$name"
done
EOF
chmod +x "$HOME/.local/bin/eget"
install_eget_tools >/dev/null
"$HOME/.local/bin/uvx" --version >/dev/null || fail "companion missing after install"
eval "$(tool_verify_command uv)" || fail "complete component verification"
[[ "$(tool_uninstall_paths uv)" == *"/uvx"* ]] || fail "companion not included in removal"
rm "$HOME/.local/bin/uvx"
if eval "$(tool_verify_command uv)"; then fail "verification missed companion loss"; fi
install_eget_tools >/dev/null
[[ -x "$HOME/.local/bin/uvx" ]] || fail "pinned primary prevented companion repair"
export OMIT_COMPANION=1
FORCE_REINSTALL=true
before="$(sha256sum "$HOME/.local/bin/uv")"
if install_eget_tools >/dev/null 2>&1; then fail "incomplete release accepted"; fi
assert_eq "$(sha256sum "$HOME/.local/bin/uv")" "$before" "incomplete release changed primary"
printf 'companion-artifacts: ok\n'
