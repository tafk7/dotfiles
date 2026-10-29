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

# dotfiles upgrade (and bin/ai-update, its older name) updates an installed AI
# CLI through setup and leaves the machine profile alone: Claude is installed
# here but not in the profile, and an update must not make dotfiles manage it.
(
    unset DOTFILES_OPERATION
    export NO_COLOR=1 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
    profile="$XDG_STATE_HOME/dotfiles/profile"
    updates="$TEST_ROOT/claude-updates"
    printf '#!/bin/sh\necho run >> "%s"\nexec sh "%s"\n' "$updates" "$claude_installer" > "$TEST_ROOT/claude-update.sh"
    export DOTFILES_CLAUDE_INSTALLER_SCRIPT="$TEST_ROOT/claude-update.sh"
    "$ROOT/setup.sh" --config --no-hooks --no-theme >/dev/null 2>&1 || fail "fixture setup failed"
    before="$(<"$profile")"
    runs() { if [[ -f "$updates" ]]; then wc -l < "$updates"; else echo 0; fi; }

    "$ROOT/bin/dotfiles" upgrade claude > "$TEST_ROOT/upgrade.log" 2>&1 \
        || { cat "$TEST_ROOT/upgrade.log" >&2; fail "dotfiles upgrade claude failed"; }
    assert_eq "$(runs)" 1 "the updater did not run once"
    grep -Fq 'Machine profile left as it is' "$TEST_ROOT/upgrade.log" || fail "the one-off was not said"
    assert_eq "$(<"$profile")" "$before" "dotfiles upgrade changed the profile"
    "$ROOT/bin/ai-update" claude >/dev/null 2>&1 || fail "ai-update claude failed"
    assert_eq "$(runs)" 2 "ai-update did not run the updater"
    assert_eq "$(<"$profile")" "$before" "ai-update changed the profile"

    "$ROOT/bin/dotfiles" upgrade --dry-run claude >/dev/null 2>&1 || fail "the dry run failed"
    assert_eq "$(runs)" 2 "a dry run ran the updater"

    # A CLI that is not installed is refused, not installed unmanaged; pi is
    # one of the CLIs ai-update takes now.
    rc=0; out="$("$ROOT/bin/dotfiles" upgrade codex 2>&1)" || rc=$?
    assert_eq "$rc" 1 "upgrading a missing CLI"
    [[ "$out" == *"codex is not installed"*"dotfiles profile --add codex"* ]] || fail "missing CLI: $out"
    [[ ! -e "$HOME/.local/bin/codex" ]] || fail "upgrade installed codex"
    rc=0; "$ROOT/bin/ai-update" pi >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" 1 "ai-update pi (not installed)"
    rc=0; "$ROOT/bin/dotfiles" upgrade bat >/dev/null 2>&1 || rc=$?
    assert_eq "$rc" 64 "upgrade accepted a component that is not an AI CLI"
    assert_eq "$(<"$profile")" "$before" "a refused upgrade changed the profile"

    # Without a profile, none is created.
    rm "$profile"
    "$ROOT/bin/dotfiles" upgrade claude >/dev/null 2>&1 || fail "upgrade without a profile failed"
    [[ ! -e "$profile" ]] || fail "upgrade created a profile: $(<"$profile")"

    # The setup run ai-update used to make is what added the CLI.
    printf '%s\n' "$before" > "$profile"
    "$ROOT/setup.sh" --claude --only claude --upgrade >/dev/null 2>&1 || fail "setup --upgrade failed"
    grep -q $'^ai\tclaude$' "$profile" || fail "the contrast run did not add claude: $(<"$profile")"
)

opencode_installer="$TEST_ROOT/opencode-install.sh"
cat > "$opencode_installer" <<'EOF'
#!/bin/sh
set -eu
[ "$1" = --no-modify-path ] || exit 1
mkdir -p "$HOME/.opencode/bin"
cat > "$HOME/.opencode/bin/opencode" <<'BIN'
#!/bin/sh
[ "${1:-}" = --version ] && echo 'opencode v2.0.22'
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
printf '%s\n' "npm warn deprecated node-domexception@1.0.0: Use your platform's native DOMException instead" >&2
printf '%s\n' "npm warn retained-warning: diagnostic must remain visible" >&2
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
pi_output="$("$ROOT/installers/install-pi.sh" 2>&1)"
[[ "$pi_output" != *'node-domexception@1.0.0'* ]] || fail "known Pi transitive deprecation warning leaked"
[[ "$pi_output" == *'retained-warning'* ]] || fail "Pi installer hid an unrelated npm warning"
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

# The rc safety net reports only edits made during the install, not
# uncommitted local changes that were already there.
rc_repo="$TEST_ROOT/rc-repo"
mkdir -p "$rc_repo/entry"
printf 'export KEEP=1\n' > "$rc_repo/entry/bash.sh"
git -C "$rc_repo" init -q && git -C "$rc_repo" add . \
    && git -C "$rc_repo" -c user.name=t -c user.email=t@example.invalid commit -qm fixture
printf '# local edit\n' >> "$rc_repo/entry/bash.sh"
rc_output="$(DOTFILES_DIR="$rc_repo" bash -c '
    source "$0/lib/install.sh"
    before="$(rc_snapshot)"; warn_if_rc_changed "$before"; echo "[quiet]"
    echo "export PATH=\$HOME/vendor:\$PATH" >> "$DOTFILES_DIR/entry/bash.sh"
    warn_if_rc_changed "$before"' "$ROOT" 2>&1)"
[[ "$rc_output" == *'[quiet]'* && "$rc_output" != *'modified during install'*'[quiet]'* ]] || fail "rc net blamed a local edit"
[[ "$rc_output" == *'[quiet]'*'modified during install'* ]] || fail "rc net missed an installer edit"

printf 'install-ai: ok\n'
