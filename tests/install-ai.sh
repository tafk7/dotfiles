#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export PATH="$HOME/.local/bin:$TEST_ROOT/bin:$TEST_SYSTEM_PATH"
export DOTFILES_AGENT_BADGE_ENABLED=0

claude_installer="$TEST_ROOT/claude-install.sh"
cat > "$claude_installer" <<'EOF'
#!/bin/sh
set -eu
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/claude" <<'BIN'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'claude test'
BIN
chmod +x "$HOME/.local/bin/claude"
EOF
chmod +x "$claude_installer"
DOTFILES_CLAUDE_INSTALLER_SCRIPT="$claude_installer" "$ROOT/installers/install-claude.sh" >/dev/null
"$HOME/.local/bin/claude" --version >/dev/null || fail "Claude installer output"

opencode_installer="$TEST_ROOT/opencode-install.sh"
cat > "$opencode_installer" <<'EOF'
#!/bin/sh
set -eu
mkdir -p "$HOME/.opencode/bin"
cat > "$HOME/.opencode/bin/opencode" <<'BIN'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'opencode test'
BIN
chmod +x "$HOME/.opencode/bin/opencode"
EOF
chmod +x "$opencode_installer"
DOTFILES_OPENCODE_INSTALLER_SCRIPT="$opencode_installer" "$ROOT/installers/install-opencode.sh" >/dev/null
[[ -L "$HOME/.local/bin/opencode" ]] || fail "opencode launcher not linked"

cat > "$TEST_ROOT/bin/node" <<'EOF'
#!/bin/sh
echo v22.19.0
EOF
cat > "$TEST_ROOT/bin/npm" <<'EOF'
#!/bin/sh
set -eu
prefix=""
while [ "$#" -gt 0 ]; do
    [ "$1" = --prefix ] && { prefix="$2"; shift 2; continue; }
    shift
done
mkdir -p "$prefix/bin"
cat > "$prefix/bin/pi" <<'BIN'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'pi test'
BIN
chmod +x "$prefix/bin/pi"
EOF
chmod +x "$TEST_ROOT/bin/node" "$TEST_ROOT/bin/npm"
"$ROOT/installers/install-pi.sh" >/dev/null
"$HOME/.local/bin/pi" --version >/dev/null || fail "Pi installer output"

# Every installer must preserve an externally managed binary rather than
# creating a shadow copy in ~/.local/bin.
external="$TEST_ROOT/external"
mkdir -p "$external"
cat > "$external/claude" <<'EOF'
#!/bin/sh
[ "${1:-}" = --version ] && echo external
EOF
chmod +x "$external/claude"
fresh="$TEST_ROOT/external-home"; mkdir -p "$fresh"
rc=0
HOME="$fresh" PATH="$external:$TEST_SYSTEM_PATH" DOTFILES_DIR="$ROOT" \
    DOTFILES_AGENT_BADGE_ENABLED=0 "$ROOT/installers/install-claude.sh" --force >/dev/null 2>&1 || rc=$?
[[ $rc -eq 2 && ! -e "$fresh/.local/bin/claude" ]] || fail "Claude external ownership"

printf 'install-ai: ok\n'
