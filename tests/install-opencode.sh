#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export PATH="$HOME/.local/bin:$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
mkdir -p "$HOME/.opencode/bin" "$HOME/.local/bin" "$XDG_CONFIG_HOME/opencode"
cat > "$HOME/.opencode/bin/opencode" <<'EOF'
#!/bin/sh
echo 1.18.33
EOF
chmod +x "$HOME/.opencode/bin/opencode"
ln -s "$HOME/.opencode/bin/opencode" "$HOME/.local/bin/opencode"
printf '{"autoupdate":true,"provider":{"mine":{}}}\n' > "$XDG_CONFIG_HOME/opencode/opencode.json"
installer="$TEST_ROOT/vendor.sh"
cat > "$installer" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = --no-modify-path ]
cat > "$HOME/.opencode/bin/opencode" <<'BIN'
#!/bin/sh
case "$1" in
--version) echo 'opencode v2.0.22' ;;
service) exit 0 ;;
esac
BIN
chmod +x "$HOME/.opencode/bin/opencode"
EOF
export DOTFILES_OPENCODE_INSTALLER_SCRIPT="$installer"
"$ROOT/installers/install-opencode.sh" >/dev/null
[[ "$(opencode --version)" == 'opencode v2.0.22' ]] || fail 'owned V1 was not upgraded'
python3 -c 'import json,os; d=json.load(open(os.path.join(os.environ["XDG_CONFIG_HOME"],"opencode/opencode.json"))); assert d["update"]=="notify" and "autoupdate" not in d and d["provider"]=={"mine":{}}'
rc=0
"$ROOT/installers/install-opencode.sh" >/dev/null || rc=$?
[[ "$rc" == 2 ]] || fail 'V2 rerun should skip download'
cp "$XDG_CONFIG_HOME/opencode/opencode.json" "$TEST_ROOT/before.json"
cat > "$installer" <<'EOF'
#!/bin/sh
printf '#!/bin/sh\necho broken\n' > "$HOME/.opencode/bin/opencode"
exit 1
EOF
rc=0
"$ROOT/installers/install-opencode.sh" --force >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 && "$(opencode --version)" == 'opencode v2.0.22' ]] || fail 'failed update did not restore the binary'
cmp "$XDG_CONFIG_HOME/opencode/opencode.json" "$TEST_ROOT/before.json" || fail 'failed update changed config'
# Verification failure also restores an executable which merely reports V1.
cat > "$installer" <<'EOF'
#!/bin/sh
printf '#!/bin/sh\necho 1.18.34\n' > "$HOME/.opencode/bin/opencode"
EOF
rc=0
"$ROOT/installers/install-opencode.sh" --force >/dev/null 2>&1 || rc=$?
[[ "$rc" == 1 && "$(opencode --version)" == 'opencode v2.0.22' ]] || fail 'wrong major was accepted'
mkdir -p "$TEST_ROOT/external"
printf '#!/bin/sh\necho 1.18.33\n' > "$TEST_ROOT/external/opencode"
chmod +x "$TEST_ROOT/external/opencode"
rc=0
PATH="$TEST_ROOT/external:$PATH" "$ROOT/installers/install-opencode.sh" --force >/dev/null 2>&1 || rc=$?
[[ "$rc" == 2 ]] || fail 'external installation was shadowed'
cmp "$XDG_CONFIG_HOME/opencode/opencode.json" "$TEST_ROOT/before.json" || fail 'external config changed'
printf 'install-opencode: ok\n'
