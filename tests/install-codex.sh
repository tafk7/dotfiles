#!/bin/bash
# Deterministic ownership tests for installers/install-codex.sh. The test uses
# isolated HOME directories and a local stand-in for OpenAI's installer; it
# never reads or writes the invoking user's ~/.codex runtime.
set -euo pipefail
# Installer hooks must never reach the invoking user's tmux server.
unset TMUX TMUX_PANE

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
# Keep the test isolated from a Codex installed in the invoking user's PATH.
SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
trap 'rm -rf "$TEST_ROOT"' EXIT

STUB_INSTALLER="$TEST_ROOT/official-install.sh"
TEST_STATE="$TEST_ROOT/state"
mkdir -p "$TEST_STATE"
export TEST_STATE

cat > "$STUB_INSTALLER" <<'INSTALLER'
#!/bin/sh
set -eu

printf '%s\t%s\n' "${CODEX_NON_INTERACTIVE:-}" "${PROFILE:-}" > "$TEST_STATE/environment"

count_file="$TEST_STATE/count"
count=0
if [ -f "$count_file" ]; then
    count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"

if [ -e "$HOME/.local/bin/codex" ] || [ -L "$HOME/.local/bin/codex" ]; then
    preexisting=yes
else
    preexisting=no
fi
printf '%s\t%s\n' "$count" "$preexisting" >> "$TEST_STATE/observations"

release="$HOME/.codex/packages/standalone/releases/test-$count"
mkdir -p "$release/bin" "$HOME/.local/bin"
cat > "$release/bin/codex" <<CODEX
#!/bin/sh
case "\${1:-}" in
    --version) printf '%s\\n' 'codex-cli test-$count' ;;
    plugin) exit 0 ;;
    *) exit 0 ;;
esac
CODEX
chmod +x "$release/bin/codex"
ln -sfn "$release" "$HOME/.codex/packages/standalone/current"
ln -sfn "$HOME/.codex/packages/standalone/current/bin/codex" \
    "$HOME/.local/bin/codex"
INSTALLER
chmod +x "$STUB_INSTALLER"

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

run_expect() {
    local expected="$1"
    shift
    local rc=0
    "$@" >/dev/null 2>&1 || rc=$?
    [[ "$rc" == "$expected" ]] \
        || fail "expected exit $expected, got $rc: $*"
}

use_home() {
    export HOME="$1"
    mkdir -p "$HOME"
    export XDG_CONFIG_HOME="$HOME/.config" XDG_STATE_HOME="$HOME/.local/state" XDG_CACHE_HOME="$HOME/.cache"
    export PATH="$HOME/.local/bin:$SYSTEM_PATH"
    export DOTFILES_DIR="$REPO_ROOT"
    export DOTFILES_CODEX_INSTALLER_SCRIPT="$STUB_INSTALLER"
}

# Codex's configure steps (settings, agent-badge), as setup runs them after
# the installer.
configure_codex() {
    bash -c 'source "$1/lib/install.sh" && configure_component codex' _ "$REPO_ROOT" >/dev/null 2>&1 \
        || fail "Codex's configure steps failed"
}

# Fresh install creates the official-style launcher; configuring provisions
# config.
use_home "$TEST_ROOT/home-fresh"
run_expect 0 "$REPO_ROOT/installers/install-codex.sh"
[[ -L "$HOME/.local/bin/codex" ]] || fail "fresh install did not create launcher symlink"
[[ ! -e "$HOME/.codex/config.toml" ]] || fail "the installer wrote configuration itself"
configure_codex
[[ -f "$HOME/.codex/config.toml" ]] || fail "configuring did not provision config"
grep -qx 'model_reasoning_effort = "high"' "$HOME/.codex/config.toml" \
    || fail "fresh config did not receive portable preferences"
[[ "$(cat "$TEST_STATE/count")" == 1 ]] || fail "fresh install invocation count"
[[ "$(cat "$TEST_STATE/environment")" == $'1\t/dev/null' ]] \
    || fail "official installer was not invoked noninteractively with profile writes disabled"

# An ordinary rerun puts enforced keys back, keeps a default the machine changed
# and other local state, and does not call upstream.
sed -i 's/model_reasoning_effort = "high"/model_reasoning_effort = "low"/; s/metrics_exporter = "none"/metrics_exporter = "otlp"/' \
    "$HOME/.codex/config.toml"
cat >>"$HOME/.codex/config.toml" <<'LOCAL_STATE'

[projects."/tmp/example"]
trust_level = "trusted"
LOCAL_STATE
run_expect 2 "$REPO_ROOT/installers/install-codex.sh"
[[ "$(cat "$TEST_STATE/count")" == 1 ]] || fail "ordinary rerun called installer"
configure_codex
grep -qx 'metrics_exporter = "none"' "$HOME/.codex/config.toml" \
    || fail "ordinary rerun did not put an enforced key back"
grep -qx 'model_reasoning_effort = "low"' "$HOME/.codex/config.toml" \
    || fail "ordinary rerun reset a default the machine changed"
grep -qx '\[projects\."/tmp/example"\]' "$HOME/.codex/config.toml" \
    || fail "ordinary rerun discarded local Codex state"
python3 -c 'import pathlib, tomllib; tomllib.loads(pathlib.Path("'$HOME'/.codex/config.toml").read_text())' \
    || fail "ordinary rerun produced invalid TOML"
[[ "$(grep -cx '\[tui.keymap.editor\]' "$HOME/.codex/config.toml")" == 1 ]] \
    || fail "ordinary rerun duplicated tui.keymap.editor"
[[ "$(grep -cx '\[tui.keymap.chat\]' "$HOME/.codex/config.toml")" == 1 ]] \
    || fail "ordinary rerun duplicated tui.keymap.chat"
# --force invokes repair/update while leaving the launcher present for the
# upstream installer to replace atomically.
run_expect 0 "$REPO_ROOT/installers/install-codex.sh" --force
[[ "$(cat "$TEST_STATE/count")" == 2 ]] || fail "forced update invocation count"
[[ "$(tail -n 1 "$TEST_STATE/observations")" == $'2\tyes' ]] \
    || fail "forced update removed launcher before invoking installer"

# A binary managed elsewhere on PATH is respected, even under --force.
use_home "$TEST_ROOT/home-external"
external_bin="$TEST_ROOT/external-bin"
mkdir -p "$external_bin"
cat > "$external_bin/codex" <<'EXTERNAL'
#!/bin/sh
case "${1:-}" in
    --version) echo 'codex-cli external' ;;
    plugin) exit 0 ;;
    *) exit 0 ;;
esac
EXTERNAL
chmod +x "$external_bin/codex"
export PATH="$external_bin:$SYSTEM_PATH"
run_expect 2 "$REPO_ROOT/installers/install-codex.sh" --force
[[ "$(cat "$TEST_STATE/count")" == 2 ]] || fail "external install was shadowed"
[[ ! -e "$HOME/.local/bin/codex" ]] || fail "external install created a shadow launcher"
# An external Codex still gets its settings.
configure_codex
grep -qx 'model_reasoning_effort = "high"' "$HOME/.codex/config.toml" \
    || fail "an external Codex did not get its portable settings"

printf 'Codex installer ownership tests passed.\n'
